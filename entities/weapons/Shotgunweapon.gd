## ShotgunWeapon.gd
class_name ShotgunWeapon
extends Node2D

var crosshair_type: int     = 1
var cooldown: float         = 50.0
var current_cooldown: float = 0.0
var damage: float           = 18.0
var pellets: int            = 8
var spread: float           = 0.4
var kickback: float         = 12.0
var shake_amount: float     = 8.0

var owner_player: Node = null

func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm

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
		var angle:  float = base_angle + offset + randf_range(-0.05, 0.05)
		var spawn_pos: Vector2 = owner_player.position \
			+ Vector2(cos(base_angle), sin(base_angle)) * 15.0
		_spawn_projectile(spawn_pos, angle,
			randf_range(14.0, 16.0) * speed_mult,
			final_dmg, 3 + extra_pen, 35)
	return true

func _apply_physics() -> void:
	if owner_player == null: return
	var angle: float = owner_player.aim_angle
	owner_player.velocity -= Vector2(cos(angle), sin(angle)) * kickback * 60.0
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_shake"):
		camera.add_shake(shake_amount)

func _spawn_projectile(pos: Vector2, angle: float, speed: float,
					   dmg: int, pen: int, lifetime: float) -> void:
	var p             := _PelletNode.new()
	p.position         = pos
	p.velocity         = Vector2(cos(angle), sin(angle)) * speed * 60.0
	p.damage           = dmg
	p.penetration      = pen
	p.max_lifetime     = lifetime
	var size_mult: float = owner_player.projectile_size_mult if owner_player else 1.0
	p.radius = maxf(3.0, 7.0 * size_mult)
	var pn: Node = get_tree().get_first_node_in_group("projectiles")
	if pn: pn.add_child(p)
	else:  get_parent().add_child(p)

class _PelletNode extends Node2D:
	var velocity:     Vector2 = Vector2.ZERO
	var damage:       int     = 18
	var penetration:  int     = 3
	var lifetime:     float   = 0.0
	var max_lifetime: float   = 35.0
	var radius:       float   = 7.0
	var _hit_ids:     Dictionary = {}

	func _ready() -> void: z_index = 1

	func _physics_process(delta: float) -> void:
		var frames: float = delta * 60.0
		position  += velocity * delta
		lifetime  += frames
		if lifetime >= max_lifetime:
			queue_free()
			return
		# ── Spatial query ────────────────────────────────────
		var hits : PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(global_position, radius + 12.0)
		for idx in hits:
			if _hit_ids.has(idx): continue
			_hit_ids[idx] = true
			GameManager.enemy_manager.damage_enemy(idx, damage, velocity.normalized(), 8.0)
			penetration -= 1
			if penetration <= 0:
				queue_free()
				return

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var alpha: float = clampf(progress, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius,
			Color(1.0, float(randi_range(100, 150)) / 255.0, 0.0, alpha))