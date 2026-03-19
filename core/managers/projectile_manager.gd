extends Node2D
class_name ProjectileManager

## ProjectileManager v2 — DOD + MultiMesh + Comportamientos Avanzados
## Cambio respecto a la versión anterior: _render() usa
## cam.get_screen_center_position() para el frustum culling,
## corrigiendo la desaparición de proyectiles en esquinas del mapa.

const MAX_PROJECTILES := 1500
const QUAD_MULT := 2.5

var active_count := 0

var positions      := PackedVector2Array()
var prev_positions := PackedVector2Array()
var velocities     := PackedVector2Array()
var damages        := PackedInt32Array()
var penetrations   := PackedInt32Array()
var lifetimes      := PackedFloat32Array()
var max_lifetimes  := PackedFloat32Array()
var radii          := PackedFloat32Array()
var kb_mults       := PackedFloat32Array()
var inner_mults    := PackedFloat32Array()
var col_r          := PackedFloat32Array()
var col_g          := PackedFloat32Array()
var col_b          := PackedFloat32Array()
var use_swept      := PackedByteArray()
var fade_out       := PackedByteArray()
var fade_mults     := PackedFloat32Array()
var flicker_flags  := PackedByteArray()
var hit_sets       : Array = []

var is_homing        := PackedByteArray()
var homing_strengths := PackedFloat32Array()
var homing_delays    := PackedFloat32Array()
var homing_ranges    := PackedFloat32Array()
var base_speeds      := PackedFloat32Array()
var bounces_left     := PackedInt32Array()
var chain_left       := PackedInt32Array()
var chain_ranges     := PackedFloat32Array()
var chain_dmg_mults  := PackedFloat32Array()
var explodes         := PackedByteArray()
var explode_radii    := PackedFloat32Array()
var explode_dmg_mults:= PackedFloat32Array()
var splits           := PackedByteArray()
var split_counts     := PackedInt32Array()
var split_spreads    := PackedFloat32Array()
var accelerations    := PackedFloat32Array()
var speed_caps       := PackedFloat32Array()
var sine_amps        := PackedFloat32Array()
var sine_freqs       := PackedFloat32Array()
var sine_phases      := PackedFloat32Array()
var size_growths     := PackedFloat32Array()
var burn_dps_arr     := PackedFloat32Array()
var burn_durations   := PackedFloat32Array()
var slow_factors     := PackedFloat32Array()
var slow_durations   := PackedFloat32Array()

var _pending_spawns : Array = []

var _mm_instance : MultiMeshInstance2D
var _mm          : MultiMesh

const SHADER_CODE := """
shader_type canvas_item;
varying flat vec4 v_col;
varying flat vec4 v_cd;
void vertex() { v_col = COLOR; v_cd = INSTANCE_CUSTOM; }
void fragment() {
    vec2  uv  = UV - vec2(0.5);
    float dst = length(uv);
    const float OUTER = 0.40;
    if (dst > OUTER + 0.04) discard;
    vec3  col  = v_col.rgb;
    float alph = v_col.a;
    if (v_cd.b > 0.5) {
        float t = v_cd.g;
        col  = vec3(1.0, mix(0.30, 0.65, t), 0.0);
        alph = mix(0.70, 1.00, t) * v_col.a;
    }
    float im = v_cd.r;
    if (im > 0.01 && dst <= OUTER * im) { col = mix(col, vec3(1.0, 1.0, 0.95), 0.70); }
    float edge = smoothstep(OUTER + 0.02, OUTER - 0.04, dst);
    COLOR = vec4(col, alph * edge);
}
"""

func _ready() -> void:
	add_to_group("projectile_manager")
	_init_arrays()
	_init_multimesh()

