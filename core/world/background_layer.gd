extends Node2D

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
##  background_layer.gd — ProyectSurvivor
##
##  Shader UV-based (1 draw call) con anti-aliasing via fwidth().
##  Las líneas del grid se suavizan automáticamente a cualquier
##  zoom y resolución, sin bordes duros ni artefactos visuales.
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const TILE_MARGIN : int = 2

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec2 world_top_left = vec2(0.0);
uniform vec2 world_size     = vec2(1280.0, 720.0);

const float TILE_SIZE  = 64.0;
const float GRID_EVERY = 256.0;

const vec3 COL_A = vec3(0.08, 0.08, 0.08);
const vec3 COL_B = vec3(0.11, 0.11, 0.11);
const vec3 GRID  = vec3(0.18, 0.18, 0.18);

// ── Línea anti-aliased ────────────────────────────────────────────
// Devuelve [0,1]: 1.0 = sobre la línea, 0.0 = fuera.
// px_size  = fwidth(coord)  → cuántas unidades-mundo ocupa 1px.
// thickness = grosor deseado en píxeles de pantalla.
float aa_line(float coord, float period, float px_size, float thickness) {
    float c    = mod(coord, period);
    float dist = min(c, period - c);       // dist al borde más cercano
    float half = px_size * thickness * 0.5;
    return 1.0 - smoothstep(half - px_size, half + px_size, dist);
}

void fragment() {
    // ── Posición de mundo desde UV (exacta a cualquier zoom) ──────
    vec2 w  = world_top_left + UV * world_size;
    vec2 sw = w + vec2(100000.0);   // offset para mod() con coords negativas

    // ── Damero ────────────────────────────────────────────────────
    vec2  tile = floor(sw / TILE_SIZE);
    float chk  = mod(tile.x + tile.y, 2.0);
    vec3  col  = chk < 0.5 ? COL_A : COL_B;

    // ── Grid cada 256 unidades — anti-aliased con fwidth ──────────
    // fwidth(sw.x/y) devuelve cuántas unidades de mundo equivalen
    // a 1 px de pantalla en ese eje. Con esto el grosor es siempre
    // exactamente "thickness" píxeles, sin importar el zoom.
    float px_x  = fwidth(sw.x);
    float px_y  = fwidth(sw.y);

    float lx = aa_line(sw.x, GRID_EVERY, px_x, 0.5);
    float ly = aa_line(sw.y, GRID_EVERY, px_y, 0.5);
    float l  = max(lx, ly);

    col = mix(col, GRID, l * 0.60);

    COLOR = vec4(col, 1.0);
}
"""

var _mat : ShaderMaterial = null

func _ready() -> void:
	_mat        = ShaderMaterial.new()
	var sh      := Shader.new()
	sh.code     = SHADER_CODE
	_mat.shader = sh
	material    = _mat

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var vp_size : Vector2 = get_viewport_rect().size
	var zoom    : Vector2 = cam.zoom
	var center  : Vector2 = cam.get_screen_center_position()

	var half : Vector2 = vp_size * 0.5 / zoom \
						 + Vector2(64.0 * TILE_MARGIN, 64.0 * TILE_MARGIN)

	var rect := Rect2(center - half, half * 2.0)

	_mat.set_shader_parameter("world_top_left", rect.position)
	_mat.set_shader_parameter("world_size",     rect.size)

	draw_rect(rect, Color.WHITE)