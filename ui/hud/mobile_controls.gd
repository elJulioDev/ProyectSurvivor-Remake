extends CanvasLayer

# Referencias
@onready var move_joystick : VirtualJoystickPlus = $Control/MoveJoystick
@onready var aim_joystick  : VirtualJoystickPlus = $Control/AimJoystick
@onready var dash_button   : TouchScreenButton   = $Control/DashButton

var _player : Node = null

# ── OPTIMIZACIÓN: StringNames cacheados para evitar Allocs en memoria ──
const A_MOVE_R := &"move_right"
const A_MOVE_L := &"move_left"
const A_MOVE_D := &"move_down"
const A_MOVE_U := &"move_up"
const A_AIM_R  := &"aim_right"
const A_AIM_L  := &"aim_left"
const A_AIM_D  := &"aim_down"
const A_AIM_U  := &"aim_up"
const A_DASH   := &"dash"

const ALL_ACTIONS: Array[StringName] = [
	A_MOVE_R, A_MOVE_L, A_MOVE_D, A_MOVE_U, 
	A_AIM_R, A_AIM_L, A_AIM_D, A_AIM_U, A_DASH
]

func _ready() -> void:
	if not GameManager.is_mobile():
		queue_free()
		return

	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")

	dash_button.pressed.connect(_on_dash_pressed)
	dash_button.visible = false

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# 1. Movimiento (Joystick Izquierdo)
	var mv : Vector2 = move_joystick.value
	_set_axis(A_MOVE_R, A_MOVE_L, mv.x)
	_set_axis(A_MOVE_D, A_MOVE_U, mv.y)

	# 2. Apuntado y Disparo (Joystick Derecho)
	var aim : Vector2 = aim_joystick.value
	
	# Comprobamos si el jugador está moviendo el joystick derecho 
	# (usamos > 0.01 como zona muerta para evitar disparos accidentales)
	if aim.length_squared() > 0.01:
		# Modificamos la variable directamente como esperaba player.gd
		_player.aim_angle = aim.angle()
		# Llamamos a la función de ataque continuamente mientras se mantenga presionado
		_player.attack()

#  SISTEMA DE RESETEO ANTI-STUCK

## Se llama desde gameplay.gd al abrir el menú de mejora
func hide_and_release() -> void:
	visible = false
	set_process(false) 
	
	# 1. Reseteo forzado del estado interno del plugin
	var joysticks: Array = [move_joystick, aim_joystick]
	for joy in joysticks:
		if is_instance_valid(joy):
			joy._reset_values()           
			joy._touch_index = -1         
			joy._click_in = false
			joy._drag_started_inside = false
			joy._dynamic_active = false
	
	# 2. Forzamos la liberación en el Input global
	for action in ALL_ACTIONS:
		_release_action(action)

## Se llama desde gameplay.gd al cerrar el menú de mejora
func show_controls() -> void:
	visible = true
	set_process(true) 

#  HELPERS DE INPUT

func _on_dash_pressed() -> void:
	_press_action(A_DASH)
	await get_tree().process_frame
	_release_action(A_DASH)

func _set_axis(pos_action: StringName, neg_action: StringName, value: float) -> void:
	var dead : float = 0.12
	if value > dead:
		_press_action(pos_action, value)
		_release_action(neg_action)
	elif value < -dead:
		_press_action(neg_action, -value)
		_release_action(pos_action)
	else:
		_release_action(pos_action)
		_release_action(neg_action)

func _press_action(action: StringName, strength: float = 1.0) -> void:
	if not InputMap.has_action(action): return
	var ev := InputEventAction.new()
	ev.action   = action
	ev.pressed  = true
	ev.strength = strength
	Input.parse_input_event(ev)

func _release_action(action: StringName) -> void:
	if not InputMap.has_action(action): return
	var ev := InputEventAction.new()
	ev.action  = action
	ev.pressed = false
	Input.parse_input_event(ev)