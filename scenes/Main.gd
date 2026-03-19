extends Node

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/Main.gd — ProyectSurvivor
##
##  CAMBIO: Las escenas marcadas en LOADING_REQUIRED se cargan a través
##  de loading.tscn, que usa ResourceLoader.load_threaded_request() para
##  evitar el freeze al instanciar gameplay.tscn por primera vez.
##
##  Mecanismo anti-loop:
##    _skip_loading = true  →  la segunda llamada (desde loading.gd)
##    carga la escena directamente sin redirigir de nuevo.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@onready var scene_container: Node = $SceneContainer

## Escenas que requieren pantalla de carga previa.
const LOADING_REQUIRED : PackedStringArray = [
	"res://scenes/gameplay.tscn",
]

var _current_scene : Node = null

## Evita que la segunda llamada (desde loading.gd) vuelva a redirigir.
var _skip_loading : bool = false

func _ready() -> void:
	GameManager.scene_change_requested.connect(_on_scene_change)
	_load_scene("res://scenes/menu.tscn", {})

func _on_scene_change(path: String, data: Dictionary) -> void:
	call_deferred("_load_scene", path, data)

func _load_scene(path: String, data: Dictionary) -> void:
	# ── Limpiar escena anterior ────────────────────────────────────
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null

	# ── ¿Requiere pantalla de carga? ──────────────────────────────
	# Solo redirige si aún no estamos en medio de esa transición.
	if path in LOADING_REQUIRED and not _skip_loading:
		_skip_loading = true
		_load_via_loading_screen(path, data)
		return

	# Segunda llamada: viene de loading.gd con el recurso ya en caché.
	_skip_loading = false

	# ── Carga directa ─────────────────────────────────────────────
	var packed := load(path) as PackedScene
	if not packed:
		push_error("Main.gd: no se pudo cargar la escena: " + path)
		return

	_current_scene = packed.instantiate()
	scene_container.add_child(_current_scene)

	if _current_scene.has_method("setup"):
		_current_scene.setup(data)

	GameManager.current_scene_node = _current_scene

# ── Carga con loading.tscn como intermediario ─────────────────────

func _load_via_loading_screen(target_path: String, target_data: Dictionary) -> void:
	const LOADING_SCENE := "res://scenes/loading.tscn"

	var loading_packed := load(LOADING_SCENE) as PackedScene
	if not loading_packed:
		# Fallback: cargar directamente si no existe loading.tscn
		push_warning("Main.gd: no se encontró loading.tscn — cargando directo.")
		_skip_loading = false
		_load_scene(target_path, target_data)
		return

	_current_scene = loading_packed.instantiate()
	scene_container.add_child(_current_scene)

	if _current_scene.has_method("setup"):
		_current_scene.setup({"target": target_path, "data": target_data})

	GameManager.current_scene_node = _current_scene