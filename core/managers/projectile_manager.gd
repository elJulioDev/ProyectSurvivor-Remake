extends Node2D
class_name ProjectileManager

## ════════════════════════════════════════════════════════════════════════════
##  ProjectileManager — DOD + MultiMesh  (ProyectSurvivor)
##
##  Reemplaza los nodos Node2D individuales (proyectile.tscn) por arrays
##  paralelos renderizados en un único MultiMeshInstance2D → 1 draw call
##  independientemente de la cantidad de proyectiles en pantalla.
##
##  ARQUITECTURA:
##    · Todos los datos viven en PackedArrays paralelos (cero nodos hijos).
##    · Un único MultiMeshInstance2D con shader personalizado renderiza TODO.
##    · La física (movimiento, colisión, swept) corre en _physics_process.
##    · Frustum culling manual: solo se envían a GPU los proyectiles visibles.
##    · Swap-back O(1) para eliminar proyectiles sin desplazar el array.
##
##  INTEGRACIÓN:
##    · gameplay.gd  → GameManager.projectile_manager = $ProjectileManager
##    · weapon_controller.gd → GameManager.projectile_manager.spawn(...)
##
##  INSTANCE_COLOR (use_colors=true):
##    r,g,b = color principal del proyectil | a = alpha (fade-out)
##
##  INSTANCE_CUSTOM (use_custom_data=true):
##    .r = inner_mult   (0.0 = sin círculo interior, >0 = radio del núcleo)
##    .g = flicker_rand (valor aleatorio 0-1, actualizado cada frame)
##    .b = is_flicker   (1.0 si el arma tiene efecto de llama/chispa)
##    .a = reservado
## ════════════════════════════════════════════════════════════════════════════

const MAX_PROJECTILES := 1500

## quad_side = radius * QUAD_MULT.
## Con QUAD_MULT=2.5 → outer_r en UV = 1/(2.5*0.5) = 0.40 (ver shader).
const QUAD_MULT := 2.5

# ════════════════════════════════════════════════════════════════════════════
#  1. ARRAYS DOD
# ════════════════════════════════════════════════════════════════════════════

var active_count := 0

var positions      := PackedVector2Array()
var prev_positions := PackedVector2Array()   # para swept collision (francotirador)
var velocities     := PackedVector2Array()
var damages        := PackedInt32Array()
var penetrations   := PackedInt32Array()     # penetraciones restantes
var lifetimes      := PackedFloat32Array()   # en frames (@ 60 fps)
var max_lifetimes  := PackedFloat32Array()   # en frames
var radii          := PackedFloat32Array()   # radio de colisión / render
var kb_mults       := PackedFloat32Array()   # multiplicador de knockback
var inner_mults    := PackedFloat32Array()   # radio del núcleo interior (0 = ninguno)
var col_r          := PackedFloat32Array()
var col_g          := PackedFloat32Array()
var col_b          := PackedFloat32Array()
var use_swept      := PackedByteArray()      # 1 = swept collision (sniper)
var fade_out       := PackedByteArray()      # 1 = fade progresivo
var fade_mults     := PackedFloat32Array()   # multiplicador del fade
var flicker_flags  := PackedByteArray()      # 1 = efecto llama (escopeta)

## Un Dictionary por proyectil para registrar los enemigos ya impactados.
## No puede ser PackedArray porque el tamaño varía por proyectil.
## Se pre-asignan MAX_PROJECTILES diccionarios al inicio y se reutilizan.
var hit_sets: Array = []

# ════════════════════════════════════════════════════════════════════════════
#  2. MULTIMESH + SHADER
# ════════════════════════════════════════════════════════════════════════════

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

