extends Control

# Variables visuales por defecto (valores originales grandes)
const GAP := 8.0        # Separación del centro
const SIZE := 12.0      # Largo de cada línea
const THICKNESS := 2.0  # Grosor de la línea
const COLOR := Color(0.0, 1.0, 0.0, 0.8) # Verde transparente
const DOT_SIZE := 2.0   # Tamaño del punto central

var crosshair_scale: float = 1.0
var current_type: int = 0 # Corresponde a WeaponBase.CrosshairType.CROSS

@onready var player = get_tree().get_first_node_in_group("player")
var _last_cooldown: float = 0.0

func _ready() -> void:
    # Ocultamos el cursor por defecto del sistema (como en Pygame)
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    
    # Aseguramos que el Control no bloquee los clicks del ratón
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Forzamos a que el nodo no tenga un tamaño delimitado
    set_anchors_preset(PRESET_FULL_RECT)

func _process(delta: float) -> void:
    # Seguir la posición del ratón en la pantalla
    global_position = get_viewport().get_mouse_position()

    if is_instance_valid(player) and player.active_weapons.size() > 0:
        var current_weapon = player.active_weapons[player.current_weapon_index]
        
        # Leer el tipo de mira del arma actual
        if "crosshair_type" in current_weapon:
            current_type = current_weapon.crosshair_type
        else:
            current_type = 0
            
        # Detectar cuándo se dispara para animar la mira (pulso)
        # Comparamos el cooldown actual con el del frame anterior
        if current_weapon.current_cooldown > _last_cooldown and current_weapon.current_cooldown > 0:
            # Aplicamos el cálculo original de Pygame: 0.3 + shake_amount * 0.15
            var shake = current_weapon.shake_amount if "shake_amount" in current_weapon else 0.0
            crosshair_scale += 0.3 + (shake * 0.15)
            
        _last_cooldown = current_weapon.current_cooldown

    # Limitar la escala a un máximo de 4.0
    crosshair_scale = clampf(crosshair_scale, 1.0, 4.0)
    # Interpolar suavemente de vuelta a 1.0 (0.08 * dt ajustado a delta)
    crosshair_scale += (1.0 - crosshair_scale) * 15.0 * delta

    # Pedirle a Godot que redibuje en este frame
    queue_redraw()

func _draw() -> void:
    # Variables escaladas dinámicamente usando los valores grandes originales
    var g = GAP * crosshair_scale
    var sz = SIZE * crosshair_scale

    match current_type:
        0: # CROSS (Pistola - Versión PEQUEÑA)
            # Reducimos a la mitad g y sz SOLO para esta mira
            var g_small = g * 0.5
            var sz_small = sz * 0.5
            
            # Punto central
            draw_rect(Rect2(-DOT_SIZE/2, -DOT_SIZE/2, DOT_SIZE, DOT_SIZE), COLOR)
            # Arriba
            draw_line(Vector2(0, -g_small - sz_small), Vector2(0, -g_small), COLOR, THICKNESS)
            # Abajo
            draw_line(Vector2(0, g_small), Vector2(0, g_small + sz_small), COLOR, THICKNESS)
            # Izquierda
            draw_line(Vector2(-g_small - sz_small, 0), Vector2(-g_small, 0), COLOR, THICKNESS)
            # Derecha
            draw_line(Vector2(g_small, 0), Vector2(g_small + sz_small, 0), COLOR, THICKNESS)
            
        1: # CIRCLE (Ideal para escopeta)
            draw_rect(Rect2(-DOT_SIZE/2, -DOT_SIZE/2, DOT_SIZE, DOT_SIZE), COLOR)
            # Un círculo que se expande con la dispersión
            draw_arc(Vector2.ZERO, g + sz, 0, TAU, 24, COLOR, THICKNESS)
            
        2: # DOT (Ideal para láser)
            # Un simple punto que aumenta ligeramente de tamaño
            draw_circle(Vector2.ZERO, (DOT_SIZE + 2.0) * crosshair_scale, COLOR)
            
        3: # SNIPER (Ideal para francotirador)
            var snipe_color = Color(1.0, 0.2, 0.2, 0.9)
            var snipecr_color = Color(1.0, 1.0, 1.0, 0.9)
            draw_circle(Vector2.ZERO, 1.5, snipe_color)
            # Cruz completa que cruza toda la zona sin separarse
            draw_line(Vector2(0, -sz * 2), Vector2(0, sz * 2), snipecr_color, 1.0)
            draw_line(Vector2(-sz * 2, 0), Vector2(sz * 2, 0), snipecr_color, 1.0)
            # Círculo exterior fino
            draw_arc(Vector2.ZERO, sz * 1.5, 0, TAU, 32, snipe_color, 1.0)

        4: # CROSS ASALTO (Igual que la 0 pero GRANDE)
            # Punto central
            draw_rect(Rect2(-DOT_SIZE/2, -DOT_SIZE/2, DOT_SIZE, DOT_SIZE), COLOR)
            # Arriba
            draw_line(Vector2(0, -g - sz), Vector2(0, -g), COLOR, THICKNESS)
            # Abajo
            draw_line(Vector2(0, g), Vector2(0, g + sz), COLOR, THICKNESS)
            # Izquierda
            draw_line(Vector2(-g - sz, 0), Vector2(-g, 0), COLOR, THICKNESS)
            # Derecha
            draw_line(Vector2(g, 0), Vector2(g + sz, 0), COLOR, THICKNESS)