## LaserWeapon.gd
class_name LaserWeapon
extends Node2D

var crosshair_type: int     = 2
var cooldown: float         = 0.0
var current_cooldown: float = 0.0
var damage: float           = 30.0
var max_range: float        = 1500.0
var beam_duration: float    = 10.0
var draw_timer: float       = 0.0
var shake_amount: float     = 1.0

var owner_player: Node = null

func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if draw_timer > 0.0:
		draw_timer -= frames
		queue_redraw()
		_deal_beam_damage(delta)

func _deal_beam_damage(delta: float) -> void:
	if owner_player == null: return

	var damage_mult: float = owner_player.global_damage_mult
	var dps: float         = damage * damage_mult * 6.0
	var dmg_this_frame: float = dps * delta

	var angle:   float  = owner_player.aim_angle
	var origin:  Vector2 = owner_player.global_position
	var end:     Vector2 = origin + Vector2(cos(angle), sin(angle)) * max_range
	var hit_dir: Vector2 = Vector2(cos(angle), sin(angle))

	# ── Spatial query a lo largo del rayo ─────────────────────────
	var seg_len := 200.0
	var ray_len := max_range
	var checked_ids: Dictionary = {}
	var t := 0.0
	while t < ray_len:
		var sample_pos := origin + hit_dir * (t + seg_len * 0.5)
		var hits : PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(sample_pos, seg_len * 0.5 + 20.0)
		for idx in hits:
			if checked_ids.has(idx): continue
			var enemy_pos = GameManager.enemy_manager.positions[idx]
			# Verificar distancia al segmento completo
			if _point_near_segment(enemy_pos, origin, end, 20.0):
				checked_ids[idx] = true
				GameManager.enemy_manager.damage_enemy(idx, dmg_this_frame, hit_dir, 0.0)
		t += seg_len

func shoot() -> bool:
	if _activate():
		_apply_physics()
		return true
	return false

func _activate() -> bool:
	draw_timer = beam_duration
	queue_redraw()
	return true

func _apply_physics() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_shake"):
		camera.add_shake(shake_amount)

func _draw() -> void:
	if draw_timer <= 0.0 or owner_player == null: return
	var angle:        float   = owner_player.aim_angle
	var local_origin: Vector2 = Vector2.ZERO
	var world_end:    Vector2 = owner_player.global_position \
		+ Vector2(cos(angle), sin(angle)) * max_range
	var local_end:    Vector2 = to_local(world_end)
	local_end += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	var progress: float = draw_timer / beam_duration
	var width: int      = maxi(2, int(10.0 * progress))
	draw_line(local_origin, local_end,
		Color(0.0, 0.78, 1.0, clampf(progress * 0.7, 0.0, 1.0)), float(width + 4))
	draw_line(local_origin, local_end,
		Color(1.0, 1.0, 1.0, clampf(progress, 0.0, 1.0)), float(width))

func _point_near_segment(pt: Vector2, a: Vector2, b: Vector2, threshold: float) -> bool:
	var ab:     Vector2 = b - a
	var len_sq: float   = ab.length_squared()
	if len_sq == 0.0:
		return pt.distance_to(a) <= threshold
	var t:       float   = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector2 = a + t * ab
	return pt.distance_to(closest) <= threshold