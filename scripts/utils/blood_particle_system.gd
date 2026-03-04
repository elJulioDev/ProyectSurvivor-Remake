extends Node2D
class_name BloodParticleSystem

# ════════════════════════════════════════════════════════════════════════════
#  BloodParticleSystem — ProyectSurvivor (Godot 4)
#
#  LÓGICA FIEL AL ORIGINAL PYGAME:
#
#  · Las partículas de sangre líquida (no vísceras) se HORNEAN y MATAN
#    INMEDIATAMENTE cuando su velocidad cae por debajo del umbral.
#    Nunca se renderizan estáticas: en el frame en que se detienen,
#    se convierten en decal permanente en el ChunkManager.
#
#  · create_blood_pool() NO usa partículas vivas. Llama directamente
#    a chunk_manager.bake_particles_batch() → el charco aparece INSTANTÁNEO
#    sin ningún artefacto visual previo.
#
#  · Solo las vísceras (is_viscera=true) se renderizan animadas y se
#    desvanecen con el tiempo; nunca se hornean.
#
#  · 3 niveles LOD idénticos al original Python:
#      0 = CRISIS  → splatter omitido, pools mínimos, explosión: 2 niebla
#      1 = MEDIO   → reducido
#      2 = ALTO    → completo
# ════════════════════════════════════════════════════════════════════════════

# ── Paleta (idéntica a Pygame) ────────────────────────────────────────────
const BLOOD_RED  := Color8(160,  0,  0)
const DARK_BLOOD := Color8( 80,  0,  0)
const BRIGHT_RED := Color8(200, 20, 20)
const GUTS_PINK  := Color8(180, 90, 100)

# ── Pool ──────────────────────────────────────────────────────────────────
const MAX_PARTICLES := 3000

# ── Umbral de velocidad para bake (equivale a abs(vel) < 0.1 en Pygame) ──
const STOP_THRESHOLD_SQ := 0.01   # 0.1 * 0.1

# ── LOD ───────────────────────────────────────────────────────────────────
var quality: int = 2

# ── Referencia al gestor de chunks ───────────────────────────────────────
@export var chunk_manager: Node2D

# ════ ESTRUCTURA DOD ══════════════════════════════════════════════════════
# Solo se guardan partículas EN MOVIMIENTO o vísceras animadas.
# Las partículas de sangre que se detienen se hornean y eliminan al instante.
var p_pos   := PackedVector2Array()
var p_vel   := PackedVector2Array()
var p_color := PackedColorArray()
var p_size  := PackedFloat32Array()
var p_life  := PackedFloat32Array()
var p_max_life := PackedFloat32Array()  # para el fade-out de vísceras
var p_frict := PackedFloat32Array()
var p_flags := PackedByteArray()
# Bit 0: 1 = víscera (cuadrado animado, fade, no horneable)
#        0 = sangre  (círculo, se hornea al detenerse)

var active_count: int = 0

# Texturas para _draw (una por tipo)
var _circle_tex: ImageTexture
var _chunk_tex:  ImageTexture

# ════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("blood_particles")
	p_pos.resize(MAX_PARTICLES)
	p_vel.resize(MAX_PARTICLES)
	p_color.resize(MAX_PARTICLES)
	p_size.resize(MAX_PARTICLES)
	p_life.resize(MAX_PARTICLES)
	p_max_life.resize(MAX_PARTICLES)
	p_frict.resize(MAX_PARTICLES)
	p_flags.resize(MAX_PARTICLES)

	_circle_tex = _build_circle_texture(32)
	_chunk_tex  = _build_rect_texture(16)

func _build_circle_texture(d: int) -> ImageTexture:
	var img    := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var center := Vector2(d * 0.5, d * 0.5)
	var r      := d * 0.5 - 0.5
	for y in range(d):
		for x in range(d):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

func _build_rect_texture(s: int) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

# ════════════════════════════════════════════════════════════════════════════
#  LOD
# ════════════════════════════════════════════════════════════════════════════
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)

func auto_update_lod() -> void:
	if   active_count > 2400: quality = 0
	elif active_count > 1600: quality = 1
	else:                     quality = 2