func _init_arrays() -> void:
	positions.resize(MAX_PROJECTILES);      prev_positions.resize(MAX_PROJECTILES)
	velocities.resize(MAX_PROJECTILES);     damages.resize(MAX_PROJECTILES)
	penetrations.resize(MAX_PROJECTILES);   lifetimes.resize(MAX_PROJECTILES)
	max_lifetimes.resize(MAX_PROJECTILES);  radii.resize(MAX_PROJECTILES)
	kb_mults.resize(MAX_PROJECTILES);       inner_mults.resize(MAX_PROJECTILES)
	col_r.resize(MAX_PROJECTILES);          col_g.resize(MAX_PROJECTILES)
	col_b.resize(MAX_PROJECTILES);          use_swept.resize(MAX_PROJECTILES)
	fade_out.resize(MAX_PROJECTILES);       fade_mults.resize(MAX_PROJECTILES)
	flicker_flags.resize(MAX_PROJECTILES)
	is_homing.resize(MAX_PROJECTILES);      homing_strengths.resize(MAX_PROJECTILES)
	homing_delays.resize(MAX_PROJECTILES);  homing_ranges.resize(MAX_PROJECTILES)
	base_speeds.resize(MAX_PROJECTILES);    bounces_left.resize(MAX_PROJECTILES)
	chain_left.resize(MAX_PROJECTILES);     chain_ranges.resize(MAX_PROJECTILES)
	chain_dmg_mults.resize(MAX_PROJECTILES);explodes.resize(MAX_PROJECTILES)
	explode_radii.resize(MAX_PROJECTILES);  explode_dmg_mults.resize(MAX_PROJECTILES)
	splits.resize(MAX_PROJECTILES);         split_counts.resize(MAX_PROJECTILES)
	split_spreads.resize(MAX_PROJECTILES);  accelerations.resize(MAX_PROJECTILES)
	speed_caps.resize(MAX_PROJECTILES);     sine_amps.resize(MAX_PROJECTILES)
	sine_freqs.resize(MAX_PROJECTILES);     sine_phases.resize(MAX_PROJECTILES)
	size_growths.resize(MAX_PROJECTILES);   burn_dps_arr.resize(MAX_PROJECTILES)
	burn_durations.resize(MAX_PROJECTILES); slow_factors.resize(MAX_PROJECTILES)
	slow_durations.resize(MAX_PROJECTILES)
	hit_sets.resize(MAX_PROJECTILES)
	for i in range(MAX_PROJECTILES):
		hit_sets[i] = {}

func _init_multimesh() -> void:
	_mm                        = MultiMesh.new()
	_mm.mesh                   = QuadMesh.new()
	_mm.mesh.size              = Vector2(1.0, 1.0)
	_mm.use_colors             = true
	_mm.use_custom_data        = true
	_mm.instance_count         = MAX_PROJECTILES
	_mm.visible_instance_count = 0
	_mm.custom_aabb            = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	var mat    := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code  = SHADER_CODE
	mat.shader   = shader
	_mm_instance           = MultiMeshInstance2D.new()
	_mm_instance.multimesh = _mm
	_mm_instance.material  = mat
	add_child(_mm_instance)

