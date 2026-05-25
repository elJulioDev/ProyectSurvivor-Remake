extends Control

# Paleta
const C_GRID   := Color(1.0, 1.0, 1.0, 0.027)
const C_DIAG_1 := Color(0.784, 0.078, 0.078, 0.071)
const C_DIAG_2 := Color(0.784, 0.078, 0.078, 0.047)

const GRID_SIZE      := 60.0
const PART_COUNT     := 70
const SCAN_COUNT     := 6
const PART_SPEED_MIN := 0.55   # más rápido → cruzan toda la pantalla
const PART_SPEED_MAX := 1.60

var VW := 1280.0
var VH :=  720.0

# Grid animado
var _grid_offset_x := 0.0
var _grid_offset_y := 0.0
var _grid_speed_x  := 0.4
var _grid_speed_y  := 0.25

var _grid_v_points := PackedVector2Array()
var _grid_h_points := PackedVector2Array()

# Partículas
var _px       := PackedFloat32Array()
var _py       := PackedFloat32Array()
var _pspeed   := PackedFloat32Array()
var _psize    := PackedFloat32Array()   # ancho del segmento visible
var _plife    := PackedFloat32Array()
var _pmaxlife := PackedFloat32Array()
var _pcolor   := Array()

var _batch_red  := PackedVector2Array()
var _batch_cyan := PackedVector2Array()
var _batch_grey := PackedVector2Array()

# Scanlines
var _sl_y     := PackedFloat32Array()
var _sl_speed := PackedFloat32Array()
var _sl_lines := PackedVector2Array()

# Vignette
var _vignette_mesh   : PackedVector2Array
var _vignette_colors : PackedColorArray

func _ready() -> void:
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_update_dimensions()
	_init_particles()
	_init_scanlines()

func _on_viewport_resized() -> void:
	_update_dimensions()
	queue_redraw()

func _update_dimensions() -> void:
	var s := get_viewport_rect().size
	VW = s.x
	VH = s.y
	_build_grid_template()
	_build_vignette()

func _build_grid_template() -> void:
	_grid_v_points.clear()
	_grid_h_points.clear()
	var x := 0.0
	while x <= VW + GRID_SIZE:
		_grid_v_points.append(Vector2(x, 0.0))
		_grid_v_points.append(Vector2(x, VH))
		x += GRID_SIZE
	var y := 0.0
	while y <= VH + GRID_SIZE:
		_grid_h_points.append(Vector2(0.0, y))
		_grid_h_points.append(Vector2(VW,  y))
		y += GRID_SIZE

func _build_vignette() -> void:
	_vignette_mesh   = PackedVector2Array()
	_vignette_colors = PackedColorArray()
	var cx    := VW * 0.5
	var cy    := VH * 0.5
	var dark  := Color(0.0, 0.0, 0.0, 0.42)
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var corners := [
		Vector2(0.0, 0.0), Vector2(VW, 0.0),
		Vector2(VW,  VH),  Vector2(0.0, VH),
	]
	var edges := [
		[Vector2(cx, 0.0), Vector2(0.0, cy)],
		[Vector2(VW, cy),  Vector2(cx, 0.0)],
		[Vector2(cx, VH),  Vector2(VW, cy)],
		[Vector2(0.0, cy), Vector2(cx, VH)],
	]
	for i in range(4):
		_vignette_mesh.append(corners[i])
		_vignette_mesh.append(edges[i][0])
		_vignette_mesh.append(edges[i][1])
		_vignette_colors.append(dark)
		_vignette_colors.append(clear)
		_vignette_colors.append(clear)

# Partículas
func _init_particles() -> void:
	_px.resize(PART_COUNT);  _py.resize(PART_COUNT)
	_pspeed.resize(PART_COUNT);  _psize.resize(PART_COUNT)
	_plife.resize(PART_COUNT);   _pmaxlife.resize(PART_COUNT)
	_pcolor.resize(PART_COUNT)
	for i in range(PART_COUNT):
		_spawn_particle(i, false)

func _spawn_particle(i: int, respawn: bool) -> void:
	_px[i]     = randf() * VW
	# Spawn distribuido por toda la pantalla, no solo abajo
	_py[i]     = VH + randf_range(5.0, 40.0) if respawn else randf() * VH
	_pspeed[i] = randf_range(PART_SPEED_MIN, PART_SPEED_MAX)
	# Tamaños variados y más grandes: cortos brillantes + largos tenues
	var kind := randf()
	if kind < 0.35:
		# Estela larga
		_psize[i] = randf_range(18.0, 42.0)
	elif kind < 0.70:
		# Estela media
		_psize[i] = randf_range(6.0, 18.0)
	else:
		# Punto brillante pequeño
		_psize[i] = randf_range(2.0, 6.0)
	# max_life calculada para que la velocidad permita cruzar la pantalla entera
	var travel  := VH + 50.0
	var frames  := travel / _pspeed[i]
	_pmaxlife[i] = frames * randf_range(0.9, 1.1)   # leve variación
	_plife[i]    = 0.0 if respawn else randf_range(0.0, _pmaxlife[i])
	var r := randf()
	if r < 0.45:
		_pcolor[i] = Color(0.824, 0.118, 0.118)
	elif r < 0.65:
		_pcolor[i] = Color(0.000, 0.824, 0.863)
	else:
		_pcolor[i] = Color(0.314, 0.333, 0.431)

