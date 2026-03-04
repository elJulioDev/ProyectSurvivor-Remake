extends Node2D
class_name BloodChunkManager

const CHUNK_SIZE: int = 1000

var chunks: Dictionary = {}
var brush_cache: Dictionary = {}

func get_brush(radius: int, color: Color) -> Image:
	var key = str(radius) + "_" + color.to_html()
	if brush_cache.has(key): return brush_cache[key]
		
	var size = maxi(radius * 2, 2)
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(radius, radius)
	for y in range(size):
		for x in range(size):
			if Vector2(x, y).distance_to(center) <= radius:
				img.set_pixel(x, y, color)
				
	brush_cache[key] = img
	return img

class BloodChunk extends Node2D:
	var cx: int
	var cy: int
	var image: Image
	var texture: ImageTexture
	var dirty: bool = false
	var sprite: Sprite2D
	var manager: Node2D
	
	func _init(_cx: int, _cy: int, size: int, _manager: Node2D) -> void:
		cx = _cx
		cy = _cy
		manager = _manager
		position = Vector2(cx * size, cy * size)
		
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)
		
		sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		add_child(sprite)

	# BATCH BAKE: ¡La magia del rendimiento aquí!
	func bake_batch(datos: Array) -> void:
		for d in datos:
			var radius = maxi(1, int(d.size / 2.0))
			var brush = manager.get_brush(radius, d.col)
			var brush_rect = Rect2i(0, 0, brush.get_width(), brush.get_height())
			var dst_pos = Vector2i(int(d.pos.x) - radius, int(d.pos.y) - radius)
			image.blend_rect(brush, brush_rect, dst_pos)
		dirty = true

	func apply_updates() -> void:
		if dirty:
			texture.update(image) # ¡Se llama SOLO 1 VEZ por frame por chunk!
			dirty = false

func _process(_delta: float) -> void:
	for chunk_key in chunks:
		chunks[chunk_key].apply_updates()

func get_chunk(world_x: float, world_y: float) -> BloodChunk:
	var cx = int(floor(world_x / CHUNK_SIZE))
	var cy = int(floor(world_y / CHUNK_SIZE))
	var key = Vector2(cx, cy)
	
	if not chunks.has(key):
		var new_chunk = BloodChunk.new(cx, cy, CHUNK_SIZE, self)
		chunks[key] = new_chunk
		add_child(new_chunk)
	return chunks[key]

func bake_particles_batch(positions: PackedVector2Array, colors: PackedColorArray, sizes: PackedFloat32Array) -> void:
	var chunk_updates = {}
	
	# 1. Agrupar por Chunk
	for i in range(positions.size()):
		var chunk = get_chunk(positions[i].x, positions[i].y)
		if not chunk_updates.has(chunk):
			chunk_updates[chunk] = []
		chunk_updates[chunk].append({
			"pos": positions[i] - chunk.position,
			"col": colors[i],
			"size": sizes[i]
		})

	# 2. Imprimir en lote (Batch bake)
	for chunk in chunk_updates:
		chunk.bake_batch(chunk_updates[chunk])