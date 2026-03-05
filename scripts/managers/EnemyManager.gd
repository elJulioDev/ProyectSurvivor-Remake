extends Node2D
class_name EnemyManager

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  EnemyManager — Data-Oriented Design + MultiMeshInstance2D
##
##  Reemplaza cientos de nodos Area2D individuales por:
##    · PackedFloat32Array para lógica (acceso caché-friendly)
##    · MultiMeshInstance2D para render (1 draw call GPU total)
##    · Spatial hash propio para queries de balas en O(1)
##    · Un solo _physics_process en lugar de N
##
##  Ganancia esperada: 60+ FPS estable con 1000-2000 enemigos.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

signal enemy_killed(pos: Vector2, points: int)

const MAX_ENEMIES  := 3000
const GRID_CELL    := 160.0   # tamaño de celda del spatial hash (px)
const HP_BAR_RANGE := 400.0   # dibuja barra de vida solo dentro de este radio

# ── Datos de tipo (espejo de Enemy.TYPES) ─────────────────────────
const TYPE_NAMES   := ["small","normal","large","tank","exploder","spitter"]
const TYPE_SIZE_M  := [0.85,  1.0,   1.5,   2.2,   1.4,   1.1 ]
const TYPE_HEALTH  := [40.0,  90.0,  220.0, 700.0, 70.0,  110.0]
const TYPE_SPEED_M := [1.2,   1.0,   0.72,  0.38,  0.75,  0.75 ]
const TYPE_DAMAGE  := [6.0,   12.0,  18.0,  30.0,  0.0,   8.0  ]
const TYPE_POINTS  := [5,     10,    20,    60,    22,    30   ]
const TYPE_COLORS  := [
	Color8(160,240,160), Color8(70,160,70),  Color8(30,100,30),
	Color8(45,65,30),    Color8(255,80,20),  Color8(80,210,50),
]

# ── Arrays empaquetados ────────────────────────────────────────────
var _px      := PackedFloat32Array()   # posición X
var _py      := PackedFloat32Array()   # posición Y
var _vx      := PackedFloat32Array()   # velocidad X
var _vy      := PackedFloat32Array()   # velocidad Y
var _kx      := PackedFloat32Array()   # knockback X
var _ky      := PackedFloat32Array()   # knockback Y
var _hp      := PackedFloat32Array()   # salud actual
var _maxhp   := PackedFloat32Array()   # salud máxima
var _spd     := PackedFloat32Array()   # velocidad real (con varianza)
var _dmg     := PackedFloat32Array()   # daño al jugador por contacto
var _sz      := PackedFloat32Array()   # tamaño sprite (px)
var _lane    := PackedFloat32Array()   # factor de deriva lateral
var _alive   := PackedByteArray()      # 0=muerto 1=vivo
var _type    := PackedByteArray()      # índice en TYPE_* arrays
var _pts     := PackedInt32Array()     # puntos al morir
var _dmg_inv := PackedFloat32Array()   # invulnerabilidad temporal tras daño
var _flash   := PackedFloat32Array()   # Temporizador de destello blanco

var _count   : int = 0   # enemigos activos en este frame

# ── Spatial hash ──────────────────────────────────────────────────
# Reconstruido cada _physics_process; clave = Vector2i de celda
var _grid : Dictionary = {}

# ── MultiMesh ─────────────────────────────────────────────────────
var _mm  : MultiMesh
var _mmi : MultiMeshInstance2D

# ── Referencias cacheadas ─────────────────────────────────────────
var _player    : Node2D = null
var _blood_sys : Node2D = null

# ── LOD automático ────────────────────────────────────────────────
var _lod : int = 2   # 2=completo  1=medio  0=mínimo


# ════════════════════════════════════════════════════════════════
#  INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
	_alloc_arrays()
	_build_multimesh()
	add_to_group("enemy_manager")

func _alloc_arrays() -> void:
	var n := MAX_ENEMIES
	_px.resize(n);    _py.resize(n)
	_vx.resize(n);    _vy.resize(n)
	_kx.resize(n);    _ky.resize(n)
	_hp.resize(n);    _maxhp.resize(n)
	_spd.resize(n);   _dmg.resize(n)
	_sz.resize(n);    _lane.resize(n)
	_alive.resize(n); _type.resize(n)
	_pts.resize(n);   _dmg_inv.resize(n)
	_alive.fill(0)
	_dmg_inv.fill(0)
	_flash.fill(0)
	_flash.resize(n)

