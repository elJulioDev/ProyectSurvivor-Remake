extends Control

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  hud.gd — ProyectSurvivor (Godot 4)
##  Traducción fiel de src/ui/hud.py
##
##  Conexión (desde gameplay.gd cada frame):
##      hud.score         = level.score
##      hud.enemies_alive = len(level.enemies)
##      hud.wave_time_str = spawn_manager.get_time_string()
##
##  El HUD busca al jugador por el grupo "player" automáticamente.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Fuentes (tamaños aprox. a pygame.font.Font(None, N)) ─────────
const FS_HUGE  := 52   # temporizador
const FS_LARGE := 34   # puntuación
const FS_SMALL := 19   # detalles / nivel
const FS_TINY  := 15   # sub-etiquetas

# ── Paleta (idéntica a hud.py) ────────────────────────────────────
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

const WEAPON_COLORS := {
	"PistolWeapon":       Color(0.000, 0.824, 0.824),
	"ShotgunWeapon":      Color(1.000, 0.549, 0.157),
	"AssaultRifleWeapon": Color(1.000, 0.863, 0.275),
	"LaserWeapon":        Color(0.392, 0.706, 1.000),
	"SniperWeapon":       Color(0.784, 1.000, 0.392),
	"NovaWeapon":         Color(0.863, 0.314, 1.000),
	"OrbitalWeapon":      Color(0.392, 0.824, 1.000),
	"BoomerangWeapon":    Color(1.000, 0.863, 0.235),
}

const WEAPON_NAMES := {
	"PistolWeapon":       "PISTOLA",
	"ShotgunWeapon":      "ESCOPETA",
	"AssaultRifleWeapon": "RIFLE",
	"LaserWeapon":        "LASER",
	"SniperWeapon":       "FRANCO",
	"NovaWeapon":         "NOVA",
	"OrbitalWeapon":      "ORBITAL",
	"BoomerangWeapon":    "BOOMER",
}

# ── Datos públicos (actualizados por gameplay.gd cada frame) ──────
var score         : int    = 0
var enemies_alive : int    = 0
var wave_time_str : String = "00:00"

# ── Estado interno (animaciones suavizadas) ───────────────────────
var _player          : Node   = null
var _damage_health   : float  = -1.0   # barra de daño suavizada
var _score_display   : float  = 0.0    # contador animado
var _hp_pulse        : float  = 0.0    # pulso ícono de HP
var _xp_anim         : float  = 0.0    # glow al subir nivel
var _level_prev      : int    = 1
var _time_pulse      : float  = 0.0    # pulso del temporizador
var _font            : Font

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CICLO
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
	var p := _player
	var dt60 := dt * 60.0   # normalizado a 60 fps como en Pygame

	# Barra de daño: cae suavemente hacia HP real
	if _damage_health < 0.0:
		_damage_health = p.health
	if _damage_health > p.health:
		var diff : float = _damage_health - float(p.health)
		_damage_health -= maxf(diff * 0.08 * dt60, 0.3 * dt60)
		_damage_health  = maxf(_damage_health, p.health)
	else:
		_damage_health = p.health

	# Contador de score sube suavemente
	var gap := float(score) - _score_display
	if absf(gap) > 0.5:
		_score_display += gap * 0.12 * dt60
	else:
		_score_display = float(score)

	# Pulso ícono HP (más rápido con poca vida)
	var hp_pct : float = float(p.health) / maxf(float(p.max_health), 1.0)
	_hp_pulse += (1.5 + (1.0 - hp_pct) * 6.0) * dt

	# Glow al subir de nivel
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

## Muestra solo el temporizador y barra XP vacía si no hay jugador
func _draw_minimal() -> void:
	draw_rect(Rect2(0, 0, size.x, 20), C_XP_BG)
	draw_line(Vector2(0, 19), Vector2(size.x, 19), C_BORDER_LIT, 1.0)
	_text_center(wave_time_str, Vector2(size.x * 0.5, 90.0), FS_HUGE, C_TIME)

# ── 1. BARRA DE XP  (franja superior, h = 20) ─────────────────────

func _draw_xp_strip() -> void:
	var p   := _player
	var W   := size.x
	const H := 20.0

	var xp_next : float = maxf(p.experience_next, 1.0) if "experience_next" in p \
				  else maxf(p.experience_next_level, 1.0)
	var pct : float = clampf(float(p.experience) / xp_next, 0.0, 1.0)

	# Fondo
	draw_rect(Rect2(0, 0, W, H), C_XP_BG)

	# Relleno de experiencia
	if pct > 0.0:
		draw_rect(Rect2(0, 0, W * pct, H), C_XP_FILL)

	# Glow al subir de nivel
	if _xp_anim > 0.0:
		draw_rect(Rect2(0, 0, W, H),
				  Color(C_XP_GLOW.r, C_XP_GLOW.g, C_XP_GLOW.b, _xp_anim * 0.78))

	# Borde inferior
	draw_line(Vector2(0, H - 1), Vector2(W, H - 1), C_BORDER_LIT, 1.0)

	# Pastilla de nivel (centrada)
	var lv_str  := "LVL  %d" % p.level
	var tw      := _str_w(lv_str, FS_SMALL)
	var pill_w  := tw + 28.0
	var pill_h  := 22.0
	var pill_x  := W * 0.5 - pill_w * 0.5
	var pill_y  := H + 4.0

	_panel(pill_x, pill_y, pill_w, pill_h, C_BG_PANEL, C_BORDER_LIT)
	_text_center(lv_str, Vector2(W * 0.5, pill_y + pill_h * 0.5), FS_SMALL, C_WHITE)

