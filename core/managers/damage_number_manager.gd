extends CanvasLayer

## Sistema de numeros de danio flotantes. Usa draw_string() en un solo
## Control con transform para scale y sombra para legibilidad.
class_name DamageNumberManager

const POOL_SIZE   : int   = 60
const FLOAT_SPEED : float = 55.0
const FADE_TIME   : float = 1.5
const FONT_SIZE   : int   = 20

var _texts    : PackedStringArray  = []
var _colors   : PackedColorArray   = []
var _positions: PackedVector2Array = []   # centro en pantalla (CanvasLayer)
var _sizes    : PackedVector2Array = []   # tamanio del texto (cacheado al spawn)
var _timers   : PackedFloat32Array = []
var _velocities: PackedFloat32Array = []
var _next     : int   = 0
var _camera   : Camera2D = null
var _canvas   : Control  = null
var _font     : Font     = null
var _active_count: int  = 0

func _ready() -> void:
	_texts.resize(POOL_SIZE)
	_colors.resize(POOL_SIZE)
	_positions.resize(POOL_SIZE)
	_sizes.resize(POOL_SIZE)
	_timers.resize(POOL_SIZE)
	_velocities.resize(POOL_SIZE)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_font = ThemeDB.fallback_font
	if not _font:
		var sys_font := SystemFont.new()
		sys_font.font_names = PackedStringArray(["Arial", "Noto Sans", "DejaVu Sans", "Liberation Sans"])
		sys_font.font_size = FONT_SIZE
		_font = sys_font

func _process(delta: float) -> void:
	if _active_count == 0:
		return
	for i in range(POOL_SIZE):
		if _timers[i] <= 0.0:
			continue
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_active_count -= 1
		else:
			_positions[i].y -= _velocities[i] * delta
	_canvas.queue_redraw()

func _on_draw() -> void:
	for i in range(POOL_SIZE):
		if _timers[i] <= 0.0:
			continue
		var t     := _timers[i] / FADE_TIME
		var alpha := t * t
		var scale := 1.0 + (1.0 - t) * 0.5
		var col   := Color(_colors[i], alpha)
		var shd   := Color(0.0, 0.0, 0.0, alpha * 0.6)
		var pos   := _positions[i]
		var half  := _sizes[i] * 0.5 * scale
		var shadow_offset := Vector2(2.0, 2.0)

		# Sombra
		_canvas.draw_set_transform(pos + shadow_offset, 0.0, Vector2(scale, scale))
		_canvas.draw_string(_font, -half, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, shd)

		# Texto principal
		_canvas.draw_set_transform(pos, 0.0, Vector2(scale, scale))
		_canvas.draw_string(_font, -half, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)

	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Spawnea un numero de danio en posicion global `world_pos`.
func spawn_damage(world_pos: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	if not _camera:
		return

	var idx := _next
	_next = (_next + 1) % POOL_SIZE

	if _timers[idx] > 0.0:
		_active_count -= 1   # sobrescribiendo uno activo

	var view_size : Vector2 = get_viewport().get_visible_rect().size
	var cam_zoom  : Vector2 = _camera.zoom

	_texts[idx]      = str(roundi(amount))
	_colors[idx]     = color
	_positions[idx]  = (world_pos - _camera.global_position) / cam_zoom + view_size * 0.5
	_sizes[idx]      = _font.get_string_size(_texts[idx], HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
	_timers[idx]     = FADE_TIME
	_velocities[idx] = FLOAT_SPEED + randf_range(-25.0, 25.0)
	_active_count   += 1
