extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/upgrade.gd — ProyectSurvivor v2
##
##  CAMBIOS vs v1:
##    · Sidebar izquierda con TODAS las mejoras activas + nivel/stacks
##    · Cada carta muestra "Nv. X" si ya la has elegido antes
##    · Barra de progreso de stacks (2/5) en la carta
##    · Soporte para type: "weapon_specific", "curse", "passive"
##    · Categorías nuevas con colores e iconos
##    · Roll ponderado mejorado: evita sub-categorías de arma repetidas
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

signal upgrade_selected

# ── Paleta de rareza ──────────────────────────────────────────────
const RARITY_COLORS := {
	"common":    Color8(160, 165, 175),
	"uncommon":  Color8( 80, 200,  80),
	"rare":      Color8( 60, 130, 255),
	"epic":      Color8(190,  60, 255),
	"legendary": Color8(255, 180,   0),
}
const RARITY_BG := {
	"common":    Color8(18,  19,  22),
	"uncommon":  Color8(13,  26,  13),
	"rare":      Color8(10,  14,  32),
	"epic":      Color8(22,   8,  32),
	"legendary": Color8(30,  20,   4),
}
const RARITY_LABEL := {
	"common":    "COMUN",
	"uncommon":  "POCO COMUN",
	"rare":      "RARO",
	"epic":      "EPICO",
	"legendary": "LEGENDARIO",
}
const RARITY_WEIGHTS := {
	"common":    50,
	"uncommon":  28,
	"rare":      14,
	"epic":       5,
	"legendary":  3,
}

# ── Paleta de categoría (expandida) ──────────────────────────────
const CATEGORY_COLOR := {
	"movement":       Color(0.000, 0.824, 1.000),
	"survival":       Color(1.000, 0.314, 0.314),
	"weapons":        Color(1.000, 0.784, 0.196),
	"xp":             Color(0.588, 0.314, 1.000),
	"curse":          Color(0.800, 0.100, 0.100),
	"weapon_pistol":  Color(0.000, 0.824, 0.824),
	"weapon_shotgun": Color(1.000, 0.549, 0.157),
	"weapon_rifle":   Color(1.000, 0.863, 0.275),
	"weapon_sniper":  Color(0.784, 1.000, 0.392),
	"weapon_laser":   Color(0.392, 0.706, 1.000),
	"weapon_nova":    Color(1.000, 0.400, 0.600),
	"weapon_skibidi": Color(1.000, 0.200, 0.800),
}

const CATEGORY_SHAPE := {
	"movement":  "arrow",
	"survival":  "cross",
	"weapons":   "diamond",
	"xp":        "gem",
	"curse":     "skull",
}

# ── Geometría de cartas ───────────────────────────────────────────
const CARD_W       := 265.0
const CARD_H       := 380.0
const CARD_GAP     :=  28.0
const CARDS_Y      := 170.0

# ── Sidebar de mejoras activas ────────────────────────────────────
const SIDEBAR_W    := 195.0
const SIDEBAR_X    :=  12.0
const SIDEBAR_Y    := 170.0
const SIDEBAR_ROW  :=  22.0

# ── Estado ────────────────────────────────────────────────────────
var VW := 1280.0
var VH :=  720.0

var _player        : Node  = null
var _options       : Array = []
var _hovered_idx   : int   = -1
var _hover_scales  : Array = [1.0, 1.0, 1.0]
var _anim_timer    : float = 0.0
var _fade_alpha    : float = 255.0
var _fade_speed    : float = 14.0
var _input_cooldown: float = 0.55
var _cards_start_x : float = 0.0
var _font          : Font
var _sidebar_scroll: float = 0.0   # Para cuando hay muchas mejoras

# ── Touch móvil ───────────────────────────────────────────────────
var _touch_pressed_idx : int   = -1   # Carta donde empezó el toque
var _touch_id          : int   = -1   # Finger ID activo
var _touch_start_pos   : Vector2 = Vector2.ZERO
const TOUCH_DRAG_THRESHOLD := 20.0   # px — si arrastra más, cancela

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func setup(player: Node) -> void:
	_player = player
	var vp := get_viewport_rect().size
	VW = vp.x; VH = vp.y
	_recalc_layout()
	_options = _select_upgrades()

