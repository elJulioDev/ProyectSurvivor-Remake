extends Node2D
class_name BloodParticleSystem

const BLOOD_RED = Color8(160, 0, 0)
const DARK_BLOOD = Color8(80, 0, 0)
const BRIGHT_RED = Color8(200, 20, 20)
const GUTS_PINK = Color8(180, 90, 100)

const MAX_PARTICLES = 3000
const LOD_CRISIS = 2500

# ====== ARQUITECTURA DOD (Structure of Arrays) ======
# En lugar de objetos, usamos memoria contigua pura. Es brutalmente más rápido en GDScript.
var p_pos := PackedVector2Array()
var p_vel := PackedVector2Array()
var p_color := PackedColorArray()
var p_size := PackedFloat32Array()
var p_life := PackedFloat32Array()
var p_frict := PackedFloat32Array()
var p_flags := PackedByteArray() # 0 = Sangre (Círculo/Horneable), 1 = Víscera (Cuadrada)

var active_count: int = 0
var circle_tex: ImageTexture

@export var chunk_manager: Node2D

func _ready() -> void:
	add_to_group("blood_particles")
	
	# 1. Pre-reservar RAM. ¡0 creaciones de objetos durante el gameplay!
	p_pos.resize(MAX_PARTICLES)
	p_vel.resize(MAX_PARTICLES)
	p_color.resize(MAX_PARTICLES)
	p_size.resize(MAX_PARTICLES)
	p_life.resize(MAX_PARTICLES)
	p_frict.resize(MAX_PARTICLES)
	p_flags.resize(MAX_PARTICLES)
	
	# 2. Generar UNA textura circular blanca para usar como sello ultrarrápido
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center = Vector2(16, 16)
	for y in range(32):
		for x in range(32):
			if Vector2(x, y).distance_to(center) <= 15.5:
				img.set_pixel(x, y, Color.WHITE)
	circle_tex = ImageTexture.create_from_image(img)

# Función interna hiper-optimizada para inyectar datos
func _spawn(pos: Vector2, vel: Vector2, color: Color, size: float, life: float, frict: float, is_viscera: bool) -> void:
	if active_count >= MAX_PARTICLES: return
	var i = active_count
	p_pos[i] = pos
	p_vel[i] = vel
	p_color[i] = color
	p_size[i] = size
	p_life[i] = life
	p_frict[i] = frict
	p_flags[i] = 1 if is_viscera else 0
	active_count += 1

func _process(delta: float) -> void:
	if active_count == 0: return
	
	var dt = delta * 60.0 
	var i = active_count - 1
	
	# Lotes (Batches) para mandar al ChunkManager y no saturar la CPU
	var bake_pos = PackedVector2Array()
	var bake_col = PackedColorArray()
	var bake_size = PackedFloat32Array()
	
	while i >= 0:
		# Extraer a variables locales es más rápido
		var vel = p_vel[i]
		vel *= pow(p_frict[i], dt)
		p_vel[i] = vel
		p_pos[i] += vel * dt
		
		var speed_sq = vel.length_squared()
		var is_viscera = p_flags[i] == 1
		
		if not is_viscera and speed_sq < 0.01:
			p_vel[i] = Vector2.ZERO
			p_life[i] -= 0.2 * dt
		else:
			p_life[i] -= 1.0 * dt
			
		# Si muere
		if p_life[i] <= 0:
			if not is_viscera and chunk_manager:
				bake_pos.append(p_pos[i])
				bake_col.append(p_color[i])
				bake_size.append(p_size[i] * 1.5) # Charcos más grandes
				
			# Swap and Pop O(1) con Arrays Planos
			active_count -= 1
			if i != active_count: # Sobrescribir con el último elemento vivo
				p_pos[i] = p_pos[active_count]
				p_vel[i] = p_vel[active_count]
				p_color[i] = p_color[active_count]
				p_size[i] = p_size[active_count]
				p_life[i] = p_life[active_count]
				p_frict[i] = p_frict[active_count]
				p_flags[i] = p_flags[active_count]
		i -= 1
		
	# Enviar el lote completo al administrador de sangre en el suelo
	if chunk_manager and bake_pos.size() > 0:
		chunk_manager.bake_particles_batch(bake_pos, bake_col, bake_size)
		
	queue_redraw()

