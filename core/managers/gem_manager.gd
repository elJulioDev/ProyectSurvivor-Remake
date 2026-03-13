extends Node2D
class_name GemManager

## ════════════════════════════════════════════════════════════════════════════
##  GemManager v2 — DOD + MultiMesh  (ProyectSurvivor)
##
##  ARQUITECTURA:
##    · Todos los datos viven en PackedArrays paralelos (cero nodos hijos).
##    · Un único MultiMeshInstance2D renderiza TODAS las gemas en 1 draw call.
##    · Shader personalizado dibuja el diamante con halo, núcleo y efecto
##      de streak al ser atraída — visualmente idéntico al ExperienceGem
##      original pero sin coste de nodos.
##    · La física (scatter, imán, recolección) corre en _physics_process.
##    · El merge periódico compacta gemas solapadas para limitar el conteo.
##
##  INTEGRACIÓN CON gameplay.gd:
##    · Llama a  gem_manager.spawn_gem(pos, xp)  en lugar de instanciar
##      PackedScene.  El resto de la API pública (get_gem_count, attract_all)
##      no cambia.
##    · La señal ya no existe; la gema llama directamente a
##      player.gain_experience(xp) igual que EnemyManager llama a
##      player.take_damage().
## ════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════
#  1. CONSTANTES
# ════════════════════════════════════════════════════════════════════════════

## Límite absoluto de gemas simultáneas
const MAX_GEMS          : int   = 2000

## Física de atracción / scatter
const COLLECT_RADIUS    : float = 20.0
const COLLECT_RADIUS_SQ : float = COLLECT_RADIUS * COLLECT_RADIUS
const MAGNET_BASE       : float = 140.0
const ATTRACT_ACCEL     : float = 700.0
const MAX_ATTRACT_SPD   : float = 480.0
const SCATTER_FRICTION  : float = 0.88   # por frame @ 60 fps
const SCATTER_TIME      : float = 0.25   # segundos de vuelo inicial

## Merge
const MERGE_INTERVAL    : float = 2.0
const MERGE_THRESHOLD   : int   = 35     # mínimo de gemas para ejecutar merge
const MERGE_RADIUS      : float = 22.0
const MERGE_RADIUS_SQ   : float = MERGE_RADIUS * MERGE_RADIUS
const HARD_CAP          : int   = 200    # radio ×2 si se supera este límite

# ════════════════════════════════════════════════════════════════════════════
#  2. ARRAYS DOD
# ════════════════════════════════════════════════════════════════════════════

var active_count : int = 0

var positions      := PackedVector2Array()   # posición en mundo
var velocities     := PackedVector2Array()   # velocidad actual
var xp_values      := PackedInt32Array()     # XP que concede
var lifetimes      := PackedFloat32Array()   # segundos desde spawn (scatter)
var attract_speeds := PackedFloat32Array()   # velocidad de atracción actual
var pulse_timers   := PackedFloat32Array()   # fase del pulso visual
var attracted      := PackedByteArray()      # 0 = libre, 1 = atraída por imán

# ════════════════════════════════════════════════════════════════════════════
#  3. MULTIMESH + SHADER
# ════════════════════════════════════════════════════════════════════════════

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

