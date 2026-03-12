extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/game_over.gd — ProyectSurvivor
##  v2: layout corregido + sistema de sangre persistente en suelo
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Paleta ────────────────────────────────────────────────────────
const C_BG     := Color(0.024, 0.027, 0.039)
const C_RED    := Color(0.824, 0.118, 0.118)
const C_CYAN   := Color(0.000, 0.824, 0.863)
const C_WHITE  := Color(0.902, 0.910, 0.933)
const C_GRAY   := Color(0.353, 0.361, 0.412)
const C_PANEL  := Color(0.055, 0.063, 0.094)
const C_BORDER := Color(0.157, 0.173, 0.243)
const C_GOLD   := Color(1.000, 0.784, 0.157)

# Paleta de sangre (rojo muy oscuro y saturado)
const BLOOD_A  := Color(0.28, 0.000, 0.002)
const BLOOD_B  := Color(0.42, 0.012, 0.010)
const BLOOD_C  := Color(0.55, 0.028, 0.020)

# ── Viewport ──────────────────────────────────────────────────────
var VW := 1280.0
var VH :=  720.0

# ── Datos de partida ──────────────────────────────────────────────
var _final_score    : int    = 0
var _final_time_str : String = "00:00"
var _blood_factor   : float  = 0.0   # 0–1 según puntuación

# ── Fases de animación ────────────────────────────────────────────
var _phase        : String = "enter"
var _phase_timer  : float  = 0.0
var _fade_in      : float  = 0.0
var _title_shown  : float  = 0.0
var _content_prog : float  = 0.0
var _buttons_prog : float  = 0.0

# ── Badges ────────────────────────────────────────────────────────
var _badge_score_shown : float = 0.0
var _badge_time_shown  : float = 0.0
var _badge_score_delay : float = 55.0
var _badge_time_delay  : float = 90.0

# ── Botones ───────────────────────────────────────────────────────
const BTN_W   := 280.0
const BTN_H   :=  62.0
const BTN_GAP :=  24.0
const BTN_Y   := 480.0

var _btn_retry_cx : float = 488.0
var _btn_menu_cx  : float = 792.0
var _btn_retry_scale : float = 1.0
var _btn_retry_glow  : float = 0.0
var _btn_menu_scale  : float = 1.0
var _btn_menu_glow   : float = 0.0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CLASES INTERNAS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _Shard:
	var x        : float
	var y        : float
	var vx       : float
	var vy       : float
	var size     : float
	var color    : Color
	var alpha    : float = 1.0
	var landed   : bool  = false
	var spawned  : bool  = false   # ya generó su charco
	var life     : float = 0.0
	var max_life : float = 360.0
	var is_blood : bool  = false   # ¿es una gota de sangre?

## Charco de sangre persistente en el suelo
class _BloodPool:
	var x          : float
	var y          : float
	var target_r   : float   # radio final
	var current_r  : float = 0.0
	var grow_speed : float   # px por tick
	var alpha      : float = 0.0
	var target_a   : float
	var color      : Color
	var settled    : bool  = false   # terminó de crecer

var _shards      : Array = []
var _blood_pools : Array = []
var _font        : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INICIALIZACIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	_font = ThemeDB.fallback_font
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var vp := get_viewport_rect().size
	VW = vp.x;  VH = vp.y
	_recalc_btn_positions()
	_init_shards()

func setup(data: Dictionary) -> void:
	_final_score    = data.get("score", 0)
	_final_time_str = data.get("time",  "00:00")
	# Factor de sangre: 0 con 0 pts → 1.0 con ≥5000 pts
	_blood_factor   = clampf(float(_final_score) / 5000.0, 0.0, 1.0)

func _recalc_btn_positions() -> void:
	_btn_retry_cx = VW * 0.5 - BTN_W * 0.5 - BTN_GAP * 0.5
	_btn_menu_cx  = VW * 0.5 + BTN_W * 0.5 + BTN_GAP * 0.5

func _init_shards() -> void:
	# Siempre al menos 14 shards; más si hay sangre
	var total := 14 + int(_blood_factor * 28.0)
	for _i in range(total):
		_shards.append(_make_shard())

