extends Node
class_name SpawnManager

const SPAWN_RADIUS_MIN := 650.0
const SPAWN_RADIUS_MAX := 1100.0
const HARD_CAP         := 2000

@export var is_mobile: bool = false

var game_time:        float = 0.0
var spawn_timer:      float = 0.0
var difficulty_level: float = 1.0

# Referencia al EnemyManager (se asigna desde gameplay.gd o se busca en _ready)
var _enemy_manager: Node = null

func _ready() -> void:
	# Buscar EnemyManager (puede no estar listo en _ready, gameplay.gd lo asigna)
	_enemy_manager = get_tree().get_first_node_in_group("enemy_manager")

func setup(manager: Node) -> void:
	_enemy_manager = manager

func update_spawner(delta: float, current_enemy_count: int,
					player_pos: Vector2, player_level: int) -> void:
	game_time     += delta
	spawn_timer   -= delta

	var minutes         := game_time / 60.0
	difficulty_level     = 1.0 + (minutes * 0.15)

	# ── Cap dinámico ────────────────────────────────────────────
	var current_cap: int
	if is_mobile:
		if minutes < 3:       current_cap = int(20  + minutes * 8)
		elif minutes < 12:    current_cap = int(44  + (minutes - 3)  * 55)
		else:                 current_cap = int(539 + (minutes - 12) * 47)
	else:
		if minutes < 3:       current_cap = int(35   + minutes * 21)
		elif minutes < 12:    current_cap = int(98   + (minutes - 3)  * 155)
		else:                 current_cap = int(1493 + (minutes - 12) * 169)

	current_cap = mini(current_cap, HARD_CAP)

	if current_enemy_count >= current_cap or spawn_timer > 0:
		return

	var deficit := current_cap - current_enemy_count

	# ── Velocidad de spawn ───────────────────────────────────────
	if   deficit > 30: spawn_timer = 1.0 / 60.0
	elif deficit > 10: spawn_timer = maxf(1.0, 8.0 - minutes * 0.3) / 60.0
	else:              spawn_timer = maxf(1.0, 18.0 - minutes * 0.5) / 60.0

	# ── Tamaño del batch ─────────────────────────────────────────
	var batch := 1
	if   deficit > 50:  batch = randi_range(5,  12 + int(minutes * 1.5))
	elif deficit > 20:  batch = randi_range(3,   8 + int(minutes))
	elif minutes < 2:   batch = 1
	elif minutes < 5:   batch = randi_range(1, 3)
	elif minutes < 10:  batch = randi_range(2, 5)
	else:               batch = randi_range(3, 7)

	batch = mini(batch, deficit)
	if batch <= 0:
		return

	for _i in range(batch):
		_spawn_enemy(player_pos, player_level)

func _spawn_enemy(player_pos: Vector2, player_level: int) -> void:
	if not is_instance_valid(_enemy_manager):
		_enemy_manager = get_tree().get_first_node_in_group("enemy_manager")
		if not is_instance_valid(_enemy_manager):
			return

	var type_name        := _pick_enemy_type()
	var speed_mult       := minf(2.6, 1.0 + difficulty_level * 0.11)
	var time_health_mult := minf(4.5, 1.0 + (difficulty_level - 1.0) * 0.32)
	var level_factor     : int = max(0, player_level - 1)
	var health_mult      := minf(8.0, time_health_mult * (1.0 + level_factor * 0.05))
	var damage_mult      := 1.0 + level_factor * 0.04

	var pos := _get_spawn_position(player_pos)

	# ── Spawneamos directo en el pool — sin instanciar ningún nodo ──
	_enemy_manager.spawn(pos, type_name, speed_mult, health_mult, damage_mult)

func _get_spawn_position(player_pos: Vector2) -> Vector2:
	var angle  := randf() * PI * 2.0
	var radius := randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	return player_pos + Vector2(cos(angle), sin(angle)) * radius

func _pick_enemy_type() -> String:
	var minutes := game_time / 60.0
	var weights := {
		"small": 70, "normal": 30, "large": 0,
		"tank": 0, "exploder": 0, "spitter": 0
	}

	if minutes > 3:
		weights["normal"]   += 15
		weights["small"]    -= 15
		weights["exploder"] +=  5
	if minutes > 7:
		weights["large"]    += 15
		weights["spitter"]  +=  5
		weights["small"]    -= 20
	if minutes > 12:
		weights["tank"]     +=  5
		weights["large"]    +=  5
	if minutes > 18:
		weights["tank"]     += 10
		weights["exploder"] += 10

	var total_weight := 0
	for key in weights:
		weights[key] = maxi(0, weights[key])
		total_weight += weights[key]

	var roll    := randi() % maxi(1, total_weight)
	var current := 0
	for key in weights:
		current += weights[key]
		if roll < current:
			return key
	return "normal"