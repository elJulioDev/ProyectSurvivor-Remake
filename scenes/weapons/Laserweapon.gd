## LaserWeapon.gd
## Láser de Plasma — daño continuo masivo en línea recta.
## Tecla 4. Daño 30 DPS base (×6 por frame). Se dibuja mientras dispara.
class_name LaserWeapon
extends Node2D

# ── Stats base ──────────────────────────────────────────────────────────────
var crosshair_type: int    = 2
var cooldown: float        = 0.0    # sin cooldown entre activaciones
var current_cooldown: float = 0.0
var damage: float          = 30.0   # DPS base
var max_range: float       = 1500.0
var beam_duration: float   = 10.0   # frames que dura el haz visible
var draw_timer: float      = 0.0
var shake_amount: float    = 1.0

var owner_player: Node     = null

# ── Acumulador de daño fraccional (para DPS suave) ─────────────────────────
var _damage_accum: float   = 0.0

# ── Actualización ───────────────────────────────────────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	if draw_timer > 0.0:
		draw_timer -= frames
		queue_redraw()
		_deal_beam_damage(delta)

func _deal_beam_damage(delta: float) -> void:
	if owner_player == null:
		return

	var damage_mult: float  = owner_player.global_damage_mult
	# 30 × damage_mult × 6 hits/s → DPS equivalente al pygame (30 * 6 = 180 DPS)
	var dps: float   = damage * damage_mult * 6.0
	var dmg_this_frame: float = dps * delta

	var angle: float   = owner_player.aim_angle
	var origin: Vector2 = owner_player.global_position
	var end: Vector2    = origin + Vector2(cos(angle), sin(angle)) * max_range

	# Comprobar todos los enemigos en el haz (segmento)
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not enemy.has_method("take_damage"):
			continue
		# Distancia punto-segmento
		if _point_near_segment(enemy.global_position, origin, end, 20.0):
			enemy.take_damage(dmg_this_frame)

# ── Disparo ─────────────────────────────────────────────────────────────────
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
	if owner_player and owner_player.has_method("add_camera_shake"):
		owner_player.add_camera_shake(shake_amount)

# ── Render del haz ──────────────────────────────────────────────────────────
func _draw() -> void:
	if draw_timer <= 0.0 or owner_player == null:
		return

	var angle: float    = owner_player.aim_angle
	var local_origin: Vector2 = Vector2.ZERO  # relativo al nodo (en WeaponPivot)
	var world_end: Vector2 = owner_player.global_position \
		+ Vector2(cos(angle), sin(angle)) * max_range
	var local_end: Vector2  = to_local(world_end)

	# Añadir jitter para efecto visual
	local_end += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

	var progress: float = draw_timer / beam_duration
	var width: int      = max(2, int(10.0 * progress))

	# Halo exterior azul
	draw_line(local_origin, local_end,
		Color(0.0, 0.78, 1.0, clamp(progress * 0.7, 0.0, 1.0)),
		float(width + 4))
	# Núcleo blanco
	draw_line(local_origin, local_end,
		Color(1.0, 1.0, 1.0, clamp(progress, 0.0, 1.0)),
		float(width))

# ── Utilidad: distancia punto a segmento ───────────────────────────────────
func _point_near_segment(
		pt: Vector2, a: Vector2, b: Vector2, threshold: float
) -> bool:
	var ab: Vector2  = b - a
	var len_sq: float = ab.length_squared()
	if len_sq == 0.0:
		return pt.distance_to(a) <= threshold
	var t: float = clamp((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector2 = a + t * ab
	return pt.distance_to(closest) <= threshold