## blood_particle_system.gd — ProyectSurvivor (Godot 4)
##
## OPTIMIZACIÓN v2 — MultiMesh rendering
##   ANTES : 1 draw_texture_rect / draw_line por partícula → 200-500 draw calls
##   AHORA : 1 MultiMeshInstance2D para TODAS las partículas → 1 draw call total
##
## CAMBIOS CLAVE:
##   · _draw() eliminado completamente — reemplazado por _update_multimesh()
##   · MAX_PARTICLES reducido de 3000 → 600
##   · Conteos de spawn reducidos ~60 %
##   · Flushing de bakes movido FUERA del while (bug fix del original)
##   · Referencia a chunk_manager cacheada (no más group lookup por frame)
##   · Umbrales LOD ajustados a los nuevos límites
##   · create_blood_splatter: throttle más estricto (MAX_BLOOD_CALLS=2)
##   · create_viscera_explosion: conteos mínimos para evitar spikes en kills masivos

extends Node2D
class_name BloodParticleSystem

# ════════════════════════════════════════════════════════════════════
#  CONSTANTES
# ════════════════════════════════════════════════════════════════════

const TYPE_MIST  : int = 0   # nube de impacto, borde suave
const TYPE_DROP  : int = 1   # gota principal, se bakea al detenerse
const TYPE_CHUNK : int = 2   # víscera sólida, fade-out al morir
const TYPE_DRIP  : int = 3   # goteo de herida, se bakea al detenerse

## Límite absoluto de partículas simultáneas (era 3000)
const MAX_PARTICLES : int = 600

const STOP_VEL_SQ : float = 1.5   # vel² < esto → "detenida" → se bakea

## Máximo de bakes enviados al ChunkManager por frame (lotes al suelo)
const MAX_BAKES_PER_FRAME : int = 8

## Máximo de llamadas a create_blood_splatter por frame (era 4)
const MAX_BLOOD_CALLS_PER_FRAME : int = 2

## Umbrales LOD ajustados al nuevo MAX_PARTICLES
const LOD_CRISIS_THRESHOLD : int = 450  # quality=0 (crisis)
const LOD_MID_THRESHOLD    : int = 250  # quality=1 (medio)

# Paleta de colores
const COL_BLOOD_RED  := Color8(160,  0,  0)
const COL_DARK_BLOOD := Color8( 80,  0,  0)
const COL_BRIGHT_RED := Color8(220, 20, 20)
const COL_GUTS_PINK  := Color8(180, 90,100)
const COL_MIST_RED   := Color(0.65, 0.0, 0.0, 0.55)

# ════════════════════════════════════════════════════════════════════
#  EXPORTS
# ════════════════════════════════════════════════════════════════════

@export var chunk_manager : Node2D
@export_range(0, 2) var quality : int = 2

# ════════════════════════════════════════════════════════════════════
#  ARRAYS DOD  (igual que antes — sin cambios de estructura)
# ════════════════════════════════════════════════════════════════════

var p_pos      := PackedVector2Array()
var p_prev_pos := PackedVector2Array()   # mantenemos por si se necesita en el futuro
var p_vel      := PackedVector2Array()
var p_color    := PackedColorArray()
var p_size     := PackedFloat32Array()
var p_life     := PackedFloat32Array()
var p_max_life := PackedFloat32Array()
var p_frict    := PackedFloat32Array()
var p_type     := PackedByteArray()

var active_count : int = 0

# ════════════════════════════════════════════════════════════════════
#  MULTIMESH  —  reemplaza _draw() completamente
##
##  INSTANCE_COLOR  (use_colors=true):
##    r,g,b = color de la partícula   |   a = alpha ya computado
##
##  INSTANCE_CUSTOM (use_custom_data=true):
##    .r = softness (1.0=niebla/drip suave, 0.0=círculo duro)
##    otros = reservado
##
##  Shader: círculo con borde suave o duro según el tipo.
##  1 draw call para TODOS los tipos de partículas.
# ════════════════════════════════════════════════════════════════════

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

