extends Node2D
class_name WeaponController

var equipped_weapons: Array[WeaponData] = []
var cooldowns: Dictionary = {}
var current_spreads: Dictionary = {} # Para el Rifle de Asalto
var muzzle_timers: Dictionary = {}   # Para el Sniper

var active_laser_weapon: WeaponData = null
var laser_end_point: Vector2 = Vector2.ZERO
var laser_timer: float = 0.0 # ¡NUEVO! Temporizador visual del láser

@onready var player = get_parent().get_parent()

func add_weapon(weapon_data: WeaponData) -> void:
	var instanced_weapon = weapon_data.duplicate()
	equipped_weapons.append(instanced_weapon)
	cooldowns[instanced_weapon] = 0.0
	current_spreads[instanced_weapon] = instanced_weapon.base_spread
	muzzle_timers[instanced_weapon] = 0.0

func _physics_process(delta: float) -> void:
	if not player: return
	
	var frames: float = delta * 60.0
	var cooldown_mult = player.global_cooldown_mult if "global_cooldown_mult" in player else 1.0
	
	# Manejo del desvanecimiento del Láser
	if laser_timer > 0.0:
		laser_timer -= frames
		if laser_timer <= 0.0:
			active_laser_weapon = null
			
	queue_redraw() 
	
	for weapon in equipped_weapons:
		# Cooldowns
		if cooldowns[weapon] > 0.0:
			cooldowns[weapon] -= frames / cooldown_mult
			
		# Recuperación de Spread (Rifle de Asalto)
		if current_spreads[weapon] > weapon.base_spread:
			current_spreads[weapon] -= weapon.spread_recovery * frames
			if current_spreads[weapon] < weapon.base_spread:
				current_spreads[weapon] = weapon.base_spread
				
		# Animación de Fogonazo (Sniper)
		if muzzle_timers[weapon] > 0.0:
			muzzle_timers[weapon] -= frames

func attempt_shoot(weapon_index: int) -> bool:
	if equipped_weapons.is_empty() or weapon_index >= equipped_weapons.size(): return false
	var weapon = equipped_weapons[weapon_index]
	
	if cooldowns[weapon] <= 0.0:
		shoot_weapon(weapon)
		cooldowns[weapon] = weapon.cooldown
		return true
	return false

func shoot_weapon(weapon: WeaponData) -> void:
	_apply_physics(weapon)
	match weapon.type:
		WeaponData.WeaponType.PROJECTILE: _fire_projectiles(weapon)
		WeaponData.WeaponType.HITSCAN_LASER: _fire_laser(weapon)

func _fire_projectiles(weapon: WeaponData) -> void:
	if not weapon.projectile_scene: return
		
	var base_angle: float = player.aim_angle
	var dmg_mult: float = player.global_damage_mult if "global_damage_mult" in player else 1.0
	var final_dmg: int = int(weapon.damage * dmg_mult)
	var extra_pen: int = player.extra_penetration if "extra_penetration" in player else 0
	var speed_mult: float = player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0
	var size_mult: float = player.projectile_size_mult if "projectile_size_mult" in player else 1.0
	
	# Actualizar dispersión del arma actual al disparar
	var dyn_spread = current_spreads[weapon]
	current_spreads[weapon] = minf(current_spreads[weapon] + weapon.spread_per_shot, weapon.max_spread)
	
	if weapon.has_muzzle_flash: muzzle_timers[weapon] = 8.0
	
	for i in range(weapon.pellets):
		var angle: float = base_angle
		
		# Lógica Escopeta (Fija y uniforme)
		if weapon.pellets > 1:
			var factor: float = float(i) / float(weapon.pellets - 1)
			angle += ((factor - 0.5) * weapon.shotgun_spread) + randf_range(-0.05, 0.05)
			
		# Lógica Rifle de Asalto (Dinámica y aleatoria)
		if dyn_spread > 0.0:
			angle += randf_range(-dyn_spread, dyn_spread)
			
		var spawn_pos: Vector2 = player.global_position + Vector2(cos(base_angle), sin(base_angle)) * 15.0
		
		# Velocidad Aleatoria (Escopeta)
		var spd: float = weapon.projectile_speed
		if weapon.projectile_speed_max > weapon.projectile_speed:
			spd = randf_range(weapon.projectile_speed, weapon.projectile_speed_max)
			
		var final_radius = maxf(3.0, weapon.projectile_radius * size_mult)
		
		var proj = weapon.projectile_scene.instantiate()
		proj.global_position = spawn_pos
		proj.setup(angle, spd * speed_mult, final_dmg, weapon.penetration + extra_pen, weapon, final_radius)
		
		var pn = get_tree().get_first_node_in_group("projectiles")
		if pn: pn.add_child(proj)
		else: get_tree().current_scene.add_child(proj)

