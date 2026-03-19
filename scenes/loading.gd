extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/loading.gd — ProyectSurvivor
##
##  Pantalla de carga minimalista con barra verde.
##  Usa ResourceLoader.load_threaded_request() para cargar la escena
##  destino en un hilo secundario sin bloquear el main thread.
##
##  Flujo:
##    Main.gd detecta gameplay.tscn → instancia loading.tscn primero
##    loading.gd carga gameplay.tscn en segundo plano
##    Cuando termina → llama GameManager.goto_scene() con el target
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Paleta ────────────────────────────────────────────────────────
const C_BG      := Color(0.024, 0.027, 0.039)
const C_GREEN   := Color(0.196, 0.863, 0.431)
const C_GREEN_G := Color(0.196, 0.863, 0.431, 0.0)  # para glow
const C_WHITE   := Color(0.902, 0.910, 0.933)
const C_GRAY    := Color(0.275, 0.290, 0.345)
const C_DIM     := Color(0.110, 0.118, 0.157)
const C_BORDER  := Color(0.157, 0.173, 0.243)

# ── Barra ─────────────────────────────────────────────────────────
const BAR_W : float = 300.0
const BAR_H : float = 3.0

# ── Estado ────────────────────────────────────────────────────────
var VW : float = 1280.0
var VH : float =  720.0

var _target_scene  : String     = "res://scenes/gameplay.tscn"
var _target_data   : Dictionary = {}

var _progress      : float = 0.0   # real (del loader)
var _display_prog  : float = 0.0   # suavizada para el render
var _done          : bool  = false
var _transitioning : bool  = false

var _timer      : float = 0.0
var _dot_phase  : int   = 0
var _dot_timer  : float = 0.0
var _fade_in    : float = 0.0     # 0→1 al entrar
var _fade_out   : float = 0.0     # 0→1 al salir

var _font : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CICLO DE VIDA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	_font = ThemeDB.fallback_font

func setup(data: Dictionary) -> void:
	_target_scene = data.get("target", "res://scenes/gameplay.tscn")
	_target_data  = data.get("data",   {})
	ResourceLoader.load_threaded_request(_target_scene)

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	VW = vp.x
	VH = vp.y

	_timer     += delta
	_dot_timer += delta
	if _dot_timer > 0.38:
		_dot_timer = 0.0
		_dot_phase = (_dot_phase + 1) % 4

	# ── Fade de entrada ───────────────────────────────────────────
	_fade_in = minf(1.0, _fade_in + delta * 3.5)

	# ── Consultar el loader ───────────────────────────────────────
	if not _done:
		var progress_arr : Array = []
		var status := ResourceLoader.load_threaded_get_status(_target_scene, progress_arr)

		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if progress_arr.size() > 0:
					_progress = float(progress_arr[0])
			ResourceLoader.THREAD_LOAD_LOADED:
				_progress = 1.0
				_done     = true
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("loading.gd: fallo al cargar %s" % _target_scene)
				_progress = 1.0
				_done     = true

	# ── Interpolar barra de progreso ──────────────────────────────
	var lerp_speed : float = 5.0 if not _done else 14.0
	_display_prog += (_progress - _display_prog) * minf(1.0, delta * lerp_speed)

	# ── Transición de salida ──────────────────────────────────────
	if _done and _display_prog >= 0.995 and not _transitioning:
		_transitioning = true
		_display_prog  = 1.0
		# Reclamar recurso del caché de hilos para que load() lo encuentre
		ResourceLoader.load_threaded_get(_target_scene)
		# Pequeña pausa para que el fade-out se vea
		await get_tree().create_timer(0.18).timeout
		GameManager.goto_scene(_target_scene, _target_data)

	# ── Fade de salida ────────────────────────────────────────────
	if _transitioning:
		_fade_out = minf(1.0, _fade_out + delta * 6.0)

	queue_redraw()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  RENDER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), C_BG)
	_draw_grid()
	_draw_vignette()

	var alpha : float = _fade_in * (1.0 - _fade_out)

	#_draw_title(alpha)
	_draw_bar(alpha)
	_draw_label(alpha)

	# Fade negro encima al salir
	if _fade_out > 0.01:
		draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, _fade_out))

