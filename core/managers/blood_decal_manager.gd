## blood_chunk_manager.gd
## Gestor de decales de sangre en el suelo — ProyectSurvivor (Godot 4)
##
## ARQUITECTURA DE CHUNKS:
##   El mundo se divide en cuadrados de CHUNK_SIZE × CHUNK_SIZE px.
##   Cada chunk tiene una Image + ImageTexture pintada a escala reducida
##   (BAKE_SCALE) para ahorrar VRAM. Las partículas que se detienen
##   se "hornean" en el chunk correspondiente como manchas orgánicas.
##
## PINCELES ORGÁNICOS (get_brush):
##   Cada mancha se pinta en múltiples capas concéntricas para dar
##   un aspecto orgánico y creíble:
##     · Halo exterior  — radio × 1.8, alpha bajo (sangre dispersa)
##     · Cuerpo         — radio × 1.0, alpha medio (mancha principal)
##     · Núcleo oscuro  — radio × 0.42, alpha alto (sangre coagulada)
##     · Satélites      — 2-4 gotas pequeñas alrededor
##   El pincel se cachea por (radio_cuantizado, color_cuantizado)
##   → máx MAX_BRUSH_CACHE entradas distintas en memoria.
##
## CULLING Y EVICTION:
##   · Solo se sube la textura GPU de los chunks visibles (dentro de
##     la viewport + margen UPLOAD_MARGIN).
##   · Cada EVICT_INTERVAL segundos se liberan los chunks a más de
##     EVICT_RADIUS chunks de distancia de la cámara.
##
## USO DESDE BloodParticleSystem:
##   chunk_manager.bake_particles_batch(positions, colors, sizes)
##
## USO DESDE EnemyManager / gameplay:
##   chunk_manager.bake_particles_batch(...)
##
## NOTA: Este nodo debe ser hijo de World en gameplay.tscn,
##       con z_index = -1 (por debajo de enemigos y jugador).

extends Node2D
class_name BloodChunkManager

# ════════════════════════════════════════════════════════════════════
#  CONFIGURACIÓN
# ════════════════════════════════════════════════════════════════════

## Tamaño del chunk en pixels del mundo
const CHUNK_SIZE        : int   = 1000

## Escala de bake: 0.5 → imagen de 500×500 para un chunk de 1000×1000
## Reduce la memoria de VRAM a la cuarta parte sin pérdida visual notable
const BAKE_SCALE        : float = 0.5

## Máximo de pinceles cacheados en RAM (Image, no textura)
const MAX_BRUSH_CACHE   : int   = 160

## Margen extra de viewport para carga de chunks (en px de mundo)
const UPLOAD_MARGIN     : float = 800.0

## Intervalo entre limpiezas de chunks lejanos (segundos)
const EVICT_INTERVAL    : float = 12.0

## Radio de chunks a conservar alrededor de la cámara (en unidades chunk)
const EVICT_RADIUS      : int   = 6

## Paleta de colores de sangre (usada para cuantizar colores del pincel)
const PALETTE := [
	Color8(160,  0,  0),   # rojo sangre
	Color8( 80,  0,  0),   # rojo oscuro / coagulado
	Color8(200, 20, 20),   # rojo brillante
	Color8(180, 90,100),   # rosa vísceras
]

# ════════════════════════════════════════════════════════════════════
#  CLASE CHUNK
# ════════════════════════════════════════════════════════════════════

