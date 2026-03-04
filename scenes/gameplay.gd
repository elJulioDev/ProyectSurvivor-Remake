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
		# En Godot 4 se conecta directamente, has_user_signal() no existe
		player_ref.died.connect(_on_player_died)
		player_ref.leveled_up.connect(_on_player_leveled_up)

		# La cámara sigue al jugador: reparentamos al Player
		camera.reparent(player_ref)
		camera.position = Vector2.ZERO
		camera.make_current()

func _setup_camera() -> void:
	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = GameManager.WORLD_WIDTH
	camera.limit_bottom = GameManager.WORLD_HEIGHT
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed   = 5.0

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
	var m: int = floori(seconds / 60.0)
	var s: int = floori(fmod(seconds, 60.0))
	return "%02d:%02d" % [m, s]

func setup(_data: Dictionary) -> void:
	pass