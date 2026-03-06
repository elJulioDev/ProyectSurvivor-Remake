extends Node2D

# ── Señales ───────────────────────────────────────────────────────────
#signal player_leveled_up

# ── Referencias ──────────────────────────────────────────────────────
@onready var world:                 Node2D       = $World
@onready var projectiles_container: Node2D       = $World/Projectiles
@onready var gems_container:        Node2D       = $World/Gems
@onready var camera:                Camera2D     = $Camera2D
@onready var hud:                   Control      = $HUD/HUDControl
@onready var spawn_manager:         SpawnManager = $SpawnManager

# EnemyManager: nodo hijo añadido en esta escena (ver gameplay.tscn)
@onready var enemy_manager: Node2D = $EnemyManager

# ── Estado ───────────────────────────────────────────────────────────
var score:     int   = 0
var game_over: bool  = false
var game_time: float = 0.0

var player_ref: Node2D = null

# ── Escena de gema de experiencia ────────────────────────────────────
@export var gem_scene: PackedScene

func _ready() -> void:
	# Registrar el EnemyManager en el autoload para que las armas lo usen
	GameManager.enemy_manager = enemy_manager

	# Pasar el manager al SpawnManager
	spawn_manager.setup(enemy_manager)

	# Conectar señal de muerte de enemigos
	enemy_manager.enemy_killed.connect(_on_enemy_killed)

	_setup_camera()

	player_ref = $World/Player
	if player_ref:
		player_ref.died.connect(_on_player_died)
		player_ref.leveled_up.connect(_on_player_leveled_up)

		player_ref.global_position = Vector2(
			GameManager.WORLD_WIDTH  / 2.0,
			GameManager.WORLD_HEIGHT / 2.0
		)

		if camera.has_method("snap_to_player"):
			camera.snap_to_player()

		camera.make_current()

func _setup_camera() -> void:
	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = GameManager.WORLD_WIDTH
	camera.limit_bottom = GameManager.WORLD_HEIGHT
	camera.position_smoothing_enabled = false

func _process(delta: float) -> void:
	if game_over:
		return

	game_time += delta
	_update_hud()

	var current_level := 1
	if player_ref and "level" in player_ref:
		current_level = player_ref.level

	# Actualizar Spawner con el conteo actual del EnemyManager (no de nodos hijos)
	if is_instance_valid(player_ref):
		var current_enemies : int = enemy_manager.get_active_count()
		spawn_manager.update_spawner(delta, current_enemies,
									 player_ref.global_position, current_level)

# ── Señal de muerte de enemigo (viene de EnemyManager) ──────────────
func _on_enemy_killed(pos: Vector2, points: int) -> void:
	score += points * 100

	# Drop de gema de experiencia (~25% de probabilidad)
	if randi() % 4 == 0 and gem_scene:
		var gem := gem_scene.instantiate()
		gems_container.add_child(gem)
		gem.global_position = pos
		# Si la gema tiene un método de setup, llamarlo
		if gem.has_method("setup"):
			gem.setup(1)

	# --- LÍNEAS ELIMINADAS ---
	# El código de abajo causaba que la barra subiera instantáneamente. 
	# Ahora el jugador solo ganará XP cuando colisione con el nodo de la gema.
	
	# if is_instance_valid(player_ref) and player_ref.has_method("gain_experience"):
	# 	player_ref.gain_experience(points)

## Compatibilidad con el sistema anterior (por si algún script lo llama)
func _on_enemy_killed_at(pos: Vector2, points: int) -> void:
	_on_enemy_killed(pos, points)

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.score         = score
	hud.enemies_alive = enemy_manager.get_active_count()
	hud.wave_time_str = _format_time(game_time)

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
	var m: int = floori(seconds / 60.0)
	var s: int = floori(fmod(seconds, 60.0))
	return "%02d:%02d" % [m, s]

func setup(_data: Dictionary) -> void:
	pass
