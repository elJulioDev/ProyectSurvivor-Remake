extends Node
class_name SpawnManager

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  SpawnManager v5 — Cap reducido a 1000, ritmo ajustado VS-style

const HARD_CAP         := 1000   # era 2000 — cap máximo en pantalla
const SPAWNS_PER_FRAME :=    2
const FALLBACK_RADIUS_MIN := 1300.0
const FALLBACK_RADIUS_MAX := 1700.0
const VIEWPORT_MARGIN     :=  120.0
const TELEPORT_INTERVAL   :=    3.0

# ════════════════════════════════════════════════════════════════
#  TABLA DE OLEADAS
#  Quotas ajustadas para cap 1000 con ritmo VS (progresión más suave)
# ════════════════════════════════════════════════════════════════

const WAVE_MINUTES : Array[float] = [
    0.0, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 13.0, 17.0, 20.0, 23.0, 27.0
]

const WAVE_TABLE : Array[Dictionary] = [
    # ── Oleada 0 (0:00) ─ Tutorial muy suave ──────────────────────
    {
        "small":   {"quota": 12, "interval": 2.5},
        "normal":  {"quota":  4, "interval": 5.0},
    },
    # ── Oleada 1 (1:00) ───────────────────────────────────────────
    {
        "small":   {"quota": 18, "interval": 2.0},
        "normal":  {"quota":  8, "interval": 3.5},
        "exploder":{"quota":  2, "interval": 7.0},
    },
    # ── Oleada 2 (2:00) ───────────────────────────────────────────
    {
        "small":   {"quota": 24, "interval": 1.6},
        "normal":  {"quota": 12, "interval": 2.8},
        "exploder":{"quota":  4, "interval": 6.0},
    },
    # ── Oleada 3 (3:00) ───────────────────────────────────────────
    {
        "small":   {"quota": 30, "interval": 1.4},
        "normal":  {"quota": 15, "interval": 2.5},
        "large":   {"quota":  3, "interval": 9.0},
        "exploder":{"quota":  6, "interval": 5.0},
    },
    # ── Oleada 4 (5:00) ─ Spitter entra ───────────────────────────
    {
        "small":   {"quota": 36, "interval": 1.2},
        "normal":  {"quota": 18, "interval": 2.2},
        "large":   {"quota":  7, "interval": 7.0},
        "spitter": {"quota":  3, "interval": 8.0},
        "exploder":{"quota":  8, "interval": 4.5},
    },
    # ── Oleada 5 (7:00) ───────────────────────────────────────────
    {
        "small":   {"quota": 40, "interval": 1.0},
        "normal":  {"quota": 22, "interval": 2.0},
        "large":   {"quota": 12, "interval": 6.0},
        "spitter": {"quota":  6, "interval": 6.5},
        "exploder":{"quota": 10, "interval": 4.0},
    },
    # ── Oleada 6 (10:00) ─ Tank entra ─────────────────────────────
    {
        "small":   {"quota": 42, "interval": 1.0},
        "normal":  {"quota": 25, "interval": 1.8},
        "large":   {"quota": 18, "interval": 5.0},
        "spitter": {"quota": 10, "interval": 5.5},
        "exploder":{"quota": 12, "interval": 3.5},
        "tank":    {"quota":  2, "interval":18.0},
    },
    # ── Oleada 7 (13:00) ──────────────────────────────────────────
    {
        "small":   {"quota": 42, "interval": 1.0},
        "normal":  {"quota": 26, "interval": 1.5},
        "large":   {"quota": 22, "interval": 4.5},
        "spitter": {"quota": 13, "interval": 5.0},
        "exploder":{"quota": 14, "interval": 3.0},
        "tank":    {"quota":  3, "interval":15.0},
    },
    # ── Oleada 8 (17:00) ──────────────────────────────────────────
    {
        "small":   {"quota": 38, "interval": 1.1},
        "normal":  {"quota": 22, "interval": 1.5},
        "large":   {"quota": 28, "interval": 4.0},
        "spitter": {"quota": 16, "interval": 4.5},
        "exploder":{"quota": 18, "interval": 2.8},
        "tank":    {"quota":  5, "interval":12.0},
    },
    # ── Oleada 9 (20:00) ─ Caos controlado ────────────────────────
    {
        "small":   {"quota": 30, "interval": 1.2},
        "normal":  {"quota": 20, "interval": 1.5},
        "large":   {"quota": 40, "interval": 3.5},
        "spitter": {"quota": 20, "interval": 4.0},
        "exploder":{"quota": 20, "interval": 2.5},
        "tank":    {"quota":  8, "interval":10.0},
    },
    # ── Oleada 10 (23:00) ─────────────────────────────────────────
    {
        "small":   {"quota": 25, "interval": 1.3},
        "normal":  {"quota": 16, "interval": 1.5},
        "large":   {"quota": 48, "interval": 3.0},
        "spitter": {"quota": 24, "interval": 3.5},
        "exploder":{"quota": 24, "interval": 2.2},
        "tank":    {"quota": 11, "interval": 8.0},
    },
    # ── Oleada 11 (27:00) ─ Final ─────────────────────────────────
    {
        "small":   {"quota": 18, "interval": 1.5},
        "normal":  {"quota": 12, "interval": 1.5},
        "large":   {"quota": 55, "interval": 2.8},
        "spitter": {"quota": 28, "interval": 3.0},
        "exploder":{"quota": 28, "interval": 2.0},
        "tank":    {"quota": 14, "interval": 7.0},
    },
]