func spawn(
	pos: Vector2, vel: Vector2, damage: int, penetration: int,
	max_lt: float, radius: float, knockback: float, inner_mult: float,
	color: Color, p_use_swept: bool, p_fade_out: bool, fade_mult: float,
	p_flicker: bool, extra: Dictionary = {}
) -> void:
	if active_count >= MAX_PROJECTILES: return
	var i     := active_count
	var speed : float = vel.length()
	positions[i]         = pos;   prev_positions[i]    = pos
	velocities[i]        = vel;   damages[i]           = damage
	penetrations[i]      = penetration; lifetimes[i]   = 0.0
	max_lifetimes[i]     = max_lt; radii[i]            = radius
	kb_mults[i]          = knockback; inner_mults[i]   = inner_mult
	col_r[i]             = color.r; col_g[i]           = color.g; col_b[i] = color.b
	use_swept[i]         = 1 if p_use_swept else 0
	fade_out[i]          = 1 if p_fade_out  else 0
	fade_mults[i]        = fade_mult
	flicker_flags[i]     = 1 if p_flicker   else 0
	hit_sets[i].clear()
	var init_hits : Dictionary = extra.get("initial_hits", {})
	if not init_hits.is_empty():
		for k in init_hits: hit_sets[i][k] = true
	is_homing[i]         = 1 if extra.get("homing", false) else 0
	homing_strengths[i]  = extra.get("homing_strength", PI)
	homing_delays[i]     = extra.get("homing_delay",    0.0)
	homing_ranges[i]     = extra.get("homing_range",    600.0)
	base_speeds[i]       = speed
	bounces_left[i]      = extra.get("bounces", 0)
	chain_left[i]        = extra.get("chain_count",      0)
	chain_ranges[i]      = extra.get("chain_range",      220.0)
	chain_dmg_mults[i]   = extra.get("chain_damage_mult",0.65)
	explodes[i]          = 1 if extra.get("explodes", false) else 0
	explode_radii[i]     = extra.get("explosion_radius",      90.0)
	explode_dmg_mults[i] = extra.get("explosion_damage_mult", 0.55)
	splits[i]            = 1 if extra.get("splits", false) else 0
	split_counts[i]      = extra.get("split_count",  3)
	split_spreads[i]     = extra.get("split_spread", 1.2)
	accelerations[i]     = extra.get("acceleration",   0.0)
	speed_caps[i]        = extra.get("max_speed_cap",  0.0)
	sine_amps[i]         = extra.get("sine_amplitude", 0.0)
	sine_freqs[i]        = extra.get("sine_frequency", 2.0)
	sine_phases[i]       = randf_range(0.0, TAU) if sine_amps[i] > 0.0 else 0.0
	size_growths[i]      = extra.get("size_growth",    0.0)
	burn_dps_arr[i]      = extra.get("burn_dps",       0.0)
	burn_durations[i]    = extra.get("burn_duration",  3.0)
	slow_factors[i]      = extra.get("slow_factor",    0.0)
	slow_durations[i]    = extra.get("slow_duration",  2.0)
	active_count += 1

func _physics_process(delta: float) -> void:
	if active_count == 0:
		_mm.visible_instance_count = 0
		return
	if not is_instance_valid(GameManager.enemy_manager): return

	var dt60 := delta * 60.0
	var i    := 0

	while i < active_count:
		prev_positions[i] = positions[i]
		if is_homing[i]:
			if homing_delays[i] > 0.0: homing_delays[i] -= dt60
			else: _apply_homing(i, delta)
		if accelerations[i] != 0.0: _apply_acceleration(i, delta)

		var pos_delta : Vector2 = velocities[i] * delta
		if sine_amps[i] > 0.0:
			var old_phase : float = sine_phases[i]
			sine_phases[i] += sine_freqs[i] * TAU * delta
			var delta_sin : float = sin(sine_phases[i]) - sin(old_phase)
			var vel_len   : float = velocities[i].length()
			if vel_len > 0.1:
				var perp : Vector2 = Vector2(-velocities[i].y, velocities[i].x) / vel_len
				pos_delta += perp * delta_sin * sine_amps[i]

		positions[i]  += pos_delta
		lifetimes[i]  += dt60
		if size_growths[i] > 0.0: radii[i] += size_growths[i] * delta
		if bounces_left[i] > 0:   _check_wall_bounce(i)

		if lifetimes[i] >= max_lifetimes[i]:
			_on_death(i, false); _remove(i); continue

		var killed := false
		if use_swept[i]: killed = _check_swept(i)
		else:            killed = _check_normal(i)
		if killed: _on_death(i, true); _remove(i); continue
		i += 1

	for cfg in _pending_spawns:
		if active_count < MAX_PROJECTILES:
			spawn(cfg.pos, cfg.vel, cfg.dmg, cfg.pen, cfg.lt, cfg.rad,
				  cfg.kb, cfg.inner, cfg.col, false,
				  cfg.fade, cfg.fade_m, cfg.flicker, cfg.extra)
	_pending_spawns.clear()
	_render()

func _apply_homing(idx: int, delta: float) -> void:
	var em := GameManager.enemy_manager
	if not is_instance_valid(em): return
	var pos        : Vector2 = positions[idx]
	var candidates           = em.get_enemies_near_proxy(pos, homing_ranges[idx])
	if candidates.is_empty(): return
	var best_idx   : int   = -1
	var best_dsq   : float = INF
	for eidx in candidates:
		if hit_sets[idx].has(eidx): continue
		var dsq : float = pos.distance_squared_to(em.positions[eidx])
		if dsq < best_dsq: best_dsq = dsq; best_idx = eidx
	if best_idx < 0: return
	var target_dir  : Vector2 = (em.positions[best_idx] - pos).normalized()
	var current_dir : Vector2 = velocities[idx].normalized()
	if current_dir == Vector2.ZERO or target_dir == Vector2.ZERO: return
	var angle_diff : float = current_dir.angle_to(target_dir)
	var max_turn   : float = homing_strengths[idx] * delta
	velocities[idx] = current_dir.rotated(clampf(angle_diff, -max_turn, max_turn)) * base_speeds[idx]

