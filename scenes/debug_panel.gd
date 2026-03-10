extends CanvasLayer

@onready var label: Label = $MarginContainer/Label

func _ready() -> void:
	# El panel arranca oculto
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	# Asegúrate de tener "toggle_debug" asignado a la tecla X en tu Mapa de Entrada
	if Input.is_action_just_pressed("toggle_debug"):
		visible = !visible
		
	# Solo calculamos el texto si el panel está abierto
	if visible:
		update_debug_text()

func update_debug_text() -> void:
	var fps: float = Engine.get_frames_per_second()
	var memory_usage: float = OS.get_static_memory_usage() / 1048576.0 # MB
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects_rendered = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	
	# --- CONTEO DE ENTIDADES ---
	
	# 1. Enemigos (Le preguntamos a tu nuevo Manager en lugar de contar nodos)
	var enemies_count: int = 0
	if is_instance_valid(GameManager.enemy_manager):
		enemies_count = GameManager.enemy_manager.get_active_count()
	
	# 2. Proyectiles y Gemas (Estos sí siguen siendo Nodos en tu World)
	var projectiles_count: int = get_tree().get_nodes_in_group("projectiles").size()
	var gems_count: int = get_tree().get_nodes_in_group("gems").size()
	
	# --- CONSTRUIR EL TEXTO ---
	var debug_text: String = "[ MODO DEBUG ]\n"
	debug_text += "------------------\n"
	debug_text += "FPS: %d\n" % fps
	debug_text += "RAM Uso: %.2f MB\n" % memory_usage
	debug_text += "Draw Calls: %d\n" % draw_calls
	debug_text += "Objetos Render: %d\n" % objects_rendered
	debug_text += "------------------\n"
	debug_text += "Enemigos (MultiMesh): %d\n" % enemies_count
	debug_text += "Proyectiles Activos: %d\n" % projectiles_count
	debug_text += "Gemas de Exp: %d\n" % gems_count
	
	label.text = debug_text
