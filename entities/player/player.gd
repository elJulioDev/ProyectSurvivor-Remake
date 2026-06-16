extends CharacterBody2D

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  player.gd — ProyectSurvivor
#  Sin _draw(). El render se delega a nodos hijos:
#    · PlayerSprite (ColorRect)  — cuerpo visible
#    · AimLine (Line2D)          — indicador de ángulo
#    · DamageFlash (ColorRect)   — flash al recibir daño
#    · DashGhosts (Node2D)       — estelas del dash
#    · AuraVisual (Node2D)       — círculo y pulso del aura
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

signal died
signal leveled_up
signal health_changed(current: float, maximum: float)
signal xp_changed(current: int, next_level: int)

const PLAYER_SIZE    := 20

const BASE_MAX_SPEED := 210.0
const BASE_ACCEL     := 38.0
const FRICTION       := 0.88
const SPEED_DEADZONE := 4.0

const DASH_DURATION_BASE := 12.0 / 60.0
const DASH_COOLDOWN_BASE := 45.0 / 60.0
const DASH_SPEED         := 1100.0
const DASH_BUFFER_SECS   :=  9.0 / 60.0
const MAX_GHOSTS         := 5

const INVULN_BASE_SECS  := 60.0 / 60.0
const DAMAGE_FLASH_SECS := 15.0 / 60.0

# ── Stats ─────────────────────────────────────────────────────────
var max_speed        : float = BASE_MAX_SPEED
var accel            : float = BASE_ACCEL
var max_health       : float = 100.0
var health           : float = 100.0
var health_regen     : float = 0.0
var damage_reduction : float = 0.0
var invulnerable_mult: float = 1.0
var emergency_regen  : float = 0.0
var is_alive         : bool  = true
var level            : int   = 1
var experience       : float = 0.0
var experience_next  : float = 50.0
var experience_next_level : float :
	get: return experience_next
	set(v): experience_next = v
var pending_level_ups: int   = 0
var upgrade_counts   : Dictionary = {}
var xp_mult          : float = 1.0
var magnet_range_mult: float = 1.0
var magnet_speed_mult: float = 1.0
var xp_on_kill_bonus : int   = 0

var gem_xp_mult            : float = 1.0
var extra_gem_chance_bonus : float = 0.0

var curse_spawn_mult  : float = 1.0
var curse_health_mult : float = 1.0
var curse_speed_mult  : float = 1.0
var curse_elite_mult  : float = 1.0

var aura_damage            : float = 0.0
var aura_radius            : float = 80.0
var aura_knockback         : float = 0.0
var aura_knockback_interval: float = 4.0

var global_damage_mult    : float = 1.0
var global_cooldown_mult  : float = 1.0
var projectile_speed_mult : float = 1.0
var projectile_size_mult  : float = 1.0
var extra_penetration     : int   = 0
var knockback_mult        : float = 1.0

var lifesteal_chance : float = 0.0
var lifesteal        : float = 5.0

# ── Estado interno ────────────────────────────────────────────────
var dash_unlocked      : bool  = false
var dash_active        : bool  = false
var dash_duration_mult : float = 1.0
var dash_cooldown_mult : float = 1.0
var ninja_dash         : bool  = false

var _dash_timer        : float   = 0.0
var _dash_cd_timer     : float   = 0.0
var _dash_buffer_timer : float   = 0.0
var _dash_dir          : Vector2 = Vector2.ZERO
var _ghost_positions   : Array   = []
var _ninja_hit_ids     : Dictionary = {}

var aim_angle           : float = 0.0
var _invuln_timer       : float = 0.0
var _damage_flash_timer : float = 0.0

var stun_timer       : float = 0.0
var knockback_vel    : Vector2 = Vector2.ZERO

# Estado interno
var bleed_intensity : float = 0.0
var bleed_cooldown  : float = 0.0

var _shoot_block_timer : float = 0.0
var _aura_pulse_timer  : float = 0.0

var character_data : CharacterData = null

