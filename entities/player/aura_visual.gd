extends Node2D
# aura_visual.gd
# Dibuja el círculo del aura de espinas y el arco de pulso.
# Recibe datos del player vía set_state().

var _radius            : float = 80.0
var _knockback         : float = 0.0
var _pulse_timer       : float = 0.0
var _pulse_interval    : float = 4.0
var _vis_timer         : float = 0.0

func set_state(radius: float, knockback: float, pulse_timer: float, pulse_interval: float) -> void:
	_radius         = radius
	_knockback      = knockback
	_pulse_timer    = pulse_timer
	_pulse_interval = pulse_interval

func _process(delta: float) -> void:
	_vis_timer += delta
	queue_redraw()

func _draw() -> void:
	var pulse := sin(_vis_timer * 2.5) * 0.5 + 0.5
	draw_circle(Vector2.ZERO, _radius,
		Color(0.58, 0.0, 1.0, 0.06 + pulse * 0.04))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64,
		Color(0.78, 0.2, 1.0, 0.25 + pulse * 0.20), 2.0)

	if _knockback > 0.0 and _pulse_interval > 0.0:
		var pulse_progress := clampf(_pulse_timer / _pulse_interval, 0.0, 1.0)
		draw_arc(Vector2.ZERO, _radius * 0.93,
			0.0, TAU * pulse_progress, 48,
			Color(1.0, 0.4, 1.0, 0.55), 3.0)