extends Node
class_name SpawnManager

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  SpawnManager v3 — Sistema de Oleadas estilo Vampire Survivors
##
##  ARQUITECTURA CORE (igual que VS):
##
##  1. WAVE TABLE con QUOTAS por minuto
##     Cada oleada define un mínimo de cada tipo que DEBE estar vivo.
##     No es generación aleatoria infinita, es una lista guionada.
##
##  2. QUOTA REPLENISHMENT
##     En cuanto muere un enemigo y baja del quota, el sistema
##     encola un reemplazo inmediatamente. Así siempre hay presión.
##
##  3. SPAWN SECUENCIAL (cola de frames)
##     Los enemigos se instancian de 1 en 1 por frame (configurable).
##     Evita los freezes de "batch de 50 en un solo frame".
##
##  4. SPAWN EN BORDES DEL VIEWPORT
##     Los enemigos aparecen justo fuera del área visible, no en un
##     radio fijo. Con sesgo direccional si el jugador se mueve.
##
##  5. CURSE FACTOR
##     Multiplica quotas y cap global. Sube con el tiempo o con
##     ítems de maldición. Equivalente 1:1 al atributo Curse de VS.
##
##  INTEGRACIÓN:
##     En gameplay.gd → spawn_manager.setup(enemy_manager)
##     Cada frame     → spawn_manager.update_spawner(delta, player)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ════════════════════════════════════════════════════════════════
#  CONFIGURACIÓN GLOBAL
# ════════════════════════════════════════════════════════════════

## Cap máximo absoluto (ni con Curse puede superarse)
const HARD_CAP := 2000

## Cuántos enemigos se instancian por frame como máximo.
## 1–2 es ideal: sin freeze, densidad sube suavemente.
const SPAWNS_PER_FRAME := 2

## Radio mínimo/máximo cuando NO hay cámara disponible (fallback)
const FALLBACK_RADIUS_MIN := 1300.0
const FALLBACK_RADIUS_MAX := 1700.0

## Margen en píxeles fuera del viewport donde aparecen los enemigos
const VIEWPORT_MARGIN := 120.0

## Intervalo de teleport de enemigos rezagados (segundos)
const TELEPORT_INTERVAL := 3.0

# ════════════════════════════════════════════════════════════════
#  TABLA DE OLEADAS
##
##  Cada entrada corresponde a un minuto de juego.
##  "quota"    → mínimo de este tipo que debe estar vivo a la vez.
##  "interval" → segundos entre intentos de spawn de este tipo.
##               (protege contra spikes si mueren en masa)
##
##  Las quotas se ACUMULAN linealmente entre oleadas para
##  evitar saltos bruscos. Ver _get_interpolated_quotas().
# ════════════════════════════════════════════════════════════════

## Minutos en que COMIENZA cada oleada (mismo índice que WAVE_TABLE)
const WAVE_MINUTES : Array[float] = [
	0.0, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 13.0, 17.0, 20.0
]