func _recalc_layout() -> void:
	var total_w := CARD_W * 3.0 + CARD_GAP * 2.0
	# Desplazar cartas un poco a la derecha para dejar espacio a la sidebar
	var sidebar_offset := SIDEBAR_W * 0.35
	_cards_start_x = (VW - total_w) * 0.5 + sidebar_offset

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PROCESO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	VW = vp.x; VH = vp.y
	_recalc_layout()

	var dt := delta * 60.0
	_anim_timer += 0.04 * dt

	if _fade_alpha > 0.0:
		_fade_alpha = maxf(0.0, _fade_alpha - _fade_speed * dt)

	if _input_cooldown > 0.0:
		_input_cooldown -= delta

	var mp := get_local_mouse_position()
	_hovered_idx = -1
	for i in range(_options.size()):
		if _get_card_rect(i).has_point(mp):
			_hovered_idx = i

	for i in range(_options.size()):
		var target := 1.045 if (i == _hovered_idx or i == _touch_pressed_idx) else 1.0
		_hover_scales[i] += (target - _hover_scales[i]) * 0.15 * dt
		_hover_scales[i]  = clampf(_hover_scales[i], 0.98, 1.06)

	queue_redraw()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _unhandled_input(event: InputEvent) -> void:
	if _input_cooldown > 0.0:
		return

	# ── Touch móvil (pantalla táctil) ─────────────────────────────
	if event is InputEventScreenTouch:
		if event.pressed:
			# Registrar la carta bajo el dedo en el momento del toque
			if _touch_id == -1:
				_touch_id        = event.index
				_touch_start_pos = event.position
				var local_pos : Vector2 = get_global_transform().affine_inverse() * event.position
				_touch_pressed_idx = -1
				for i in range(_options.size()):
					if _get_card_rect(i).has_point(local_pos):
						_touch_pressed_idx = i
						break
		else:
			# Finger levantado — confirmar solo si es el mismo dedo
			# y no hubo arrastre excesivo
			if event.index == _touch_id:
				var drag_dist : float = event.position.distance_to(_touch_start_pos)
				if _touch_pressed_idx >= 0 and drag_dist < TOUCH_DRAG_THRESHOLD:
					_confirm(_touch_pressed_idx)
				_touch_id          = -1
				_touch_pressed_idx = -1
		return

	# ── Arrastre táctil (cancelar si se movió mucho) ──────────────
	if event is InputEventScreenDrag:
		if event.index == _touch_id:
			var drag_dist : float = event.position.distance_to(_touch_start_pos)
			if drag_dist >= TOUCH_DRAG_THRESHOLD:
				_touch_pressed_idx = -1   # Cancela la selección
		return

	# ── Mouse (PC / emulación) ────────────────────────────────────
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_idx >= 0:
				_confirm(_hovered_idx)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_sidebar_scroll = maxf(0.0, _sidebar_scroll - SIDEBAR_ROW * 2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_sidebar_scroll += SIDEBAR_ROW * 2
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: if _options.size() >= 1: _confirm(0)
			KEY_2: if _options.size() >= 2: _confirm(1)
			KEY_3: if _options.size() >= 3: _confirm(2)

func _confirm(idx: int) -> void:
	_apply_upgrade(_options[idx])
	upgrade_selected.emit()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SELECCIÓN DE MEJORAS (ROLL)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _select_upgrades() -> Array:
	if not is_instance_valid(_player):
		return []

	# ── Cache del pool de armas del personaje actual ──────────────
	# Si no hay character_data (ej: primera versión sin selección),
	# se permite todo para no romper partidas en curso.
	var char_weapon_pool : Array[String] = []
	var has_char_filter  : bool = false
	if is_instance_valid(_player.character_data):
		char_weapon_pool = _player.character_data.available_weapons
		has_char_filter  = true

	var available_keys    : Array = []
	var available_weights : Array = []

	for key in UpgradesData.UPGRADES:
		var upg : Dictionary = UpgradesData.UPGRADES[key]

		if not _check_requires(upg.get("requires", null)):
			continue

		# ── Filtro de desbloqueo de arma ──────────────────────────
		if upg["type"] == "unlock_weapon":
			var weapon_class := upg["weapon_class"] as String
			# Ya la tiene equipada
			if weapon_class in _player.unlocked_weapon_names:
				continue
			# NUEVO: ¿está en el pool de este personaje?
			if has_char_filter and weapon_class not in char_weapon_pool:
				continue

		# ── Filtro de mejora de arma específica ───────────────────
		elif upg["type"] == "weapon_specific":
			var weapon_target := upg.get("weapon_target", "") as String
			# NUEVO: si el personaje no puede tener esta arma, ocultar su mejora
			if has_char_filter and weapon_target not in char_weapon_pool:
				continue

		# ── Desbloqueos únicos (dash, etc.) ───────────────────────
		elif upg["type"] == "unlock" and key == "dash":
			if _player.dash_unlocked:
				continue

		# ── Límite de stacks (sin cambios) ────────────────────────
		var max_stacks = upg.get("max_stacks", null)
		if max_stacks != null:
			if _player.upgrade_counts.get(key, 0) >= max_stacks:
				continue
		if not upg.get("stackable", false):
			if _player.upgrade_counts.get(key, 0) >= 1:
				continue

		available_keys.append(key)
		var rarity : String = upg.get("rarity", "common")
		available_weights.append(RARITY_WEIGHTS.get(rarity, 20))

	# Elegir 3 evitando misma base_category
	var chosen     : Array = []
	var used_cats  : Dictionary = {}
	var keys_cp    := available_keys.duplicate()
	var weights_cp := available_weights.duplicate()
	var attempts   := 0

	while chosen.size() < 3 and keys_cp.size() > 0 and attempts < 60:
		attempts += 1
		var idx := _weighted_random_pick(weights_cp)
		if idx < 0: break
		var key : String = keys_cp[idx]
		var cat : String = UpgradesData.UPGRADES[key].get("category", "")
		var base_cat := UpgradesData.get_base_category(cat)
		if not (base_cat in used_cats) or attempts > 30:
			chosen.append(key)
			used_cats[base_cat] = true
		keys_cp.remove_at(idx)
		weights_cp.remove_at(idx)

	# Fallback stackables
	while chosen.size() < 3:
		var valid : Array = []
		for key in UpgradesData.UPGRADES:
			if key in chosen: continue
			var v : Dictionary = UpgradesData.UPGRADES[key]
			if not v.get("stackable", false): continue
			if not _check_requires(v.get("requires", null)): continue
			var ms = v.get("max_stacks", null)
			var cur : int = _player.upgrade_counts.get(key, 0)
			if ms == null or cur < ms:
				valid.append(key)
		if valid.size() > 0:
			chosen.append(valid[randi() % valid.size()])
		else:
			break

	return chosen.slice(0, 3)

func _check_requires(req) -> bool:
	if req == null or req == "":
		return true
	# Per-weapon requirement: "has_weapon:Shotgun"
	if typeof(req) == TYPE_STRING and (req as String).begins_with("has_weapon:"):
		var weapon_name : String = (req as String).substr(11)
		return weapon_name in _player.unlocked_weapon_names
	match req:
		"dash_unlocked":
			return bool(_player.dash_unlocked)
		"aura_unlocked":
			return float(_player.get("aura_damage")) > 0.0
		"aura_knockback_unlocked":
			return float(_player.get("aura_knockback")) > 0.0
		"ninja_dash_ready":
			return bool(_player.dash_unlocked) \
				and _player.upgrade_counts.get("dash_cooldown", 0) >= 3
	if req in _player:
		return bool(_player.get(req))
	return false

func _weighted_random_pick(weights: Array) -> int:
	var total := 0
	for w in weights: total += w
	if total <= 0: return -1
	var roll := randi() % total
	var acc  := 0
	for i in range(weights.size()):
		acc += weights[i]
		if roll < acc: return i
	return weights.size() - 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  APLICAR MEJORA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _apply_upgrade(key: String) -> void:
	if not is_instance_valid(_player):
		return

	var upg   : Dictionary = UpgradesData.UPGRADES[key]
	var utype : String     = upg["type"]
	_player.upgrade_counts[key] = _player.upgrade_counts.get(key, 0) + 1

	match utype:
		"unlock":
			if key == "dash":
				_player.dash_unlocked = true

		"unlock_weapon":
			_player.add_weapon(upg["weapon_class"] as String)

		"stat":
			_apply_stat(upg["stat_name"], upg["value"])

		"weapon":
			_apply_weapon_stat(upg["stat_name"], upg["value"])

		"weapon_specific":
			_apply_weapon_specific(upg)

		"xp":
			_apply_xp_stat(upg["stat_name"], upg["value"])

		"passive":
			_apply_passive(upg["stat_name"], upg["value"])

		"curse":
			_apply_curse(upg)

	print("✅ Mejora: [%s] %s (x%d)" % [
		(upg.get("rarity", "?") as String).to_upper(),
		upg["name"],
		_player.upgrade_counts.get(key, 1)
	])

func _apply_stat(sname: String, val) -> void:
	match sname:
		"max_speed":
			_player.max_speed *= val
			_player.accel     *= val
		"max_health":
			_player.max_health += val
			_player.health      = minf(_player.health + val, _player.max_health)
		"health_regen":
			_player.health_regen += val
		"damage_reduction":
			_player.damage_reduction = minf(0.60, _player.damage_reduction + float(val))
		"lifesteal_chance":
			_player.lifesteal_chance = minf(1.0, _player.lifesteal_chance + float(val))
		"emergency_regen":
			_player.emergency_regen += val
		"invulnerable_mult":
			_player.invulnerable_mult *= val
		"dash_cooldown":
			_player.dash_cooldown_mult = _player.dash_cooldown_mult * float(val)
		"dash_duration":
			_player.dash_duration_mult = _player.dash_duration_mult * float(val)
		"ninja_dash":
			_player.ninja_dash = true
		"aura_damage":
			_player.aura_damage += val
		"aura_radius":
			_player.aura_radius += val
		"aura_damage_mult":
			_player.aura_damage *= val
		"aura_knockback":
			_player.aura_knockback = float(val)
			if not ("aura_knockback_interval" in _player) \
					or float(_player.aura_knockback_interval) <= 0.0:
				_player.aura_knockback_interval = 4.0
		"aura_knockback_interval":
			var ak_int = _player.get("aura_knockback_interval")
			var cur : float = float(ak_int) if ak_int != null else 4.0
			_player.aura_knockback_interval = maxf(1.0, cur + float(val))

func _apply_weapon_stat(sname: String, val) -> void:
	match sname:
		"global_damage_mult":    _player.global_damage_mult    *= val
		"global_cooldown_mult":  _player.global_cooldown_mult  *= val
		"projectile_speed_mult": _player.projectile_speed_mult *= val
		"extra_penetration":     _player.extra_penetration     += int(val)
		"projectile_size_mult":  _player.projectile_size_mult  *= val
		"knockback_mult":        _player.knockback_mult        *= val

func _apply_xp_stat(sname: String, val) -> void:
	match sname:
		"magnet_range_mult":  _player.magnet_range_mult *= val
		"xp_mult":            _player.xp_mult           *= val
		"xp_on_kill_bonus":   _player.xp_on_kill_bonus  += int(val)
		"magnet_speed_mult":  _player.magnet_speed_mult *= val

## Aplica mejora pasiva (gem_xp_mult, extra_gem_chance, etc.)
func _apply_passive(sname: String, val) -> void:
	match sname:
		"gem_xp_mult":
			_player.gem_xp_mult = float(val)
		"extra_gem_chance_bonus":
			_player.extra_gem_chance_bonus = _player.get("extra_gem_chance_bonus") \
				if "extra_gem_chance_bonus" in _player else 0.0
			_player.extra_gem_chance_bonus += float(val)

## Aplica mejora per-weapon directamente sobre el WeaponData duplicado
func _apply_weapon_specific(upg: Dictionary) -> void:
	var target_name : String = upg["weapon_target"]
	var sname       : String = upg["stat_name"]
	var val                  = upg["value"]
	var mode        : String = upg.get("apply_mode", "multiply")

	# Buscar el WeaponData en el WeaponController
	var wc = _player.get_node_or_null("WeaponPivot/WeaponController")
	if not is_instance_valid(wc):
		return

	for weapon in wc.equipped_weapons:
		# WeaponData.weapon_name o el nombre del recurso
		var wname : String = ""
		if "weapon_name" in weapon:
			wname = weapon.weapon_name
		if wname == "" and weapon.resource_path != "":
			wname = weapon.resource_path.get_file().get_basename()

		if wname == target_name:
			var current = weapon.get(sname)
			if current == null:
				push_warning("weapon_specific: '%s' no tiene propiedad '%s'" % [target_name, sname])
				return
			if mode == "multiply":
				weapon.set(sname, current * val)
			else: # "add"
				weapon.set(sname, current + val)
			return

## Aplica maldición: penalty + bonus
func _apply_curse(upg: Dictionary) -> void:
	var sname : String = upg["stat_name"]
	var val            = upg["value"]

	# Aplicar la maldición al jugador (SpawnManager la lee)
	match sname:
		"curse_spawn_mult":
			_player.curse_spawn_mult = _player.get("curse_spawn_mult") \
				if "curse_spawn_mult" in _player else 1.0
			_player.curse_spawn_mult *= float(val)
		"curse_health_mult":
			_player.curse_health_mult = _player.get("curse_health_mult") \
				if "curse_health_mult" in _player else 1.0
			_player.curse_health_mult *= float(val)
		"curse_speed_mult":
			_player.curse_speed_mult = _player.get("curse_speed_mult") \
				if "curse_speed_mult" in _player else 1.0
			_player.curse_speed_mult *= float(val)
		"curse_elite_mult":
			_player.curse_elite_mult = _player.get("curse_elite_mult") \
				if "curse_elite_mult" in _player else 1.0
			_player.curse_elite_mult *= float(val)

	# Aplicar el bonus asociado
	var bonus_stat  : String = upg.get("bonus_stat", "")
	var bonus_value          = upg.get("bonus_value", 1.0)
	if bonus_stat != "":
		match bonus_stat:
			"xp_mult":
				_player.xp_mult *= float(bonus_value)
			"global_damage_mult":
				_player.global_damage_mult *= float(bonus_value)
			"max_speed":
				_player.max_speed *= float(bonus_value)
				_player.accel     *= float(bonus_value)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  RENDER PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.84))

	_draw_title()
	_draw_subtitle()
	_draw_active_upgrades_sidebar()

	for i in range(_options.size()):
		_draw_card(i, _options[i])

	if _fade_alpha > 0.5:
		draw_rect(Rect2(0.0, 0.0, VW, VH),
				  Color(0.0, 0.0, 0.0, _fade_alpha / 255.0))