## Dos círculos concéntricos (cuerpo + núcleo brillante) con suavizado de borde.
## Soporta efecto flicker (armas de fuego) y fade-out progresivo.
const SHADER_CODE := """
shader_type canvas_item;

// v_col: COLOR de la instancia (r,g,b = color base, a = alpha)
// v_cd:  INSTANCE_CUSTOM       (r = inner_mult, g = flicker_rand, b = is_flicker)
varying flat vec4 v_col;
varying flat vec4 v_cd;

void vertex() {
    v_col = COLOR;
    v_cd  = INSTANCE_CUSTOM;
}

void fragment() {
    vec2  uv  = UV - vec2(0.5);
    float dst = length(uv);

    // OUTER_UV = radius / (radius * QUAD_MULT * 0.5)
    // Con QUAD_MULT=2.5: outer = 1.0 / (2.5 * 0.5) = 0.40
    const float OUTER = 0.40;

    // Descartar pixels fuera del círculo principal (+ margen para smoothstep)
    if (dst > OUTER + 0.04) discard;

    vec3  col  = v_col.rgb;
    float alph = v_col.a;

    // ── Efecto flicker (escopeta / armas de llama) ────────────────────
    // Sobreescribe el color base con tonos naranja-fuego aleatorios.
    if (v_cd.b > 0.5) {
        float t = v_cd.g;
        col  = vec3(1.0, mix(0.30, 0.65, t), 0.0);
        alph = mix(0.70, 1.00, t) * v_col.a;
    }

    // ── Círculo interior (núcleo brillante) ───────────────────────────
    // inner_mult > 0 → pinta un núcleo blanco-brillante en el centro.
    float im = v_cd.r;
    if (im > 0.01 && dst <= OUTER * im) {
        col = mix(col, vec3(1.0, 1.0, 0.95), 0.70);
    }

    // ── Suavizado de borde (antialiasing 1-2px) ───────────────────────
    float edge = smoothstep(OUTER + 0.02, OUTER - 0.04, dst);

    COLOR = vec4(col, alph * edge);
}
"""

# ════════════════════════════════════════════════════════════════════════════
#  3. INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("projectile_manager")
	_init_arrays()
	_init_multimesh()

func _init_arrays() -> void:
	positions.resize(MAX_PROJECTILES)
	prev_positions.resize(MAX_PROJECTILES)
	velocities.resize(MAX_PROJECTILES)
	damages.resize(MAX_PROJECTILES)
	penetrations.resize(MAX_PROJECTILES)
	lifetimes.resize(MAX_PROJECTILES)
	max_lifetimes.resize(MAX_PROJECTILES)
	radii.resize(MAX_PROJECTILES)
	kb_mults.resize(MAX_PROJECTILES)
	inner_mults.resize(MAX_PROJECTILES)
	col_r.resize(MAX_PROJECTILES)
	col_g.resize(MAX_PROJECTILES)
	col_b.resize(MAX_PROJECTILES)
	use_swept.resize(MAX_PROJECTILES)
	fade_out.resize(MAX_PROJECTILES)
	fade_mults.resize(MAX_PROJECTILES)
	flicker_flags.resize(MAX_PROJECTILES)

	# Pre-asignar diccionarios para hit_sets — se reutilizan con .clear()
	hit_sets.resize(MAX_PROJECTILES)
	for i in range(MAX_PROJECTILES):
		hit_sets[i] = {}

func _init_multimesh() -> void:
	_mm                        = MultiMesh.new()
	_mm.mesh                   = QuadMesh.new()
	_mm.mesh.size              = Vector2(1.0, 1.0)
	_mm.use_colors             = true          # INSTANCE_COLOR por instancia
	_mm.use_custom_data        = true          # INSTANCE_CUSTOM por instancia
	_mm.instance_count         = MAX_PROJECTILES
	_mm.visible_instance_count = 0
	# AABB enorme para que el culling de Godot nunca corte el MultiMesh completo
	_mm.custom_aabb            = AABB(Vector3(-100000, -100000, -1),
	                                  Vector3(200000,  200000,   2))

	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code  = SHADER_CODE
	mat.shader   = shader

	_mm_instance           = MultiMeshInstance2D.new()
	_mm_instance.multimesh = _mm
	_mm_instance.material  = mat
	add_child(_mm_instance)

# ════════════════════════════════════════════════════════════════════════════
#  4. SPAWN
# ════════════════════════════════════════════════════════════════════════════

