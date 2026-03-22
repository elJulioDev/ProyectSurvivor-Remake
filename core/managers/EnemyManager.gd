extends Node2D
class_name EnemyManager

signal enemy_killed(pos: Vector2, points: int, type_id: int)

# ════════════════════════════════════════════════════════════════════════════
#  1. CONSTANTES Y CONFIGURACIÓN
#  CAMBIOS:
#    · Velocidad base: 100→65 (estilo Vampire Survivors, más lento)
#    · small speed_mult: 1.2→1.15 (siguen siendo los más rápidos pero menos)
#    · Spitter: lógica de IA propia — se queda en radio y dispara
#    · Exploder: explosión solo daña al jugador, NO a otros enemigos
# ════════════════════════════════════════════════════════════════════════════
const MAX_ENEMIES = 1200  # buffer interno (el cap real lo controla SpawnManager)

const TYPES = {
	"small":    { "id": 0, "size_mult": 0.70, "health": 40.0,  "speed_mult": 1.15, "damage": 6,  "color": Color8(160,240,160), "points": 5 },
	"normal":   { "id": 1, "size_mult": 0.90, "health": 90.0,  "speed_mult": 1.0,  "damage": 12, "color": Color8(70,160,70),   "points": 10 },
	"large":    { "id": 2, "size_mult": 1.1,  "health": 220.0, "speed_mult": 0.70, "damage": 18, "color": Color8(30,100,30),   "points": 20 },
	"tank":     { "id": 3, "size_mult": 1.3,  "health": 700.0, "speed_mult": 0.35, "damage": 30, "color": Color8(45,65,30),    "points": 60 },
	"exploder": { "id": 4, "size_mult": 0.95, "health": 70.0,  "speed_mult": 0.80, "damage": 0,  "color": Color8(255,80,20),   "points": 22 },
	"spitter":  { "id": 5, "size_mult": 1.0,  "health": 110.0, "speed_mult": 0.65, "damage": 8,  "color": Color8(80,210,50),   "points": 30 },
}

# Velocidad base reducida a 65 (era 100) — movimiento más táctico tipo VS
const ENEMY_BASE_SPEED : float = 65.0

const GRID_CELL_SIZE = 64.0
const GRID_WIDTH = 400
const GRID_HEIGHT = 400
const GRID_OFFSET = 12800.0
var _current_batch: int = 0
const BATCH_COUNT: int = 4

# ════════════════════════════════════════════════════════════════════════════
#  2. ESTRUCTURA DE ARREGLOS
# ════════════════════════════════════════════════════════════════════════════
var active_count: int = 0

var positions   := PackedVector2Array()
var velocities  := PackedVector2Array()
var knockbacks  := PackedVector2Array()

var healths           := PackedFloat32Array()
var max_healths       := PackedFloat32Array()
var speeds            := PackedFloat32Array()
var sizes             := PackedFloat32Array()
var hit_flashes       := PackedFloat32Array()
var lanes             := PackedFloat32Array()
var bleed_intensities := PackedFloat32Array()
var bleed_cooldowns   := PackedFloat32Array()

var types   := PackedInt32Array()
var damages := PackedInt32Array()
var points  := PackedInt32Array()

var grid_head := PackedInt32Array()
var grid_next := PackedInt32Array()

# ════════════════════════════════════════════════════════════════════════════
#  3. MOTOR DE DIBUJADO GPU
# ════════════════════════════════════════════════════════════════════════════
var multimesh_instance: MultiMeshInstance2D
var multimesh: MultiMesh

# ════════════════════════════════════════════════════════════════════════════
#  CONSTANTES PARA HABILIDADES ESPECIALES
# ════════════════════════════════════════════════════════════════════════════

# Exploder — solo daña al jugador
const EXPLODER_CHARGE_DIST   := 170.0
const EXPLODER_TRIGGER_DIST  :=  85.0
const EXPLODER_TRIGGER_CHARGE := 0.80
const EXPLODER_RADIUS        := 140.0
const EXPLODER_DAMAGE        :=  65.0   # solo al jugador
const EXPLODER_CHARGE_RATE   :=   0.035
const EXPLODER_DISCHARGE_RATE :=  0.025

