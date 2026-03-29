extends Node2D
class_name BloodSystem

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  blood_system.gd — ProyectSurvivor
##
##  Sistema de sangre y partículas gore con baking en chunks.
##  Port del sistema de pygame (ParticleSystem + ChunkManager).
##
##  ARQUITECTURA:
##    Pool circular de partículas (struct-of-arrays, sin nodos por partícula).
##    Chunks de mundo como Image + ImageTexture → Sprite2D por chunk.
##    Partículas líquidas detenidas se "bakean" en el chunk correspondiente.
##    Partículas activas se dibujan con draw_rect() en _draw().
##
##  INTEGRACIÓN:
##    Agregar a grupo "blood_particles". El EnemyManager ya busca este grupo.
##    Métodos públicos coinciden con las llamadas en EnemyManager.damage_enemy()
##    y _kill_enemy().
##
##  LOD:
##    quality 0 = CRISIS  → mínimo visual, skips agresivos
##    quality 1 = MEDIO   → efectos reducidos
##    quality 2 = ALTO    → comportamiento completo
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Configuración ─────────────────────────────────────────────────
@export var capacity     : int = 1500    ## Partículas máximas simultáneas
@export var chunk_size   : int = 512     ## Px de mundo por chunk
@export var evict_margin : int = 3       ## Chunks fuera de vista antes de evicción

# ── Paleta ────────────────────────────────────────────────────────
const C_BLOOD  := Color(0.63, 0.0, 0.0, 1.0)
const C_DARK   := Color(0.31, 0.0, 0.0, 1.0)
const C_PINK   := Color(0.71, 0.35, 0.39, 1.0)
const C_BRIGHT := Color(0.78, 0.08, 0.08, 1.0)
const PALETTE  : Array[Color] = [C_BLOOD, C_DARK, C_PINK, C_BRIGHT]

# ── Flags de partícula (bitfield) ─────────────────────────────────
const F_ALIVE  := 1
const F_CHUNK  := 2   # trozo de carne — persiste más, no se bakea
const F_LIQUID := 4   # sangre líquida — se bakea al detenerse

# ── Pool (struct-of-arrays) ───────────────────────────────────────
var _px     : PackedFloat32Array
var _py     : PackedFloat32Array
var _vx     : PackedFloat32Array
var _vy     : PackedFloat32Array
var _life   : PackedFloat32Array
var _mlife  : PackedFloat32Array   # max lifetime
var _size   : PackedFloat32Array
var _osize  : PackedFloat32Array   # original size
var _cidx   : PackedInt32Array     # índice de color en PALETTE
var _flags  : PackedInt32Array
var _next   : int = 0
var _alive  : int = 0

# ── Calidad / LOD ────────────────────────────────────────────────
var quality : int = 2  ## 0=Crisis 1=Medio 2=Alto

# ── Chunks ────────────────────────────────────────────────────────
# Cada chunk: { "image": Image, "texture": ImageTexture, "dirty": bool }
var _chunks        : Dictionary = {}
var _chunk_sprites : Dictionary = {}   # Vector2i → Sprite2D
var _floor_container : Node2D

# ── Stamp cache ──────────────────────────────────────────────────
# Pre-crea imágenes pequeñas para blend_rect sobre los chunks.
var _stamps : Dictionary = {}   # Vector2i(color_idx, size_bucket) → Image

# ── Visibility ───────────────────────────────────────────────────
var _vis_rect : Rect2 = Rect2()
var _evict_timer : float = 0.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INICIALIZACIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	add_to_group("blood_particles")

	# Este nodo dibuja partículas activas ENCIMA de las entidades
	z_index = 10

	# Contenedor de chunks: z absoluto negativo → debajo de entidades
	_floor_container = Node2D.new()
	_floor_container.name = "FloorChunks"
	_floor_container.z_index = -10
	_floor_container.z_as_relative = false
	add_child(_floor_container)

	_init_pool()
	_init_stamps()


