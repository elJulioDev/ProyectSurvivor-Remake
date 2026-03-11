extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/menu.gd — ProyectSurvivor
##  Port de src/scenes/menu.py (Pygame) a Godot 4
##
##  Sin nodos hijos requeridos — todo se dibuja con _draw().
##  Compatible con el sistema de escenas de scenes/Main.gd.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Paleta ────────────────────────────────────────────────────────
const C_BG         := Color(0.024, 0.027, 0.039)
const C_RED        := Color(0.824, 0.118, 0.118)
const C_RED_DIM    := Color(0.510, 0.059, 0.059)
const C_CYAN       := Color(0.000, 0.824, 0.863)
const C_CYAN_DIM   := Color(0.000, 0.353, 0.392)
const C_WHITE      := Color(0.902, 0.910, 0.933)
const C_GRAY       := Color(0.353, 0.361, 0.412)
const C_PANEL      := Color(0.055, 0.063, 0.094)
const C_BORDER     := Color(0.157, 0.173, 0.243)
const C_BORDER_LIT := Color(0.275, 0.294, 0.431)

# ── Dimensiones (espacio virtual — igual que en Pygame) ───────────
var VW := 1280.0
var VH :=  720.0

# ── Botones ───────────────────────────────────────────────────────
const BTN_W  := 320.0
const BTN_H  :=  64.0
var BTN_CX := 640.0
const BTN_Y0 := 300.0        # INICIAR JUEGO
const BTN_Y1 := 390.0        # SALIR  (340 + 82)

# ── Estado interno ────────────────────────────────────────────────
var _timer         : float = 0.0
var _glitch_timer  : float = 0.0
var _glitch_active : bool  = false

# Animaciones de botones
var _play_scale : float = 1.0
var _play_glow  : float = 0.0
var _exit_scale : float = 1.0
var _exit_glow  : float = 0.0

# ── Partículas ────────────────────────────────────────────────────
class _Particle:
	var x        : float
	var y        : float
	var speed    : float
	var size     : float
	var color    : Color
	var life     : float
	var max_life : float

	func reset(vw: float, vh: float) -> void:
		x        = randf() * vw
		y        = randf() * vh
		speed    = randf_range(0.15, 0.55)
		size     = float(randi_range(1, 3))
		max_life = randf_range(180.0, 420.0)
		life     = randf_range(0.0, max_life)
		var r := randf()
		if r < 0.45:
			color = Color(0.824, 0.118, 0.118)
		elif r < 0.65:
			color = Color(0.000, 0.824, 0.863)
		else:
			color = Color(0.314, 0.333, 0.431)

	func alpha() -> float:
		var t := life / max_life
		if t < 0.2: return t / 0.2 * 0.627
		if t > 0.8: return (1.0 - t) / 0.2 * 0.627
		return 0.627

var _particles : Array[_Particle] = []

# ── Líneas de escaneo ─────────────────────────────────────────────

# ── Líneas de escaneo ─────────────────────────────────────────────
class _ScanLine:
	var y     : float
	var alpha : float
	var speed : float

	func reset(vh: float) -> void:
		y     = randf() * vh
		alpha = randf_range(0.031, 0.086)
		speed = randf_range(0.2, 0.8)

var _scanlines : Array[_ScanLine] = []

