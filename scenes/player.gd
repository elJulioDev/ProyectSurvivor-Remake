extends CharacterBody2D

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  player.gd — ProyectSurvivor
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

signal died
signal leveled_up
signal health_changed(current: float, maximum: float)
signal xp_changed(current: int, next_level: int)

const PLAYER_SIZE    := 20
const BASE_MAX_SPEED := 360.0
const BASE_ACCEL     := 60.0
const FRICTION       := 0.85
const SPEED_DEADZONE := 6.0

const DASH_DURATION_BASE := 12.0 / 60.0
const DASH_COOLDOWN_BASE := 45.0 / 60.0
const DASH_SPEED         := 1440.0
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
## Alias para compatibilidad con hud.gd
var experience_next_level : float :
	get: return experience_next
	set(v): experience_next = v
var pending_level_ups: int   = 0
var upgrade_counts   : Dictionary = {}
var xp_mult          : float = 1.0
var magnet_range_mult: float = 1.0
var magnet_speed_mult: float = 1.0
var xp_on_kill_bonus : int   = 0
var aura_damage      : float = 0.0
var aura_radius      : float = 80.0
var aura_knockback   : float = 0.0
var aura_knockback_interval: float = 4.0
var global_damage_mult    : float = 1.0
var global_cooldown_mult  : float = 1.0
var projectile_speed_mult : float = 1.0
var projectile_size_mult  : float = 1.0
var extra_penetration     : int   = 0
var knockback_mult        : float = 1.0
var lifesteal_chance      : float = 0.0
var lifesteal             : float = 5.0

# ── Estado interno ────────────────────────────────────────────────
var dash_unlocked      : bool  = true
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

@onready var _weapon_pivot: Node2D = get_node_or_null("WeaponPivot")

# ── Sistema de Armas ──────────────────────────────────────────────
## Referencia a active_weapons desde HUD (alias de weapons)
var weapons : Array[Node2D] :
	get: return active_weapons
var active_weapons  : Array[Node2D] = []
var passive_weapons : Array[Node2D] = []
var unlocked_weapon_names : Array[String] = []
var current_weapon_index  : int = 0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CICLO PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	add_to_group("player")
	# Auto-equipar pistola para poder testear sin upgrades
	add_weapon("PistolWeapon")
	add_weapon("Shotgunweapon")
	add_weapon("Assaultrifleweapon")
	add_weapon("Laserweapon")
	add_weapon("Sniperweapon")

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if Input.is_action_just_pressed("dash"):
		_attempt_dash()

	_update_aim()
	_update_timers(delta)
	_handle_movement(delta)
	_clamp_to_world()
	move_and_slide()
	_process_weapons(delta)

	# Disparo con click izquierdo
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		attack()

	queue_redraw()

# ── Apuntado ──────────────────────────────────────────────────────

func _update_aim() -> void:
	aim_angle = (get_global_mouse_position() - global_position).angle()
	if is_instance_valid(_weapon_pivot):
		_weapon_pivot.rotation = aim_angle

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

	if health_regen > 0.0 and health < max_health:
		health = minf(health + health_regen * delta, max_health)

	if emergency_regen > 0.0 and health < max_health * 0.25:
		health = minf(health + emergency_regen * delta, max_health)

# ── Movimiento ────────────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	if dash_active:
		if _ghost_positions.size() < MAX_GHOSTS:
			_ghost_positions.append({"pos": global_position, "angle": aim_angle})
		else:
			_ghost_positions.pop_front()
			_ghost_positions.append({"pos": global_position, "angle": aim_angle})
		velocity = _dash_dir * DASH_SPEED
		return

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    input_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):  input_dir.y += 1.0
	if Input.is_action_pressed("move_left"):  input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"): input_dir.x += 1.0

	if input_dir.length_squared() > 1.0:
		input_dir = input_dir.normalized()

	var dt := delta * 60.0

	velocity += input_dir * accel * dt
	velocity *= pow(FRICTION, dt)

	var spd_sq := velocity.length_squared()
	if spd_sq > max_speed * max_speed:
		velocity = velocity.normalized() * max_speed

	if absf(velocity.x) < SPEED_DEADZONE: velocity.x = 0.0
	if absf(velocity.y) < SPEED_DEADZONE: velocity.y = 0.0

func _clamp_to_world() -> void:
	var half := float(PLAYER_SIZE) * 0.5
	global_position.x = clampf(global_position.x, half, GameManager.WORLD_WIDTH - half)
	global_position.y = clampf(global_position.y, half, GameManager.WORLD_HEIGHT - half)

