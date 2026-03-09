## blood_particle_system.gd
## Sistema de partículas de sangre — ProyectSurvivor (Godot 4)
##
## ARQUITECTURA DOD (Data-Oriented Design):
##   Todos los datos viven en PackedArrays paralelos.
##   Sin nodos hijo, sin objetos Particle individuales.
##   _draw() recorre los arrays UNA sola vez por frame.
##
## TIPOS DE PARTÍCULA (p_type[]):
##   0 = MIST   — niebla de impacto, círculo pequeño, vida corta
##   1 = DROP   — gota de salpicadura, se bake al suelo al detenerse
##   2 = CHUNK  — víscera animada, cuadrado, persiste, fade-out al morir
##   3 = DRIP   — goteo de herida, cae y se bake al suelo
##
## STREAK RENDERING:
##   Si vel.length² > STREAK_THRESHOLD_SQ → draw_line(prev_pos → pos)
##   Esto da el look de salpicadura elongada típico de shooters.
##
## LOD AUTOMÁTICO (auto_update_lod()):
##   quality 2 (ALTO)   → efectos completos
##   quality 1 (MEDIO)  → conteos reducidos a la mitad
##   quality 0 (CRISIS) → solo mist mínimo, sin charcos en tiempo real
##
## BAKING AL SUELO:
##   Las gotas (DROP, DRIP) que se detienen se envían al BloodChunkManager
##   para pintarse como decal permanente. Se eliminan del array activo.
##   Los CHUNK nunca se bakean, solo se desvanecen y mueren.

extends Node2D
class_name BloodParticleSystem

# ════════════════════════════════════════════════════════════════════
#  CONSTANTES
# ════════════════════════════════════════════════════════════════════

const TYPE_MIST  : int = 0
const TYPE_DROP  : int = 1
const TYPE_CHUNK : int = 2
const TYPE_DRIP  : int = 3

const MAX_PARTICLES       : int   = 4000
const STREAK_THRESHOLD_SQ : float = 5.0       # vel² > este valor → streak
const STOP_VEL_SQ         : float = 1.5       # vel² < este → "detenida"
const BAKE_ALPHA          : float = 0.82      # alpha con que se bake al suelo

# Umbrales de auto-LOD (partículas activas)
const LOD_CRISIS_THRESHOLD : int = 2800
const LOD_MID_THRESHOLD    : int = 1800

# Paleta de colores
const COL_BLOOD_RED  := Color8(160,  0,  0)
const COL_DARK_BLOOD := Color8( 80,  0,  0)
const COL_BRIGHT_RED := Color8(220, 20, 20)
const COL_GUTS_PINK  := Color8(180, 90,100)
const COL_MIST_RED   := Color(0.65, 0.0, 0.0, 0.55)

# ════════════════════════════════════════════════════════════════════
#  EXPORTS
# ════════════════════════════════════════════════════════════════════

## Referencia al BloodChunkManager para baking de decales
@export var chunk_manager: Node2D

## Calidad inicial (el sistema ajusta automáticamente via auto_update_lod)
@export_range(0, 2) var quality: int = 2

# ════════════════════════════════════════════════════════════════════
#  ARRAYS DOD
# ════════════════════════════════════════════════════════════════════

var p_pos       := PackedVector2Array()   # posición actual (world)
var p_prev_pos  := PackedVector2Array()   # posición frame anterior (para streaks)
var p_vel       := PackedVector2Array()   # velocidad (world px/frame)
var p_color     := PackedColorArray()     # color base
var p_size      := PackedFloat32Array()   # radio o semi-lado
var p_life      := PackedFloat32Array()   # vida restante en frames
var p_max_life  := PackedFloat32Array()   # vida máxima
var p_frict     := PackedFloat32Array()   # fricción por frame (0.80–0.96)
var p_type      := PackedByteArray()      # TYPE_MIST / DROP / CHUNK / DRIP

var active_count: int = 0

# ════════════════════════════════════════════════════════════════════
#  TEXTURAS DE RENDER
# ════════════════════════════════════════════════════════════════════

var _tex_circle : ImageTexture
var _tex_square : ImageTexture

# ════════════════════════════════════════════════════════════════════
#  LISTA DE BAKE PENDIENTE (acumulada durante _process, enviada al final)
# ════════════════════════════════════════════════════════════════════

