extends Node2D
class_name WeaponController

## ════════════════════════════════════════════════════════════════════
##  WeaponController — ProyectSurvivor
##
##  NUEVAS FUNCIONALIDADES:
##    · Burst fire: burst_count disparos separados burst_interval frames.
##    · Patrones: SINGLE (clásico), RADIAL (360°), SPIRAL (ángulo rotatorio),
##      ALTERNATING (barriles alternantes).
##    · Construcción de extra_config para ProjectileManager DOD con todos
##      los nuevos parámetros (homing, rebote, cadena, split, etc.)
## ════════════════════════════════════════════════════════════════════

var equipped_weapons  : Array[WeaponData] = []
var cooldowns         : Dictionary = {}   # weapon → frames restantes
var current_spreads   : Dictionary = {}   # weapon → spread dinámico actual
var muzzle_timers     : Dictionary = {}   # weapon → frames del fogonazo

# ── Estado de burst ──────────────────────────────────────────────────
# weapon → { "rem": int, "timer": float }
var _burst_data       : Dictionary = {}

# ── Estado de patrones ───────────────────────────────────────────────
var _spiral_angles    : Dictionary = {}   # weapon → float (grados acumulados)
var _alt_sides        : Dictionary = {}   # weapon → int (0 ó 1)

# ── Láser hitscan ────────────────────────────────────────────────────
var active_laser_weapon : WeaponData = null
var laser_end_point     : Vector2    = Vector2.ZERO
var laser_timer         : float      = 0.0

@onready var player = get_parent().get_parent()

# ════════════════════════════════════════════════════════════════════
#  GESTIÓN DE ARMAS
# ════════════════════════════════════════════════════════════════════

func add_weapon(weapon_data: WeaponData) -> void:
	var w := weapon_data.duplicate()
	equipped_weapons.append(w)
	cooldowns[w]      = 0.0
	current_spreads[w] = w.base_spread
	muzzle_timers[w]  = 0.0
	_burst_data[w]    = {"rem": 0, "timer": 0.0}
	_spiral_angles[w] = 0.0
	_alt_sides[w]     = 0

# ════════════════════════════════════════════════════════════════════
#  PROCESO — cooldowns, burst timers, spread recovery, laser fade
# ════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not player: return

	var frames       : float = delta * 60.0
	var cd_mult      : float = player.global_cooldown_mult if "global_cooldown_mult" in player else 1.0

	# Fade del láser hitscan
	if laser_timer > 0.0:
		laser_timer -= frames
		if laser_timer <= 0.0:
			active_laser_weapon = null

	queue_redraw()

	for weapon in equipped_weapons:
		# ── Cooldown principal ────────────────────────────────────
		if cooldowns[weapon] > 0.0:
			cooldowns[weapon] -= frames / cd_mult

		# ── Burst: avanzar timer y disparar siguiente bala ────────
		var bd : Dictionary = _burst_data[weapon]
		if bd["rem"] > 0:
			bd["timer"] -= frames
			if bd["timer"] <= 0.0:
				_fire_one_shot(weapon)
				bd["rem"] -= 1
				bd["timer"] = weapon.burst_interval if bd["rem"] > 0 else 0.0

		# ── Recuperación de spread (Rifle de Asalto) ──────────────
		if current_spreads[weapon] > weapon.base_spread:
			current_spreads[weapon] -= weapon.spread_recovery * frames
			if current_spreads[weapon] < weapon.base_spread:
				current_spreads[weapon] = weapon.base_spread

		# ── Fogonazo (Sniper) ─────────────────────────────────────
		if muzzle_timers[weapon] > 0.0:
			muzzle_timers[weapon] -= frames

# ════════════════════════════════════════════════════════════════════
#  API PÚBLICA — intento de disparo desde player.gd
# ════════════════════════════════════════════════════════════════════

