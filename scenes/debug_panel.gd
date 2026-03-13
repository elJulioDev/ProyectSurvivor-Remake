extends CanvasLayer

@onready var label: Label = $MarginContainer/Label

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		visible = !visible
	if visible:
		update_debug_text()

func update_debug_text() -> void:
	var fps: float = Engine.get_frames_per_second()
	var memory_usage: float = OS.get_static_memory_usage() / 1048576.0
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects_rendered = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)

	var enemies_count: int = 0
	if is_instance_valid(GameManager.enemy_manager):
		enemies_count = GameManager.enemy_manager.get_active_count()

	# Proyectiles: ahora se leen desde el ProjectileManager DOD (no nodos de escena)
	var projectiles_count: int = 0
	if is_instance_valid(GameManager.projectile_manager):
		projectiles_count = GameManager.projectile_manager.get_active_count()

	var gems_count: int = 0
	var gem_mgr = get_tree().get_first_node_in_group("gem_manager")
	if is_instance_valid(gem_mgr):
		gems_count = gem_mgr.get_gem_count()

	var debug_text: String = "[ MODO DEBUG ]\n"
	debug_text += "------------------\n"
	debug_text += "FPS: %d\n" % fps
	debug_text += "RAM Uso: %.2f MB\n" % memory_usage
	debug_text += "Draw Calls: %d\n" % draw_calls
	debug_text += "Objetos Render: %d\n" % objects_rendered
	debug_text += "------------------\n"
	debug_text += "Enemigos (MultiMesh): %d\n" % enemies_count
	debug_text += "Proyectiles (MultiMesh): %d\n" % projectiles_count
	debug_text += "Gemas XP (MultiMesh): %d\n" % gems_count

	label.text = debug_text