## ShotgunWeapon.gd
## Escopeta — 8 perdigones, devastadora a corto rango.
## Tecla 2. Cooldown 50f, daño 18 por perdigón, retroceso fuerte.
class_name ShotgunWeapon
extends Node2D

# ── Stats base (en unidades de frames a 60fps) ─────────────────────────────
var cooldown: float       = 50.0
var current_cooldown: float = 0.0
var damage: float         = 18.0
var pellets: int          = 8
var spread: float         = 0.4     # radianes totales del abanico
var kickback: float       = 12.0
var shake_amount: float   = 8.0

var owner_player: Node    = null

# ── Actualización interna ───────────────────────────────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm

# ── Disparo (activo, llamado por player.attack()) ──────────────────────────
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

	for i in range(pellets):
		var factor: float = float(i) / float(pellets - 1) if pellets > 1 else 0.5
		var offset: float = (factor - 0.5) * spread
		var angle: float  = base_angle + offset + randf_range(-0.05, 0.05)
		var spawn_pos: Vector2 = owner_player.position \
			+ Vector2(cos(base_angle), sin(base_angle)) * 15.0

		var pellet_speed: float = randf_range(14.0, 16.0) * speed_mult

		_spawn_projectile(
			spawn_pos, angle,
			pellet_speed, final_dmg,
			3 + extra_pen,
			35          # lifetime muy corta → rango corto
		)

	return true

func _apply_physics() -> void:
	if owner_player == null:
		return
	var angle: float = owner_player.aim_angle
	owner_player.velocity -= Vector2(cos(angle), sin(angle)) * kickback
	# Cámara shake (si el player expone el método)
	if owner_player.has_method("add_camera_shake"):
		owner_player.add_camera_shake(shake_amount)

# ── Proyectil inline ────────────────────────────────────────────────────────
func _spawn_projectile(
		pos:       Vector2,
		angle:     float,
		speed:     float,
		dmg:       int,
		pen:       int,
		lifetime:  float
) -> void:
	var p := _PelletNode.new()
	p.position     = pos
	p.velocity     = Vector2(cos(angle), sin(angle)) * speed * 60.0  # px/s
	p.damage       = dmg
	p.penetration  = pen
	p.max_lifetime = lifetime

	var size_mult: float = owner_player.projectile_size_mult if owner_player else 1.0
	p.radius = max(3.0, 7.0 * size_mult)

	var projectiles_node: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_node:
		projectiles_node.add_child(p)
	else:
		get_parent().add_child(p)


# ══ Clase interna del perdigón ══════════════════════════════════════════════
class _PelletNode:
	extends Node2D

	var velocity:     Vector2 = Vector2.ZERO
	var damage:       int     = 18
	var penetration:  int     = 3
	var lifetime:     float   = 0.0
	var max_lifetime: float   = 35.0
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

		# Detección de enemigos
		var enemies := get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if not enemy.has_method("take_damage"):
				continue
			if enemy in _enemies_hit:
				continue
			var dist: float = position.distance_to(enemy.global_position)
			if dist <= radius + 12.0:
				_enemies_hit.append(enemy)
				enemy.take_damage(damage)
				if enemy.has_method("apply_knockback"):
					enemy.apply_knockback(global_position, 8.0)
				penetration -= 1
				if penetration <= 0:
					queue_free()
					return

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var alpha: int = int(clamp(progress * 255.0, 0.0, 255.0))
		draw_circle(Vector2.ZERO, radius, Color(1.0, float(randi_range(100, 150)) / 255.0, 0.0, float(alpha) / 255.0))