const TYPE_ID_TO_NAME : Dictionary = {
    0: "small", 1: "normal", 2: "large",
    3: "tank",  4: "exploder", 5: "spitter",
}

# ════════════════════════════════════════════════════════════════
#  ESTADO
# ════════════════════════════════════════════════════════════════

@export var is_mobile : bool = false

var curse_factor     : float = 1.0
var game_time        : float = 0.0
var difficulty_level : float = 1.0

var _spawn_queue    : Array = []
var _type_cooldowns : Dictionary = {}
var _player_pos     : Vector2 = Vector2.ZERO
var _player_vel     : Vector2 = Vector2.ZERO
var _teleport_timer : float   = 0.0
var _enemy_manager  : Node    = null

# ════════════════════════════════════════════════════════════════
#  INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
    _enemy_manager = get_tree().get_first_node_in_group("enemy_manager")
    for key in ["small", "normal", "large", "tank", "exploder", "spitter"]:
        _type_cooldowns[key] = 0.0

func setup(manager: Node) -> void:
    _enemy_manager = manager

# ════════════════════════════════════════════════════════════════
#  UPDATE
# ════════════════════════════════════════════════════════════════

func update_spawner(delta: float, current_enemy_count: int,
                    player_pos: Vector2, player_level: int) -> void:
    game_time  += delta
    _player_pos = player_pos

    var player := get_tree().get_first_node_in_group("player")
    if is_instance_valid(player) and "velocity" in player:
        _player_vel = player.velocity

    difficulty_level = 1.0 + (game_time / 60.0) * 0.15

    _teleport_timer += delta
    if _teleport_timer >= TELEPORT_INTERVAL:
        _teleport_timer = 0.0
        if is_instance_valid(_enemy_manager):
            _enemy_manager.teleport_distant(player_pos, _player_vel)

    var minutes     := game_time / 60.0
    var current_cap := mini(int(_calc_base_cap(minutes) * curse_factor), HARD_CAP)
    var quotas      := _get_interpolated_quotas(minutes)

    for key in _type_cooldowns:
        _type_cooldowns[key] = maxf(0.0, _type_cooldowns[key] - delta)

    var active_counts : Dictionary = {}
    if is_instance_valid(_enemy_manager):
        active_counts = _enemy_manager.get_all_type_counts()

    if current_enemy_count < current_cap:
        var remaining_capacity := current_cap - current_enemy_count
        for type_name in quotas:
            if remaining_capacity <= 0: break
            var q_data   : Dictionary = quotas[type_name]
            var quota    : int        = int(q_data["quota"] * curse_factor)
            var interval : float      = q_data["interval"]
            if _type_cooldowns.get(type_name, 0.0) > 0.0: continue
            var active_of_type : int = active_counts.get(type_name, 0)
            var deficit        : int = quota - active_of_type
            var to_queue           := mini(deficit, remaining_capacity)
            if to_queue <= 0: continue
            for _i in range(to_queue):
                _spawn_queue.append({"type": type_name, "level": player_level})
                remaining_capacity -= 1
            _type_cooldowns[type_name] = interval

    var spawned := 0
    while _spawn_queue.size() > 0 \
            and spawned < SPAWNS_PER_FRAME \
            and current_enemy_count + spawned < current_cap:
        var entry : Dictionary = _spawn_queue.pop_front()
        _do_spawn(entry["type"], entry["level"])
        spawned += 1

