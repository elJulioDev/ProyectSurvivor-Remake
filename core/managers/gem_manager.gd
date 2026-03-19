extends Node2D
class_name GemManager

const MAX_GEMS          : int   = 2000
const COLLECT_RADIUS    : float = 20.0
const COLLECT_RADIUS_SQ : float = COLLECT_RADIUS * COLLECT_RADIUS
const MAGNET_BASE       : float = 140.0
const ATTRACT_ACCEL     : float = 700.0
const MAX_ATTRACT_SPD   : float = 480.0
const SCATTER_FRICTION  : float = 0.88
const SCATTER_TIME      : float = 0.25
const MERGE_INTERVAL    : float = 2.0
const MERGE_THRESHOLD   : int   = 35
const MERGE_RADIUS      : float = 22.0
const MERGE_RADIUS_SQ   : float = MERGE_RADIUS * MERGE_RADIUS
const HARD_CAP          : int   = 200

var active_count : int = 0

var positions      := PackedVector2Array()
var velocities     := PackedVector2Array()
var xp_values      := PackedInt32Array()
var lifetimes      := PackedFloat32Array()
var attract_speeds := PackedFloat32Array()
var pulse_timers   := PackedFloat32Array()
var attracted      := PackedByteArray()

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

const SHADER_CODE := """
shader_type canvas_item;
const float R_UV = 0.14286;
varying flat vec4 cd;
void vertex() { cd = INSTANCE_CUSTOM; }
void fragment() {
    vec2 uv = UV - vec2(0.5);
    float pulse_sin = cd.r;
    float vel_norm  = cd.g;
    vec2 vel_dir = vec2(cd.b * 2.0 - 1.0, -(cd.a * 2.0 - 1.0));
    float pulse = pulse_sin * 0.12 + 1.0;
    float rp    = R_UV * pulse;
    float d_gem  = abs(uv.x / (rp * 0.65)) + abs(uv.y / rp);
    float body   = smoothstep(1.06, 0.92, d_gem);
    float border = smoothstep(1.13, 1.03, d_gem) * (1.0 - smoothstep(1.03, 0.94, d_gem));
    float dist = length(uv);
    float g1    = max(0.0, 1.0 - dist / (R_UV * 3.2));
    float glow1 = g1 * g1 * g1 * 0.90;
    float g2    = max(0.0, 1.0 - dist / (R_UV * 2.0));
    float glow2 = g2 * g2 * 1.00;
    float core_r = max(0.025, R_UV * 0.30);
    float core   = smoothstep(core_r, core_r * 0.15, dist);
    float streak = 0.0;
    if (vel_norm > 0.02 && length(vel_dir) > 0.01) {
        vec2  sd   = -normalize(vel_dir);
        float proj = dot(uv, sd);
        float perp = length(uv - sd * proj);
        float slen = rp * 4.5;
        float sw   = max(0.010, rp * 0.80);
        float ma = smoothstep(0.0, slen * 0.25, proj) * smoothstep(slen * 1.05, slen * 0.55, proj);
        float mp = smoothstep(sw, sw * 0.08, perp);
        streak = ma * mp * vel_norm;
    }
    vec3  col   = vec3(0.0);
    float alpha = 0.0;
    col   += vec3(0.35, 0.75, 1.0) * glow1;
    alpha += glow1;
    col   += vec3(0.40, 0.82, 1.0) * glow2;
    alpha  = clamp(alpha + glow2, 0.0, 1.0);
    col   = mix(col, vec3(0.38, 0.80, 1.0) * pulse, body);
    alpha = mix(alpha, 0.92, body);
    col  += vec3(0.80, 0.96, 1.0) * border * 0.85;
    alpha = clamp(alpha + border * 0.85, 0.0, 1.0);
    col   = mix(col, vec3(0.95, 1.0, 1.0), core);
    alpha = mix(alpha, 1.0, core);
    col  += vec3(0.40, 0.82, 1.0) * streak * 1.5;
    alpha = clamp(alpha + streak * 0.80, 0.0, 1.0);
    COLOR = vec4(col, alpha);
}
"""

var _gems_container : Node = null
var _merge_timer    : float = 0.0

func _ready() -> void:
	add_to_group("gem_manager")
	_init_arrays()
	_init_multimesh()

func setup(container: Node) -> void:
	_gems_container = container

func _init_arrays() -> void:
	positions.resize(MAX_GEMS);      velocities.resize(MAX_GEMS)
	xp_values.resize(MAX_GEMS);      lifetimes.resize(MAX_GEMS)
	attract_speeds.resize(MAX_GEMS); pulse_timers.resize(MAX_GEMS)
	attracted.resize(MAX_GEMS)

func _init_multimesh() -> void:
	_mm                        = MultiMesh.new()
	_mm.mesh                   = QuadMesh.new()
	_mm.mesh.size              = Vector2(1.0, 1.0)
	_mm.use_custom_data        = true
	_mm.instance_count         = MAX_GEMS
	_mm.visible_instance_count = 0
	_mm.custom_aabb            = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code    = SHADER_CODE
	mat.shader     = shader
	_mm_instance           = MultiMeshInstance2D.new()
	_mm_instance.multimesh = _mm
	_mm_instance.material  = mat
	add_child(_mm_instance)

func spawn_gem(pos: Vector2, xp: int, scatter_force: float = 1.0) -> void:
	if active_count >= MAX_GEMS: return
	var i     := active_count
	var angle := randf_range(0.0, TAU)
	var speed := randf_range(30.0, 90.0) * scatter_force
	positions[i]      = pos
	velocities[i]     = Vector2(cos(angle), sin(angle)) * speed
	xp_values[i]      = maxi(1, xp)
	lifetimes[i]      = 0.0
	attract_speeds[i] = 60.0
	pulse_timers[i]   = randf_range(0.0, TAU)
	attracted[i]      = 0
	active_count += 1