# ── Fuente ────────────────────────────────────────────────────────
var _font : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INICIALIZACIÓN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	_font = ThemeDB.fallback_font
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var vp_size := get_viewport_rect().size

	for _i in range(55):
		var p := _Particle.new()
		p.reset(vp_size.x, vp_size.y)
		_particles.append(p)

	for _i in range(6):
		var sl := _ScanLine.new()
		sl.reset(vp_size.y)
		_scanlines.append(sl)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PROCESO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _process(delta: float) -> void:
	var vp_size := get_viewport_rect().size
	VW = vp_size.x
	VH = vp_size.y
	BTN_CX = VW * 0.5

	var dt := delta * 60.0
	_timer += 0.018 * dt

	# Partículas
	for p in _particles:
		p.y    -= p.speed * dt
		p.life += dt
		if p.y < -10.0 or p.life > p.max_life:
			p.reset(VW, VH)
			p.y = VH + 5.0

	# Líneas de escaneo
	for sl in _scanlines:
		sl.y += sl.speed * dt
		if sl.y > VH:
			sl.reset(VH)
			sl.y = -2.0

	# Efecto glitch del título
	_glitch_timer += dt
	if _glitch_timer > 180.0 and not _glitch_active:
		if randf() < 0.012:
			_glitch_active = true
			_glitch_timer  = 0.0
	if _glitch_active and _glitch_timer > 6.0:
		_glitch_active = false
		_glitch_timer  = 0.0

	# Hover de botones (coordenadas virtuales)
	var mp       := _virtual_mouse()
	var safe_dt  := minf(dt, 3.0)
	var spd      := 0.14 * safe_dt

	var play_hov := _btn_rect(BTN_Y0).has_point(mp)
	var exit_hov := _btn_rect(BTN_Y1).has_point(mp)

	_play_scale += ((1.015 if play_hov else 1.0) - _play_scale) * spd * 3.0
	_exit_scale += ((1.015 if exit_hov else 1.0) - _exit_scale) * spd * 3.0
	_play_glow  += ((1.0   if play_hov else 0.0) - _play_glow)  * spd * 2.0
	_exit_glow  += ((1.0   if exit_hov else 0.0) - _exit_glow)  * spd * 2.0

	_play_scale = clampf(_play_scale, 0.98, 1.05)
	_exit_scale = clampf(_exit_scale, 0.98, 1.05)
	_play_glow  = clampf(_play_glow,  0.0,  1.0)
	_exit_glow  = clampf(_exit_glow,  0.0,  1.0)

	queue_redraw()

# ── Input ─────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := _virtual_mouse()
		if _btn_rect(BTN_Y0).has_point(mp):
			_go_play()
			return
		if _btn_rect(BTN_Y1).has_point(mp):
			get_tree().quit()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER:
				_go_play()
			KEY_ESCAPE:
				get_tree().quit()

func _go_play() -> void:
	GameManager.goto_scene("res://scenes/gameplay.tscn", {})

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DIBUJO PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), C_BG)
	_draw_grid()
	_draw_vignette()
	_draw_particles()
	_draw_scanlines()
	_draw_title()
	_draw_tagline()
	_draw_button(BTN_Y0, "  INICIAR JUEGO", C_RED,
				 _play_scale, _play_glow, 28)
	_draw_button(BTN_Y1, "  SALIR",
				 Color(0.314, 0.314, 0.431),
				 _exit_scale, _exit_glow, 26)
	_draw_key_hint()
	_draw_controls_panel()
	_draw_version()

# ── Cuadrícula de fondo ───────────────────────────────────────────

func _draw_grid() -> void:
	var gs := 60.0
	var x  := 0.0
	while x <= VW:
		draw_line(Vector2(x, 0.0), Vector2(x, VH), Color(1, 1, 1, 0.027))
		x += gs
	var y := 0.0
	while y <= VH:
		draw_line(Vector2(0.0, y), Vector2(VW, y), Color(1, 1, 1, 0.027))
		y += gs
	# Diagonales decorativas
	draw_line(Vector2(0.0, VH),       Vector2(VW * 0.6, 0.0), Color(0.784, 0.078, 0.078, 0.071))
	draw_line(Vector2(0.0, VH * 0.8), Vector2(VW * 0.8, 0.0), Color(0.784, 0.078, 0.078, 0.047))
	# Barras accent (arriba roja, abajo cian)
	draw_line(Vector2(0.0, 2.0), Vector2(VW, 2.0), C_RED_DIM,  2.0)
	draw_line(Vector2(0.0, VH - 3.0), Vector2(VW, VH - 3.0), C_CYAN_DIM, 2.0)

# ── Viñeta oscura en esquinas ─────────────────────────────────────

