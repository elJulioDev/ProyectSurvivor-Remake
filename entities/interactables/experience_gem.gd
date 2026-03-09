## experience_gem.gd
## Gema de experiencia — ProyectSurvivor (Godot 4)
##
## FLUJO DE VIDA:
##   1. spawn → scatter radial (velocidad inicial aleatoria)
##   2. reposo → la gema frena por fricción y espera
##   3. imán  → cuando el jugador entra en rango, la gema se
##              acelera suavemente hacia él (aceleración progresiva)
##   4. recolección → distancia ≤ COLLECT_RADIUS → gain_experience()
##
## VISUAL:
##   Diamante de 4 vértices con glow exterior y núcleo brillante.
##   El tamaño escala con log(xp_value) para que las gemas grandes
##   sean visiblemente distintas pero no enormes.
##
## MERGING (llamado desde GemManager):
##   merge_with(value) suma el XP y recalcula el radio visual.

extends Node2D
class_name ExperienceGem

# ════════════════════════════════════════════════════════════════
#  CONSTANTES
# ════════════════════════════════════════════════════════════════

## Radio de colisión con el jugador (px de mundo)
const COLLECT_RADIUS   : float = 20.0

## Radio de activación del imán en ausencia de upgrades
const MAGNET_RADIUS_BASE : float = 140.0

## Aceleración adicional cada segundo mientras la gema está atraída
const ATTRACT_ACCEL    : float = 700.0

## Velocidad máxima de atracción (sin upgrades)
const MAX_ATTRACT_SPEED : float = 480.0

## Fricción durante la fase de scatter (por frame a 60 fps)
const SCATTER_FRICTION : float = 0.88

## Tiempo de scatter antes de que el imán pueda activarse
const SCATTER_TIME     : float = 0.25   # segundos

# ════════════════════════════════════════════════════════════════
#  ESTADO
# ════════════════════════════════════════════════════════════════

var xp_value         : int     = 1
var _vel             : Vector2 = Vector2.ZERO
var _attracted       : bool    = false
var _attraction_speed: float   = 60.0
var _lifetime        : float   = 0.0
var _pulse_timer     : float   = 0.0

## Radio visual, recalculado al crear o mergear
var _gem_radius      : float   = 6.0

# ════════════════════════════════════════════════════════════════
#  INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("experience_gems")

## Llamar inmediatamente después de instanciar.
## value  — cantidad de XP que concede.
## scatter_force — intensidad del salto inicial (0 para gemas estáticas).
func setup(value: int, scatter_force: float = 1.0) -> void:
	xp_value = value
	_recalc_radius()

	# Impulso radial aleatorio para dispersar visualmente
	var angle : float = randf_range(0.0, TAU)
	var speed : float = randf_range(30.0, 90.0) * scatter_force
	_vel = Vector2(cos(angle), sin(angle)) * speed

## Fuerza el inicio de atracción aunque el jugador esté fuera de rango.
## Usado por el upgrade "Campo Magnético" (magnet_huge).
func force_attract() -> void:
	_attracted = true

# ════════════════════════════════════════════════════════════════
#  PROCESO
# ════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_lifetime     += delta
	_pulse_timer  += delta * 3.0

	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.is_alive:
		queue_redraw()
		return

	var dist    : float   = global_position.distance_to(player.global_position)
	var mag_r   : float   = MAGNET_RADIUS_BASE * player.magnet_range_mult
	var max_spd : float   = MAX_ATTRACT_SPEED  * player.magnet_speed_mult

	# ── Fase scatter ─────────────────────────────────────────────
	if _lifetime < SCATTER_TIME and not _attracted:
		_vel *= pow(SCATTER_FRICTION, delta * 60.0)

	# ── Activación del imán ──────────────────────────────────────
	elif dist <= mag_r or _attracted:
		_attracted = true
		var dir : Vector2 = global_position.direction_to(player.global_position)

		# Aceleración progresiva para que las gemas parezcan "succionadas"
		_attraction_speed = minf(
			_attraction_speed + ATTRACT_ACCEL * delta,
			max_spd
		)
		_vel = dir * _attraction_speed

	# ── Sin imán aún → fricción pasiva ───────────────────────────
	else:
		_vel *= pow(0.96, delta * 60.0)

	global_position += _vel * delta

	# ── Recolección ──────────────────────────────────────────────
	if dist <= COLLECT_RADIUS:
		_collect(player)
		return

	queue_redraw()

func _collect(player: Node) -> void:
	player.gain_experience(xp_value)
	queue_free()

# ════════════════════════════════════════════════════════════════
#  API PÚBLICA — MERGING
# ════════════════════════════════════════════════════════════════

## Absorbe el XP de otra gema (llamado por GemManager antes de
## hacer queue_free() sobre la gema absorbida).
func merge_with(other_value: int) -> void:
	xp_value += other_value
	_recalc_radius()
	# Al aumentar de tamaño, la gema emite un pequeño pulso visual
	_pulse_timer = 0.0

func _recalc_radius() -> void:
	# log escala: 1 XP → r≈4, 10 XP → r≈7, 100 XP → r≈11, 1000 XP → r≈14
	_gem_radius = clampf(4.0 + log(float(xp_value) + 1.0) * 2.0, 4.0, 15.0)

# ════════════════════════════════════════════════════════════════
#  RENDER
# ════════════════════════════════════════════════════════════════

func _draw() -> void:
	var pulse : float = sin(_pulse_timer) * 0.12 + 1.0
	var r     : float = _gem_radius * pulse

	# Brillo exterior difuso (dos capas para suavizar)
	draw_circle(Vector2.ZERO, r * 2.6, Color(0.35, 0.75, 1.0, 0.10))
	draw_circle(Vector2.ZERO, r * 1.8, Color(0.40, 0.82, 1.0, 0.18))

	# Diamante principal (4 vértices)
	var pts := PackedVector2Array([
		Vector2(0.0,       -r),
		Vector2(r * 0.65,  0.0),
		Vector2(0.0,        r),
		Vector2(-r * 0.65, 0.0),
	])
	draw_colored_polygon(pts, Color(0.38, 0.80, 1.0, 0.92))

	# Borde brillante
	draw_polyline(
		PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(0.80, 0.96, 1.0, 0.85),
		1.5
	)

	# Núcleo blanco (destello interior)
	draw_circle(Vector2.ZERO, maxf(1.5, r * 0.30), Color(0.95, 1.0, 1.0, 1.0))

	# Si está atraída: traza estela de velocidad
	if _attracted and _vel.length_squared() > 400.0:
		var streak_end := Vector2.ZERO - _vel.normalized() * r * 2.5
		draw_line(Vector2.ZERO, streak_end,
				  Color(0.40, 0.82, 1.0, 0.40), maxf(1.0, r * 0.4))