# ── Dash ──────────────────────────────────────────────────────────

func _attempt_dash() -> void:
	if not dash_unlocked:
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

func take_damage(damage: float) -> void:
	if not is_alive or _invuln_timer > 0.0 or dash_active:
		return
	health -= damage * maxf(0.0, 1.0 - damage_reduction)
	_damage_flash_timer = DAMAGE_FLASH_SECS
	_invuln_timer       = INVULN_BASE_SECS * invulnerable_mult
	emit_signal("health_changed", health, max_health)
	if health <= 0.0:
		health   = 0.0
		is_alive = false
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
	if index < active_weapons.size():
		current_weapon_index = index

func _process_weapons(delta: float) -> void:
	for w in active_weapons:
		if w.has_method("update_weapon"):
			w.update_weapon(delta)
	for pw in passive_weapons:
		if pw.has_method("update_weapon"):
			pw.update_weapon(delta)
		if pw.has_method("auto_shoot"):
			pw.auto_shoot(delta)

func attack() -> bool:
	if not is_alive or dash_active or active_weapons.is_empty():
		return false
	if current_weapon_index >= active_weapons.size():
		current_weapon_index = 0
	var w = active_weapons[current_weapon_index]
	if w.has_method("shoot"):
		return w.shoot()
	return false

func add_weapon(weapon_class_name: String) -> void:
	if weapon_class_name in unlocked_weapon_names:
		return

	# Buscar el script en la carpeta de armas
	var path := "res://scenes/weapons/%s.gd" % weapon_class_name
	if not ResourceLoader.exists(path):
		# Fallback: intentar en scripts/
		path = "res://scripts/entities/weapons/%s.gd" % weapon_class_name
	if not ResourceLoader.exists(path):
		push_warning("add_weapon: no se encontró %s" % weapon_class_name)
		return

	var script_res = load(path)
	var weapon_node := Node2D.new()
	weapon_node.set_script(script_res)
	weapon_node.name = weapon_class_name	
	# Solo asigna el jugador si el arma tiene la variable "owner_player"
	if "owner_player" in weapon_node:
		weapon_node.owner_player = self

	if is_instance_valid(_weapon_pivot):
		_weapon_pivot.add_child(weapon_node)
	else:
		add_child(weapon_node)

	unlocked_weapon_names.append(weapon_class_name)

	var passive_list := ["NovaWeapon", "OrbitalWeapon", "BoomerangWeapon"]
	if weapon_class_name in passive_list:
		passive_weapons.append(weapon_node)
	else:
		active_weapons.append(weapon_node)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DIBUJO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	if not is_alive:
		return

	var half := float(PLAYER_SIZE) * 0.5

	if _invuln_timer > 0.0 and _damage_flash_timer <= 0.0:
		if int(_invuln_timer * 60.0) % 6 < 3:
			return

	if dash_active and _ghost_positions.size() > 0:
		var n := _ghost_positions.size()
		for i in range(n):
			var g     : Dictionary = _ghost_positions[i]
			var alpha : float      = float(i) / float(max(1, n)) * (180.0 / 255.0)
			var lpos  : Vector2    = to_local(g["pos"])
			var gc    : Color      = Color(0.63, 0.0, 1.0, alpha) if ninja_dash \
								   else Color(1.0, 1.0, 1.0, alpha)
			draw_rect(Rect2(lpos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), gc)
			if alpha > 0.196:
				var ghost_tip := lpos + Vector2(cos(g["angle"]), sin(g["angle"])) * half * 2.5
				draw_line(lpos, ghost_tip, gc, 2.0)

	if ninja_dash and dash_unlocked:
		draw_rect(Rect2(Vector2(-half - 2.0, -half - 2.0),
						Vector2(half * 2.0 + 4.0, half * 2.0 + 4.0)),
				  Color(0.63, 0.0, 1.0), false, 2.0)

	var body_color := Color.WHITE
	if _damage_flash_timer > 0.0:
		var t := _damage_flash_timer / DAMAGE_FLASH_SECS
		body_color = Color(1.0, 1.0 - t, 1.0 - t)

	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), body_color)

	var tip := Vector2(cos(aim_angle), sin(aim_angle)) * (float(PLAYER_SIZE) * 1.0)
	draw_line(Vector2.ZERO, tip, body_color, 3.0)
