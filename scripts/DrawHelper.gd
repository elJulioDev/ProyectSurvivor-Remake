class_name DrawHelper

# Equivalente a pygame.draw.rect con borde
static func rect_with_border(
	canvas: CanvasItem,
	pos: Vector2,
	size: Vector2,
	fill_color: Color,
	border_color: Color,
	border_width: int = 2
) -> void:
	var r = Rect2(pos - size / 2.0, size)
	canvas.draw_rect(r, fill_color)
	canvas.draw_rect(r, border_color, false, border_width)

# Cuadrado centrado (tu sprite de enemigo/jugador)
static func square_entity(
	canvas: CanvasItem,
	size: int,
	color: Color,
	border_color: Color
) -> void:
	var half = size / 2.0
	var r = Rect2(Vector2(-half, -half), Vector2(size, size))
	canvas.draw_rect(r, color)
	canvas.draw_rect(r, border_color, false, 2)
	# Centro oscuro (igual que tu sprite cacheado)
	var center_size = max(2, size / 3)
	var ch = center_size / 2.0
	canvas.draw_rect(
		Rect2(Vector2(-ch, -ch), Vector2(center_size, center_size)),
		border_color
	)