# ════════════════════════════════════════════════════════════════════════════
#  PROCESO — FIEL A PYGAME
# ════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if active_count == 0:
		return

	var dt := delta * 60.0  # normalizado a 60 fps

	# Acumulamos las partículas que se detienen para hornearlas en batch
	var bake_pos  := PackedVector2Array()
	var bake_col  := PackedColorArray()
	var bake_size := PackedFloat32Array()

	var i := active_count - 1
	while i >= 0:
		var is_viscera: bool = (p_flags[i] & 1) == 1

		# Física
		var vel := p_vel[i]
		vel        *= pow(p_frict[i], dt)
		p_vel[i]    = vel
		p_pos[i]   += vel * dt

		if not is_viscera:
			# ── SANGRE: si se detiene → HORNEAR INMEDIATAMENTE y matar ──
			# Esto replica exactamente el comportamiento de Python:
			#   if abs(vel_x) < 0.1 and abs(vel_y) < 0.1 → bake + kill
			if vel.length_squared() < STOP_THRESHOLD_SQ:
				if chunk_manager:
					bake_pos.append(p_pos[i])
					bake_col.append(p_color[i])
					# Multiplicar por 1.1 o 1.0 hará que se respete el tamaño exacto al caer
					bake_size.append(p_size[i] * 1.2)

				# Eliminar partícula (swap-and-pop O(1))
				active_count -= 1
				if i != active_count:
					p_pos[i]      = p_pos[active_count]
					p_vel[i]      = p_vel[active_count]
					p_color[i]    = p_color[active_count]
					p_size[i]     = p_size[active_count]
					p_life[i]     = p_life[active_count]
					p_max_life[i] = p_max_life[active_count]
					p_frict[i]    = p_frict[active_count]
					p_flags[i]    = p_flags[active_count]
				i -= 1
				continue

			# Sangre en movimiento: decaimiento normal (1/frame como en Python)
			p_life[i] -= 1.0 * dt
			if p_life[i] <= 0.0:
				# Expiró sin detenerse del todo → hornear donde quedó
				if chunk_manager:
					bake_pos.append(p_pos[i])
					bake_col.append(p_color[i])
					bake_size.append(p_size[i])
				active_count -= 1
				if i != active_count:
					p_pos[i]      = p_pos[active_count]
					p_vel[i]      = p_vel[active_count]
					p_color[i]    = p_color[active_count]
					p_size[i]     = p_size[active_count]
					p_life[i]     = p_life[active_count]
					p_max_life[i] = p_max_life[active_count]
					p_frict[i]    = p_frict[active_count]
					p_flags[i]    = p_flags[active_count]
		else:
			# ── VÍSCERA: decaimiento normal + fade, nunca se hornea ──
			p_life[i] -= 1.0 * dt
			if p_life[i] <= 0.0:
				active_count -= 1
				if i != active_count:
					p_pos[i]      = p_pos[active_count]
					p_vel[i]      = p_vel[active_count]
					p_color[i]    = p_color[active_count]
					p_size[i]     = p_size[active_count]
					p_life[i]     = p_life[active_count]
					p_max_life[i] = p_max_life[active_count]
					p_frict[i]    = p_frict[active_count]
					p_flags[i]    = p_flags[active_count]

		i -= 1

	# Enviar todo el batch al ChunkManager de una sola vez
	if chunk_manager and bake_pos.size() > 0:
		chunk_manager.bake_particles_batch(bake_pos, bake_col, bake_size)

	queue_redraw()

# ════════════════════════════════════════════════════════════════════════════
#  RENDER — Solo partículas en movimiento o vísceras animadas
# ════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	for i in range(active_count):
		var pos   := p_pos[i]
		var sz    := p_size[i]
		var col   := p_color[i]
		var is_viscera: bool = (p_flags[i] & 1) == 1

		# Fade-out solo para vísceras (la sangre no se renderiza detenida)
		if is_viscera:
			var life_ratio := p_life[i] / maxf(1.0, p_max_life[i])
			if life_ratio < 0.3:
				col.a = life_ratio / 0.3
			draw_texture_rect(
				_chunk_tex,
				Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz),
				false, col
			)
		else:
			# Sangre en movimiento: sin fade (se hornea antes de detenerse)
			draw_texture_rect(
				_circle_tex,
				Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz),
				false, col
			)

# ════════════════════════════════════════════════════════════════════════════
#  SPAWN INTERNO
# ════════════════════════════════════════════════════════════════════════════
func _spawn(
	pos: Vector2, vel: Vector2, color: Color,
	size: float, life: float, frict: float,
	is_viscera: bool
) -> void:
	if active_count >= MAX_PARTICLES:
		return
	var i := active_count
	p_pos[i]      = pos
	p_vel[i]      = vel
	p_color[i]    = color
	p_size[i]     = size
	p_life[i]     = life
	p_max_life[i] = life
	p_frict[i]    = frict
	p_flags[i]    = 1 if is_viscera else 0
	active_count  += 1

# ════════════════════════════════════════════════════════════════════════════
#  EFECTOS PÚBLICOS — Réplica exacta del original Python
# ════════════════════════════════════════════════════════════════════════════

## Salpicadura direccional al impactar un proyectil.
## Equivale a ParticleSystem.create_blood_splatter() del Python.
func create_blood_splatter(
	pos: Vector2,
	direction_vector: Vector2 = Vector2.ZERO,
	force: float = 1.2,
	count: int = 8 # Aumentamos la cantidad base de partículas
) -> void:
	if quality == 0:
		return

	var actual_count: int
	if quality == 2:
		actual_count = count * 4  # Generará 32 partículas por impacto en calidad Alta
	else:
		actual_count = maxi(1, count)

	for _i in range(actual_count):
		var angle: float
		var speed: float

		if direction_vector != Vector2.ZERO:
			# Cono más amplio para que se vea más esparcido
			angle = direction_vector.angle() + randf_range(-0.7, 0.7)
			speed = randf_range(4.0, 15.0) * force
		else:
			angle = randf_range(0.0, TAU)
			speed = randf_range(3.0, 9.0)

		# Mantenemos las partículas pequeñas en el aire (para no tapar la pantalla)
		var sz   := randf_range(5.0, 9.0)
		
		# Reducimos el tiempo de vida (antes 40-80) para que se peguen al piso mucho más rápido
		var life := randf_range(15.0, 35.0)

		_spawn(
			pos,
			Vector2(cos(angle), sin(angle)) * speed,
			[BLOOD_RED, BRIGHT_RED, DARK_BLOOD].pick_random(),
			sz, life, 0.82,
			false
		)

