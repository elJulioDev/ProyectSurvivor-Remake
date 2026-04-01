extends Resource
class_name CharacterData

# ════════════════════════════════════════════════════════════════════
#  CharacterData — Define un personaje jugable completo.
#  Cada personaje tiene su propio pool de armas: no comparte con otros.
# ════════════════════════════════════════════════════════════════════

@export var character_id   : String = "soldier"
@export var character_name : String = "Soldado"
@export var description    : String = "Equilibrado. Pistola y Escopeta disponibles."
## Color primario del sprite (usado en UI de selección)
@export var color          : Color  = Color(0.2, 0.8, 1.0)

# ── Stats base ────────────────────────────────────────────────────
@export_group("Stats Base")
@export var base_hp           : float = 100.0
@export var base_speed        : float = 200.0
@export var hp_mult           : float = 1.0
@export var speed_mult        : float = 1.0
@export var damage_mult       : float = 1.0
@export var cooldown_mult     : float = 1.0  # <1 = más rápido
@export var xp_mult           : float = 1.0

# ── Armas ────────────────────────────────────────────────────────
@export_group("Armas")
## Armas con las que empieza la run (nombres de .tres sin extensión)
@export var starting_weapons  : Array[String] = ["Pistol"]
## TODOS las armas que ESTE personaje puede desbloquear durante la run
## (incluye starting_weapons). Las upgrades se filtran a esta lista.
@export var available_weapons : Array[String] = ["Pistol", "Shotgun"]

# ── Pasiva de personaje ───────────────────────────────────────────
@export_group("Habilidad Pasiva")
## ID de la pasiva. Interpretado por player.gd en _apply_character_passive()
@export var passive_id        : String = ""
## Valor numérico que la pasiva puede usar (multiplicador, radio, etc.)
@export var passive_value     : float  = 0.0