# ════════════════════════════════════════════════════════════════
#  SPAWN INDIVIDUAL
# ════════════════════════════════════════════════════════════════

func _do_spawn(type_name: String, player_level: int) -> void:
    if not is_instance_valid(_enemy_manager):
        _enemy_manager = get_tree().get_first_node_in_group("enemy_manager")
        if not is_instance_valid(_enemy_manager): return

    # Escalado de dificultad — velocidad limitada para feel VS
    var speed_mult       : float = minf(2.2, 1.0 + difficulty_level * 0.09)  # era 2.8/0.11
    var time_health_mult : float = minf(5.5, 1.0 + (difficulty_level - 1.0) * 0.32)
    var level_factor     : int   = maxi(0, player_level - 1)
    var health_mult      : float = minf(10.0, time_health_mult * (1.0 + float(level_factor) * 0.05))
    var damage_mult      : float = 1.0 + float(level_factor) * 0.04

    var pos := _get_spawn_position()
    _enemy_manager.spawn(pos, type_name, speed_mult, health_mult, damage_mult)

# ════════════════════════════════════════════════════════════════
#  POSICIÓN DE SPAWN
# ════════════════════════════════════════════════════════════════

func _get_spawn_position() -> Vector2:
    var viewport : Viewport = get_viewport()
    var cam      : Camera2D = viewport.get_camera_2d()

    var spawn_center : Vector2
    var half_x       : float
    var half_y       : float

    if is_instance_valid(cam):
        var zoom    : Vector2 = cam.zoom
        var vp_size : Vector2 = viewport.get_visible_rect().size
        half_x = (vp_size.x / zoom.x) * 0.5 + VIEWPORT_MARGIN
        half_y = (vp_size.y / zoom.y) * 0.5 + VIEWPORT_MARGIN
        spawn_center = cam.get_screen_center_position()
    else:
        var angle  := randf() * TAU
        var radius := randf_range(FALLBACK_RADIUS_MIN, FALLBACK_RADIUS_MAX)
        return _clamp_to_world(_player_pos + Vector2(cos(angle), sin(angle)) * radius)

    var moving := _player_vel.length_squared() > 400.0
    var fwd    := _player_vel.normalized() if moving else Vector2.ZERO

    var side : int
    if moving:
        var roll := randf()
        if roll < 0.50:   side = _fwd_side(fwd)
        elif roll < 0.75: side = (_fwd_side(fwd) + 1) % 4
        else:             side = (_fwd_side(fwd) + 3) % 4
    else:
        side = randi() % 4

    var pos : Vector2
    match side:
        0: pos = Vector2(spawn_center.x + randf_range(-half_x, half_x), spawn_center.y - half_y)
        1: pos = Vector2(spawn_center.x + half_x, spawn_center.y + randf_range(-half_y, half_y))
        2: pos = Vector2(spawn_center.x + randf_range(-half_x, half_x), spawn_center.y + half_y)
        _: pos = Vector2(spawn_center.x - half_x, spawn_center.y + randf_range(-half_y, half_y))

    return _clamp_to_world(pos)