# ── Armas ─────────────────────────────────────────────────────────
var weapons : Array :
	get:
		if has_node("WeaponPivot/WeaponController"):
			return $WeaponPivot/WeaponController.equipped_weapons
		return []

var unlocked_weapon_names : Array[String] = []
var current_weapon_index  : int = 0

@onready var _weapon_pivot      : Node2D    = get_node_or_null("WeaponPivot")
@onready var _weapon_controller : Node2D    = get_node_or_null("WeaponPivot/WeaponController")
@onready var _sprite            : ColorRect = get_node_or_null("PlayerSprite")
@onready var _aim_line          : Line2D    = get_node_or_null("AimLine")
@onready var _damage_flash      : ColorRect = get_node_or_null("DamageFlash")
@onready var _dash_ghosts       : Node2D    = get_node_or_null("DashGhosts")
@onready var _aura_visual       : Node2D    = get_node_or_null("AuraVisual")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	add_to_group("player")
	_apply_character_data()
	
	if is_instance_valid(_aura_visual):
		_aura_visual.visible = false
		
	# Forzamos la primera actualización visual
	_update_visuals()

# ════════════════════════════════════════════════════════════════════

func _apply_character_data() -> void:
	character_data = GameManager.get_or_default_character()
	if not character_data:
		add_weapon("Pistol")
		return

	max_health           = character_data.base_hp * character_data.hp_mult
	health               = max_health
	global_damage_mult  *= character_data.damage_mult
	global_cooldown_mult *= character_data.cooldown_mult
	xp_mult             *= character_data.xp_mult

	for weapon_name in character_data.starting_weapons:
		add_weapon(weapon_name)

	_apply_character_passive(character_data.passive_id, character_data.passive_value)

	# Colorear sprite con el color del personaje
	if is_instance_valid(_sprite):
		_sprite.color = character_data.color

	print("[Player] Personaje cargado: %s | Armas: %s" % [
		character_data.character_name,
		character_data.starting_weapons
	])


func _apply_character_passive(passive_id: String, value: float) -> void:
	match passive_id:
		"health_regen": health_regen += value
		"double_tap":   set_meta("double_tap_chance", value)
		"":             pass
		_: push_warning("_apply_character_passive: pasiva desconocida '%s'" % passive_id)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if Input.is_action_just_pressed("dash"):
		_attempt_dash()

	_update_aim()
	_update_timers(delta)
	_handle_movement(delta)
	_process_aura(delta)
	_process_blood_drip(delta)
	_clamp_to_world()
	move_and_slide()

	if not GameManager.is_mobile():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			attack()

	_update_visuals()

# ── Apuntado ──────────────────────────────────────────────────────

func _update_aim() -> void:
	if not GameManager.is_mobile():
		aim_angle = (get_global_mouse_position() - global_position).angle()
	if is_instance_valid(_weapon_pivot):
		_weapon_pivot.rotation = aim_angle

# ── Visuals (sin _draw, actualizamos propiedades de nodos) ────────

