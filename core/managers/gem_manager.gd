## gem_manager.gd
## Gestor de gemas de experiencia — ProyectSurvivor (Godot 4)
##
## RESPONSABILIDADES:
##   · Referencia al contenedor de gemas (Node2D padre de todos los
##     nodos ExperienceGem).
##   · Merge periódico: cuando hay demasiadas gemas acumuladas en
##     el mismo punto, se fusionan en una sola con XP combinado.
##     Esto reduce el número de nodos activos y mejora el rendimiento,
##     replicando el comportamiento de Vampire Survivors.
##
## LÓGICA DE MERGE:
##   Cada MERGE_INTERVAL segundos, y solo cuando el conteo de gemas
##   supera MERGE_THRESHOLD, se ejecuta un sweepline O(n²) sobre
##   las gemas activas.  Dado que n es pequeño (< 500 típicamente)
##   y el intervalo es amplio (2 s), el coste es negligible.
##
## USO:
##   En gameplay.gd:
##       gem_manager.setup($World/Gems)
##   El nodo se autogestiona desde ese momento.

extends Node
class_name GemManager

# ════════════════════════════════════════════════════════════════
#  CONFIGURACIÓN
# ════════════════════════════════════════════════════════════════

## Segundos entre cada pasada de merge
const MERGE_INTERVAL   : float = 2.0

## Número mínimo de gemas para activar el merge
const MERGE_THRESHOLD  : int   = 35

## Distancia (px) en la que dos gemas se fusionan
const MERGE_RADIUS     : float = 22.0
const MERGE_RADIUS_SQ  : float = MERGE_RADIUS * MERGE_RADIUS

## Número máximo de gemas permitidas en escena antes de forzar
## un merge agresivo (radio aumentado ×2)
const HARD_CAP         : int   = 200

# ════════════════════════════════════════════════════════════════
#  ESTADO
# ════════════════════════════════════════════════════════════════

var _gems_container : Node   = null
var _merge_timer    : float  = 0.0

# ════════════════════════════════════════════════════════════════
#  INICIALIZACIÓN
# ════════════════════════════════════════════════════════════════

## Llamar desde gameplay.gd después de _ready.
func setup(container: Node) -> void:
	_gems_container = container

# ════════════════════════════════════════════════════════════════
#  PROCESO
# ════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not is_instance_valid(_gems_container):
		return

	_merge_timer += delta
	if _merge_timer < MERGE_INTERVAL:
		return
	_merge_timer = 0.0

	var gem_nodes := _gems_container.get_children()
	var count     := gem_nodes.size()

	if count < MERGE_THRESHOLD:
		return

	# Radio de merge agresivo si superamos el hard cap
	var effective_r_sq := MERGE_RADIUS_SQ
	if count >= HARD_CAP:
		effective_r_sq = MERGE_RADIUS_SQ * 4.0   # radio ×2

	_run_merge_pass(gem_nodes, effective_r_sq)

# ════════════════════════════════════════════════════════════════
#  MERGE PASS  O(n²) — aceptable con el intervalo amplio
# ════════════════════════════════════════════════════════════════

func _run_merge_pass(gems: Array, r_sq: float) -> void:
	var n      := gems.size()
	# Bitset de "ya absorbida" para evitar procesar nodos freed
	var absorbed := PackedByteArray()
	absorbed.resize(n)
	absorbed.fill(0)

	for i in range(n):
		if absorbed[i] == 1:
			continue
		var gem_a = gems[i]
		if not is_instance_valid(gem_a):
			absorbed[i] = 1
			continue

		var pos_a : Vector2 = gem_a.global_position

		for j in range(i + 1, n):
			if absorbed[j] == 1:
				continue
			var gem_b = gems[j]
			if not is_instance_valid(gem_b):
				absorbed[j] = 1
				continue

			var dx : float = pos_a.x - gem_b.global_position.x
			var dy : float = pos_a.y - gem_b.global_position.y
			if dx * dx + dy * dy <= r_sq:
				# gem_a absorbe a gem_b
				gem_a.merge_with(gem_b.xp_value)
				gem_b.queue_free()
				absorbed[j] = 1

# ════════════════════════════════════════════════════════════════
#  API PÚBLICA
# ════════════════════════════════════════════════════════════════

## Devuelve cuántas gemas hay actualmente en escena.
func get_gem_count() -> int:
	if not is_instance_valid(_gems_container):
		return 0
	return _gems_container.get_child_count()

## Fuerza atracción de TODAS las gemas (útil para items especiales
## como "aspirar todo" o upgrade de imán gigante).
func attract_all() -> void:
	if not is_instance_valid(_gems_container):
		return
	for gem in _gems_container.get_children():
		if is_instance_valid(gem) and gem.has_method("force_attract"):
			gem.force_attract()