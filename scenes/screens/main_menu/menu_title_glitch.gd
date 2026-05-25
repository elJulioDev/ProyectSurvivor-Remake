extends Control

@export var min_interval := 2.0
@export var max_interval := 5.5
@export var glitch_duration := 0.15

var _timer := 0.0
var _next_glitch := 0.0

# Referencias a los nodos que ya existen en tu escena
@onready var title_red: Label = $TitleRed
@onready var title_cyan: Label = $TitleCyan
@onready var title_main: Label = $TitleMain

# Guardaremos sus posiciones iniciales
var _base_pos_red: Vector2
var _base_pos_cyan: Vector2
var _base_pos_main: Vector2

func _ready() -> void:
	# Guardamos el acomodo inicial que les diste en el editor (con sus offsets)
	_base_pos_red = title_red.position
	_base_pos_cyan = title_cyan.position
	_base_pos_main = title_main.position
	
	_next_glitch = randf_range(min_interval, max_interval)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_glitch:
		_trigger_glitch()
		_timer = 0.0
		_next_glitch = randf_range(min_interval, max_interval)

func _trigger_glitch() -> void:
	var offset_x := randf_range(6.0, 16.0)
	var offset_y := randf_range(-4.0, 4.0)
	
	# --- PRIMER CORTE (Movimiento errático) ---
	title_main.position = _base_pos_main + Vector2(-offset_x / 2.0, offset_y)
	title_red.position = _base_pos_red + Vector2(-offset_x, -offset_y / 2.0)
	title_cyan.position = _base_pos_cyan + Vector2(offset_x, offset_y / 2.0)
	
	# Pausa minúscula
	await get_tree().create_timer(glitch_duration / 2.0).timeout
	
	# --- SEGUNDO CORTE (Invertimos las posiciones) ---
	title_main.position = _base_pos_main + Vector2(offset_x / 2.0, -offset_y)
	title_red.position = _base_pos_red + Vector2(offset_x, offset_y / 2.0)
	title_cyan.position = _base_pos_cyan + Vector2(-offset_x, -offset_y / 2.0)
	
	# Pausa minúscula
	await get_tree().create_timer(glitch_duration / 2.0).timeout
	
	# --- FIN DEL GLITCH (Volvemos a la normalidad) ---
	title_main.position = _base_pos_main
	title_red.position = _base_pos_red
	title_cyan.position = _base_pos_cyan