func _apply_acceleration(idx: int, delta: float) -> void:
	var spd : float = velocities[idx].length()
	if spd < 0.001: return
	var new_spd : float = spd + accelerations[idx] * delta
	if speed_caps[idx] > 0.0: new_spd = clampf(new_spd, 0.0, speed_caps[idx])
	else: new_spd = maxf(0.0, new_spd)
	velocities[idx] *= (new_spd / spd)
	base_speeds[idx]  = new_spd

func _check_wall_bounce(idx: int) -> void:
	var pos : Vector2 = positions[idx]
	var vel : Vector2 = velocities[idx]
	var bounced := false
	if pos.x < 0.0:                      pos.x = 0.0;                   vel.x =  absf(vel.x); bounced = true
	elif pos.x > GameManager.WORLD_WIDTH: pos.x = GameManager.WORLD_WIDTH; vel.x = -absf(vel.x); bounced = true
	if pos.y < 0.0:                       pos.y = 0.0;                   vel.y =  absf(vel.y); bounced = true
	elif pos.y > GameManager.WORLD_HEIGHT:pos.y = GameManager.WORLD_HEIGHT;vel.y = -absf(vel.y); bounced = true
	if bounced:
		positions[idx] = pos; velocities[idx] = vel
		base_speeds[idx] = vel.length(); bounces_left[idx] -= 1
		hit_sets[idx].clear()

func _check_normal(idx: int) -> bool:
	var pos  := positions[idx]
	var hits  = GameManager.enemy_manager.get_enemies_near_proxy(pos, radii[idx] + 16.0)
	var vn   := velocities[idx].normalized()
	for eidx in hits:
		if hit_sets[idx].has(eidx): continue
		hit_sets[idx][eidx] = true
		GameManager.enemy_manager.damage_enemy(eidx, float(damages[idx]), vn, 8.0 * kb_mults[idx])
		penetrations[idx] -= 1
		if penetrations[idx] <= 0: return true
	return false

func _check_swept(idx: int) -> bool:
	var pa    := prev_positions[idx]
	var pb    := positions[idx]
	var mid   := (pa + pb) * 0.5
	var seg_r := pb.distance_to(pa) * 0.5 + radii[idx] + 14.0
	var hits   = GameManager.enemy_manager.get_enemies_near_proxy(mid, seg_r)
	var vn    := velocities[idx].normalized()
	var hr    := radii[idx] + 14.0
	for eidx in hits:
		if hit_sets[idx].has(eidx): continue
		var epos = GameManager.enemy_manager.positions[eidx]
		if _point_seg_dist(epos, pa, pb) <= hr:
			hit_sets[idx][eidx] = true
			GameManager.enemy_manager.damage_enemy(eidx, float(damages[idx]), vn, 12.0 * kb_mults[idx])
			penetrations[idx] -= 1
			if penetrations[idx] <= 0: return true
	return false

func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab  : Vector2 = b - a
	var lsq : float   = ab.length_squared()
	if lsq == 0.0: return p.distance_to(a)
	return p.distance_to(a + clampf((p - a).dot(ab) / lsq, 0.0, 1.0) * ab)

