extends Control

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  hud.gd — ProyectSurvivor v3 (estilo Pygame reference)
##
##  Layout:
##    · Barra XP superior con marco NinePatch (hud_test assets)
##    · Timer centrado debajo de la XP bar
##    · Score arriba-izq con ícono dorado
##    · Kills arriba-der con ícono rojo
##    · Slots de arma a la izquierda
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const FS_HUGE  := 36
const FS_LARGE := 22
const FS_SMALL := 14
const FS_TINY  := 12

# ── Paleta ──────────────────────────────────────────────────────
const C_BG_PANEL   := Color(0.06, 0.06, 0.08, 0.92)
const C_BORDER     := Color(0.15, 0.15, 0.20, 1.0)
const C_BORDER_LIT := Color(0.28, 0.28, 0.38, 1.0)
const C_WHITE      := Color(0.92, 0.92, 0.96, 1.0)
const C_GRAY       := Color(0.40, 0.40, 0.48, 1.0)
const C_DIM        := Color(0.20, 0.20, 0.26, 1.0)
const C_SCORE      := Color(1.0, 0.82, 0.18, 1.0)
const C_KILLS      := Color(0.90, 0.30, 0.24, 1.0)
const C_TIME       := Color(0.82, 0.86, 0.92, 1.0)
const C_XP_FILL    := Color(0.31, 0.55, 1.0, 1.0)
const C_XP_BG      := Color(0.04, 0.05, 0.12, 1.0)

# ── Datos públicos (actualizados por gameplay.gd) ───────────────
var score          : int    = 0
var enemies_killed : int    = 0
var enemies_alive  : int    = 0
var wave_time_str  : String = "00:00"

# ── Estado interno ─────────────────────────────────────────────
var _player          : Node   = null
var _score_display   : float  = 0.0
var _xp_anim         : float  = 0.0
var _level_prev      : int    = 1
var _time_pulse      : float  = 0.0
var _font            : Font
var _font_dpcomic    : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = ThemeDB.fallback_font
	# Cargar dpcomic para el timer
	_font_dpcomic = load("res://assets/fonts/dpcomic.ttf") if ResourceLoader.exists("res://assets/fonts/dpcomic.ttf") else _font
	_try_find_player()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_try_find_player()
	if is_instance_valid(_player):
		_update_anims(delta)
	queue_redraw()

func _try_find_player() -> void:
	var arr := get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ANIMACIONES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _update_anims(dt: float) -> void:
	var p    := _player
	var dt60 := dt * 60.0

	var gap := float(score) - _score_display
	if absf(gap) > 0.5:
		_score_display += gap * 0.12 * dt60
	else:
		_score_display = float(score)

	if p.level != _level_prev:
		_xp_anim   = 1.0
		_level_prev = p.level
	if _xp_anim > 0.0:
		_xp_anim = maxf(0.0, _xp_anim - 0.02 * dt60)

	_time_pulse += 0.04 * dt60

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DIBUJO PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	if not is_instance_valid(_player):
		_draw_minimal()
		return
	_draw_xp_strip()
	_draw_timer()
	_draw_score_panel()
	_draw_kills_panel()
	_draw_weapon_indicator()

func _draw_minimal() -> void:
	_text_center(wave_time_str, Vector2(size.x * 0.5, 90.0), FS_HUGE, C_TIME)

# ── 1. BARRA DE XP (superior) ──────────────────────────────────

func _draw_xp_strip() -> void:
	var p   := _player
	var W   := size.x
	const H := 24.0

	var xp_next : float = maxf(p.experience_next, 1.0) if "experience_next" in p \
				  else maxf(p.experience_next_level, 1.0)
	var pct : float = clampf(float(p.experience) / xp_next, 0.0, 1.0)

	# Fondo de la barra
	draw_rect(Rect2(0, 0, W, H), C_XP_BG)
	# Relleno
	if pct > 0.0:
		draw_rect(Rect2(0, 0, W * pct, H), C_XP_FILL)
	# Flash de nivel
	if _xp_anim > 0.0:
		draw_rect(Rect2(0, 0, W, H),
				  Color(C_XP_FILL.r, C_XP_FILL.g, C_XP_FILL.b, _xp_anim * 0.78))
	# Borde inferior
	draw_line(Vector2(0, H - 1), Vector2(W, H - 1), C_BORDER_LIT, 1.0)

	# Label "XP" izquierda
	_text("XP", Vector2(10.0, 4.0), FS_SMALL, C_WHITE)

	# Label "LVL X" derecha
	var lv_str := "LVL %d" % p.level
	_text_right(lv_str, W - 10.0, 3.0, FS_SMALL, C_WHITE)

# ── 2. TEMPORIZADOR (centro, grande) ────────────────────────────

func _draw_timer() -> void:
	var cx    := size.x * 0.5
	var pulse := sin(_time_pulse) * 0.5 + 0.5
	var col   := C_TIME.lerp(Color.WHITE, pulse * 0.10)

	# Sombra
	_text_center_dp(wave_time_str, Vector2(cx + 2.0, 58.0), FS_HUGE,
					Color(0.0, 0.0, 0.0, 0.60))
	# Texto principal
	_text_center_dp(wave_time_str, Vector2(cx, 56.0), FS_HUGE, col)

# ── 3. PANEL DE PUNTUACIÓN (arriba-izq) ─────────────────────────

func _draw_score_panel() -> void:
	const PW := 200.0; const PH := 40.0; const PX := 8.0; const PY := 30.0

	# Fondo
	_panel(PX, PY, PW, PH, C_BG_PANEL, C_BORDER)

	# Ícono (corazón/diamante de Icons_RPG)
	_draw_score_icon(Vector2(PX + 10.0, PY + PH * 0.5))

	# Score
	var sc_str := _fmt_score(int(_score_display))
	_text(sc_str, Vector2(PX + 34.0, PY + 9.0), FS_LARGE, C_SCORE)