# Spitter — mantiene distancia y dispara (igual que en Pygame)
const SPITTER_PREF_DIST     := 270.0   # distancia ideal del jugador
const SPITTER_NEAR_LIMIT    := 162.0   # 60% de pref — si más cerca, huye
const SPITTER_FAR_LIMIT     := 405.0   # 150% de pref — si más lejos, se acerca
const SPITTER_SHOOT_RANGE   := 530.0
const SPITTER_COOLDOWN_BASE := 360.0
const SPITTER_COOLDOWN_MIN  :=  90.0

var charge_levels     := PackedFloat32Array()
var special_cooldowns := PackedFloat32Array()

signal enemy_exploded(pos: Vector2, damage: float, radius: float)
signal enemy_shot(pos: Vector2, angle: float)

const SHADER_CODE = """
shader_type canvas_item;
uniform vec3 enemy_colors[6];
varying flat vec4 custom_data;

void vertex() {
	custom_data = INSTANCE_CUSTOM;
}

void fragment() {
	int type_idx = int(round(custom_data.r));
	vec3 base_color = enemy_colors[type_idx];
	vec3 border_color = base_color * 0.5;
	vec2 uv = UV - 0.5;

	vec4 final_color = vec4(0.0);
	if (abs(uv.x) <= 0.35 && abs(uv.y) <= 0.35) {
		final_color = vec4(base_color, 1.0);
		if (abs(uv.x) < 0.12 && abs(uv.y) < 0.12) { final_color.rgb = border_color; }
		if (abs(uv.x) > 0.31 || abs(uv.y) > 0.31)  { final_color.rgb = border_color; }
		final_color.rgb = mix(final_color.rgb, vec3(1.0), custom_data.b);
	}

	if (UV.y > 0.88 && UV.y < 0.98 && custom_data.a > 0.5) {
		if (UV.x > 0.15 && UV.x < 0.85) {
			final_color = vec4(0.1, 0.1, 0.1, 1.0);
			if (UV.y > 0.90 && UV.y < 0.96 && UV.x > 0.17 && UV.x < 0.83) {
				float hp_bar_x = (UV.x - 0.17) / 0.66;
				if (hp_bar_x < custom_data.g) {
					vec3 hp_col = custom_data.g < 0.3 ?
						vec3(1.0, 0.0, 0.0) : vec3(1.0, 0.6, 0.0);
					final_color.rgb = hp_col;
				} else {
					final_color.rgb = vec3(0.25, 0.0, 0.0);
				}
			}
		}
	}

	COLOR = final_color;
}
"""

var _particle_sys : Node = null

func _ready() -> void:
	add_to_group("enemy_manager")
	_init_arrays()
	_init_multimesh()
	call_deferred("_cache_refs")

func _cache_refs() -> void:
	_particle_sys = get_tree().get_first_node_in_group("blood_particles")

func _init_arrays() -> void:
	positions.resize(MAX_ENEMIES); velocities.resize(MAX_ENEMIES); knockbacks.resize(MAX_ENEMIES)
	healths.resize(MAX_ENEMIES); max_healths.resize(MAX_ENEMIES); speeds.resize(MAX_ENEMIES)
	sizes.resize(MAX_ENEMIES); hit_flashes.resize(MAX_ENEMIES); lanes.resize(MAX_ENEMIES)
	types.resize(MAX_ENEMIES); damages.resize(MAX_ENEMIES); points.resize(MAX_ENEMIES)
	grid_head.resize(GRID_WIDTH * GRID_HEIGHT)
	grid_next.resize(MAX_ENEMIES)
	bleed_intensities.resize(MAX_ENEMIES)
	bleed_cooldowns.resize(MAX_ENEMIES)
	charge_levels.resize(MAX_ENEMIES)
	special_cooldowns.resize(MAX_ENEMIES)

