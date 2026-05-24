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

# ── Referencias a Managers (se asignan en gameplay.gd) ───────────────────
var enemy_manager      : Node = null
var projectile_manager : Node = null   # ProjectileManager DOD

# Señal global para cambio de escena
signal scene_change_requested(scene_path: String, data: Dictionary)
var current_scene_node: Node = null

## Personaje seleccionado antes de entrar a gameplay.
## Se asigna en character_select.gd y se lee en player.gd._ready()
var selected_character : CharacterData = null

## Carga un personaje por su ID desde la carpeta estándar.
## Útil para fallback si character_select no fue visitado.
func get_or_default_character() -> CharacterData:
	if is_instance_valid(selected_character):
		return selected_character
	# Fallback: carga el Soldado por defecto para no romper el flujo
	var fallback_path := "res://entities/characters/Soldier.tres"
	if ResourceLoader.exists(fallback_path):
		return load(fallback_path) as CharacterData
	push_error("GameManager: No hay personaje seleccionado y no existe Soldier.tres")
	return null

func goto_scene(path: String, data: Dictionary = {}) -> void:
	scene_change_requested.emit(path, data)

# ── Helper para que las armas obtengan enemigos cercanos ─────────────────
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

# --- MODO DEBUG MÓVIL ---
# Cambia esto a "true" para probar la interfaz de Android/iOS en PC.
var force_mobile_mode: bool = false 

func is_mobile() -> bool:
	if force_mobile_mode:
		return true
	# OS.has_feature("mobile") es la forma oficial y más robusta en Godot 4 para exportaciones
	return OS.get_name() in ["Android", "iOS"] or OS.has_feature("mobile")