func _draw() -> void:
	for i in range(active_count):
		var size = p_size[i]
		var col = p_color[i]
		var pos = p_pos[i]
		
		if p_flags[i] == 1:
			# Vísceras: Cuadrados sólidos (draw_rect)
			draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), col)
		else:
			# Sangre: Textura circular teñida (100x más rápido que draw_circle)
			draw_texture_rect(circle_tex, Rect2(pos.x - size/2, pos.y - size/2, size, size), false, col)

# === EFECTOS DE GENERACIÓN ===

func create_blood_splatter(pos: Vector2, direction_vector: Vector2 = Vector2.ZERO, force: float = 1.0, count: int = 4) -> void:
	# Sin multiplicadores locos. Si hay muchas partículas, generamos la mitad.
	var actual_count = count
	if active_count > LOD_CRISIS:
		actual_count = maxi(1, int(count / 2.0))

	for _i in range(actual_count):
		var angle = randf_range(0, TAU)
		var speed = randf_range(2, 5) # Velocidad más contenida
		
		if direction_vector != Vector2.ZERO:
			# Cono de dispersión más cerrado (-0.5 a 0.5 radianes)
			angle = direction_vector.angle() + randf_range(-0.5, 0.5) 
			speed = randf_range(4, 9) * force
			
		var col = [BLOOD_RED, BRIGHT_RED, DARK_BLOOD].pick_random()
		
		# Tamaño más grande (6 a 11) para que formen manchas/charcos sólidos al caer,
		# pero con un tiempo de vida un poco menor para que se peguen al piso rápido.
		var size = randf_range(6, 11)
		var lifetime = randf_range(30, 50) 
		
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col, size, lifetime, 0.82, false)

func create_blood_drip(pos: Vector2, intensity: float = 1.0) -> void:
	if active_count > LOD_CRISIS: return
	var base_size = min(12.0, 3.0 + int(intensity * 0.4))
	var col = DARK_BLOOD if intensity > 10 else [BLOOD_RED, DARK_BLOOD].pick_random()
	_spawn(pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)), Vector2.ZERO, col, randf_range(base_size, base_size + 4), randf_range(60, 120), 0.0, false)

func create_viscera_explosion(pos: Vector2) -> void:
	var mist_count = 22
	var chunk_count = 9
	var pool_blobs = randi_range(6, 12)
	
	if active_count > LOD_CRISIS:
		mist_count = 4; chunk_count = 2; pool_blobs = 2

	# Niebla
	for _i in range(mist_count): 
		var angle = randf_range(0, TAU)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * randf_range(4, 12), [BLOOD_RED, BRIGHT_RED].pick_random(), randf_range(4, 8), randf_range(20, 45), 0.89, false)

	# Trozos de carne cuadrados (is_viscera = true)
	for _i in range(chunk_count):
		var angle = randf_range(0, TAU)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * randf_range(5, 14), [DARK_BLOOD, GUTS_PINK].pick_random(), randf_range(6, 12), randf_range(100, 300), 0.91, true)

	if chunk_manager:
		var pos_arr = PackedVector2Array()
		var col_arr = PackedColorArray()
		var size_arr = PackedFloat32Array()
		for _i in range(pool_blobs):
			var offset_angle = randf_range(0, TAU)
			var offset_dist = randf_range(0, 30)
			pos_arr.append(pos + Vector2(cos(offset_angle), sin(offset_angle)) * offset_dist)
			col_arr.append(DARK_BLOOD)
			size_arr.append(randf_range(15, 35)) # Charcos gigantes e irregulares
		chunk_manager.bake_particles_batch(pos_arr, col_arr, size_arr)