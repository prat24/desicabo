## Music — global background music autoload. The title screen starts it once
## the title cards have landed; it loops forever and survives scene changes.
extends AudioStreamPlayer

const MUSIC_VOLUME_DB := -20.0


func _ready() -> void:
	var music: AudioStreamMP3 = preload("res://Assets/Sounds/Background.mp3")
	music.loop = true
	stream = music
	volume_db = MUSIC_VOLUME_DB


func start() -> void:
	if not playing:
		play()