func attempt_shoot(weapon_index: int) -> bool:
	if equipped_weapons.is_empty() or weapon_index >= equipped_weapons.size():
		return false
	var weapon := equipped_weapons[weapon_index]

	if cooldowns[weapon] > 0.0:
		return false

	_apply_physics(weapon)

	match weapon.type:
		WeaponData.WeaponType.HITSCAN_LASER:
			_fire_laser(weapon)
		WeaponData.WeaponType.PROJECTILE:
			# Primer disparo del burst (o disparo único si burst_count=1)
			_fire_one_shot(weapon)
			# Encolar disparos restantes del burst
			if weapon.burst_count > 1:
				_burst_data[weapon]["rem"]   = weapon.burst_count - 1
				_burst_data[weapon]["timer"] = weapon.burst_interval

	cooldowns[weapon] = weapon.cooldown
	return true

# ════════════════════════════════════════════════════════════════════
#  DESPACHO DE PATRÓN — llamado por attempt_shoot y el burst timer
# ════════════════════════════════════════════════════════════════════

func _fire_one_shot(weapon: WeaponData) -> void:
	match weapon.fire_pattern:
		WeaponData.FirePattern.SINGLE:
			_fire_pellets(weapon, player.aim_angle, Vector2.ZERO)

		WeaponData.FirePattern.RADIAL:
			_fire_radial(weapon)

		WeaponData.FirePattern.SPIRAL:
			# El ángulo base rota cada disparo, independientemente del aim
			var angle_deg : float = _spiral_angles[weapon]
			_spiral_angles[weapon] = fmod(angle_deg + weapon.spiral_angle_step, 360.0)
			_fire_pellets(weapon, deg_to_rad(angle_deg), Vector2.ZERO)

		WeaponData.FirePattern.ALTERNATING:
			# Alterna el punto de spawn entre dos barriles laterales
			var side   : int    = _alt_sides[weapon]
			_alt_sides[weapon]  = 1 - side
			var perp   : Vector2 = Vector2(-sin(player.aim_angle), cos(player.aim_angle))
			var offset : Vector2 = perp * weapon.alternating_offset * (1.0 if side == 0 else -1.0)
			_fire_pellets(weapon, player.aim_angle, offset)

# ════════════════════════════════════════════════════════════════════
#  DISPARO DE PELLETS — patrón SINGLE / SPIRAL / ALTERNATING
# ════════════════════════════════════════════════════════════════════

func _fire_pellets(weapon: WeaponData, base_angle: float,
				   spawn_offset: Vector2) -> void:
	var pm := GameManager.projectile_manager
	if not is_instance_valid(pm):
		push_warning("WeaponController: ProjectileManager no disponible.")
		return

	var dmg_mult   : float = player.global_damage_mult    if "global_damage_mult"    in player else 1.0
	var extra_pen  : int   = player.extra_penetration     if "extra_penetration"     in player else 0
	var speed_mult : float = player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0
	var size_mult  : float = player.projectile_size_mult  if "projectile_size_mult"  in player else 1.0
	var kb_mult    : float = player.knockback_mult        if "knockback_mult"        in player else 1.0

	var final_dmg : int   = maxi(1, int(weapon.damage * dmg_mult))
	var final_pen : int   = weapon.penetration + extra_pen
	var final_rad : float = maxf(3.0, weapon.projectile_radius * size_mult)

	# Spread dinámico (Rifle de Asalto)
	var dyn_spread : float = current_spreads[weapon]
	current_spreads[weapon] = minf(current_spreads[weapon] + weapon.spread_per_shot,
								   weapon.max_spread)

	if weapon.has_muzzle_flash:
		muzzle_timers[weapon] = 8.0

	var spawn_pos : Vector2 = player.global_position \
		+ Vector2(cos(player.aim_angle), sin(player.aim_angle)) * 15.0 \
		+ spawn_offset

	var extra := _build_extra_config(weapon)

	for i in range(weapon.pellets):
		var angle : float = base_angle

		# Dispersión de escopeta
		if weapon.pellets > 1:
			var factor : float = float(i) / float(weapon.pellets - 1)
			angle += (factor - 0.5) * weapon.shotgun_spread + randf_range(-0.05, 0.05)

		# Spread dinámico
		if dyn_spread > 0.0:
			angle += randf_range(-dyn_spread, dyn_spread)

		# Velocidad (puede variar en escopeta)
		var spd : float = weapon.projectile_speed
		if weapon.projectile_speed_max > weapon.projectile_speed:
			spd = randf_range(weapon.projectile_speed, weapon.projectile_speed_max)

		var vel : Vector2 = Vector2(cos(angle), sin(angle)) * spd * speed_mult * 60.0

		pm.spawn(spawn_pos, vel, final_dmg, final_pen, weapon.max_lifetime,
				 final_rad, kb_mult, weapon.inner_radius_mult,
				 weapon.projectile_color, weapon.use_swept_collision,
				 weapon.fade_out, weapon.fade_multiplier,
				 weapon.flicker_fire_effect, extra)

