extends Node

# Equivalente a tu load_sound() en weapon.py
var _sounds: Dictionary = {}

func _ready() -> void:
	_preload_sounds()

func _preload_sounds() -> void:
	var sound_files = {
		"pistol_fire":  "res://assets/sounds/pistol_fire.wav",
		"shotgun_fire": "res://assets/sounds/shotgun_fire.wav",
		"rifle_fire":   "res://assets/sounds/rifle_fire.wav",
	}
	for key in sound_files:
		var stream = load(sound_files[key])
		if stream:
			_sounds[key] = stream

func play(sound_name: String, volume_db: float = -14.0) -> void:
	if not _sounds.has(sound_name):
		return
	# Pool de AudioStreamPlayers para no bloquear
	var player = AudioStreamPlayer.new()
	add_child(player)
	player.stream = _sounds[sound_name]
	player.volume_db = volume_db
	player.play()
	player.finished.connect(player.queue_free)

func play_weapon_sound(weapon: WeaponData) -> void:
	if not weapon.fire_sound:
		return

	var player = AudioStreamPlayer.new()
	add_child(player)

	# Configuración inicial del sonido principal
	player.stream = weapon.fire_sound
	player.volume_db = weapon.fire_sound_volume
	# Variación aleatoria de pitch para mayor realismo (ej. que las metralletas no suenen robóticas)
	player.pitch_scale = weapon.fire_sound_pitch + randf_range(-weapon.fire_sound_pitch_rand, weapon.fire_sound_pitch_rand)

	# Lógica del retraso (delay)
	if weapon.fire_sound_delay > 0.0:
		await get_tree().create_timer(weapon.fire_sound_delay).timeout
		# Validamos si el nodo aún existe por si se cerró la escena durante el delay
		if not is_instance_valid(player): 
			return

	player.play()

	# Usamos un Callable (lambda) para manejar qué ocurre cuando termina el sonido
	var on_finished_callable = Callable()
	on_finished_callable = func():
		if weapon.fire_sound_loop:
			player.play() # Volver a reproducir
		elif weapon.fire_sound_tail:
			# Cambiar al sonido secundario (cola) y reproducir
			player.stream = weapon.fire_sound_tail
			player.play()
			
			# Desconectamos esta lambda para que no haga loop del tail
			player.finished.disconnect(on_finished_callable)
			# Conectamos para que libere memoria cuando termine el tail
			player.finished.connect(player.queue_free)
		else:
			# Si no hay loop ni cola, borramos el nodo
			player.queue_free()

	# Conectamos la señal de término del AudioStreamPlayer a nuestra lógica
	player.finished.connect(on_finished_callable)