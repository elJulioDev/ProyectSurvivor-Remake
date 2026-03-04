extends Area2D
class_name Enemy

const TYPES = {
	"small":    { "size_mult": 0.85, "health": 40.0,  "speed_mult": 1.2,  "damage": 6.0,  "color": Color8(160,240,160), "points": 5,  "special": null },
	"normal":   { "size_mult": 1.0,  "health": 90.0,  "speed_mult": 1.0,  "damage": 12.0, "color": Color8(70,160,70),   "points": 10, "special": null },
	"large":    { "size_mult": 1.5,  "health": 220.0, "speed_mult": 0.72, "damage": 18.0, "color": Color8(30,100,30),   "points": 20, "special": null },
	"tank":     { "size_mult": 2.2,  "health": 700.0, "speed_mult": 0.38, "damage": 30.0, "color": Color8(45,65,30),    "points": 60, "special": null },
	"exploder": { "size_mult": 1.4,  "health": 70.0,  "speed_mult": 0.75, "damage": 0.0,  "color": Color8(255,80,20),   "points": 22, "special": "explode" },
	"spitter":  { "size_mult": 1.1,  "health": 110.0, "speed_mult": 0.75, "damage": 8.0,  "color": Color8(80,210,50),   "points": 30, "special": "spit" },
}

var enemy_type: String = "normal"
var is_alive:   bool   = true

var max_health: float
var health:     float
var damage:     int
var base_speed: float
var points:     int
var size:       float
var color:      Color

var velocity:        Vector2 = Vector2.ZERO
var knockback:       Vector2 = Vector2.ZERO
var speed_variance:  float   = 1.0
var _lane:           float   = 0.0

# ── Sistema de sangre ────────────────────────────────────────────────────────
var bleed_intensity:      float = 0.0
var bleed_decay:          float = 0.3
var bleed_drip_cooldown:  float = 0.0
var splatter_cooldown:    float = 0.0

## Nivel de mancha acumulada en el cuerpo (0=limpio, 1=empapado)
## Sube con cada golpe y nunca baja — el enemigo queda más sangriento con la batalla.
var blood_stain:          float = 0.0

## Posiciones pre-calculadas de manchas en el cuerpo (espacio local, normalizadas)
var _body_stains:         Array = []   # Array de Vector2 en rango -0.5..0.5

var splatter_cooldown_max : float = 0.12

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	speed_variance = randf_range(0.9, 1.1)
	add_to_group("enemies")

func initialize(pos: Vector2, type: String,
				speed_multiplier: float, health_mult: float, damage_mult: float) -> void:
	global_position = pos
	enemy_type = type
	is_alive   = true
	blood_stain = 0.0
	_body_stains.clear()

	var data    = TYPES[type]
	size        = GameManager.ENEMY_SIZE * data["size_mult"]
	color       = data["color"]
	points      = data["points"]
	max_health  = data["health"] * health_mult
	health      = max_health
	damage      = maxi(1, int(data["damage"] * damage_mult))
	base_speed  = GameManager.ENEMY_SPEED * speed_multiplier * data["speed_mult"]
	_lane       = sin(pos.x * 0.0071 + pos.y * 0.0053)
	knockback   = Vector2.ZERO

	var shape = RectangleShape2D.new()
	shape.size = Vector2(size + 10, size + 10)
	collision_shape.shape = shape
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if splatter_cooldown > 0.0:
		splatter_cooldown -= delta

	var player = get_tree().get_first_node_in_group("player")
	if player:
		var dir          := global_position.direction_to(player.global_position)
		var current_speed := base_speed * speed_variance
		var perp          := Vector2(-dir.y, dir.x)
		var lane_vel      := perp * _lane * 0.38 * current_speed
		velocity           = velocity.lerp(dir * current_speed + lane_vel, 0.40)

	if knockback.length_squared() > 0.01:
		knockback *= pow(0.88, delta * 60)
		if knockback.length() < 0.1:
			knockback = Vector2.ZERO

	global_position += (velocity + knockback) * delta

	# Goteo de sangre
	if bleed_intensity > 0:
		bleed_intensity -= bleed_decay * delta * 60.0
		bleed_intensity  = maxf(bleed_intensity, 0.0)
		if bleed_intensity > 0.0:
			bleed_drip_cooldown -= delta * 60.0
			if bleed_drip_cooldown <= 0:
				var particle_sys = get_tree().get_first_node_in_group("blood_particles")
				if particle_sys:
					var delay := maxf(2.0, 20.0 - bleed_intensity * 0.8)
					particle_sys.create_blood_drip(global_position, bleed_intensity)
					bleed_drip_cooldown = delay

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO) -> bool:
	if not is_alive:
		return false

	health -= amount

	# Intensidad proporcional al daño relativo (0-1)
	var dmg_ratio := clampf(amount / maxf(max_health, 1.0) * 6.0, 0.0, 1.0)

	bleed_intensity = minf(40.0, bleed_intensity + amount)

	# Acumular mancha en el cuerpo
	_add_body_stain(hit_dir, dmg_ratio)

	# Salpicadura — con cooldown para no spamear y ajustada al daño
	if splatter_cooldown <= 0.0:
		var particle_sys = get_tree().get_first_node_in_group("blood_particles")
		if particle_sys:
			particle_sys.create_blood_splatter(
				global_position, hit_dir, 1.2, 8, dmg_ratio
			)
		splatter_cooldown = splatter_cooldown_max

	queue_redraw()

	if health <= 0:
		health = 0
		die()
		return true
	return false

