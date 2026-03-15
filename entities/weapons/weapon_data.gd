extends Resource
class_name WeaponData

enum WeaponType  { PROJECTILE, HITSCAN_LASER }

## Patrón de disparo para cada ráfaga individual.
## SINGLE      → comportamiento clásico (pellets en cono)
## RADIAL      → radial_count balas distribuidas 360°
## SPIRAL      → una bala por disparo, el ángulo rota spiral_angle_step grados cada vez
## ALTERNATING → alterna el punto de spawn entre dos "barriles" laterales
enum FirePattern { SINGLE, RADIAL, SPIRAL, ALTERNATING }

@export var weapon_name : String     = "Nueva Arma"
@export var type        : WeaponType = WeaponType.PROJECTILE
@export var crosshair_type : int     = 1

# ════════════════════════════════════════════════════════════════════
#  ESTADÍSTICAS BASE  (sin cambios)
# ════════════════════════════════════════════════════════════════════

@export_group("Estadísticas Base")
@export var damage              : float = 10.0
@export var cooldown            : float = 60.0
@export var projectile_speed    : float = 15.0
@export var projectile_speed_max: float = 15.0
@export var max_lifetime        : float = 35.0

@export_group("Disparo Múltiple (Escopetas)")
@export var pellets         : int   = 1
@export var shotgun_spread  : float = 0.0

@export_group("Retroceso Dinámico (Rifle de Asalto)")
@export var base_spread     : float = 0.0
@export var max_spread      : float = 0.0
@export var spread_per_shot : float = 0.0
@export var spread_recovery : float = 0.0

@export_group("Características Especiales (Sniper)")
@export var use_swept_collision : bool = false
@export var has_muzzle_flash    : bool = false
@export var has_laser_sight     : bool = false

@export_group("Efectos y Físicas")
@export var penetration    : int   = 1
@export var kickback       : float = 0.0
@export var shake_amount   : float = 0.0
@export var projectile_radius : float = 7.0

@export_group("Personalización Visual")
@export var projectile_color  : Color = Color.CYAN
@export var inner_color       : Color = Color(1.0, 1.0, 0.8, 1.0)
@export var inner_radius_mult : float = 0.5
@export var fade_out          : bool  = false
@export var fade_multiplier   : float = 1.0
@export var flicker_fire_effect : bool = false

@export_group("Características Especiales (Laser)")
@export var laser_thickness : float = 10.0

# ════════════════════════════════════════════════════════════════════
#  PATRÓN DE DISPARO
# ════════════════════════════════════════════════════════════════════

@export_group("Patrón de Disparo")

## Disparos consecutivos por activación del gatillo (burst fire).
## burst_count=3 → tres balas con burst_interval frames entre cada una.
@export var burst_count    : int   = 1
## Frames entre disparos dentro de un burst (@ 60fps). 4 = disparo cada 66ms.
@export var burst_interval : float = 4.0

## Patrón geométrico de cada ráfaga individual.
@export var fire_pattern   : FirePattern = FirePattern.SINGLE

## [RADIAL] Número de balas distribuidas uniformemente en 360°.
@export var radial_count   : int   = 8

## [SPIRAL] Grados que rota el ángulo base entre disparos consecutivos.
## 22.5° → 16 disparos para completar un giro completo.
@export var spiral_angle_step : float = 22.5

## [ALTERNATING] Distancia en px entre los dos "barriles" alternantes.
@export var alternating_offset : float = 12.0

# ════════════════════════════════════════════════════════════════════
#  SEGUIMIENTO (HOMING)
# ════════════════════════════════════════════════════════════════════

@export_group("Seguimiento (Homing)")

## Las balas persiguen al enemigo más cercano dentro del rango.
@export var is_homing : bool = false

## Velocidad de giro hacia el objetivo en grados/segundo.
## 90 = giro lento, 180 = medio, 360+ = muy agresivo.
@export var homing_strength : float = 180.0

## Frames de vuelo recto antes de activar el seguimiento.
## Evita que la bala gire sobre sí misma al salir del cañón.
@export var homing_delay_frames : float = 10.0

## Radio máximo (px) en que la bala detecta un objetivo.
@export var homing_range : float = 600.0

# ════════════════════════════════════════════════════════════════════
#  COMPORTAMIENTOS ESPECIALES
# ════════════════════════════════════════════════════════════════════

@export_group("Comportamientos Especiales")

## Veces que la bala rebota en los límites del mundo antes de expirar.
@export var bounces : int = 0

## Número de saltos de cadena tipo rayo al agotar penetraciones.
## 0 = sin cadena. 3 = encadena hasta 3 enemigos adicionales.
@export var chain_count      : int   = 0
## Radio (px) para buscar el siguiente eslabón de la cadena.
@export var chain_range      : float = 220.0
## Multiplicador de daño por cada salto. 0.65 = -35% por salto.
@export var chain_damage_mult: float = 0.65

## La bala explota al impactar o al expirar, dañando un área.
@export var explodes_on_impact     : bool  = false
@export var explosion_radius       : float = 90.0
## Multiplicador de daño de la explosión respecto al daño base.
@export var explosion_damage_mult  : float = 0.55

## La bala se divide en proyectiles secundarios al morir.
@export var splits_on_death : bool  = false
@export var split_count     : int   = 3
## Ángulo de apertura total del abanico en radianes. 1.2 ≈ 69°.
@export var split_spread    : float = 1.2

# ════════════════════════════════════════════════════════════════════
#  MOVIMIENTO DEL PROYECTIL
# ════════════════════════════════════════════════════════════════════

@export_group("Movimiento del Proyectil")

## Aceleración en px/s². Positivo = acelera, negativo = frena (como una granada).
## Ejemplo: 300 aumenta 300 px/s de velocidad por segundo.
@export var acceleration   : float = 0.0
## Velocidad máxima con aceleración activa (px/s). 0 = sin límite.
@export var max_speed_cap  : float = 0.0

## Amplitud del movimiento sinusoidal perpendicular a la trayectoria (px).
## 0 = línea recta, 20 = ondula ±20px. Crea patrones de zigzag/serpenteo.
@export var sine_amplitude : float = 0.0
## Frecuencia del ondulado en Hz (ciclos/segundo). 2 = 2 ondas por segundo.
@export var sine_frequency : float = 2.0

## Crecimiento del radio de colisión por segundo (px/s).
## Útil para balas que se expanden, como proyectiles de plasma o bolas de fuego.
@export var size_growth_rate : float = 0.0

# ════════════════════════════════════════════════════════════════════
#  EFECTOS DE ESTADO
##  Nota: requieren extensión de EnemyManager para efecto total.
##  Los arrays de datos ya se almacenan en ProjectileManager.
# ════════════════════════════════════════════════════════════════════

@export_group("Efectos de Estado (WIP — requiere EnemyManager)")

## Daño por segundo de quemadura aplicado al impactar. 0 = inactivo.
@export var burn_dps      : float = 0.0
## Duración de la quemadura en segundos.
@export var burn_duration : float = 3.0

## Factor de ralentización del objetivo (0 = sin efecto, 0.5 = 50% más lento).
@export var slow_factor   : float = 0.0
## Duración del ralentizamiento en segundos.
@export var slow_duration : float = 2.0