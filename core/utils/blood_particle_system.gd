extends Node2D
class_name BloodParticleSystem

const BLOOD_RED  := Color8(160,  0,  0)
const DARK_BLOOD := Color8( 80,  0,  0)
const BRIGHT_RED := Color8(200, 20, 20)
const GUTS_PINK  := Color8(180, 90,100)

const MAX_PARTICLES    := 3000
const STOP_THRESHOLD_SQ := 0.01

# Umbrales para auto-LOD
const LOD_CRISIS := 2200   # partículas → calidad 0
const LOD_MID    := 1400   # partículas → calidad 1

var quality: int = 2   # 2=alto 1=medio 0=crisis

@export var chunk_manager: Node2D

# DOD arrays
var p_pos      := PackedVector2Array()
var p_vel      := PackedVector2Array()
var p_color    := PackedColorArray()
var p_size     := PackedFloat32Array()
var p_life     := PackedFloat32Array()
var p_max_life := PackedFloat32Array()
var p_frict    := PackedFloat32Array()
var p_flags    := PackedByteArray()

var active_count: int = 0

var _circle_tex: ImageTexture
var _chunk_tex:  ImageTexture

func _ready() -> void:
	add_to_group("blood_particles")
	p_pos.resize(MAX_PARTICLES);      p_vel.resize(MAX_PARTICLES)
	p_color.resize(MAX_PARTICLES);    p_size.resize(MAX_PARTICLES)
	p_life.resize(MAX_PARTICLES);     p_max_life.resize(MAX_PARTICLES)
	p_frict.resize(MAX_PARTICLES);    p_flags.resize(MAX_PARTICLES)
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
#  LOD automático — se actualiza cada frame
# ════════════════════════════════════════════════════════════════════════════
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)

func auto_update_lod() -> void:
	if   active_count >= LOD_CRISIS: quality = 0
	elif active_count >= LOD_MID:    quality = 1
	else:                            quality = 2

# ════════════════════════════════════════════════════════════════════════════
#  PROCESO
# ════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	# Auto LOD cada frame — coste cero
	auto_update_lod()

	if active_count == 0:
		return

	var dt := delta * 60.0

	var bake_pos  := PackedVector2Array()
	var bake_col  := PackedColorArray()
	var bake_size := PackedFloat32Array()

	var i := active_count - 1
	while i >= 0:
		var is_viscera: bool = (p_flags[i] & 1) == 1
		var vel := p_vel[i]
		vel       *= pow(p_frict[i], dt)
		p_vel[i]   = vel
		p_pos[i]  += vel * dt

		if not is_viscera:
			if vel.length_squared() < STOP_THRESHOLD_SQ:
				if chunk_manager:
					bake_pos.append(p_pos[i])
					bake_col.append(p_color[i])
					bake_size.append(p_size[i] * 1.2)
				_remove(i)
				i -= 1
				continue
			p_life[i] -= 1.0 * dt
			if p_life[i] <= 0.0:
				if chunk_manager:
					bake_pos.append(p_pos[i])
					bake_col.append(p_color[i])
					bake_size.append(p_size[i])
				_remove(i)
		else:
			p_life[i] -= 1.0 * dt
			if p_life[i] <= 0.0:
				_remove(i)
		i -= 1

	if chunk_manager and bake_pos.size() > 0:
		chunk_manager.bake_particles_batch(bake_pos, bake_col, bake_size)

	queue_redraw()

func _remove(i: int) -> void:
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

# ════════════════════════════════════════════════════════════════════════════
#  RENDER
# ════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	for i in range(active_count):
		var pos  := p_pos[i]
		var sz   := p_size[i]
		var col  := p_color[i]
		var is_viscera: bool = (p_flags[i] & 1) == 1

		if is_viscera:
			var life_ratio := p_life[i] / maxf(1.0, p_max_life[i])
			if life_ratio < 0.3:
				col.a = life_ratio / 0.3
			draw_texture_rect(_chunk_tex,
				Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz), false, col)
		else:
			draw_texture_rect(_circle_tex,
				Rect2(pos.x - sz * 0.5, pos.y - sz * 0.5, sz, sz), false, col)

# ════════════════════════════════════════════════════════════════════════════
#  SPAWN INTERNO
# ════════════════════════════════════════════════════════════════════════════
func _spawn(pos: Vector2, vel: Vector2, color: Color,
			size: float, life: float, frict: float, is_viscera: bool) -> void:
	if active_count >= MAX_PARTICLES:
		return
	var i          := active_count
	p_pos[i]       = pos;     p_vel[i]      = vel
	p_color[i]     = color;   p_size[i]     = size
	p_life[i]      = life;    p_max_life[i] = life
	p_frict[i]     = frict;   p_flags[i]    = 1 if is_viscera else 0
	active_count  += 1

# ════════════════════════════════════════════════════════════════════════════
#  EFECTOS PÚBLICOS
# ════════════════════════════════════════════════════════════════════════════