const WAVE_TABLE : Array[Dictionary] = [
	# ── Oleada 0 (0:00) ────────────────────────────────────────
	{
		"small":   {"quota": 15, "interval": 2.0},
		"normal":  {"quota":  5, "interval": 4.0},
	},
	# ── Oleada 1 (1:00) ────────────────────────────────────────
	{
		"small":   {"quota": 22, "interval": 1.6},
		"normal":  {"quota": 10, "interval": 3.0},
		"exploder":{"quota":  3, "interval": 6.0},
	},
	# ── Oleada 2 (2:00) ────────────────────────────────────────
	{
		"small":   {"quota": 30, "interval": 1.3},
		"normal":  {"quota": 14, "interval": 2.5},
		"exploder":{"quota":  6, "interval": 5.0},
	},
	# ── Oleada 3 (3:00) ────────────────────────────────────────
	{
		"small":   {"quota": 38, "interval": 1.1},
		"normal":  {"quota": 18, "interval": 2.0},
		"large":   {"quota":  4, "interval": 8.0},
		"exploder":{"quota":  8, "interval": 4.5},
	},
	# ── Oleada 4 (5:00) ────────────────────────────────────────
	{
		"small":   {"quota": 45, "interval": 0.9},
		"normal":  {"quota": 22, "interval": 1.8},
		"large":   {"quota":  9, "interval": 6.0},
		"spitter": {"quota":  4, "interval": 7.0},
		"exploder":{"quota": 10, "interval": 4.0},
	},
	# ── Oleada 5 (7:00) ────────────────────────────────────────
	{
		"small":   {"quota": 50, "interval": 0.8},
		"normal":  {"quota": 26, "interval": 1.5},
		"large":   {"quota": 15, "interval": 5.0},
		"spitter": {"quota":  8, "interval": 5.5},
		"exploder":{"quota": 12, "interval": 3.5},
	},
	# ── Oleada 6 (10:00) ───────────────────────────────────────
	{
		"small":   {"quota": 55, "interval": 0.7},
		"normal":  {"quota": 30, "interval": 1.2},
		"large":   {"quota": 22, "interval": 4.0},
		"spitter": {"quota": 12, "interval": 4.5},
		"exploder":{"quota": 15, "interval": 3.0},
		"tank":    {"quota":  2, "interval":15.0},
	},
	# ── Oleada 7 (13:00) ───────────────────────────────────────
	{
		"small":   {"quota": 55, "interval": 0.7},
		"normal":  {"quota": 32, "interval": 1.0},
		"large":   {"quota": 28, "interval": 3.5},
		"spitter": {"quota": 16, "interval": 4.0},
		"exploder":{"quota": 18, "interval": 2.5},
		"tank":    {"quota":  4, "interval":12.0},
	},
	# ── Oleada 8 (17:00) ───────────────────────────────────────
	{
		"small":   {"quota": 50, "interval": 0.8},
		"normal":  {"quota": 28, "interval": 1.0},
		"large":   {"quota": 35, "interval": 3.0},
		"spitter": {"quota": 20, "interval": 3.5},
		"exploder":{"quota": 22, "interval": 2.2},
		"tank":    {"quota":  6, "interval":10.0},
	},
	# ── Oleada 9 (20:00+) ──────────────────────────────────────
	{
		"small":   {"quota": 40, "interval": 0.9},
		"normal":  {"quota": 25, "interval": 1.0},
		"large":   {"quota": 50, "interval": 2.5},
		"spitter": {"quota": 25, "interval": 3.0},
		"exploder":{"quota": 25, "interval": 1.8},
		"tank":    {"quota": 10, "interval": 8.0},
	},
]

# ════════════════════════════════════════════════════════════════
#  ID → nombre de tipo (para contar activos en EnemyManager)
# ════════════════════════════════════════════════════════════════

const TYPE_ID_TO_NAME : Dictionary = {
	0: "small",
	1: "normal",
	2: "large",
	3: "tank",
	4: "exploder",
	5: "spitter",
}

# ════════════════════════════════════════════════════════════════
#  ESTADO
# ════════════════════════════════════════════════════════════════

@export var is_mobile : bool = false

## Factor de maldición (Curse). 1.0 = normal.
## Aumentarlo sube quotas y cap. Conéctalo a ítems del jugador.
var curse_factor : float = 1.0

var game_time       : float = 0.0
var difficulty_level: float = 1.0

## Cola de spawns pendientes. Cada entrada: {"type": String, "level": int}
var _spawn_queue : Array = []

## Timers por tipo — evita rafagas de replenishment tras una limpieza masiva
var _type_cooldowns : Dictionary = {}

## Cache de posición / velocidad del jugador
var _player_pos : Vector2 = Vector2.ZERO
var _player_vel : Vector2 = Vector2.ZERO

var _teleport_timer : float = 0.0
var _enemy_manager  : Node  = null

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
#  UPDATE PRINCIPAL — llamar desde gameplay.gd cada frame
# ════════════════════════════════════════════════════════════════

