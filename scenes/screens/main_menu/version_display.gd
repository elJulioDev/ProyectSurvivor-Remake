extends Label

@export var prefix := "v"

func _ready() -> void:
	# Extraemos la versión global (el segundo parámetro es un valor por defecto por si falla)
	var game_version: String = ProjectSettings.get_setting("application/config/version", "0.0.1")
	
	# OS.has_feature("editor") asegura que solo sea true dentro del editor de Godot
	if OS.has_feature("editor"):
		text = prefix + game_version + " [DEBUG]"
	else:
		# Versión limpia para el jugador final exportado
		text = prefix + game_version