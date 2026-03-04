## SniperWeapon.gd
## Rifle de Caza — 110 daño, penetración 8, bala supersónica.
## Tecla 5. Cooldown 100f, speed 38, mira láser roja.
class_name SniperWeapon
extends Node2D

# ── Stats base ──────────────────────────────────────────────────────────────
var crosshair_type: int     = 3     # 3 = SNIPER (Mira de francotirador)
var cooldown: float         = 100.0
var current_cooldown: float = 0.0
var damage: float           = 110.0
var kickback: float         = 14.0
var shake_amount: float     = 9.0
var base_penetration: int   = 8
var muzzle_flash_timer: float = 0.0

var owner_player: Node      = null

# ── Actualización ───────────────────────────────────────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm
	if muzzle_flash_timer > 0.0:
		muzzle_flash_timer -= frames
		queue_redraw()

func _process(_delta: float) -> void:
	# Redibujar cada frame para la mira de puntería (siempre visible)
	queue_redraw()

# ── Disparo ─────────────────────────────────────────────────────────────────
func shoot() -> bool:
	if current_cooldown <= 0.0:
		if _activate():
			current_cooldown = cooldown
			_apply_physics()
			return true
	return false

func _activate() -> bool:
	if owner_player == null:
		return false

	var speed_mult:  float = owner_player.projectile_speed_mult
	var extra_pen:   int   = owner_player.extra_penetration
	var damage_mult: float = owner_player.global_damage_mult
	var final_dmg:   int   = int(damage * damage_mult)
	var angle:       float = owner_player.aim_angle
	var size_mult:   float = owner_player.projectile_size_mult

	var spawn_pos: Vector2 = owner_player.position \
		+ Vector2(cos(angle), sin(angle)) * 28.0

	_spawn_projectile(
		spawn_pos, angle,
		38.0 * speed_mult,
		final_dmg,
		base_penetration + extra_pen,
		220,
		size_mult
	)

	muzzle_flash_timer = 8.0
	queue_redraw()
	return true

func _apply_physics() -> void:
	if owner_player == null:
		return
	var angle: float = owner_player.aim_angle
	owner_player.velocity -= Vector2(cos(angle), sin(angle)) * kickback
	if owner_player.has_method("add_camera_shake"):
		owner_player.add_camera_shake(shake_amount)

# ── Render: mira + flash ────────────────────────────────────────────────────
func _draw() -> void:
	if owner_player == null:
		return

	# 1. Ocultar la mira si no es el arma equipada actualmente
	if owner_player.active_weapons.size() > 0:
		if owner_player.active_weapons[owner_player.current_weapon_index] != self:
			return

	var angle: float = owner_player.aim_angle
	var origin_local: Vector2 = Vector2.ZERO
	var scope_len: float = 950.0

	# 2. Corregir la rotación convirtiendo de espacio Global a Local
	var world_end: Vector2 = owner_player.global_position + Vector2(cos(angle), sin(angle)) * scope_len
	var end_local: Vector2 = to_local(world_end)

	# Mira láser roja (tres capas: sombra, media, brillante)
	draw_line(origin_local, end_local, Color(0.39, 0.0, 0.0, 0.85), 3)
	draw_line(origin_local, end_local, Color(0.78, 0.06, 0.06, 0.9), 2)
	draw_line(origin_local, end_local, Color(1.0, 0.16, 0.16, 0.95), 1)

	# Punto de mira en el extremo
	var tip: Vector2 = end_local
	draw_arc(tip, 6.0, 0.0, TAU, 32, Color(0.71, 0.0, 0.0, 0.9), 1)
	draw_circle(tip, 3.0, Color(1.0, 0.31, 0.31, 1.0))

	# Muzzle flash
	if muzzle_flash_timer > 0.0:
		var prog: float = muzzle_flash_timer / 8.0
		
		# Aplicamos to_local() también a los efectos visuales del flash
		var flash_world_end: Vector2 = owner_player.global_position + Vector2(cos(angle), sin(angle)) * (500.0 * prog)
		var flash_end: Vector2 = to_local(flash_world_end)
		
		draw_line(origin_local, flash_end, Color(1.0, 0.12, 0.71, prog * 0.8), 2)
		var flash_r: float = 14.0 * prog
		if flash_r > 1.0:
			var muz_world_pos: Vector2 = owner_player.global_position + Vector2(cos(angle), sin(angle)) * 28.0
			var muz_pos: Vector2 = to_local(muz_world_pos)
			draw_circle(muz_pos, flash_r, Color(1.0, 0.86, 1.0, prog * 0.86))

# ── Proyectil inline ────────────────────────────────────────────────────────
func _spawn_projectile(
		pos:      Vector2,
		angle:    float,
		speed:    float,
		dmg:      int,
		pen:      int,
		lifetime: float,
		sz_mult:  float
) -> void:
	var p := _SniperBullet.new()
	p.position     = pos
	p.velocity     = Vector2(cos(angle), sin(angle)) * speed * 60.0
	p.damage       = dmg
	p.penetration  = pen
	p.max_lifetime = lifetime
	p.radius       = max(3.0, 5.0 * sz_mult)

	var projectiles_node: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_node:
		projectiles_node.add_child(p)
	else:
		get_parent().add_child(p)


# ══ Bala de francotirador (swept collision) ══════════════════════════════════
class _SniperBullet:
	extends Node2D

	var velocity:     Vector2 = Vector2.ZERO
	var damage:       int     = 110
	var penetration:  int     = 8
	var lifetime:     float   = 0.0
	var max_lifetime: float   = 220.0
	var radius:       float   = 5.0
	var _enemies_hit: Array   = []
	var _prev_pos:    Vector2 = Vector2.ZERO

	func _ready() -> void:
		z_index = 1
		_prev_pos = position

	func _physics_process(delta: float) -> void:
		var frames: float = delta * 60.0
		_prev_pos  = position
		position  += velocity * delta
		lifetime  += frames
		if lifetime >= max_lifetime:
			queue_free()
			return

		_check_hit_swept()

	func _check_hit_swept() -> void:
		var enemies := get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if not enemy.has_method("take_damage"):
				continue
			if enemy in _enemies_hit:
				continue
			# Swept check: ¿el trayecto prev→current pasa por el enemigo?
			var dist_seg: float = _point_to_segment_dist(
				enemy.global_position, _prev_pos, position
			)
			if dist_seg <= radius + 14.0:
				_enemies_hit.append(enemy)
				enemy.take_damage(damage)
				if enemy.has_method("apply_knockback"):
					enemy.apply_knockback(global_position, 12.0)
				penetration -= 1
				if penetration <= 0:
					queue_free()
					return

	func _point_to_segment_dist(pt: Vector2, a: Vector2, b: Vector2) -> float:
		var ab: Vector2 = b - a
		var len_sq: float = ab.length_squared()
		if len_sq == 0.0:
			return pt.distance_to(a)
		var t: float = clamp((pt - a).dot(ab) / len_sq, 0.0, 1.0)
		return pt.distance_to(a + t * ab)

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var a: float = clamp(progress * 1.2, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.12, 0.71, a))
		draw_circle(Vector2.ZERO, max(1.0, radius * 0.5), Color(1.0, 0.9, 1.0, a))