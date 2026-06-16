extends CanvasLayer

## Sistema de numeros de danio flotantes sin nodos Label.
## Usa draw_string() en un solo Control para maximo rendimiento.
class_name DamageNumberManager

const POOL_SIZE   : int   = 60
const FLOAT_SPEED : float = 80.0
const FADE_TIME   : float = 0.55
const FONT_SIZE   : int   = 14

var _texts    : Array[String]      = []
var _colors   : Array[Color]       = []
var _positions: Array[Vector2]     = []   # posicion en pantalla (CanvasLayer)
var _timers   : Array[float]       = []
var _velocities: Array[float]      = []
var _next     : int   = 0
var _camera   : Camera2D = null
var _canvas   : Control  = null
var _any_active: bool    = false
var _font     : Font     = null

func _ready() -> void:
	for _i in range(POOL_SIZE):
		_texts.append("")
		_colors.append(Color.WHITE)
		_positions.append(Vector2.ZERO)
		_timers.append(0.0)
		_velocities.append(0.0)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)

	_canvas.draw.connect(_on_draw)

	# Crear una DynamicFont simple (o usar la del theme)
	_font = ThemeDB.fallback_font
	if not _font:
		var sys_font := SystemFont.new()
		sys_font.font_names = PackedStringArray(["Arial", "Noto Sans", "DejaVu Sans", "Liberation Sans"])
		sys_font.font_size = FONT_SIZE
		_font = sys_font

func _process(delta: float) -> void:
	if not _any_active:
		return
	_any_active = false
	for i in range(POOL_SIZE):
		if _timers[i] <= 0.0:
			continue
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			continue
		_any_active = true
		_positions[i].y -= _velocities[i] * delta

	_canvas.queue_redraw()

func _on_draw() -> void:
	for i in range(POOL_SIZE):
		if _timers[i] <= 0.0:
			continue
		var t := _timers[i] / FADE_TIME
		var alpha := t * t
		var col := Color(_colors[i], alpha)
		var pos := _positions[i]
		var size := _font.get_string_size(_texts[i], HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE + roundi((1.0 - t) * 6))
		pos -= size * 0.5
		_canvas.draw_string(_font, pos, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + roundi((1.0 - t) * 6), col)

## Spawnea un numero de danio en posicion global `world_pos`.
func spawn_damage(world_pos: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	if not _camera:
		return

	var idx := _next
	_next = (_next + 1) % POOL_SIZE

	var view_size : Vector2 = get_viewport().get_visible_rect().size
	var cam_zoom  : Vector2 = _camera.zoom

	_texts[idx]     = str(roundi(amount))
	_colors[idx]    = color
	_positions[idx] = (world_pos - _camera.global_position) / cam_zoom + view_size * 0.5
	_timers[idx]    = FADE_TIME
	_velocities[idx] = FLOAT_SPEED + randf_range(-25.0, 25.0)
	_any_active     = true
