extends Control

var button: Button
@onready var glow: ColorRect = $GlowRect

# Valores extraídos exactamente de tu matemática original
const SCALE_HOVER := Vector2(1.015, 1.015)
const SCALE_NORMAL := Vector2(1.0, 1.0)
const SCALE_PRESSED := Vector2(0.985, 0.985) # Hundimiento sutil al presionar

const GLOW_ALPHA_HOVER := 0.216 
const GLOW_ALPHA_NORMAL := 0.0
const GLOW_ALPHA_PRESSED := 0.100 

const ANIM_DURATION := 0.12 

var tween: Tween
var is_pressed := false
var _base_glow_color: Color

func _ready() -> void:
	# Buscar automáticamente el botón sin importar su nombre
	for child in get_children():
		if child is Button:
			button = child
			break
			
	if not button:
		push_error("No se encontró un nodo Button en el wrapper: ", name)
		return

	# Guardamos el color original del glow (Rojo, Cian o Gris) configurado en el editor
	_base_glow_color = glow.color
	
	# Aseguramos el pivote en el centro para el botón de 320x64
	button.pivot_offset = Vector2(160, 32)
	
	# Conexión de todos los estados del ratón
	button.mouse_entered.connect(_on_hover_enter)
	button.mouse_exited.connect(_on_hover_exit)
	button.button_down.connect(_on_button_down)
	button.button_up.connect(_on_button_up)

func _on_hover_enter() -> void:
	if not is_pressed:
		_animate_button(SCALE_HOVER, GLOW_ALPHA_HOVER)

func _on_hover_exit() -> void:
	if not is_pressed:
		_animate_button(SCALE_NORMAL, GLOW_ALPHA_NORMAL)

func _on_button_down() -> void:
	is_pressed = true
	_animate_button(SCALE_PRESSED, GLOW_ALPHA_PRESSED)

func _on_button_up() -> void:
	is_pressed = false
	if button.is_hovered():
		_animate_button(SCALE_HOVER, GLOW_ALPHA_HOVER)
	else:
		_animate_button(SCALE_NORMAL, GLOW_ALPHA_NORMAL)

func _animate_button(target_scale: Vector2, target_glow_alpha: float) -> void:
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Anima la escala del botón
	tween.tween_property(button, "scale", target_scale, ANIM_DURATION)
	
	# Anima el halo trasero utilizando el color base guardado
	var target_glow_color = _base_glow_color
	target_glow_color.a = target_glow_alpha
	tween.tween_property(glow, "color", target_glow_color, ANIM_DURATION)
