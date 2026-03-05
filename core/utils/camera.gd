extends Camera2D

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  camera.gd — ProyectSurvivor
#
#  Traducción de camera.py (utils/camera.py del Pygame):
#    · Lerp frame-rate independent: 1 - (1 - 0.08)^dt
#    · Shake con decay frame-rate independent: intensity *= 0.88^dt
#    · Paralaje del ratón: ×0.4 dividido por zoom
#    · Clamp dentro de los límites del mundo
#
#  INSTALACIÓN:
#    1. Selecciona el nodo Camera2D en gameplay.tscn
#    2. Arrastra este script al campo "Script" en el Inspector
#    3. Asegúrate de que el nodo Camera2D tiene "Current" = true
#
#  El script busca al jugador automáticamente via el grupo "player".
#  No necesitas conectar nada manualmente.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const LERP_SPEED  := 0.08       # idéntico a camera.py
const SHAKE_DECAY := 0.88       # idéntico a camera.py
const MOUSE_PARA  := 0.4        # factor de paralaje del ratón

var shake_intensity : float = 0.0

var _player : Node2D = null
var _vp_half: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Tamaño de medio viewport (para calcular límites)
	_vp_half = get_viewport_rect().size * 0.5

	# Buscar jugador por grupo — funciona aunque el orden de _ready varíe
	_find_player()

	# Si el jugador ya existe, hacer snap instantáneo (sin lerp)
	if is_instance_valid(_player):
		global_position = _player.global_position
	
	# Activar esta cámara
	make_current()

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		# El jugador puede no estar listo todavía; reintentamos el siguiente frame
		await get_tree().process_frame
		players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
			global_position = _player.global_position

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Actualizar la mitad del viewport en tiempo real
	# por si el jugador maximiza o redimensiona la ventana
	_vp_half = get_viewport_rect().size * 0.5

	# ── Target: posición del jugador + paralaje del ratón ────────
	var mouse_screen := get_viewport().get_mouse_position() - _vp_half
	var z  := maxf(zoom.x, 0.01)
	var tx := _player.global_position.x + mouse_screen.x / z * MOUSE_PARA
	var ty := _player.global_position.y + mouse_screen.y / z * MOUSE_PARA

	# ── Lerp frame-rate independent ──────────────────────────────
	# Fórmula de camera.py:  lerp_dt = 1 - (1 - lerp_speed)^dt
	var dt      := delta * 60.0
	var lerp_dt := 1.0 - pow(1.0 - LERP_SPEED, dt)
	global_position.x += (tx - global_position.x) * lerp_dt
	global_position.y += (ty - global_position.y) * lerp_dt

    # ── Clamp a los límites del mundo ────────────────────────────
	var half_w := _vp_half.x / z
	var half_h := _vp_half.y / z
	global_position.x = clampf(global_position.x, half_w, GameManager.WORLD_WIDTH - half_w)
	global_position.y = clampf(global_position.y, half_h, GameManager.WORLD_HEIGHT - half_h)

	# ── Shake frame-rate independent ─────────────────────────────
	if shake_intensity > 0.1:
		offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		shake_intensity *= pow(SHAKE_DECAY, dt)
		if shake_intensity < 0.1:
			shake_intensity = 0.0
			offset = Vector2.ZERO
	else:
		offset = Vector2.ZERO

# ── API pública ───────────────────────────────────────────────────

func add_shake(amount: float) -> void:
	shake_intensity = minf(shake_intensity + amount, 20.0)

func snap_to_player() -> void:
	## Teletransporta la cámara al jugador sin lerp (usar en initialize).
	if is_instance_valid(_player):
		global_position = _player.global_position
		offset = Vector2.ZERO
		shake_intensity = 0.0