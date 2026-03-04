extends Node2D

# ── Señales ───────────────────────────────────────────────────────────
signal enemy_killed(enemy_node: Node2D)
signal player_leveled_up

# ── Referencias ─────────────────────────────────────────────────────
@onready var world: Node2D                 = $World
@onready var enemies_container: Node2D     = $World/Enemies
@onready var projectiles_container: Node2D = $World/Projectiles
@onready var gems_container: Node2D        = $World/Gems
@onready var camera: Camera2D              = $Camera2D
@onready var hud: Control                  = $HUD/HUDControl

# ── Estado del juego ─────────────────────────────────────────────────
var score: int = 0
var game_over: bool = false
var game_time: float = 0.0

var player_ref: Node2D = null

func _ready() -> void:
	_setup_camera()

	player_ref = $World/Player
	if player_ref:
		player_ref.died.connect(_on_player_died)
		player_ref.leveled_up.connect(_on_player_leveled_up)

		player_ref.global_position = Vector2(
			GameManager.WORLD_WIDTH / 2.0,
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

@onready var spawn_manager: SpawnManager = $SpawnManager

func _process(delta: float) -> void:
	if game_over:
		return

	game_time += delta
	_update_hud()
	
	# Asumiendo que player_ref tiene una propiedad `level`, o se la pones
	var current_level = 1
	if player_ref and "level" in player_ref:
		current_level = player_ref.level
		
	# Actualizar el Spawner
	if is_instance_valid(player_ref):
		var current_enemies = enemies_container.get_child_count()
		spawn_manager.update_spawner(delta, current_enemies, player_ref.global_position, current_level)

# Manejar cuando un enemigo muere
func _on_enemy_killed(enemy: Node2D) -> void:
	score += enemy.points * 100
	
	# Instanciar gema de experiencia aquí...
	# var gem = gem_scene.instantiate()
	# gems_container.add_child(gem)
	# gem.global_position = enemy.global_position

# ── Actualiza el HUD con los datos del frame ──────────────────────────
func _update_hud() -> void:
	if not is_instance_valid(hud):
		return

	hud.score         = score
	hud.enemies_alive = enemies_container.get_child_count()
	hud.wave_time_str = _format_time(game_time)

# ── Callbacks ────────────────────────────────────────────────────────

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