## Crea un nuevo proyectil en el buffer DOD.
## Llamar desde WeaponController en lugar de instanciar proyectile.tscn.
##
## @param vel         Velocidad en px/s (ya multiplicada por 60 como en el original).
## @param max_lt      Vida máxima EN FRAMES (@ 60fps), igual que WeaponData.max_lifetime.
## @param inner_mult  0 = sin núcleo; 0.5 = núcleo al 50% del radio exterior.
## @param p_fade_out  Si true, el proyectil se desvanece según fade_mult y lifetime.
## @param p_flicker   Si true, el shader aplica efecto llama naranja.
func spawn(
	pos         : Vector2,
	vel         : Vector2,
	damage      : int,
	penetration : int,
	max_lt      : float,
	radius      : float,
	knockback   : float,
	inner_mult  : float,
	color       : Color,
	p_use_swept : bool,
	p_fade_out  : bool,
	fade_mult   : float,
	p_flicker   : bool
) -> void:
	if active_count >= MAX_PROJECTILES:
		return

	var i               := active_count
	positions[i]        = pos
	prev_positions[i]   = pos
	velocities[i]       = vel
	damages[i]          = damage
	penetrations[i]     = penetration
	lifetimes[i]        = 0.0
	max_lifetimes[i]    = max_lt
	radii[i]            = radius
	kb_mults[i]         = knockback
	inner_mults[i]      = inner_mult
	col_r[i]            = color.r
	col_g[i]            = color.g
	col_b[i]            = color.b
	use_swept[i]        = 1 if p_use_swept else 0
	fade_out[i]         = 1 if p_fade_out  else 0
	fade_mults[i]       = fade_mult
	flicker_flags[i]    = 1 if p_flicker   else 0
	hit_sets[i].clear()

	active_count += 1

# ════════════════════════════════════════════════════════════════════════════
#  5. FÍSICA — movimiento y colisiones
# ════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if active_count == 0:
		_mm.visible_instance_count = 0
		return
	if not is_instance_valid(GameManager.enemy_manager):
		return

	var dt60 := delta * 60.0
	var i    := 0

	while i < active_count:
		# Guardar posición anterior (necesaria para swept collision del sniper)
		prev_positions[i] = positions[i]
		positions[i]     += velocities[i] * delta
		lifetimes[i]     += dt60

		# Muerte por agotamiento de vida
		if lifetimes[i] >= max_lifetimes[i]:
			_remove(i)
			continue

		# Detección de colisión (devuelve true si el proyectil debe destruirse)
		var killed := false
		if use_swept[i]:
			killed = _check_swept(i)
		else:
			killed = _check_normal(i)

		if killed:
			_remove(i)
			continue

		i += 1

	_render()

## Colisión estándar por proximidad (pistola, escopeta, rifle, etc.)
func _check_normal(idx: int) -> bool:
	var pos  := positions[idx]
	var hits = GameManager.enemy_manager.get_enemies_near_proxy(pos, radii[idx] + 16.0)
	var vn   := velocities[idx].normalized()

	for eidx in hits:
		if hit_sets[idx].has(eidx):
			continue
		hit_sets[idx][eidx] = true
		GameManager.enemy_manager.damage_enemy(
			eidx, float(damages[idx]), vn, 8.0 * kb_mults[idx])
		penetrations[idx] -= 1
		if penetrations[idx] <= 0:
			return true   # sin más penetraciones: destruir proyectil

	return false

## Colisión swept (segmento entre pos anterior y actual) para el francotirador.
## Garantiza que proyectiles rápidos no atraviesen enemigos entre frames.
func _check_swept(idx: int) -> bool:
	var pa    := prev_positions[idx]
	var pb    := positions[idx]
	var mid   := (pa + pb) * 0.5
	var seg_r := pb.distance_to(pa) * 0.5 + radii[idx] + 14.0
	var hits  = GameManager.enemy_manager.get_enemies_near_proxy(mid, seg_r)
	var vn    := velocities[idx].normalized()
	var hr    := radii[idx] + 14.0

	for eidx in hits:
		if hit_sets[idx].has(eidx):
			continue
		var epos = GameManager.enemy_manager.positions[eidx]
		if _point_seg_dist(epos, pa, pb) <= hr:
			hit_sets[idx][eidx] = true
			GameManager.enemy_manager.damage_enemy(
				eidx, float(damages[idx]), vn, 12.0 * kb_mults[idx])
			penetrations[idx] -= 1
			if penetrations[idx] <= 0:
				return true

	return false

## Distancia mínima de un punto a un segmento AB.
func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab  : Vector2 = b - a
	var lsq : float   = ab.length_squared()
	if lsq == 0.0:
		return p.distance_to(a)
	var t : float = clampf((p - a).dot(ab) / lsq, 0.0, 1.0)
	return p.distance_to(a + t * ab)