func _fwd_side(dir: Vector2) -> int:
    var angle := dir.angle()
    if angle >= -PI * 0.25 and angle < PI * 0.25:  return 1
    if angle >= PI * 0.25  and angle < PI * 0.75:  return 2
    if angle >= -PI * 0.75 and angle < -PI * 0.25: return 0
    return 3

func _clamp_to_world(pos: Vector2) -> Vector2:
    const MARGIN := 50.0
    return Vector2(
        clampf(pos.x, -MARGIN, GameManager.WORLD_WIDTH  + MARGIN),
        clampf(pos.y, -MARGIN, GameManager.WORLD_HEIGHT + MARGIN)
    )

# ════════════════════════════════════════════════════════════════
#  QUOTAS INTERPOLADAS
# ════════════════════════════════════════════════════════════════

func _get_interpolated_quotas(minutes: float) -> Dictionary:
    var curr_idx := 0
    for i in range(WAVE_MINUTES.size()):
        if minutes >= WAVE_MINUTES[i]: curr_idx = i

    var next_idx := mini(curr_idx + 1, WAVE_TABLE.size() - 1)
    if curr_idx == next_idx: return WAVE_TABLE[curr_idx]

    var t_start := WAVE_MINUTES[curr_idx]
    var t_end   := WAVE_MINUTES[next_idx]
    var t       := clampf((minutes - t_start) / (t_end - t_start), 0.0, 1.0)

    var curr_wave : Dictionary = WAVE_TABLE[curr_idx]
    var next_wave : Dictionary = WAVE_TABLE[next_idx]
    var result    : Dictionary = {}
    var all_keys  := {}
    for key in curr_wave: all_keys[key] = true
    for key in next_wave: all_keys[key] = true

    for key in all_keys:
        var curr_q   := float(curr_wave.get(key, {}).get("quota",    0))
        var curr_int := float(curr_wave.get(key, {}).get("interval", 5.0))
        var next_q   := float(next_wave.get(key, {}).get("quota",    curr_q))
        var next_int := float(next_wave.get(key, {}).get("interval", curr_int))
        result[key]  = {
            "quota":    int(lerp(curr_q,   next_q,   t)),
            "interval": lerp(curr_int, next_int, t),
        }
    return result

# ════════════════════════════════════════════════════════════════
#  CAP DINÁMICO — máximo 1000 enemigos
# ════════════════════════════════════════════════════════════════

func _calc_base_cap(minutes: float) -> float:
    if is_mobile:
        if minutes < 3.0:    return 15.0  + minutes * 6.0
        elif minutes < 12.0: return 33.0  + (minutes - 3.0)  * 40.0
        elif minutes < 22.0: return 393.0 + (minutes - 12.0) * 35.0
        else:                return 743.0 + (minutes - 22.0) * 25.0
    else:
        if minutes < 3.0:    return  25.0  + minutes * 16.0
        elif minutes < 12.0: return  73.0  + (minutes - 3.0)  * 100.0
        elif minutes < 22.0: return 973.0  + (minutes - 12.0) * 2.7  # se estabiliza cerca de 1000
        else:                return 1000.0  # cap máximo fijo los últimos minutos

# ════════════════════════════════════════════════════════════════
#  API PÚBLICA
# ════════════════════════════════════════════════════════════════

func set_curse(value: float) -> void:  curse_factor = clampf(value, 1.0, 4.0)
func get_minutes() -> float:           return game_time / 60.0
func clear_queue() -> void:            _spawn_queue.clear()

func force_wave(wave_index: int) -> void:
    if wave_index >= 0 and wave_index < WAVE_TABLE.size():
        game_time = WAVE_MINUTES[wave_index] * 60.0