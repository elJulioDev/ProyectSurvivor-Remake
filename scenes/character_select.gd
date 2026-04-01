extends Node2D

# ════════════════════════════════════════════════════════════════════
#  CharacterSelect — Pantalla de selección de personaje.
#  Estilo visual consistente con upgrade.gd (canvas drawing).
#  Carga dinámicamente todos los .tres de entities/characters/
# ════════════════════════════════════════════════════════════════════

const CHARACTERS_DIR := "res://entities/characters/"
const C_BG           := Color(0.024, 0.027, 0.039)
const C_BORDER       := Color(0.157, 0.173, 0.243)
const C_WHITE        := Color(0.902, 0.910, 0.933)
const C_DIM          := Color(0.45, 0.47, 0.55)

# Dimensiones de la tarjeta de personaje
const CARD_W : float = 220.0
const CARD_H : float = 320.0
const CARD_GAP : float = 30.0

var VW : float = 1280.0
var VH : float = 720.0

var _characters   : Array[CharacterData] = []
var _hovered_idx  : int = -1
var _selected_idx : int = 0  # 0 = primer personaje por defecto
var _font         : Font
var _anim_timer   : float = 0.0
var _input_cd     : float = 0.0
var _fade_alpha   : float = 255.0

# ── Ciclo de vida ─────────────────────────────────────────────────

func _ready() -> void:
	VW = get_viewport_rect().size.x
	VH = get_viewport_rect().size.y
	_font = ThemeDB.fallback_font
	_load_all_characters()

func _load_all_characters() -> void:
	## Carga automáticamente todos los CharacterData .tres del directorio.
	## Para añadir un personaje nuevo: solo crea el .tres, sin tocar este script.
	var dir := DirAccess.open(CHARACTERS_DIR)
	if not dir:
		push_error("CharacterSelect: no se puede abrir " + CHARACTERS_DIR)
		return

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load(CHARACTERS_DIR + fname)
			if res is CharacterData:
				_characters.append(res)
		fname = dir.get_next()
	dir.list_dir_end()

	# Ordenar por character_id para orden consistente
	_characters.sort_custom(func(a, b): return a.character_id < b.character_id)

	if _characters.is_empty():
		push_error("CharacterSelect: no se encontraron CharacterData en " + CHARACTERS_DIR)

# ── Update ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_anim_timer += delta
	if _input_cd > 0.0:
		_input_cd -= delta

	# Hover por mouse
	var mp := get_local_mouse_position()
	_hovered_idx = -1
	for i in range(_characters.size()):
		if _get_card_rect(i).has_point(mp):
			_hovered_idx = i

	if _fade_alpha > 0.0:
		_fade_alpha = maxf(0.0, _fade_alpha - 300.0 * delta)

	queue_redraw()

# ── Input ─────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _input_cd > 0.0 or _characters.is_empty():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _hovered_idx >= 0:
			_confirm(_hovered_idx)

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_selected_idx = posmod(_selected_idx - 1, _characters.size())
			KEY_RIGHT, KEY_D:
				_selected_idx = posmod(_selected_idx + 1, _characters.size())
			KEY_ENTER, KEY_SPACE:
				_confirm(_selected_idx)
			KEY_ESCAPE:
				GameManager.goto_scene("res://scenes/menu.tscn")

func _confirm(idx: int) -> void:
	_input_cd = 0.5
	GameManager.selected_character = _characters[idx]
	print("[CharacterSelect] Seleccionado: ", _characters[idx].character_name)
	# Lanza gameplay con la pantalla de carga estándar
	GameManager.goto_scene("res://scenes/gameplay.tscn")

# ── Rendering ─────────────────────────────────────────────────────

func _draw() -> void:
	# Fondo
	draw_rect(Rect2(Vector2.ZERO, Vector2(VW, VH)), C_BG)

	if _characters.is_empty():
		_text_center("No se encontraron personajes.", Vector2(VW * 0.5, VH * 0.5), 28, C_DIM)
		return

	# Título
	_text_center("SELECCIONA TU PERSONAJE",
				 Vector2(VW * 0.5, 48.0), 36, C_WHITE)
	_text_center("← → para navegar · ENTER para confirmar · ESC para volver",
				 Vector2(VW * 0.5, 80.0), 16, C_DIM)

	# Tarjetas
	for i in range(_characters.size()):
		_draw_card(i)

	# Fade-in inicial
	if _fade_alpha > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(VW, VH)),
				  Color(C_BG.r, C_BG.g, C_BG.b, _fade_alpha / 255.0))


