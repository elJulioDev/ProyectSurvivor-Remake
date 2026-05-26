extends CharacterBody2D
class_name Boss

signal boss_died(pos: Vector2, points: int, xp: int)
signal health_changed(current: float, maximum: float)

# ── Datos ──────────────────────────────────────────────────────
var data         : BossData = null
var max_health   : float    = 1500.0
var health       : float    = 1500.0
var damage       : int      = 40
var move_speed   : float    = 55.0
var is_alive     : bool     = true

# Multiplicadores (los mismos que SpawnManager pasa a los normales)
var health_mult  : float = 1.0
var damage_mult  : float = 1.0
var speed_mult   : float = 1.0

# ── Estado visual ──────────────────────────────────────────────
var _hit_flash   : float = 0.0
var _anim_timer  : float = 0.0
var _player      : Node2D = null
var _font        : Font

# Knockback
var _knockback   : Vector2 = Vector2.ZERO

# ── Sangrado continuo ──
var bleed_intensity : float = 0.0
var bleed_cooldown  : float = 0.0

# ── Constantes ─────────────────────────────────────────────────
const FRICTION        := 0.88
const INVULN_SECS     := 0.08   # pequeño iframes para no spamear daño
var   _invuln_timer   : float = 0.0

# ── Shader para el parpadeo ──
const FLASH_SHADER = """
shader_type canvas_item;
uniform float flash_opacity = 0.0;
void fragment() {
    // Mezcla los colores originales con blanco puro cuando recibe daño
    COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash_opacity);
}
"""

@onready var _col      : CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("boss")
	_font = ThemeDB.fallback_font
	
	# ── Asignar el shader al Boss ──
	var mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = FLASH_SHADER
	self.material = mat
	
	_apply_data()

func setup(boss_data: BossData, h_mult: float, d_mult: float, s_mult: float) -> void:
	data         = boss_data
	health_mult  = h_mult
	damage_mult  = d_mult
	speed_mult   = s_mult
	if is_node_ready():
		_apply_data()

func _apply_data() -> void:
	if data == null:
		return
		
	max_health = data.base_health  * health_mult
	health     = max_health
	damage     = maxi(1, int(data.base_damage * damage_mult))
	move_speed = data.base_speed   * speed_mult

	# Ajustar colisión al tamaño del boss
	var shape := RectangleShape2D.new()
	shape.size = Vector2(data.size, data.size)
	_col.shape = shape

	queue_redraw()

# ── Ciclo ──────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_anim_timer += delta

	if _invuln_timer > 0.0:
		_invuln_timer -= delta

	_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_player):
		return

	# Movimiento hacia el jugador
	var dir := ((_player.global_position - global_position).normalized()
				if global_position.distance_squared_to(_player.global_position) > 1.0
				else Vector2.ZERO)

	velocity = dir * move_speed

	# Knockback
	if _knockback.length_squared() > 0.01:
		_knockback *= pow(FRICTION, delta * 60.0)
		if _knockback.length() < 0.5:
			_knockback = Vector2.ZERO
	velocity += _knockback

	move_and_slide()
	_clamp_world()

	# Daño al jugador por contacto
	var half := data.size * 0.5 + 12.0
	if global_position.distance_squared_to(_player.global_position) < half * half:
		if _player.has_method("take_damage"):
			# Calculamos la dirección del empuje (desde el boss hacia el jugador)
			var hit_dir = global_position.direction_to(_player.global_position)
			
			# Pasamos: Daño | Dirección | Fuerza de empuje | Tiempo de noqueo (0.4s)
			_player.take_damage(damage, hit_dir, 1500.0, 0.4)

	# Flash de golpe
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)

	# ── Enviar la intensidad del flash al material ──
	if material:
		material.set_shader_parameter("flash_opacity", _hit_flash)

	# ── NUEVO: Goteo de sangre al caminar ──
	if bleed_intensity > 0.0:
		bleed_intensity -= 0.3 * delta * 60.0
		if bleed_intensity <= 0.0:
			bleed_intensity = 0.0
		else:
			bleed_cooldown -= delta * 60.0
			if bleed_cooldown <= 0.0:
				var particles := get_tree().get_first_node_in_group("blood_particles")
				if is_instance_valid(particles) and particles.has_method("create_blood_drip"):
					# Añadir un leve desfase aleatorio para que no gotee siempre desde el centro exacto
					var drip_pos = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
					particles.create_blood_drip(drip_pos, bleed_intensity)
				
				# El cooldown será más rápido entre mayor sea la herida (igual que en EnemyManager)
				bleed_cooldown = maxf(2.0, 20.0 - (bleed_intensity * 0.8))

	# Flash de golpe
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)

	queue_redraw()