func _update_visuals() -> void:
	# Calcular cuándo ocultar los nodos por frames de invulnerabilidad (parpadeo)
	var should_hide := false
	if _invuln_timer > 0.0 and _damage_flash_timer <= 0.0:
		should_hide = int(_invuln_timer * 60.0) % 6 >= 3

	# Calcular ratio de flash rojo (1.0 = recién golpeado, 0.0 = sano)
	var flash_ratio := clampf(_damage_flash_timer / DAMAGE_FLASH_SECS, 0.0, 1.0)
	var base_color := character_data.color if character_data else Color.WHITE
	
	# Interpolar suavemente el color base del jugador hacia rojo
	var current_color := base_color.lerp(Color(1.0, 0.2, 0.2), flash_ratio)

	# Actualizar Sprite
	if is_instance_valid(_sprite):
		_sprite.visible = not should_hide
		_sprite.color = current_color # Aplica el tinte suave
		
		# Override de Ninja Dash
		if ninja_dash and dash_unlocked:
			_sprite.modulate = Color(0.63, 0.0, 1.0) if dash_active else Color.WHITE

	# Actualizar AimLine para que parpadee y se tiña con el jugador
	if is_instance_valid(_aim_line):
		var tip := Vector2(cos(aim_angle), sin(aim_angle)) * float(PLAYER_SIZE)
		_aim_line.set_point_position(1, tip)
		_aim_line.visible = not should_hide
		_aim_line.default_color = current_color # Recibe el mismo lerp rojo

	# Desvanecimiento suave del DamageFlash general
	if is_instance_valid(_damage_flash):
		_damage_flash.visible = flash_ratio > 0.0
		var df_color = _damage_flash.color
		df_color.a = flash_ratio * 0.6 # Interpolación de opacidad de 0.6 hacia 0.0
		_damage_flash.color = df_color

	if is_instance_valid(_dash_ghosts):
		_dash_ghosts.set_ghosts(_ghost_positions, ninja_dash)

	if is_instance_valid(_aura_visual):
		_aura_visual.visible = aura_damage > 0.0
		if _aura_visual.visible:
			_aura_visual.set_state(aura_radius, aura_knockback, _aura_pulse_timer, aura_knockback_interval)

# ── Timers ────────────────────────────────────────────────────────

func _update_timers(delta: float) -> void:
	if _dash_cd_timer > 0.0:
		_dash_cd_timer -= delta
		if _dash_cd_timer <= 0.0:
			_dash_cd_timer = 0.0
			if _dash_buffer_timer > 0.0:
				_execute_dash()

	if _dash_buffer_timer > 0.0:
		_dash_buffer_timer -= delta
		if _dash_buffer_timer < 0.0:
			_dash_buffer_timer = 0.0

	if dash_active:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			dash_active = false
			_ghost_positions.clear()
			_ninja_hit_ids.clear()
			velocity = _dash_dir * max_speed * 0.8

	if _invuln_timer > 0.0:
		_invuln_timer = maxf(0.0, _invuln_timer - delta)

	if _damage_flash_timer > 0.0:
		_damage_flash_timer = maxf(0.0, _damage_flash_timer - delta)

	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)

	if health_regen > 0.0 and health < max_health:
		health = minf(health + health_regen * delta, max_health)

	if emergency_regen > 0.0 and health < max_health * 0.25:
		health = minf(health + emergency_regen * delta, max_health)

	if _shoot_block_timer > 0.0:
		_shoot_block_timer -= delta

# ── Movimiento ────────────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	if dash_active:
		if _ghost_positions.size() < MAX_GHOSTS:
			_ghost_positions.append({"pos": global_position, "angle": aim_angle})
		else:
			_ghost_positions.pop_front()
			_ghost_positions.append({"pos": global_position, "angle": aim_angle})

		velocity = _dash_dir * DASH_SPEED

		if ninja_dash and is_instance_valid(GameManager.enemy_manager):
			var hits = GameManager.enemy_manager.get_enemies_near_proxy(
				global_position, float(PLAYER_SIZE) * 1.5)
			for idx in hits:
				if not _ninja_hit_ids.has(idx):
					_ninja_hit_ids[idx] = true
					GameManager.enemy_manager.damage_enemy(idx, 99999.0, _dash_dir, 0.0)
		return

	var dt := delta * 60.0

	if stun_timer > 0.0:
		velocity = knockback_vel
		knockback_vel *= pow(0.85, dt)
		return

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    input_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):  input_dir.y += 1.0
	if Input.is_action_pressed("move_left"):  input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0

	if input_dir.length_squared() > 1.0:
		input_dir = input_dir.normalized()

	velocity += input_dir * accel * dt
	velocity *= pow(FRICTION, dt)

	var spd_sq := velocity.length_squared()
	if spd_sq > max_speed * max_speed:
		velocity = velocity.normalized() * max_speed

	if absf(velocity.x) < SPEED_DEADZONE: velocity.x = 0.0
	if absf(velocity.y) < SPEED_DEADZONE: velocity.y = 0.0