func _on_death(idx: int, was_hit: bool) -> void:
	var pos : Vector2 = positions[idx]
	var vel : Vector2 = velocities[idx]
	var em          := GameManager.enemy_manager

	if explodes[idx] and is_instance_valid(em):
		var er  : float = explode_radii[idx]
		var edm : float = float(damages[idx]) * explode_dmg_mults[idx]
		var in_r        = em.get_enemies_near_proxy(pos, er)
		for eidx in in_r:
			if hit_sets[idx].has(eidx): continue
			var dir : Vector2 = (em.positions[eidx] - pos)
			if dir.length_squared() > 0.001: dir = dir.normalized()
			em.damage_enemy(eidx, edm, dir, 6.0)

	if was_hit and chain_left[idx] > 0 and is_instance_valid(em):
		var cands   = em.get_enemies_near_proxy(pos, chain_ranges[idx])
		var best_i  : int   = -1
		var best_d  : float = INF
		for eidx in cands:
			if hit_sets[idx].has(eidx): continue
			var d : float = pos.distance_squared_to(em.positions[eidx])
			if d < best_d: best_d = d; best_i = eidx
		if best_i >= 0:
			var dir_c = (em.positions[best_i] - pos).normalized()
			var ec    := _build_chain_extra(idx)
			_pending_spawns.append({
				"pos": pos, "vel": dir_c * base_speeds[idx],
				"dmg": maxi(1, int(float(damages[idx]) * chain_dmg_mults[idx])),
				"pen": 1, "lt": max_lifetimes[idx] * 0.75, "rad": radii[idx],
				"kb": kb_mults[idx], "inner": inner_mults[idx],
				"col": Color(col_r[idx], col_g[idx], col_b[idx]),
				"fade": true, "fade_m": 1.2, "flicker": flicker_flags[idx] != 0, "extra": ec,
			})

	if splits[idx] and split_counts[idx] > 0:
		var n      : int   = split_counts[idx]
		var spread : float = split_spreads[idx]
		var base_a : float = vel.angle() if vel.length_squared() > 0.1 else 0.0
		var es     := _build_split_extra(idx)
		for k in range(n):
			var t   : float = float(k) / float(maxi(1, n - 1)) - 0.5
			var ang : float = base_a + (spread * t if n > 1 else 0.0)
			_pending_spawns.append({
				"pos": pos, "vel": Vector2(cos(ang), sin(ang)) * base_speeds[idx] * 0.85,
				"dmg": damages[idx], "pen": 1, "lt": max_lifetimes[idx] * 0.5,
				"rad": radii[idx] * 0.7, "kb": kb_mults[idx], "inner": inner_mults[idx],
				"col": Color(col_r[idx], col_g[idx], col_b[idx]),
				"fade": true, "fade_m": 1.5, "flicker": flicker_flags[idx] != 0, "extra": es,
			})

func _build_chain_extra(idx: int) -> Dictionary:
	var e := _build_base_extra(idx)
	e["bounces"] = 0; e["chain_count"] = chain_left[idx] - 1
	e["splits"] = false; e["sine_amplitude"] = 0.0; e["homing_delay"] = 0.0
	e["initial_hits"] = hit_sets[idx].duplicate()
	return e

func _build_split_extra(idx: int) -> Dictionary:
	var e := _build_base_extra(idx)
	e["chain_count"] = 0; e["splits"] = false; e["explodes"] = false; e["sine_amplitude"] = 0.0
	return e

func _build_base_extra(idx: int) -> Dictionary:
	return {
		"homing": is_homing[idx] != 0, "homing_strength": homing_strengths[idx],
		"homing_delay": homing_delays[idx], "homing_range": homing_ranges[idx],
		"bounces": bounces_left[idx], "chain_count": chain_left[idx],
		"chain_range": chain_ranges[idx], "chain_damage_mult": chain_dmg_mults[idx],
		"explodes": explodes[idx] != 0, "explosion_radius": explode_radii[idx],
		"explosion_damage_mult": explode_dmg_mults[idx],
		"splits": splits[idx] != 0, "split_count": split_counts[idx],
		"split_spread": split_spreads[idx], "acceleration": accelerations[idx],
		"max_speed_cap": speed_caps[idx], "sine_amplitude": sine_amps[idx],
		"sine_frequency": sine_freqs[idx], "size_growth": size_growths[idx],
		"burn_dps": burn_dps_arr[idx], "burn_duration": burn_durations[idx],
		"slow_factor": slow_factors[idx], "slow_duration": slow_durations[idx],
		"initial_hits": {},
	}