## INSTANCE_CUSTOM layout:
##   .r = sin(pulse_timer)          (-1..1)  → pulso de brillo
##   .g = vel normalizada           (0..1)   → intensidad del streak
##   .b = (vel_dir.x + 1) * 0.5    (0..1)   → dirección X del streak
##   .a = (vel_dir.y + 1) * 0.5    (0..1)   → dirección Y del streak
##
## Shader fiel al _draw() original:
##   · Diamante ancho=r*0.65, alto=r  (igual que los 4 vértices del original)
##   · Dos glows circulares planos  (r*2.6 α=0.10  +  r*1.8 α=0.18)
##   · Borde nítido Color(0.80, 0.96, 1.0, 0.85)
##   · Núcleo blanco r*0.30
##   · Streak en dirección opuesta a la velocidad (igual que draw_line)
##   · quad_size = radius * 7.0  →  R_UV = 1/7 constante en shader
const SHADER_CODE := """
shader_type canvas_item;

// quad_size = radius * 7.0  →  R_UV = gem_radius / quad_size = 1/7
const float R_UV = 0.14286;

varying flat vec4 cd;

void vertex() {
    cd = INSTANCE_CUSTOM;
}

void fragment() {
    vec2 uv = UV - vec2(0.5);   // centrado, ±0.5

    // ── Decode custom data ─────────────────────────────────────
    float pulse_sin = cd.r;                     // -1..1
    float vel_norm  = cd.g;                     // 0..1
    // FIX: QuadMesh en 2D invierte el eje Y del UV respecto al mundo.
    //      Negamos vel_dir.y al decodificar para compensar el flip.
    vec2 vel_dir = vec2(
        cd.b * 2.0 - 1.0,
       -(cd.a * 2.0 - 1.0)    // ← negado
    );

    // ── Pulso: sin()*0.12 + 1.0  (igual que el original) ──────
    float pulse = pulse_sin * 0.12 + 1.0;       // 0.88..1.12
    float rp    = R_UV * pulse;

    // ── Forma diamante ─────────────────────────────────────────
    // Vértices originales: (0,-r), (r*0.65, 0), (0,r), (-r*0.65, 0)
    // Ecuación: |x/(r*0.65)| + |y/r| ≤ 1
    float d_gem  = abs(uv.x / (rp * 0.65)) + abs(uv.y / rp);
    float body   = smoothstep(1.06, 0.92, d_gem);
    float border = smoothstep(1.13, 1.03, d_gem)
                 * (1.0 - smoothstep(1.03, 0.94, d_gem));

    // ── Distancia radial (glow y núcleo) ──────────────────────
    float dist = length(uv);

    // ── Glow suave (falloff cuadrático, mucho más visible que
    //    el original flat-circle a alpha bajo) ─────────────────
    // Reemplaza draw_circle(r*2.6, α=0.10) y draw_circle(r*1.8, α=0.18)
    // con una versión que produce el mismo área visible pero con glow real.
    // Glow exterior: radio r*3.2, falloff cúbico para suavidad máxima
    float g1    = max(0.0, 1.0 - dist / (R_UV * 3.2));
    float glow1 = g1 * g1 * g1 * 0.90;

    // Glow interior: radio r*2.0, caída cuadrática más intensa
    float g2    = max(0.0, 1.0 - dist / (R_UV * 2.0));
    float glow2 = g2 * g2 * 1.00;

    // ── Núcleo blanco ─────────────────────────────────────────
    // Original: draw_circle(max(1.5, r*0.30), Color(0.95,1,1,1))
    float core_r = max(0.025, R_UV * 0.30);
    float core   = smoothstep(core_r, core_r * 0.15, dist);

    // ── Streak (estela detrás del movimiento) ─────────────────
    // Original: draw_line(ZERO, -vel.normalized()*r*2.5,
    //           Color(0.40,0.82,1.0,0.40), max(1.0, r*0.4))
    // sd apunta en dirección opuesta a la velocidad = detrás de la gema.
    float streak = 0.0;
    if (vel_norm > 0.02 && length(vel_dir) > 0.01) {
        vec2  sd   = -normalize(vel_dir);        // opuesto al movimiento
        float proj = dot(uv, sd);                // > 0 detrás de la gema
        float perp = length(uv - sd * proj);

        float slen = rp * 4.5;                   // longitud = r*2.5 (igual que original)
        float sw   = max(0.010, rp * 0.80);      // ancho = max(1px, r*0.4)

        // Fade-in desde el centro, fade-out al final
        float ma = smoothstep(0.0,  slen * 0.25, proj)
                 * smoothstep(slen * 1.05, slen * 0.55, proj);
        float mp = smoothstep(sw, sw * 0.08, perp);

        streak = ma * mp * vel_norm;             // α máx = vel_norm (≤1)
    }

    // ── Composición (mismo orden que _draw()) ─────────────────
    vec3  col   = vec3(0.0);
    float alpha = 0.0;

    // Halo exterior  Color(0.35, 0.75, 1.0)
    col   += vec3(0.35, 0.75, 1.0) * glow1;
    alpha += glow1;

    // Halo interior  Color(0.40, 0.82, 1.0)
    col   += vec3(0.40, 0.82, 1.0) * glow2;
    alpha  = clamp(alpha + glow2, 0.0, 1.0);

    // Cuerpo diamante  Color(0.38, 0.80, 1.0, 0.92)
    col   = mix(col, vec3(0.38, 0.80, 1.0) * pulse, body);
    alpha = mix(alpha, 0.92, body);

    // Borde  Color(0.80, 0.96, 1.0, 0.85)
    col  += vec3(0.80, 0.96, 1.0) * border * 0.85;
    alpha = clamp(alpha + border * 0.85, 0.0, 1.0);

    // Núcleo  Color(0.95, 1.0, 1.0, 1.0)
    col   = mix(col, vec3(0.95, 1.0, 1.0), core);
    alpha = mix(alpha, 1.0, core);

    // Estela  Color(0.40, 0.82, 1.0, 0.40)
    col  += vec3(0.40, 0.82, 1.0) * streak * 1.5;
    alpha = clamp(alpha + streak * 0.80, 0.0, 1.0);

    COLOR = vec4(col, alpha);
}
"""