func _init_multimesh() -> void:
	multimesh = MultiMesh.new()
	multimesh.mesh = QuadMesh.new()
	multimesh.mesh.size = Vector2(1.0, 1.0)
	multimesh.use_custom_data = true
	multimesh.instance_count = MAX_ENEMIES
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))

	var custom_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = SHADER_CODE
	custom_mat.shader = shader

	var colors_array = PackedVector3Array()
	colors_array.resize(6)
	for key in TYPES:
		colors_array[TYPES[key]["id"]] = Vector3(
			TYPES[key]["color"].r, TYPES[key]["color"].g, TYPES[key]["color"].b)
	custom_mat.set_shader_parameter("enemy_colors", colors_array)

	multimesh_instance = MultiMeshInstance2D.new()
	multimesh_instance.multimesh = multimesh
	multimesh_instance.material = custom_mat
	add_child(multimesh_instance)

# ════════════════════════════════════════════════════════════════════════════
#  4. GENERADOR Y UTILIDADES
# ════════════════════════════════════════════════════════════════════════════
func get_active_count() -> int: return active_count

func spawn(pos: Vector2, type_name: String, speed_multiplier: float,
		   health_mult: float, damage_mult: float) -> void:
	if active_count >= MAX_ENEMIES: return

	var idx  = active_count
	var data = TYPES[type_name]
	var h    = data["health"] * health_mult

	positions[idx]  = pos
	velocities[idx] = Vector2.ZERO
	knockbacks[idx] = Vector2.ZERO
	healths[idx]    = h
	max_healths[idx]= h
	# Velocidad con la nueva base reducida
	speeds[idx]     = ENEMY_BASE_SPEED * speed_multiplier * data["speed_mult"] * randf_range(0.92, 1.08)
	sizes[idx]      = 36.0 * data["size_mult"]
	types[idx]      = data["id"]
	damages[idx]    = maxi(1, int(data["damage"] * damage_mult))
	points[idx]     = data["points"]
	hit_flashes[idx]= 0.0
	lanes[idx]      = sin(pos.x * 0.0071 + pos.y * 0.0053)
	bleed_intensities[idx] = 0.0
	bleed_cooldowns[idx]   = 0.0
	charge_levels[idx]    = 0.0
	special_cooldowns[idx] = randf_range(0.0, SPITTER_COOLDOWN_BASE * 0.5)
	active_count += 1

func teleport_distant(player_pos: Vector2, player_vel: Vector2 = Vector2.ZERO) -> void:
	const MAX_DIST_SQ      : float = 1900.0 * 1900.0
	const SPAWN_R_MIN      : float = 1300.0
	const SPAWN_R_MAX      : float = 1600.0
	const VEL_THRESHOLD_SQ : float = 400.0

	var moving  : bool  = player_vel.length_squared() > VEL_THRESHOLD_SQ
	var fwd_ang : float = player_vel.angle() if moving else 0.0

	for i in range(active_count):
		if positions[i].distance_squared_to(player_pos) <= MAX_DIST_SQ:
			continue

		var angle : float
		if moving:
			var roll := randf()
			if roll < 0.60:
				angle = fwd_ang + randf_range(-PI * 0.45, PI * 0.45)
			elif roll < 0.80:
				angle = fwd_ang + randf_range(PI * 0.45, PI * 0.90)
			else:
				angle = fwd_ang + randf_range(-PI * 0.90, -PI * 0.45)
		else:
			angle = randf() * TAU

		var radius : float = randf_range(SPAWN_R_MIN, SPAWN_R_MAX)
		positions[i]  = player_pos + Vector2(cos(angle), sin(angle)) * radius
		velocities[i] = Vector2.ZERO
		knockbacks[i] = Vector2.ZERO
		hit_flashes[i]= 0.0