func _make_shard() -> _Shard:
	var s       := _Shard.new()
	s.x         = randf_range(0.0, VW)
	s.y         = randf_range(-80.0, -5.0)
	s.vx        = randf_range(-1.4, 1.4)
	s.vy        = randf_range(1.2, 4.2)
	s.size      = randf_range(2.0, 8.0)
	s.alpha     = 0.96
	s.landed    = false
	s.spawned   = false
	s.life      = 0.0
	s.max_life  = randf_range(220.0, 500.0)
	var r := randf()
	if r < 0.55 and _blood_factor > 0.0:
		# gota de sangre roja
		s.is_blood = true
		var t := randf()
		if t < 0.5:
			s.color = BLOOD_C
		else:
			s.color = BLOOD_B
	elif r < 0.75:
		s.color = Color(0.600, 0.050, 0.050)
	else:
		s.color = Color(0.160, 0.165, 0.230)
	return s

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SPAWN DE CHARCOS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _spawn_blood(x: float, y: float, impact: float) -> void:
	# Número de gotas satélite (dispersión al impactar)
	var drops := 1 + int(_blood_factor * 4.0) + randi_range(0, 2)
	var base_r := randf_range(5.0, 12.0) * (0.6 + _blood_factor * 1.8) * clampf(impact / 3.0, 0.5, 2.5)

	for _i in range(drops):
		var p            := _BloodPool.new()
		p.x              = x + randf_range(-22.0, 22.0) * (impact / 3.0)
		# Mantener en banda inferior de pantalla
		p.y              = clampf(y + randf_range(-6.0, 6.0), VH * 0.72, VH * 0.97)
		p.target_r       = base_r * randf_range(0.5, 1.5)
		p.current_r      = 0.0
		p.grow_speed     = p.target_r / randf_range(10.0, 25.0)
		p.target_a       = randf_range(0.38, 0.68) * (0.4 + _blood_factor * 0.6)
		p.alpha          = 0.0
		p.settled        = false
		var t := randf()
		p.color = BLOOD_A if t < 0.45 else (BLOOD_B if t < 0.75 else BLOOD_C)
		_blood_pools.append(p)

	# Charco principal grande centrado en el impacto
	var main         := _BloodPool.new()
	main.x           = x + randf_range(-4.0, 4.0)
	main.y           = clampf(y, VH * 0.72, VH * 0.97)
	main.target_r    = base_r * randf_range(1.2, 2.2)
	main.current_r   = 0.0
	main.grow_speed  = main.target_r / randf_range(18.0, 38.0)
	main.target_a    = (0.42 + _blood_factor * 0.38)
	main.alpha       = 0.0
	main.settled     = false
	main.color       = BLOOD_A
	_blood_pools.append(main)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PROCESO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	VW = vp.x;  VH = vp.y
	_recalc_btn_positions()
	var dt := delta * 60.0

	# ── Máquina de estados ────────────────────────────────────────
	_phase_timer += dt
	match _phase:
		"enter":
			_fade_in     = minf(1.0, _phase_timer / 40.0)
			if _phase_timer > 25.0:
				_title_shown = minf(1.0, (_phase_timer - 25.0) / 30.0)
			if _phase_timer >= 60.0:
				_phase = "stats"; _phase_timer = 0.0
		"stats":
			_content_prog = minf(1.0, _phase_timer / 50.0)
			_update_badges(dt)
			if _phase_timer >= 80.0:
				_phase = "buttons"; _phase_timer = 0.0
		"buttons":
			_buttons_prog = minf(1.0, _phase_timer / 40.0)
			_update_badges(dt)

	# ── Shards ────────────────────────────────────────────────────
	var floor_y := VH * 0.82
	for s in _shards:
		if not s.landed:
			s.x  += s.vx * dt
			s.y  += s.vy * dt
			s.vy *= pow(1.004, dt)
			if s.y >= floor_y:
				s.y      = floor_y + randf_range(0.0, VH * 0.10)
				s.landed = true
		else:
			# Spawn charco al primer frame en suelo
			if not s.spawned:
				s.spawned = true
				if s.is_blood and _blood_factor > 0.02:
					_spawn_blood(s.x, s.y, s.vy)
			# Fade lento del shard visual
			s.life  += dt
			s.alpha  = maxf(0.0, 0.96 * (1.0 - s.life / s.max_life))

	# ── Charcos: crecer suavemente ────────────────────────────────
	for p in _blood_pools:
		if not p.settled:
			p.current_r = minf(p.target_r, p.current_r + p.grow_speed * dt)
			p.alpha     = minf(p.target_a, p.alpha + 0.018 * dt)
			if p.current_r >= p.target_r:
				p.settled = true

	# ── Hover de botones ─────────────────────────────────────────
	var mp      := _virtual_mouse()
	var safe_dt := minf(dt, 3.0)
	var spd     := 0.14 * safe_dt
	var rhov    := _buttons_prog > 0.3 and _btn_hit_rect(_btn_retry_cx).has_point(mp)
	var mhov    := _buttons_prog > 0.3 and _btn_hit_rect(_btn_menu_cx).has_point(mp)

	_btn_retry_scale += ((1.015 if rhov else 1.0) - _btn_retry_scale) * spd * 3.0
	_btn_menu_scale  += ((1.015 if mhov else 1.0) - _btn_menu_scale)  * spd * 3.0
	_btn_retry_glow  += ((1.0   if rhov else 0.0) - _btn_retry_glow)  * spd * 2.0
	_btn_menu_glow   += ((1.0   if mhov else 0.0) - _btn_menu_glow)   * spd * 2.0

	_btn_retry_scale = clampf(_btn_retry_scale, 0.98, 1.05)
	_btn_menu_scale  = clampf(_btn_menu_scale,  0.98, 1.05)
	_btn_retry_glow  = clampf(_btn_retry_glow,  0.0,  1.0)
	_btn_menu_glow   = clampf(_btn_menu_glow,   0.0,  1.0)

	queue_redraw()