## Añade una mancha de sangre en el cuerpo del enemigo en dirección al impacto.
func _add_body_stain(hit_dir: Vector2, dmg_ratio: float) -> void:
	# Acumular nivel de mancha global
	blood_stain = minf(1.0, blood_stain + dmg_ratio * 0.35)

	# Añadir posición de mancha localizada (máx 12 manchas para no saturar el draw)
	if _body_stains.size() < 12 and dmg_ratio > 0.1:
		var half := 0.4  # rango normalizado dentro del sprite
		# Posición semi-aleatoria sesgada hacia el lado del impacto
		var offset := Vector2(randf_range(-half, half), randf_range(-half, half))
		if hit_dir != Vector2.ZERO:
			offset = offset.lerp(hit_dir.normalized() * half * 0.5, 0.4)
		_body_stains.append({"local": offset, "r": dmg_ratio})

func die() -> void:
	is_alive = false
	set_deferred("monitoring",  false)
	set_deferred("monitorable", false)

	# Escalar la explosión con el tamaño del enemigo
	var size_mult: float = TYPES[enemy_type]["size_mult"] as float
	var particle_sys = get_tree().get_first_node_in_group("blood_particles")
	if particle_sys:
		particle_sys.create_viscera_explosion(global_position, size_mult)

	var gameplay = get_tree().current_scene
	if gameplay.has_method("_on_enemy_killed"):
		gameplay._on_enemy_killed(self)

	queue_free()

func apply_knockback(source_pos: Vector2, force: float) -> void:
	var dir         := source_pos.direction_to(global_position)
	var size_factor : float = 1.0 / TYPES[enemy_type]["size_mult"]
	knockback        = dir * force * size_factor

# ════════════════════════════════════════════════════════════════════════════
#  DIBUJO — cuerpo + barra de vida + manchas de sangre
# ════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	var half := size * 0.5
	var rect  := Rect2(-half, -half, size, size)
	var border_color := color.darkened(0.2)

	# Cuerpo base
	draw_rect(rect, color)
	draw_rect(rect, border_color, false, 2.0)

	# Centro oscuro
	var cs   := maxf(2.0, size / 3.0)
	var ch   := cs * 0.5
	draw_rect(Rect2(-ch, -ch, cs, cs), border_color)

	# ── Manchas de sangre en el cuerpo ──────────────────────────────────────
	if blood_stain > 0.0 and _body_stains.size() > 0:
		for stain_data in _body_stains:
			var local_off: Vector2 = stain_data["local"]
			var ratio:     float   = stain_data["r"]
			# Radio de la mancha proporcional al daño y al tamaño del enemigo
			var stain_r := maxf(2.0, size * 0.18 * ratio * (1.0 + blood_stain))
			var stain_pos := local_off * size
			# Capa exterior oscura (costra de sangre seca)
			draw_rect(Rect2(stain_pos - Vector2(stain_r, stain_r), Vector2(stain_r * 2, stain_r * 2)),
				Color(0.28, 0.0, 0.0, minf(0.85, blood_stain * 0.9)))
			# Núcleo brillante (sangre fresca)
			if ratio > 0.3:
				draw_rect(Rect2(stain_pos - Vector2(stain_r * 0.5, stain_r * 0.5), Vector2(stain_r, stain_r)),
					Color(0.65, 0.04, 0.04, minf(0.9, blood_stain)))

	# Overlay de sangre global cuando el enemigo está muy dañado
	if blood_stain > 0.4:
		var alpha := (blood_stain - 0.4) / 0.6 * 0.30
		draw_rect(rect, Color(0.35, 0.0, 0.0, alpha))

	# ── Barra de vida ────────────────────────────────────────────────────────
	if health < max_health:
		var bar_w := size
		var hp_w  := (health / max_health) * bar_w
		var bar_y := -half - 7.0
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 4.0), Color(0.2, 0, 0))
		var hp_col := Color(1, 0, 0) if health < max_health * 0.3 else Color(1, 0.4, 0)
		draw_rect(Rect2(-bar_w * 0.5, bar_y, hp_w, 4.0), hp_col)