func update_spawner(delta: float, current_enemy_count: int,
					player_pos: Vector2, player_level: int) -> void:
	game_time += delta
	_player_pos = player_pos

	# Cachear velocidad del jugador para sesgo de spawn direccional
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "velocity" in player:
		_player_vel = player.velocity

	difficulty_level = 1.0 + (game_time / 60.0) * 0.15

	# ── Teleport periódico de rezagados ────────────────────────
	_teleport_timer += delta
	if _teleport_timer >= TELEPORT_INTERVAL:
		_teleport_timer = 0.0
		if is_instance_valid(_enemy_manager):
			_enemy_manager.teleport_distant(player_pos, _player_vel)

	# ── Cap dinámico con Curse ──────────────────────────────────
	var minutes     := game_time / 60.0
	var current_cap := mini(int(_calc_base_cap(minutes) * curse_factor), HARD_CAP)

	# ── Construir quotas interpoladas para el minuto actual ─────
	var quotas := _get_interpolated_quotas(minutes)

	# ── Decrementar cooldowns por tipo ─────────────────────────
	for key in _type_cooldowns:
		_type_cooldowns[key] = maxf(0.0, _type_cooldowns[key] - delta)

	# ── Obtener conteos activos por tipo (O(n) single pass) ─────
	var active_counts : Dictionary = {}
	if is_instance_valid(_enemy_manager):
		active_counts = _enemy_manager.get_all_type_counts()

	# ── Encolar spawns para cubrir deficit de cada tipo ─────────
	if current_enemy_count < current_cap:
		var remaining_capacity := current_cap - current_enemy_count
		for type_name in quotas:
			if remaining_capacity <= 0:
				break

			var q_data    : Dictionary = quotas[type_name]
			var quota     : int        = int(q_data["quota"] * curse_factor)
			var interval  : float      = q_data["interval"]

			# Cooldown de spawn por tipo (anti-burst)
			if _type_cooldowns.get(type_name, 0.0) > 0.0:
				continue

			var active_of_type : int = active_counts.get(type_name, 0)
			var deficit        : int = quota - active_of_type

			# Encolar hasta cubrir el deficit (respetando capacidad global)
			var to_queue := mini(deficit, remaining_capacity)
			if to_queue <= 0:
				continue

			# Encolar de golpe pero con separación temporal via cooldown
			for _i in range(to_queue):
				_spawn_queue.append({"type": type_name, "level": player_level})
				remaining_capacity -= 1

			# Activar cooldown para este tipo
			_type_cooldowns[type_name] = interval

	# ── Procesar cola: SPAWNS_PER_FRAME por frame ───────────────
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
		if not is_instance_valid(_enemy_manager):
			return

	# Variables tipadas estrictamente para evitar errores del compilador
	var speed_mult: float       = minf(2.6, 1.0 + difficulty_level * 0.11)
	var time_health_mult: float = minf(4.5, 1.0 + (difficulty_level - 1.0) * 0.32)
	var level_factor: int       = maxi(0, player_level - 1)
	var health_mult: float      = minf(8.0, time_health_mult * (1.0 + float(level_factor) * 0.05))
	var damage_mult: float      = 1.0 + float(level_factor) * 0.04

	var pos := _get_spawn_position()
	_enemy_manager.spawn(pos, type_name, speed_mult, health_mult, damage_mult)

# ════════════════════════════════════════════════════════════════
#  POSICIÓN DE SPAWN — bordes del viewport (estilo VS real)
# ════════════════════════════════════════════════════════════════

## VS spawna enemigos JUSTO fuera del área visible, no en radio fijo.
## Con sesgo direccional: si el jugador se mueve, más enemigos aparecen
## por delante y los lados (como en el juego original).
func _get_spawn_position() -> Vector2:
	# Tipado estricto para las dimensiones del viewport y cámara
	var viewport: Viewport = Engine.get_main_loop().root.get_viewport()
	var cam: Camera2D      = viewport.get_camera_2d()

	var half_x: float
	var half_y: float

	if is_instance_valid(cam):
		var zoom: Vector2    = cam.zoom
		var vp_size: Vector2 = viewport.get_visible_rect().size
		half_x = (vp_size.x / zoom.x) * 0.5 + VIEWPORT_MARGIN
		half_y = (vp_size.y / zoom.y) * 0.5 + VIEWPORT_MARGIN
	else:
		# Fallback si no hay cámara
		var angle  := randf() * TAU
		var radius := randf_range(FALLBACK_RADIUS_MIN, FALLBACK_RADIUS_MAX)
		return _clamp_to_world(_player_pos + Vector2(cos(angle), sin(angle)) * radius)

	# Sesgo direccional: más peso al frente del jugador
	var moving := _player_vel.length_squared() > 400.0
	var fwd    := _player_vel.normalized() if moving else Vector2.ZERO

	# Elegir borde con peso (frente = 50%, lados = 25% cada uno, atrás = 0%)
	var side : int
	if moving:
		var roll := randf()
		if roll < 0.50:
			side = _fwd_side(fwd)        # borde frontal
		elif roll < 0.75:
			side = (_fwd_side(fwd) + 1) % 4  # borde lateral derecho
		else:
			side = (_fwd_side(fwd) + 3) % 4  # borde lateral izquierdo
	else:
		side = randi() % 4  # circular cuando está quieto

	var pos : Vector2
	match side:
		0: # arriba
			pos = Vector2(
				_player_pos.x + randf_range(-half_x, half_x),
				_player_pos.y - half_y
			)
		1: # derecha
			pos = Vector2(
				_player_pos.x + half_x,
				_player_pos.y + randf_range(-half_y, half_y)
			)
		2: # abajo
			pos = Vector2(
				_player_pos.x + randf_range(-half_x, half_x),
				_player_pos.y + half_y
			)
		_: # izquierda
			pos = Vector2(
				_player_pos.x - half_x,
				_player_pos.y + randf_range(-half_y, half_y)
			)

	return _clamp_to_world(pos)

