extends Control

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  hud.gd — ProyectSurvivor (Godot 4)
##
##  OPTIMIZACIONES respecto a la versión anterior:
##
##  _draw_weapon_indicator():
##    · Antes: 6 _panel() individuales = 12 draw_rect + 12 extras
##             = ~30 draw_rect por frame solo para el indicador.
##    · Ahora: 1 fondo compartido para todos los slots = 2 draw_rect
##             + 2 draw_rect por slot activo + textos → ~8 draw calls.
##    · Eliminado el código muerto de la barra de cooldown
##      (weapon.current_cooldown no existe en WeaponData, por lo que
##      dibujaba 2 rects innecesarios siempre que un arma estaba activa).
##    · Nombres de arma truncados a 6 caracteres para evitar overflow.
##
##  Resto del HUD sin cambios funcionales.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const FS_HUGE  := 52
const FS_LARGE := 34
const FS_SMALL := 19
const FS_TINY  := 15

const C_BG_PANEL   := Color(0.071, 0.071, 0.102, 0.92)
const C_BORDER     := Color(0.176, 0.176, 0.255, 1.0)
const C_BORDER_LIT := Color(0.314, 0.314, 0.431, 1.0)
const C_WHITE      := Color(0.922, 0.922, 0.961, 1.0)
const C_GRAY       := Color(0.431, 0.431, 0.510, 1.0)
const C_RED        := Color(0.824, 0.314, 0.235, 1.0)
const C_DIM        := Color(0.216, 0.216, 0.275, 1.0)
const C_HP_HIGH    := Color(0.180, 0.800, 0.443, 1.0)
const C_HP_MID     := Color(0.945, 0.769, 0.059, 1.0)
const C_HP_LOW     := Color(0.906, 0.298, 0.235, 1.0)
const C_HP_SHADOW  := Color(0.392, 0.078, 0.039, 1.0)
const C_DASH_READY := Color(0.000, 0.824, 1.000, 1.0)
const C_XP_FILL    := Color(0.314, 0.549, 1.000, 1.0)
const C_XP_BG      := Color(0.059, 0.078, 0.157, 1.0)
const C_XP_GLOW    := Color(0.196, 0.353, 0.784, 1.0)
const C_SCORE      := Color(1.000, 0.863, 0.235, 1.0)
const C_TIME       := Color(0.784, 0.824, 0.902, 1.0)
const C_ENEMIES    := Color(0.863, 0.314, 0.235, 1.0)

# Datos públicos actualizados por gameplay.gd cada frame
var score          : int    = 0
var enemies_killed : int    = 0
var enemies_alive  : int    = 0
var wave_time_str  : String = "00:00"

# Estado interno de animaciones
var _player          : Node   = null
var _damage_health   : float  = -1.0
var _score_display   : float  = 0.0
var _hp_pulse        : float  = 0.0
var _xp_anim         : float  = 0.0
var _level_prev      : int    = 1
var _time_pulse      : float  = 0.0
var _font            : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_try_find_player()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_try_find_player()
	if is_instance_valid(_player):
		_update_anims(delta)
	queue_redraw()

func _try_find_player() -> void:
	var arr := get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0]
		if _damage_health < 0.0:
			_damage_health = _player.health

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ANIMACIONES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _update_anims(dt: float) -> void:
	var p    := _player
	var dt60 := dt * 60.0

	if _damage_health < 0.0:
		_damage_health = p.health
	if _damage_health > p.health:
		var diff : float = _damage_health - float(p.health)
		_damage_health -= maxf(diff * 0.08 * dt60, 0.3 * dt60)
		_damage_health  = maxf(_damage_health, p.health)
	else:
		_damage_health = p.health

	var gap := float(score) - _score_display
	if absf(gap) > 0.5:
		_score_display += gap * 0.12 * dt60
	else:
		_score_display = float(score)

	var hp_pct : float = float(p.health) / maxf(float(p.max_health), 1.0)
	_hp_pulse += (1.5 + (1.0 - hp_pct) * 6.0) * dt

	if p.level != _level_prev:
		_xp_anim   = 1.0
		_level_prev = p.level
	if _xp_anim > 0.0:
		_xp_anim = maxf(0.0, _xp_anim - 0.02 * dt60)

	_time_pulse += 0.04 * dt60

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DIBUJO PRINCIPAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _draw() -> void:
	if not is_instance_valid(_player):
		_draw_minimal()
		return
	_draw_xp_strip()
	_draw_timer()
	_draw_health_panel()
	_draw_score_panel()
	_draw_weapon_indicator()

func _draw_minimal() -> void:
	draw_rect(Rect2(0, 0, size.x, 20), C_XP_BG)
	draw_line(Vector2(0, 19), Vector2(size.x, 19), C_BORDER_LIT, 1.0)
	_text_center(wave_time_str, Vector2(size.x * 0.5, 90.0), FS_HUGE, C_TIME)

# ── 1. BARRA DE XP ────────────────────────────────────────────────

