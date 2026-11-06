## CardMotion — the one way a card travels across the table.
##
## Every flight (a deal, a draw, a swap, a throw onto the pile) goes through
## fly(), so they all move alike:
##
## - The card follows one smooth curve over the whole flight: it eases off the
##   mark, is at full speed about a third of the way in, glides most of the rest
##   of the way, swings a hair past its spot and settles back. Quick, but every
##   frame of it is readable — no whip off the mark, no snap at the end.
## - It leans with its sideways speed, like a card held at the top and pulled
##   along: it tips into the move as it speeds up and swings back upright as it
##   settles. That lean, not the path, is what makes motion feel physical.
## - It turns to its new orientation *while* it travels (the shortest way
##   round), riding the same curve, so it never arrives sideways and then
##   snaps straight.
##
## A flight works in global space, so a card can leave one hand and land in
## another hand that faces a different way: it arrives already turned to sit in
## its new slot.
class_name CardMotion
extends RefCounted

## How far past its mark a card swings before settling back: the "back" of an
## ease-out-back curve. 0.5 overshoots by under 1% of the distance — felt as the
## card settling into place rather than seen as a bounce.
const OVERSHOOT := 0.5

## Degrees of lean per pixel-per-second of sideways speed, and the most a card
## will ever lean, so a long fast flight tips noticeably without tumbling. The
## limit is approached softly, so a card never visibly hits it.
const LEAN_PER_SPEED := 0.0028
const MAX_LEAN_DEGREES := 13.0
## The shadow drifts out with the card's speed, so a moving card reads as
## lifted off the felt and tucks back under as it lands.
const SHADOW_LIFT := 0.9
## A turn bigger than this (a half-turn, more or less) goes round the way the
## card curls instead of whichever way is a hair shorter, so cards dealt across
## the table all spin the same way rather than alternating with the fan tilt.
const LONG_TURN := deg_to_rad(150.0)


## Adds a flight of `card` to `tween`: from where the card is now to
## `to_position`, turned to `to_rotation` and sized to `to_scale` on arrival.
## Position and rotation are global (radians); scale is the card's own, which
## is all the game needs since nothing that holds a card is scaled itself.
##
## `duration` is the whole flight including the settle — the card is about
## five-sixths of the way there halfway through, and the rest is the glide in.
##
## `arc` bows the path out sideways by that fraction of the distance, to the
## left of travel for a positive value (and swings a half-turn clockwise). Two
## cards trading places with the same arc pass beside each other instead of
## through each other; a plain move goes straight.
##
## Add a landing cue with cue_on_landing(). Create `tween` parallel when other
## flights or cues share it.
static func fly(
	tween: Tween,
	card: Node2D,
	to_position: Vector2,
	to_rotation: float,
	to_scale: Vector2,
	duration: float,
	arc: float = 0.0
) -> MethodTweener:
	var from_position: Vector2 = card.global_position
	var from_rotation: float = card.global_rotation
	var from_scale: Vector2 = card.scale

	var travel: Vector2 = to_position - from_position
	var bow: Vector2 = travel.orthogonal() * arc

	var curl: float = -1.0 if arc < 0.0 else 1.0
	var turn: float = angle_difference(from_rotation, to_rotation)
	if absf(turn) > LONG_TURN and signf(turn) != curl:
		turn -= TAU * signf(turn)

	var shadow: Sprite2D = (card as Card).shadow if card is Card else null
	var shadow_rest: Vector2 = (card as Card).shadow_rest_position if card is Card else Vector2.ZERO

	var max_lean: float = deg_to_rad(MAX_LEAN_DEGREES)
	var lean_per_speed: float = deg_to_rad(LEAN_PER_SPEED)
	# Peak speed of the curve, to scale the shadow drift by.
	var peak_speed: float = _peak_rate()
	var span: float = maxf(duration, 0.01)

	var step := func(time: float) -> void:
		if not is_instance_valid(card):
			return
		var settled: bool = time >= duration
		var s: float = 1.0 if settled else _progress(time / span)
		# Per second, for the lean; per unit of flight, for the shadow.
		var rate: float = 0.0 if settled else _rate(time / span) / span
		# The bow rises and falls once over the flight, along a parabola.
		var bow_amount: float = 4.0 * s * (1.0 - s)
		var bow_rate: float = 4.0 * (1.0 - 2.0 * s) * rate

		var base_rotation: float = from_rotation + turn * s
		var velocity: Vector2 = travel * rate + bow * bow_rate
		# Sideways relative to the card itself, so a card lying sideways in a
		# right-edge hand leans as it moves up the screen.
		var sideways_speed: float = velocity.dot(Vector2.from_angle(base_rotation))
		var lean: float = max_lean * tanh(sideways_speed * lean_per_speed / max_lean)

		card.global_position = from_position + travel * s + bow * bow_amount
		card.global_rotation = base_rotation + lean
		card.scale = from_scale.lerp(to_scale, s)
		if shadow:
			shadow.position = shadow_rest * (1.0 + SHADOW_LIFT * absf(rate * span) / peak_speed)

	return tween.tween_method(step, 0.0, duration, duration)


## Adds `cue` to `tween` on the frame a flight of `duration` reads as landed.
static func cue_on_landing(tween: Tween, cue: Callable, duration: float) -> void:
	tween.parallel().tween_callback(cue).set_delay(landing_delay(duration))


## How long into a flight of `duration` the card first covers
## CardSfx.LANDED_PROGRESS of its way — the frame it reads as arrived, which is
## well before the settle at the end of the curve.
static func landing_delay(duration: float) -> float:
	const STEPS := 240
	for i in range(1, STEPS + 1):
		var u: float = float(i) / STEPS
		if _progress(u) >= CardSfx.LANDED_PROGRESS:
			return duration * u
	return duration


## The flight's progress at `u` (0 to 1 through its time): 0 to 1 along its
## path, a touch past 1 while it overshoots. An ease-out-back curve run on a
## clock that starts slow (w = u²(2 − u), which leaves the curve's end alone), so
## the card eases off its mark instead of leaving at full speed.
static func _progress(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	var d: float = u * u * (2.0 - u) - 1.0
	return 1.0 + (OVERSHOOT + 1.0) * d * d * d + OVERSHOOT * d * d


## How fast that progress is changing, per unit of `u`.
static func _rate(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	var d: float = u * u * (2.0 - u) - 1.0
	var clock_rate: float = u * (4.0 - 3.0 * u)
	return (3.0 * (OVERSHOOT + 1.0) * d * d + 2.0 * OVERSHOOT * d) * clock_rate


## The curve's top speed, per unit of `u` (it peaks about 30% through).
static func _peak_rate() -> float:
	var peak := 0.001
	for i in range(1, 32):
		peak = maxf(peak, _rate(i / 32.0))
	return peak