func _draw_vignette() -> void:
	var corners := [
		Vector2(0.0, 0.0), Vector2(VW, 0.0),
		Vector2(0.0, VH),  Vector2(VW, VH),
	]
	for c in corners:
		for i in range(6):
			var frac  := float(i) / 6.0
			var radius := 380.0 * (1.0 - frac * 0.35)
			var alpha  := 0.055 * frac
			draw_circle(c, radius, Color(0.0, 0.0, 0.0, alpha))

# ── Partículas de ambiente ────────────────────────────────────────

func _draw_particles() -> void:
	for p in _particles:
		var a := p.alpha()
		if a < 0.031:
			continue
		draw_circle(Vector2(p.x, p.y), p.size,
					Color(p.color.r, p.color.g, p.color.b, a))

# ── Líneas de escaneo ─────────────────────────────────────────────

func _draw_scanlines() -> void:
	for sl in _scanlines:
		draw_line(Vector2(0.0, sl.y), Vector2(VW, sl.y),
				  Color(1.0, 1.0, 1.0, sl.alpha), 2.0)

# ── Título "PROYECT / SURVIVOR" ───────────────────────────────────

func _draw_title() -> void:
	var gx  := randf_range(-4.0, 4.0) if _glitch_active else 0.0
	var cx  := VW * 0.5
	var ty  := 105.0
	var fst := 80   # tamaño fuente título

	# Efecto chromatic aberration (sombras desplazadas)
	_text_center("PROYECT", Vector2(cx + gx + 3.0, ty + 3.0), fst,
				 Color(0.706, 0.0, 0.0, 1.0))
	_text_center("PROYECT", Vector2(cx + gx - 3.0, ty + 1.0), fst,
				 Color(0.0, 0.471, 0.510, 1.0))
	# Texto principal
	_text_center("PROYECT", Vector2(cx + gx, ty), fst, C_WHITE)

	# Subtítulo pulsante
	var beat     : float = abs(sin(_timer * 0.9))
	var sub_col  := Color(0.784 + beat * 0.216, beat * 0.078, beat * 0.078)
	var sub_str  := "SURVIVOR"
	var fss      := 24
	var sw       := _str_w(sub_str, fss)
	var sy       := 190.0
	var line_y   := sy + 1.0

	# Líneas flanqueando el subtítulo
	draw_line(Vector2(cx - sw * 0.5 - 60.0, line_y),
			  Vector2(cx - sw * 0.5 - 8.0,  line_y), C_RED_DIM, 2.0)
	draw_line(Vector2(cx + sw * 0.5 + 8.0,  line_y),
			  Vector2(cx + sw * 0.5 + 60.0, line_y), C_RED_DIM, 2.0)

	# Sombra + texto subtítulo
	_text_center(sub_str, Vector2(cx + 2.0, sy + 2.0), fss, Color(0.235, 0.0, 0.0))
	_text_center(sub_str, Vector2(cx, sy),              fss, sub_col)

# ── Tagline ───────────────────────────────────────────────────────

func _draw_tagline() -> void:
	var cy := 240.0 + sin(_timer * 0.7) * 2.0
	_text_center("Sobrevive. Evoluciona. Muere de pie.", Vector2(VW * 0.5, cy), 18, C_GRAY)

# ── Botón genérico ────────────────────────────────────────────────