const SHADER_CODE := """
shader_type canvas_item;

varying flat vec4  v_col;
varying flat float v_soft;

void vertex() {
	v_col  = COLOR;
	v_soft = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec2  uv   = UV - vec2(0.5);
	float dist = length(uv) * 2.0;  // 0 en el centro, 1 en el borde

	float edge;
	if (v_soft > 0.5) {
		// Borde gaussiano suave para TYPE_MIST y TYPE_DRIP
		float t = max(0.0, 1.0 - dist);
		edge = t * t * 0.90;
	} else {
		// Borde nítido con antialiasing de 1px para TYPE_DROP y TYPE_CHUNK
		edge = smoothstep(1.06, 0.80, dist);
	}

	if (edge < 0.008) discard;
	COLOR = vec4(v_col.rgb, v_col.a * edge);
}
"""

# ════════════════════════════════════════════════════════════════════
#  ACUMULADORES DE BAKE  (se flushean UNA VEZ al final del frame)
# ════════════════════════════════════════════════════════════════════

var _bake_pos  := PackedVector2Array()
var _bake_col  := PackedColorArray()
var _bake_size := PackedFloat32Array()

var _blood_calls_this_frame : int = 0

# ════════════════════════════════════════════════════════════════════
#  INIT
# ════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("blood_particles")
	_resize_arrays(MAX_PARTICLES)
	_init_multimesh()

func _resize_arrays(n: int) -> void:
	p_pos.resize(n);      p_prev_pos.resize(n)
	p_vel.resize(n);      p_color.resize(n)
	p_size.resize(n);     p_life.resize(n)
	p_max_life.resize(n); p_frict.resize(n)
	p_type.resize(n)

func _init_multimesh() -> void:
	_mm              = MultiMesh.new()
	_mm.mesh         = QuadMesh.new()
	_mm.mesh.size    = Vector2(1.0, 1.0)
	_mm.use_colors        = true
	_mm.use_custom_data   = true
	_mm.instance_count    = MAX_PARTICLES
	_mm.visible_instance_count = 0
	# AABB enorme: desactivamos el frustum culling de Godot (lo hacemos manual)
	_mm.custom_aabb = AABB(Vector3(-100000, -100000, -1),
	                       Vector3( 200000,  200000,  2))

	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code  = SHADER_CODE
	mat.shader   = shader

	_mm_instance           = MultiMeshInstance2D.new()
	_mm_instance.multimesh = _mm
	_mm_instance.material  = mat
	add_child(_mm_instance)

# ════════════════════════════════════════════════════════════════════
#  LOD AUTOMÁTICO
# ════════════════════════════════════════════════════════════════════

func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)

func auto_update_lod() -> void:
	if   active_count >= LOD_CRISIS_THRESHOLD: quality = 0
	elif active_count >= LOD_MID_THRESHOLD:    quality = 1
	else:                                      quality = 2

# ════════════════════════════════════════════════════════════════════
#  PROCESO PRINCIPAL  (_draw() eliminado — usamos MultiMesh)
# ════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_blood_calls_this_frame = 0
	auto_update_lod()

	if active_count == 0:
		_mm.visible_instance_count = 0
		return

	# Limpiar acumuladores de bake del frame anterior
	_bake_pos.clear()
	_bake_col.clear()
	_bake_size.clear()

	var dt := delta * 60.0   # normalizado a 60fps

	# ── Actualizar física de todas las partículas ──────────────────
	# Iteramos HACIA ATRÁS para que swap-back sea correcto al eliminar
	var i := active_count - 1
	while i >= 0:
		p_prev_pos[i] = p_pos[i]

		var vel := p_vel[i]
		vel      *= pow(p_frict[i], dt)
		p_vel[i]  = vel
		p_pos[i] += vel * dt
		p_life[i] -= dt

		var ptype  := int(p_type[i])
		var vel_sq := vel.length_squared()

		# Bakear al suelo si la gota/goteo se detuvo
		if (ptype == TYPE_DROP or ptype == TYPE_DRIP) and vel_sq < STOP_VEL_SQ:
			_bake_pos.append(p_pos[i])
			_bake_col.append(p_color[i])
			_bake_size.append(p_size[i] * 3.5)
			_remove(i)
			i -= 1
			continue

		# Eliminar por tiempo de vida agotado
		if p_life[i] <= 0.0:
			_remove(i)
			i -= 1
			continue

		i -= 1

	# ── Flush de bakes UNA SOLA VEZ por frame (fuera del while) ───
	# BUG FIX del original: el flush estaba DENTRO del while, una vez por iteración
	if chunk_manager and _bake_pos.size() > 0:
		var n := mini(_bake_pos.size(), MAX_BAKES_PER_FRAME)
		chunk_manager.bake_particles_batch(
			_bake_pos.slice(0, n),
			_bake_col.slice(0, n),
			_bake_size.slice(0, n)
		)

	# ── Actualizar MultiMesh (1 draw call en GPU) ──────────────────
	_update_multimesh()