var _bake_pos   := PackedVector2Array()
var _bake_col   := PackedColorArray()
var _bake_size  := PackedFloat32Array()

# ════════════════════════════════════════════════════════════════════
#  INIT
# ════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("blood_particles")
	_resize_arrays(MAX_PARTICLES)
	_tex_circle = _make_circle_tex(32)
	_tex_square = _make_square_tex(16)

func _resize_arrays(n: int) -> void:
	p_pos.resize(n);      p_prev_pos.resize(n)
	p_vel.resize(n);      p_color.resize(n)
	p_size.resize(n);     p_life.resize(n)
	p_max_life.resize(n); p_frict.resize(n)
	p_type.resize(n)

func _make_circle_tex(d: int) -> ImageTexture:
	var img    := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var center := Vector2(d * 0.5, d * 0.5)
	var r      := d * 0.5 - 0.5
	for y in range(d):
		for x in range(d):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if dist <= r:
				# Borde suave (antialiasing manual)
				var edge := clampf(r - dist, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, edge))
	return ImageTexture.create_from_image(img)

func _make_square_tex(s: int) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

# ════════════════════════════════════════════════════════════════════
#  LOD
# ════════════════════════════════════════════════════════════════════

func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)

func auto_update_lod() -> void:
	if   active_count >= LOD_CRISIS_THRESHOLD: quality = 0
	elif active_count >= LOD_MID_THRESHOLD:    quality = 1
	else:                                      quality = 2

# ════════════════════════════════════════════════════════════════════
#  PROCESO PRINCIPAL
# ════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	auto_update_lod()
	if active_count == 0:
		return

	_bake_pos.clear()
	_bake_col.clear()
	_bake_size.clear()

	var dt := delta * 60.0   # normalizado a 60fps como en el original Pygame

	var i := active_count - 1
	while i >= 0:
		var vel  := p_vel[i]
		var ptype := int(p_type[i])

		# Guardar posición previa para streaks
		p_prev_pos[i] = p_pos[i]

		# Integración de movimiento
		vel           *= pow(p_frict[i], dt)
		p_vel[i]       = vel
		p_pos[i]      += vel * dt

		# Decremento de vida
		p_life[i] -= dt

		var vel_sq := vel.length_squared()
		var stopped := vel_sq < STOP_VEL_SQ

		# ── Baking al suelo (DROP y DRIP detenidas) ──────────────
		if (ptype == TYPE_DROP or ptype == TYPE_DRIP) and stopped:
			if chunk_manager:
				_bake_pos.append(p_pos[i])
				_bake_col.append(p_color[i])
				# MULTIPLICADOR CLAVE: Convertimos el radio en diámetro y lo exageramos
				# para que la mancha aplastada sea mucho mayor que la gota en el aire
				_bake_size.append(p_size[i] * 3.5) 
			_remove(i)
			i -= 1
			continue

		# ── Muerte por agotamiento ────────────────────────────────
		if p_life[i] <= 0.0:
			_remove(i)
			i -= 1
			continue

		i -= 1

	# Enviar lote de bakes al chunk manager
	if chunk_manager and _bake_pos.size() > 0:
		chunk_manager.bake_particles_batch(_bake_pos, _bake_col, _bake_size)

	queue_redraw()