# ════════════════════════════════════════════════════════════════════════════
#  5. LÓGICA DE MOVIMIENTO MULTI-HILO
# ════════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	_cleanup_dead_enemies()
	if active_count == 0:
		multimesh.visible_instance_count = 0
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player: return

	var p_pos = player.global_position
	var p_vel = player.velocity if "velocity" in player else Vector2.ZERO

	if Engine.get_process_frames() % 30 == 0:
		teleport_distant(p_pos, p_vel)

	_build_grid()

	_current_batch = (_current_batch + 1) % BATCH_COUNT
	var group_id = WorkerThreadPool.add_group_task(
		_process_enemy_movement.bind(delta, p_pos, p_vel, _current_batch), active_count)
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_process_specials(p_pos, delta)

	var render_hp_dist_sq : float = 550.0 * 550.0

	if not is_instance_valid(_particle_sys):
		_particle_sys = get_tree().get_first_node_in_group("blood_particles")

	var viewport  = get_viewport()
	var cam       = viewport.get_camera_2d()
	var cam_zoom  = cam.zoom if cam else Vector2.ONE
	var view_size = viewport.get_visible_rect().size / cam_zoom
	var cam_center : Vector2 = cam.get_screen_center_position() if cam else p_pos

	var half_screen_x : float = view_size.x * 0.5 + 300.0
	var half_screen_y : float = view_size.y * 0.5 + 300.0

	var visible_count     := 0
	var drips_this_frame  := 0
	const MAX_DRIPS_PER_FRAME := 3

	for i in range(active_count):
		var pos = positions[i]

		var dist_sq  = pos.distance_squared_to(p_pos)
		var min_dist = (sizes[i] * 0.4) + 12.0
		if dist_sq < min_dist * min_dist:
			if player.has_method("take_damage"):
				player.take_damage(damages[i])

		if bleed_intensities[i] > 0.0:
			bleed_intensities[i] -= 0.3 * delta * 60.0
			if bleed_intensities[i] <= 0.0:
				bleed_intensities[i] = 0.0
			else:
				bleed_cooldowns[i] -= delta * 60.0
				if bleed_cooldowns[i] <= 0.0 and drips_this_frame < MAX_DRIPS_PER_FRAME:
					if is_instance_valid(_particle_sys):
						_particle_sys.create_blood_drip(pos, bleed_intensities[i])
					bleed_cooldowns[i] = maxf(2.0, 20.0 - (bleed_intensities[i] * 0.8))
					drips_this_frame += 1

		var dist_x = absf(pos.x - cam_center.x)
		var dist_y = absf(pos.y - cam_center.y)

		if dist_x < half_screen_x and dist_y < half_screen_y:
			var quad_size = sizes[i] * 1.4
			var t = Transform2D(0, Vector2(quad_size, quad_size), 0, pos)
			multimesh.set_instance_transform_2d(visible_count, t)

			var hp_pct  = clampf(healths[i] / max_healths[i], 0.0, 1.0)
			var show_hp = 1.0 if healths[i] < max_healths[i] \
				and (dist_x * dist_x + dist_y * dist_y) < render_hp_dist_sq else 0.0
			var flash_val : float = hit_flashes[i]
			if types[i] == 4:
				flash_val = maxf(flash_val, charge_levels[i] * 0.75)
			multimesh.set_instance_custom_data(visible_count,
                Color(float(types[i]), hp_pct, flash_val, show_hp))

			visible_count += 1

	multimesh.visible_instance_count = visible_count

