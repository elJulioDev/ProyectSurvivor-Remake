extends Node

# Equivalente a settings.py
const BASE_WIDTH  = 1280
const BASE_HEIGHT = 720
const WORLD_WIDTH  = 12000
const WORLD_HEIGHT = 9000

# Colores frecuentes
const COLOR_WHITE  = Color(1, 1, 1)
const COLOR_BLACK  = Color(0, 0, 0)
const COLOR_YELLOW = Color(1, 1, 0)
const COLOR_CYAN   = Color(0, 1, 1)

# Stats de jugador base
const PLAYER_SIZE     = 20
const PLAYER_SPEED    = 200.0   # px/s en Godot (tu 6 * 60 frames)
const PLAYER_ACCEL    = 1800.0
const PLAYER_FRICTION = 12.0    # para lerp de velocidad

const ENEMY_SIZE  = 25
const ENEMY_SPEED = 80.0        # tu 2 * 60 → ~120, ajusta en playtest

# Señal global para cambio de escena
signal scene_change_requested(scene_path: String, data: Dictionary)

var current_scene_node: Node = null

func goto_scene(path: String, data: Dictionary = {}) -> void:
	scene_change_requested.emit(path, data)
