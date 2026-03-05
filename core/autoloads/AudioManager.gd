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