func _clamp_world() -> void:
	var h := data.size * 0.5
	global_position.x = clampf(global_position.x, h, GameManager.WORLD_WIDTH  - h)
	global_position.y = clampf(global_position.y, h, GameManager.WORLD_HEIGHT - h)

# ── API pública ────────────────────────────────────────────────

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if not is_alive:
		return
		
	health       -= amount
	_hit_flash    = 1.0
	emit_signal("health_changed", health, max_health)

	if knockback_force > 0.0 and hit_dir != Vector2.ZERO:
		_knockback += hit_dir.normalized() * knockback_force * 0.15

	# ── Acumular intensidad de sangrado ──
	bleed_intensity = minf(50.0, bleed_intensity + amount)

	# Sistema de salpicadura de sangre y manchas (Impacto inicial)
	var particles := get_tree().get_first_node_in_group("blood_particles")
	if is_instance_valid(particles):
		var dmg_ratio := clampf(amount / max_health * 6.0, 0.0, 1.0)
		if particles.has_method("create_blood_splatter"):
			particles.create_blood_splatter(global_position, hit_dir, 1.4, 12, dmg_ratio)
		if (amount > 10.0 or dmg_ratio > 0.1) and particles.has_method("create_wound_stain"):
			particles.create_wound_stain(global_position, dmg_ratio)

	if health <= 0.0:
		health   = 0.0
		is_alive = false
		emit_signal("boss_died", global_position, data.points, data.xp_reward)
		queue_free()

# ── Dibujo ─────────────────────────────────────────────────────

func _draw() -> void:
	if data == null:
		return

	var half := data.size * 0.5

	if data.sprite_texture:
		# Sprite personalizado
		var tex_size := Vector2(data.size, data.size)
		draw_texture_rect(data.sprite_texture,
			Rect2(-tex_size * 0.5, tex_size), false)
	else:
		# Color sólido con flash de daño
		var col := data.color
		if _hit_flash > 0.0:
			col = col.lerp(Color.WHITE, _hit_flash * 0.85)

		# Cuerpo
		draw_rect(Rect2(-half, -half, data.size, data.size), col)

		# Borde oscuro
		var border := Color(col.r * 0.4, col.g * 0.4, col.b * 0.4)
		draw_rect(Rect2(-half, -half, data.size, data.size), border, false, 3.0)

		# Centro
		var c_size := data.size * 0.28
		draw_rect(Rect2(-c_size * 0.5, -c_size * 0.5, c_size, c_size), border)

	_draw_health_bar(half)
	_draw_name(half)

func _draw_health_bar(half: float) -> void:
	if data == null or not is_alive:
		return

	var bar_w  := data.size * 1.8
	var bar_h  := 10.0
	var bx     := -bar_w * 0.5
	var by     := half + 12.0
	var pct    := clampf(health / max_health, 0.0, 1.0)

	# Fondo
	draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.1, 0.0, 0.0))

	# Relleno — verde→amarillo→rojo
	var fill_col : Color
	if pct > 0.5:
		fill_col = Color(0.18, 0.80, 0.44)
	elif pct > 0.25:
		fill_col = Color(0.94, 0.77, 0.06)
	else:
		fill_col = Color(0.90, 0.20, 0.10)

	draw_rect(Rect2(bx, by, bar_w * pct, bar_h), fill_col)
	draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.8, 0.8, 0.8, 0.5), false, 1.5)

	# Texto de HP
	if is_instance_valid(_font):
		var hp_str := "%d / %d" % [int(health), int(max_health)]
		var tw     := _font.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_font,
			Vector2(-tw * 0.5, by + bar_h + 14.0),
			hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.9, 0.9, 0.9))

func _draw_name(half: float) -> void:
	if data == null or not is_instance_valid(_font):
		return
	var pulse : float = abs(sin(_anim_timer * 2.0)) * 0.3 + 0.7
	var col   := Color(data.color.r, data.color.g, data.color.b, pulse)
	var tw    := _font.get_string_size(data.boss_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(_font,
		Vector2(-tw * 0.5, -half - 18.0),
		data.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