## Goteo continuo de un enemigo sangrando.
## Equivale a ParticleSystem.create_blood_drip().
func create_blood_drip(pos: Vector2, intensity: float = 1.0) -> void:
	if quality == 0:
		return

	var base_size := minf(10.0, 2.0 + intensity * 0.3)
	var drops     := 1
	if intensity > 15.0:
		drops = randi_range(1, 2)

	for _i in range(drops):
		var col: Color = DARK_BLOOD if intensity > 10.0 else \
				([BLOOD_RED, DARK_BLOOD].pick_random())
		_spawn(
			pos + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
			Vector2.ZERO,
			col,
			randf_range(base_size, base_size + 3.0),
			randf_range(60.0, 120.0),
			0.0,
			false
		)
	# vel=0, frict=0 → se hornea en el primer frame de _process ✓

## Charco de sangre grande.
## DIFERENCIA CLAVE: No usa partículas vivas.
## Llama directamente a bake_particles_batch → charco INSTANTÁNEO.
## Equivale a ParticleSystem.create_blood_pool() del Python.
func create_blood_pool(pos: Vector2) -> void:
	var blobs: int
	if   quality == 2: blobs = randi_range(4, 8)
	elif quality == 1: blobs = randi_range(2, 3)
	else:              blobs = 1

	if chunk_manager:
		# Bake directo: el charco aparece en el mismo frame sin ningún artefacto
		var pos_arr  := PackedVector2Array()
		var col_arr  := PackedColorArray()
		var size_arr := PackedFloat32Array()

		for _i in range(blobs):
			var offset_angle := randf_range(0.0, TAU)
			var offset_dist  := randf_range(0.0, 18.0) if blobs > 1 else 0.0
			var blob_pos     := pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist
			var sz := randf_range(10.0, 24.0) if quality == 2 else randf_range(6.0, 12.0)

			pos_arr.append(blob_pos)
			col_arr.append(DARK_BLOOD)
			size_arr.append(sz)

		chunk_manager.bake_particles_batch(pos_arr, col_arr, size_arr)
	else:
		# Sin ChunkManager: fallback con partículas normales (vel=0 → bake en frame 1)
		for _i in range(blobs):
			var offset_angle := randf_range(0.0, TAU)
			var offset_dist  := randf_range(0.0, 18.0) if blobs > 1 else 0.0
			var blob_pos     := pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist
			var sz := randf_range(10.0, 24.0) if quality == 2 else randf_range(6.0, 12.0)
			_spawn(blob_pos, Vector2.ZERO, DARK_BLOOD, sz, 60.0, 0.0, false)

## Explosión gore al morir un enemigo: niebla + trozos + charco instantáneo.
## Equivale a ParticleSystem.create_viscera_explosion() del Python.
func create_viscera_explosion(pos: Vector2) -> void:
	var mist_count:  int
	var chunk_count: int
	var do_pool:     bool

	if quality == 2:
		mist_count  = 22
		chunk_count = 9
		do_pool     = true
	elif quality == 1:
		mist_count  = 6
		chunk_count = 2
		do_pool     = true
	else:
		# CRISIS: mínimo visualmente satisfactorio (igual que Python)
		mist_count  = 2
		chunk_count = 0
		do_pool     = false

	# Charco instantáneo (idéntico a Python: crea el pool antes de la niebla)
	if do_pool:
		create_blood_pool(pos)

	# Niebla de sangre — partículas pequeñas en movimiento
	for _i in range(mist_count):
		var angle := randf_range(0.0, TAU)
		_spawn(
			pos,
			Vector2(cos(angle), sin(angle)) * randf_range(3.0, 10.0),
			[BLOOD_RED, BRIGHT_RED].pick_random(),
			randf_range(3.0, 6.0),
			randf_range(20.0, 45.0),
			0.89,
			false  # sangre: se hornea cuando se detiene
		)

	# Trozos de carne — animados, persistentes, nunca hornean
	for _i in range(chunk_count):
		var angle := randf_range(0.0, TAU)
		var life  := randf_range(100.0, 300.0)
		_spawn(
			pos,
			Vector2(cos(angle), sin(angle)) * randf_range(5.0, 12.0),
			[DARK_BLOOD, GUTS_PINK].pick_random(),
			randf_range(4.0, 9.0),
			life,
			0.91,
			true  # víscera: persiste animada con fade
		)