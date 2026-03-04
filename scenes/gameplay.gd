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
		# En Godot 4 se conecta directamente
		player_ref.died.connect(_on_player_died)
		player_ref.leveled_up.connect(_on_player_leveled_up)

		# 1. Mover al jugador al centro de la pantalla inicial
		player_ref.global_position = Vector2(GameManager.WORLD_WIDTH / 2.0, GameManager.WORLD_HEIGHT / 2.0)

		# 2. Eliminamos camera.reparent(player_ref). Dejamos que camera.gd haga el seguimiento global.
		# Forzamos un salto instantáneo para centrar la cámara al iniciar el juego.
		if camera.has_method("snap_to_player"):
			camera.snap_to_player()
			
		camera.make_current()

func _setup_camera() -> void:
	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = GameManager.WORLD_WIDTH
	camera.limit_bottom = GameManager.WORLD_HEIGHT
	
	# 3. Desactivamos el suavizado nativo de Godot para que no pelee 
	# con la física "lerp_dt" que programaste en camera.gd
	camera.position_smoothing_enabled = false

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