# ════════════════════════════════════════════════════════════════════════════
#  4. INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════════════════

## Guardado por compatibilidad con gameplay.gd — ya no se usa para spawning.
var _gems_container : Node = null

var _merge_timer : float = 0.0

func _ready() -> void:
	add_to_group("gem_manager")
	_init_arrays()
	_init_multimesh()

## Llamado desde gameplay.gd — mantiene la firma original.
func setup(container: Node) -> void:
	_gems_container = container

func _init_arrays() -> void:
	positions.resize(MAX_GEMS)
	velocities.resize(MAX_GEMS)
	xp_values.resize(MAX_GEMS)
	lifetimes.resize(MAX_GEMS)
	attract_speeds.resize(MAX_GEMS)
	pulse_timers.resize(MAX_GEMS)
	attracted.resize(MAX_GEMS)

func _init_multimesh() -> void:
	_mm              = MultiMesh.new()
	_mm.mesh         = QuadMesh.new()
	_mm.mesh.size    = Vector2(1.0, 1.0)   # escala real vía Transform2D
	_mm.use_custom_data    = true
	_mm.instance_count     = MAX_GEMS
	_mm.visible_instance_count = 0
	# AABB enorme para que el frustum culling de Godot no corte el MultiMesh
	_mm.custom_aabb  = AABB(Vector3(-100000, -100000, -1),
							Vector3(200000,  200000,   2))

	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code    = SHADER_CODE
	mat.shader     = shader

	_mm_instance           = MultiMeshInstance2D.new()
	_mm_instance.multimesh = _mm
	_mm_instance.material  = mat
	add_child(_mm_instance)

# ════════════════════════════════════════════════════════════════════════════
#  5. SPAWN
# ════════════════════════════════════════════════════════════════════════════

## Reemplaza la instanciación del PackedScene.
## Llamar desde gameplay.gd: gem_manager.spawn_gem(pos, xp)
func spawn_gem(pos: Vector2, xp: int, scatter_force: float = 1.0) -> void:
	if active_count >= MAX_GEMS:
		return

	var i     := active_count
	var angle := randf_range(0.0, TAU)
	var speed := randf_range(30.0, 90.0) * scatter_force

	positions[i]      = pos
	velocities[i]     = Vector2(cos(angle), sin(angle)) * speed
	xp_values[i]      = maxi(1, xp)
	lifetimes[i]      = 0.0
	attract_speeds[i] = 60.0
	pulse_timers[i]   = randf_range(0.0, TAU)   # fase aleatoria → gemas no sincronizan
	attracted[i]      = 0

	active_count += 1

