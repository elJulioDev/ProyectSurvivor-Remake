## OrbitalWeapon.gd
## Orbe Orbital — pasiva. Orbes girando alrededor del jugador que dañan por contacto.
## Empieza con 1 orbe. Mejoras: add_orb(), increase_speed(), increase_orbit_radius(),
## increase_damage_mult().
class_name OrbitalWeapon
extends Node2D

# ── Stats base ──────────────────────────────────────────────────────────────
var damage: float          = 45.0
var num_orbs: int          = 1       # empieza con 1
var orbit_radius: float    = 95.0    # radio de la órbita (px)
var orb_radius: float      = 10.0    # radio visual + hitbox del orbe
var orbit_speed: float     = 0.05    # rad/frame
var hit_cooldown_max: float = 35.0   # frames entre golpes al mismo enemigo

var owner_player: Node     = null

# ── Estado interno ──────────────────────────────────────────────────────────
var _angle: float           = 0.0
var _hit_cd: Dictionary     = {}    # id(enemy) → frames restantes

# ── Glow pre-allocado ───────────────────────────────────────────────────────
# (se reconstruye solo si cambia orb_radius)
var _glow_texture: ImageTexture = null
var _glow_radius: float         = -1.0

# ── Métodos de mejora ───────────────────────────────────────────────────────
func add_orb() -> void:
	num_orbs = min(4, num_orbs + 1)

func increase_speed(mult: float) -> void:
	orbit_speed = min(0.18, orbit_speed * mult)

func increase_orbit_radius(amount: float) -> void:
	orbit_radius += amount

func increase_damage_mult(mult: float) -> void:
	damage = int(damage * mult)

# ── Actualización ───────────────────────────────────────────────────────────
func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	_angle += orbit_speed * frames

	# Decrementar cooldowns de golpe
	var to_erase: Array = []
	for key in _hit_cd:
		_hit_cd[key] -= frames
		if _hit_cd[key] <= 0.0:
			to_erase.append(key)
	for key in to_erase:
		_hit_cd.erase(key)

	# Forzar redibujado
	queue_redraw()

	# Verificar hits
	_check_hits()

func _check_hits() -> void:
	if owner_player == null:
		return

	var damage_mult: float = owner_player.global_damage_mult
	var kb_mult: float     = owner_player.knockback_mult if "knockback_mult" in owner_player else 1.0
	var final_dmg: float   = damage * damage_mult
	var hit_r_sq: float    = (orb_radius + 10.0) ** 2
	var positions: Array   = _get_orb_positions()

	var enemies := get_tree().get_nodes_in_group("enemies")
	for orb_pos in positions:
		for enemy in enemies:
			if not enemy.has_method("take_damage"):
				continue
			var eid: int = enemy.get_instance_id()
			if _hit_cd.has(eid):
				continue
			var dx: float = enemy.global_position.x - orb_pos.x
			var dy: float = enemy.global_position.y - orb_pos.y
			if dx * dx + dy * dy <= hit_r_sq:
				_hit_cd[eid] = hit_cooldown_max
				var hit_dir: Vector2 = (enemy.global_position - orb_pos).normalized()
				enemy.take_damage(final_dmg, hit_dir)
				if enemy.has_method("apply_knockback"):
					enemy.apply_knockback(orb_pos, 9.0 * kb_mult)

# ── Posiciones de los orbes (en coordenadas mundo) ─────────────────────────
func _get_orb_positions() -> Array:
	if owner_player == null:
		return []
	var positions: Array = []
	var px: float = owner_player.global_position.x
	var py: float = owner_player.global_position.y
	var tau_n: float = TAU / float(num_orbs)
	for i in range(num_orbs):
		positions.append(Vector2(
			px + cos(_angle + tau_n * float(i)) * orbit_radius,
			py + sin(_angle + tau_n * float(i)) * orbit_radius
		))
	return positions

# ── Render ──────────────────────────────────────────────────────────────────
func _draw() -> void:
	if owner_player == null:
		return

	var positions: Array = _get_orb_positions()
	var r: float         = orb_radius
	var gs: float        = r * 3.0

	for orb_world in positions:
		# Convertir posición mundo a local (este nodo vive en el árbol del jugador)
		var orb_local: Vector2 = to_local(orb_world)

		# Glow difuso
		var glow_c := Color(0.2, 0.71, 1.0, 0.22)
		draw_circle(orb_local, gs, glow_c)

		# Cuerpo del orbe
		draw_circle(orb_local, r, Color(0.39, 0.82, 1.0, 1.0))
		# Brillo interior
		draw_circle(orb_local, max(1.0, r * 0.5), Color(0.86, 0.96, 1.0, 1.0))
		# Anillo exterior
		draw_arc(orb_local, r, 0.0, TAU, 32, Color(0.71, 0.90, 1.0, 0.85), 2)

# ── auto_shoot y shoot (compatibilidad con player) ─────────────────────────
func auto_shoot(_delta: float) -> void:
	pass  # Los orbes siempre están activos — la lógica está en update_weapon

func shoot() -> bool:
	return false