# ════════════════════════════════════════════════════════════════════
#  DISPARO RADIAL — patrón RADIAL (360°)
# ════════════════════════════════════════════════════════════════════

func _fire_radial(weapon: WeaponData) -> void:
	var pm := GameManager.projectile_manager
	if not is_instance_valid(pm): return

	var dmg_mult   : float = player.global_damage_mult    if "global_damage_mult"    in player else 1.0
	var extra_pen  : int   = player.extra_penetration     if "extra_penetration"     in player else 0
	var speed_mult : float = player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0
	var size_mult  : float = player.projectile_size_mult  if "projectile_size_mult"  in player else 1.0
	var kb_mult    : float = player.knockback_mult        if "knockback_mult"        in player else 1.0

	var final_dmg  : int   = maxi(1, int(weapon.damage * dmg_mult))
	var final_pen  : int   = weapon.penetration + extra_pen
	var final_rad  : float = maxf(3.0, weapon.projectile_radius * size_mult)
	var spawn_pos  : Vector2 = player.global_position
	var n          : int   = maxi(1, weapon.radial_count)
	var step       : float = TAU / float(n)
	var extra      := _build_extra_config(weapon)

	for i in range(n):
		var angle : float = player.aim_angle + step * float(i)
		var spd   : float = weapon.projectile_speed
		if weapon.projectile_speed_max > weapon.projectile_speed:
			spd = randf_range(weapon.projectile_speed, weapon.projectile_speed_max)
		var vel : Vector2 = Vector2(cos(angle), sin(angle)) * spd * speed_mult * 60.0
		pm.spawn(spawn_pos, vel, final_dmg, final_pen, weapon.max_lifetime,
				 final_rad, kb_mult, weapon.inner_radius_mult,
				 weapon.projectile_color, weapon.use_swept_collision,
				 weapon.fade_out, weapon.fade_multiplier,
				 weapon.flicker_fire_effect, extra)

# ════════════════════════════════════════════════════════════════════
#  CONSTRUCCIÓN DEL EXTRA CONFIG — empaqueta todas las propiedades nuevas
##  para enviarlas al ProjectileManager mediante el dict `extra`.
##  homing_strength: weapon_data en grados/s → aquí convertimos a rad/s.
# ════════════════════════════════════════════════════════════════════

func _build_extra_config(weapon: WeaponData) -> Dictionary:
	return {
		# Homing
		"homing":           weapon.is_homing,
		"homing_strength":  deg_to_rad(weapon.homing_strength),   # rad/s
		"homing_delay":     weapon.homing_delay_frames,
		"homing_range":     weapon.homing_range,
		# Rebote
		"bounces":          weapon.bounces,
		# Cadena
		"chain_count":      weapon.chain_count,
		"chain_range":      weapon.chain_range,
		"chain_damage_mult":weapon.chain_damage_mult,
		# Explosión
		"explodes":         weapon.explodes_on_impact,
		"explosion_radius": weapon.explosion_radius,
		"explosion_damage_mult": weapon.explosion_damage_mult,
		# Split
		"splits":           weapon.splits_on_death,
		"split_count":      weapon.split_count,
		"split_spread":     weapon.split_spread,
		# Movimiento
		"acceleration":     weapon.acceleration,          # px/s²
		"max_speed_cap":    weapon.max_speed_cap,         # px/s
		"sine_amplitude":   weapon.sine_amplitude,        # px
		"sine_frequency":   weapon.sine_frequency,        # Hz
		"size_growth":      weapon.size_growth_rate,      # px/s
		# Estado (framework — sin efecto hasta extensión de EnemyManager)
		"burn_dps":         weapon.burn_dps,
		"burn_duration":    weapon.burn_duration,
		"slow_factor":      weapon.slow_factor,
		"slow_duration":    weapon.slow_duration,
		# Hit set inicial vacío (los spawns de cadena lo prerellenan)
		"initial_hits":     {},
	}

