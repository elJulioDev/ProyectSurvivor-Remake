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
	# Recolección de datos
	var fps: float = Engine.get_frames_per_second()
	var process_time: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 
	var physics_time: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var mem_static: float = OS.get_static_memory_usage() / 1048576.0
	var mem_peak: float = OS.get_static_memory_peak_usage() / 1048576.0
	var vram_usage: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects_rendered = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	var physics_objects = Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	var collision_pairs = Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)

	var enemies_count: int = 0
	if is_instance_valid(GameManager.enemy_manager):
		enemies_count = GameManager.enemy_manager.get_active_count()

	var projectiles_count: int = 0
	if is_instance_valid(GameManager.projectile_manager):
		projectiles_count = GameManager.projectile_manager.get_active_count()

	var gems_count: int = 0
	var gem_mgr = get_tree().get_first_node_in_group("gem_manager")
	if is_instance_valid(gem_mgr):
		gems_count = gem_mgr.get_gem_count()

	# Añadimos la versión del motor para darle un toque más "F3"
	var engine_version: String = Engine.get_version_info().string

	# Construcción compacta del texto (Estilo Minecraft)
	var text := "Godot %s | FPS: %d\n" % [engine_version, fps]
	text += "CPU (Proc/Phys): %.2f ms / %.2f ms\n" % [process_time, physics_time]
	text += "Memoria RAM: %.2f MB (Pico: %.2f MB) | VRAM: %.2f MB\n" % [mem_static, mem_peak, vram_usage]
	text += "Render - Draws: %d | Objetos: %d | Prims: %d\n" % [draw_calls, objects_rendered, primitives]
	text += "Físicas 2D - Activos: %d | Pares colisión: %d\n" % [physics_objects, collision_pairs]
	text += "Entidades - Enemigos: %d | Proyectiles: %d | Gemas XP: %d" % [enemies_count, projectiles_count, gems_count]

	label.text = text