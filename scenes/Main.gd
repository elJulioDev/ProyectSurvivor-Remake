extends Node

@onready var scene_container: Node = $SceneContainer

var _current_scene: Node = null

func _ready() -> void:
	GameManager.scene_change_requested.connect(_on_scene_change)
	_load_scene("res://scenes/menu.tscn", {})

func _on_scene_change(path: String, data: Dictionary) -> void:
	_load_scene(path, data)

func _load_scene(path: String, data: Dictionary) -> void:
	# Limpiar escena anterior
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null
	
	# Cargar nueva
	var packed = load(path) as PackedScene
	if not packed:
		push_error("No se pudo cargar la escena: " + path)
		return
	
	_current_scene = packed.instantiate()
	scene_container.add_child(_current_scene)
	
	# Pasar datos si la escena lo soporta (ej: score final a GameOver)
	if _current_scene.has_method("setup"):
		_current_scene.setup(data)
	
	GameManager.current_scene_node = _current_scene
