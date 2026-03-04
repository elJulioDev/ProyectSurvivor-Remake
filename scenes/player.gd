# scripts/entities/player.gd
extends CharacterBody2D
class_name Player

# ── Señales ──────────────────────────────────────────────────────────
signal died
signal leveled_up
signal health_changed(current: int, max_val: int)
signal xp_changed(current: int, needed: int)

# ── Stats base (equivalente a tu PlayerStats de pygame) ───────────────
var max_health: int   = 100
var health: int       = 100
var max_speed: float  = GameManager.PLAYER_SPEED
var acceleration: float = GameManager.PLAYER_ACCEL
var size: int         = GameManager.PLAYER_SIZE

# XP / nivel
var xp: int           = 0
var level: int        = 1
var xp_to_next: int   = 50       # igual a tu base_xp
const XP_SCALE: float = 1.35     # tu escala de curva

# Invencibilidad post-daño
var invincible: bool  = false
var invincible_timer: float = 0.0
const INVINCIBLE_DURATION: float = 0.8

# Dash (desbloqueado por upgrade)
var dash_unlocked: bool  = false
var dash_cooldown: float = 0.0
const DASH_DURATION: float  = 0.18
const DASH_SPEED: float     = 700.0
const DASH_COOLDOWN: float  = 1.2
var _dashing: bool          = false
var _dash_timer: float      = 0.0
var _dash_dir: Vector2      = Vector2.ZERO

# Colores del jugador
const COLOR_BODY   = Color(0.2, 0.5, 1.0)     # azul
const COLOR_BORDER = Color(0.05, 0.15, 0.5)
const COLOR_CENTER = Color(0.05, 0.15, 0.5)

# ── Referencias ───────────────────────────────────────────────────────
@onready var draw_node: Node2D      = $DrawNode
@onready var health_bar: Node2D     = $HealthBar
@onready var weapon_pivot: Node2D   = $WeaponPivot

# ── Ciclo de vida ─────────────────────────────────────────────────────
func _ready() -> void:
	draw_node.draw.connect(_on_draw_node_draw)
	health_bar.draw.connect(_on_health_bar_draw)
	# Spawn en centro del mundo
	position = Vector2(GameManager.WORLD_WIDTH / 2.0, GameManager.WORLD_HEIGHT / 2.0)
	# La cámara necesita seguirnos — se asigna desde gameplay.gd
	health_changed.emit(health, max_health)

func _process(delta: float) -> void:
	_handle_invincibility(delta)
	_handle_dash_cooldown(delta)
	draw_node.queue_redraw()
	health_bar.queue_redraw()
	# El WeaponPivot apunta al cursor (PC) o a la dirección de movimiento (móvil)
	_rotate_weapon_pivot()

func _physics_process(delta: float) -> void:
	if _dashing:
		_process_dash(delta)
	else:
		_process_movement(delta)
	move_and_slide()

# ── Movimiento ────────────────────────────────────────────────────────
func _process_movement(delta: float) -> void:
	var dir := _get_input_direction()

	if dir != Vector2.ZERO:
		# Aceleración suave — igual a tu lerp en pygame
		velocity = velocity.move_toward(dir * max_speed, acceleration * delta)
	else:
		# Fricción
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)

	# Dash input
	if Input.is_action_just_pressed("dash") and dash_unlocked and dash_cooldown <= 0.0:
		_start_dash(dir if dir != Vector2.ZERO else Vector2.RIGHT)

func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = Input.get_axis("move_left", "move_right")
	dir.y = Input.get_axis("move_up", "move_down")
	return dir.normalized()

func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	velocity = _dash_dir * DASH_SPEED
	if _dash_timer <= 0.0:
		_dashing = false
		invincible = false

func _start_dash(dir: Vector2) -> void:
	_dashing = true
	_dash_timer = DASH_DURATION
	_dash_dir = dir
	dash_cooldown = DASH_COOLDOWN
	invincible = true   # invencible durante el dash

