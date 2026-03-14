extends Node2D

# ── Referencias ──────────────────────────────────────────────────────
@onready var world:                  Node2D          = $World
@onready var camera:                 Camera2D        = $Camera2D
@onready var hud:                    Control         = $HUD/HUDControl
@onready var spawn_manager:          SpawnManager    = $SpawnManager
@onready var enemy_manager:          Node2D          = $EnemyManager
@onready var gem_manager:            GemManager      = $GemManager
@onready var upgrade_layer:          CanvasLayer     = $UpgradeLayer
@onready var projectile_manager:     ProjectileManager = $ProjectileManager

# ── Estado ───────────────────────────────────────────────────────────
var score:     int   = 0
var enemies_killed: int = 0
var game_over: bool  = false
var game_time: float = 0.0

var player_ref: Node2D = null

## True mientras hay una pantalla de upgrade visible
var _upgrade_active: bool = false

# ── Tabla de drop de gemas por tipo de enemigo ───────────────────────
## key = points del enemigo  → [xp_base, extra_gems_prob, extra_gems_max]
const GEM_DROP_TABLE : Dictionary = {
	5:  [3,  0.0,  0],   # small
	10: [6,  0.15, 1],   # normal
	20: [14, 0.30, 2],   # large
	60: [45, 0.60, 3],   # tank
	22: [15, 0.20, 1],   # exploder
	30: [20, 0.25, 2],   # spitter
}

# ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Registrar managers globales — deben estar disponibles ANTES de que
	# cualquier arma o enemigo intente disparar/dañar.
	GameManager.enemy_manager      = enemy_manager
	GameManager.projectile_manager = projectile_manager

	spawn_manager.setup(enemy_manager)

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

	if is_instance_valid(player_ref):
		var current_enemies : int = enemy_manager.get_active_count()
		spawn_manager.update_spawner(delta, current_enemies,
									 player_ref.global_position, current_level)

# ════════════════════════════════════════════════════════════════
#  DROPS DE GEMA
# ════════════════════════════════════════════════════════════════

func _on_enemy_killed(pos: Vector2, points: int, _type_id: int) -> void:
	score += points * 100
	enemies_killed += 1
	_drop_gems(pos, points)

	if is_instance_valid(player_ref) and player_ref.is_alive:
		if player_ref.lifesteal_chance > 0.0:
			if randf() < player_ref.lifesteal_chance:
				player_ref.heal(player_ref.lifesteal)

		if "xp_on_kill_bonus" in player_ref and player_ref.xp_on_kill_bonus > 0:
			player_ref.gain_experience(player_ref.xp_on_kill_bonus)

func _drop_gems(pos: Vector2, points: int) -> void:
	var entry : Array = GEM_DROP_TABLE.get(points, [points, 0.15, 1])
	var xp_base    : int   = entry[0]
	var extra_prob : float = entry[1]
	var extra_max  : int   = entry[2]

	_spawn_gem(pos, xp_base)

	if extra_max > 0 and randf() < extra_prob:
		var extras   : int = randi_range(1, extra_max)
		var small_xp : int = maxi(1, int(xp_base * 0.3))
		for _i in range(extras):
			_spawn_gem(pos, small_xp)

func _spawn_gem(pos: Vector2, xp: int) -> void:
	gem_manager.spawn_gem(pos, xp)

# ════════════════════════════════════════════════════════════════
#  PANTALLA DE MEJORA
# ════════════════════════════════════════════════════════════════

func _on_player_leveled_up() -> void:
	if _upgrade_active:
		return
	_show_upgrade_screen()

func _show_upgrade_screen() -> void:
	if not is_instance_valid(player_ref):
		get_tree().paused = false
		return
	if player_ref.pending_level_ups <= 0:
		get_tree().paused = false
		return

	_upgrade_active   = true
	get_tree().paused = true

	var upgrade_packed := load("res://scenes/upgrade.tscn") as PackedScene
	if not upgrade_packed:
		push_error("gameplay.gd: no se encontró res://scenes/upgrade.tscn")
		get_tree().paused = false
		_upgrade_active   = false
		return

	var upgrade_node := upgrade_packed.instantiate()
	upgrade_layer.add_child(upgrade_node)
	upgrade_node.setup(player_ref)

	upgrade_node.upgrade_selected.connect(
		func() -> void:
			upgrade_node.queue_free()
			player_ref.pending_level_ups -= 1
			_upgrade_active = false

			if player_ref.pending_level_ups > 0:
				await get_tree().process_frame
				_show_upgrade_screen()
			else:
				get_tree().paused = false
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	)

# ════════════════════════════════════════════════════════════════
#  CALLBACKS DE JUGADOR
# ════════════════════════════════════════════════════════════════

func _on_player_died() -> void:
	game_over = true
	await get_tree().create_timer(1.2).timeout
	GameManager.goto_scene("res://scenes/game_over.tscn", {
		"score": score,
		"time":  _format_time(game_time),
	})

# ════════════════════════════════════════════════════════════════
#  HUD
# ════════════════════════════════════════════════════════════════

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.score         = score
	hud.enemies_killed = enemies_killed
	hud.wave_time_str = _format_time(game_time)

func _format_time(seconds: float) -> String:
	var m: int = floori(seconds / 60.0)
	var s: int = floori(fmod(seconds, 60.0))
	return "%02d:%02d" % [m, s]

func setup(_data: Dictionary) -> void:
	pass