func _draw_xp_strip() -> void:
	var p   := _player
	var W   := size.x
	const H := 20.0

	var xp_next : float = maxf(p.experience_next, 1.0) if "experience_next" in p \
				  else maxf(p.experience_next_level, 1.0)
	var pct : float = clampf(float(p.experience) / xp_next, 0.0, 1.0)

	draw_rect(Rect2(0, 0, W, H), C_XP_BG)
	if pct > 0.0:
		draw_rect(Rect2(0, 0, W * pct, H), C_XP_FILL)
	if _xp_anim > 0.0:
		draw_rect(Rect2(0, 0, W, H),
				  Color(C_XP_GLOW.r, C_XP_GLOW.g, C_XP_GLOW.b, _xp_anim * 0.78))
	draw_line(Vector2(0, H - 1), Vector2(W, H - 1), C_BORDER_LIT, 1.0)

	var lv_str  := "LVL  %d" % p.level
	var tw      := _str_w(lv_str, FS_SMALL)
	var pill_w  := tw + 28.0
	var pill_h  := 22.0
	var pill_x  := W * 0.5 - pill_w * 0.5
	var pill_y  := H + 4.0
	_panel(pill_x, pill_y, pill_w, pill_h, C_BG_PANEL, C_BORDER_LIT)
	_text_center(lv_str, Vector2(W * 0.5, pill_y + pill_h * 0.5), FS_SMALL, C_WHITE)

# ── 2. TEMPORIZADOR ───────────────────────────────────────────────

func _draw_timer() -> void:
	var cx    := size.x * 0.5
	var pulse := sin(_time_pulse) * 0.5 + 0.5
	var col   := C_TIME.lerp(Color.WHITE, pulse * 0.12)
	_text_center(wave_time_str, Vector2(cx + 2.0, 92.0), FS_HUGE,
				 Color(0.0, 0.0, 0.0, 0.55))
	_text_center(wave_time_str, Vector2(cx, 90.0), FS_HUGE, col)

# ── 3. PANEL DE SALUD ─────────────────────────────────────────────

func _draw_health_panel() -> void:
	var p  := _player
	const PX := 16.0;  const PY := 28.0
	const PW := 310.0; const PH := 83.0
	_panel(PX, PY, PW, PH, C_BG_PANEL, C_BORDER)

	var hp_pct : float = clampf(float(p.health) / maxf(float(p.max_health), 1.0), 0.0, 1.0)
	var dmg_pct : float = clampf(_damage_health / maxf(p.max_health, 1.0), 0.0, 1.0)
	var hp_col  := _hp_color(hp_pct)

	var icon_cx := PX + 22.0;  var icon_cy := PY + 28.0
	var pulse   := (sin(_hp_pulse) * 0.5 + 0.5) * (0.15 + (1.0 - hp_pct) * 0.45)
	var arm     := 9.0 * (1.0 + pulse)
	var thick   := maxf(3.0, 5.0 * (1.0 + pulse * 0.3))
	draw_line(Vector2(icon_cx, icon_cy - arm), Vector2(icon_cx, icon_cy + arm), hp_col, thick)
	draw_line(Vector2(icon_cx - arm, icon_cy), Vector2(icon_cx + arm, icon_cy), hp_col, thick)

	const BX := PX + 42.0; const BY := PY + 19.0
	const BW := PW - 55.0; const BH := 20.0
	draw_rect(Rect2(BX, BY, BW, BH), Color(0.04, 0.04, 0.055))
	if dmg_pct > 0.0:
		draw_rect(Rect2(BX, BY, BW * dmg_pct, BH), C_HP_SHADOW)
	if hp_pct > 0.0:
		draw_rect(Rect2(BX, BY, BW * hp_pct, BH), hp_col)
	draw_rect(Rect2(BX, BY, BW, BH), C_BORDER, false, 1.0)

	var hp_str := "%d / %d" % [int(p.health), int(p.max_health)]
	_text_center(hp_str, Vector2(BX + BW * 0.5, BY + BH * 0.5), FS_TINY, C_GRAY)
	_text("SALUD", Vector2(BX, BY - 20.0), FS_TINY, C_DIM)

	var dash_y   := BY + BH + 8.0
	var dash_pct : float = float(p.get_dash_cooldown_fraction()) \
		if p.has_method("get_dash_cooldown_fraction") else 1.0
	var dash_unlocked : bool = bool(p.dash_unlocked) if "dash_unlocked" in p else false

	draw_rect(Rect2(BX, dash_y, BW, 8.0), Color(0.04, 0.04, 0.055))
	if dash_pct > 0.0:
		var dc : Color
		if not dash_unlocked:        dc = C_DIM
		elif dash_pct >= 0.99:       dc = C_DASH_READY
		else:                         dc = Color(0.118, 0.353, 0.510)
		draw_rect(Rect2(BX, dash_y, BW * dash_pct, 8.0), dc)

	var dash_lbl : String
	var dash_col : Color
	if not dash_unlocked:
		dash_lbl = "DASH — BLOQUEADO"; dash_col = C_DIM
	elif dash_pct >= 0.99:
		dash_lbl = "DASH — LISTO";     dash_col = C_DASH_READY
	else:
		dash_lbl = "DASH — RECARGANDO…"; dash_col = C_DIM
	_text(dash_lbl, Vector2(BX, dash_y + 11.0), FS_TINY, dash_col)

