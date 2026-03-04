extends Node2D

# Cuadrícula del mundo dibujada proceduralmente
# Equivale exactamente a tu pygame.draw.rect del suelo en chunks

const TILE_SIZE: int = 64
const COLOR_FLOOR_A := Color(0.08, 0.08, 0.08)   # cuadros oscuros
const COLOR_FLOOR_B := Color(0.11, 0.11, 0.11)   # cuadros claros
const COLOR_GRID    := Color(0.18, 0.18, 0.18, 0.6)  # línea de grid
const COLOR_BORDER  := Color(0.8, 0.2, 0.2)      # borde del mundo

func _draw() -> void:
	_draw_floor()
	_draw_world_border()

# Reemplaza _draw_floor() por esta versión — solo dibuja tiles visibles
func _draw_floor() -> void:
	# Calcular el rectángulo visible en coordenadas de mundo
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	
	var view_size := get_viewport_rect().size
	var cam_pos   := cam.global_position
	var zoom      := cam.zoom
	
	# Área visible en el mundo
	var half_view := view_size / (2.0 * zoom)
	var world_rect := Rect2(cam_pos - half_view, view_size / zoom)
	
	# Clamp al mundo
	world_rect = world_rect.intersection(
		Rect2(Vector2.ZERO, Vector2(GameManager.WORLD_WIDTH, GameManager.WORLD_HEIGHT))
	)
	
	# Rango de tiles a dibujar
	var col_start := int(world_rect.position.x / TILE_SIZE)
	var row_start := int(world_rect.position.y / TILE_SIZE)
	var col_end   := int(world_rect.end.x / TILE_SIZE) + 1
	var row_end   := int(world_rect.end.y / TILE_SIZE) + 1
	
	col_start = max(0, col_start)
	row_start = max(0, row_start)
	col_end   = min(GameManager.WORLD_WIDTH  / TILE_SIZE, col_end)
	row_end   = min(GameManager.WORLD_HEIGHT / TILE_SIZE, row_end)
	
	for row in range(row_start, row_end):
		for col in range(col_start, col_end):
			var pos  := Vector2(col * TILE_SIZE, row * TILE_SIZE)
			var rect := Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE))
			var color := COLOR_FLOOR_A if (row + col) % 2 == 0 else COLOR_FLOOR_B
			draw_rect(rect, color)
	
	# Grid solo en área visible
	var g := TILE_SIZE * 4
	var x_start := (col_start * TILE_SIZE / g) * g
	var y_start := (row_start * TILE_SIZE / g) * g
	for x in range(x_start, int(world_rect.end.x) + g, g):
		draw_line(Vector2(x, world_rect.position.y), Vector2(x, world_rect.end.y), COLOR_GRID, 1.0)
	for y in range(y_start, int(world_rect.end.y) + g, g):
		draw_line(Vector2(world_rect.position.x, y), Vector2(world_rect.end.x, y), COLOR_GRID, 1.0)

func _draw_world_border() -> void:
	# Borde rojo del límite del mundo
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(GameManager.WORLD_WIDTH, GameManager.WORLD_HEIGHT)),
		COLOR_BORDER,
		false,
		4.0
	)

func _process(_delta: float) -> void:
	queue_redraw()  # redibuja cada frame (la cámara puede haberse movido)