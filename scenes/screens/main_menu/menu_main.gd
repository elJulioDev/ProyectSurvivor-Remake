extends Control

# Referencias a los botones exactos (asegúrate de que las rutas coincidan con los nombres en tu escena)
@onready var btn_play: Button = $ButtonsContainer/BtnPlayWrapper/BtnPlay
@onready var btn_settings: Button = $ButtonsContainer/BtnSettingsWrapper/BtnSettings
@onready var btn_exit: Button = $ButtonsContainer/BtnExitWrapper/BtnExit

func _ready() -> void:
	# Asegurarnos de que el mouse sea visible al entrar al menú
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Conectar las señales 'pressed' de cada botón
	btn_play.pressed.connect(_on_play_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)

func _on_play_pressed() -> void:
	# Utiliza tu sistema GameManager para cambiar a la pantalla de selección de personaje
	GameManager.goto_scene("res://scenes/screens/character_select/character_select.tscn")

func _on_settings_pressed() -> void:
	# Aquí pondrás la ruta a tu menú de ajustes cuando lo crees
	print("Abriendo Ajustes...")
	# GameManager.goto_scene("res://scenes/screens/settings/settings.tscn")

func _on_exit_pressed() -> void:
	# Salir del juego de forma limpia
	get_tree().quit()