# ── 5. PANEL DE ELIMINADOS (arriba-der) ─────────────────────────

func _draw_kills_panel() -> void:
	const PW := 190.0; const PH := 40.0
	var px := size.x - PW - 8.0
	const PY := 30.0

	# Fondo
	_panel(px, PY, PW, PH, C_BG_PANEL, C_BORDER)

	# Ícono (espada de Icons_RPG)
	_draw_kills_icon(Vector2(px + PW - 28.0, PY + PH * 0.5))

	# Kills
	var en_str := "%d" % enemies_killed
	_text_right(en_str, px + PW - 40.0, PY + 9.0, FS_LARGE, C_KILLS)

# ── 6. INDICADOR DE ARMAS (izquierda) ───────────────────────────

func _draw_weapon_indicator() -> void:
	var p := _player
	if not ("weapons" in p) or p.weapons == null or p.weapons.size() == 0:
		return

	var n       : int   = p.weapons.size()
	var slot_w  : float = 68.0
	var slot_h  : float = 60.0
	var gap     : float = 6.0
	var total_h : float = n * slot_h + (n - 1) * gap
	var sx      : float = 8.0
	var sy      : float = size.y * 0.5 - total_h * 0.5
	var cur     : int   = int(p.current_weapon_index) if "current_weapon_index" in p else 0

	# Fondo del panel
	_panel(sx - 4, sy - 4, slot_w + 8, total_h + 8, C_BG_PANEL, C_BORDER)

	for i in range(n):
		var sy_i  : float = sy + i * (slot_h + gap)
		var weapon         = p.weapons[i]
		var active : bool  = (i == cur)

		if active:
			draw_rect(Rect2(sx, sy_i, slot_w, slot_h), Color(0.06, 0.14, 0.28, 0.90))
			draw_rect(Rect2(sx, sy_i, slot_w, slot_h), Color(0.0, 0.82, 1.0), false, 2.0)

		# Número de tecla
		_text(str(i + 1), Vector2(sx + 4.0, sy_i + 4.0), FS_TINY, C_WHITE if active else C_DIM)

		# Nombre del arma (truncado)
		var wn : String = (weapon.weapon_name as String) if "weapon_name" in weapon else "?"
		if wn.length() > 7:
			wn = wn.substr(0, 6) + "."
		_text_center(wn, Vector2(sx + slot_w * 0.5, sy_i + slot_h * 0.5 + 4.0),
					 FS_TINY, C_WHITE if active else C_DIM)

# ── Íconos de score y kills (dibujados proceduralmente) ──────────

func _draw_score_icon(center: Vector2) -> void:
	# Diamante simple
	var sz := 7.0
	var pts := PackedVector2Array([
		Vector2(center.x, center.y - sz),
		Vector2(center.x + sz, center.y),
		Vector2(center.x, center.y + sz),
		Vector2(center.x - sz, center.y),
	])
	draw_colored_polygon(pts, C_SCORE)
	draw_polyline(pts, Color.WHITE, 1.0)

func _draw_kills_icon(center: Vector2) -> void:
	# X simple (cruz de eliminados)
	var sz := 6.0
	draw_line(Vector2(center.x - sz, center.y - sz),
			  Vector2(center.x + sz, center.y + sz), C_KILLS, 2.0)
	draw_line(Vector2(center.x + sz, center.y - sz),
			  Vector2(center.x - sz, center.y + sz), C_KILLS, 2.0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE DIBUJO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _panel(x: float, y: float, w: float, h: float,
			bg: Color, border: Color, bw: float = 1.0) -> void:
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), border, false, bw)

func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	draw_string(_font, Vector2(pos.x, pos.y + _font.get_ascent(fs)),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_right(t: String, right_x: float, top_y: float, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw := _str_w(t, fs)
	draw_string(_font, Vector2(right_x - tw, top_y + _font.get_ascent(fs)),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center_dp(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty(): return
	var f := _font_dpcomic if is_instance_valid(_font_dpcomic) else _font
	if not is_instance_valid(f): return
	var tw       := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline := center.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	draw_string(f, Vector2(center.x - tw * 0.5, baseline),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font): return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _fmt_score(s: int) -> String:
	if s <= 0: return "0"
	var result := ""; var n := s; var count := 0
	while n > 0:
		if count > 0 and count % 3 == 0: result = "." + result
		result = str(n % 10) + result; n /= 10; count += 1
	return result

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(_player) or not ("weapons" in _player):
		return

	if GameManager.is_mobile():
		if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.is_pressed():
			var n : int = _player.weapons.size()
			if n == 0: return

			var slot_w  : float = 68.0
			var slot_h  : float = 60.0
			var gap     : float = 6.0
			var total_h : float = n * slot_h + (n - 1) * gap
			var sx      : float = 8.0
			var sy      : float = size.y * 0.5 - total_h * 0.5

			var ev_pos : Vector2 = event.position

			for i in range(n):
				var sy_i : float = sy + i * (slot_h + gap)
				var rect := Rect2(sx, sy_i, slot_w, slot_h)

				if rect.has_point(ev_pos):
					var key_ev := InputEventKey.new()
					key_ev.keycode = (KEY_1 + i) as Key
					key_ev.pressed = true
					Input.parse_input_event(key_ev)

					await get_tree().process_frame

					var key_release = key_ev.duplicate()
					key_release.pressed = false
					Input.parse_input_event(key_release)

					get_viewport().set_input_as_handled()
					return
