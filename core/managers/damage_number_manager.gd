extends Node2D
class_name DamageNumberManager

## Numeros de danio en espacio de mundo. Al ser Node2D (no CanvasLayer)
## la camara los transforma solo, sin conversion manual a pantalla.

@export_group("Texto y Fuente")
## Fuente a usar. Si se deja vacio usa la fuente por defecto del proyecto.
@export var font: Font = null
## Tamanio de fuente en pixeles.
@export var font_size: int = 20
## Grosor del borde del texto. 0 desactiva el borde.
@export var outline_size: int = 4
## Color del borde (usa el alpha del numero, no el de aca).
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.6)

@export_group("Colores por Daño")
## Color por defecto para daño por debajo del primer umbral.
@export var base_color: Color = Color(1.0, 1.0, 0.8)
## Umbrales de daño ordenados de menor a mayor (ej: 15, 30).
@export var damage_thresholds: PackedFloat32Array = PackedFloat32Array([15.0, 30.0])
## Un color por cada umbral, mismo orden que damage_thresholds.
@export var threshold_colors: Array[Color] = [Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.2)]

@export_group("Animación")
## Velocidad vertical base de subida (px/seg).
@export var float_speed: float = 55.0
## Variacion aleatoria de velocidad vertical (+/-).
@export var float_speed_variance: float = 25.0
## Deriva horizontal aleatoria (+/- px/seg). Da un efecto mas organico.
@export var horizontal_jitter: float = 20.0
## Tiempo total de vida antes de desaparecer (segundos).
@export var fade_time: float = 1.5
## Escala inicial al aparecer (efecto "pop").
@export var start_scale: float = 1.6
## Escala final tras el pop, se mantiene hasta desvanecerse.
@export var end_scale: float = 1.0
## Duracion del pop inicial, como fraccion de fade_time (0-1).
@export_range(0.01, 1.0) var punch_in_fraction: float = 0.18
## Curva opcional para la escala (0=spawn, 1=muerte). Si se deja vacia usa el pop por defecto.
@export var scale_curve: Curve = null
## Curva opcional para el alpha (0=spawn, 1=muerte, 1→0 de opacidad). Si se deja vacia usa el fade por defecto.
@export var alpha_curve: Curve = null

@export_group("Rendimiento")
## Cantidad maxima de numeros simultaneos en pantalla (pool reciclado).
@export var pool_size: int = 60

var _texts     : PackedStringArray  = []
var _colors    : PackedColorArray   = []
var _positions : PackedVector2Array = []   # posicion local (mundo)
var _vel_y     : PackedFloat32Array = []
var _vel_x     : PackedFloat32Array = []
var _sizes     : PackedVector2Array = []
var _timers    : PackedFloat32Array = []
var _next      : int = 0
var _active_count: int = 0

func _ready() -> void:
	_texts.resize(pool_size)
	_colors.resize(pool_size)
	_positions.resize(pool_size)
	_vel_y.resize(pool_size)
	_vel_x.resize(pool_size)
	_sizes.resize(pool_size)
	_timers.resize(pool_size)

	if not font:
		font = ThemeDB.fallback_font
	z_index = 50

func _process(delta: float) -> void:
	if _active_count == 0:
		return
	for i in range(pool_size):
		if _timers[i] <= 0.0:
			continue
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_active_count -= 1
		else:
			_positions[i].y -= _vel_y[i] * delta
			_positions[i].x += _vel_x[i] * delta
	queue_redraw()

func _draw() -> void:
	for i in range(pool_size):
		if _timers[i] <= 0.0:
			continue
		var progress := 1.0 - (_timers[i] / fade_time)   # 0 al spawnear, 1 al morir
		var scaleq    := _scale_for(progress)
		var alpha    := _alpha_for(progress)
		var col      := Color(_colors[i], alpha)
		var half     := _sizes[i] * 0.5 * scaleq

		draw_set_transform(_positions[i], 0.0, Vector2(scaleq, scaleq))
		if outline_size > 0:
			draw_string_outline(font, -half, _texts[i], HORIZONTAL_ALIGNMENT_LEFT,
				-1, font_size, outline_size, Color(outline_color, alpha))
		draw_string(font, -half, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _scale_for(progress: float) -> float:
	if scale_curve:
		return scale_curve.sample(progress)
	var pop_t := clampf(progress / punch_in_fraction, 0.0, 1.0)
	return lerpf(start_scale, end_scale, pop_t)

func _alpha_for(progress: float) -> float:
	if alpha_curve:
		return alpha_curve.sample(progress)
	var t := 1.0 - progress
	return t * t

## Elige el color segun damage_thresholds/threshold_colors. El umbral mas alto
## que cumpla amount gana.
func _color_for_amount(amount: float) -> Color:
	var chosen := base_color
	for i in range(damage_thresholds.size()):
		if i >= threshold_colors.size():
			break
		if amount >= damage_thresholds[i]:
			chosen = threshold_colors[i]
	return chosen

## Spawnea un numero de danio, fijo en el punto de impacto (world_pos).
## Si no se pasa color (o se pasa con alpha 0), el color se calcula
## automaticamente segun `amount` usando damage_thresholds/threshold_colors.
func spawn_damage(world_pos: Vector2, amount: float, color: Color = Color(0, 0, 0, 0)) -> void:
	var idx := _next
	_next = (_next + 1) % pool_size

	if _timers[idx] > 0.0:
		_active_count -= 1   # sobrescribiendo uno activo

	var final_color := color if color.a > 0.0 else _color_for_amount(amount)

	_texts[idx]      = str(roundi(amount))
	_colors[idx]     = final_color
	_positions[idx]  = to_local(world_pos)
	_sizes[idx]      = font.get_string_size(_texts[idx], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	_timers[idx]     = fade_time
	_vel_y[idx]      = float_speed + randf_range(-float_speed_variance, float_speed_variance)
	_vel_x[idx]      = randf_range(-horizontal_jitter, horizontal_jitter)
	_active_count   += 1