func _fire_laser(weapon: WeaponData) -> void:
	active_laser_weapon = weapon
	laser_timer = 10.0 # Restablecemos el tiempo de vida visual del láser (10 frames)
	
	var max_len: float = 1500.0 * (player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0)
	var start_pos = player.global_position
	laser_end_point = start_pos + Vector2(cos(player.aim_angle), sin(player.aim_angle)) * max_len
	
	var dmg_this_frame = weapon.damage * (player.global_damage_mult if "global_damage_mult" in player else 1.0) * get_physics_process_delta_time()
	var hits = GameManager.enemy_manager.get_enemies_near_proxy(start_pos + (laser_end_point-start_pos)/2.0, max_len)
	for idx in hits:
		var e_pos = GameManager.enemy_manager.positions[idx]
		if _closest_point_on_segment(start_pos, laser_end_point, e_pos).distance_squared_to(e_pos) <= 400.0:
			GameManager.enemy_manager.damage_enemy(idx, dmg_this_frame, Vector2.ZERO, 0.0)

func _draw() -> void:
	if not is_instance_valid(player): return
	var angle: float = player.aim_angle
	var origin_local: Vector2 = to_local(player.global_position) if player.get_parent() != self else Vector2.ZERO
	
	# 1. Dibujar Láser Hitscan (RESTAURADO)
	if active_laser_weapon and laser_timer > 0.0:
		var prog: float = laser_timer / 10.0 # Va de 1.0 a 0.0
		var end_pos = to_local(laser_end_point)
		
		# Tu efecto original de "vibración" de la punta del rayo
		end_pos += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		
		# CAMBIO AQUÍ: Llamamos a la variable directamente y aplicamos multiplicador de tamaño
		var size_mult: float = player.projectile_size_mult if "projectile_size_mult" in player else 1.0
		var base_thickness: float = active_laser_weapon.laser_thickness * size_mult
		
		# Usamos float (maxf) para un escalado de grosor perfecto
		var width: float = maxf(2.0, base_thickness * prog)
		
		var main_color = active_laser_weapon.projectile_color
		main_color.a = clampf(prog * 0.7, 0.0, 1.0)
		
		# Línea gruesa de color exterior
		draw_line(origin_local, end_pos, main_color, width)
		# Línea fina interior brillante
		draw_line(origin_local, end_pos, Color(1.0, 1.0, 1.0, clampf(prog, 0.0, 1.0)), maxf(1.0, width / 2.0))


	# 2. Dibujar Miras y Fogonazos del Sniper (si es el arma activa)
	if player.weapons.size() > 0:
		var current_w = player.weapons[player.current_weapon_index]
		if current_w.has_laser_sight:
			var world_end = player.global_position + Vector2(cos(angle), sin(angle)) * 950.0
			var end_local = to_local(world_end)
			draw_line(origin_local, end_local, Color(0.39, 0.0, 0.0, 0.85), 3)
			draw_line(origin_local, end_local, Color(0.78, 0.06, 0.06, 0.9), 2)
			draw_line(origin_local, end_local, Color(1.0, 0.16, 0.16, 0.95), 1)
			draw_arc(end_local, 6.0, 0.0, TAU, 32, Color(0.71, 0.0, 0.0, 0.9), 1)
			draw_circle(end_local, 3.0, Color(1.0, 0.31, 0.31, 1.0))
			
		if current_w.has_muzzle_flash and muzzle_timers[current_w] > 0.0:
			var prog: float = muzzle_timers[current_w] / 8.0
			var flash_world = player.global_position + Vector2(cos(angle), sin(angle)) * (500.0 * prog)
			draw_line(origin_local, to_local(flash_world), Color(1.0, 0.12, 0.71, prog * 0.8), 2)
			var flash_r: float = 14.0 * prog
			if flash_r > 1.0:
				var muz_w = player.global_position + Vector2(cos(angle), sin(angle)) * 28.0
				draw_circle(to_local(muz_w), flash_r, Color(1.0, 0.86, 1.0, prog * 0.86))

func _closest_point_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab = b - a
	var t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return a + t * ab

func _apply_physics(weapon: WeaponData) -> void:
	var angle: float = player.aim_angle
	player.velocity -= Vector2(cos(angle), sin(angle)) * weapon.kickback * 60.0
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_shake") and weapon.shake_amount > 0:
		camera.add_shake(weapon.shake_amount)