# ════════════════════════════════════════════════════════════════════
#  LÁSER HITSCAN — sin cambios respecto a la versión original
# ════════════════════════════════════════════════════════════════════

func _fire_laser(weapon: WeaponData) -> void:
	active_laser_weapon = weapon
	laser_timer         = 10.0

	var max_len : float = 1500.0 * (player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0)
	var start   = player.global_position
	laser_end_point = start + Vector2(cos(player.aim_angle), sin(player.aim_angle)) * max_len

	var dmg : float = weapon.damage \
		* (player.global_damage_mult if "global_damage_mult" in player else 1.0) \
		* get_physics_process_delta_time()

	var hits = GameManager.enemy_manager.get_enemies_near_proxy(
		start + (laser_end_point - start) * 0.5, max_len)

	for idx in hits:
		var e_pos = GameManager.enemy_manager.positions[idx]
		if _closest_point_on_segment(start, laser_end_point, e_pos).distance_squared_to(e_pos) <= 400.0:
			GameManager.enemy_manager.damage_enemy(idx, dmg, Vector2.ZERO, 0.0)

# ════════════════════════════════════════════════════════════════════
#  DRAW — miras, fogonazos, láser (sin cambios respecto al original)
# ════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if not is_instance_valid(player): return
	var angle       : float   = player.aim_angle
	var origin_local: Vector2 = to_local(player.global_position) \
		if player.get_parent() != self else Vector2.ZERO

	# Láser hitscan
	if active_laser_weapon and laser_timer > 0.0:
		var prog      : float   = laser_timer / 10.0
		var end_pos   : Vector2 = to_local(laser_end_point) \
			+ Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		var sm        : float   = player.projectile_size_mult if "projectile_size_mult" in player else 1.0
		var width     : float   = maxf(2.0, active_laser_weapon.laser_thickness * sm * prog)
		var mc        : Color   = active_laser_weapon.projectile_color
		mc.a = clampf(prog * 0.7, 0.0, 1.0)
		draw_line(origin_local, end_pos, mc, width)
		draw_line(origin_local, end_pos, Color(1, 1, 1, clampf(prog, 0, 1)), maxf(1.0, width * 0.5))

	# Miras y fogonazos del arma activa
	if player.weapons.size() > 0:
		var cw = player.weapons[player.current_weapon_index]

		if cw.has_laser_sight:
			var end_w  = player.global_position + Vector2(cos(angle), sin(angle)) * 950.0
			var el    := to_local(end_w)
			draw_line(origin_local, el, Color(0.39, 0.0, 0.0, 0.85), 3)
			draw_line(origin_local, el, Color(0.78, 0.06, 0.06, 0.9), 2)
			draw_line(origin_local, el, Color(1.0,  0.16, 0.16, 0.95), 1)
			draw_arc(el, 6.0, 0.0, TAU, 32, Color(0.71, 0.0, 0.0, 0.9), 1)
			draw_circle(el, 3.0, Color(1.0, 0.31, 0.31, 1.0))

		if cw.has_muzzle_flash and muzzle_timers[cw] > 0.0:
			var prog  : float = muzzle_timers[cw] / 8.0
			var fw    = player.global_position + Vector2(cos(angle), sin(angle)) * (500.0 * prog)
			draw_line(origin_local, to_local(fw), Color(1.0, 0.12, 0.71, prog * 0.8), 2)
			var fr : float = 14.0 * prog
			if fr > 1.0:
				var mw = player.global_position + Vector2(cos(angle), sin(angle)) * 28.0
				draw_circle(to_local(mw), fr, Color(1.0, 0.86, 1.0, prog * 0.86))

# ════════════════════════════════════════════════════════════════════
#  UTILIDADES
# ════════════════════════════════════════════════════════════════════

func _apply_physics(weapon: WeaponData) -> void:
	var angle : float = player.aim_angle
	player.velocity -= Vector2(cos(angle), sin(angle)) * weapon.kickback * 60.0
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("add_shake") and weapon.shake_amount > 0:
		cam.add_shake(weapon.shake_amount)

func _closest_point_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab : Vector2 = b - a
	var t  : float   = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return a + t * ab