# ════════════════════════════════════════════════════════════════════════════
#  6. FÍSICA  (imán, scatter, recolección)
# ════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if active_count == 0:
		_mm.visible_instance_count = 0
		return

	var player := get_tree().get_first_node_in_group("player")

	# Sin jugador: solo renderizamos en sus posiciones actuales
	if not is_instance_valid(player) or not player.is_alive:
		_render(null)
		return

	var p_pos       : Vector2 = player.global_position
	var mag_r_mult  : float   = player.magnet_range_mult if "magnet_range_mult" in player else 1.0
	var mag_spd_mult: float   = player.magnet_speed_mult if "magnet_speed_mult" in player else 1.0
	var mag_r_sq    : float   = (MAGNET_BASE * mag_r_mult) * (MAGNET_BASE * mag_r_mult)
	var max_spd     : float   = MAX_ATTRACT_SPD * mag_spd_mult
	var dt60        : float   = delta * 60.0

	var i := 0
	while i < active_count:
		lifetimes[i]    += delta
		pulse_timers[i] += delta * 3.0

		var pos    := positions[i]
		var vel    := velocities[i]
		var dx     := pos.x - p_pos.x
		var dy     := pos.y - p_pos.y
		var dsq    := dx * dx + dy * dy

		# ── Recolección ───────────────────────────────────────────────────
		if dsq <= COLLECT_RADIUS_SQ:
			var xp_to_give : int = xp_values[i]
			_remove(i)
			player.gain_experience(xp_to_give)
			continue   # NO incrementar i — swap-back puso otro elemento aquí

		# ── Fase scatter: fricción hasta SCATTER_TIME ─────────────────────
		if lifetimes[i] < SCATTER_TIME and attracted[i] == 0:
			vel = vel * pow(SCATTER_FRICTION, dt60)

		# ── Imán activo ───────────────────────────────────────────────────
		elif dsq <= mag_r_sq or attracted[i] == 1:
			attracted[i] = 1
			var inv_d  : float = 1.0 / sqrt(dsq) if dsq > 0.0001 else 0.0
			var dir_x  : float = -dx * inv_d
			var dir_y  : float = -dy * inv_d
			attract_speeds[i] = minf(attract_speeds[i] + ATTRACT_ACCEL * delta, max_spd)
			vel = Vector2(dir_x, dir_y) * attract_speeds[i]

		# ── Reposo pasivo ─────────────────────────────────────────────────
		else:
			vel = vel * pow(0.96, dt60)

		velocities[i] = vel
		positions[i]  = pos + vel * delta
		i += 1

	# ── Merge periódico ───────────────────────────────────────────────────
	_merge_timer += delta
	if _merge_timer >= MERGE_INTERVAL and active_count >= MERGE_THRESHOLD:
		_merge_timer = 0.0
		_run_merge()

	_render(player)

# ════════════════════════════════════════════════════════════════════════════
#  7. MERGE  (O(n²) sobre ventana pequeña — seguro con el intervalo amplio)
# ════════════════════════════════════════════════════════════════════════════

func _run_merge() -> void:
	# Radio aumentado ×2 si superamos el hard cap
	var r_sq : float = MERGE_RADIUS_SQ * (4.0 if active_count >= HARD_CAP else 1.0)

	var absorbed := PackedByteArray()
	absorbed.resize(active_count)
	absorbed.fill(0)

	var i := 0
	while i < active_count:
		if absorbed[i] == 1:
			i += 1; continue

		var px : float = positions[i].x
		var py : float = positions[i].y

		var j := i + 1
		while j < active_count:
			if absorbed[j] == 0:
				var ddx : float = px - positions[j].x
				var ddy : float = py - positions[j].y
				if ddx * ddx + ddy * ddy <= r_sq:
					# La gema i absorbe a la gema j
					xp_values[i] += xp_values[j]
					# Si la absorbida estaba siendo atraída, la principal también
					if attracted[j] == 1:
						attracted[i] = 1
					absorbed[j] = 1
			j += 1
		i += 1

	# Compactar el buffer eliminando las absorbidas
	var write := 0
	for k in range(active_count):
		if absorbed[k] == 0:
			if write != k:
				positions[write]      = positions[k]
				velocities[write]     = velocities[k]
				xp_values[write]      = xp_values[k]
				lifetimes[write]      = lifetimes[k]
				attract_speeds[write] = attract_speeds[k]
				pulse_timers[write]   = pulse_timers[k]
				attracted[write]      = attracted[k]
			write += 1
	active_count = write

