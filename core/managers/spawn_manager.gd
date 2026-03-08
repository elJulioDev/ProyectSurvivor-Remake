extends Node
class_name SpawnManager

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  SpawnManager v2 — portado completo de spawn_manager.py
##
##  Cambios respecto a v1:
##
##    1. Teleportación periódica de enemigos lejanos (cada 3 s).
##       Llama a EnemyManager.teleport_distant() para reubicar
##       cualquier enemigo a más de 1050 px del jugador hacia una
##       nueva posición de spawn.  Evita que el CPU procese físicas
##       de cientos de enemigos que nunca llegarán a la pantalla.
##
##    2. _pick_enemy_type() con los 5 umbrales temporales del original
##       Python (3, 7, 13, 20, 25 min) en lugar de los 4 de v1.
##       Esto produce una curva de dificultad más suave y correcta.
##
##    3. damage_mult escala con nivel del jugador (igual que Python):
##       +4 % daño por nivel desde el 2.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const SPAWN_RADIUS_MIN := 1300.0
const SPAWN_RADIUS_MAX := 1700.0
const HARD_CAP         := 2000

## Intervalo en segundos entre llamadas a teleport_distant.
## Valor bajo → más CPU en el teleport.  Valor alto → más enemigos
## fantasma fuera de pantalla.  3 s es el equilibrio óptimo.
const TELEPORT_INTERVAL := 3.0

@export var is_mobile: bool = false

var game_time        : float = 0.0
var spawn_timer      : float = 0.0
var difficulty_level : float = 1.0

## Timer para la teleportación periódica de enemigos lejanos
var _teleport_timer  : float = 0.0

var _enemy_manager: Node = null

func _ready() -> void:
	_enemy_manager = get_tree().get_first_node_in_group("enemy_manager")

func setup(manager: Node) -> void:
	_enemy_manager = manager

func update_spawner(delta: float, current_enemy_count: int,
					player_pos: Vector2, player_level: int) -> void:
	game_time    += delta
	spawn_timer  -= delta

	# ── Teleportación periódica de enemigos lejanos ──────────────
	_teleport_timer += delta
	if _teleport_timer >= TELEPORT_INTERVAL:
		_teleport_timer = 0.0
		if is_instance_valid(_enemy_manager) and \
				_enemy_manager.has_method("teleport_distant"):
			_enemy_manager.teleport_distant(player_pos)

	var minutes         := game_time / 60.0
	difficulty_level     = 1.0 + (minutes * 0.15)

	# ── Cap dinámico ─────────────────────────────────────────────
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

	# ── Velocidad de spawn ────────────────────────────────────────
	if   deficit > 30: spawn_timer = 1.0 / 60.0
	elif deficit > 10: spawn_timer = maxf(1.0, 8.0 - minutes * 0.3) / 60.0
	else:              spawn_timer = maxf(1.0, 18.0 - minutes * 0.5) / 60.0

	# ── Tamaño del batch ──────────────────────────────────────────
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

	# Escala temporal de vida
	var time_health_mult := minf(4.5, 1.0 + (difficulty_level - 1.0) * 0.32)

	# Escala por nivel del jugador — portado de spawn_manager.py:
	#   level_factor = max(0, player_level - 1)
	#   +5 % HP y +4 % daño por cada nivel a partir del 2
	var level_factor     : int = max(0, player_level - 1)
	var health_mult      := minf(8.0, time_health_mult * (1.0 + level_factor * 0.05))
	var damage_mult      := 1.0 + level_factor * 0.04

	var pos := _get_spawn_position(player_pos)
	_enemy_manager.spawn(pos, type_name, speed_mult, health_mult, damage_mult)

func _get_spawn_position(player_pos: Vector2) -> Vector2:
	var angle: float
	var radius: float
	
	# 15 intentos para encontrar una posición dentro del mundo
	for _i in range(15):
		angle  = randf() * PI * 2.0
		radius = randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
		var x := player_pos.x + cos(angle) * radius
		var y := player_pos.y + sin(angle) * radius
		if x >= -250.0 and x <= GameManager.WORLD_WIDTH + 250.0 \
				and y >= -250.0 and y <= GameManager.WORLD_HEIGHT + 250.0:
			return Vector2(x, y)
			
	# Fallback: spawn sin restricción de mundo
	angle  = randf() * PI * 2.0
	radius = randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	return player_pos + Vector2(cos(angle), sin(angle)) * radius

## Portado completo de spawn_manager.py con los 5 umbrales temporales:
## 3 min → más normal + exploder
## 7 min → large + spitter entran
## 13 min → spitter + exploder + large escalan, normal cae
## 20 min → tank + large dominan, small desaparece
## 25 min → tank + exploder se vuelven comunes
func _pick_enemy_type() -> String:
	var minutes := game_time / 60.0

	var weights := {
		"small":    70,
		"normal":   30,
		"large":     0,
		"tank":      0,
		"exploder":  0,
		"spitter":   0,
	}

	if minutes > 3:
		weights["normal"]   += 15
		weights["small"]    -= 15
		weights["exploder"] +=  5

	if minutes > 7:
		weights["large"]    += 15
		weights["spitter"]  +=  5
		weights["small"]    -= 20

	if minutes > 13:
		weights["spitter"]  += 10
		weights["exploder"] +=  5
		weights["large"]    += 10
		weights["normal"]   -= 15

	if minutes > 20:
		weights["tank"]     +=  5
		weights["large"]    += 10
		weights["small"]     =  0

	if minutes > 25:
		weights["tank"]     += 10
		weights["exploder"] +=  5
		weights["normal"]   -= 10

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