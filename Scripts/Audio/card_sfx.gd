## CardSfx — builds the card sound players shared by the menu and the game.
## Uses AudioStreamRandomizer so each play() picks a random variation with
## slight pitch drift, and polyphony so rapid sounds overlap instead of
## cutting each other off.
##
## Four cues: `slide` when a card starts moving, `place` when it lands, `hover`
## when a card's hover animation starts, and `flip` as a card turns over. Each
## fires from the tween that animates its event, never from a separate timer.
## A landing fires when the card reads as arrived, not on the tween's last
## frame (see cue_on_landing()).
##
## The place, slide and hover samples are head-trimmed WAVs, not the raw
## source files. Each starts 3 ms before its main transient, faded in over
## those 3 ms, so it is heard on the frame it is triggered. The source
## recordings carried 45-80 ms of rustle before the hit, and the amount
## differed per variation, so the same cue used to land at a different moment
## each time. Any replacement sample must be trimmed the same way.
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
## The flip whoosh is ~11 dB hotter in RMS than the place samples. This sits
## it ~4 dB under them: a flip is lighter than a card landing, and the reveals
## turn a whole hand over in a row.
const FLIP_VOLUME_DB := -33.0
## The flip is a whoosh, not a hit: it swells for this long before its peak.
## Card.animate_flip starts it this early, so the peak lands on the frame the
## card is edge-on.
const FLIP_PEAK_TIME := 0.045

## How far along its path a flight has to be to read as landed. Ease-out
## curves crawl the last few pixels: a cubic ease-out covers only the final 2%
## of its distance in the last 27% of its time, so a cue on the last frame is
## heard up to 120 ms after the eye sees the card arrive.
const LANDED_PROGRESS := 0.98

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
## A whoosh cut to its swell and peak, sped up 1.8x (which raises the pitch
## with it) and high-passed at 350 Hz, so it is a light card turning rather
## than something heavy going past.
const FLIP_SOUNDS = [
	preload("res://Assets/Sounds/cardFlip.wav"),
]


static func create_place_player() -> AudioStreamPlayer:
	return _create_player(PLACE_SOUNDS, CARD_VOLUME_DB)


static func create_slide_player() -> AudioStreamPlayer:
	return _create_player(SLIDE_SOUNDS, CARD_VOLUME_DB)


static func create_hover_player() -> AudioStreamPlayer:
	return _create_player(HOVER_SOUNDS, HOVER_VOLUME_DB)


static func create_flip_player() -> AudioStreamPlayer:
	return _create_player(FLIP_SOUNDS, FLIP_VOLUME_DB)


## Adds `cue` to `tween`, on the frame a flight of `duration` along this
## curve reads as landed. Add the flight first: the cue runs alongside the
## tween's last step, so the tween has to be parallel or end with the flight.
static func cue_on_landing(
	tween: Tween,
	cue: Callable,
	duration: float,
	trans_type: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease_type: Tween.EaseType = Tween.EASE_OUT
) -> void:
	tween.parallel().tween_callback(cue).set_delay(landing_delay(duration, trans_type, ease_type))


## How long into a flight it first covers LANDED_PROGRESS of its path.
static func landing_delay(duration: float, trans_type: Tween.TransitionType, ease_type: Tween.EaseType) -> float:
	const STEPS := 240
	for step in range(1, STEPS + 1):
		var elapsed: float = duration * step / STEPS
		var progress: float = Tween.interpolate_value(0.0, 1.0, elapsed, duration, trans_type, ease_type)
		if progress >= LANDED_PROGRESS:
			return elapsed
	return duration


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
