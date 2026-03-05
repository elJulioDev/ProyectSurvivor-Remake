extends Node2D
class_name PistolWeapon

var cooldown         : float = 12.0
var damage           : float = 12.0
var current_cooldown : float = 0.0

@onready var player : Node2D = get_tree().get_first_node_in_group("player")

func update_weapon(delta: float) -> void:
	if current_cooldown > 0.0:
		var cm : float = player.global_cooldown_mult if "global_cooldown_mult" in player else 1.0
		current_cooldown -= (delta * 60.0) / cm

func shoot() -> bool:
	if current_cooldown > 0.0:
		return false

	current_cooldown = cooldown

	var dm    : float = player.global_damage_mult    if "global_damage_mult"    in player else 1.0
	var sm    : float = player.projectile_speed_mult if "projectile_speed_mult" in player else 1.0
	var pen   : int   = 1 + (player.extra_penetration if "extra_penetration"    in player else 0)
	var angle : float = player.aim_angle

	_spawn_projectile(angle, 16.0 * sm, int(damage * dm), pen)
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_shake"):
		camera.add_shake(2.0)
	return true

func _spawn_projectile(angle: float, speed: float, dmg: int, pen: int) -> void:
	var proj_container := get_tree().get_first_node_in_group("projectiles")
	if not proj_container:
		return

	var proj := _make_projectile()
	proj_container.add_child(proj)

	var spawn_dist := 18.0
	proj.global_position = player.global_position + Vector2(
		cos(angle) * spawn_dist,
		sin(angle) * spawn_dist
	)
	proj.setup(angle, speed, dmg, pen, Color(0.0, 1.0, 1.0), 6.0)

func _make_projectile() -> Node2D:
	return _ProjectileNode.new()

class _ProjectileNode extends Node2D:
	var vel      : Vector2 = Vector2.ZERO
	var damage   : int     = 10
	var pen      : int     = 1
	var lifetime : float   = 120.0
	var _color   : Color   = Color.CYAN
	var _radius  : float   = 6.0
	var _hit_ids : Dictionary = {}   # id→true  (más rápido que Array.has)

	func setup(angle: float, speed: float, dmg: int, p: int,
			   col: Color, rad: float) -> void:
		vel    = Vector2(cos(angle), sin(angle)) * speed * 60.0
		damage = dmg;  pen    = p
		_color = col;  _radius = rad

	func _process(delta: float) -> void:
		global_position += vel * delta
		lifetime        -= delta * 60.0
		if lifetime <= 0.0:
			queue_free()
			return

		# ── Colisión con spatial query O(1) ──────────────────────
		var hits := GameManager.get_enemies_in_radius(global_position, _radius + 16.0)
		for enemy in hits:
			var eid : int = enemy.idx
			if _hit_ids.has(eid):
				continue
			_hit_ids[eid] = true
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage, vel.normalized())
			pen -= 1
			if pen <= 0:
				queue_free()
				return

	func _draw() -> void:
		draw_circle(Vector2.ZERO, _radius, _color)
		draw_circle(Vector2.ZERO, _radius * 0.5, Color(1.0, 1.0, 0.8))