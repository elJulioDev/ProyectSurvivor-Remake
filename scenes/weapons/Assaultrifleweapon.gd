## AssaultRifleWeapon.gd
## Rifle de Asalto — alta cadencia, dispersión acumulativa que se recupera.
## Tecla 3. Cooldown 8f, daño 20, speed 19.
class_name AssaultRifleWeapon
extends Node2D

# ── Stats base ──────────────────────────────────────────────────────────────
var cooldown: float        = 8.0
var current_cooldown: float = 0.0
var damage: float          = 20.0
var kickback: float        = 0.5
var shake_amount: float    = 2.0

# Dispersión acumulativa
var base_spread: float     = 0.05
var current_spread: float  = 0.05
var max_spread: float      = 0.35
var spread_per_shot: float = 0.04
var spread_recovery: float = 0.01   # por frame

var owner_player: Node     = null

# ── Actualización ───────────────────────────────────────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm

	# Recuperación de dispersión
	if current_spread > base_spread:
		current_spread -= spread_recovery * frames
		if current_spread < base_spread:
			current_spread = base_spread

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
	var base_angle:  float = owner_player.aim_angle
	var angle: float       = base_angle + randf_range(-current_spread, current_spread)

	var spawn_pos: Vector2 = owner_player.position \
		+ Vector2(cos(base_angle), sin(base_angle)) * 22.0

	var size_mult: float = owner_player.projectile_size_mult
	_spawn_projectile(spawn_pos, angle, 19.0 * speed_mult, final_dmg, 1 + extra_pen, 60, size_mult)

	# Acumular dispersión
	current_spread = min(current_spread + spread_per_shot, max_spread)
	return true

func _apply_physics() -> void:
	if owner_player == null:
		return
	var angle: float = owner_player.aim_angle
	
	# Añadimos la multiplicación por 60.0 para pasarlo a px/s
	owner_player.velocity -= Vector2(cos(angle), sin(angle)) * kickback * 60.0
	
	# Cámara shake (si el player expone el método)
	if owner_player.has_method("add_camera_shake"):
		owner_player.add_camera_shake(shake_amount)

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
	var p := _BulletNode.new()
	p.position     = pos
	p.velocity     = Vector2(cos(angle), sin(angle)) * speed * 60.0
	p.damage       = dmg
	p.penetration  = pen
	p.max_lifetime = lifetime
	p.radius       = max(3.0, 7.0 * sz_mult)

	var projectiles_node: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_node:
		projectiles_node.add_child(p)
	else:
		get_parent().add_child(p)


# ══ Bala de rifle ════════════════════════════════════════════════════════════
class _BulletNode:
	extends Node2D

	var velocity:     Vector2 = Vector2.ZERO
	var damage:       int     = 20
	var penetration:  int     = 1
	var lifetime:     float   = 0.0
	var max_lifetime: float   = 60.0
	var radius:       float   = 7.0
	var _enemies_hit: Array   = []

	func _ready() -> void:
		z_index = 1

	func _physics_process(delta: float) -> void:
		var frames: float = delta * 60.0
		position  += velocity * delta
		lifetime  += frames
		if lifetime >= max_lifetime:
			queue_free()
			return

		var enemies := get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if not enemy.has_method("take_damage"):
				continue
			if enemy in _enemies_hit:
				continue
			if position.distance_to(enemy.global_position) <= radius + 12.0:
				_enemies_hit.append(enemy)
				enemy.take_damage(damage, velocity.normalized())
				if enemy.has_method("apply_knockback"):
					enemy.apply_knockback(global_position, 8.0)
				penetration -= 1
				if penetration <= 0:
					queue_free()
					return

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var a: float = clamp(progress, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.9, 0.39, a))
		draw_circle(Vector2.ZERO, max(1.0, radius * 0.4), Color(1.0, 1.0, 0.9, a))