# ════════════════════════════════════════════════════════════════════════════
#  6. RENDER — frustum culling + actualización del MultiMesh
# ════════════════════════════════════════════════════════════════════════════

func _render() -> void:
	var player    := get_tree().get_first_node_in_group("player")
	var p_pos     = player.global_position if is_instance_valid(player) else Vector2.ZERO

	var viewport  := get_viewport()
	var cam       := viewport.get_camera_2d()
	var cam_zoom  := cam.zoom if cam else Vector2.ONE
	var view_size := viewport.get_visible_rect().size / cam_zoom
	var half_x    := view_size.x * 0.5 + 150.0
	var half_y    := view_size.y * 0.5 + 150.0

	var vis := 0

	for i in range(active_count):
		var pos := positions[i]

		# Frustum culling: saltar proyectiles fuera del área visible
		if absf(pos.x - p_pos.x) > half_x or absf(pos.y - p_pos.y) > half_y:
			continue

		# Transformación: posición + escala uniforme según radio
		var qs : float = radii[i] * QUAD_MULT
		_mm.set_instance_transform_2d(vis,
			Transform2D(0.0, Vector2(qs, qs), 0.0, pos))

		# Alpha: 1.0 por defecto, desvanecido si fade_out=true
		var alpha := 1.0
		if fade_out[i]:
			var progress := 1.0 - (lifetimes[i] / maxf(1.0, max_lifetimes[i]))
			alpha = clampf(progress * fade_mults[i], 0.0, 1.0)

		# Color de instancia: r,g,b = color del arma, a = alpha
		_mm.set_instance_color(vis, Color(col_r[i], col_g[i], col_b[i], alpha))

		# Datos personalizados: inner_mult, flicker (aleatorio por frame), flag
		_mm.set_instance_custom_data(vis, Color(
			inner_mults[i],
			randf() if flicker_flags[i] else 0.0,
			float(flicker_flags[i]),
			0.0
		))

		vis += 1

	_mm.visible_instance_count = vis

# ════════════════════════════════════════════════════════════════════════════
#  7. UTILIDADES INTERNAS
# ════════════════════════════════════════════════════════════════════════════

## Elimina el proyectil en idx usando swap-back O(1).
## El proyectil del final del buffer se mueve a idx, sin desplazar el resto.
func _remove(idx: int) -> void:
	active_count -= 1

	if idx == active_count:
		# Era el último: solo limpiar hit_set
		hit_sets[idx].clear()
		return

	# Mover datos del último al slot liberado
	positions[idx]      = positions[active_count]
	prev_positions[idx] = prev_positions[active_count]
	velocities[idx]     = velocities[active_count]
	damages[idx]        = damages[active_count]
	penetrations[idx]   = penetrations[active_count]
	lifetimes[idx]      = lifetimes[active_count]
	max_lifetimes[idx]  = max_lifetimes[active_count]
	radii[idx]          = radii[active_count]
	kb_mults[idx]       = kb_mults[active_count]
	inner_mults[idx]    = inner_mults[active_count]
	col_r[idx]          = col_r[active_count]
	col_g[idx]          = col_g[active_count]
	col_b[idx]          = col_b[active_count]
	use_swept[idx]      = use_swept[active_count]
	fade_out[idx]       = fade_out[active_count]
	fade_mults[idx]     = fade_mults[active_count]
	flicker_flags[idx]  = flicker_flags[active_count]

	# Intercambiar hit_sets por referencia (O(1), sin copiar contenidos)
	var recycled        = hit_sets[idx]
	hit_sets[idx]        = hit_sets[active_count]
	hit_sets[active_count] = recycled
	recycled.clear()   # limpiar el que queda al final para reutilización futura

# ════════════════════════════════════════════════════════════════════════════
#  8. API PÚBLICA
# ════════════════════════════════════════════════════════════════════════════

## Número de proyectiles activos (para debug_panel).
func get_active_count() -> int:
	return active_count

## Vacía todos los proyectiles (útil al limpiar la escena).
func clear() -> void:
	active_count = 0
	for i in range(MAX_PROJECTILES):
		hit_sets[i].clear()
	_mm.visible_instance_count = 0