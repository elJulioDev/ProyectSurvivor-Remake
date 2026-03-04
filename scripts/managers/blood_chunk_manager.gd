extends Node2D
class_name BloodChunkManager

# ════════════════════════════════════════════════════════════════════════════
#  BloodChunkManager — ProyectSurvivor (Godot 4)
#
#  Almacén de decales de sangre estáticos dividido en chunks del mundo.
#  Equivale a utils/chunk_manager.py del original Python.
#
#  Flujo:
#    1. BloodParticleSystem llama bake_particles_batch() con posiciones mundo.
#    2. Cada posición se asigna al chunk correcto.
#    3. Se pinta el brush en la Image interna del chunk (a BAKE_SCALE).
#    4. En _process(), apply_updates() sube la textura a GPU UNA SOLA VEZ.
#    5. Cada BloodChunk es un Sprite2D hijo escalado al tamaño de mundo.
# ════════════════════════════════════════════════════════════════════════════

const CHUNK_SIZE      := 1000    # píxeles de mundo por lado
const BAKE_SCALE      := 0.5     # resolución interna (ahorra RAM y CPU)
const MAX_BRUSH_CACHE := 128     # límite de brushes en caché

# Paleta de sangre (quantización de color para maximizar cache hits)
const PALETTE := [
	Color8(160,  0,  0),   # BLOOD_RED
	Color8( 80,  0,  0),   # DARK_BLOOD
	Color8(200, 20, 20),   # BRIGHT_RED
	Color8(180, 90,100),   # GUTS_PINK
]

var chunks      : Dictionary = {}   # Vector2i(cx,cy) → BloodChunk
var brush_cache : Dictionary = {}   # String key     → Image

# ════════════════════════════════════════════════════════════════════════════
#  CLASE INTERNA: BloodChunk
# ════════════════════════════════════════════════════════════════════════════
class BloodChunk extends Node2D:
	var cx:        int
	var cy:        int
	var image:     Image
	var texture:   ImageTexture
	var dirty:     bool = false
	var sprite:    Sprite2D
	var _manager:  Node2D

	func _init(_cx: int, _cy: int, mgr: Node2D) -> void:
		cx       = _cx
		cy       = _cy
		_manager = mgr

		var ws     := BloodChunkManager.CHUNK_SIZE
		var bs_int := int(ws * BloodChunkManager.BAKE_SCALE)

		# Posición en el mundo
		position = Vector2(_cx * ws, _cy * ws)

		# Imagen interna a resolución reducida
		image   = Image.create(bs_int, bs_int, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)

		# Sprite escalado al tamaño real de mundo
		sprite          = Sprite2D.new()
		sprite.texture  = texture
		sprite.centered = false
		sprite.scale    = Vector2(float(ws) / float(bs_int),
		                          float(ws) / float(bs_int))
		add_child(sprite)

	## Pinta un lote de manchas en la imagen del chunk.
	func bake_batch(datos: Array) -> void:
		var bs := int(BloodChunkManager.CHUNK_SIZE * BloodChunkManager.BAKE_SCALE)
		var scale := BloodChunkManager.BAKE_SCALE

		for d in datos:
			var brush: Image = _manager.get_brush(d.size / 2.0, d.col)
			if brush == null:
				continue

			var bw := brush.get_width()
			var bh := brush.get_height()

			# Coordenadas locales al chunk → espacio de bake
			var local_x := float (d.pos.x - position.x)
			var local_y := float (d.pos.y - position.y)
			var bx      := int(local_x * scale) - bw / 2.0
			var by_     := int(local_y * scale) - bh / 2.0

			# Recortar src_rect si el brush cae parcialmente fuera del chunk
			var src_x := 0
			var src_y := 0
			var src_w := bw
			var src_h := bh

			if bx < 0:
				src_x -= bx
				src_w += bx
				bx     = 0
			if by_ < 0:
				src_y -= by_
				src_h += by_
				by_    = 0

			src_w = mini(src_w, bs - bx)
			src_h = mini(src_h, bs - by_)

			if src_w <= 0 or src_h <= 0:
				continue

			var src_rect := Rect2i(src_x, src_y, src_w, src_h)
			image.blend_rect(brush, src_rect, Vector2i(bx, by_))

		dirty = true

	## Sube cambios a GPU una sola vez por frame.
	func apply_updates() -> void:
		if dirty:
			texture.update(image)
			dirty = false

# ════════════════════════════════════════════════════════════════════════════
#  BRUSH CACHE
# ════════════════════════════════════════════════════════════════════════════