# ════════════════════════════════════════════════════════════════════
#  RENDER — actualiza el MultiMesh con frustum culling manual
# ════════════════════════════════════════════════════════════════════

func _update_multimesh() -> void:
	var player   := get_tree().get_first_node_in_group("player")
	var cam_pos  = player.global_position if is_instance_valid(player) else Vector2.ZERO

	var viewport  := get_viewport()
	var cam       := viewport.get_camera_2d()
	var cam_zoom  := cam.zoom if cam else Vector2.ONE
	var view_size := viewport.get_visible_rect().size / cam_zoom
	var half_x    := view_size.x * 0.5 + 120.0
	var half_y    := view_size.y * 0.5 + 120.0

	var vis := 0

	for idx in range(active_count):
		var pos := p_pos[idx]

		# Frustum culling manual — saltar partículas fuera de pantalla
		if absf(pos.x - cam_pos.x) > half_x or absf(pos.y - cam_pos.y) > half_y:
			continue

		var life_ratio := p_life[idx] / maxf(1.0, p_max_life[idx])
		if life_ratio <= 0.0:
			continue

		var ptype := int(p_type[idx])
		var col   := p_color[idx]

		# Calcular alpha final según el tipo de partícula
		var alpha := col.a
		match ptype:
			TYPE_MIST:
				alpha *= life_ratio
			TYPE_DROP:
				alpha *= minf(1.0, life_ratio * 1.3)
			TYPE_CHUNK:
				if life_ratio < 0.35:
					alpha *= (life_ratio / 0.35)
			TYPE_DRIP:
				alpha *= minf(1.0, life_ratio * 2.0)

		if alpha < 0.02:
			continue

		# Tamaño del quad: 2.4× el radio de la partícula
		var quad_size := p_size[idx] * 2.4
		_mm.set_instance_transform_2d(vis,
			Transform2D(0.0, Vector2(quad_size, quad_size), 0.0, pos))
		_mm.set_instance_color(vis, Color(col.r, col.g, col.b, alpha))

		# Softness flag: TYPE_MIST y TYPE_DRIP usan borde gaussiano
		var is_soft := 1.0 if (ptype == TYPE_MIST or ptype == TYPE_DRIP) else 0.0
		_mm.set_instance_custom_data(vis, Color(is_soft, 0.0, 0.0, 0.0))

		vis += 1

	_mm.visible_instance_count = vis

# ════════════════════════════════════════════════════════════════════
#  SPAWN / REMOVE INTERNO
# ════════════════════════════════════════════════════════════════════

func _spawn(pos: Vector2, vel: Vector2, color: Color,
            size: float, life: float, frict: float, ptype: int) -> void:
	if active_count >= MAX_PARTICLES:
		return
	var i        := active_count
	p_pos[i]      = pos
	p_prev_pos[i] = pos
	p_vel[i]      = vel
	p_color[i]    = color
	p_size[i]     = size
	p_life[i]     = life
	p_max_life[i] = life
	p_frict[i]    = frict
	p_type[i]     = ptype
	active_count += 1

