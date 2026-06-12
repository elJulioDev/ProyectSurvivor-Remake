extends Control

signal continue_pressed
signal main_menu_pressed

@onready var btn_continue: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/VBoxContainer/BtnContinueWrapper/BtnContinue
@onready var btn_menu: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/VBoxContainer/BtnMenuWrapper/BtnMenu

func _ready() -> void:
	# 1. Permite que la interfaz procese clics y eventos aunque el juego esté pausado
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# 2. Muestra el cursor nuevamente para poder interactuar con los botones
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Quitar el borde visual de focus
	btn_continue.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_menu.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_menu.pressed.connect(_on_menu_pressed)
	
	btn_continue.grab_focus()

func _input(event: InputEvent) -> void:
	# Presionar ESC para continuar
	if event.is_action_pressed("ui_cancel"):
		get_tree().root.set_input_as_handled()
		_on_continue_pressed()
	# Presionar Enter para continuar (en algunos contextos)
	elif event.is_action_pressed("ui_accept"):
		get_tree().root.set_input_as_handled()
		_on_continue_pressed()

func _on_continue_pressed() -> void:
	get_tree().paused = false
	continue_pressed.emit()
	queue_free()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	main_menu_pressed.emit()
	# El gameplay se encargará de ir al menú