# ════════════════════════════════════════════════════════════════════
#  RENDER
# ════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if active_count == 0:
		return

	# Separar en dos passes: FLOOR (DROP detenido) y AIR (resto)
	# Para top-down 2D, renderizamos todo en un solo pass aquí
	# Los chunks (TYPE_DROP detenidos) ya se bakearon, así que
	# aquí solo vemos partículas en movimiento.

	for i in range(active_count):
		var life_ratio := p_life[i] / maxf(1.0, p_max_life[i])
		if life_ratio <= 0.0:
			continue

		var ptype := int(p_type[i])
		var pos   := p_pos[i]
		var vel   := p_vel[i]
		var sz    := p_size[i]
		var col   := p_color[i]
		var vel_sq := vel.length_squared()

		match ptype:
			TYPE_MIST:
				# Círculo pequeño que se desvanece rápido
				var a := life_ratio * col.a
				draw_texture_rect(
					_tex_circle,
					Rect2(pos.x - sz, pos.y - sz, sz * 2.0, sz * 2.0),
					false,
					Color(col.r, col.g, col.b, a)
				)

			TYPE_DROP:
				# Streak si se mueve rápido, círculo si va lento
				var a := minf(1.0, life_ratio * 1.3) * col.a
				if vel_sq > STREAK_THRESHOLD_SQ:
					# Línea desde posición anterior → actual
					var prev := p_prev_pos[i]
					var streak_width := maxf(1.0, sz * 0.55)
					# Cuerpo del streak
					draw_line(prev, pos, Color(col.r, col.g, col.b, a * 0.9), streak_width)
					# Cabeza brillante
					draw_texture_rect(
						_tex_circle,
						Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz),
						false,
						Color(col.r * 1.1, col.g, col.b, a)
					)
				else:
					draw_texture_rect(
						_tex_circle,
						Rect2(pos.x - sz, pos.y - sz, sz * 2.0, sz * 2.0),
						false,
						Color(col.r, col.g, col.b, a)
					)

			TYPE_CHUNK:
				# Cuadrado con fade-out al final de vida
				var a := col.a
				if life_ratio < 0.35:
					a *= life_ratio / 0.35
				# Streak de chunk si se mueve rápido
				if vel_sq > STREAK_THRESHOLD_SQ:
					var prev := p_prev_pos[i]
					draw_line(prev, pos, Color(col.r, col.g, col.b, a * 0.7), sz * 0.8)
				draw_texture_rect(
					_tex_square,
					Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz),
					false,
					Color(col.r, col.g, col.b, a)
				)

			TYPE_DRIP:
				# Gota que cae lentamente — círculo alargado
				var a := minf(1.0, life_ratio * 2.0) * col.a
				if vel_sq > 0.1:
					draw_line(
						p_prev_pos[i], pos,
						Color(col.r, col.g, col.b, a),
						maxf(1.5, sz * 0.7)
					)
				draw_texture_rect(
					_tex_circle,
					Rect2(pos.x - sz * 0.6, pos.y - sz * 0.6, sz * 1.2, sz * 1.2),
					false,
					Color(col.r, col.g, col.b, a)
				)

# ════════════════════════════════════════════════════════════════════
#  SPAWN INTERNO
# ════════════════════════════════════════════════════════════════════

func _spawn(
	pos:      Vector2,
	vel:      Vector2,
	color:    Color,
	size:     float,
	life:     float,
	frict:    float,
	ptype:    int
) -> void:
	if active_count >= MAX_PARTICLES:
		return
	var i           := active_count
	p_pos[i]         = pos
	p_prev_pos[i]    = pos
	p_vel[i]         = vel
	p_color[i]       = color
	p_size[i]        = size
	p_life[i]        = life
	p_max_life[i]    = life
	p_frict[i]       = frict
	p_type[i]        = ptype
	active_count    += 1

func _remove(i: int) -> void:
	active_count -= 1
	if i == active_count:
		return
	p_pos[i]      = p_pos[active_count]
	p_prev_pos[i] = p_prev_pos[active_count]
	p_vel[i]      = p_vel[active_count]
	p_color[i]    = p_color[active_count]
	p_size[i]     = p_size[active_count]
	p_life[i]     = p_life[active_count]
	p_max_life[i] = p_max_life[active_count]
	p_frict[i]    = p_frict[active_count]
	p_type[i]     = p_type[active_count]

# ════════════════════════════════════════════════════════════════════
#  API PÚBLICA — EFECTOS
# ════════════════════════════════════════════════════════════════════

