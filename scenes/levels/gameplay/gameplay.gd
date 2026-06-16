extends Node2D

# ── Referencias ──────────────────────────────────────────────────────
@onready var world:                  Node2D          = $World
@onready var camera:                 Camera2D        = $Camera2D
@onready var hud:                    Control         = $HUD/HUDControl
@onready var spawn_manager:          SpawnManager    = $SpawnManager
@onready var enemy_manager:          Node2D          = $EnemyManager
@onready var gem_manager:            GemManager      = $GemManager
@onready var upgrade_layer:          CanvasLayer     = $UpgradeLayer
@onready var projectile_manager:     ProjectileManager = $ProjectileManager
@onready var enemy_proj_manager : EnemyProjectileManager = $EnemyProjectileManager

# ── Boss ──────────────────────────────────────────────────────────
const BOSS_INTERVAL_SECS : float = 120.0   # 300.0 para 5 minutos
const BOSS_SPAWN_REDUCTION := 0.25         # spawn al 25% mientras hay boss

var _next_boss_time  : float = BOSS_INTERVAL_SECS
var _active_boss     : Node2D = null
var _pre_boss_cap    : float  = 1.0        # guarda el curse_factor original

# Pool dinámico que guardará las rutas de tus archivos .tres
var _boss_pool : Array[Dictionary] = []

# ── Estado ───────────────────────────────────────────────────────────
var score:     int   = 0
var enemies_killed: int = 0
var game_over: bool  = false
var game_time: float = 0.0

var player_ref: Node2D = null

var mobile_controls: CanvasLayer = null

## True mientras hay una pantalla de upgrade visible
var _upgrade_active: bool = false

## True mientras hay pausa activa
var _pause_active: bool = false

# ── Tabla de drop de gemas por tipo de enemigo ───────────────────────
## key = points del enemigo  → [xp_base, extra_gems_prob, extra_gems_max]
const GEM_DROP_TABLE : Dictionary = {
	5:  [3,  0.0,  0],   # small
	10: [6,  0.15, 1],   # normal
	20: [14, 0.30, 2],   # large
	60: [45, 0.60, 3],   # tank
	22: [15, 0.20, 1],   # exploder
	30: [20, 0.25, 2],   # spitter
}

# ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Registrar managers globales — deben estar disponibles ANTES de que
	# cualquier arma o enemigo intente disparar/dañar.
	GameManager.enemy_manager      = enemy_manager
	GameManager.projectile_manager = projectile_manager

	if not has_node("DamageNumberManager"):
		const DAMAGE_NUM_SCRIPT = preload("res://core/managers/damage_number_manager.gd")
		var dnm := DAMAGE_NUM_SCRIPT.new()
		dnm.name = "DamageNumberManager"
		call_deferred("add_child", dnm)
		GameManager.damage_numbers = dnm
	else:
		GameManager.damage_numbers = $DamageNumberManager

	spawn_manager.setup(enemy_manager)

	enemy_manager.enemy_killed.connect(_on_enemy_killed)
	enemy_manager.enemy_exploded.connect(_on_enemy_exploded)
	enemy_manager.enemy_shot.connect(_on_enemy_shot)

	_setup_camera()

	_load_boss_resources_automatically()

	player_ref = $World/Player
	if player_ref:
		player_ref.died.connect(_on_player_died)
		player_ref.leveled_up.connect(_on_player_leveled_up)

		player_ref.global_position = Vector2(
			GameManager.WORLD_WIDTH  / 2.0,
			GameManager.WORLD_HEIGHT / 2.0
		)

		if camera.has_method("snap_to_player"):
			camera.snap_to_player()

		camera.make_current()

	# Invocamos el setup usando la función global (muy útil si inicias con F6)
	setup({"is_mobile": GameManager.is_mobile()})

func _setup_camera() -> void:
	camera.limit_left   = 0
	camera.limit_top    = 0
	camera.limit_right  = GameManager.WORLD_WIDTH
	camera.limit_bottom = GameManager.WORLD_HEIGHT
	camera.position_smoothing_enabled = false

