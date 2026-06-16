extends CanvasLayer

## Pool de Labels reutilizables para mostrar numeros de danio flotantes.
## Usa global_position del danio (mundo) convertido a pantalla via camara.
class_name DamageNumberManager

const POOL_SIZE   : int   = 60
const FLOAT_SPEED : float = 80.0
const FADE_TIME   : float = 0.55
const BASE_SCALE  : float = 1.0

var _pool     : Array[Label] = []
var _timers   : Array[float] = []          # tiempo restante de vida
var _velocities: Array[float] = []         # velocidad vertical por label
var _next     : int   = 0
var _camera   : Camera2D = null

func _ready() -> void:
	for _i in range(POOL_SIZE):
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		lbl.visible              = false
		add_child(lbl)
		_pool.append(lbl)
		_timers.append(0.0)
		_velocities.append(0.0)

func _process(delta: float) -> void:
	if _next == 0:
		return
	for i in range(POOL_SIZE):
		if _timers[i] <= 0.0:
			continue
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_pool[i].visible = false
			continue
		var t := _timers[i] / FADE_TIME
		_pool[i].position.y -= _velocities[i] * delta
		_pool[i].modulate.a   = t * t
		_pool[i].scale         = Vector2.ONE * (BASE_SCALE + (1.0 - t) * 0.3)

## Spawnea un numero de danio en posicion global `world_pos`.
## @param amount: danio a mostrar (se redondea a entero)
## @param color:  color del texto (por defecto blanco)
func spawn_damage(world_pos: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
	if not _camera:
		return

	var idx := _next
	_next = (_next + 1) % POOL_SIZE

	# Convertir posicion del mundo a coordenadas de pantalla (CanvasLayer)
	var view_size : Vector2 = get_viewport().get_visible_rect().size
	var cam_zoom  : Vector2 = _camera.zoom
	var screen_pos: Vector2 = (world_pos - _camera.global_position) / cam_zoom + view_size * 0.5

	_pool[idx].text    = str(roundi(amount))
	_pool[idx].position = screen_pos
	_pool[idx].add_theme_font_size_override("font_size", 14)
	_pool[idx].add_theme_color_override("font_color", color)
	_pool[idx].add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_pool[idx].modulate = Color.WHITE
	_pool[idx].scale    = Vector2.ONE * BASE_SCALE
	_pool[idx].visible  = true

	_timers[idx]    = FADE_TIME
	_velocities[idx] = FLOAT_SPEED + randf_range(-25.0, 25.0)