func _handle_dash_cooldown(delta: float) -> void:
	if dash_cooldown > 0.0:
		dash_cooldown -= delta

func _rotate_weapon_pivot() -> void:
	# PC: apunta al ratón
	var mouse_pos := get_global_mouse_position()
	var angle := (mouse_pos - global_position).angle()
	weapon_pivot.rotation = angle

# ── Daño / salud ─────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if invincible:
		return
	health -= amount
	health = max(0, health)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
	else:
		invincible = true
		invincible_timer = INVINCIBLE_DURATION

func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)

func _handle_invincibility(delta: float) -> void:
	if invincible and not _dashing:
		invincible_timer -= delta
		if invincible_timer <= 0.0:
			invincible = false

func _die() -> void:
	died.emit()
	queue_free()

# ── XP / Nivel ────────────────────────────────────────────────────────
func gain_xp(amount: int) -> void:
	xp += amount
	xp_changed.emit(xp, xp_to_next)
	if xp >= xp_to_next:
		_level_up()

func _level_up() -> void:
	xp -= xp_to_next
	level += 1
	xp_to_next = int(xp_to_next * XP_SCALE)
	# Curar un poco al subir de nivel (igual que tu pygame)
	heal(int(max_health * 0.15))
	leveled_up.emit()
	xp_changed.emit(xp, xp_to_next)

# ── Aplicar upgrades (llamado desde UpgradeScene) ─────────────────────
func apply_upgrade(upgrade_id: String) -> void:
	if not UpgradesData.UPGRADES.has(upgrade_id):
		return
	var u: Dictionary = UpgradesData.UPGRADES[upgrade_id]
	match u["type"]:
		"unlock":
			if upgrade_id == "dash":
				dash_unlocked = true
		"stat":
			_apply_stat(u["stat_name"], u["value"])
		"weapon":
			# El WeaponManager lo maneja — emite señal o lo procesa gameplay.gd
			pass  # se expandirá con el sistema de armas

func _apply_stat(stat_name: String, value: float) -> void:
	match stat_name:
		"max_speed":   max_speed *= value
		"max_health":
			max_health = int(max_health * value)
			heal(int(max_health * 0.1))

# ── Dibujo procedural ─────────────────────────────────────────────────
func _on_draw_node_draw() -> void:
	var half := size / 2.0
	var alpha := 0.4 if (invincible and not _dashing) else 1.0  # parpadeo
	var body_color := Color(COLOR_BODY.r, COLOR_BODY.g, COLOR_BODY.b, alpha)

	# Cuerpo principal
	var rect := Rect2(Vector2(-half, -half), Vector2(size, size))
	draw_node.draw_rect(rect, body_color)
	draw_node.draw_rect(rect, COLOR_BORDER, false, 2)

	# Detalle central (equivalente a tu pygame sprite cacheado)
	var c: int = max(2, int(float(size) / 4.0))
	draw_node.draw_rect(
		Rect2(Vector2(-c / 2.0, -c / 2.0), Vector2(c, c)),
		COLOR_CENTER
	)

	# Indicador de dirección de movimiento
	if velocity.length() > 10.0:
		var dir := velocity.normalized() * (half + 4)
		draw_node.draw_circle(dir, 3.0, COLOR_BORDER)

func _on_health_bar_draw() -> void:
	# Barra de vida encima del jugador
	var bar_w := float(size + 6)
	var bar_h := 4.0
	var y_off := -size / 2.0 - 8.0
	var x_off := -bar_w / 2.0

	# Fondo
	health_bar.draw_rect(Rect2(Vector2(x_off, y_off), Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2))
	# Relleno (proporcional)
	var fill := bar_w * (float(health) / float(max_health))
	var hp_color := Color(0.1, 0.9, 0.1)  # verde → rojo según salud
	hp_color = Color(1.0 - (float(health) / float(max_health)), float(health) / float(max_health), 0.1)
	health_bar.draw_rect(Rect2(Vector2(x_off, y_off), Vector2(fill, bar_h)), hp_color)