func _update_badges(dt: float) -> void:
	if _badge_score_delay > 0.0: _badge_score_delay -= dt
	else: _badge_score_shown = minf(1.0, _badge_score_shown + 0.035 * dt)
	if _badge_time_delay > 0.0: _badge_time_delay -= dt
	else: _badge_time_shown  = minf(1.0, _badge_time_shown  + 0.035 * dt)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _unhandled_input(event: InputEvent) -> void:
	if _buttons_prog < 0.3: return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := _virtual_mouse()
		if _btn_hit_rect(_btn_retry_cx).has_point(mp): _go_retry(); return
		if _btn_hit_rect(_btn_menu_cx).has_point(mp):  _go_menu();  return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:                        _go_retry()
			KEY_SPACE, KEY_ENTER, KEY_ESCAPE: _go_menu()

func _go_retry() -> void:
	GameManager.goto_scene("res://scenes/gameplay.tscn", {})

func _go_menu() -> void:
	GameManager.goto_scene("res://scenes/menu.tscn", {})

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DIBUJO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), C_BG)
	_draw_grid()
	_draw_vignette()
	_draw_blood_pools()   # charcos — capa más baja
	_draw_shards()
	_draw_overlay()
	_draw_title()
	_draw_divider()
	_draw_badges()
	_draw_buttons()
	_draw_hints()

# ── Grid ──────────────────────────────────────────────────────────

func _draw_grid() -> void:
	var gs := 60.0
	var x := 0.0
	while x <= VW:
		draw_line(Vector2(x, 0), Vector2(x, VH), Color(1, 1, 1, 0.018)); x += gs
	var y := 0.0
	while y <= VH:
		draw_line(Vector2(0, y), Vector2(VW, y), Color(1, 1, 1, 0.018)); y += gs

# ── Viñeta ────────────────────────────────────────────────────────

func _draw_vignette() -> void:
	for c in [Vector2(0, 0), Vector2(VW, 0), Vector2(0, VH), Vector2(VW, VH)]:
		for i in range(6):
			draw_circle(c, 400.0 - float(i) * 30.0,
						Color(0, 0, 0, 0.06 + float(i) * 0.018))

# ── Charcos de sangre ─────────────────────────────────────────────