## ── 1. SALPICADURA DE IMPACTO ────────────────────────────────────
## Llamar al impactar un proyectil. `direction_vector` = dirección de
## vuelo del proyectil (normalizada). `damage_ratio` 0-1 escala la
## cantidad e intensidad según el daño relativo al max_health.
func create_blood_splatter(
	pos:              Vector2,
	direction_vector: Vector2 = Vector2.ZERO,
	force:            float   = 1.5, # Fuerza base aumentada
	count:            int     = 12,
	damage_ratio:     float   = 0.5
) -> void:
	if quality == 0:
		return

	var intensity := clampf(damage_ratio, 0.2, 1.0)
	var mist_count : int
	var drop_count : int
	
	match quality:
		2:
			mist_count = int(count * 0.8 * intensity) + 4
			drop_count = int(count * 1.5 * intensity) + 4
		1:
			mist_count = int(count * 0.4 * intensity) + 2
			drop_count = int(count * 0.8 * intensity) + 2
		_:
			return

	var base_angle: float = direction_vector.angle() if direction_vector != Vector2.ZERO else 0.0
	var has_dir    := direction_vector != Vector2.ZERO

	# ── DROPS: Manchas principales ──────────
	for _i in range(drop_count):
		var angle: float = base_angle + randf_range(-0.55, 0.55) if has_dir else randf_range(0.0, TAU)
		var speed := randf_range(4.0, 13.0) * force
		
		# Tamaños pequeños en el aire (radio 2 a 5), idéntico a Pygame
		var sz    := randf_range(2.0, 5.0) 
		var life  := randf_range(40.0, 80.0)

		var col: Color = [COL_BLOOD_RED, COL_BRIGHT_RED, COL_DARK_BLOOD].pick_random()
		col.a = 0.95

		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
			   col, sz, life, 0.84, TYPE_DROP)

	# ── MIST: Niebla acompañante ──────────────────────────
	for _i in range(mist_count):
		var angle: float = base_angle + randf_range(-1.4, 1.4) if has_dir else randf_range(0.0, TAU)
		var speed := randf_range(6.0, 18.0 * intensity) * force
		var sz    := randf_range(2.5, 5.0 + intensity * 2.0)
		var col   := COL_MIST_RED
		col.a     = randf_range(0.4, 0.7)

		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
			   col, sz, randf_range(8.0, 18.0), 0.75, TYPE_MIST)

func create_blood_drip(pos: Vector2, intensity: float = 1.0) -> void:
	if quality == 0:
		return

	var drops := 1
	if intensity > 12.0 and quality == 2:
		drops = randi_range(1, 3)

	for _i in range(drops):
		var offset := Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		var sz     := clampf(4.0 + intensity * 0.3, 3.0, 11.0) # Gotas más grandes
		var col: Color = COL_DARK_BLOOD if intensity > 10.0 else COL_BLOOD_RED
		col.a = 0.90

		# Movimiento radial suave sin inercias gravitacionales en Y
		var angle = randf_range(0.0, TAU)
		var speed = randf_range(0.0, 0.6)
		var vel = Vector2(cos(angle), sin(angle)) * speed

		_spawn(pos + offset, vel, col, sz,
			   randf_range(30.0, 60.0), 0.85, TYPE_DRIP)


## ── 3. CHARCO INMEDIATO (bake directo) ───────────────────────────
## Para muerte de enemigo: crea un charco grande bakeado al instante.
## NO genera partículas en vuelo — va directo al ChunkManager.
func create_blood_pool(pos: Vector2, radius_mult: float = 1.0) -> void:
	if not chunk_manager:
		# Fallback: partículas DROP estáticas si no hay chunk manager
		_create_pool_particles(pos, radius_mult)
		return

	var blobs: int
	match quality:
		2: blobs = randi_range(6, 10)
		1: blobs = randi_range(3, 5)
		_: blobs = randi_range(1, 2)

	var pos_arr  := PackedVector2Array()
	var col_arr  := PackedColorArray()
	var size_arr := PackedFloat32Array()

	for _i in range(blobs):
		var offset_dist: float = randf_range(0.0, 18.0 * radius_mult) if blobs > 1 else 0.0
		var offset_angle := randf_range(0.0, TAU)
		var blob_pos     := pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist

		var sz: float
		match quality:
			2: sz = randf_range(40.0, 96.0 * radius_mult)
			1: sz = randf_range(24.0, 48.0 * radius_mult)
			_: sz = randf_range(20.0, 32.0)

		pos_arr.append(blob_pos)
		col_arr.append(COL_DARK_BLOOD)
		size_arr.append(sz)

	chunk_manager.bake_particles_batch(pos_arr, col_arr, size_arr)

