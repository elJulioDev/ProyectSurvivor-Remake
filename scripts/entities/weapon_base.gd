extends Node2D
class_name WeaponBase

@export var cooldown: float = 60.0 # En frames o adaptado a segundos (cooldown / 60.0)
@export var damage: float = 10.0
@export var kickback: float = 0.0
@export var shake_amount: float = 0.0
@export var base_spread: float = 0.0

var current_cooldown: float = 0.0
var current_spread: float = base_spread

@onready var player = get_tree().get_first_node_in_group("player")

func update_weapon(delta: float) -> void:
	if current_cooldown > 0:
		# Lee el stat global de cooldown del jugador
		var cooldown_mult = player.global_cooldown_mult if "global_cooldown_mult" in player else 1.0
		# Adaptación de frames a delta time de Godot (asumiendo base 60fps)
		current_cooldown -= (1.0 * delta * 60.0) / cooldown_mult

	if current_spread > base_spread:
		current_spread -= 0.01 * delta * 60.0
		if current_spread < base_spread:
			current_spread = base_spread

func shoot() -> bool:
	if current_cooldown <= 0:
		if activate():
			current_cooldown = cooldown
			_apply_physics()
			# Aquí reproducirías el sonido de disparo
			return true
	return false

func _apply_physics() -> void:
	if kickback > 0 and player != null:
		# Aplica el retroceso empujando al jugador en dirección contraria al ángulo
		var angle = player.aim_angle
		player.velocity.x += -cos(angle) * kickback * 60.0
		player.velocity.y += -sin(angle) * kickback * 60.0
		
	if shake_amount > 0:
		# Lógica para llamar al shake de tu cámara
		pass

# Esta función debe ser sobrescrita por cada arma específica (Pistola, Escopeta, etc.)
func activate() -> bool:
	return false

# Lógica exclusiva para armas como OrbitalWeapon o NovaWeapon
func auto_shoot(delta: float) -> void:
	pass