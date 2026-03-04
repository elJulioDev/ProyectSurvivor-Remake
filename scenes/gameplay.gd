extends Node2D

# ── Señales (¡Siempre van arriba!) ───────────────────────────────────
signal enemy_killed(enemy_node: Node2D)
signal player_leveled_up

# ── Referencias ─────────────────────────────────────────────────────
@onready var world: Node2D          = $World
@onready var enemies_container: Node2D = $World/Enemies
@onready var projectiles_container: Node2D = $World/Projectiles
@onready var gems_container: Node2D    = $World/Gems
@onready var camera: Camera2D          = $Camera2D
@onready var hud: Control              = $HUD/HUDControl

# ── Estado del juego ─────────────────────────────────────────────────
var score: int = 0
var game_over: bool = false
var game_time: float = 0.0  # en segundos

# ── Managers ─────────────────────────────────────────────────────────
# var spawn_manager: SpawnManager  <-- COMENTADO HASTA CREARLO
var player_ref: Node2D = null  

func _ready() -> void:
	_setup_camera()
	# _setup_spawn_manager() <-- COMENTADO HASTA CREARLO
	
	player_ref = $World/Player
	if player_ref:
		if player_ref.has_user_signal("died"):
			player_ref.died.connect(_on_player_died)
		if player_ref.has_user_signal("leveled_up"):
			player_ref.leveled_up.connect(_on_player_leveled_up)
			
		# ── NUEVO: adjuntar la cámara al jugador ──
		camera.reparent(player_ref) 
		camera.position = Vector2.ZERO
		camera.make_current()

func _setup_camera() -> void:
	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = GameManager.WORLD_WIDTH
	camera.limit_bottom = GameManager.WORLD_HEIGHT
	# Seguir al jugador suavemente
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed   = 5.0

# <-- FUNCIÓN COMENTADA HASTA CREAR EL MANAGER
# func _setup_spawn_manager() -> void:
# 	spawn_manager = SpawnManager.new()
# 	spawn_manager.enemies_container = enemies_container
# 	add_child(spawn_manager)

func _process(delta: float) -> void:
	if game_over:
		return
	game_time += delta

func _on_player_died() -> void:
	game_over = true
	await get_tree().create_timer(1.2).timeout
	GameManager.goto_scene("res://scenes/game_over.tscn", {
		"score": score,
		"time":  _format_time(game_time),
	})

func _on_player_leveled_up() -> void:
	get_tree().paused = true
	GameManager.goto_scene("res://scenes/upgrade.tscn", {})

func _format_time(seconds: float) -> String:
	# floori asegura que siempre sea un número entero (int) válido
	var m: int = floori(seconds / 60.0)
	var s: int = floori(fmod(seconds, 60.0))
	return "%02d:%02d" % [m, s]

func setup(_data: Dictionary) -> void:
	pass  # gameplay no necesita datos de entrada