func _draw_blood_pools() -> void:
	for p in _blood_pools:
		if p.current_r < 0.5 or p.alpha < 0.01: continue
		var pos := Vector2(p.x, p.y)
		var r   : float = p.current_r
		var a   : float = p.alpha
		# Capa exterior difusa
		draw_circle(pos, r, Color(p.color.r, p.color.g, p.color.b, a * 0.55))
		# Capa media
		draw_circle(pos, r * 0.68, Color(BLOOD_B.r, BLOOD_B.g, BLOOD_B.b, a * 0.80))
		# Núcleo oscuro (da profundidad)
		draw_circle(pos, r * 0.32, Color(BLOOD_A.r * 0.6, 0.0, 0.0, a))

# ── Shards ────────────────────────────────────────────────────────

func _draw_shards() -> void:
	for s in _shards:
		if s.alpha < 0.031: continue
		var sz : float = s.size
		draw_rect(Rect2(s.x - sz, s.y - sz, sz * 2, sz * 2),
				  Color(s.color.r, s.color.g, s.color.b, s.alpha))

# ── Overlay oscuro ────────────────────────────────────────────────

func _draw_overlay() -> void:
	draw_rect(Rect2(0, 100, VW, 200), Color(0, 0, 0, _fade_in * 0.82))

# ── Título ────────────────────────────────────────────────────────

func _draw_title() -> void:
	if _title_shown < 0.01: return
	var a  := _title_shown
	var sl := (1.0 - _title_shown) * 20.0
	var cx := VW * 0.5
	var ty := 170.0 + sl
	const FS := 80
	_text_center("GAME  OVER", Vector2(cx + 4, ty + 4), FS, Color(0.627, 0.0, 0.0, a * 0.6))
	_text_center("GAME  OVER", Vector2(cx - 3, ty + 2), FS, Color(0.0, 0.392, 0.431, a * 0.6))
	_text_center("GAME  OVER", Vector2(cx, ty),          FS, Color(C_WHITE.r, C_WHITE.g, C_WHITE.b, a))
	# Línea roja bajo título — solo 460px centrada
	var lw := _title_shown * 460.0
	draw_line(Vector2(cx - lw * 0.5, ty + 70), Vector2(cx + lw * 0.5, ty + 70),
			  Color(C_RED.r, C_RED.g, C_RED.b, a), 2.0)

# ── Divisor (entre título y badges) — máx 500px, centrado ─────────

func _draw_divider() -> void:
	if _content_prog < 0.01: return
	var cx := VW * 0.5
	var lw := _content_prog * 500.0   # ← limitado, NO borde a borde
	draw_line(Vector2(cx - lw * 0.5, 268), Vector2(cx + lw * 0.5, 268),
			  Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, _content_prog * 0.65), 1.0)

# ── Badges de estadísticas ────────────────────────────────────────

func _draw_badges() -> void:
	var cx := VW * 0.5
	# Separación: 130px a cada lado del centro → gap de 260px entre centros
	_draw_badge(cx - 135.0, 350.0, "PUNTUACION", _fmt_score(_final_score), C_GOLD, _badge_score_shown)
	_draw_badge(cx + 135.0, 350.0, "TIEMPO",      _final_time_str,          C_CYAN, _badge_time_shown)

func _draw_badge(cx: float, y: float, label: String, value: String,
				 accent: Color, shown: float) -> void:
	if shown < 0.01: return
	var a     := shown
	var slide := (1.0 - shown) * 20.0
	var ry    := y + slide
	const W   := 240.0
	const H   :=  80.0
	var x     := cx - W * 0.5

	draw_rect(Rect2(x, ry, W, H), Color(C_PANEL.r, C_PANEL.g, C_PANEL.b, a * 0.88))
	draw_rect(Rect2(x, ry, W, H), Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, a), false, 1.0)
	draw_rect(Rect2(x + 5, ry + 8, 4, H - 16), Color(accent.r, accent.g, accent.b, a))
	# Línea de acento en borde superior (sutil)
	draw_line(Vector2(x + 5, ry), Vector2(x + W * 0.98, ry),
			  Color(accent.r, accent.g, accent.b, a * 0.30), 1.0)

	_text(label, Vector2(x + 16, ry + 10), 15, Color(C_GRAY.r, C_GRAY.g, C_GRAY.b, a * 0.85))
	_text(value, Vector2(x + 16, ry + 30), 36, Color(accent.r, accent.g, accent.b, a))