func _init_pool() -> void:
	_px.resize(capacity);    _py.resize(capacity)
	_vx.resize(capacity);    _vy.resize(capacity)
	_life.resize(capacity);  _mlife.resize(capacity)
	_size.resize(capacity);  _osize.resize(capacity)
	_cidx.resize(capacity);  _flags.resize(capacity)
	_flags.fill(0)


func _init_stamps() -> void:
	## Genera imágenes de stamp para cada combo color × tamaño.
	## Se usan con Image.blend_rect() para pintar sangre en los chunks.
	var sizes := [2, 3, 4, 6, 8, 10, 14, 18, 24]
	for ci in PALETTE.size():
		var c := PALETTE[ci]
		for s in sizes:
			var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
			# Alpha variada para que superposiciones den profundidad
			var stamp_color := Color(c.r, c.g, c.b, randf_range(0.6, 0.9))
			img.fill(stamp_color)
			_stamps[Vector2i(ci, s)] = img


func _get_stamp(color_idx: int, px_size: int) -> Image:
	## Devuelve el stamp más cercano al tamaño pedido.
	var buckets := [2, 3, 4, 6, 8, 10, 14, 18, 24]
	var best := 4
	var best_d := 999
	for b in buckets:
		var d := absi(b - px_size)
		if d < best_d:
			best_d = d
			best = b
	var key := Vector2i(clampi(color_idx, 0, 3), best)
	if _stamps.has(key):
		return _stamps[key]
	return _stamps[Vector2i(0, 4)]


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SPAWN INTERNO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _spawn(x: float, y: float, vel_x: float, vel_y: float,
			color_idx: int, sz: int, lifetime: float,
			is_chunk: bool = false, is_liquid: bool = true) -> void:
	var i := _next
	if _flags[i] & F_ALIVE:
		_alive -= 1

	_px[i]    = x;           _py[i]    = y
	_vx[i]    = vel_x;       _vy[i]    = vel_y
	_life[i]  = lifetime;    _mlife[i] = lifetime
	_size[i]  = float(sz);   _osize[i] = float(sz)
	_cidx[i]  = clampi(color_idx, 0, 3)

	var f := F_ALIVE
	if is_chunk:  f |= F_CHUNK
	if is_liquid: f |= F_LIQUID
	_flags[i] = f

	_next = (_next + 1) % capacity
	_alive += 1


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  API PÚBLICA — llamada desde EnemyManager
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Salpicadura direccional al impacto de bala.
## direction: dirección normalizada del proyectil.
## dmg_ratio: 0-1, proporcional al daño relativo a HP máx del enemigo.
func create_blood_splatter(pos: Vector2, direction: Vector2 = Vector2.ZERO,
						   force: float = 1.2, count: int = 6,
						   dmg_ratio: float = 0.5) -> void:
	if quality == 0:
		return

	var actual : int
	if quality == 2:
		actual = count + int(dmg_ratio * 6.0)
	else:
		actual = maxi(1, int(count / 2.0))

	var has_dir := direction.length_squared() > 0.01
	var base_angle := direction.angle() if has_dir else 0.0

	for _j in actual:
		var angle : float
		var speed : float
		if has_dir:
			angle = base_angle + randf_range(-0.55, 0.55)
			speed = randf_range(4.0, 13.0) * force
		else:
			angle = randf() * TAU
			speed = randf_range(2.0, 7.0)

		var vel := Vector2(cos(angle), sin(angle)) * speed
		# Colores: BLOOD(0), BRIGHT(3), DARK(1)
		var ci: int = [0, 3, 1][randi() % 3]
		var sz := randi_range(2, 5)
		_spawn(pos.x, pos.y, vel.x, vel.y, ci, sz,
			   randf_range(0.7, 1.3), false, true)