func _clamp_to_world() -> void:
	var half := float(PLAYER_SIZE) * 0.5
	global_position.x = clampf(global_position.x, half, GameManager.WORLD_WIDTH  - half)
	global_position.y = clampf(global_position.y, half, GameManager.WORLD_HEIGHT - half)

# ── Aura ──────────────────────────────────────────────────────────

func _process_aura(delta: float) -> void:
	if aura_damage <= 0.0:
		return
	if not is_instance_valid(GameManager.enemy_manager):
		return

	var enemies_in_range = GameManager.enemy_manager.get_enemies_near_proxy(
		global_position, aura_radius)

	for idx in enemies_in_range:
		GameManager.enemy_manager.damage_enemy(idx, aura_damage * delta, Vector2.ZERO, 0.0, true)

	if aura_knockback > 0.0:
		_aura_pulse_timer += delta
		if _aura_pulse_timer >= aura_knockback_interval:
			_aura_pulse_timer = 0.0
			var pulse_targets = GameManager.enemy_manager.get_enemies_near_proxy(
				global_position, aura_radius)
			for idx in pulse_targets:
				var enemy_pos : Vector2 = GameManager.enemy_manager.positions[idx]
				var dir := (enemy_pos - global_position)
				if dir.length_squared() > 0.01:
					dir = dir.normalized()
				else:
					dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
				GameManager.enemy_manager.damage_enemy(idx, 0.0, dir, aura_knockback * 350.0, true)

# Sangrado continuo
func _process_blood_drip(delta: float) -> void:
	if bleed_intensity > 0.0:
		bleed_intensity -= 0.3 * delta * 60.0
		if bleed_intensity <= 0.0:
			bleed_intensity = 0.0
		else:
			bleed_cooldown -= delta * 60.0
			if bleed_cooldown <= 0.0:
				var particles = get_tree().get_first_node_in_group("blood_particles")
				if is_instance_valid(particles) and particles.has_method("create_blood_drip"):
					# Añadimos un pequeño desfase aleatorio para que el goteo sea natural
					var drip_pos = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
					particles.create_blood_drip(drip_pos, bleed_intensity)
				
				# A mayor herida, más rápido es el goteo
				bleed_cooldown = maxf(2.0, 20.0 - (bleed_intensity * 0.8))

# ── Dash ──────────────────────────────────────────────────────────

func _attempt_dash() -> void:
	if not dash_unlocked or stun_timer > 0.0:
		return
	if _dash_cd_timer > 0.0:
		_dash_buffer_timer = DASH_BUFFER_SECS
		return
	_execute_dash()

func _execute_dash() -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    input_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):  input_dir.y += 1.0
	if Input.is_action_pressed("move_left"):  input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0

	if input_dir.length_squared() > 0.01:
		_dash_dir = input_dir.normalized()
	else:
		_dash_dir = Vector2(cos(aim_angle), sin(aim_angle))

	dash_active        = true
	_dash_timer        = DASH_DURATION_BASE * dash_duration_mult
	_dash_cd_timer     = DASH_COOLDOWN_BASE * dash_cooldown_mult
	_dash_buffer_timer = 0.0
	_ghost_positions.clear()
	_ninja_hit_ids.clear()

# ── API pública ───────────────────────────────────────────────────