## Salpicadura al impactar. `damage_ratio` 0-1 escala la cantidad (más daño = más sangre).
func create_blood_splatter(
	pos: Vector2,
	direction_vector: Vector2 = Vector2.ZERO,
	force: float = 1.2,
	count: int = 16,
	damage_ratio: float = 0.5
) -> void:
	if quality == 0:
		return

	# Escalar con el daño relativo — a mayor daño, más impresión visual
	var intensity := clampf(damage_ratio, 0.1, 1.0)
	var actual_count: int
	match quality:
		2: actual_count = int(count * 1.0 * intensity)
		1: actual_count = int(count * intensity)
		_: actual_count = 0

	actual_count = maxi(1, actual_count)

	for _i in range(actual_count):
		var angle: float
		var speed: float

		if direction_vector != Vector2.ZERO:
			# Cono dirigido con varianza según intensidad
			var spread: float = lerp(0.4, 0.9, intensity)
			angle = direction_vector.angle() + randf_range(-spread, spread)
			speed = randf_range(4.0, 14.0 * intensity) * force
		else:
			angle = randf_range(0.0, TAU)
			speed = randf_range(3.0, 8.0)

		var sz   := randf_range(4.0, 8.0 + intensity * 4.0)
		var life := randf_range(12.0, 30.0)

		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed,
			   [BLOOD_RED, BRIGHT_RED, DARK_BLOOD].pick_random(),
			   sz, life, 0.82, false)

## Goteo continuo de sangre de un enemigo herido.
func create_blood_drip(pos: Vector2, intensity: float = 1.0) -> void:
	if quality == 0:
		return
	var base_size := minf(10.0, 2.0 + intensity * 0.3)
	var drops     := 1
	if intensity > 15.0:
		drops = randi_range(1, 2)
	for _i in range(drops):
		var col: Color = DARK_BLOOD if intensity > 10.0 else \
			[BLOOD_RED, DARK_BLOOD].pick_random()
		_spawn(pos + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
			   Vector2.ZERO, col, randf_range(base_size, base_size + 3.0),
			   randf_range(60.0, 120.0), 0.0, false)

## Charco instantáneo. Bake directo al ChunkManager.
func create_blood_pool(pos: Vector2, radius_mult: float = 1.0) -> void:
	var blobs: int
	match quality:
		2: blobs = randi_range(6, 10)
		1: blobs = randi_range(3, 5)
		_: blobs = 2

	if chunk_manager:
		var pos_arr  := PackedVector2Array()
		var col_arr  := PackedColorArray()
		var size_arr := PackedFloat32Array()
		for _i in range(blobs):
			var offset_angle := randf_range(0.0, TAU)
			var offset_dist  := randf_range(0.0, 30.0 * radius_mult) if blobs > 1 else 0.0
			var blob_pos     := pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist
			var sz := randf_range(15.0, 35.0 * radius_mult) if quality == 2 else randf_range(10.0, 20.0)
			pos_arr.append(blob_pos);  col_arr.append(DARK_BLOOD);  size_arr.append(sz)
		chunk_manager.bake_particles_batch(pos_arr, col_arr, size_arr)
	else:
		for _i in range(blobs):
			var offset_angle := randf_range(0.0, TAU)
			var blob_pos     := pos + Vector2(cos(offset_angle), sin(offset_angle)) * randf_range(0.0, 25.0)
			_spawn(blob_pos, Vector2.ZERO, DARK_BLOOD,
				   randf_range(15.0, 32.0), 60.0, 0.0, false)

## Explosión gore al morir un enemigo. `size_mult` escala con el tipo de enemigo.
func create_viscera_explosion(pos: Vector2, size_mult: float = 1.0) -> void:
	var mist_count:  int
	var chunk_count: int
	match quality:
		2: mist_count = int(22 * size_mult); chunk_count = int(9 * size_mult)
		1: mist_count = int(6  * size_mult); chunk_count = int(2 * size_mult)
		_: mist_count = 2; chunk_count = 0

	# Charco grande proporcional al enemigo
	create_blood_pool(pos, size_mult)

	# Niebla de sangre
	for _i in range(mist_count):
		var angle := randf_range(0.0, TAU)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * randf_range(3.0, 10.0 * size_mult),
			   [BLOOD_RED, BRIGHT_RED].pick_random(),
			   randf_range(3.0, 6.0 * size_mult), randf_range(20.0, 45.0), 0.89, false)

	# Trozos animados (vísceras)
	for _i in range(chunk_count):
		var angle := randf_range(0.0, TAU)
		var life  := randf_range(100.0, 300.0)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * randf_range(5.0, 13.0 * size_mult),
			   [DARK_BLOOD, GUTS_PINK].pick_random(),
			   randf_range(4.0, 10.0 * size_mult), life, 0.91, true)