## Devuelve (o genera) un brush circular anti-aliaseado.
## Radio y color se quantizan para minimizar la cantidad de brushes únicos.
func get_brush(world_radius: float, color: Color) -> Image:
	var r_baked := _quantize_radius(world_radius)
	var q_color := _quantize_color(color)
	var key     := str(r_baked) + "_" + q_color.to_html(false)

	if brush_cache.has(key):
		return brush_cache[key]

	# Limpiar caché si se llenó
	if brush_cache.size() >= MAX_BRUSH_CACHE:
		var old_keys := brush_cache.keys().slice(0, MAX_BRUSH_CACHE / 2)
		for k in old_keys:
			brush_cache.erase(k)

	# Crear brush
	var diam := maxi(2, r_baked * 2)
	var img  := Image.create(diam, diam, false, Image.FORMAT_RGBA8)
	var r_sq := float(r_baked * r_baked)

	for y in range(diam):
		for x in range(diam):
			var dx  := float(x) - r_baked + 0.5
			var dy  := float(y) - r_baked + 0.5
			var d2  := dx * dx + dy * dy
			if d2 <= r_sq:
				# MODIFICACIÓN: Subimos la opacidad mínima de 0.6 a 0.9.
				# Esto hace que la sangre se vea densa, oscura y resalte fuertemente en el piso.
				var t := clampf(1.0 - d2 / r_sq * 0.15, 0.9, 1.0)
				var c := Color(q_color.r, q_color.g, q_color.b, t)
				img.set_pixel(x, y, c)

	brush_cache[key] = img
	return img

func _quantize_radius(world_radius: float) -> int:
	# Convertir a espacio bake y redondear al múltiplo de 2 más cercano
	var br := maxi(1, int(world_radius * BAKE_SCALE))
	return maxi(1, (br + 1) / 2 * 2)

func _quantize_color(color: Color) -> Color:
	var best := PALETTE[0]
	var best_dist := INF
	for p in PALETTE:
		var d := absf(color.r - p.r) + absf(color.g - p.g) + absf(color.b - p.b)
		if d < best_dist:
			best_dist = d
			best      = p
	return best

# ════════════════════════════════════════════════════════════════════════════
#  GESTIÓN DE CHUNKS
# ════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	for chunk in chunks.values():
		chunk.apply_updates()

## Devuelve el chunk para (world_x, world_y), creándolo si no existe.
func get_chunk(world_x: float, world_y: float) -> BloodChunk:
	var cx  := int(floor(world_x / CHUNK_SIZE))
	var cy  := int(floor(world_y / CHUNK_SIZE))
	var key := Vector2i(cx, cy)

	if not chunks.has(key):
		var c := BloodChunk.new(cx, cy, self)
		chunks[key] = c
		add_child(c)

	return chunks[key]

## Elimina chunks lejanos de la cámara para liberar RAM.
## Llamar ocasionalmente (p.ej. cada 300 frames o 5 segundos).
func evict_distant_chunks(camera_world_pos: Vector2, evict_radius_chunks: int = 4) -> void:
	var r_sq := float(evict_radius_chunks * evict_radius_chunks)
	var to_remove := []

	for key in chunks.keys():
		var cx_world := (float(key.x) + 0.5) * CHUNK_SIZE
		var cy_world := (float(key.y) + 0.5) * CHUNK_SIZE
		var dx := (cx_world - camera_world_pos.x) / CHUNK_SIZE
		var dy := (cy_world - camera_world_pos.y) / CHUNK_SIZE
		if dx * dx + dy * dy > r_sq:
			to_remove.append(key)

	for key in to_remove:
		chunks[key].queue_free()
		chunks.erase(key)

# ════════════════════════════════════════════════════════════════════════════
#  BAKE PÚBLICO — Llamado por BloodParticleSystem
# ════════════════════════════════════════════════════════════════════════════

## Distribuye un lote de manchas de sangre a sus chunks correspondientes.
## Este es el único punto de entrada desde BloodParticleSystem.
func bake_particles_batch(
	positions: PackedVector2Array,
	colors:    PackedColorArray,
	sizes:     PackedFloat32Array
) -> void:
	if positions.size() == 0:
		return

	# Agrupar por chunk
	var chunk_updates: Dictionary = {}

	for i in range(positions.size()):
		var pos := positions[i]
		if not _is_valid_pos(pos):
			continue

		var chunk := get_chunk(pos.x, pos.y)
		if chunk == null:
			continue

		if not chunk_updates.has(chunk):
			chunk_updates[chunk] = []

		chunk_updates[chunk].append({
			"pos":  pos,
			"col":  colors[i],
			"size": sizes[i]
		})

	# Pintar cada chunk (un blend_rect por mancha)
	for chunk in chunk_updates.keys():
		chunk.bake_batch(chunk_updates[chunk])

func _is_valid_pos(pos: Vector2) -> bool:
	return is_finite(pos.x) and is_finite(pos.y) \
		and absf(pos.x) < 200000.0 and absf(pos.y) < 200000.0

# ════════════════════════════════════════════════════════════════════════════
#  DEBUG
# ════════════════════════════════════════════════════════════════════════════
func get_debug_info() -> Dictionary:
	return {
		"chunks_active":  chunks.size(),
		"brush_cache":    brush_cache.size(),
	}