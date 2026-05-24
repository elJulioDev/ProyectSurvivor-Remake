extends CanvasLayer

# Referencias
@onready var move_joystick : VirtualJoystickPlus = $Control/MoveJoystick
@onready var aim_joystick  : VirtualJoystickPlus = $Control/AimJoystick
@onready var dash_button   : TouchScreenButton   = $Control/DashButton

var _player : Node = null
var _aim_vec : Vector2 = Vector2.ZERO
var _shooting : bool = false

func _ready() -> void:
	# Solo mostrar en móvil
	if not GameManager.is_mobile():
		queue_free()
		return

	# Esperar que el jugador esté en escena
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")

	aim_joystick.analogic_changed.connect(_on_aim_changed)
	dash_button.pressed.connect(_on_dash_pressed)

	# Ocultar dash hasta que se desbloquee
	dash_button.visible = false


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# ── Movimiento ────────────────────────────────────────────────
	var mv : Vector2 = move_joystick.value

	# Inyectar como acciones de Input
	_set_axis("move_right", "move_left",  mv.x)
	_set_axis("move_down",  "move_up",    mv.y)

	# ── Apuntado ──────────────────────────────────────────────────
	if _aim_vec.length_squared() > 0.01:
		_set_axis("aim_right", "aim_left", _aim_vec.x)
		_set_axis("aim_down",  "aim_up",   _aim_vec.y)

		# Actualizar aim_angle del jugador directamente
		_player.aim_angle = _aim_vec.angle()

		# Disparo automático mientras haya input en el joystick derecho
		if not _shooting:
			_shooting = true
		_player.attack()
	else:
		# Sin input en joystick derecho: liberar acciones de aim
		_release_action("aim_right")
		_release_action("aim_left")
		_release_action("aim_up")
		_release_action("aim_down")
		_shooting = false

	# ── Mostrar dash si se desbloqueó ─────────────────────────────
	if is_instance_valid(_player) and "dash_unlocked" in _player:
		dash_button.visible = _player.dash_unlocked


func _on_aim_changed(vec: Vector2, _dist, _ang, _angcw, _angccw) -> void:
	_aim_vec = vec


func _on_dash_pressed() -> void:
	if is_instance_valid(_player):
		# Simular la acción "dash" igual que el teclado
		var ev := InputEventAction.new()
		ev.action  = "dash"
		ev.pressed = true
		Input.parse_input_event(ev)


# ── Helpers ───────────────────────────────────────────────────────

func _set_axis(pos_action: String, neg_action: String, value: float) -> void:
	# Umbral mínimo para evitar drift
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


func _press_action(action: String, strength: float = 1.0) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action   = action
	ev.pressed  = true
	ev.strength = strength
	Input.parse_input_event(ev)


func _release_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action  = action
	ev.pressed = false
	Input.parse_input_event(ev)

func _is_mobile() -> bool:
	return OS.get_name() in ["Android", "iOS"]
	# return true

func show_controls() -> void:
	$Control.visible = true

func hide_and_release() -> void:
	$Control.visible = false
	_release_action("move_right")
	_release_action("move_left")
	_release_action("move_up")
	_release_action("move_down")
	_release_action("aim_right")
	_release_action("aim_left")
	_release_action("aim_up")
	_release_action("aim_down")
	_shooting = false
