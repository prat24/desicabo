## CardSfx — builds the card sound players shared by the menu and the game.
## Uses AudioStreamRandomizer so each play() picks a random variation with
## slight pitch drift, and polyphony so rapid sounds overlap instead of
## cutting each other off.
##
## Three cues: `slide` when a card starts moving, `place` the instant it lands,
## and `hover` when a card's hover animation starts. Call each at the exact
## frame of the event — never on a timer or a fraction of a flight time. The
## samples are trimmed one-shots (see below), so the sound is heard as soon as
## it is triggered.
##
## The samples are head-trimmed WAVs, not the raw source files. The originals
## carry 35-286 ms of dead air plus a long approach rustle before their main
## transient, and the amount differs per variation — so the same cue landed
## anywhere from 60 ms to 450 ms late depending on which one the randomizer
## picked. They are cut so every variation hits within ~80 ms of being
## triggered. Any replacement sample must be trimmed the same way.
class_name CardSfx
extends RefCounted

## Level for the positional cues: -10 dB from the original mix, which halves
## perceived loudness.
const CARD_VOLUME_DB := -18.0
## Hover fires constantly as the pointer crosses a hand, so it sits far under
## the cues that mark an actual move. The sample is ~15 dB hotter in RMS than
## the place/slide ones, and this level still lands its peak ~25 dB below
## theirs — felt more than heard, and never something you notice on its own.
const HOVER_VOLUME_DB := -48.0

const PLACE_SOUNDS = [
	preload("res://Assets/Sounds/cardPlace1.wav"),
	preload("res://Assets/Sounds/cardPlace2.wav"),
	preload("res://Assets/Sounds/cardPlace3.wav"),
]
const SLIDE_SOUNDS = [
	preload("res://Assets/Sounds/cardSlide1.wav"),
	preload("res://Assets/Sounds/cardSlide2.wav"),
	preload("res://Assets/Sounds/cardSlide3.wav"),
]
## One sample rather than a set, so the pitch drift below carries the variation.
const HOVER_SOUNDS = [
	preload("res://Assets/Sounds/cardHover.wav"),
]


static func create_place_player() -> AudioStreamPlayer:
	return _create_player(PLACE_SOUNDS, CARD_VOLUME_DB)


static func create_slide_player() -> AudioStreamPlayer:
	return _create_player(SLIDE_SOUNDS, CARD_VOLUME_DB)


static func create_hover_player() -> AudioStreamPlayer:
	return _create_player(HOVER_SOUNDS, HOVER_VOLUME_DB)


static func _create_player(sounds: Array, volume_db: float) -> AudioStreamPlayer:
	var randomizer := AudioStreamRandomizer.new()
	randomizer.random_pitch = 1.1
	randomizer.random_volume_offset_db = 2.0
	for sound in sounds:
		randomizer.add_stream(-1, sound)

	var player := AudioStreamPlayer.new()
	player.stream = randomizer
	player.max_polyphony = 4
	player.volume_db = volume_db
	player.bus = AudioBuses.SFX
	return player
