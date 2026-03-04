## NovaWeapon.gd
## Nova de Espinas — pasiva. Auto-disparo circular cada ~3s.
## 8 proyectiles en todas las direcciones, penetración infinita.
class_name NovaWeapon
extends Node2D

# ── Stats base ──────────────────────────────────────────────────────────────
var cooldown: float         = 180.0   # ~3 segundos a 60fps
var current_cooldown: float = 0.0
var damage: float           = 30.0
var num_projectiles: int    = 8
var shake_amount: float     = 5.0

var owner_player: Node      = null

# ── update_weapon: descuenta cooldown + redibujar ──────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm

# ── auto_shoot: llamado por player cada frame (arma pasiva) ────────────────
func auto_shoot(_delta: float) -> void:
	if current_cooldown <= 0.0:
		if _activate():
			current_cooldown = cooldown

# ── shoot: no es arma activa, no hace nada ─────────────────────────────────
func shoot() -> bool:
	return false

func _activate() -> bool:
	if owner_player == null:
		return false

	var speed_mult:  float = owner_player.projectile_speed_mult
	var extra_pen:   int   = owner_player.extra_penetration
	var damage_mult: float = owner_player.global_damage_mult
	var final_dmg:   int   = int(damage * damage_mult)
	var size_mult:   float = owner_player.projectile_size_mult

	for i in range(num_projectiles):
		var angle: float = (TAU / float(num_projectiles)) * float(i)
		var spawn_pos: Vector2 = owner_player.position \
			+ Vector2(cos(angle), sin(angle)) * 18.0

		_spawn_projectile(
			spawn_pos, angle,
			9.0 * speed_mult,
			final_dmg,
			9999 + extra_pen,   # penetración infinita
			100,
			size_mult
		)

	# Efecto visual de pulso en el jugador
	if owner_player.has_method("add_camera_shake"):
		owner_player.add_camera_shake(shake_amount)

	# Destello visual de nova (flash circular que crece y desaparece)
	_spawn_nova_flash()
	return true

func _spawn_nova_flash() -> void:
	var flash := _NovaFlash.new()
	flash.position = owner_player.position
	var projectiles_node: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_node:
		projectiles_node.add_child(flash)
	else:
		get_parent().add_child(flash)

# ── Proyectil ────────────────────────────────────────────────────────────────
func _spawn_projectile(
		pos:      Vector2,
		angle:    float,
		speed:    float,
		dmg:      int,
		pen:      int,
		lifetime: float,
		sz_mult:  float
) -> void:
	var p := _NovaProjectile.new()
	p.position     = pos
	p.velocity     = Vector2(cos(angle), sin(angle)) * speed * 60.0
	p.damage       = dmg
	p.penetration  = pen
	p.max_lifetime = lifetime
	p.radius       = max(3.0, 9.0 * sz_mult)

	var projectiles_node: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_node:
		projectiles_node.add_child(p)
	else:
		get_parent().add_child(p)


# ══ Proyectil de nova (púrpura, grande) ══════════════════════════════════════
class _NovaProjectile:
	extends Node2D

	var velocity:     Vector2 = Vector2.ZERO
	var damage:       int     = 30
	var penetration:  int     = 9999
	var lifetime:     float   = 0.0
	var max_lifetime: float   = 100.0
	var radius:       float   = 9.0
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
				enemy.take_damage(damage)
				if enemy.has_method("apply_knockback"):
					enemy.apply_knockback(global_position, 6.0)
				# Penetración infinita → NO decrementar ni destruir

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var a: float = clamp(progress * 1.1, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(0.86, 0.31, 1.0, a))
		draw_circle(Vector2.ZERO, max(2.0, radius * 0.45), Color(1.0, 0.8, 1.0, a))


# ══ Flash visual de la explosión nova ════════════════════════════════════════
class _NovaFlash:
	extends Node2D

	var timer: float    = 0.0
	var max_t: float    = 15.0
	var max_r: float    = 90.0

	func _ready() -> void:
		z_index = 0

	func _process(delta: float) -> void:
		timer += delta * 60.0
		queue_redraw()
		if timer >= max_t:
			queue_free()

	func _draw() -> void:
		var progress: float = timer / max_t
		var r: float = max_r * progress
		var a: float = (1.0 - progress) * 0.55
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.86, 0.31, 1.0, a), 3)
		draw_arc(Vector2.ZERO, r * 0.65, 0.0, TAU, 32, Color(1.0, 0.6, 1.0, a * 0.6), 2)