func _process(delta: float) -> void:
	if game_over:
		return

	game_time += delta
	
	# ── Chequeo de spawn de boss ──────────────────────────────────
	if not game_over and not is_instance_valid(_active_boss):
		if game_time >= _next_boss_time:
			_spawn_boss()
			
	_update_hud()

	var current_level := 1
	if player_ref and "level" in player_ref:
		current_level = player_ref.level

	if is_instance_valid(player_ref):
		var current_enemies : int = enemy_manager.get_active_count()
		spawn_manager.update_spawner(delta, current_enemies,
									 player_ref.global_position, current_level)

func _input(event: InputEvent) -> void:
	# Detectar Enter para pausar (y no mientras está upgrade abierto)
	if event.is_action_pressed("ui_accept") and not _upgrade_active and not _pause_active and not game_over:
		_show_pause_menu()
		get_tree().root.set_input_as_handled()

func _spawn_boss() -> void:
	var boss_scene := load("res://entities/boss/boss.tscn") as PackedScene
	if not boss_scene:
		push_error("gameplay.gd: no se encontró boss.tscn")
		return
		
	_active_boss = boss_scene.instantiate()
	add_child(_active_boss)

	var minutes     := game_time / 60.0
	var h_mult      := minf(5.5, 1.0 + maxf(0.0, minutes - 1.0) * 0.32)
	var d_mult      := 1.0 + float(maxi(0, (player_ref.level if player_ref else 1) - 1)) * 0.04
	var s_mult      := minf(2.2, 1.0 + maxf(0.0, minutes - 1.0) * 0.09)

	var p_pos := player_ref.global_position if is_instance_valid(player_ref) \
					else Vector2(GameManager.WORLD_WIDTH * 0.5, GameManager.WORLD_HEIGHT * 0.5)
	var angle := (p_pos - Vector2(GameManager.WORLD_WIDTH * 0.5,
									GameManager.WORLD_HEIGHT * 0.5)).angle() + PI
	var dist  := 800.0
	_active_boss.global_position = Vector2(
		clampf(p_pos.x + cos(angle) * dist, 100.0, GameManager.WORLD_WIDTH  - 100.0),
		clampf(p_pos.y + sin(angle) * dist, 100.0, GameManager.WORLD_HEIGHT - 100.0)
	)
	
	# ── SELECCIÓN DINÁMICA POR PROBABILIDAD PONDERADA ──
	var selected_path : String = ""
	
	if _boss_pool.is_empty():
		push_error("[Boss System] ¡CRÍTICO! No hay ningún Boss .tres en la carpeta res://entities/boss/")
		_active_boss.queue_free()
		return
	else:
		# Sumar todos los pesos (ej: 100 + 50 = 150)
		var total_weight := 0.0
		for b in _boss_pool:
			total_weight += b["weight"]
			
		# Tirar un número aleatorio entre 0 y el peso total
		var roll := randf_range(0.0, total_weight)
		var current := 0.0
		
		# Determinar en qué rango cayó la ruleta
		for b in _boss_pool:
			current += b["weight"]
			if roll <= current:
				selected_path = b["path"]
				break
				
		if selected_path == "":
			selected_path = _boss_pool[0]["path"] # Fallback de seguridad

	var boss_data := load(selected_path) as BossData
	
	if not boss_data:
		push_error("[Boss System] Fallo al cargar el recurso del boss: " + selected_path)
		boss_data = load(_boss_pool.pick_random()["path"]) as BossData

	# Ahora configuramos al boss con los datos reales
	_active_boss.setup(boss_data, h_mult, d_mult, s_mult)
	_active_boss.boss_died.connect(_on_boss_died)

	if is_instance_valid(player_ref):
		_pre_boss_cap = player_ref.get("curse_spawn_mult") \
					if "curse_spawn_mult" in player_ref else 1.0
		player_ref.set("curse_spawn_mult", _pre_boss_cap * BOSS_SPAWN_REDUCTION)
					
	print("[Boss System] Invocando jefe: %s en minuto %.1f" % [boss_data.boss_name, minutes])