## Explosión gore al morir un enemigo.
## size_factor: escala visual (tamaño del enemigo / 40).
func create_viscera_explosion(pos: Vector2, size_factor: float = 1.0) -> void:
	var mist_count  : int
	var chunk_count : int
	var pool_spawn  : bool

	match quality:
		2:  mist_count = 22; chunk_count = 9; pool_spawn = true
		1:  mist_count = 6;  chunk_count = 2; pool_spawn = true
		_:  mist_count = 2;  chunk_count = 0; pool_spawn = false

	# Charco de sangre en el suelo
	if pool_spawn:
		_create_blood_pool(pos, size_factor)

	var sf := clampf(size_factor, 0.5, 3.0)

	# Niebla de sangre (partículas rápidas que se bakean pronto)
	for _j in mist_count:
		var angle := randf() * TAU
		var speed := randf_range(3.0, 10.0) * sf
		var ci := 0 if randf() < 0.5 else 3   # BLOOD o BRIGHT
		_spawn(pos.x, pos.y, cos(angle) * speed, sin(angle) * speed,
			   ci, randi_range(3, 6), randf_range(0.35, 0.75), false, true)

	# Trozos de carne (F_CHUNK → no se bakean, persisten, cuadrados rosados)
	for _j in chunk_count:
		var angle := randf() * TAU
		var speed := randf_range(5.0, 12.0) * sf
		var ci := 1 if randf() < 0.5 else 2   # DARK o PINK
		_spawn(pos.x, pos.y, cos(angle) * speed, sin(angle) * speed,
			   ci, randi_range(4, int(9 * sf)), randf_range(1.6, 5.0), true, false)


## Mancha de herida inmediata en el suelo al recibir daño significativo.
func create_wound_stain(pos: Vector2, dmg_ratio: float = 0.5) -> void:
	if quality == 0:
		return

	var blobs := 1 + int(dmg_ratio * 3.0)
	for _j in blobs:
		var ox := randf_range(-8.0, 8.0)
		var oy := randf_range(-8.0, 8.0)
		var sz := randi_range(3, int(8 + dmg_ratio * 10))
		# Spawn con velocidad 0 → se bakea inmediatamente en el próximo frame
		_spawn(pos.x + ox, pos.y + oy, 0.0, 0.0,
			   1, sz, 0.5, false, true)


## Goteo de sangre mientras el enemigo se mueve (sangrado continuo).
func create_blood_drip(pos: Vector2, intensity: float) -> void:
	if quality == 0:
		return

	var base_size := mini(10, 2 + int(intensity * 0.3))
	var drops := 1
	if intensity > 15.0:
		drops = randi_range(1, 2)

	for _j in drops:
		var sx := pos.x + randf_range(-4.0, 4.0)
		var sy := pos.y + randf_range(-4.0, 4.0)
		var ci := 1 if intensity > 10.0 else randi_range(0, 1)
		_spawn(sx, sy, randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			   ci, randi_range(base_size, base_size + 3),
			   randf_range(1.0, 2.0), false, true)


## LOD automático — llamar desde gameplay con datos de carga.
func set_quality_auto(visible_enemies: int, alive_particles: int) -> void:
	if visible_enemies > 350 or alive_particles > 600:
		quality = 0
	elif visible_enemies > 180 or alive_particles > 350:
		quality = 1
	else:
		quality = 2


# ── Helpers internos ──────────────────────────────────────────────

