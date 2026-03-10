extends Resource
class_name WeaponData

enum WeaponType { PROJECTILE, HITSCAN_LASER }

@export var weapon_name: String = "Nueva Arma"
@export var type: WeaponType = WeaponType.PROJECTILE
@export var crosshair_type: int = 1

@export_group("Estadísticas Base")
@export var damage: float = 10.0
@export var cooldown: float = 60.0
@export var projectile_speed: float = 15.0
@export var projectile_speed_max: float = 15.0 # Si es mayor a la base, elige una velocidad al azar (Para la Escopeta 14 a 16)
@export var max_lifetime: float = 35.0

@export_group("Disparo Múltiple (Escopetas)")
@export var pellets: int = 1
@export var shotgun_spread: float = 0.0 # El '0.4' de tu escopeta

@export_group("Retroceso Dinámico (Rifle de Asalto)")
@export var base_spread: float = 0.0 # Ej: 0.05
@export var max_spread: float = 0.0  # Ej: 0.35
@export var spread_per_shot: float = 0.0 # Ej: 0.04
@export var spread_recovery: float = 0.0 # Ej: 0.01

@export_group("Características Especiales (Sniper)")
@export var use_swept_collision: bool = false # Chequeo de impacto perfecto por frame
@export var has_muzzle_flash: bool = false
@export var has_laser_sight: bool = false

@export_group("Efectos y Físicas")
@export var penetration: int = 1
@export var kickback: float = 0.0
@export var shake_amount: float = 0.0
@export var projectile_radius: float = 7.0

@export_group("Personalización Visual (Dibujado)")
@export var projectile_color: Color = Color.CYAN
@export var inner_color: Color = Color(1.0, 1.0, 0.8, 1.0)
@export var inner_radius_mult: float = 0.5
@export var fade_out: bool = false
@export var fade_multiplier: float = 1.0
@export var flicker_fire_effect: bool = false

@export_group("Características Especiales (Laser)")
@export var laser_thickness: float = 10.0

@export var projectile_scene: PackedScene