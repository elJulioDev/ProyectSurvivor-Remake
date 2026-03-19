extends Camera2D

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  camera.gd — ProyectSurvivor  (estilo Vampire Survivors)
#
#  Cambios respecto a la versión anterior:
#    · Eliminado el parallax del ratón — la cámara sigue al jugador
#      de forma estática, igual que en VS.
#    · Lerp ligeramente más rápido (0.12) para respuesta inmediata.
#    · El clamp a los límites del mundo se mantiene; cuando el
#      jugador está en la esquina, la cámara se queda en el borde
#      correcto y get_screen_center_position() refleja ese valor,
#      lo que el SpawnManager usa para colocar enemigos fuera de
#      la vista real (no del jugador).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const LERP_SPEED  : float = 0.12   # más rápido que 0.08 para feel VS
const SHAKE_DECAY : float = 0.88

var shake_intensity : float = 0.0

var _player  : Node2D  = null
var _vp_half : Vector2 = Vector2.ZERO

func _ready() -> void:
	_vp_half = get_viewport_rect().size * 0.5
	_find_player()
	if is_instance_valid(_player):
		global_position = _player.global_position
	make_current()

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		await get_tree().process_frame
		players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
			global_position = _player.global_position

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	_vp_half = get_viewport_rect().size * 0.5

	# ── Target: posición del jugador (sin parallax de ratón) ──────
	# VS sigue al jugador directamente — sin desplazamiento del mouse.
	var tx : float = _player.global_position.x
	var ty : float = _player.global_position.y

	# ── Lerp frame-rate independent ──────────────────────────────
	var dt      : float = delta * 60.0
	var lerp_dt : float = 1.0 - pow(1.0 - LERP_SPEED, dt)
	global_position.x += (tx - global_position.x) * lerp_dt
	global_position.y += (ty - global_position.y) * lerp_dt

	# ── Clamp a los límites del mundo ────────────────────────────
	# Al clampear aquí, get_screen_center_position() devolverá la
	# posición real de la cámara, que SpawnManager usará para
	# colocar enemigos justo fuera de la vista correcta.
	var z      : float = maxf(zoom.x, 0.01)
	var half_w : float = _vp_half.x / z
	var half_h : float = _vp_half.y / z
	global_position.x = clampf(global_position.x, half_w,  GameManager.WORLD_WIDTH  - half_w)
	global_position.y = clampf(global_position.y, half_h,  GameManager.WORLD_HEIGHT - half_h)

	# ── Shake frame-rate independent ─────────────────────────────
	if shake_intensity > 0.1:
		offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		shake_intensity *= pow(SHAKE_DECAY, dt)
		if shake_intensity < 0.1:
			shake_intensity = 0.0
			offset          = Vector2.ZERO
	else:
		offset = Vector2.ZERO

# ── API pública ───────────────────────────────────────────────────

func add_shake(amount: float) -> void:
	shake_intensity = minf(shake_intensity + amount, 20.0)

func snap_to_player() -> void:
	if is_instance_valid(_player):
		global_position = _player.global_position
		offset          = Vector2.ZERO
		shake_intensity = 0.0