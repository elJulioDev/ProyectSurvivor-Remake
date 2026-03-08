## OrbitalWeapon.gd
class_name OrbitalWeapon
extends Node2D

var damage: float          = 45.0
var num_orbs: int          = 1
var orbit_radius: float    = 95.0
var orb_radius: float      = 10.0
var orbit_speed: float     = 0.05
var hit_cooldown_max: float = 35.0

var owner_player: Node = null

var _angle:  float      = 0.0
var _hit_cd: Dictionary = {}   # idx → frames restantes

func add_orb()                        -> void: num_orbs = mini(4, num_orbs + 1)
func increase_speed(mult: float)      -> void: orbit_speed = minf(0.18, orbit_speed * mult)
func increase_orbit_radius(a: float)  -> void: orbit_radius += a
func increase_damage_mult(m: float)   -> void: damage = int(damage * m)

func update_weapon(delta: float) -> void:
	var frames: float = delta * 60.0
	_angle += orbit_speed * frames

	var to_erase: Array = []
	for key in _hit_cd:
		_hit_cd[key] -= frames
		if _hit_cd[key] <= 0.0: to_erase.append(key)
	for key in to_erase: _hit_cd.erase(key)

	queue_redraw()
	_check_hits()

func _check_hits() -> void:
	if owner_player == null: return
	var damage_mult: float = owner_player.global_damage_mult
	var kb_mult: float     = owner_player.knockback_mult if "knockback_mult" in owner_player else 1.0
	var final_dmg: float   = damage * damage_mult
	var hit_r: float       = orb_radius + 10.0
	var positions: Array   = _get_orb_positions()

	for orb_pos in positions:
		# ── Spatial query ────────────────────────────────────────
		var hits : PackedInt32Array = GameManager.enemy_manager.get_enemies_near_proxy(orb_pos, hit_r)
		for idx in hits:
			if _hit_cd.has(idx): continue
			_hit_cd[idx] = hit_cooldown_max
			var enemy_pos = GameManager.enemy_manager.positions[idx]
			var hit_dir: Vector2 = (enemy_pos - orb_pos).normalized()
			GameManager.enemy_manager.damage_enemy(idx, final_dmg, hit_dir, 9.0 * kb_mult)

func _get_orb_positions() -> Array:
	if owner_player == null: return []
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

func _draw() -> void:
	if owner_player == null: return
	var positions: Array = _get_orb_positions()
	var r: float         = orb_radius
	var gs: float        = r * 3.0
	for orb_world in positions:
		var orb_local: Vector2 = to_local(orb_world)
		draw_circle(orb_local, gs,  Color(0.2, 0.71, 1.0, 0.22))
		draw_circle(orb_local, r,   Color(0.39, 0.82, 1.0, 1.0))
		draw_circle(orb_local, maxf(1.0, r * 0.5), Color(0.86, 0.96, 1.0, 1.0))
		draw_arc(orb_local, r, 0.0, TAU, 32, Color(0.71, 0.90, 1.0, 0.85), 2)

func auto_shoot(_delta: float) -> void: pass
func shoot() -> bool: return false