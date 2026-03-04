extends Node2D

const TILE_SIZE: int = 64
const COLOR_FLOOR_A := Color(0.08, 0.08, 0.08)
const COLOR_FLOOR_B := Color(0.11, 0.11, 0.11)
const COLOR_GRID    := Color(0.18, 0.18, 0.18, 0.6)

func _draw() -> void:
	_draw_floor()
	# Eliminamos _draw_world_border() para quitar el límite rojo visible

func _draw_floor() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var view_size := get_viewport_rect().size
	var cam_pos   := cam.get_screen_center_position()
	var zoom      := cam.zoom

	# Área visible en la cámara. Le agregamos un margen (grow) para que 
	# el fondo cubra bien la pantalla incluso si la cámara tiembla por daño.
	var half_view := view_size / (2.0 * zoom)
	var world_rect := Rect2(cam_pos - half_view, view_size / zoom).grow(TILE_SIZE * 2)

	# Eliminamos el clamp al tamaño del mundo
	
	# Calculamos filas y columnas usando floor y ceil para soportar 
	# correctamente coordenadas negativas si la cámara se asoma.
	var col_start: int = int(floor(world_rect.position.x / TILE_SIZE))
	var row_start: int = int(floor(world_rect.position.y / TILE_SIZE))
	var col_end:   int = int(ceil(world_rect.end.x / TILE_SIZE))
	var row_end:   int = int(ceil(world_rect.end.y / TILE_SIZE))

	for row in range(row_start, row_end):
		for col in range(col_start, col_end):
			var pos  := Vector2(col * TILE_SIZE, row * TILE_SIZE)
			var rect := Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE))
			# posmod garantiza que el patrón de damero funcione bien 
			# incluso en los cuadrantes de coordenadas negativas
			var color := COLOR_FLOOR_A if posmod(row + col, 2) == 0 else COLOR_FLOOR_B
			draw_rect(rect, color)

	# Líneas del grid cada 4 tiles
	var g: int       = TILE_SIZE * 4
	var x_start: int = int(floor(world_rect.position.x / g)) * g
	var y_start: int = int(floor(world_rect.position.y / g)) * g

	var world_end_x: float = world_rect.end.x
	var world_end_y: float = world_rect.end.y

	var x: float = x_start
	while x <= world_end_x:
		draw_line(
			Vector2(x, world_rect.position.y),
			Vector2(x, world_rect.end.y),
			COLOR_GRID, 1.0
		)
		x += g

	var y: float = y_start
	while y <= world_end_y:
		draw_line(
			Vector2(world_rect.position.x, y),
			Vector2(world_rect.end.x,      y),
			COLOR_GRID, 1.0
		)
		y += g

func _process(_delta: float) -> void:
	queue_redraw()