func _render() -> void:
	var player    := get_tree().get_first_node_in_group("player")
	var p_pos     = player.global_position if is_instance_valid(player) else Vector2.ZERO

	var viewport  := get_viewport()
	var cam       := viewport.get_camera_2d()
	var cam_zoom  := cam.zoom if cam else Vector2.ONE
	var view_size := viewport.get_visible_rect().size / cam_zoom
	var half_x    := view_size.x * 0.5 + 150.0
	var half_y    := view_size.y * 0.5 + 150.0

	# ── FIX CULLING: centro de cámara, no posición del jugador ────────────
	var cam_center : Vector2 = cam.get_screen_center_position() if cam else p_pos

	var vis := 0
	for i in range(active_count):
		var pos := positions[i]
		if absf(pos.x - cam_center.x) > half_x or absf(pos.y - cam_center.y) > half_y:
			continue

		var qs : float = radii[i] * QUAD_MULT
		_mm.set_instance_transform_2d(vis, Transform2D(0.0, Vector2(qs, qs), 0.0, pos))

		var alpha := 1.0
		if fade_out[i]:
			var progress := 1.0 - (lifetimes[i] / maxf(1.0, max_lifetimes[i]))
			alpha = clampf(progress * fade_mults[i], 0.0, 1.0)

		_mm.set_instance_color(vis, Color(col_r[i], col_g[i], col_b[i], alpha))
		_mm.set_instance_custom_data(vis, Color(
			inner_mults[i],
			randf() if flicker_flags[i] else 0.0,
			float(flicker_flags[i]), 0.0))
		vis += 1

	_mm.visible_instance_count = vis

func _remove(idx: int) -> void:
	active_count -= 1
	if idx == active_count: hit_sets[idx].clear(); return
	positions[idx] = positions[active_count]; prev_positions[idx] = prev_positions[active_count]
	velocities[idx] = velocities[active_count]; damages[idx] = damages[active_count]
	penetrations[idx] = penetrations[active_count]; lifetimes[idx] = lifetimes[active_count]
	max_lifetimes[idx] = max_lifetimes[active_count]; radii[idx] = radii[active_count]
	kb_mults[idx] = kb_mults[active_count]; inner_mults[idx] = inner_mults[active_count]
	col_r[idx] = col_r[active_count]; col_g[idx] = col_g[active_count]; col_b[idx] = col_b[active_count]
	use_swept[idx] = use_swept[active_count]; fade_out[idx] = fade_out[active_count]
	fade_mults[idx] = fade_mults[active_count]; flicker_flags[idx] = flicker_flags[active_count]
	is_homing[idx] = is_homing[active_count]; homing_strengths[idx] = homing_strengths[active_count]
	homing_delays[idx] = homing_delays[active_count]; homing_ranges[idx] = homing_ranges[active_count]
	base_speeds[idx] = base_speeds[active_count]; bounces_left[idx] = bounces_left[active_count]
	chain_left[idx] = chain_left[active_count]; chain_ranges[idx] = chain_ranges[active_count]
	chain_dmg_mults[idx] = chain_dmg_mults[active_count]; explodes[idx] = explodes[active_count]
	explode_radii[idx] = explode_radii[active_count]; explode_dmg_mults[idx] = explode_dmg_mults[active_count]
	splits[idx] = splits[active_count]; split_counts[idx] = split_counts[active_count]
	split_spreads[idx] = split_spreads[active_count]; accelerations[idx] = accelerations[active_count]
	speed_caps[idx] = speed_caps[active_count]; sine_amps[idx] = sine_amps[active_count]
	sine_freqs[idx] = sine_freqs[active_count]; sine_phases[idx] = sine_phases[active_count]
	size_growths[idx] = size_growths[active_count]; burn_dps_arr[idx] = burn_dps_arr[active_count]
	burn_durations[idx] = burn_durations[active_count]; slow_factors[idx] = slow_factors[active_count]
	slow_durations[idx] = slow_durations[active_count]
	var recycled = hit_sets[idx]
	hit_sets[idx] = hit_sets[active_count]
	hit_sets[active_count] = recycled
	recycled.clear()

func get_active_count() -> int: return active_count

func clear() -> void:
	active_count = 0; _pending_spawns.clear()
	for i in range(MAX_PROJECTILES): hit_sets[i].clear()
	_mm.visible_instance_count = 0