func _on_boss_died(pos: Vector2, points: int, xp: int) -> void:
	score += points * 100
	_active_boss = null
	_next_boss_time = game_time + BOSS_INTERVAL_SECS   # próximo en 5 min/segs desde ahora

	# Restaurar spawn normal
	if is_instance_valid(player_ref):
		player_ref.set("curse_spawn_mult", _pre_boss_cap)

	# Gemas de recompensa (Fix de la advertencia INTEGER_DIVISION)
	if is_instance_valid(gem_manager):
		for _i in range(12):
			gem_manager.spawn_gem(pos, int(xp / 12.0), 2.0)
			
	print("[Boss] Derrotado. Próximo en %.0fs" % BOSS_INTERVAL_SECS)

# ════════════════════════════════════════════════════════════════
#  DROPS DE GEMA
# ════════════════════════════════════════════════════════════════

func _on_enemy_killed(pos: Vector2, points: int, _type_id: int) -> void:
	score += points * 100
	enemies_killed += 1
	_drop_gems(pos, points)

	if is_instance_valid(player_ref) and player_ref.is_alive:
		if player_ref.lifesteal_chance > 0.0:
			if randf() < player_ref.lifesteal_chance:
				player_ref.heal(player_ref.lifesteal)

		if "xp_on_kill_bonus" in player_ref and player_ref.xp_on_kill_bonus > 0:
			player_ref.gain_experience(player_ref.xp_on_kill_bonus)

func _drop_gems(pos: Vector2, points: int) -> void:
	var entry : Array = GEM_DROP_TABLE.get(points, [points, 0.15, 1])
	var xp_base    : int   = entry[0]
	var extra_prob : float = entry[1]
	var extra_max  : int   = entry[2]

	_spawn_gem(pos, xp_base)

	if extra_max > 0 and randf() < extra_prob:
		var extras   : int = randi_range(1, extra_max)
		var small_xp : int = maxi(1, int(xp_base * 0.3))
		for _i in range(extras):
			_spawn_gem(pos, small_xp)

func _spawn_gem(pos: Vector2, xp: int) -> void:
	gem_manager.spawn_gem(pos, xp)

# ════════════════════════════════════════════════════════════════
#  PANTALLA DE MEJORA
# ════════════════════════════════════════════════════════════════

func _on_player_leveled_up() -> void:
	if _upgrade_active:
		return
	_show_upgrade_screen()

func _show_upgrade_screen() -> void:
	if not is_instance_valid(player_ref):
		get_tree().paused = false
		return
	if player_ref.pending_level_ups <= 0:
		get_tree().paused = false
		return

	_upgrade_active   = true
	get_tree().paused = true

	# --- NUEVO: Ocultamos los joysticks y cancelamos el movimiento actual
	if is_instance_valid(mobile_controls):
		mobile_controls.hide_and_release()

	var upgrade_packed := load("res://ui/upgrade_screen/upgrade.tscn") as PackedScene
	if not upgrade_packed:
		push_error("gameplay.gd: no se encontró res://ui/upgrade_screen/upgrade.tscn")
		get_tree().paused = false
		_upgrade_active   = false
		return

	var upgrade_node := upgrade_packed.instantiate()
	upgrade_layer.add_child(upgrade_node)
	upgrade_node.setup(player_ref)

	upgrade_node.upgrade_selected.connect(
		func() -> void:
			upgrade_node.queue_free()
			player_ref.pending_level_ups -= 1
			_upgrade_active = false

			if player_ref.pending_level_ups > 0:
				await get_tree().process_frame
				_show_upgrade_screen()
			else:
				get_tree().paused = false
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
				
				# Aplicamos 0.25 segundos de bloqueo para que el arma ignore el clic de la UI
				if is_instance_valid(player_ref):
					player_ref._shoot_block_timer = 0.25
				
				# Volvemos a mostrar los joysticks al reanudar
				if is_instance_valid(mobile_controls):
					mobile_controls.show_controls()
	)

