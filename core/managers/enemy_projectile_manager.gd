extends Node2D
class_name EnemyProjectileManager

## Proyectiles enemigos — ácido del Spitter (DOD ligero)

const MAX_PROJ    := 60
const PROJ_SPEED  := 300.0   # px/s
const PROJ_RADIUS :=  8.0
const PROJ_DAMAGE :=  14
const PROJ_LIFE   :=   2.9   # segundos (175 frames / 60)

var active_count := 0
var positions    := PackedVector2Array()
var velocities   := PackedVector2Array()
var lifetimes    := PackedFloat32Array()
var pulse_timers := PackedFloat32Array()

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

const SHADER_CODE := """
shader_type canvas_item;
varying flat float v_life;
void vertex() { v_life = INSTANCE_CUSTOM.r; }
void fragment() {
    vec2 uv = UV - 0.5;
    float d = length(uv);
    if (d > 0.42) discard;
    float pulse = v_life;
    float core  = smoothstep(0.22, 0.10, d);
    float body  = smoothstep(0.42, 0.30, d);
    vec3 col = mix(vec3(0.20, 0.80, 0.20), vec3(0.70, 1.0, 0.30), core);
    float glow = smoothstep(0.42, 0.10, d) * 0.6;
    col += vec3(0.10, 0.25, 0.0) * glow * (0.6 + pulse * 0.4);
    COLOR = vec4(col, body * (0.75 + pulse * 0.20));
}
"""

func _ready() -> void:
    add_to_group("enemy_projectile_manager")
    _init_arrays()
    _init_multimesh()

func _init_arrays() -> void:
    positions.resize(MAX_PROJ)
    velocities.resize(MAX_PROJ)
    lifetimes.resize(MAX_PROJ)
    pulse_timers.resize(MAX_PROJ)

func _init_multimesh() -> void:
    _mm                        = MultiMesh.new()
    _mm.mesh                   = QuadMesh.new()
    _mm.mesh.size              = Vector2(1.0, 1.0)
    _mm.use_custom_data        = true
    _mm.instance_count         = MAX_PROJ
    _mm.visible_instance_count = 0
    _mm.custom_aabb            = AABB(Vector3(-100000,-100000,-1), Vector3(200000,200000,2))
    var mat    := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code  = SHADER_CODE
    mat.shader   = shader
    _mm_instance           = MultiMeshInstance2D.new()
    _mm_instance.multimesh = _mm
    _mm_instance.material  = mat
    add_child(_mm_instance)

func spawn(pos: Vector2, angle: float) -> void:
    if active_count >= MAX_PROJ: return
    var i := active_count
    positions[i]     = pos
    velocities[i]    = Vector2(cos(angle), sin(angle)) * PROJ_SPEED
    lifetimes[i]     = PROJ_LIFE
    pulse_timers[i]  = randf_range(0.0, TAU)
    active_count    += 1

func _physics_process(delta: float) -> void:
    if active_count == 0:
        _mm.visible_instance_count = 0
        return

    var player := get_tree().get_first_node_in_group("player")
    var p_pos  : Vector2 = player.global_position if is_instance_valid(player) else Vector2(-99999, -99999)
    var col_r  : float   = PROJ_RADIUS + 12.0
    var col_sq : float   = col_r * col_r

    var i := 0
    while i < active_count:
        positions[i]     += velocities[i] * delta
        lifetimes[i]     -= delta
        pulse_timers[i]  += delta * 4.0

        # Colisión con jugador
        var dx := positions[i].x - p_pos.x
        var dy := positions[i].y - p_pos.y
        if dx * dx + dy * dy <= col_sq:
            if is_instance_valid(player) and player.has_method("take_damage"):
                player.take_damage(PROJ_DAMAGE)
            _remove(i)
            continue

        if lifetimes[i] <= 0.0:
            _remove(i)
            continue
        i += 1

    _render()

func _render() -> void:
    var viewport  := get_viewport()
    var cam       := viewport.get_camera_2d()
    var cam_zoom  := cam.zoom if cam else Vector2.ONE
    var view_size := viewport.get_visible_rect().size / cam_zoom
    var half_x    := view_size.x * 0.5 + 80.0
    var half_y    := view_size.y * 0.5 + 80.0
    var cam_center : Vector2 = cam.get_screen_center_position() if cam else Vector2.ZERO

    var vis := 0
    for i in range(active_count):
        var pos := positions[i]
        if absf(pos.x - cam_center.x) > half_x or absf(pos.y - cam_center.y) > half_y:
            continue
        var qs := PROJ_RADIUS * 3.0
        _mm.set_instance_transform_2d(vis, Transform2D(0.0, Vector2(qs,qs), 0.0, pos))
        var pulse : float = sin(pulse_timers[i]) * 0.5 + 0.5
        _mm.set_instance_custom_data(vis, Color(pulse, 0.0, 0.0, 0.0))
        vis += 1
    _mm.visible_instance_count = vis

func _remove(idx: int) -> void:
    active_count -= 1
    if idx == active_count: return
    positions[idx]    = positions[active_count]
    velocities[idx]   = velocities[active_count]
    lifetimes[idx]    = lifetimes[active_count]
    pulse_timers[idx] = pulse_timers[active_count]

func get_active_count() -> int: return active_count
func clear() -> void:
    active_count = 0
    _mm.visible_instance_count = 0