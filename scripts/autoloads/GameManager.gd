extends Node

# Equivalente a settings.py
const BASE_WIDTH   = 1280
const BASE_HEIGHT  = 720
const WORLD_WIDTH  = 12000
const WORLD_HEIGHT = 9000

# Colores frecuentes
const COLOR_WHITE  = Color(1, 1, 1)
const COLOR_BLACK  = Color(0, 0, 0)
const COLOR_YELLOW = Color(1, 1, 0)
const COLOR_CYAN   = Color(0, 1, 1)

# Stats de jugador base
const PLAYER_SIZE     = 20
const PLAYER_SPEED    = 200.0
const PLAYER_ACCEL    = 1800.0
const PLAYER_FRICTION = 12.0

const ENEMY_SIZE  = 25
const ENEMY_SPEED = 80.0

# ── Referencia al EnemyManager (se asigna en gameplay.gd) ────────
var enemy_manager : Node = null

# Señal global para cambio de escena
signal scene_change_requested(scene_path: String, data: Dictionary)
var current_scene_node: Node = null

func goto_scene(path: String, data: Dictionary = {}) -> void:
	scene_change_requested.emit(path, data)

# ── Helper para que las armas obtengan enemigos cercanos ──────────
## Devuelve proxies de enemigos dentro del radio dado.
## Drop-in replacement de get_tree().get_nodes_in_group("enemies")
## pero usando el spatial hash del EnemyManager → O(1) en lugar de O(n).
func get_enemies_in_radius(pos: Vector2, radius: float) -> Array:
	if is_instance_valid(enemy_manager):
		return enemy_manager.get_enemies_near_proxy(pos, radius)
	return []

## Índice del enemigo más cercano (para player.gd).
func get_nearest_enemy_idx(pos: Vector2, max_r: float = 900.0) -> int:
	if is_instance_valid(enemy_manager):
		return enemy_manager.get_nearest_idx(pos, max_r)
	return -1

## Posición del enemigo más cercano (Vector2.ZERO si no hay ninguno).
func get_nearest_enemy_pos(pos: Vector2, max_r: float = 900.0) -> Vector2:
	if is_instance_valid(enemy_manager):
		var idx : float = enemy_manager.get_nearest_idx(pos, max_r)
		if idx >= 0:
			return enemy_manager.get_pos(idx)
	return Vector2.ZERO