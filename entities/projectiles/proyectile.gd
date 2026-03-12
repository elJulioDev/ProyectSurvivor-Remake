extends Node2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 10
var penetration: int = 1
var max_lifetime: float = 35.0
var lifetime: float = 0.0
var radius: float = 6.0
var knockback_mult: float = 1.0   # Seteado por WeaponController según player.knockback_mult
var _hit_ids: Dictionary = {}

var _prev_pos: Vector2 = Vector2.ZERO
var _use_swept: bool = false

# Visuales
var _color: Color = Color.CYAN
var _inner_color: Color = Color.WHITE
var _inner_mult: float = 0.5
var _fade_out: bool = false
var _fade_mult: float = 1.0
var _flicker: bool = false

func setup(angle: float, speed: float, calc_dmg: int, calc_pen: int, weapon_data: WeaponData, final_rad: float) -> void:
	velocity = Vector2(cos(angle), sin(angle)) * speed * 60.0
	damage = calc_dmg
	penetration = calc_pen
	max_lifetime = weapon_data.max_lifetime
	radius = final_rad

	_use_swept = weapon_data.use_swept_collision
	_color = weapon_data.projectile_color
	_inner_color = weapon_data.inner_color
	_inner_mult = weapon_data.inner_radius_mult
	_fade_out = weapon_data.fade_out
	_fade_mult = weapon_data.fade_multiplier
	_flicker = weapon_data.flicker_fire_effect

	_prev_pos = global_position

func _process(delta: float) -> void:
	_prev_pos = global_position
	global_position += velocity * delta
	lifetime += delta * 60.0
	queue_redraw()

	if lifetime >= max_lifetime:
		queue_free()
		return

	if _use_swept:
		_check_hit_swept()
	else:
		_check_hit_normal()

func _check_hit_normal() -> void:
	var hits: PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(global_position, radius + 16.0)
	for idx in hits:
		if _hit_ids.has(idx): continue
		_hit_ids[idx] = true
		GameManager.enemy_manager.damage_enemy(
			idx, damage, velocity.normalized(), 8.0 * knockback_mult)
		penetration -= 1
		if penetration <= 0:
			queue_free()
			return

func _check_hit_swept() -> void:
	var mid := (_prev_pos + global_position) * 0.5
	var seg_len := global_position.distance_to(_prev_pos)
	var hits : PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(mid, seg_len * 0.5 + radius + 14.0)
	for idx in hits:
		if _hit_ids.has(idx): continue
		var enemy_pos = GameManager.enemy_manager.positions[idx]
		var d := _point_to_segment_dist(enemy_pos, _prev_pos, global_position)
		if d <= radius + 14.0:
			_hit_ids[idx] = true
			GameManager.enemy_manager.damage_enemy(
				idx, damage, velocity.normalized(), 12.0 * knockback_mult)
			penetration -= 1
			if penetration <= 0:
				queue_free()
				return

func _point_to_segment_dist(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq == 0.0: return pt.distance_to(a)
	var t: float = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab)

func _draw() -> void:
	var current_alpha: float = 1.0
	if _fade_out:
		var progress: float = 1.0 - (lifetime / max_lifetime)
		current_alpha = clampf(progress * _fade_mult, 0.0, 1.0)

	var main_c = _color
	main_c.a *= current_alpha

	if _flicker:
		main_c = Color(1.0, float(randi_range(100, 150)) / 255.0, 0.0, current_alpha)

	draw_circle(Vector2.ZERO, radius, main_c)
	if _inner_mult > 0.0:
		var inner_c = _inner_color
		inner_c.a *= current_alpha
		draw_circle(Vector2.ZERO, maxf(1.0, radius * _inner_mult), inner_c)