func _remove(i: int) -> void:
	active_count -= 1
	if i == active_count:
		return
	p_pos[i]      = p_pos[active_count]
	p_prev_pos[i] = p_prev_pos[active_count]
	p_vel[i]      = p_vel[active_count]
	p_color[i]    = p_color[active_count]
	p_size[i]     = p_size[active_count]
	p_life[i]     = p_life[active_count]
	p_max_life[i] = p_max_life[active_count]
	p_frict[i]    = p_frict[active_count]
	p_type[i]     = p_type[active_count]

# ════════════════════════════════════════════════════════════════════
#  API PÚBLICA — EFECTOS
# ════════════════════════════════════════════════════════════════════

## ── 1. SALPICADURA DE IMPACTO ────────────────────────────────────
## Llamado al impactar proyectiles. Solo se usa si skip_blood=false
## en damage_enemy(). El aura NO llama esto nunca.
func create_blood_splatter(
	pos:              Vector2,
	direction_vector: Vector2 = Vector2.ZERO,
	force:            float   = 1.5,
	count:            int     = 12,
	damage_ratio:     float   = 0.5
) -> void:
	if _blood_calls_this_frame >= MAX_BLOOD_CALLS_PER_FRAME:
		return
	_blood_calls_this_frame += 1
	if quality == 0 or active_count >= MAX_PARTICLES:
		return

	# Reducir spawn proporcionalmente a la carga actual
	var load_factor  := float(active_count) / float(MAX_PARTICLES)
	var spawn_mult   := clampf(1.0 - load_factor, 0.1, 1.0)
	var intensity    := clampf(damage_ratio, 0.2, 1.0)

	# Conteos reducidos ~60% respecto al original
	var drop_count : int
	var mist_count : int
	match quality:
		2:
			drop_count = int(count * 0.55 * intensity * spawn_mult) + 2
			mist_count = int(count * 0.28 * intensity * spawn_mult) + 1
		1:
			drop_count = int(count * 0.28 * intensity * spawn_mult) + 1
			mist_count = 0
		_:
			return

	var base_angle := direction_vector.angle() if direction_vector != Vector2.ZERO else 0.0
	var has_dir    := direction_vector != Vector2.ZERO

	for _i in range(drop_count):
		var angle := base_angle + randf_range(-0.55, 0.55) if has_dir else randf_range(0.0, TAU)
		var speed := randf_range(3.0, 10.0) * force
		var sz    := randf_range(2.0, 4.5)
		var col   : Color = [COL_BLOOD_RED, COL_BRIGHT_RED, COL_DARK_BLOOD].pick_random()
		col.a = 0.92
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col,
		       sz, randf_range(30.0, 65.0), 0.84, TYPE_DROP)

	for _i in range(mist_count):
		var angle := base_angle + randf_range(-1.2, 1.2) if has_dir else randf_range(0.0, TAU)
		var speed := randf_range(4.0, 14.0 * intensity) * force
		var col   := COL_MIST_RED
		col.a     = randf_range(0.32, 0.62)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col,
		       randf_range(2.0, 4.0), randf_range(6.0, 13.0), 0.75, TYPE_MIST)

## ── 2. GOTEO DE HERIDA ────────────────────────────────────────────
## Solo se llama desde EnemyManager._physics_process con throttle=3/frame.
## El aura NO llama esto (bleed_intensities no se acumula con skip_blood).
func create_blood_drip(pos: Vector2, intensity: float = 1.0) -> void:
	if quality == 0:
		return
	var sz  := clampf(3.0 + intensity * 0.25, 2.5, 9.0)
	var col := COL_DARK_BLOOD if intensity > 10.0 else COL_BLOOD_RED
	col.a   = 0.88
	var angle := randf_range(0.0, TAU)
	_spawn(
		pos + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
		Vector2(cos(angle), sin(angle)) * randf_range(0.0, 0.5),
		col, sz, randf_range(25.0, 50.0), 0.85, TYPE_DRIP
	)