func _process_specials(player_pos: Vector2, delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	for i in range(active_count):
		match types[i]:
			4: _process_exploder(i, player_pos, player)
			5: _process_spitter(i, player_pos, delta)

# ─── EXPLODER ────────────────────────────────────────────────────────────
func _process_exploder(idx: int, player_pos: Vector2, player) -> void:
	if healths[idx] <= 0.0: return
	var pos    : Vector2 = positions[idx]
	var dist_sq: float   = pos.distance_squared_to(player_pos)

	if dist_sq < EXPLODER_CHARGE_DIST * EXPLODER_CHARGE_DIST:
		charge_levels[idx] = minf(1.0, charge_levels[idx] + EXPLODER_CHARGE_RATE)
	else:
		charge_levels[idx] = maxf(0.0, charge_levels[idx] - EXPLODER_DISCHARGE_RATE)

	if charge_levels[idx] >= EXPLODER_TRIGGER_CHARGE \
	    and dist_sq < EXPLODER_TRIGGER_DIST * EXPLODER_TRIGGER_DIST:
		_trigger_explosion(idx, player_pos, player)

func _trigger_explosion(idx: int, player_pos: Vector2, player) -> void:
	var pos := positions[idx]

	# Solo daña al jugador — NO a otros enemigos (comportamiento correcto)
	var dist_to_player := pos.distance_to(player_pos)
	if dist_to_player <= EXPLODER_RADIUS and is_instance_valid(player):
		var falloff := maxf(0.2, 1.0 - (dist_to_player / EXPLODER_RADIUS) * 0.7)
		if player.has_method("take_damage"):
			player.take_damage(EXPLODER_DAMAGE * falloff)

	# Señal visual → gameplay.gd crea el flash + partículas
	enemy_exploded.emit(pos, EXPLODER_DAMAGE, EXPLODER_RADIUS)

	# Matar al exploder
	healths[idx] = 0.0

# ─── SPITTER ─────────────────────────────────────────────────────────────
# El spitter se queda en su radio preferido (270px) y dispara periódicamente,
# exactamente igual que en el código Python original.
func _process_spitter(idx: int, player_pos: Vector2, delta: float) -> void:
	if healths[idx] <= 0.0: return

	if special_cooldowns[idx] > 0.0:
		special_cooldowns[idx] -= delta * 60.0
		return

	var pos    : Vector2 = positions[idx]
	var dist_sq: float   = pos.distance_squared_to(player_pos)

	if dist_sq > SPITTER_SHOOT_RANGE * SPITTER_SHOOT_RANGE: return

	var angle := (player_pos - pos).angle()
	enemy_shot.emit(pos, angle)
	special_cooldowns[idx] = SPITTER_COOLDOWN_BASE

# ════════════════════════════════════════════════════════════════════════════
#  MOVIMIENTO POR TIPO — hilo secundario
# ════════════════════════════════════════════════════════════════════════════
func _build_grid() -> void:
	grid_head.fill(-1)
	grid_next.fill(-1)
	for i in range(active_count):
		var cx = clampi(int((positions[i].x + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_WIDTH - 1)
		var cy = clampi(int((positions[i].y + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_HEIGHT - 1)
		var cell_idx = cx + cy * GRID_WIDTH
		grid_next[i]      = grid_head[cell_idx]
		grid_head[cell_idx] = i

func _process_enemy_movement(i: int, delta: float, p_pos: Vector2,
							  p_vel: Vector2, current_batch: int) -> void:
	var pos = positions[i]
	var spd = speeds[i]

	# ── SPITTER: movimiento propio — mantiene distancia y dispara ────────
	# Igual que en el código Python: si está muy cerca huye, si está en rango
	# se queda quieto, si está lejos se acerca.
	if types[i] == 5:
		var dx : float = pos.x - p_pos.x
		var dy : float = pos.y - p_pos.y
		var dist_sq : float = dx * dx + dy * dy
		var dist : float = sqrt(dist_sq) if dist_sq > 0.0001 else 0.001
		var inv_d : float = 1.0 / dist

		if dist < SPITTER_NEAR_LIMIT:
			# Muy cerca — alejarse del jugador
			var flee_speed : float = spd * 0.9
			var target_vx : float = (dx * inv_d) * flee_speed
			var target_vy : float = (dy * inv_d) * flee_speed
			velocities[i] = velocities[i].lerp(Vector2(target_vx, target_vy), 0.25)
		elif dist > SPITTER_FAR_LIMIT:
			# Muy lejos — acercarse lentamente
			var target_vx : float = (-dx * inv_d) * spd
			var target_vy : float = (-dy * inv_d) * spd
			velocities[i] = velocities[i].lerp(Vector2(target_vx, target_vy), 0.20)
		else:
			# En rango preferido — frenarse gradualmente
			velocities[i] = velocities[i].lerp(Vector2.ZERO, 0.15)

		# Aplicar knockback y física básica
		if knockbacks[i].length_squared() > 0.01:
			knockbacks[i] *= pow(0.88, delta * 60.0)
			if knockbacks[i].length() < 0.1:
				knockbacks[i] = Vector2.ZERO
		positions[i] += (velocities[i] + knockbacks[i]) * delta

		if hit_flashes[i] > 0.0:
			hit_flashes[i] = maxf(0.0, hit_flashes[i] - delta * 6.0)
		return

	# ── RESTO DE ENEMIGOS: movimiento estándar hacia el jugador ──────────
	if i % BATCH_COUNT == current_batch:
		var p_vel_frame = p_vel / 60.0
		var raw_dist    = pos.distance_to(p_pos)
		var predict_t   = minf(18.0, raw_dist / maxf(1.0, spd * 2.5))
		var target_pos  = p_pos + p_vel_frame * (predict_t * 0.55)
		var dir         = pos.direction_to(target_pos)
		if dir == Vector2.ZERO: dir = Vector2.RIGHT

		# Separación entre enemigos (anti-clustering)
		var push_x     = 0.0
		var push_y     = 0.0
		var sep_radius = sizes[i] * 0.4 * 4.0
		var cr_sq      = sep_radius * sep_radius
		var count      = 0

		var cx = clampi(int((pos.x + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_WIDTH - 1)
		var cy = clampi(int((pos.y + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_HEIGHT - 1)

		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = clampi(cx + dx, 0, GRID_WIDTH - 1)
				var ny = clampi(cy + dy, 0, GRID_HEIGHT - 1)
				var enemy_idx = grid_head[nx + ny * GRID_WIDTH]
				while enemy_idx != -1 and count < 4:
					if enemy_idx != i:
						var other_pos = positions[enemy_idx]
						var odx       = pos.x - other_pos.x
						var ody       = pos.y - other_pos.y
						var odist_sq  = odx * odx + ody * ody
						if odist_sq > 0.0001 and odist_sq < cr_sq:
							var odist  = sqrt(odist_sq)
							var overlap = sep_radius - odist
							var ps      = overlap * (overlap / sep_radius) * 0.18
							push_x += (odx / odist) * ps
							push_y += (ody / odist) * ps
							count  += 1
					enemy_idx = grid_next[enemy_idx]

		if count > 1:
			var inv_sqrt = 1.0 / sqrt(float(count))
			push_x *= inv_sqrt
			push_y *= inv_sqrt

		var push_sq  = push_x * push_x + push_y * push_y
		var max_push = spd * 1.2
		if push_sq > max_push * max_push:
			var inv_pm = max_push / sqrt(push_sq)
			push_x *= inv_pm
			push_y *= inv_pm

		# Movimiento lateral por carril (evita que todos vayan en línea recta)
		var perp        = Vector2(-dir.y, dir.x)
		var lat_strength = 0.35 * spd
		var lane_vel    = perp * lanes[i] * lat_strength

		var target_vx = dir.x * spd + push_x + lane_vel.x
		var target_vy = dir.y * spd + push_y + lane_vel.y

		var lerp_f = 0.35  # ligeramente más suave que antes (era 0.40)
		var cv     = velocities[i]
		velocities[i] = Vector2(
			cv.x * (1.0 - lerp_f) + target_vx * lerp_f,
			cv.y * (1.0 - lerp_f) + target_vy * lerp_f)

	if knockbacks[i].length_squared() > 0.01:
		knockbacks[i] *= pow(0.88, delta * 60.0)
		if knockbacks[i].length() < 0.1: knockbacks[i] = Vector2.ZERO

	positions[i] += (velocities[i] + knockbacks[i]) * delta

	if hit_flashes[i] > 0.0:
		hit_flashes[i] = maxf(0.0, hit_flashes[i] - delta * 6.0)

# ════════════════════════════════════════════════════════════════════════════
#  6. SISTEMA DE DAÑO Y BÚSQUEDA ESPACIAL
# ════════════════════════════════════════════════════════════════════════════

func get_all_type_counts() -> Dictionary:
	var counts : Dictionary = {
		"small": 0, "normal": 0, "large": 0,
		"tank": 0, "exploder": 0, "spitter": 0,
	}
	for i in range(active_count):
		match types[i]:
			0: counts["small"]    += 1
			1: counts["normal"]   += 1
			2: counts["large"]    += 1
			3: counts["tank"]     += 1
			4: counts["exploder"] += 1
			5: counts["spitter"]  += 1
	return counts

func get_enemies_near_proxy(pos: Vector2, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var r2     = radius * radius
	var min_cx = clampi(int((pos.x - radius + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_WIDTH  - 1)
	var max_cx = clampi(int((pos.x + radius + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_WIDTH  - 1)
	var min_cy = clampi(int((pos.y - radius + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_HEIGHT - 1)
	var max_cy = clampi(int((pos.y + radius + GRID_OFFSET) / GRID_CELL_SIZE), 0, GRID_HEIGHT - 1)
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var enemy_idx = grid_head[cx + cy * GRID_WIDTH]
			while enemy_idx != -1:
				if positions[enemy_idx].distance_squared_to(pos) <= r2:
					result.append(enemy_idx)
				enemy_idx = grid_next[enemy_idx]
	return result

func damage_enemy(idx: int, amount: float, hit_dir: Vector2 = Vector2.ZERO,
				  knockback_force: float = 0.0, skip_blood: bool = false) -> void:
	if idx < 0 or idx >= active_count: return
	if healths[idx] <= 0: return
	if is_nan(amount): amount = 0.0

	if is_nan(hit_dir.x) or is_nan(hit_dir.y) or hit_dir.length_squared() < 0.001:
		hit_dir = Vector2.ZERO
	else:
		hit_dir = hit_dir.normalized()

	healths[idx]     -= amount
	hit_flashes[idx]  = 1.0

	if not skip_blood:
		bleed_intensities[idx] = minf(40.0, bleed_intensities[idx] + amount)

	if knockback_force > 0.0 and hit_dir != Vector2.ZERO:
		var size_factor    = 40.0 / maxf(1.0, sizes[idx])
		var frame_knockback = hit_dir * knockback_force * size_factor * 60.0
		if not is_nan(frame_knockback.x) and not is_nan(frame_knockback.y):
			knockbacks[idx] += frame_knockback
			if knockbacks[idx].length() > 500.0:
				knockbacks[idx] = knockbacks[idx].limit_length(500.0)

	if not skip_blood:
		if not is_instance_valid(_particle_sys):
			_particle_sys = get_tree().get_first_node_in_group("blood_particles")
		if is_instance_valid(_particle_sys):
			var dmg_ratio := clampf(amount / max_healths[idx] * 6.0, 0.0, 1.0)
			_particle_sys.create_blood_splatter(positions[idx], hit_dir, 1.2, 8, dmg_ratio)
			if amount > 10.0 or dmg_ratio > 0.3:
				_particle_sys.create_wound_stain(positions[idx], dmg_ratio)

func _kill_enemy(idx: int) -> void:
	enemy_killed.emit(positions[idx], points[idx], types[idx])
	if is_instance_valid(_particle_sys):
		_particle_sys.create_viscera_explosion(positions[idx], sizes[idx] / 40.0)

	active_count -= 1
	if idx != active_count:
		positions[idx]         = positions[active_count]
		velocities[idx]        = velocities[active_count]
		knockbacks[idx]        = knockbacks[active_count]
		healths[idx]           = healths[active_count]
		max_healths[idx]       = max_healths[active_count]
		speeds[idx]            = speeds[active_count]
		sizes[idx]             = sizes[active_count]
		types[idx]             = types[active_count]
		damages[idx]           = damages[active_count]
		points[idx]            = points[active_count]
		hit_flashes[idx]       = hit_flashes[active_count]
		lanes[idx]             = lanes[active_count]
		bleed_intensities[idx] = bleed_intensities[active_count]
		bleed_cooldowns[idx]   = bleed_cooldowns[active_count]
		charge_levels[idx]     = charge_levels[active_count]
		special_cooldowns[idx] = special_cooldowns[active_count]

func _cleanup_dead_enemies() -> void:
	var i := 0
	while i < active_count:
		if healths[i] <= 0:
			_kill_enemy(i)
		else:
			i += 1