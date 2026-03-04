extends Node2D
class_name BloodChunkManager

const CHUNK_SIZE      := 1000
const BAKE_SCALE      := 0.5
const MAX_BRUSH_CACHE := 128
const EVICT_INTERVAL  := 15.0   # segundos entre limpiezas de chunks lejanos
const EVICT_RADIUS    := 5       # chunks de radio para conservar

const PALETTE := [
	Color8(160,  0,  0),
	Color8( 80,  0,  0),
	Color8(200, 20, 20),
	Color8(180, 90,100),
]

var chunks      : Dictionary = {}
var brush_cache : Dictionary = {}
var _evict_timer: float = 0.0
var _camera_ref : Camera2D = null

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

		position = Vector2(_cx * ws, _cy * ws)
		image    = Image.create(bs_int, bs_int, false, Image.FORMAT_RGBA8)
		texture  = ImageTexture.create_from_image(image)

		sprite          = Sprite2D.new()
		sprite.texture  = texture
		sprite.centered = false
		sprite.scale    = Vector2(float(ws) / float(bs_int),
		                          float(ws) / float(bs_int))
		add_child(sprite)

	func bake_batch(datos: Array) -> void:
		var bs    := int(BloodChunkManager.CHUNK_SIZE * BloodChunkManager.BAKE_SCALE)
		var scale := BloodChunkManager.BAKE_SCALE

		for d in datos:
			var brush: Image = _manager.get_brush(d.size / 2.0, d.col)
			if brush == null:
				continue
			var bw := brush.get_width()
			var bh := brush.get_height()
			var local_x := float(d.pos.x - position.x)
			var local_y := float(d.pos.y - position.y)
			var bx  := int(local_x * scale) - bw / 2.0
			var by_ := int(local_y * scale) - bh / 2.0
			var src_x := 0; var src_y := 0
			var src_w := bw; var src_h := bh
			if bx < 0:
				src_x -= bx; src_w += bx; bx = 0
			if by_ < 0:
				src_y -= by_; src_h += by_; by_ = 0
			src_w = mini(src_w, bs - bx)
			src_h = mini(src_h, bs - by_)
			if src_w <= 0 or src_h <= 0:
				continue
			image.blend_rect(brush, Rect2i(src_x, src_y, src_w, src_h), Vector2i(bx, by_))
		dirty = true

	func apply_updates() -> void:
		if dirty:
			texture.update(image)
			dirty = false

# ════════════════════════════════════════════════════════════════════════════
#  PROCESO — Culling de cámara para no subir texturas off-screen
# ════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	# Obtener cámara una vez por frame
	if not is_instance_valid(_camera_ref):
		_camera_ref = get_viewport().get_camera_2d()

	var cam_rect := _get_camera_world_rect()

	for key in chunks:
		var chunk: BloodChunk = chunks[key]
		if not chunk.dirty:
			continue
		# Solo subir la textura si el chunk es visible por la cámara
		var chunk_world_rect := Rect2(
			Vector2(key.x * CHUNK_SIZE, key.y * CHUNK_SIZE),
			Vector2(CHUNK_SIZE, CHUNK_SIZE)
		)
		if cam_rect.intersects(chunk_world_rect):
			chunk.apply_updates()
		# Si no es visible, queda dirty y se sube cuando la cámara llegue

	# Eviction periódico de chunks lejanos (libera RAM/VRAM)
	_evict_timer += delta
	if _evict_timer >= EVICT_INTERVAL:
		_evict_timer = 0.0
		if is_instance_valid(_camera_ref):
			evict_distant_chunks(_camera_ref.global_position, EVICT_RADIUS)

## Devuelve el rectángulo del mundo visible por la cámara actual.
func _get_camera_world_rect() -> Rect2:
	if not is_instance_valid(_camera_ref):
		return Rect2(-99999, -99999, 199998, 199998)  # todo visible si no hay cámara
	var vp_size := get_viewport_rect().size
	var zoom    := _camera_ref.zoom
	var half    := vp_size / (2.0 * zoom)
	var center  := _camera_ref.get_screen_center_position()
	# Margen extra de 1 chunk para evitar pop-in
	return Rect2(center - half - Vector2.ONE * CHUNK_SIZE,
	             vp_size / zoom + Vector2.ONE * CHUNK_SIZE * 2.0)

# ════════════════════════════════════════════════════════════════════════════
#  BRUSH CACHE
# ════════════════════════════════════════════════════════════════════════════
func get_brush(world_radius: float, color: Color) -> Image:
	var r_baked := _quantize_radius(world_radius)
	var q_color := _quantize_color(color)
	var key     := str(r_baked) + "_" + q_color.to_html(false)
	if brush_cache.has(key):
		return brush_cache[key]
	if brush_cache.size() >= MAX_BRUSH_CACHE:
		var old_keys := brush_cache.keys().slice(0, MAX_BRUSH_CACHE / 2)
		for k in old_keys:
			brush_cache.erase(k)
	var diam := maxi(2, r_baked * 2)
	var img  := Image.create(diam, diam, false, Image.FORMAT_RGBA8)
	var r_sq := float(r_baked * r_baked)
	for y in range(diam):
		for x in range(diam):
			var dx := float(x) - r_baked + 0.5
			var dy := float(y) - r_baked + 0.5
			var d2 := dx * dx + dy * dy
			if d2 <= r_sq:
				var t := clampf(1.0 - d2 / r_sq * 0.15, 0.9, 1.0)
				img.set_pixel(x, y, Color(q_color.r, q_color.g, q_color.b, t))
	brush_cache[key] = img
	return img

func _quantize_radius(world_radius: float) -> int:
	var br := maxi(1, int(world_radius * BAKE_SCALE))
	return maxi(1, (br + 1) / 2 * 2)

func _quantize_color(color: Color) -> Color:
	var best := PALETTE[0]
	var best_dist := INF
	for p in PALETTE:
		var d := absf(color.r - p.r) + absf(color.g - p.g) + absf(color.b - p.b)
		if d < best_dist:
			best_dist = d
			best = p
	return best

# ════════════════════════════════════════════════════════════════════════════
#  GESTIÓN DE CHUNKS
# ════════════════════════════════════════════════════════════════════════════
func get_chunk(world_x: float, world_y: float) -> BloodChunk:
	var cx  := int(floor(world_x / CHUNK_SIZE))
	var cy  := int(floor(world_y / CHUNK_SIZE))
	var key := Vector2i(cx, cy)
	if not chunks.has(key):
		var c := BloodChunk.new(cx, cy, self)
		chunks[key] = c
		add_child(c)
	return chunks[key]

func evict_distant_chunks(camera_world_pos: Vector2, evict_radius_chunks: int = 5) -> void:
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
#  BAKE PÚBLICO
# ════════════════════════════════════════════════════════════════════════════
func bake_particles_batch(
	positions: PackedVector2Array,
	colors:    PackedColorArray,
	sizes:     PackedFloat32Array
) -> void:
	if positions.size() == 0:
		return
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
		chunk_updates[chunk].append({"pos": pos, "col": colors[i], "size": sizes[i]})
	for chunk in chunk_updates.keys():
		chunk.bake_batch(chunk_updates[chunk])

func _is_valid_pos(pos: Vector2) -> bool:
	return is_finite(pos.x) and is_finite(pos.y) \
		and absf(pos.x) < 200000.0 and absf(pos.y) < 200000.0

func get_debug_info() -> Dictionary:
	return {"chunks_active": chunks.size(), "brush_cache": brush_cache.size()}