## ── 3. CHARCO DE SANGRE (bake directo al suelo) ───────────────────
func create_blood_pool(pos: Vector2, radius_mult: float = 1.0) -> void:
	if not chunk_manager:
		return
	var blobs := randi_range(3, 6) if quality == 2 else randi_range(1, 2)
	for _i in range(blobs):
		var angle    := randf_range(0.0, TAU)
		var dist     := randf_range(0.0, 15.0 * radius_mult)
		var blob_pos := pos + Vector2(cos(angle), sin(angle)) * dist
		var sz       := randf_range(30.0, 80.0 * radius_mult) if quality == 2 \
		                else randf_range(18.0, 40.0)
		_bake_pos.append(blob_pos)
		_bake_col.append(COL_DARK_BLOOD)
		_bake_size.append(sz)

## ── 4. EXPLOSIÓN DE VÍSCERAS (muerte de enemigo) ─────────────────
## Conteos reducidos agresivamente para evitar spikes de FPS en kills masivos.
## El original generaba 22 mist + 9 chunks + 16 drops = 47 partículas/muerte.
## Ahora: 6 mist + 2 chunks + 4 drops = 12 partículas/muerte (quality=2).
func create_viscera_explosion(pos: Vector2, size_mult: float = 1.0) -> void:
	# Verificar headroom antes de spawnar nada
	if active_count > MAX_PARTICLES - 15:
		if quality > 0:
			create_blood_pool(pos, size_mult)
		return

	var mist_count  : int
	var chunk_count : int
	var drop_count  : int

	match quality:
		2:
			mist_count  = 6
			chunk_count = 2
			drop_count  = 4
		1:
			mist_count  = 2
			chunk_count = 1
			drop_count  = 1
		_:
			mist_count  = 1
			chunk_count = 0
			drop_count  = 0

	if quality > 0:
		create_blood_pool(pos, size_mult)

	# Niebla de sangre
	for _i in range(mist_count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(2.0, 7.0 * size_mult)
		var sz    := randf_range(2.5, 5.0 * size_mult)
		var col   := COL_BLOOD_RED if randf() < 0.5 else COL_BRIGHT_RED
		col.a      = randf_range(0.55, 0.82)
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col,
		       sz, randf_range(14.0, 32.0), 0.89, TYPE_MIST)

	# Trozos de víscera (persisten más tiempo)
	for _i in range(chunk_count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(4.0, 10.0 * size_mult)
		var sz    := randf_range(3.0, 7.0 * size_mult)
		var col   := COL_DARK_BLOOD if randf() < 0.5 else COL_GUTS_PINK
		col.a      = 0.95
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col,
		       sz, randf_range(80.0, 200.0), 0.91, TYPE_CHUNK)

	# Gotas de salpicadura masiva
	for _i in range(drop_count):
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(6.0, 18.0 * size_mult)
		var col   := COL_BLOOD_RED if randf() < 0.7 else COL_DARK_BLOOD
		col.a      = 0.92
		_spawn(pos, Vector2(cos(angle), sin(angle)) * speed, col,
		       randf_range(3.0, 7.0 * size_mult),
		       randf_range(14.0, 32.0), 0.78, TYPE_DROP)

## ── 5. MANCHA DE HERIDA (bake directo al suelo) ───────────────────
## Solo se llama para golpes significativos (amount > 10 o dmg_ratio > 0.3).
## El aura NUNCA llama esto (skip_blood=true en damage_enemy).
func create_wound_stain(pos: Vector2, dmg_ratio: float) -> void:
	if not chunk_manager or dmg_ratio < 0.1:
		return
	var pa := PackedVector2Array([pos])
	var ca := PackedColorArray([COL_DARK_BLOOD])
	var sa := PackedFloat32Array([randf_range(6.0, 14.0) * (0.5 + dmg_ratio)])
	chunk_manager.bake_particles_batch(pa, ca, sa)

# ════════════════════════════════════════════════════════════════════
#  UTILIDADES
# ════════════════════════════════════════════════════════════════════

func get_active_count() -> int:
	return active_count

func clear() -> void:
	active_count = 0
	_bake_pos.clear()
	_bake_col.clear()
	_bake_size.clear()
	_mm.visible_instance_count = 0