# ── 2. TEMPORIZADOR (centro superior) ─────────────────────────────

func _draw_timer() -> void:
	var cx    := size.x * 0.5
	var pulse := sin(_time_pulse) * 0.5 + 0.5
	var col   := C_TIME.lerp(Color.WHITE, pulse * 0.12)

	# Sombra
	_text_center(wave_time_str, Vector2(cx + 2.0, 92.0), FS_HUGE,
				 Color(0.0, 0.0, 0.0, 0.55))
	# Texto
	_text_center(wave_time_str, Vector2(cx, 90.0), FS_HUGE, col)

# ── 3. PANEL DE SALUD (izquierda) ─────────────────────────────────

func _draw_health_panel() -> void:
	var p  := _player
	const PX := 16.0
	const PY := 28.0
	const PW := 310.0
	const PH := 83.0

	_panel(PX, PY, PW, PH, C_BG_PANEL, C_BORDER)

	var hp_pct : float = clampf(float(p.health) / maxf(float(p.max_health), 1.0), 0.0, 1.0)
	var dmg_pct := clampf(_damage_health / maxf(p.max_health, 1.0), 0.0, 1.0)
	var hp_col  := _hp_color(hp_pct)

	# ── Ícono de cruz (pulsante) ───────────────────────────────────
	var icon_cx := PX + 22.0
	var icon_cy := PY + 28.0
	var pulse   := (sin(_hp_pulse) * 0.5 + 0.5) * (0.15 + (1.0 - hp_pct) * 0.45)
	var arm     := 9.0 * (1.0 + pulse)
	var thick   := maxf(3.0, 5.0 * (1.0 + pulse * 0.3))
	draw_line(Vector2(icon_cx, icon_cy - arm),
			  Vector2(icon_cx, icon_cy + arm), hp_col, thick)
	draw_line(Vector2(icon_cx - arm, icon_cy),
			  Vector2(icon_cx + arm, icon_cy), hp_col, thick)

	# ── Barras de HP ───────────────────────────────────────────────
	const BX := PX + 42.0
	const BY := PY + 19.0
	const BW := PW - 55.0
	const BH := 20.0

	# Fondo
	draw_rect(Rect2(BX, BY, BW, BH), Color(0.04, 0.04, 0.055))
	# Barra de daño (sombra roja)
	if dmg_pct > 0.0:
		draw_rect(Rect2(BX, BY, BW * dmg_pct, BH), C_HP_SHADOW)
	# HP actual
	if hp_pct > 0.0:
		draw_rect(Rect2(BX, BY, BW * hp_pct, BH), hp_col)
	# Borde
	draw_rect(Rect2(BX, BY, BW, BH), C_BORDER, false, 1.0)

	# Texto "123 / 100"
	var hp_str := "%d / %d" % [int(p.health), int(p.max_health)]
	_text_center(hp_str, Vector2(BX + BW * 0.5, BY + BH * 0.5), FS_TINY, C_GRAY)

	# Etiqueta SALUD
	_text("SALUD", Vector2(BX, BY - 20.0), FS_TINY, C_DIM)

	# ── Barra de Dash ─────────────────────────────────────────────
	var dash_y   := BY + BH + 8.0
	var dash_pct : float = float(p.get_dash_cooldown_fraction()) if p.has_method("get_dash_cooldown_fraction") else 1.0
	var dash_unlocked : bool = bool(p.dash_unlocked) if "dash_unlocked" in p else false

	draw_rect(Rect2(BX, dash_y, BW, 8.0), Color(0.04, 0.04, 0.055))

	if dash_pct > 0.0:
		var dc : Color
		if not dash_unlocked:
			dc = C_DIM
		elif dash_pct >= 0.99:
			dc = C_DASH_READY
		else:
			dc = Color(0.118, 0.353, 0.510)
		draw_rect(Rect2(BX, dash_y, BW * dash_pct, 8.0), dc)

	var dash_lbl : String
	var dash_col : Color
	if not dash_unlocked:
		dash_lbl = "DASH — BLOQUEADO"
		dash_col = C_DIM
	elif dash_pct >= 0.99:
		dash_lbl = "DASH — LISTO"
		dash_col = C_DASH_READY
	else:
		dash_lbl = "DASH  recargando…"
		dash_col = C_DIM
	_text(dash_lbl, Vector2(BX, dash_y + 11.0), FS_TINY, dash_col)

# ── 4. PANEL DE PUNTUACIÓN (derecha) ──────────────────────────────

