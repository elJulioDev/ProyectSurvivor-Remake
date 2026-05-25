extends Label 

@export var amplitude := 3.0  # Cuántos píxeles sube y baja
@export var speed := 1.5      # Qué tan rápido lo hace

var _base_pos := Vector2.ZERO
var _time := 0.0
var _is_ready := false

func _ready() -> void:
	# El VBoxContainer calcula la posición de sus hijos un frame después.
	# Usamos call_deferred para guardar la posición exacta en la que lo deja el contenedor.
	call_deferred("_save_base_position")

func _save_base_position() -> void:
	_base_pos = position
	_is_ready = true

func _process(delta: float) -> void:
	if not _is_ready: 
		return # Evita que se mueva antes de tiempo
		
	_time += delta
	# Mantenemos su X original (dictado por el contenedor) y solo alteramos la Y
	position = _base_pos + Vector2(0, sin(_time * speed) * amplitude)