# ── 4. PANEL DE PUNTUACIÓN ────────────────────────────────────────

func _draw_score_panel() -> void:
	const PW := 220.0; const PH := 83.0; const PY := 28.0
	var   px  := size.x - PW - 16.0
	_panel(px, PY, PW, PH, C_BG_PANEL, C_BORDER)

	var sc_str := _fmt_score(int(_score_display))
	var sc_w   := _str_w(sc_str, FS_LARGE)
	_text(sc_str, Vector2(px + PW - sc_w - 12.0, PY), FS_LARGE, C_SCORE)

	var sep_y := PY + PH * 0.5 + 4.0
	draw_line(Vector2(px + 10.0, sep_y), Vector2(px + PW - 10.0, sep_y), C_BORDER, 1.0)

	var en_col := C_ENEMIES if enemies_alive > 0 else C_RED
	var en_str := "%d ELIMINADOS" % enemies_killed
	var en_w   := _str_w(en_str, FS_SMALL)
	_text(en_str, Vector2(px + PW - en_w - 12.0, sep_y + 6.0), FS_SMALL, en_col)

# ── 5. INDICADOR DE ARMAS — OPTIMIZADO ───────────────────────────
##
##  Cambios vs versión anterior:
##    · Un único fondo compartido para TODOS los slots (antes 1 panel cada uno).
##      Ahorra 10 draw_rect por frame (5 weapons × 2 rects por _panel).
##    · Eliminada la barra de cooldown muerta (weapon.current_cooldown
##      no existe en WeaponData → dibujaba 2 rects siempre llenos sin utilidad).
##    · Nombre de arma truncado a 6 chars para evitar overflow del slot.
##    · Total draw calls: antes ~30, ahora ~8.

func _draw_weapon_indicator() -> void:
	var p := _player
	if not ("weapons" in p) or p.weapons == null or p.weapons.size() == 0:
		return

	const SLOT_W : float = 54.0
	const SLOT_H : float = 50.0
	const GAP    : float = 6.0

	var n       : int   = p.weapons.size()
	var total_w : float = n * SLOT_W + (n - 1) * GAP
	var sx0     : float = size.x * 0.5 - total_w * 0.5
	var by      : float = size.y - SLOT_H - 18.0
	var cur     : int   = int(p.current_weapon_index) if "current_weapon_index" in p else 0

	# ── Fondo único para toda la tira (2 draw calls) ──────────────
	draw_rect(Rect2(sx0 - 6, by - 4, total_w + 12, SLOT_H + 8), C_BG_PANEL)
	draw_rect(Rect2(sx0 - 6, by - 4, total_w + 12, SLOT_H + 8), C_BORDER, false, 1.0)

	for i in range(n):
		var sx     : float = sx0 + i * (SLOT_W + GAP)
		var weapon         = p.weapons[i]
		var active : bool  = (i == cur)

		# Resaltar slot activo (2 draw calls solo para el arma activa)
		if active:
			draw_rect(Rect2(sx, by, SLOT_W, SLOT_H), Color(0.06, 0.16, 0.30, 0.85))
			draw_rect(Rect2(sx, by, SLOT_W, SLOT_H), C_DASH_READY, false, 2.0)

		# ── Número de tecla ───────────────────────────────────────
		_text(str(i + 1), Vector2(sx + 5.0, by + 4.0),
			  FS_TINY, C_WHITE if active else C_DIM)

		# ── Nombre del arma (truncado a 6 chars) ──────────────────
		var wn : String = (weapon.weapon_name as String) if "weapon_name" in weapon else "?"
		if wn.length() > 6:
			wn = wn.substr(0, 6)
		_text_center(wn, Vector2(sx + SLOT_W * 0.5, by + SLOT_H * 0.5 + 4.0),
					 FS_TINY, C_WHITE if active else C_DIM)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE DIBUJO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _panel(x: float, y: float, w: float, h: float,
			bg: Color, border: Color, bw: float = 1.0) -> void:
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), border, false, bw)

func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	draw_string(_font, Vector2(pos.x, pos.y + _font.get_ascent(fs)),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font): return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font): return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _hp_color(pct: float) -> Color:
	if pct > 0.5:  return C_HP_HIGH
	if pct > 0.25: return C_HP_MID
	return C_HP_LOW

func _fmt_score(s: int) -> String:
	if s <= 0: return "0"
	var result := ""; var n := s; var count := 0
	while n > 0:
		if count > 0 and count % 3 == 0: result = "." + result
		result = str(n % 10) + result; n /= 10; count += 1
	return result