func _get_card_rect(idx: int) -> Rect2:
	var total_w := _characters.size() * (CARD_W + CARD_GAP) - CARD_GAP
	var start_x := (VW - total_w) * 0.5
	var x       := start_x + idx * (CARD_W + CARD_GAP)
	var y       := (VH - CARD_H) * 0.5
	return Rect2(x, y, CARD_W, CARD_H)


func _draw_card(idx: int) -> void:
	var char_data : CharacterData = _characters[idx]
	var rect      := _get_card_rect(idx)
	var x         := rect.position.x
	var y         := rect.position.y
	var is_hov    := idx == _hovered_idx
	var is_sel    := idx == _selected_idx
	var c         := char_data.color

	# Pulso de selección
	var pulse := 0.0
	if is_sel:
		pulse = abs(sin(_anim_timer * 3.0)) * 0.15

	# Fondo de tarjeta
	var bg_alpha := 0.12 + (0.10 if is_hov else 0.0) + pulse
	draw_rect(rect, Color(c.r, c.g, c.b, bg_alpha))

	# Borde
	var border_w := 2.0 if not is_sel else 2.5
	var border_c := c if is_sel else Color(c.r, c.g, c.b, 0.4 + (0.3 if is_hov else 0.0))
	draw_rect(rect, border_c, false, border_w)

	# Indicador de selección activa (KB)
	if is_sel:
		draw_rect(Rect2(x, y, CARD_W, 3.0), c)

	# Avatar placeholder (cuadrado con color del personaje)
	var avatar_size := 80.0
	var avatar_rect := Rect2(
		x + (CARD_W - avatar_size) * 0.5,
		y + 24.0,
		avatar_size, avatar_size
	)
	draw_rect(avatar_rect, Color(c.r, c.g, c.b, 0.25))
	draw_rect(avatar_rect, Color(c.r, c.g, c.b, 0.7), false, 1.5)
	# Inicial del personaje como avatar
	_text_center(
		char_data.character_name.substr(0, 1).to_upper(),
		Vector2(x + CARD_W * 0.5, y + 24.0 + avatar_size * 0.5 + 6.0),
		42, c
	)

	# Nombre
	_text_center(char_data.character_name,
				 Vector2(x + CARD_W * 0.5, y + 130.0), 22, C_WHITE)

	# Separador
	draw_line(
		Vector2(x + 16.0, y + 148.0),
		Vector2(x + CARD_W - 16.0, y + 148.0),
		Color(c.r, c.g, c.b, 0.3), 1.0
	)

	# Descripción (wrap simple)
	_draw_wrapped(char_data.description, x + 14.0, y + 160.0, CARD_W - 28.0, 15)

	# Lista de armas disponibles
	_text_center("ARMAS", Vector2(x + CARD_W * 0.5, y + 230.0), 13, C_DIM)
	var weapons_str := " · ".join(char_data.available_weapons)
	_draw_wrapped(weapons_str, x + 14.0, y + 248.0, CARD_W - 28.0, 13)

	# Pasiva (si existe)
	if char_data.passive_id != "":
		_text_center("◆ " + char_data.passive_id.replace("_", " ").to_upper(),
					 Vector2(x + CARD_W * 0.5, y + CARD_H - 20.0),
					 13, Color(c.r, c.g, c.b, 0.8))


# ── Helpers de texto (misma API que upgrade.gd) ────────────────────

func _text(text: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _text_center(text: String, pos: Vector2, size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, pos - Vector2(w * 0.5, 0.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_wrapped(text: String, x: float, y: float, max_w: float, size: int) -> void:
	## Word-wrap simple: parte por espacios, acumula líneas.
	var words    := text.split(" ")
	var line     := ""
	var line_y   := y
	var line_h   := float(size) * 1.4

	for word in words:
		var test   := (line + " " + word).strip_edges()
		var test_w := _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if test_w > max_w and line != "":
			draw_string(_font, Vector2(x, line_y), line,
						HORIZONTAL_ALIGNMENT_LEFT, -1, size, C_DIM)
			line   = word
			line_y += line_h
		else:
			line = test

	if line != "":
		draw_string(_font, Vector2(x, line_y), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, C_DIM)