func take_damage(damage: float, hit_dir: Vector2 = Vector2.ZERO, kb_force: float = 0.0, stun_time: float = 0.0) -> void:
	if not is_alive or _invuln_timer > 0.0 or dash_active:
		return

	var actual_damage = damage * maxf(0.0, 1.0 - damage_reduction)
	health -= actual_damage
	
	_damage_flash_timer = DAMAGE_FLASH_SECS
	_invuln_timer       = INVULN_BASE_SECS * invulnerable_mult

	if stun_time > 0.0:
		stun_timer = stun_time

	if kb_force > 0.0 and hit_dir != Vector2.ZERO:
		knockback_vel = hit_dir.normalized() * kb_force

	emit_signal("health_changed", health, max_health)

	# --- SISTEMA DE SANGRE ---
	# Acumular intensidad para el goteo al caminar
	bleed_intensity = minf(50.0, bleed_intensity + actual_damage)
	
	var particles := get_tree().get_first_node_in_group("blood_particles")
	if is_instance_valid(particles):
		var dmg_ratio := clampf(actual_damage / max_health * 6.0, 0.0, 1.0)
		
		# Salpicadura en la dirección del impacto
		if particles.has_method("create_blood_splatter"):
			particles.create_blood_splatter(global_position, hit_dir, 1.2, 8, dmg_ratio)
			
		# Charco instantáneo si el daño es considerable
		if (actual_damage > 10.0 or dmg_ratio > 0.1) and particles.has_method("create_wound_stain"):
			particles.create_wound_stain(global_position, dmg_ratio)

	# --- LÓGICA DE MUERTE ---
	if health <= 0.0:
		health   = 0.0
		is_alive = false
		
		# Explosión visceral (dejando el charco grande)
		if is_instance_valid(particles) and particles.has_method("create_viscera_explosion"):
			# Usamos factor 1.0 para que la explosión del jugador sea dramática
			particles.create_viscera_explosion(global_position, 1.0)

		# Ocultar todos los nodos visuales del jugador para que "desaparezca"
		if is_instance_valid(_sprite): _sprite.visible = false
		if is_instance_valid(_aim_line): _aim_line.visible = false
		if is_instance_valid(_damage_flash): _damage_flash.visible = false
		if is_instance_valid(_dash_ghosts): _dash_ghosts.visible = false
		if is_instance_valid(_aura_visual): _aura_visual.visible = false
		
		emit_signal("died")

func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	emit_signal("health_changed", health, max_health)

func gain_experience(amount: int) -> bool:
	if not is_alive:
		return false
	var modified := maxi(1, int(float(amount) * xp_mult))
	experience += float(modified)
	var leveled := false
	while experience >= experience_next:
		experience        -= experience_next
		level             += 1
		pending_level_ups += 1
		experience_next    = int(experience_next * 1.2)
		leveled            = true
	if leveled:
		emit_signal("leveled_up")
	emit_signal("xp_changed", int(experience), int(experience_next))
	return leveled

func get_dash_cooldown_fraction() -> float:
	if not dash_unlocked:
		return 0.0
	var cd_max := DASH_COOLDOWN_BASE * dash_cooldown_mult
	if cd_max <= 0.0:
		return 1.0
	return 1.0 - clampf(_dash_cd_timer / cd_max, 0.0, 1.0)

# ── Sistema de armas ──────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_alive:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _switch_weapon(0)
			KEY_2: _switch_weapon(1)
			KEY_3: _switch_weapon(2)
			KEY_4: _switch_weapon(3)
			KEY_5: _switch_weapon(4)
			KEY_6: _switch_weapon(5)
			KEY_7: _switch_weapon(6)

func _switch_weapon(index: int) -> void:
	if _weapon_controller and index < _weapon_controller.equipped_weapons.size():
		current_weapon_index = index

func attack() -> bool:
	if not is_alive or dash_active or stun_timer > 0.0 or _shoot_block_timer > 0.0:
		return false
	if _weapon_controller:
		return _weapon_controller.attempt_shoot(current_weapon_index)
	return false

func add_weapon(weapon_file_name: String) -> void:
	if weapon_file_name in unlocked_weapon_names:
		return
	var path := "res://entities/weapons/%s.tres" % weapon_file_name
	var weapon_res: WeaponData = load(path) as WeaponData
	if not weapon_res:
		push_warning("add_weapon: no se encontró recurso en %s" % path)
		return
	if _weapon_controller:
		_weapon_controller.add_weapon(weapon_res)
		unlocked_weapon_names.append(weapon_file_name)
	else:
		push_error("Error: Player no tiene un nodo WeaponController!")
