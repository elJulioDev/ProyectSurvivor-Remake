extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  scenes/upgrade.gd — ProyectSurvivor
##  Port de src/scenes/upgrade.py (Pygame) a Godot 4
##
##  Se instancia como overlay sobre gameplay (CanvasLayer).
##  Funciona con process_mode = ALWAYS para recibir input
##  mientras get_tree().paused = true.
##
##  Uso desde gameplay.gd:
##      var upgrade_node = upgrade_packed.instantiate()
##      upgrade_node.setup(player_ref)
##      upgrade_node.upgrade_selected.connect(func(): ...)
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

# ── Paleta de categoría ───────────────────────────────────────────
const CATEGORY_LABEL := {
	"movement": "MOVIMIENTO",
	"survival": "SUPERVIVENCIA",
	"weapons":  "ARMAS",
	"xp":       "XP / GEMAS",
}
const CATEGORY_COLOR := {
	"movement": Color(0.000, 0.824, 1.000),
	"survival": Color(1.000, 0.314, 0.314),
	"weapons":  Color(1.000, 0.784, 0.196),
	"xp":       Color(0.588, 0.314, 1.000),
}

# ── Geometría de cartas ───────────────────────────────────────────
const CARD_W   := 275.0
const CARD_H   := 340.0
const CARD_GAP :=  32.0
const CARDS_Y  := 185.0

# ── Estado ────────────────────────────────────────────────────────
var VW := 1280.0
var VH :=  720.0

var _player        : Node  = null
var _options       : Array = []
var _hovered_idx   : int   = -1
var _hover_scales  : Array = [1.0, 1.0, 1.0]
var _anim_timer    : float = 0.0
var _fade_alpha    : float = 255.0    # fade de entrada (255 → 0)
var _fade_speed    : float = 14.0
var _input_cooldown: float = 0.55     # segundos de espera antes de aceptar input
var _cards_start_x : float = 0.0
var _font          : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	# CRÍTICO: debe funcionar mientras el árbol está pausado
	process_mode = PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func setup(player: Node) -> void:
	_player = player
	var vp := get_viewport_rect().size
	VW = vp.x
	VH = vp.y
	_recalc_layout()
	_options = _select_upgrades()

func _recalc_layout() -> void:
	var total_w := CARD_W * 3.0 + CARD_GAP * 2.0
	_cards_start_x = (VW - total_w) * 0.5

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

	# Hover de cartas
	var mp := get_local_mouse_position()
	_hovered_idx = -1
	for i in range(_options.size()):
		if _get_card_rect(i).has_point(mp):
			_hovered_idx = i

	# Animación de escala al hover
	for i in range(_options.size()):
		var target := 1.045 if i == _hovered_idx else 1.0
		_hover_scales[i] += (target - _hover_scales[i]) * 0.15 * dt
		_hover_scales[i]  = clampf(_hover_scales[i], 0.98, 1.06)

	queue_redraw()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  INPUT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _unhandled_input(event: InputEvent) -> void:
	if _input_cooldown > 0.0:
		return

	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _hovered_idx >= 0:
			_confirm(_hovered_idx)
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
#  SELECCIÓN DE MEJORAS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _select_upgrades() -> Array:
	if not is_instance_valid(_player):
		return []

	var available_keys    : Array = []
	var available_weights : Array = []

	for key in UpgradesData.UPGRADES:
		var upg : Dictionary = UpgradesData.UPGRADES[key]

		# Filtrar por requisito
		var req = upg.get("requires", null)
		if not _check_requires(req):
			continue

		# Desbloqueos únicos
		if upg["type"] == "unlock" and key == "dash":
			if _player.dash_unlocked:
				continue
		elif upg["type"] == "unlock_weapon":
			if (upg["weapon_class"] as String) in _player.unlocked_weapon_names:
				continue

		# Límite de stacks
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

	# Elegir 3, evitando misma categoría (hasta 30 intentos)
	var chosen     : Array = []
	var used_cats  : Dictionary = {}
	var keys_cp    := available_keys.duplicate()
	var weights_cp := available_weights.duplicate()
	var attempts   := 0

	while chosen.size() < 3 and keys_cp.size() > 0 and attempts < 60:
		attempts += 1
		var idx := _weighted_random_pick(weights_cp)
		if idx < 0:
			break
		var key : String = keys_cp[idx]
		var cat : String = UpgradesData.UPGRADES[key].get("category", "")
		if not (cat in used_cats) or attempts > 30:
			chosen.append(key)
			used_cats[cat] = true
		keys_cp.remove_at(idx)
		weights_cp.remove_at(idx)

	# Fallback con stackables si faltan cartas
	while chosen.size() < 3:
		var valid : Array = []
		for key in UpgradesData.UPGRADES:
			if key in chosen:
				continue
			var v : Dictionary = UpgradesData.UPGRADES[key]
			if not v.get("stackable", false):
				continue
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
		"orbital_unlocked":
			for w in _player.passive_weapons:
				if w is OrbitalWeapon:
					return true
			return false
	# Comprobación genérica de atributo
	if req in _player:
		return bool(_player.get(req))
	return false