func _draw_button(btn_y: float, label: String, accent: Color,
				  btn_scale: float, glow: float, fs: int) -> void:
	var w  := maxf(4.0, BTN_W * btn_scale)
	var h  := maxf(4.0, BTN_H * btn_scale)
	var x  := BTN_CX - w * 0.5
	var y  := btn_y + BTN_H * 0.5 - h * 0.5

	# Sombra
	draw_rect(Rect2(x - 6.0, y + 8.0, w + 20.0, h + 20.0),
			  Color(0.0, 0.0, 0.0, 0.35))

	# Halo de acento (al hover)
	if glow > 0.05:
		draw_rect(Rect2(x - 20.0, y - 20.0, w + 40.0, h + 40.0),
				  Color(accent.r, accent.g, accent.b, glow * 0.216))

	# Fondo
	var bg := Color(
		clampf(C_PANEL.r + glow * 0.055, 0.0, 1.0),
		clampf(C_PANEL.g + glow * 0.055, 0.0, 1.0),
		clampf(C_PANEL.b + glow * 0.094, 0.0, 1.0),
		0.88
	)
	draw_rect(Rect2(x, y, w, h), bg)

	# Barra de acento izquierda
	draw_rect(Rect2(x + 6.0, y + 8.0, 5.0, h - 16.0), accent)

	# Borde (iluminado al hover)
	var bd_col := accent if glow > 0.5 else C_BORDER_LIT
	draw_rect(Rect2(x, y, w, h), bd_col, false, 2.0)

	# Texto
	var tc := C_WHITE if glow > 0.5 else Color(0.686, 0.698, 0.753)
	_text_center(label, Vector2(BTN_CX, y + h * 0.5), fs, tc)

# ── Hint de teclado ───────────────────────────────────────────────

func _draw_key_hint() -> void:
	_text_center("ESPACIO  /  ENTER  para iniciar",
				 Vector2(VW * 0.5, 490.0), 18,
				 Color(0.216, 0.227, 0.294))

# ── Panel de controles ────────────────────────────────────────────

func _draw_controls_panel() -> void:
	var px := VW * 0.5 - 220.0
	var py := 520.0
	var pw := 440.0
	var ph := 160.0

	# Fondo y borde del panel
	draw_rect(Rect2(px, py, pw, ph),
			  Color(C_PANEL.r, C_PANEL.g, C_PANEL.b, 0.686))
	draw_rect(Rect2(px, py, pw, ph),
			  Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.784), false, 1.0)

	# Cabecera
	_text_center("CONTROLES", Vector2(px + pw * 0.5, py + 10.0),
				 15, C_CYAN_DIM)
	draw_line(Vector2(px + 12.0, py + 28.0),
			  Vector2(px + pw - 12.0, py + 28.0), C_BORDER, 1.0)

	# Filas de controles
	var controls := [
		["WASD",        "Mover"],
		["Mouse",       "Apuntar"],
		["Click Izq",   "Disparar"],
		["1 – 4",       "Cambiar arma"],
		["Ctrl",        "Dash"],
		["ESC / Enter", "Pausa"],
	]
	var row_h := 18.0
	var fs_c  := 16
	for i in range(controls.size()):
		var ky := py + 36.0 + i * row_h
		_text(controls[i][0], Vector2(px + 18.0, ky),  fs_c, Color(0.745, 0.753, 0.804))
		_text(controls[i][1], Vector2(px + 165.0, ky), fs_c, Color(0.353, 0.365, 0.451))

# ── Versión ───────────────────────────────────────────────────────

func _draw_version() -> void:
	var t  := "v0.1-alpha  -  ProyectSurvivor"
	var tw := _str_w(t, 14)
	_text(t, Vector2(VW - tw - 12.0, VH - 24.0), 14,
		  Color(0.137, 0.145, 0.204))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  UTILIDADES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Rect del botón (sin escalar) para detección de hover/click
func _btn_rect(btn_y: float) -> Rect2:
	return Rect2(BTN_CX - BTN_W * 0.5 - 8.0, btn_y - 8.0,
				 BTN_W + 16.0, BTN_H + 16.0)

## Posición del ratón convertida al espacio virtual (1280×720)
func _virtual_mouse() -> Vector2:
	return get_local_mouse_position()

## Dibuja texto con origen en la esquina superior-izquierda
func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var baseline := pos.y + _font.get_ascent(fs)
	draw_string(_font, Vector2(pos.x, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Dibuja texto centrado en (cx, cy)
func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Ancho de una cadena en píxeles para el tamaño de fuente dado
func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font):
		return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## Entrada requerida por el sistema de escenas de Main.gd
func setup(_data: Dictionary) -> void:
	pass