class BloodChunk:
	var cx       : int
	var cy       : int
	var image    : Image
	var texture  : ImageTexture
	var sprite   : Sprite2D
	var dirty    : bool = false          # imagen modificada, necesita upload GPU
	var _mgr     : Node2D

	func _init(_cx: int, _cy: int, mgr: Node2D) -> void:
		cx = _cx; cy = _cy; _mgr = mgr

		var ws     : int = BloodChunkManager.CHUNK_SIZE
		var bs_int : int = int(ws * BloodChunkManager.BAKE_SCALE)

		image   = Image.create(bs_int, bs_int, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)

		sprite          = Sprite2D.new()
		sprite.texture  = texture
		sprite.centered = false
		sprite.position = Vector2(_cx * ws, _cy * ws)
		# Escalar el sprite de baked_size → world_size
		var world_scale := float(ws) / float(bs_int)
		sprite.scale    = Vector2(world_scale, world_scale)

	## Agrega el sprite al árbol de escena
	func attach(parent: Node) -> void:
		parent.add_child(sprite)

	## Quita el sprite del árbol y libera memoria de GPU
	func detach() -> void:
		if is_instance_valid(sprite) and sprite.get_parent():
			sprite.get_parent().remove_child(sprite)
			sprite.queue_free()

	## Hornea un lote de manchas en la imagen del chunk
	func bake_batch(datos: Array) -> void:
		var bs_int : int   = int(BloodChunkManager.CHUNK_SIZE * BloodChunkManager.BAKE_SCALE)
		var bs     : float = BloodChunkManager.BAKE_SCALE
		var world_x : float = float(cx * BloodChunkManager.CHUNK_SIZE)
		var world_y : float = float(cy * BloodChunkManager.CHUNK_SIZE)

		for d in datos:
			# Obtener el pincel orgánico multicapa del manager
			var layers : Array = _mgr.get_brush_layers(d.size / 2.0, d.col)
			for layer in layers:
				var brush : Image = layer.img
				if brush == null:
					continue
				var bw  : int = brush.get_width()
				var bh  : int = brush.get_height()

				# Convertir de coordenadas mundo → coordenadas de imagen del chunk
				var local_x := float(d.pos.x - world_x) * bs
				var local_y := float(d.pos.y - world_y) * bs
				var bx : int = int(local_x + layer.offset_x * bs) - int(bw / 2.0)
				var by : int = int(local_y + layer.offset_y * bs) - int(bh / 2.0)

				# Clipping manual
				var src_x := 0; var src_y := 0
				var src_w := bw; var src_h := bh
				if bx < 0:
					src_x -= bx; src_w += bx; bx = 0
				if by < 0:
					src_y -= by; src_h += by; by = 0
				src_w = mini(src_w, bs_int - bx)
				src_h = mini(src_h, bs_int - by)
				if src_w <= 0 or src_h <= 0:
					continue

				image.blend_rect(brush, Rect2i(src_x, src_y, src_w, src_h), Vector2i(bx, by))

		dirty = true

	## Sube la imagen a GPU (solo si dirty y es visible)
	func upload_if_dirty() -> void:
		if dirty:
			texture.update(image)
			dirty = false

# ════════════════════════════════════════════════════════════════════
#  ESTADO DEL MANAGER
# ════════════════════════════════════════════════════════════════════

## Diccionario (Vector2i → BloodChunk)
var chunks      : Dictionary = {}

## Cache de pinceles base: key (String) → Array of {img, offset_x, offset_y}
## Cada entrada contiene las 3-5 capas orgánicas del pincel.
var brush_cache : Dictionary = {}

var _evict_timer  : float   = 0.0
var _camera_ref   : Camera2D = null

# ════════════════════════════════════════════════════════════════════
#  PROCESO
# ════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# z_index negativo: el suelo de sangre debe renderizarse bajo todo
	z_index = 0

func _process(delta: float) -> void:
	# Obtener cámara una vez y cachear
	if not is_instance_valid(_camera_ref):
		_camera_ref = get_viewport().get_camera_2d()

	# Upload de chunks sucios visibles
	var cam_rect := _get_camera_world_rect()
	for key in chunks:
		var chunk : BloodChunk = chunks[key]
		if not chunk.dirty:
			continue
		var chunk_rect := Rect2(
			float(key.x * CHUNK_SIZE), float(key.y * CHUNK_SIZE),
			float(CHUNK_SIZE), float(CHUNK_SIZE)
		)
		if cam_rect.intersects(chunk_rect):
			chunk.upload_if_dirty()
		# Si el chunk no es visible, queda dirty y se sube cuando llegue la cámara

	# Eviction periódica de chunks lejanos
	_evict_timer += delta
	if _evict_timer >= EVICT_INTERVAL and is_instance_valid(_camera_ref):
		_evict_timer = 0.0
		_evict_distant(_camera_ref.get_screen_center_position())

# ════════════════════════════════════════════════════════════════════
#  GESTIÓN DE CHUNKS
# ════════════════════════════════════════════════════════════════════

func _get_or_create_chunk(world_x: float, world_y: float) -> BloodChunk:
	var cx  : int     = int(floor(world_x / float(CHUNK_SIZE)))
	var cy  : int     = int(floor(world_y / float(CHUNK_SIZE)))
	var key : Vector2i = Vector2i(cx, cy)
	if not chunks.has(key):
		var c := BloodChunk.new(cx, cy, self)
		chunks[key] = c
		c.attach(self)
	return chunks[key]