func _draw_title() -> void:
	if not is_instance_valid(_player): return
	var glow_t  : float = absf(sin(_anim_timer))
	var glow_val: float = glow_t * 40.0 + 180.0
	var tcol     := Color(1.0, glow_val / 255.0, 40.0 / 255.0)
	var title    := "NIVEL %d ALCANZADO" % _player.level
	var cx       := VW * 0.5 + SIDEBAR_W * 0.15
	_text_center(title, Vector2(cx + 3.0, 68.0), 44,
				 Color(0.314, 0.157, 0.0, 0.75))
	_text_center(title, Vector2(cx, 65.0), 44, tcol)

func _draw_subtitle() -> void:
	var cx := VW * 0.5 + SIDEBAR_W * 0.15
	_text_center(
		"Elige una mejora   |   Teclas  1   2   3",
		Vector2(cx, 128.0), 17,
		Color(0.392, 0.412, 0.471)
	)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SIDEBAR — MEJORAS ACTIVAS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw_active_upgrades_sidebar() -> void:
	if not is_instance_valid(_player): return
	if _player.upgrade_counts.is_empty(): return

	var sx := SIDEBAR_X
	var sy := SIDEBAR_Y
	var sw := SIDEBAR_W

	# Fondo del panel
	var entries := _get_sorted_upgrade_entries()
	var panel_h := maxf(40.0, 32.0 + entries.size() * SIDEBAR_ROW + 8.0)
	var max_h   := VH - sy - 30.0
	panel_h = minf(panel_h, max_h)

	draw_rect(Rect2(sx, sy, sw, panel_h), Color(0.04, 0.04, 0.06, 0.92))
	draw_rect(Rect2(sx, sy, sw, panel_h), Color(0.25, 0.25, 0.35, 0.5), false, 1.0)

	# Título
	_text(
		"MEJORAS ACTIVAS", Vector2(sx + 8.0, sy + 6.0), 13,
		Color(0.6, 0.6, 0.7)
	)
	draw_line(
		Vector2(sx + 8.0, sy + 26.0),
		Vector2(sx + sw - 8.0, sy + 26.0),
		Color(0.3, 0.3, 0.4, 0.5), 1.0
	)

	# Entradas
	var row_y := sy + 32.0 - _sidebar_scroll
	var clip_top := sy + 28.0
	var clip_bot := sy + panel_h - 4.0

	for entry in entries:
		if row_y < clip_top - SIDEBAR_ROW:
			row_y += SIDEBAR_ROW
			continue
		if row_y > clip_bot:
			break

		var upg    : Dictionary = UpgradesData.UPGRADES[entry.key]
		var rarity : String = upg.get("rarity", "common")
		var rc     : Color = RARITY_COLORS.get(rarity, Color8(150, 150, 150))
		var cat    : String = upg.get("category", "")
		var cc     : Color = CATEGORY_COLOR.get(cat, Color(0.5, 0.5, 0.5))

		# Indicador de color de categoría (bolita)
		draw_circle(Vector2(sx + 14.0, row_y + 9.0), 4.0, cc)

		# Nombre (truncado)
		var name_str : String = upg["name"]
		if name_str.length() > 14:
			name_str = name_str.substr(0, 13) + ".."
		_text(name_str, Vector2(sx + 22.0, row_y), 13, rc)

		# Stack info a la derecha
		var max_stacks = upg.get("max_stacks", null)
		var stack_str  : String
		if max_stacks != null:
			stack_str = "%d/%d" % [entry.count, max_stacks]
		elif upg.get("stackable", false):
			stack_str = "x%d" % entry.count
		else:
			stack_str = "✓"

		_text_right(stack_str, sx + sw - 8.0, row_y + 1.0, 12, Color(0.7, 0.7, 0.8))

		row_y += SIDEBAR_ROW

	# Scroll indicator
	if entries.size() * SIDEBAR_ROW > panel_h - 36.0:
		var indicator_col := Color(1, 1, 1, 0.3 + abs(sin(_anim_timer * 2.0)) * 0.2)
		_text_center("▼ scroll ▼", Vector2(sx + sw * 0.5, sy + panel_h - 14.0),
					 11, indicator_col)