func _build_multimesh() -> void:
	# Quad 1×1 blanco — escalamos vía Transform2D por instancia
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors       = true
	_mm.instance_count   = MAX_ENEMIES
	_mm.mesh             = mesh

	# Ocultar todas las instancias fuera de pantalla
	var off := Transform2D(0.0, Vector2(-999999.0, -999999.0))
	for i in range(MAX_ENEMIES):
		_mm.set_instance_transform_2d(i, off)
		_mm.set_instance_color(i, Color.TRANSPARENT)

	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = _mm

	# Textura blanca 1×1 para que el color de instancia se aplique correctamente
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_mmi.texture = ImageTexture.create_from_image(img)

	# --- NUEVO CÓDIGO: SHADER PARA RECUPERAR EL ESTILO VISUAL ---
	var mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
	shader_type canvas_item;
	void fragment() {
		vec4 base_color = COLOR;
		
		// Calcular borde (aprox 8% del tamaño del sprite)
		float b = 0.08;
		bool is_border = (UV.x < b || UV.x > 1.0 - b || UV.y < b || UV.y > 1.0 - b);
		
		// Calcular centro oscuro (1/3 del tamaño)
		bool is_center = (abs(UV.x - 0.5) < 0.166 && abs(UV.y - 0.5) < 0.166);

		if (is_border || is_center) {
			// Oscurecer el color base para simular el borde y el centro
			COLOR = vec4(base_color.rgb * 0.7, base_color.a);
		}
	}
	"""
	_mmi.material = mat
	# -----------------------------------------------------------

	add_child(_mmi)

# ════════════════════════════════════════════════════════════════
#  API PÚBLICA
# ════════════════════════════════════════════════════════════════

## Genera un enemigo en el pool. Devuelve índice (o -1 si lleno).
func spawn(pos: Vector2, type_name: String,
		   speed_mult: float, health_mult: float, damage_mult: float) -> int:
	if _count >= MAX_ENEMIES:
		return -1
	var idx := _find_slot()
	if idx < 0:
		return -1

	var ti := TYPE_NAMES.find(type_name)
	if ti < 0: ti = 1

	_px[idx]    = pos.x;  _py[idx]    = pos.y
	_vx[idx]    = 0.0;    _vy[idx]    = 0.0
	_kx[idx]    = 0.0;    _ky[idx]    = 0.0
	var mh      : float = TYPE_HEALTH[ti] * health_mult
	_hp[idx]    = mh;     _maxhp[idx] = mh
	var spd     : float = GameManager.ENEMY_SPEED * speed_mult * TYPE_SPEED_M[ti]
	_spd[idx]   = spd * randf_range(0.9, 1.1)
	_dmg[idx]   = maxf(1.0, TYPE_DAMAGE[ti] * damage_mult)
	_sz[idx]    = GameManager.ENEMY_SIZE * TYPE_SIZE_M[ti]
	_lane[idx]  = sin(pos.x * 0.0071 + pos.y * 0.0053)
	_alive[idx] = 1;      _type[idx]  = ti
	_pts[idx]   = TYPE_POINTS[ti]
	_dmg_inv[idx] = 0.0
	_count += 1
	return idx

## Aplica daño a un enemigo. Devuelve true si muere.
func take_damage(idx: int, amount: float,
				 hit_dir: Vector2 = Vector2.ZERO) -> bool:
	if idx < 0 or _alive[idx] == 0:
		return false
	if _dmg_inv[idx] > 0.0:
		return false

	_hp[idx] -= amount
	_flash[idx] = 0.166

	# Kickback proporcional al tipo
	if hit_dir != Vector2.ZERO:
		var sf := 1.0 / maxf(TYPE_SIZE_M[_type[idx]], 0.01)
		_kx[idx] += hit_dir.x * 6.0 * sf
		_ky[idx] += hit_dir.y * 6.0 * sf

	if _hp[idx] <= 0.0:
		_kill(idx)
		return true
	return false

## Aplica knockback desde una posición fuente.
func apply_knockback_to(idx: int, src: Vector2, force: float) -> void:
	if idx < 0 or _alive[idx] == 0:
		return
	var dx  := _px[idx] - src.x
	var dy  := _py[idx] - src.y
	var dist := maxf(sqrt(dx * dx + dy * dy), 0.01)
	var sf  := 1.0 / maxf(TYPE_SIZE_M[_type[idx]], 0.01)
	_kx[idx] += (dx / dist) * force * sf
	_ky[idx] += (dy / dist) * force * sf

## Posición de un enemigo por índice.
func get_pos(idx: int) -> Vector2:
	return Vector2(_px[idx], _py[idx])

## Daño de contacto de un enemigo.
func get_damage(idx: int) -> float:
	return _dmg[idx]

## Devuelve proxies de enemigos dentro de `radius` de `pos`.
## Los proxies exponen .take_damage() y .apply_knockback()
## para compatibilidad total con el código de armas existente.
func get_enemies_near_proxy(pos: Vector2, radius: float) -> Array:
	var indices : Array = []
	_query_radius(pos, radius, indices)
	var proxies : Array = []
	proxies.resize(indices.size())
	for i in range(indices.size()):
		var p        := EnemyProxy.new()
		p._mgr       = self
		p.idx        = indices[i]
		p.global_position = Vector2(_px[indices[i]], _py[indices[i]])
		proxies[i]   = p
	return proxies

## Índice del enemigo más cercano a `pos` dentro de `max_r` (o -1).
func get_nearest_idx(pos: Vector2, max_r: float = 900.0) -> int:
	var best_sq  := max_r * max_r
	var best_idx := -1
	var indices  : Array = []
	_query_radius(pos, max_r, indices)
	for i in indices:
		var dx := _px[i] - pos.x
		var dy := _py[i] - pos.y
		var sq := dx * dx + dy * dy
		if sq < best_sq:
			best_sq  = sq
			best_idx = i
	return best_idx

func get_active_count() -> int:
	return _count

# ════════════════════════════════════════════════════════════════
#  PROCESO PRINCIPAL
# ════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	# Cachear referencias una vez
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return
	if not is_instance_valid(_blood_sys):
		_blood_sys = get_tree().get_first_node_in_group("blood_particles")

	# Auto-LOD basado en número de enemigos activos
	if   _count >= 1500: _lod = 0
	elif _count >= 700:  _lod = 1
	else:                _lod = 2

	_run_logic(delta)
	_update_multimesh()

func _run_logic(delta: float) -> void:
	var dt := delta * 60.0
	var px := _player.global_position.x
	var py := _player.global_position.y

	# Reconstruir spatial hash cada frame
	_grid.clear()

	for i in range(MAX_ENEMIES):
		if _alive[i] == 0:
			continue

		# ── Dirección al jugador ─────────────────────────────
		var cx  := _px[i];  var cy := _py[i]
		var dx  := px - cx; var dy := py - cy
		var dist := sqrt(dx * dx + dy * dy)
		if dist > 0.001:
			dx /= dist; dy /= dist

		# ── Velocidad con deriva de carril ───────────────────
		var spd    := _spd[i]
		var lane   := _lane[i]
		var tvx    := dx * spd + (-dy * lane * 0.38 * spd)
		var tvy    := dy * spd + ( dx * lane * 0.38 * spd)
		_vx[i]    += (tvx - _vx[i]) * 0.4
		_vy[i]    += (tvy - _vy[i]) * 0.4

		# ── Knockback decay ──────────────────────────────────
		if _kx[i] != 0.0 or _ky[i] != 0.0:
			var decay := pow(0.88, dt)
			_kx[i] *= decay; _ky[i] *= decay
			if abs(_kx[i]) < 0.1 and abs(_ky[i]) < 0.1:
				_kx[i] = 0.0; _ky[i] = 0.0

		# ── Invulnerabilidad temporal ────────────────────────
		if _dmg_inv[i] > 0.0:
			_dmg_inv[i] = maxf(0.0, _dmg_inv[i] - delta)
			
		# ── Destello de impacto ──────────────────────────────
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta)

		# ── Mover ────────────────────────────────────────────
		_px[i] = cx + (_vx[i] + _kx[i]) * delta
		_py[i] = cy + (_vy[i] + _ky[i]) * delta

		# ── Insertar en spatial hash ─────────────────────────
		var gx := int(floor(_px[i] / GRID_CELL))
		var gy := int(floor(_py[i] / GRID_CELL))
		var k  := Vector2i(gx, gy)
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(i)

	# ── Separación (previene el apilamiento) ─────────────────
	if _lod >= 1:
		_separation_pass()

	# ── Daño al jugador por contacto ─────────────────────────
	_check_player_damage()

func _separation_pass() -> void:
	# Solo se procesa dentro de un radio del jugador para ahorrar CPU
	var px       := _player.global_position.x
	var py       := _player.global_position.y
	var max_d_sq := 800.0 * 800.0
	var iters    := 1 if _lod == 1 else 2   # menos iteraciones en LOD medio

	for _iter in range(iters):
		for k in _grid.keys():
			var indices : Array = _grid[k]
			if indices.size() < 2:
				continue
			var n := indices.size()
			for ii in range(n):
				var i : int = indices[ii]
				if _alive[i] == 0:
					continue
				# Omitir si está lejos del jugador
				var dpx := _px[i] - px; var dpy := _py[i] - py
				if dpx * dpx + dpy * dpy > max_d_sq:
					continue
				for jj in range(ii + 1, n):
					var j : int = indices[jj]
					if _alive[j] == 0:
						continue
					var sx    := _px[i] - _px[j]
					var sy    := _py[i] - _py[j]
					var min_d := (_sz[i] + _sz[j]) * 0.45
					var dsq   := sx * sx + sy * sy
					if dsq < min_d * min_d and dsq > 0.0001:
						var d     := sqrt(dsq)
						var push  := (min_d - d) * 0.35 / d
						_px[i]   += sx * push; _py[i] += sy * push
						_px[j]   -= sx * push; _py[j] -= sy * push

func _check_player_damage() -> void:
	if not is_instance_valid(_player):
		return
	if not _player.has_method("take_damage"):
		return

	var px := _player.global_position.x
	var py := _player.global_position.y
	var gx := int(floor(px / GRID_CELL))
	var gy := int(floor(py / GRID_CELL))

	for ddx in range(-1, 2):
		for ddy in range(-1, 2):
			var k := Vector2i(gx + ddx, gy + ddy)
			if not _grid.has(k):
				continue
			for i in _grid[k]:
				if _alive[i] == 0:
					continue
				var dx := _px[i] - px
				var dy := _py[i] - py
				# Radio de colisión: mitad del sprite + 10px de hitbox del jugador
				var r  := (_sz[i] * 0.5) + 10.0
				if dx * dx + dy * dy < r * r:
					_player.take_damage(_dmg[i])
					return   # solo 1 golpe por frame


# ════════════════════════════════════════════════════════════════
#  RENDER — MultiMesh + barras de vida en _draw
# ════════════════════════════════════════════════════════════════

func _update_multimesh() -> void:
	var cam := get_viewport().get_camera_2d()
	var cam_cx := _player.global_position.x
	var cam_cy := _player.global_position.y
	if is_instance_valid(cam):
		var csp := cam.get_screen_center_position()
		cam_cx = csp.x; cam_cy = csp.y

	var vp     := get_viewport_rect().size
	var half_x := vp.x * 0.75
	var half_y := vp.y * 0.75
	var off    := Transform2D(0.0, Vector2(-999999.0, -999999.0))

	for i in range(MAX_ENEMIES):
		if _alive[i] == 0:
			_mm.set_instance_transform_2d(i, off)
			_mm.set_instance_color(i, Color.TRANSPARENT)
			continue

		var ex := _px[i]; var ey := _py[i]

		# Frustum cull — off-screen no ocupa draw calls
		if abs(ex - cam_cx) > half_x or abs(ey - cam_cy) > half_y:
			_mm.set_instance_transform_2d(i, off)
			_mm.set_instance_color(i, Color.TRANSPARENT)
			continue

		# Transform2D escalada al tamaño del enemigo
		var sz := _sz[i]
		_mm.set_instance_transform_2d(i,
			Transform2D(Vector2(sz, 0.0), Vector2(0.0, sz), Vector2(ex, ey)))

		# Color base del tipo
		var ti     := _type[i]
		var col    : Color = TYPE_COLORS[ti]
			
		# --- Aplicar el destello blanco de impacto ---
		if _flash[i] > 0.0:
			var flash_pct := _flash[i] / 0.166
			# Mezcla hacia color blanco puro dependiendo del tiempo restante
			col = col.lerp(Color.WHITE, flash_pct * 0.95)

		_mm.set_instance_color(i, col)

	queue_redraw()

func _draw() -> void:
	# Barras de vida solo para enemigos cerca del jugador (LOD visual)
	if not is_instance_valid(_player):
		return

	var px    := _player.global_position.x
	var py    := _player.global_position.y
	var r_sq  := HP_BAR_RANGE * HP_BAR_RANGE

	for i in range(MAX_ENEMIES):
		if _alive[i] == 0:
			continue
		if _hp[i] >= _maxhp[i]:
			continue   # llena → no dibujar

		var ex := _px[i]; var ey := _py[i]
		var dx := ex - px; var dy := ey - py
		if dx * dx + dy * dy > r_sq:
			continue

		var sz    := _sz[i]
		var bar_w := sz
		var bar_h := 4.0
		var bx    := ex - bar_w * 0.5
		var by_   := ey - sz * 0.5 - 7.0
		var hppct := _hp[i] / maxf(_maxhp[i], 1.0)

		draw_rect(Rect2(bx, by_, bar_w, bar_h), Color(0.15, 0.0, 0.0))
		var hp_col := Color(1.0, 0.35, 0.0) if hppct > 0.3 else Color(0.9, 0.1, 0.1)
		draw_rect(Rect2(bx, by_, bar_w * hppct, bar_h), hp_col)


# ════════════════════════════════════════════════════════════════
#  INTERNAL HELPERS
# ════════════════════════════════════════════════════════════════

func _find_slot() -> int:
	for i in range(MAX_ENEMIES):
		if _alive[i] == 0:
			return i
	return -1

func _kill(idx: int) -> void:
	_alive[idx] = 0
	_count      -= 1
	var pos  := Vector2(_px[idx], _py[idx])
	var ti   := _type[idx]

	# Efecto de muerte (sangre)
	if is_instance_valid(_blood_sys):
		_blood_sys.create_viscera_explosion(pos, TYPE_SIZE_M[ti])

	# Notificar a gameplay (XP, score, etc.)
	emit_signal("enemy_killed", pos, _pts[idx])

## Consulta rápida por radio usando el spatial hash.
func _query_radius(pos: Vector2, radius: float, out: Array) -> void:
	var cell_r := int(ceil(radius / GRID_CELL)) + 1
	var gx     := int(floor(pos.x / GRID_CELL))
	var gy     := int(floor(pos.y / GRID_CELL))
	var r_sq   := radius * radius
	for ddx in range(-cell_r, cell_r + 1):
		for ddy in range(-cell_r, cell_r + 1):
			var k := Vector2i(gx + ddx, gy + ddy)
			if not _grid.has(k):
				continue
			for i in _grid[k]:
				if _alive[i] == 0:
					continue
				var dx := _px[i] - pos.x
				var dy := _py[i] - pos.y
				if dx * dx + dy * dy <= r_sq:
					out.append(i)


# ════════════════════════════════════════════════════════════════
#  EnemyProxy — compatibilidad con código de armas existente
#
#  Permite que las armas sigan usando:
#      enemy.take_damage(dmg, dir)
#      enemy.apply_knockback(pos, force)
#  sin ningún cambio adicional.
# ════════════════════════════════════════════════════════════════

class EnemyProxy:
	var _mgr             : Node
	var idx              : int
	var global_position  : Vector2

	func take_damage(amount: float,
					 hit_dir: Vector2 = Vector2.ZERO) -> bool:
		return _mgr.take_damage(idx, amount, hit_dir)

	func apply_knockback(source_pos: Vector2, force: float) -> void:
		_mgr.apply_knockback_to(idx, source_pos, force)

	func _has_method(m: StringName) -> bool:
		return m == "take_damage" or m == "apply_knockback"