## CardSfx — builds the card sound players shared by the menu and the game.
## Uses AudioStreamRandomizer so each play() picks a random variation with
## slight pitch drift, and polyphony so rapid sounds overlap instead of
## cutting each other off.
class_name CardSfx
extends RefCounted

const PLACE_SOUNDS = [
	preload("res://Assets/Sounds/cardPlace1.ogg"),
	preload("res://Assets/Sounds/cardPlace2.ogg"),
	preload("res://Assets/Sounds/cardPlace3.ogg"),
]
const SLIDE_SOUNDS = [
	preload("res://Assets/Sounds/cardSlide1.ogg"),
	preload("res://Assets/Sounds/cardSlide2.ogg"),
	preload("res://Assets/Sounds/cardSlide3.ogg"),
]


static func create_place_player() -> AudioStreamPlayer:
	return _create_player(PLACE_SOUNDS)


static func create_slide_player() -> AudioStreamPlayer:
	return _create_player(SLIDE_SOUNDS)


static func _create_player(sounds: Array) -> AudioStreamPlayer:
	var randomizer := AudioStreamRandomizer.new()
	randomizer.random_pitch = 1.1
	randomizer.random_volume_offset_db = 2.0
	for sound in sounds:
		randomizer.add_stream(-1, sound)

	var player := AudioStreamPlayer.new()
	player.stream = randomizer
	player.max_polyphony = 4
	player.volume_db = -8.0
	return player