## Devuelve las mejoras activas ordenadas por categoría
func _get_sorted_upgrade_entries() -> Array:
	var entries : Array = []
	for key in _player.upgrade_counts:
		var count : int = _player.upgrade_counts[key]
		if count <= 0: continue
		if not UpgradesData.UPGRADES.has(key): continue
		var upg = UpgradesData.UPGRADES[key]
		var cat = upg.get("category", "zzz")
		entries.append({"key": key, "count": count, "sort_cat": cat})

	entries.sort_custom(func(a, b):
		if a.sort_cat != b.sort_cat:
			return a.sort_cat < b.sort_cat
		return a.key < b.key
	)
	return entries

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CARTA INDIVIDUAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _get_card_rect(index: int) -> Rect2:
	return Rect2(_cards_start_x + index * (CARD_W + CARD_GAP),
				 CARDS_Y, CARD_W, CARD_H)

func _draw_card(index: int, key: String) -> void:
	var upg    : Dictionary = UpgradesData.UPGRADES[key]
	var rarity : String = upg.get("rarity", "common")
	var cat    : String = upg.get("category", "weapons")

	var rc      : Color = RARITY_COLORS.get(rarity, Color8(150, 150, 150))
	var rbg     : Color = RARITY_BG.get(rarity, Color8(18, 18, 22))
	var cat_col : Color = CATEGORY_COLOR.get(cat, Color(0.588, 0.588, 0.588))

	var is_hov := (index == _hovered_idx or index == _touch_pressed_idx)
	var card_scale : float = _hover_scales[index]

	var bx := _cards_start_x + index * (CARD_W + CARD_GAP)
	var by := CARDS_Y
	var cw := CARD_W * card_scale
	var ch := CARD_H * card_scale
	var cx := bx + CARD_W * 0.5
	var cy := by + CARD_H * 0.5
	var x  := cx - cw * 0.5
	var y  := cy - ch * 0.5

	# ── Sombra ────────────────────────────────────────────────────
	draw_rect(Rect2(x + 6.0, y + 8.0, cw + 8.0, ch + 8.0),
			  Color(0.0, 0.0, 0.0, 0.47))

	# ── Glow ──────────────────────────────────────────────────────
	var glow_a := 0.10
	if is_hov:
		glow_a = 0.22 + abs(sin(_anim_timer * 3.0)) * 0.18
	draw_rect(Rect2(x - 14.0, y - 14.0, cw + 28.0, ch + 28.0),
			  Color(rc.r, rc.g, rc.b, glow_a))

	# ── Fondo ─────────────────────────────────────────────────────
	draw_rect(Rect2(x, y, cw, ch), rbg)

	# ── Barra de categoría (top) ──────────────────────────────────
	draw_rect(Rect2(x, y, cw, 5.0 * card_scale), cat_col)

	# ── Borde ─────────────────────────────────────────────────────
	draw_rect(Rect2(x, y, cw, ch), rc, false, 3.0 if is_hov else 2.0)
	draw_rect(Rect2(x + 3.0, y + 3.0, cw - 6.0, ch - 6.0),
			  Color(rc.r, rc.g, rc.b, 0.10), false, 1.0)

	# ── Tecla (sup. izq.) ────────────────────────────────────────
	_text(str(index + 1), Vector2(x + 10.0, y + 10.0),
		  19, Color(0.235, 0.255, 0.294))

	# ── Rareza (sup. der.) ───────────────────────────────────────
	var rlabel : String = RARITY_LABEL.get(rarity, rarity.to_upper())
	_text_right(rlabel, x + cw - 10.0, y + 12.0, 13, rc)

	# ── Badge de nivel si ya se ha elegido antes ──────────────────
	var current_count : int = _player.upgrade_counts.get(key, 0)
	if current_count > 0:
		var badge_x := x + cw - 42.0
		var badge_y := y + 30.0
		draw_rect(Rect2(badge_x, badge_y, 34.0, 18.0),
				  Color(rc.r, rc.g, rc.b, 0.25))
		draw_rect(Rect2(badge_x, badge_y, 34.0, 18.0), rc, false, 1.0)
		_text_center("Nv.%d" % current_count,
					 Vector2(badge_x + 17.0, badge_y + 9.0), 12, rc)

	# ── Icono de categoría ────────────────────────────────────────
	var icon_cx := x + cw * 0.5
	var icon_cy := y + 62.0
	_draw_category_icon(icon_cx, icon_cy, cat, cat_col, card_scale * 20.0)

	# ── Categoría label ───────────────────────────────────────────
	var cat_lbl : String = UpgradesData.get_category_display_name(cat)
	_text_center(cat_lbl, Vector2(x + cw * 0.5, y + 92.0), 14, cat_col)

	# ── Separador ─────────────────────────────────────────────────
	var sep_y := y + 112.0
	draw_line(Vector2(x + 16.0, sep_y), Vector2(x + cw - 16.0, sep_y),
			  Color(rc.r, rc.g, rc.b, 0.20), 1.0)

	# ── Nombre ────────────────────────────────────────────────────
	_text_center(upg["name"] as String,
				 Vector2(x + cw * 0.5, sep_y + 12.0),
				 22, Color(0.92, 0.92, 0.96))

	# ── Descripción ───────────────────────────────────────────────
	_draw_wrapped(upg["desc"] as String,
				  x + 12.0, sep_y + 38.0, cw - 24.0, 15)

	# ── BARRA DE STACKS (nueva!) ──────────────────────────────────
	var max_stacks = upg.get("max_stacks", null)
	var is_stackable : bool = upg.get("stackable", false)
	var bar_y := y + ch - 64.0

	if max_stacks != null and max_stacks > 0:
		var bar_w := cw - 40.0
		var bar_x := x + 20.0
		var bar_h := 8.0

		# Fondo de la barra
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h),
				  Color(0.15, 0.15, 0.20))

		# Segmentos llenos (stacks actuales)
		var seg_w := bar_w / float(max_stacks)
		for s in range(current_count):
			draw_rect(Rect2(bar_x + s * seg_w + 1, bar_y + 1,
							seg_w - 2, bar_h - 2), rc)

		# Segmento que se llenará (parpadeante)
		if current_count < max_stacks:
			var fill_a = 0.3 + abs(sin(_anim_timer * 3.0)) * 0.4
			draw_rect(Rect2(bar_x + current_count * seg_w + 1, bar_y + 1,
							seg_w - 2, bar_h - 2),
					  Color(rc.r, rc.g, rc.b, fill_a))

		# Separadores
		for s in range(1, max_stacks):
			var lx := bar_x + s * seg_w
			draw_line(Vector2(lx, bar_y), Vector2(lx, bar_y + bar_h),
					  Color(0.0, 0.0, 0.0, 0.6), 1.0)

		# Texto de stacks
		var stack_label := "%d / %d" % [current_count, max_stacks]
		_text_center(stack_label,
					 Vector2(x + cw * 0.5, bar_y + bar_h + 10.0),
					 13, Color(0.6, 0.6, 0.7))

	elif is_stackable:
		# Stackable sin límite → mostrar solo count
		if current_count > 0:
			_text_center("x%d aplicado" % current_count,
						 Vector2(x + cw * 0.5, bar_y + 4.0),
						 13, Color(0.6, 0.6, 0.7))
	else:
		# No stackable → "ÚNICO"
		if current_count > 0:
			_text_center("YA APLICADO",
						 Vector2(x + cw * 0.5, bar_y + 4.0),
						 13, Color(0.5, 0.5, 0.3))
		else:
			_text_center("UNICO",
						 Vector2(x + cw * 0.5, bar_y + 4.0),
						 12, Color(0.35, 0.35, 0.45))

	# ── Pie de carta ──────────────────────────────────────────────
	if is_hov:
		var pulse : float = abs(sin(_anim_timer * 4.0))
		var pcol := Color(rc.r, rc.g, rc.b, 0.85 + pulse * 0.15)
		_text_center("ELEGIR", Vector2(x + cw * 0.5, y + ch - 28.0), 20, pcol)
		draw_line(Vector2(x, y + ch - 1.0),
				  Vector2(x + cw, y + ch - 1.0), rc, 2.0)
	else:
		_text_center("Tecla  %d" % (index + 1),
					 Vector2(x + cw * 0.5, y + ch - 20.0),
					 12, Color(0.196, 0.216, 0.255))

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ÍCONO DE CATEGORÍA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw_category_icon(cx: float, cy: float, cat: String,
						 col: Color, sz: float) -> void:
	# Para categorías de arma específica → usar icono "diamond" con acento
	var shape : String = CATEGORY_SHAPE.get(cat, "")
	if shape == "" and cat.begins_with("weapon_"):
		shape = "diamond"
	elif shape == "":
		shape = "diamond"

	match shape:
		"arrow":
			var pts := PackedVector2Array([
				Vector2(cx - sz, cy - sz * 0.7),
				Vector2(cx - sz, cy + sz * 0.7),
				Vector2(cx + sz, cy),
			])
			draw_colored_polygon(pts, col)
			draw_polyline(pts, Color.WHITE, 2.0)

		"cross":
			var w := maxf(3.0, sz / 3.0)
			draw_rect(Rect2(cx - w, cy - sz, w * 2, sz * 2), col)
			draw_rect(Rect2(cx - sz, cy - w, sz * 2, w * 2), col)

		"diamond":
			var pts := PackedVector2Array([
				Vector2(cx, cy - sz),
				Vector2(cx + sz, cy),
				Vector2(cx, cy + sz),
				Vector2(cx - sz, cy),
			])
			draw_colored_polygon(pts, col)
			draw_polyline(pts, Color.WHITE, 2.0)

		"gem":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := deg_to_rad(i * 60.0 - 30.0)
				var r := sz if i % 2 == 0 else sz * 0.7
				pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
			draw_colored_polygon(pts, col)
			draw_polyline(pts, Color.WHITE, 2.0)

		"skull":
			# Cráneo simplificado: círculo + mandíbula
			draw_circle(Vector2(cx, cy - sz * 0.15), sz * 0.7, col)
			draw_rect(Rect2(cx - sz * 0.45, cy + sz * 0.2,
							sz * 0.9, sz * 0.4), col)
			# Ojos
			draw_circle(Vector2(cx - sz * 0.22, cy - sz * 0.2),
						sz * 0.18, Color.BLACK)
			draw_circle(Vector2(cx + sz * 0.22, cy - sz * 0.2),
						sz * 0.18, Color.BLACK)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE TEXTO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw_wrapped(text: String, x: float, y: float,
				   max_width: float, fs: int,
				   col := Color(0.627, 0.647, 0.686),
				   line_h := 0.0) -> void:
	if line_h <= 0.0:
		line_h = float(fs) + 4.0
	var words := text.split(" ", false)
	var lines : Array[String] = []
	var cur   := ""
	for word in words:
		var test := (cur + " " + word).strip_edges() if cur != "" else word
		if _str_w(test, fs) <= max_width:
			cur = test
		else:
			if cur != "": lines.append(cur)
			cur = word
	if cur != "": lines.append(cur)

	for i in range(lines.size()):
		_text(lines[i], Vector2(x, y + i * line_h), fs, col)

func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var baseline := pos.y + _font.get_ascent(fs)
	draw_string(_font, Vector2(pos.x, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_right(t: String, right_x: float, top_y: float,
				 fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw := _str_w(t, fs)
	var baseline := top_y + _font.get_ascent(fs)
	draw_string(_font, Vector2(right_x - tw, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font): return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
