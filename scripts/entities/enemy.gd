extends Area2D
class_name Enemy

const TYPES = {
	"small": {
		"size_mult": 0.85, "health": 40.0, "speed_mult": 1.2, "damage": 6.0,
		"color": Color8(160, 240, 160), "points": 5, "special": null
	},
	"normal": {
		"size_mult": 1.0, "health": 90.0, "speed_mult": 1.0, "damage": 12.0,
		"color": Color8(70, 160, 70), "points": 10, "special": null
	},
	"large": {
		"size_mult": 1.5, "health": 220.0, "speed_mult": 0.72, "damage": 18.0,
		"color": Color8(30, 100, 30), "points": 20, "special": null
	},
	"tank": {
		"size_mult": 2.2, "health": 700.0, "speed_mult": 0.38, "damage": 30.0,
		"color": Color8(45, 65, 30), "points": 60, "special": null
	},
	"exploder": {
		"size_mult": 1.4, "health": 70.0, "speed_mult": 0.75, "damage": 0.0,
		"color": Color8(255, 80, 20), "points": 22, "special": "explode"
	},
	"spitter": {
		"size_mult": 1.1, "health": 110.0, "speed_mult": 0.75, "damage": 8.0,
		"color": Color8(80, 210, 50), "points": 30, "special": "spit"
	}
}

var enemy_type: String = "normal"
var is_alive: bool = true

# Stats calculadas
var max_health: float
var health: float
var damage: int
var base_speed: float
var points: int
var size: float
var color: Color

# Físicas y movimiento
var velocity: Vector2 = Vector2.ZERO
var knockback: Vector2 = Vector2.ZERO
var speed_variance: float = 1.0
var _lane: float = 0.0

var bleed_intensity: float = 0.0
var bleed_decay: float = 0.3
var bleed_drip_cooldown: float = 0.0

var splatter_cooldown: float = 0.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	speed_variance = randf_range(0.9, 1.1)
	add_to_group("enemies")

func initialize(pos: Vector2, type: String, speed_multiplier: float, health_mult: float, damage_mult: float) -> void:
	global_position = pos
	enemy_type = type
	is_alive = true
	
	var data = TYPES[type]
	size = GameManager.ENEMY_SIZE * data["size_mult"]
	color = data["color"]
	points = data["points"]
	
	max_health = data["health"] * health_mult
	health = max_health
	damage = maxi(1, int(data["damage"] * damage_mult))
	base_speed = GameManager.ENEMY_SPEED * speed_multiplier * data["speed_mult"]
	
	_lane = sin(pos.x * 0.0071 + pos.y * 0.0053)
	knockback = Vector2.ZERO
	
	# Ajustar hitbox
	var shape = RectangleShape2D.new()
	shape.size = Vector2(size + 10, size + 10) # size + padding
	collision_shape.shape = shape
	
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_alive: return

	if splatter_cooldown > 0.0:
		splatter_cooldown -= delta
	
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var dir = global_position.direction_to(player.global_position)
		var current_speed = base_speed * speed_variance
		
		# Movimiento básico + carril determinista
		var perp = Vector2(-dir.y, dir.x)
		var lateral_strength = 0.38 * current_speed
		var lane_vel = perp * _lane * lateral_strength
		
		var target_vel = (dir * current_speed) + lane_vel
		velocity = velocity.lerp(target_vel, 0.40)
	
	# Aplicar knockback con decay
	if knockback.length_squared() > 0.01:
		knockback *= pow(0.88, delta * 60)
		if knockback.length() < 0.1:
			knockback = Vector2.ZERO
			
	global_position += (velocity + knockback) * delta

	if bleed_intensity > 0:
		bleed_intensity -= bleed_decay * delta * 60.0
		if bleed_intensity < 0:
			bleed_intensity = 0.0
		else:
			bleed_drip_cooldown -= delta * 60.0
			if bleed_drip_cooldown <= 0:
				var particle_sys = get_tree().get_first_node_in_group("blood_particles")
				if particle_sys:
					var delay = max(2.0, 20.0 - (bleed_intensity * 0.8))
					particle_sys.create_blood_drip(global_position, bleed_intensity)
					bleed_drip_cooldown = delay

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO) -> bool:
	if not is_alive: return false
	
	health -= amount
	bleed_intensity = min(40.0, bleed_intensity + amount)
	
	if splatter_cooldown <= 0.0:
		var particle_sys = get_tree().get_first_node_in_group("blood_particles")
		if particle_sys:
			# Llamamos al splatter, pero con menos fuerza y cantidad (ej: count de 3)
			particle_sys.create_blood_splatter(global_position, hit_dir, 1.0, 3)
		# Darle un cooldown de 0.15 segundos antes de poder salpicar de nuevo
		splatter_cooldown = 0.15
		
	queue_redraw() 
	
	if health <= 0:
		health = 0
		die()
		return true
	return false

func die() -> void:
	is_alive = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	var particle_sys = get_tree().get_first_node_in_group("blood_particles")
	if particle_sys:
		particle_sys.create_viscera_explosion(global_position)
	
	var gameplay = get_tree().current_scene
	if gameplay.has_method("_on_enemy_killed"):
		gameplay._on_enemy_killed(self)
		
	queue_free()

func apply_knockback(source_pos: Vector2, force: float) -> void:
	var dir = source_pos.direction_to(global_position)
	var size_factor = 1.0 / TYPES[enemy_type]["size_mult"]
	knockback = dir * force * size_factor

func _draw() -> void:
	# Dibujo estilo rectángulos de tu código original
	var rect = Rect2(-size/2, -size/2, size, size)
	var border_color = color.darkened(0.2)
	
	draw_rect(rect, color)
	draw_rect(rect, border_color, false, 2.0)
	
	# Centro
	var center_size = max(2.0, size / 3.0)
	var center_rect = Rect2(-center_size/2, -center_size/2, center_size, center_size)
	draw_rect(center_rect, border_color)
	
	# Barra de vida
	if health < max_health:
		var bar_w = size
		var hp_w = (health / max_health) * bar_w
		var bar_y = (-size/2) - 7
		draw_rect(Rect2(-bar_w/2, bar_y, bar_w, 4), Color(0.2, 0, 0))
		var hp_color = Color(1, 0, 0) if health < max_health * 0.3 else Color(1, 0.4, 0)
		draw_rect(Rect2(-bar_w/2, bar_y, hp_w, 4), hp_color)