# ── Cuadrícula sutil ──────────────────────────────────────────────

func _draw_grid() -> void:
	const GS : float = 80.0
	var x := 0.0
	while x <= VW:
		draw_line(Vector2(x, 0.0), Vector2(x, VH), Color(1.0, 1.0, 1.0, 0.018))
		x += GS
	var y := 0.0
	while y <= VH:
		draw_line(Vector2(0.0, y), Vector2(VW, y), Color(1.0, 1.0, 1.0, 0.018))
		y += GS

# ── Viñeta ────────────────────────────────────────────────────────

func _draw_vignette() -> void:
	for corner in [Vector2(0.0, 0.0), Vector2(VW, 0.0), Vector2(0.0, VH), Vector2(VW, VH)]:
		for i in range(5):
			draw_circle(corner, 420.0 - float(i) * 40.0, Color(0.0, 0.0, 0.0, 0.05 + float(i) * 0.012))

# ── Título del juego (tenue) ──────────────────────────────────────

func _draw_title(alpha: float) -> void:
	if alpha < 0.01:
		return
	var cx := VW * 0.5
	var ty := VH * 0.5 - 52.0

	# Nombre de juego muy sutil
	_text_center("PROYECT  SURVIVOR", Vector2(cx, ty), 18,
				 Color(C_DIM.r, C_DIM.g, C_DIM.b + 0.04, alpha * 0.70))

	# Separador
	var sep_w : float = 140.0 * alpha
	draw_line(
		Vector2(cx - sep_w * 0.5, ty + 20.0),
		Vector2(cx + sep_w * 0.5, ty + 20.0),
		Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, alpha * 0.45), 1.0
	)

# ── Barra de carga ────────────────────────────────────────────────

func _draw_bar(alpha: float) -> void:
	if alpha < 0.01:
		return

	var cx  : float = VW * 0.5
	var by  : float = VH * 0.5 + 6.0
	var bx  : float = cx - BAR_W * 0.5

	# Fondo de la barra
	draw_rect(Rect2(bx - 1.0, by - 1.0, BAR_W + 2.0, BAR_H + 2.0),
			  Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, alpha * 0.4))
	draw_rect(Rect2(bx, by, BAR_W, BAR_H),
			  Color(0.055, 0.065, 0.055, alpha))

	# Relleno
	var fill_w : float = maxf(0.0, BAR_W * _display_prog)
	if fill_w > 0.5:
		draw_rect(Rect2(bx, by, fill_w, BAR_H),
				  Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, alpha))

		# Pulso en el borde de avance
		if fill_w < BAR_W - 2.0:
			var pulse_a : float = (sin(_timer * 8.0) * 0.5 + 0.5) * alpha * 0.9
			draw_rect(
				Rect2(bx + fill_w - 1.0, by - 2.0, 3.0, BAR_H + 4.0),
				Color(C_GREEN.r * 1.4, C_GREEN.g * 1.2, C_GREEN.b * 1.1, pulse_a)
			)

# ── Texto "CARGANDO..." + porcentaje ──────────────────────────────

func _draw_label(alpha: float) -> void:
	if alpha < 0.01:
		return

	var cx : float = VW * 0.5
	var ty : float = VH * 0.5 - 16.0

	# "CARGANDO" con puntos animados
	var dots : String = ".".repeat(_dot_phase)
	var spaces : String = " ".repeat(3 - _dot_phase)    # mantiene ancho constante
	var label : String = "CARGANDO" + dots + spaces
	_text_center(label, Vector2(cx, ty), 14,
				 Color(C_GRAY.r, C_GRAY.g, C_GRAY.b, alpha * 0.85))

	# Porcentaje alineado debajo de la barra
	var pct_str : String = "%d%%" % int(_display_prog * 100.0)
	var bar_by  : float  = VH * 0.5 + 6.0
	_text_center(pct_str, Vector2(cx, bar_by + BAR_H + 16.0), 13,
				 Color(C_GREEN.r, C_GREEN.g, C_GREEN.b, alpha * (0.5 + _display_prog * 0.5)))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE TEXTO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var tw       : float = _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline : float = center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)