# ── Botones ───────────────────────────────────────────────────────

func _draw_buttons() -> void:
	if _buttons_prog < 0.01: return
	_draw_button(_btn_retry_cx, BTN_Y, "  REINTENTAR",
				 C_RED, _btn_retry_scale, _btn_retry_glow, _buttons_prog, 26)
	_draw_button(_btn_menu_cx,  BTN_Y, "  MENU PRINCIPAL",
				 Color(0.275, 0.294, 0.451),
				 _btn_menu_scale, _btn_menu_glow, _buttons_prog, 22)

func _draw_button(btn_cx: float, btn_y: float, label: String, accent: Color,
				  btn_scale: float, glow: float, vis: float, fs: int) -> void:
	var a := vis
	if a < 0.031: return
	var w := maxf(4.0, BTN_W * btn_scale)
	var h := maxf(4.0, BTN_H * btn_scale)
	var x := btn_cx - w * 0.5
	var y := btn_y + BTN_H * 0.5 - h * 0.5

	draw_rect(Rect2(x - 4, y + 6, w + 16, h + 16), Color(0, 0, 0, 0.4 * a))
	if glow > 0.05:
		draw_rect(Rect2(x - 20, y - 20, w + 40, h + 40),
				  Color(accent.r, accent.g, accent.b, glow * 0.196 * a))
	draw_rect(Rect2(x, y, w, h), Color(
		clampf(C_PANEL.r + glow * 0.055, 0, 1),
		clampf(C_PANEL.g + glow * 0.055, 0, 1),
		clampf(C_PANEL.b + glow * 0.094, 0, 1),
		0.88 * a))
	draw_rect(Rect2(x + 6, y + 8, 5, h - 16), Color(accent.r, accent.g, accent.b, a))
	var bd := accent if glow > 0.5 else C_BORDER
	draw_rect(Rect2(x, y, w, h), Color(bd.r, bd.g, bd.b, a), false, 2.0)
	var tc := C_WHITE if glow > 0.5 else Color(0.686, 0.698, 0.753)
	_text_center(label, Vector2(btn_cx, y + h * 0.5), fs, Color(tc.r, tc.g, tc.b, a))

# ── Hints ─────────────────────────────────────────────────────────

func _draw_hints() -> void:
	if _buttons_prog < 0.6: return
	var a  := (_buttons_prog - 0.6) / 0.4 * 0.62
	var cx := VW * 0.5
	var y  := BTN_Y + BTN_H + 26.0
	const FS  := 15
	const GAP := 54.0
	var h0  := ["R", "Reintentar"]
	var h1  := ["ESPACIO / ESC", "Menu principal"]
	var tw0 := _str_w(h0[0], FS) + _str_w("  " + h0[1], FS)
	var tw1 := _str_w(h1[0], FS) + _str_w("  " + h1[1], FS)
	var sx  := cx - (tw0 + GAP + tw1) * 0.5
	var ck  := Color(0.314, 0.325, 0.392, a)
	var ca  := Color(0.196, 0.204, 0.267, a)
	_text(h0[0],          Vector2(sx, y), FS, ck)
	_text("  " + h0[1],   Vector2(sx + _str_w(h0[0], FS), y), FS, ca)
	var x1 := sx + tw0 + GAP
	_text(h1[0],          Vector2(x1, y), FS, ck)
	_text("  " + h1[1],   Vector2(x1 + _str_w(h1[0], FS), y), FS, ca)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  UTILIDADES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _btn_hit_rect(btn_cx: float) -> Rect2:
	return Rect2(btn_cx - BTN_W * 0.5 - 7, BTN_Y - 7, BTN_W + 14, BTN_H + 14)

func _virtual_mouse() -> Vector2:
	return get_local_mouse_position()

func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	draw_string(_font, Vector2(pos.x, pos.y + _font.get_ascent(fs)),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline),
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