# ════════════════════════════════════════════════════════════════════════════
#  8. RENDER  (frustum culling manual + actualización del MultiMesh)
# ════════════════════════════════════════════════════════════════════════════

func _render(player) -> void:
	var p_pos : Vector2 = player.global_position if is_instance_valid(player) else Vector2.ZERO

	# Límites de viewport para frustum culling manual
	var viewport  := get_viewport()
	var cam       := viewport.get_camera_2d()
	var cam_zoom  := cam.zoom if cam else Vector2.ONE
	var view_size := viewport.get_visible_rect().size / cam_zoom
	var half_x    := view_size.x * 0.5 + 200.0
	var half_y    := view_size.y * 0.5 + 200.0

	var visible_count := 0

	for i in range(active_count):
		var pos := positions[i]

		# Culling: saltar gemas fuera de pantalla
		if absf(pos.x - p_pos.x) > half_x or absf(pos.y - p_pos.y) > half_y:
			continue

		# XP mínimo real del juego = 5  →  base más alta para que se vea bien
		# xp=5  → r≈12  |  xp=10 → r≈14  |  xp=50 → r≈18  |  xp=200 → r≈22
		var radius    : float = clampf(4.0 + log(float(xp_values[i]) + 1.0) * 3.0, 4.0, 16.0)
		# quad_size = radius*7  →  R_UV ≈ 1/7 ≈ 0.1429 en el shader
		var quad_size : float = radius * 7.0

		_mm.set_instance_transform_2d(visible_count,
			Transform2D(0.0, Vector2(quad_size, quad_size), 0.0, pos))

		# Custom data para el shader
		var pulse_val : float = sin(pulse_timers[i])
		var vel       : Vector2 = velocities[i]
		var vel_sq    : float = vel.length_squared()
		# vel_norm: solo nonzero si atraída Y moviéndose (vel>20 → vel_sq>400)
		# igual que la condición del streak original
		var vel_norm  : float = 0.0
		var dir_x     : float = 0.5   # (0,0) codificado como (0.5, 0.5)
		var dir_y     : float = 0.5
		if attracted[i] == 1 and vel_sq > 400.0:
			vel_norm = clampf(vel_sq / (MAX_ATTRACT_SPD * MAX_ATTRACT_SPD), 0.0, 1.0)
			var inv_len : float = 1.0 / sqrt(vel_sq)
			dir_x = (vel.x * inv_len + 1.0) * 0.5   # encode -1..1 → 0..1
			dir_y = (vel.y * inv_len + 1.0) * 0.5

		_mm.set_instance_custom_data(visible_count,
			Color(pulse_val, vel_norm, dir_x, dir_y))

		visible_count += 1

	_mm.visible_instance_count = visible_count

# ════════════════════════════════════════════════════════════════════════════
#  9. UTILIDADES INTERNAS
# ════════════════════════════════════════════════════════════════════════════

## Elimina el índice i usando swap-back (O(1), sin mover todo el array).
func _remove(i: int) -> void:
	active_count -= 1
	if i == active_count:
		return
	positions[i]      = positions[active_count]
	velocities[i]     = velocities[active_count]
	xp_values[i]      = xp_values[active_count]
	lifetimes[i]      = lifetimes[active_count]
	attract_speeds[i] = attract_speeds[active_count]
	pulse_timers[i]   = pulse_timers[active_count]
	attracted[i]      = attracted[active_count]

# ════════════════════════════════════════════════════════════════════════════
#  10. API PÚBLICA  (sin cambios de firma respecto a la versión anterior)
# ════════════════════════════════════════════════════════════════════════════

## Número de gemas activas (para el debug panel).
func get_gem_count() -> int:
	return active_count

## Fuerza la atracción de TODAS las gemas al jugador
## (upgrade "Campo Magnético" / aspirar todo).
func attract_all() -> void:
	for i in range(active_count):
		attracted[i] = 1