func _draw_score_panel() -> void:
	const PW := 220.0
	const PH := 83.0
	const PY := 28.0
	var   px := size.x - PW - 16.0

	_panel(px, PY, PW, PH, C_BG_PANEL, C_BORDER)

	# Score (contador animado)
	var sc_str := _fmt_score(int(_score_display))
	var sc_w   := _str_w(sc_str, FS_LARGE)
	_text(sc_str, Vector2(px + PW - sc_w - 12.0, PY), FS_LARGE, C_SCORE)

	# Separador
	var sep_y := PY + PH * 0.5 + 4.0
	draw_line(Vector2(px + 10.0, sep_y),
			  Vector2(px + PW - 10.0, sep_y), C_BORDER, 1.0)

	# Contador de enemigos
	var en_col := C_ENEMIES if enemies_alive > 0 else C_RED
	var en_str := "%d ENEMIGOS" % enemies_alive
	var en_w   := _str_w(en_str, FS_SMALL)
	_text(en_str, Vector2(px + PW - en_w - 12.0, sep_y + 6.0), FS_SMALL, en_col)

# ── 5. INDICADOR DE ARMAS (centro inferior) ───────────────────────

func _draw_weapon_indicator() -> void:
	var p := _player
	if not ("weapons" in p) or p.weapons == null or p.weapons.size() == 0:
		return

	const SLOT_W := 54.0
	const SLOT_H := 54.0
	const GAP    := 8.0

	var n : int = p.weapons.size()
	var total_w : float = n * SLOT_W + (n - 1) * GAP
	var start_x  := size.x * 0.5 - total_w * 0.5
	var base_y   := size.y - SLOT_H - 20.0
	var cur_idx  := int(p.current_weapon_index) if "current_weapon_index" in p else 0

	for i in range(n):
		var weapon     = p.weapons[i]
		var is_active  := (i == cur_idx)
		var sx         := start_x + i * (SLOT_W + GAP)
		var wtype : String = str(weapon.get_class()) if weapon.has_method("get_class") else ""
		var wc : Color  = WEAPON_COLORS.get(wtype, C_BORDER)
		var bd_col      = wc if is_active else C_BORDER
		var bd_w        = 2.0 if is_active else 1.0

		_panel(sx, base_y, SLOT_W, SLOT_H, C_BG_PANEL, bd_col, bd_w)

		# Número de tecla
		_text(str(i + 1), Vector2(sx + 6.0, base_y + 5.0), FS_SMALL,
			  C_WHITE if is_active else C_DIM)

		# Nombre corto del arma
		var wname : String = WEAPON_NAMES.get(wtype, "ARMA")
		var wn_w  := _str_w(wname, FS_TINY)
		_text(wname, Vector2(sx + (SLOT_W - wn_w) * 0.5, base_y + SLOT_H - 18.0),
			  FS_TINY, wc if is_active else C_DIM)

		# Barra de recarga (solo arma activa)
		if is_active:
			var cd_pct := 1.0
			if "cooldown" in weapon and "current_cooldown" in weapon:
				var cd_max := maxf(float(weapon.cooldown), 1.0)
				cd_pct = 1.0 - clampf(float(weapon.current_cooldown) / cd_max, 0.0, 1.0)
			var bar_y := base_y + SLOT_H - 6.0
			var bw    := SLOT_W - 10.0
			draw_rect(Rect2(sx + 5.0, bar_y, bw, 4.0), Color(0.04, 0.04, 0.055))
			if cd_pct > 0.0:
				draw_rect(Rect2(sx + 5.0, bar_y, bw * cd_pct, 4.0), wc)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PRIMITIVAS DE DIBUJO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Panel con fondo sólido y borde (sin bordes redondeados = eficiente)
func _panel(x: float, y: float, w: float, h: float,
			bg: Color, border: Color, bw: float = 1.0) -> void:
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), border, false, bw)

## Texto: pos = esquina superior-izquierda del bloque
func _text(t: String, pos: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var baseline := pos.y + _font.get_ascent(fs)
	draw_string(_font, Vector2(pos.x, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Texto centrado en el punto (cx, cy)
func _text_center(t: String, center: Vector2, fs: int, col: Color) -> void:
	if t.is_empty() or not is_instance_valid(_font):
		return
	var tw       := _str_w(t, fs)
	var baseline := center.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	draw_string(_font, Vector2(center.x - tw * 0.5, baseline), t,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Ancho de una cadena en píxeles
func _str_w(t: String, fs: int) -> float:
	if not is_instance_valid(_font):
		return 0.0
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## Color de barra según porcentaje de vida
func _hp_color(pct: float) -> Color:
	if pct > 0.5:  return C_HP_HIGH
	if pct > 0.25: return C_HP_MID
	return C_HP_LOW

## Formatea score con punto como separador de miles: 1234567 → "1.234.567"
func _fmt_score(s: int) -> String:
	if s <= 0:
		return "0"
	var result := ""
	var n      := s
	var count  := 0
	while n > 0:
		if count > 0 and count % 3 == 0:
			result = "." + result
		result = str(n % 10) + result
		n /= 10
		count += 1
	return result
