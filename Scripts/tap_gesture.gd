## TapGesture — tells a quick tap apart from a press-and-hold.
##
## On a phone the finger is also the pointer: resting it on a card is the only
## way to hover one, so acting the moment it touches down fires the click on
## every hover. Instead the press only starts the gesture and the action runs
## on release — either as a quick tap, or after resting on one card long enough
## that the choice is plainly deliberate. The stretch in between is browsing:
## the card hovers, and lifting off leaves it unpicked.
class_name TapGesture
extends RefCounted

## Longest a press can last and still count as a tap.
const MAX_TAP_TIME := 0.35
## How far the pointer may travel during a tap, in viewport pixels.
const MAX_TAP_DISTANCE := 60.0
## How long the pointer must rest on one card before lifting off it picks it.
const DWELL_TIME := 1.2

## The device has a single pointer, so its state is shared by everything that
## has to know whether the thing beneath it should look hovered.
static var is_touch_pointer := false
static var is_pointer_down := false

var press_position := Vector2.ZERO
var press_msec := 0
var dwell_msec := 0
var has_press := false


## Whether whatever sits under the pointer should look hovered right now. A
## finger only points while it is held down: once it lifts, the pointer stays
## parked on its last spot, and treating that ghost as a hover lights up cards
## nobody is touching. A mouse hovers wherever it sits.
static func is_pointer_hovering() -> bool:
	return is_pointer_down or not is_touch_pointer


func press(event: InputEventMouseButton, position: Vector2) -> void:
	# Godot stamps DEVICE_ID_EMULATION on the mouse events it synthesizes from
	# touches — the only way to tell a finger from a real mouse.
	is_touch_pointer = event.device == InputEvent.DEVICE_ID_EMULATION
	is_pointer_down = true
	has_press = true
	press_position = position
	press_msec = Time.get_ticks_msec()
	dwell_msec = 0


## Call whenever the card under the pointer changes, so the dwell clock only
## ever times the current one. Passing false (nothing under it) stops it —
## unless the target was lost because the finger lifted, which is the very
## release the clock exists to answer, not a change of mind.
func hover_target_changed(has_target: bool) -> void:
	if has_target:
		dwell_msec = Time.get_ticks_msec()
	elif is_pointer_hovering():
		dwell_msec = 0


## True when lifting here should act: a quick tap that stayed where it started,
## or a long rest on one card — holding still that long is a choice, not a
## look. A release with no matching press never counts.
func release(position: Vector2) -> bool:
	is_pointer_down = false
	if not has_press:
		return false

	has_press = false
	if dwell_msec > 0 and Time.get_ticks_msec() - dwell_msec >= DWELL_TIME * 1000.0:
		return true

	var held_time: float = (Time.get_ticks_msec() - press_msec) / 1000.0
	return held_time <= MAX_TAP_TIME and position.distance_to(press_position) <= MAX_TAP_DISTANCE
