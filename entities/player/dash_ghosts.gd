extends Node2D
# dash_ghosts.gd
# Dibuja las estelas fantasma durante el dash.
# Recibe datos del player, no tiene lógica propia.

const PLAYER_SIZE := 20

var _ghosts    : Array = []
var _ninja_mode: bool  = false

func set_ghosts(ghosts: Array, ninja: bool) -> void:
	_ghosts     = ghosts
	_ninja_mode = ninja
	visible     = ghosts.size() > 0
	queue_redraw()

func _draw() -> void:
	if _ghosts.is_empty():
		return

	var half := float(PLAYER_SIZE) * 0.5
	var n    := _ghosts.size()

	for i in range(n):
		var g     : Dictionary = _ghosts[i]
		var alpha : float      = float(i) / float(max(1, n)) * (180.0 / 255.0)
		var lpos  : Vector2    = to_local(g["pos"])
		var gc    : Color      = Color(0.63, 0.0, 1.0, alpha) if _ninja_mode \
							   else Color(1.0, 1.0, 1.0, alpha)

		draw_rect(Rect2(lpos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), gc)

		if alpha > 0.196:
			var ghost_tip := lpos + Vector2(cos(g["angle"]), sin(g["angle"])) * half * 2.5
			draw_line(lpos, ghost_tip, gc, 2.0)