## Convierte un vector de dirección en el índice de borde (0=top 1=right 2=bottom 3=left)
func _fwd_side(dir: Vector2) -> int:
	var angle := dir.angle()  # -PI..PI
	# Mapear a 0–3: derecha=0, abajo=1, izquierda=2, arriba=3 → reordenar a top/right/bottom/left
	if angle >= -PI * 0.25 and angle < PI * 0.25:   return 1  # derecha
	if angle >= PI * 0.25  and angle < PI * 0.75:   return 2  # abajo
	if angle >= -PI * 0.75 and angle < -PI * 0.25:  return 0  # arriba
	return 3                                                    # izquierda

func _clamp_to_world(pos: Vector2) -> Vector2:
	# Pequeño margen para no spawnear exactamente en el borde del mundo
	const MARGIN := 50.0
	return Vector2(
		clampf(pos.x, -MARGIN, GameManager.WORLD_WIDTH  + MARGIN),
		clampf(pos.y, -MARGIN, GameManager.WORLD_HEIGHT + MARGIN)
	)

# ════════════════════════════════════════════════════════════════
#  CÁLCULO DE QUOTAS INTERPOLADAS
# ════════════════════════════════════════════════════════════════

## Devuelve las quotas suavizadas entre la oleada actual y la siguiente.
## Esto evita saltos bruscos de "de repente 20 tanques al minuto 10".
func _get_interpolated_quotas(minutes: float) -> Dictionary:
	# Encontrar índice de oleada actual y siguiente
	var curr_idx := 0
	for i in range(WAVE_MINUTES.size()):
		if minutes >= WAVE_MINUTES[i]:
			curr_idx = i

	var next_idx := mini(curr_idx + 1, WAVE_TABLE.size() - 1)

	if curr_idx == next_idx:
		return WAVE_TABLE[curr_idx]

	# Factor de interpolación entre oleada actual y siguiente
	var t_start := WAVE_MINUTES[curr_idx]
	var t_end   := WAVE_MINUTES[next_idx]
	var t       := clampf((minutes - t_start) / (t_end - t_start), 0.0, 1.0)

	var curr_wave : Dictionary = WAVE_TABLE[curr_idx]
	var next_wave : Dictionary = WAVE_TABLE[next_idx]

	var result : Dictionary = {}

	# Combinar todas las claves de ambas oleadas
	var all_keys := {}
	for key in curr_wave: all_keys[key] = true
	for key in next_wave: all_keys[key] = true

	for key in all_keys:
		var curr_q    := float(curr_wave.get(key, {}).get("quota",    0))
		var curr_int  := float(curr_wave.get(key, {}).get("interval", 5.0))
		var next_q    := float(next_wave.get(key, {}).get("quota",    curr_q))
		var next_int  := float(next_wave.get(key, {}).get("interval", curr_int))

		result[key] = {
			"quota":    int(lerp(curr_q,   next_q,   t)),
			"interval": lerp(curr_int, next_int, t),
		}

	return result

# ════════════════════════════════════════════════════════════════
#  CAP DINÁMICO
# ════════════════════════════════════════════════════════════════

func _calc_base_cap(minutes: float) -> float:
	if is_mobile:
		if minutes < 3.0:  return 20.0  + minutes * 8.0
		elif minutes < 12: return 44.0  + (minutes - 3.0)  * 55.0
		else:              return 539.0 + (minutes - 12.0) * 47.0
	else:
		if minutes < 3.0:  return 35.0   + minutes * 21.0
		elif minutes < 12: return 98.0   + (minutes - 3.0)  * 155.0
		else:              return 1493.0 + (minutes - 12.0) * 169.0

# ════════════════════════════════════════════════════════════════
#  API PÚBLICA
# ════════════════════════════════════════════════════════════════

## Multiplica la dificultad vía Curse (ítems, mapa, etc.)
func set_curse(value: float) -> void:
	curse_factor = clampf(value, 1.0, 4.0)

## Fuerza una oleada concreta (útil para eventos especiales / jefes)
func force_wave(wave_index: int) -> void:
	if wave_index >= 0 and wave_index < WAVE_TABLE.size():
		var target_minute := WAVE_MINUTES[wave_index]
		game_time = target_minute * 60.0

## Devuelve el minuto actual de juego
func get_minutes() -> float:
	return game_time / 60.0

## Vacía la cola de spawn (útil al pausar o cambiar escena)
func clear_queue() -> void:
	_spawn_queue.clear()