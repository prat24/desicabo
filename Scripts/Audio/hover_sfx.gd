## HoverSfx — global autoload for the card hover swoosh.
##
## Hover belongs to the card, not to the menu or the game controller, so both
## hover entry points (PlayerCard.set_drag_hovered and BoardCard's
## mouse_entered) call straight into this instead of the per-scene sfx players.
## Routing it through the scene controllers would mean wiring a signal on every
## card the hand deals.
extends Node

## Pointer jitter on the seam between two fanned cards flips the hover back and
## forth every few frames. One swoosh per this window keeps that from turning
## into a stutter.
const RETRIGGER_COOLDOWN := 0.05

var player: AudioStreamPlayer
var last_play_seconds := -1.0


func _ready() -> void:
	player = CardSfx.create_hover_player()
	add_child(player)


## Call on the frame the hover animation starts, not when it finishes.
func play_hover() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_play_seconds < RETRIGGER_COOLDOWN:
		return

	last_play_seconds = now
	player.play()