func _weighted_random_pick(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += w
	if total <= 0:
		return -1
	var roll := randi() % total
	var acc  := 0
	for i in range(weights.size()):
		acc += weights[i]
		if roll < acc:
			return i
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

		"orbital":
			_apply_orbital(upg["stat_name"], upg["value"])

		"xp":
			_apply_xp_stat(upg["stat_name"], upg["value"])

	print("✅ Mejora: [%s] %s" % [
		(upg.get("rarity", "?") as String).to_upper(),
		upg["name"]
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

func _apply_orbital(sname: String, val) -> void:
	for w in _player.passive_weapons:
		if w is OrbitalWeapon:
			match sname:
				"orbital_add_orb":  w.add_orb()
				"orbital_speed":    w.increase_speed(float(val))
				"orbital_range":    w.increase_orbit_radius(float(val))
				"orbital_damage":   w.increase_damage_mult(float(val))
			return

func _apply_xp_stat(sname: String, val) -> void:
	match sname:
		"magnet_range_mult":  _player.magnet_range_mult *= val
		"xp_mult":            _player.xp_mult           *= val
		"xp_on_kill_bonus":   _player.xp_on_kill_bonus  += int(val)
		"magnet_speed_mult":  _player.magnet_speed_mult *= val

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  RENDER PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	# Fondo semitransparente
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.82))

	_draw_title()
	_draw_subtitle()

	for i in range(_options.size()):
		_draw_card(i, _options[i])

	# Fade de entrada
	if _fade_alpha > 0.5:
		draw_rect(Rect2(0.0, 0.0, VW, VH),
				  Color(0.0, 0.0, 0.0, _fade_alpha / 255.0))

func _draw_title() -> void:
	if not is_instance_valid(_player):
		return
	var glow_t: float = absf(sin(_anim_timer))
	var glow_val: float = glow_t * 40.0 + 180.0
	var tcol     := Color(1.0, glow_val / 255.0, 40.0 / 255.0)
	var title    := "NIVEL %d ALCANZADO" % _player.level
	var cx       := VW * 0.5
	# Sombra
	_text_center(title, Vector2(cx + 3.0, 78.0), 46,
				 Color(0.314, 0.157, 0.0, 0.75))
	# Texto principal
	_text_center(title, Vector2(cx, 75.0), 46, tcol)

func _draw_subtitle() -> void:
	_text_center(
		"Elige una mejora   |   Teclas  1   2   3",
		Vector2(VW * 0.5, 142.0), 18,
		Color(0.392, 0.412, 0.471)
	)

# ── Carta individual ──────────────────────────────────────────────

func _get_card_rect(index: int) -> Rect2:
	return Rect2(_cards_start_x + index * (CARD_W + CARD_GAP),
				 CARDS_Y, CARD_W, CARD_H)

func _draw_card(index: int, key: String) -> void:
	var upg    : Dictionary = UpgradesData.UPGRADES[key]
	var rarity : String = upg.get("rarity", "common")
	var cat    : String = upg.get("category", "weapons")

	var rc: Color = RARITY_COLORS.get(rarity, Color8(150, 150, 150))
	var rbg: Color = RARITY_BG.get(rarity, Color8(18, 18, 22))
	var cat_color: Color = CATEGORY_COLOR.get(cat, Color(0.588, 0.588, 0.588))

	var is_hov := (index == _hovered_idx)
	var card_scale: float = _hover_scales[index]

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

	# ── Glow de rareza ────────────────────────────────────────────
	var glow_a := 0.118
	if is_hov:
		var pulse : float = abs(sin(_anim_timer * 3.0))
		glow_a = 0.235 + pulse * 0.196
	draw_rect(Rect2(x - 15.0, y - 15.0, cw + 30.0, ch + 30.0),
			  Color(rc.r, rc.g, rc.b, glow_a))

	# ── Fondo ─────────────────────────────────────────────────────
	draw_rect(Rect2(x, y, cw, ch), rbg)

	# ── Barra de acento superior (categoría) ──────────────────────
	draw_rect(Rect2(x, y, cw, 5.0 * card_scale), cat_color)

	# ── Borde ─────────────────────────────────────────────────────
	var bw := 3.0 if is_hov else 2.0
	draw_rect(Rect2(x, y, cw, ch), rc, false, bw)

	# Borde interior sutil
	draw_rect(Rect2(x + 3.0, y + 3.0, cw - 6.0, ch - 6.0),
			  Color(rc.r, rc.g, rc.b, 0.118), false, 1.0)

	# ── Número de tecla (esquina sup. izquierda) ──────────────────
	_text(str(index + 1), Vector2(x + 10.0, y + 10.0),
		  19, Color(0.235, 0.255, 0.294))

	# ── Rareza (esquina sup. derecha) ─────────────────────────────
	var rlabel : String = RARITY_LABEL.get(rarity, rarity.to_upper())
	_text_right(rlabel, x + cw - 10.0, y + 12.0, 14, rc)

	# ── Icono de categoría ────────────────────────────────────────
	var icon_cx := x + cw * 0.5
	var icon_cy := y + 65.0
	_draw_category_icon(icon_cx, icon_cy, cat, cat_color, card_scale * 22.0)

	# ── Etiqueta de categoría ─────────────────────────────────────
	var cat_lbl : String = CATEGORY_LABEL.get(cat, cat.to_upper())
	_text_center(cat_lbl, Vector2(x + cw * 0.5, y + 96.0), 16, cat_color)

	# ── Separador ─────────────────────────────────────────────────
	var sep_y := y + 117.0
	draw_line(Vector2(x + 16.0, sep_y), Vector2(x + cw - 16.0, sep_y),
			  Color(rc.r, rc.g, rc.b, 0.235), 1.0)

	# ── Nombre de la mejora ───────────────────────────────────────
	_text_center(upg["name"] as String,
				 Vector2(x + cw * 0.5, sep_y + 10.0),
				 24, Color(0.922, 0.922, 0.961))

	# ── Descripción (texto ajustado) ──────────────────────────────
	_draw_wrapped(upg["desc"] as String,
				  x + 14.0, sep_y + 42.0, cw - 28.0, 16)

	# ── Pie de carta ──────────────────────────────────────────────
	if is_hov:
		var pulse : float = abs(sin(_anim_timer * 4.0))
		var pcol := Color(rc.r, rc.g, rc.b, 0.85 + pulse * 0.15)
		_text_center("ELEGIR", Vector2(x + cw * 0.5, y + ch - 32.0), 22, pcol)
		draw_line(Vector2(x, y + ch - 1.0),
				  Vector2(x + cw, y + ch - 1.0), rc, 2.0)
	else:
		_text_center("Tecla  %d" % (index + 1),
					 Vector2(x + cw * 0.5, y + ch - 22.0),
					 13, Color(0.196, 0.216, 0.255))

# ── Ícono de categoría ────────────────────────────────────────────

func _draw_category_icon(cx: float, cy: float, cat: String,
						  color: Color, size: float) -> void:
	var s := int(size)
	match cat:
		"movement":   # Flecha →
			var pts := PackedVector2Array([
				Vector2(cx - s, cy - s * 0.7),
				Vector2(cx - s, cy + s * 0.7),
				Vector2(cx + s, cy),
			])
			draw_colored_polygon(pts, color)
			draw_polyline(
				PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
				Color.WHITE, 2.0)

		"survival":   # Cruz médica
			var w := maxi(3, int(s / 3.0))
			draw_rect(Rect2(cx - w, cy - s, w * 2, s * 2), color)
			draw_rect(Rect2(cx - s, cy - w, s * 2, w * 2), color)

		"weapons":    # Diamante
			var pts := PackedVector2Array([
				Vector2(cx,     cy - s),
				Vector2(cx + s, cy),
				Vector2(cx,     cy + s),
				Vector2(cx - s, cy),
			])
			draw_colored_polygon(pts, color)
			draw_polyline(
				PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color.WHITE, 2.0)

		"xp":         # Gema hexagonal
			var pts := PackedVector2Array()
			for i in range(6):
				var a := deg_to_rad(float(i) * 60.0 - 30.0)
				var r := float(s) if i % 2 == 0 else float(s) * 0.7
				pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
			draw_colored_polygon(pts, color)
			draw_polyline(
				PackedVector2Array([pts[0], pts[1], pts[2],
									pts[3], pts[4], pts[5], pts[0]]),
				Color.WHITE, 2.0)

# ── Texto ajustado (wrapped) ──────────────────────────────────────

func _draw_wrapped(text: String, x: float, y: float,
				   max_width: float, fs: int) -> void:
	var col    := Color(0.627, 0.647, 0.686)
	var line_h := 20.0
	var words  := text.split(" ")
	var lines  : Array[String] = []
	var cur    := ""

	for word in words:
		var test : String = (cur + " " + word).strip_edges() if cur != "" else word
		if _str_w(test, fs) <= max_width:
			cur = test
		else:
			if cur != "":
				lines.append(cur)
			cur = word
	if cur != "":
		lines.append(cur)

	for i in range(lines.size()):
		_text(lines[i], Vector2(x, y + i * line_h), fs, col)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE TEXTO (misma API que menu.gd / game_over.gd)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var baseline := pos.y + _font.get_ascent(fs)
	draw_string(_font, Vector2(pos.x, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_right(t: String, right_x: float, top_y: float,
				 fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var tw       := _str_w(t, fs)
	var baseline := top_y + _font.get_ascent(fs)
	draw_string(_font, Vector2(right_x - tw, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font):
		return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
