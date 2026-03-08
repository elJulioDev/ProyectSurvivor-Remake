## BoomerangWeapon.gd
class_name BoomerangWeapon
extends Node2D

var cooldown: float         = 80.0
var current_cooldown: float = 0.0
var damage: float           = 60.0
var shake_amount: float     = 3.0
var max_dist: float         = 400.0

var owner_player: Node = null

var _active_proj: Node  = null
var _start_pos: Vector2 = Vector2.ZERO
var _returning: bool    = false

func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if current_cooldown > 0.0:
		var cm: float = owner_player.global_cooldown_mult if owner_player else 1.0
		current_cooldown -= frames / cm

	if _active_proj and is_instance_valid(_active_proj):
		if _active_proj.is_queued_for_deletion():
			_on_proj_destroyed(); return
		if not _returning:
			if _active_proj.position.distance_squared_to(_start_pos) >= max_dist * max_dist:
				_active_proj.velocity = -_active_proj.velocity
				_active_proj.clear_hits()
				_active_proj.set_color_return()
				_returning = true
		else:
			if owner_player:
				var d_sq: float = _active_proj.position.distance_squared_to(
					owner_player.global_position)
				if d_sq < 45.0 * 45.0:
					_active_proj.queue_free()
					_on_proj_destroyed()
				elif d_sq > 1500.0 * 1500.0:
					_active_proj.queue_free()
					_on_proj_destroyed()

func _on_proj_destroyed() -> void:
	_active_proj = null; _returning = false
	if current_cooldown <= 0.0: current_cooldown = cooldown

func auto_shoot(_delta: float) -> void:
	if current_cooldown <= 0.0 and _active_proj == null:
		_fire_boomerang()

func shoot() -> bool: return false

func _fire_boomerang() -> void:
	if owner_player == null: return
	if _active_proj and is_instance_valid(_active_proj): return
	var speed_mult:  float = owner_player.projectile_speed_mult
	var extra_pen:   int   = owner_player.extra_penetration
	var damage_mult: float = owner_player.global_damage_mult
	var final_dmg:   int   = int(damage * damage_mult)
	var sz_mult:     float = owner_player.projectile_size_mult
	var angle:       float = owner_player.aim_angle
	var spawn_pos: Vector2 = owner_player.position \
		+ Vector2(cos(angle), sin(angle)) * 24.0
	var p             := _BoomerangNode.new()
	p.position         = spawn_pos
	p.velocity         = Vector2(cos(angle), sin(angle)) * 15.0 * speed_mult * 60.0
	p.damage           = final_dmg
	p.penetration      = 9999 + extra_pen
	p.max_lifetime     = 800.0
	p.radius           = maxf(4.0, 11.0 * sz_mult)
	p._on_freed        = Callable(self, "_on_proj_destroyed")
	var pn: Node = get_tree().get_first_node_in_group("projectiles")
	if pn: pn.add_child(p)
	else:  get_parent().add_child(p)
	_active_proj = p; _start_pos = owner_player.position; _returning = false

class _BoomerangNode extends Node2D:
	var velocity:     Vector2  = Vector2.ZERO
	var damage:       int      = 60
	var penetration:  int      = 9999
	var lifetime:     float    = 0.0
	var max_lifetime: float    = 800.0
	var radius:       float    = 11.0
	var _hit_ids:     Dictionary = {}
	var _color:       Color    = Color(1.0, 0.86, 0.24, 1.0)
	var _on_freed:    Callable = Callable()

	func _ready()             -> void: z_index = 2
	func clear_hits()         -> void: _hit_ids.clear()
	func set_color_return()   -> void: _color = Color(1.0, 0.55, 0.12, 1.0)

	func _physics_process(delta: float) -> void:
		var frames: float = delta * 60.0
		position  += velocity * delta
		lifetime  += frames
		if lifetime >= max_lifetime:
			_notify_free(); queue_free(); return
		# ── Spatial query ─────────────────────────────────────
		var hits : PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(global_position, radius + 14.0)
		for idx in hits:
			if _hit_ids.has(idx): continue
			_hit_ids[idx] = true
			GameManager.enemy_manager.damage_enemy(idx, damage, velocity.normalized(), 10.0)
		queue_redraw()

	func _notify_free() -> void:
		if _on_freed.is_valid(): _on_freed.call()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE: _notify_free()

	func _draw() -> void:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		var a: float = clampf(progress * 1.2, 0.0, 1.0)
		var rot_rad: float = deg_to_rad(lifetime * 10.0)
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(4):
			var ap: float = rot_rad + (PI * 0.5 * float(i))
			pts.append(Vector2(cos(ap), sin(ap)) * radius)
		draw_colored_polygon(pts, Color(_color.r, _color.g, _color.b, a))
		draw_polyline(pts + PackedVector2Array([pts[0]]),
			Color(1.0, 1.0, 0.9, a * 0.7), 2)
		draw_circle(Vector2.ZERO, maxf(2.0, radius * 0.3), Color(1.0, 0.97, 0.85, a))