func _create_pool_particles(pos: Vector2, radius_mult: float) -> void:
	var blobs: int = randi_range(3, 6) if quality == 2 else 2
	for _i in range(blobs):
		var angle  := randf_range(0.0, TAU)
		var dist   := randf_range(0.0, 20.0 * radius_mult)
		var bpos   := pos + Vector2(cos(angle), sin(angle)) * dist
		var sz     := randf_range(10.0, 24.0 * radius_mult)
		_spawn(bpos, Vector2.ZERO, COL_DARK_BLOOD, sz,
			   80.0, 0.0, TYPE_DROP)


## ── 4. EXPLOSIÓN DE VÍSCERAS (muerte de enemigo) ─────────────────
## `size_mult` escala todo con el tipo de enemigo (0.7–2.2).
func create_viscera_explosion(pos: Vector2, size_mult: float = 1.0) -> void:
	var mist_count : int
	var chunk_count: int
	
	match quality:
		2:
			mist_count  = 22
			chunk_count = 9
		1:
			mist_count  = 6
			chunk_count = 2
		_:
			mist_count  = 2
			chunk_count = 0

	if quality > 0:
		create_blood_pool(pos, size_mult)

	# ── MIST: nube de sangre ───────────────────────
	for _i in range(mist_count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(3.0, 10.0 * size_mult)
		var sz    := randf_range(3.0, 6.0 * size_mult)
		var life  := randf_range(20.0, 45.0)
		var col   : Color = COL_BLOOD_RED if randf() < 0.5 else COL_BRIGHT_RED
		col.a      = randf_range(0.6, 0.85)
		
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
			   col, sz, life, 0.89, TYPE_MIST)

	# ── CHUNKS: trozos de carne (No se hornean, persisten) ───────────────────
	for _i in range(chunk_count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(5.0, 12.0 * size_mult)
		var sz    := randf_range(4.0, 9.0 * size_mult)
		var life  := randf_range(100.0, 300.0)
		var col   : Color = COL_DARK_BLOOD if randf() < 0.5 else COL_GUTS_PINK
		col.a      = 0.95
		
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
			   col, sz, life, 0.91, TYPE_CHUNK)

	# ── DROPS largos: Salpicaduras masivas radiales
	if quality >= 1:
		var long_drops := int(clampf(8.0 * size_mult, 4.0, 16.0))
		for _i in range(long_drops):
			var angle := randf_range(0.0, TAU)
			var speed := randf_range(8.0, 22.0 * size_mult) # Mayor velocidad inicial
			var col   := COL_BLOOD_RED if randf() < 0.7 else COL_DARK_BLOOD
			col.a      = 0.95
			_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
				   col, randf_range(4.0, 8.0 * size_mult), # Tamaño incrementado masivamente
				   randf_range(20.0, 45.0), 0.78, TYPE_DROP) # Fricción fuerte para que la sangre reviente y se asiente rápido


## ── 5. MANCHA DE HERIDA EN EL CUERPO DEL ENEMIGO ────────────────
## Bake directo al suelo bajo la posición del enemigo.
## Llamar desde enemy.gd cuando recibe daño acumulado suficiente.
func create_wound_stain(pos: Vector2, dmg_ratio: float) -> void:
	if not chunk_manager or dmg_ratio < 0.05:
		return

	var pos_arr  := PackedVector2Array()
	var col_arr  := PackedColorArray()
	var size_arr := PackedFloat32Array()

	# Una mancha principal + gotas satélite
	pos_arr.append(pos)
	col_arr.append(COL_DARK_BLOOD)
	size_arr.append(randf_range(8.0, 18.0) * (0.5 + dmg_ratio))

	if quality >= 1 and dmg_ratio > 0.2:
		for _i in range(randi_range(1, 3)):
			var offset := Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
			pos_arr.append(pos + offset)
			col_arr.append(COL_BLOOD_RED)
			size_arr.append(randf_range(3.0, 8.0) * dmg_ratio)

	chunk_manager.bake_particles_batch(pos_arr, col_arr, size_arr)


# ════════════════════════════════════════════════════════════════════
#  UTILIDADES
# ════════════════════════════════════════════════════════════════════

func get_active_count() -> int:
	return active_count

func clear() -> void:
	active_count = 0
	_bake_pos.clear()
	_bake_col.clear()
	_bake_size.clear()