func _physics_process(delta: float) -> void:
	if active_count == 0:
		_mm.visible_instance_count = 0
		return

	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.is_alive:
		_render(null)
		return

	var p_pos        : Vector2 = player.global_position
	var mag_r_mult   : float   = player.magnet_range_mult if "magnet_range_mult" in player else 1.0
	var mag_spd_mult : float   = player.magnet_speed_mult if "magnet_speed_mult" in player else 1.0
	var mag_r_sq     : float   = (MAGNET_BASE * mag_r_mult) * (MAGNET_BASE * mag_r_mult)
	var max_spd      : float   = MAX_ATTRACT_SPD * mag_spd_mult
	var dt60         : float   = delta * 60.0

	var i := 0
	while i < active_count:
		lifetimes[i]    += delta
		pulse_timers[i] += delta * 3.0

		var pos := positions[i]
		var vel := velocities[i]
		var dx  := pos.x - p_pos.x
		var dy  := pos.y - p_pos.y
		var dsq := dx * dx + dy * dy

		if dsq <= COLLECT_RADIUS_SQ:
			var xp_to_give : int = xp_values[i]
			_remove(i)
			player.gain_experience(xp_to_give)
			continue

		if lifetimes[i] < SCATTER_TIME and attracted[i] == 0:
			vel = vel * pow(SCATTER_FRICTION, dt60)
		elif dsq <= mag_r_sq or attracted[i] == 1:
			attracted[i] = 1
			var inv_d  : float = 1.0 / sqrt(dsq) if dsq > 0.0001 else 0.0
			attract_speeds[i] = minf(attract_speeds[i] + ATTRACT_ACCEL * delta, max_spd)
			vel = Vector2(-dx * inv_d, -dy * inv_d) * attract_speeds[i]
		else:
			vel = vel * pow(0.96, dt60)

		velocities[i] = vel
		positions[i]  = pos + vel * delta
		i += 1

	_merge_timer += delta
	if _merge_timer >= MERGE_INTERVAL and active_count >= MERGE_THRESHOLD:
		_merge_timer = 0.0
		_run_merge()

	_render(player)

func _run_merge() -> void:
	var r_sq : float = MERGE_RADIUS_SQ * (4.0 if active_count >= HARD_CAP else 1.0)
	var absorbed := PackedByteArray()
	absorbed.resize(active_count)
	absorbed.fill(0)

	var i := 0
	while i < active_count:
		if absorbed[i] == 1: i += 1; continue
		var px : float = positions[i].x
		var py : float = positions[i].y
		var j  := i + 1
		while j < active_count:
			if absorbed[j] == 0:
				var ddx : float = px - positions[j].x
				var ddy : float = py - positions[j].y
				if ddx * ddx + ddy * ddy <= r_sq:
					xp_values[i] += xp_values[j]
					if attracted[j] == 1: attracted[i] = 1
					absorbed[j] = 1
			j += 1
		i += 1

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

func _render(player) -> void:
	var viewport  := get_viewport()
	var cam       := viewport.get_camera_2d()
	var cam_zoom  := cam.zoom if cam else Vector2.ONE
	var view_size := viewport.get_visible_rect().size / cam_zoom
	var half_x    := view_size.x * 0.5 + 200.0
	var half_y    := view_size.y * 0.5 + 200.0

	# ── FIX CULLING: usar centro real de cámara, no posición del jugador ──
	# En esquinas del mapa la cámara está clampeada y su centro difiere
	# del jugador. Usar p_pos cortaba la visibilidad en mitad de pantalla.
	var cam_center : Vector2 = cam.get_screen_center_position() \
		if cam else (player.global_position if is_instance_valid(player) else Vector2.ZERO)

	var visible_count := 0
	for i in range(active_count):
		var pos := positions[i]
		if absf(pos.x - cam_center.x) > half_x or absf(pos.y - cam_center.y) > half_y:
			continue

		var radius    : float = clampf(4.0 + log(float(xp_values[i]) + 1.0) * 3.0, 4.0, 16.0)
		var quad_size : float = radius * 7.0
		_mm.set_instance_transform_2d(visible_count,
			Transform2D(0.0, Vector2(quad_size, quad_size), 0.0, pos))

		var pulse_val : float = sin(pulse_timers[i])
		var vel       : Vector2 = velocities[i]
		var vel_sq    : float   = vel.length_squared()
		var vel_norm  : float   = 0.0
		var dir_x     : float   = 0.5
		var dir_y     : float   = 0.5
		if attracted[i] == 1 and vel_sq > 400.0:
			vel_norm  = clampf(vel_sq / (MAX_ATTRACT_SPD * MAX_ATTRACT_SPD), 0.0, 1.0)
			var inv_l : float = 1.0 / sqrt(vel_sq)
			dir_x = (vel.x * inv_l + 1.0) * 0.5
			dir_y = (vel.y * inv_l + 1.0) * 0.5
		_mm.set_instance_custom_data(visible_count, Color(pulse_val, vel_norm, dir_x, dir_y))
		visible_count += 1

	_mm.visible_instance_count = visible_count

func _remove(i: int) -> void:
	active_count -= 1
	if i == active_count: return
	positions[i]      = positions[active_count]
	velocities[i]     = velocities[active_count]
	xp_values[i]      = xp_values[active_count]
	lifetimes[i]      = lifetimes[active_count]
	attract_speeds[i] = attract_speeds[active_count]
	pulse_timers[i]   = pulse_timers[active_count]
	attracted[i]      = attracted[active_count]

func get_gem_count() -> int: return active_count

func attract_all() -> void:
	for i in range(active_count):
		attracted[i] = 1