extends Resource
class_name BossData

@export var boss_name      : String  = "Jefe"
@export var base_health    : float   = 1500.0
@export var base_damage    : int     = 40
@export var base_speed     : float   = 55.0
@export var size           : float   = 72.0
@export var color          : Color   = Color8(180, 30, 30)
@export var points         : int     = 500
@export var xp_reward      : int     = 200

## Sprite personalizado (opcional — deja null para usar color sólido)
@export var sprite_texture : Texture2D = null

@export var spawn_weight: float = 100.0 # Probabilidad/Peso de aparición