# Scanlines
func _init_scanlines() -> void:
	_sl_y.resize(SCAN_COUNT)
	_sl_speed.resize(SCAN_COUNT)
	for i in range(SCAN_COUNT):
		_spawn_scanline(i, false)

func _spawn_scanline(i: int, respawn: bool) -> void:
	_sl_y[i]     = -2.0 if respawn else randf() * VH
	_sl_speed[i] = randf_range(0.2, 0.8)

func _process(delta: float) -> void:
	var dt := delta * 60.0

	_grid_offset_x = fmod(_grid_offset_x + _grid_speed_x * dt, GRID_SIZE)
	_grid_offset_y = fmod(_grid_offset_y + _grid_speed_y * dt, GRID_SIZE)

	_batch_red.clear()
	_batch_cyan.clear()
	_batch_grey.clear()

	for i in range(PART_COUNT):
		_py[i]    -= _pspeed[i] * dt
		_plife[i] += dt
		if _py[i] < -60.0 or _plife[i] >= _pmaxlife[i]:
			_spawn_particle(i, true)
			continue
		var t := _plife[i] / _pmaxlife[i]
		var a : float
		if   t < 0.15: a = t / 0.15 * 0.75
		elif t > 0.80: a = (1.0 - t) / 0.20 * 0.75
		else:          a = 0.75
		if a < 0.02:
			continue
		var px  := _px[i]
		var py  := _py[i]
		var hsz := _psize[i] * 0.5
		var c   : Color = _pcolor[i]
		# Segmento vertical (estela que sube)
		if c.r > 0.5 and c.g < 0.3:
			_batch_red.append(Vector2(px, py + hsz))
			_batch_red.append(Vector2(px, py - hsz))
		elif c.b > 0.5:
			_batch_cyan.append(Vector2(px, py + hsz))
			_batch_cyan.append(Vector2(px, py - hsz))
		else:
			_batch_grey.append(Vector2(px, py + hsz))
			_batch_grey.append(Vector2(px, py - hsz))

	_sl_lines.clear()
	for i in range(SCAN_COUNT):
		_sl_y[i] += _sl_speed[i] * dt
		if _sl_y[i] > VH:
			_spawn_scanline(i, true)
		_sl_lines.append(Vector2(0.0, _sl_y[i]))
		_sl_lines.append(Vector2(VW,  _sl_y[i]))

	queue_redraw()

func _draw() -> void:
	_draw_grid()
	_draw_vignette()
	#_draw_particles()
	_draw_scanlines()

func _draw_grid() -> void:
	var shifted_v := PackedVector2Array()
	shifted_v.resize(_grid_v_points.size())
	var ox := -_grid_offset_x
	for i in range(0, _grid_v_points.size(), 2):
		shifted_v[i]   = _grid_v_points[i]   + Vector2(ox, 0.0)
		shifted_v[i+1] = _grid_v_points[i+1] + Vector2(ox, 0.0)
	draw_multiline(shifted_v, C_GRID)

	var shifted_h := PackedVector2Array()
	shifted_h.resize(_grid_h_points.size())
	var oy := -_grid_offset_y
	for i in range(0, _grid_h_points.size(), 2):
		shifted_h[i]   = _grid_h_points[i]   + Vector2(0.0, oy)
		shifted_h[i+1] = _grid_h_points[i+1] + Vector2(0.0, oy)
	draw_multiline(shifted_h, C_GRID)

	# Solo diagonales decorativas, sin franjas de borde
	draw_line(Vector2(0.0, VH),       Vector2(VW * 0.6, 0.0), C_DIAG_1)
	draw_line(Vector2(0.0, VH * 0.8), Vector2(VW * 0.8, 0.0), C_DIAG_2)

func _draw_vignette() -> void:
	for i in range(4):
		var base := i * 3
		draw_primitive(
			PackedVector2Array([_vignette_mesh[base], _vignette_mesh[base+1], _vignette_mesh[base+2]]),
			PackedColorArray([_vignette_colors[base], _vignette_colors[base+1], _vignette_colors[base+2]]),
			PackedVector2Array()
		)

func _draw_particles() -> void:
	# width = tamaño visual de la partícula
	if _batch_red.size()  > 0: draw_multiline(_batch_red,  Color(0.900, 0.150, 0.150, 0.80), 3.0)
	if _batch_cyan.size() > 0: draw_multiline(_batch_cyan, Color(0.000, 0.900, 0.940, 0.80), 3.0)
	if _batch_grey.size() > 0: draw_multiline(_batch_grey, Color(0.380, 0.400, 0.520, 0.65), 2.0)

func _draw_scanlines() -> void:
	if _sl_lines.size() > 0:
		draw_multiline(_sl_lines, Color(1.0, 1.0, 1.0, 0.045), 2.0)