func _get_camera_world_rect() -> Rect2:
	if not is_instance_valid(_camera_ref):
		return Rect2(-99999.0, -99999.0, 199998.0, 199998.0)
	var vp_size := get_viewport_rect().size
	var zoom    := _camera_ref.zoom
	var half    := vp_size / (2.0 * zoom)
	var center  := _camera_ref.get_screen_center_position()
	return Rect2(
		center - half - Vector2.ONE * UPLOAD_MARGIN,
		vp_size / zoom + Vector2.ONE * UPLOAD_MARGIN * 2.0
	)

func _evict_distant(camera_world_pos: Vector2) -> void:
	var r_sq   := float(EVICT_RADIUS * EVICT_RADIUS)
	var to_del : Array[Vector2i] = []
	for key in chunks.keys():
		var cx_center := (float(key.x) + 0.5) * float(CHUNK_SIZE)
		var cy_center := (float(key.y) + 0.5) * float(CHUNK_SIZE)
		var dx        := (cx_center - camera_world_pos.x) / float(CHUNK_SIZE)
		var dy        := (cy_center - camera_world_pos.y) / float(CHUNK_SIZE)
		if dx * dx + dy * dy > r_sq:
			to_del.append(key)
	for key in to_del:
		var c : BloodChunk = chunks[key]
		c.detach()
		chunks.erase(key)

# ════════════════════════════════════════════════════════════════════
#  CACHE DE PINCELES ORGÁNICOS
# ════════════════════════════════════════════════════════════════════

## Devuelve el array de capas del pincel orgánico para (world_radius, color).
## Cada capa es un Dictionary {img: Image, offset_x: float, offset_y: float}.
## Las capas se generan una vez y se cachean.
func get_brush_layers(world_radius: float, color: Color) -> Array:
	var r_key   : int    = _quantize_radius(world_radius)
	var q_color : Color  = _quantize_color(color)
	var cache_key : String = str(r_key) + "_" + q_color.to_html(false)

	if brush_cache.has(cache_key):
		return brush_cache[cache_key]

	# Límite del cache: descartar la mitad más antigua
	if brush_cache.size() >= MAX_BRUSH_CACHE:
		var limit : int  = int(MAX_BRUSH_CACHE / 2.0)
		var old_keys     = brush_cache.keys().slice(0, limit)
		for k in old_keys:
			brush_cache.erase(k)

	var layers : Array = _build_brush_layers(r_key, q_color)
	brush_cache[cache_key] = layers
	return layers

## Construye las capas del pincel orgánico multicapa.
func _build_brush_layers(r: int, base_color: Color) -> Array:
	var layers : Array = []
	var bs     : float = BAKE_SCALE

	# ── Capa 1: Halo exterior (sangre dispersa, alpha bajo) ───────
	var halo_r : int = maxi(2, int(r * 1.8 * bs))
	layers.append({
		"img":      _make_circle_image(halo_r, base_color, 0.22, true),
		"offset_x": 0.0,
		"offset_y": 0.0
	})

	# ── Capa 2: Cuerpo principal ──────────────────────────────────
	var body_r : int = maxi(1, int(r * bs))
	layers.append({
		"img":      _make_circle_image(body_r, base_color, 0.72, false),
		"offset_x": 0.0,
		"offset_y": 0.0
	})

	# ── Capa 3: Núcleo oscuro (sangre coagulada) ──────────────────
	var core_col  := base_color.darkened(0.4)
	var core_r    : int = maxi(1, int(r * 0.42 * bs))
	layers.append({
		"img":      _make_circle_image(core_r, core_col, 0.92, false),
		"offset_x": randf_range(-r * 0.18, r * 0.18),
		"offset_y": randf_range(-r * 0.18, r * 0.18)
	})

	# ── Capa 4-7: Gotas satélite (irregularidad orgánica) ─────────
	var num_satellites : int = randi_range(2, 4)
	for _i in range(num_satellites):
		var sat_r     : int   = maxi(1, int(r * randf_range(0.15, 0.32) * bs))
		var sat_dist  : float = r * randf_range(0.5, 1.1)
		var sat_angle : float = randf_range(0.0, TAU)
		layers.append({
			"img":      _make_circle_image(sat_r, base_color, randf_range(0.5, 0.82), false),
			"offset_x": cos(sat_angle) * sat_dist,
			"offset_y": sin(sat_angle) * sat_dist
		})

	return layers

