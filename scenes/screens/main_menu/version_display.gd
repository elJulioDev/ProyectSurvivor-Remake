extends Label

@export var prefix := "v"

func _ready() -> void:
	# Extraemos la versión global (el segundo parámetro es un valor por defecto por si falla)
	var game_version: String = ProjectSettings.get_setting("application/config/version", "0.0.1")
	
	# Detectamos si estamos ejecutando el juego desde el editor (modo Debug)
	if OS.is_debug_build():
		text = prefix + game_version + " [DEBUG]"
	else:
		# Versión limpia para el jugador final
		text = prefix + game_version