func _create_blood_pool(pos: Vector2, size_factor: float = 1.0) -> void:
	var blobs : int
	match quality:
		2:  blobs = randi_range(4, 8)
		1:  blobs = randi_range(2, 3)
		_:  blobs = 1

	var sf := clampf(size_factor, 0.5, 2.5)
	for _j in blobs:
		var od := randf_range(0.0, 18.0 * sf) if blobs > 1 else 0.0
		var oa := randf() * TAU
		var bsize : int
		if quality == 2:
			bsize = randi_range(int(10 * sf), int(24 * sf))
		else:
			bsize = randi_range(6, 12)
		_spawn(pos.x + cos(oa) * od, pos.y + sin(oa) * od,
			   0.0, 0.0, 1, bsize, randf_range(1.0, 2.0), false, true)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  UPDATE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _process(delta: float) -> void:
	if _alive <= 0:
		_alive = 0
		# Aún así actualizamos chunks y redibujamos por si quedan dirty
		_update_visible_rect()
		_update_chunk_visibility()
		queue_redraw()
		return

	var freed := 0

	for i in capacity:
		var f := _flags[i]
		if not (f & F_ALIVE):
			continue

		var vx := _vx[i]
		var vy := _vy[i]

		# Fricción frame-rate independent
		var friction := 0.91 if (f & F_CHUNK) else 0.84
		# pow(friction, delta*60) normaliza a 60fps
		var friction_dt := pow(friction, delta * 60.0)
		vx *= friction_dt
		vy *= friction_dt
		_vx[i] = vx
		_vy[i] = vy

		_px[i] += vx * delta * 60.0
		_py[i] += vy * delta * 60.0

		# Decremento de vida
		var is_slow := absf(vx) < 1.0 and absf(vy) < 1.0
		var is_liquid_flag := bool(f & F_LIQUID)
		var is_chunk_flag  := bool(f & F_CHUNK)

		if is_liquid_flag and not is_chunk_flag and is_slow:
			# Partícula líquida detenida: vida se consume rápido → bakeo
			_life[i] -= delta * 12.0
		else:
			_life[i] -= delta

		if _life[i] <= 0.0:
			_flags[i] = 0
			freed += 1
			continue

		# Baking: partícula líquida + detenida → estampar en chunk
		if is_liquid_flag and not is_chunk_flag and is_slow:
			_bake_particle(i)
			_flags[i] = 0
			freed += 1

	_alive -= freed
	if _alive < 0:
		_alive = 0

	# Visibility y mantenimiento de chunks
	_update_visible_rect()
	_update_chunk_textures()
	_update_chunk_visibility()

	# Evicción periódica de chunks lejanos (cada ~2 segundos)
	_evict_timer += delta
	if _evict_timer >= 2.0:
		_evict_timer = 0.0
		_evict_distant_chunks()

	queue_redraw()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  BAKING — estampar partícula en chunk
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _bake_particle(i: int) -> void:
	var wx := _px[i]
	var wy := _py[i]
	var ci := _cidx[i]
	var sz := maxi(2, int(_size[i]))

	var ck := Vector2i(floori(wx / float(chunk_size)), floori(wy / float(chunk_size)))

	# Crear chunk si no existe
	if not _chunks.has(ck):
		var img := Image.create(chunk_size, chunk_size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var tex := ImageTexture.create_from_image(img)
		_chunks[ck] = { "image": img, "texture": tex, "dirty": false }
		_create_chunk_sprite(ck)

	var chunk_data : Dictionary = _chunks[ck]
	var local_x := int(wx) - ck.x * chunk_size - int(sz / 2.0)
	var local_y := int(wy) - ck.y * chunk_size - int(sz / 2.0)

	var stamp := _get_stamp(ci, sz)
	var src_rect := Rect2i(0, 0, stamp.get_width(), stamp.get_height())
	var dst := Vector2i(local_x, local_y)

	# blend_rect() hace alpha blending correcto sobre la Image del chunk
	chunk_data["image"].blend_rect(stamp, src_rect, dst)
	chunk_data["dirty"] = true


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  GESTIÓN DE CHUNKS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _create_chunk_sprite(ck: Vector2i) -> void:
	if _chunk_sprites.has(ck):
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(ck.x * chunk_size, ck.y * chunk_size)
	sprite.texture = _chunks[ck]["texture"]
	# TEXTURE_FILTER_NEAREST → look pixelado "low quality" como en pygame
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_container.add_child(sprite)
	_chunk_sprites[ck] = sprite


func _update_chunk_textures() -> void:
	## Sube a GPU solo los chunks modificados desde el último frame.
	for ck in _chunks:
		var data : Dictionary = _chunks[ck]
		if data["dirty"]:
			# ImageTexture.update() reutiliza el recurso GPU existente
			data["texture"].update(data["image"])
			data["dirty"] = false


func _update_chunk_visibility() -> void:
	## Muestra/oculta sprites según si están en pantalla.
	for ck in _chunk_sprites:
		var sprite : Sprite2D = _chunk_sprites[ck]
		var chunk_rect := Rect2(
			Vector2(ck.x * chunk_size, ck.y * chunk_size),
			Vector2(chunk_size, chunk_size)
		)
		sprite.visible = _vis_rect.intersects(chunk_rect)


func _evict_distant_chunks() -> void:
	## Elimina chunks muy lejos de la vista para liberar RAM.
	var margin := evict_margin * chunk_size
	var expanded := _vis_rect.grow(margin)

	var to_remove : Array[Vector2i] = []
	for ck in _chunks:
		var chunk_rect := Rect2(
			Vector2(ck.x * chunk_size, ck.y * chunk_size),
			Vector2(chunk_size, chunk_size)
		)
		if not expanded.intersects(chunk_rect):
			to_remove.append(ck)

	for ck in to_remove:
		_chunks.erase(ck)
		if _chunk_sprites.has(ck):
			_chunk_sprites[ck].queue_free()
			_chunk_sprites.erase(ck)


func _update_visible_rect() -> void:
	## Calcula el rect visible en coordenadas de mundo usando la
	## transform inversa del canvas (funciona con cualquier Camera2D).
	var ctf := get_canvas_transform()
	var vp_size := get_viewport_rect().size
	var inv := ctf.affine_inverse()
	var tl := inv * Vector2.ZERO
	var br := inv * vp_size
	_vis_rect = Rect2(tl, br - tl).grow(200.0)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  RENDER — partículas activas (en el aire)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	if _alive <= 0:
		return

	for i in capacity:
		var f := _flags[i]
		if not (f & F_ALIVE):
			continue

		var px := _px[i]
		var py := _py[i]

		# Culling: no dibujar fuera de pantalla
		if not _vis_rect.has_point(Vector2(px, py)):
			continue

		var lr := _life[i] / maxf(0.001, _mlife[i])
		if lr <= 0.0:
			continue

		var alpha := clampf(lr, 0.0, 1.0)
		if alpha < 0.04:
			continue

		var ci := _cidx[i]
		var col := Color(PALETTE[ci].r, PALETTE[ci].g, PALETTE[ci].b, alpha)

		var is_chunk_flag := bool(f & F_CHUNK)
		var cur_size : float

		if is_chunk_flag:
			# Chunks de carne: mantienen tamaño, se desvanecen
			cur_size = _size[i]
		else:
			# Sangre líquida en aire: encoge con el tiempo
			cur_size = maxf(1.0, _osize[i] * lr)

		var half := cur_size * 0.5
		# draw_rect en coordenadas de mundo — Camera2D aplica transform
		draw_rect(Rect2(px - half, py - half, cur_size, cur_size), col)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CLEANUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func clear_all() -> void:
	## Limpia todo — llamar al reiniciar nivel.
	_flags.fill(0)
	_alive = 0
	_next = 0
	_chunks.clear()
	for sprite in _chunk_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	_chunk_sprites.clear()


func get_alive_count() -> int:
	return _alive


func get_debug_info() -> Dictionary:
	return {
		"particles_alive": _alive,
		"particles_capacity": capacity,
		"chunks_loaded": _chunks.size(),
		"chunks_visible": _chunk_sprites.values().filter(
			func(s: Sprite2D): return s.visible).size(),
		"quality": quality,
	}