## Genera una Image circular con suavizado en el borde.
## `soft_edge = true` → gradiente gaussiano (para el halo exterior).
## `soft_edge = false` → borde duro con ligero antialiasing.
func _make_circle_image(r: int, color: Color, alpha: float, soft_edge: bool) -> Image:
	var d   : int = r * 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var cr  := float(r)
	for y in range(d):
		for x in range(d):
			var dx   := float(x) - cr + 0.5
			var dy   := float(y) - cr + 0.5
			var dist := sqrt(dx * dx + dy * dy)
			if dist > cr:
				continue
			var t: float
			if soft_edge:
				# Gradiente cuadrático suave: más transparente en el borde
				t = 1.0 - (dist / cr)
				t = t * t
			else:
				# Borde con antialiasing de 1px
				t = clampf(cr - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha * t))
	return img

## Cuantiza el radio del mundo al sistema de bake para minimizar entradas de cache.
## Usa cuantización logarítmica para distribuir mejor el espacio.
func _quantize_radius(world_radius: float) -> int:
	var br : int = maxi(1, int(world_radius * BAKE_SCALE))
	# Redondear al múltiplo de 2 más cercano
	return maxi(1, int((br + 1) / 2.0) * 2)

## Mapea un color al color más cercano de la paleta de sangre.
func _quantize_color(color: Color) -> Color:
	var best       : Color = PALETTE[0]
	var best_dist  : float = INF
	for p in PALETTE:
		var d : float = absf(color.r - p.r) + absf(color.g - p.g) + absf(color.b - p.b)
		if d < best_dist:
			best_dist = d
			best      = p
	return best

# ════════════════════════════════════════════════════════════════════
#  API PÚBLICA — BAKE DE PARTÍCULAS
# ════════════════════════════════════════════════════════════════════

## Hornea un lote de partículas al suelo de forma eficiente.
## Agrupa por chunk antes de pintar → minimiza accesos a Image.
##
## `positions` — coordenadas mundo (Vector2Array)
## `colors`    — color de cada partícula (ColorArray)
## `sizes`     — diámetro aproximado en px del mundo (Float32Array)
func bake_particles_batch(
	positions : PackedVector2Array,
	colors    : PackedColorArray,
	sizes     : PackedFloat32Array
) -> void:
	if positions.size() == 0:
		return

	# Agrupar datos por chunk para hacer una sola llamada bake_batch por chunk
	var chunk_data : Dictionary = {}

	for i in range(positions.size()):
		var pos := positions[i]
		if not _is_valid_pos(pos):
			continue

		var cx  : int     = int(floor(pos.x / float(CHUNK_SIZE)))
		var cy  : int     = int(floor(pos.y / float(CHUNK_SIZE)))
		var key : Vector2i = Vector2i(cx, cy)

		if not chunk_data.has(key):
			chunk_data[key] = []

		chunk_data[key].append({
			"pos": pos,
			"col": colors[i],
			"size": sizes[i]
		})

	# Procesar cada chunk de una sola vez
	for key in chunk_data:
		var pos_key : Vector2i = key
		# Obtener o crear el chunk
		var cx_world : float = float(pos_key.x * CHUNK_SIZE)
		var cy_world : float = float(pos_key.y * CHUNK_SIZE)
		var chunk : BloodChunk = _get_or_create_chunk(cx_world + 1.0, cy_world + 1.0)
		if chunk:
			chunk.bake_batch(chunk_data[key])

## Bake de una sola mancha (wrapper conveniente)
func bake_single(world_pos: Vector2, color: Color, world_radius: float) -> void:
	var pa := PackedVector2Array([world_pos])
	var ca := PackedColorArray([color])
	var sa := PackedFloat32Array([world_radius])
	bake_particles_batch(pa, ca, sa)

# ════════════════════════════════════════════════════════════════════
#  UTILIDADES
# ════════════════════════════════════════════════════════════════════

func _is_valid_pos(pos: Vector2) -> bool:
	return is_finite(pos.x) and is_finite(pos.y) \
		and absf(pos.x) < 200000.0 and absf(pos.y) < 200000.0

func clear() -> void:
	for key in chunks:
		(chunks[key] as BloodChunk).detach()
	chunks.clear()
	brush_cache.clear()
	_evict_timer = 0.0

func get_debug_info() -> Dictionary:
	return {
		"chunks_alive":   chunks.size(),
		"brush_cache":    brush_cache.size(),
	}