func _show_pause_menu() -> void:
	if not is_instance_valid(player_ref):
		return
	
	_pause_active = true
	get_tree().paused = true
	
	# Ocultamos los joysticks si existen
	if is_instance_valid(mobile_controls):
		mobile_controls.hide_and_release()
	
	var pause_packed := load("res://scenes/screens/pause/pause.tscn") as PackedScene
	if not pause_packed:
		push_error("gameplay.gd: no se encontró pause.tscn")
		get_tree().paused = false
		_pause_active = false
		return
	
	var pause_node := pause_packed.instantiate()
	upgrade_layer.add_child(pause_node)
	
	pause_node.continue_pressed.connect(
		func() -> void:
			_pause_active = false
			
			# Solo ocultamos el mouse al volver si NO estamos usando controles móviles
			if not is_instance_valid(mobile_controls):
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			else:
				mobile_controls.show_controls()
	)
	
	pause_node.main_menu_pressed.connect(
		func() -> void:
			_pause_active = false
			GameManager.goto_scene("res://scenes/screens/main_menu/menu.tscn", {})
	)

# ════════════════════════════════════════════════════════════════
#  CALLBACKS DE JUGADOR
# ════════════════════════════════════════════════════════════════

func _on_player_died() -> void:
	game_over = true
	await get_tree().create_timer(1.2).timeout
	GameManager.goto_scene("res://scenes/screens/game_over/game_over.tscn", {
		"score": score,
		"time":  _format_time(game_time),
	})

# ════════════════════════════════════════════════════════════════
#  HUD
# ════════════════════════════════════════════════════════════════

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.score         = score
	hud.enemies_killed = enemies_killed
	hud.wave_time_str = _format_time(game_time)

func _format_time(seconds: float) -> String:
	var m: int = floori(seconds / 60.0)
	var s: int = floori(fmod(seconds, 60.0))
	return "%02d:%02d" % [m, s]

func setup(data: Dictionary) -> void:

	if is_instance_valid(mobile_controls):
		return
	
	var is_mobile: bool = data.get("is_mobile", false)
	
	if is_mobile:
		var mc_path := "res://ui/hud/mobile_controls.tscn"
		var mc_packed : PackedScene
		
		# Intentar consumir el recurso precargado por loading.gd para máxima velocidad
		if ResourceLoader.has_cached(mc_path):
			mc_packed = ResourceLoader.load_threaded_get(mc_path) as PackedScene
		else:
			# Fallback normal (por si ejecutas gameplay.tscn directamente con F6)
			mc_packed = load(mc_path) as PackedScene
		
		if is_instance_valid(mc_packed):
			mobile_controls = mc_packed.instantiate()
			add_child(mobile_controls)
		else:
			push_error("No se pudo cargar mobile_controls.tscn")

# ════════════════════════════════════════════════════════════════
#  CALLBACKS DE HABILIDADES ESPECIALES
# ════════════════════════════════════════════════════════════════

func _on_enemy_exploded(pos: Vector2, damage: float, radius: float) -> void:
	# Sacudida de cámara proporcional al daño
	if camera.has_method("add_shake"):
		camera.add_shake(clampf(damage * 0.18, 4.0, 14.0))

	# Flash naranja de explosión (sistema de partículas / efecto visual)
	var particles := get_tree().get_first_node_in_group("blood_particles")
	if is_instance_valid(particles):
		# Usar viscera_explosion si existe, o añadir un método de explosión
		if particles.has_method("create_viscera_explosion"):
			particles.create_viscera_explosion(pos, radius / 40.0)

func _on_enemy_shot(pos: Vector2, angle: float) -> void:
	# Delegar al EnemyProjectileManager
	if is_instance_valid(enemy_proj_manager):
		enemy_proj_manager.spawn(pos, angle)

func _load_boss_resources_automatically() -> void:
	var folder_path := "res://entities/boss/"
	var dir := DirAccess.open(folder_path)
	
	if not dir:
		push_error("No se pudo acceder a la carpeta de bosses en: " + folder_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				var clean_name := file_name.replace(".remap", "")
				var full_path := folder_path + clean_name
				
				# Verificamos si ya existe para no duplicar
				var exists := false
				for b in _boss_pool:
					if b["path"] == full_path:
						exists = true
						break
						
				if not exists:
					var res = load(full_path)
					# Obtenemos el peso de aparición (por defecto 100 si no lo encuentra)
					var weight = res.get("spawn_weight") if res and "spawn_weight" in res else 100.0
					_boss_pool.append({"path": full_path, "weight": weight})
					
		file_name = dir.get_next()
	dir.list_dir_end()
	
	print("[Boss System] %d Jefes detectados para pool de probabilidad." % _boss_pool.size())
