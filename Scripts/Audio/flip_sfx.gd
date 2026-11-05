## FlipSfx — global autoload for the card flip whoosh.
##
## Like HoverSfx, the flip belongs to the card rather than to a scene: every
## flip in the game goes through Card.animate_flip, which calls straight into
## this, so no scene controller has to wire it up.
extends Node

var player: AudioStreamPlayer


func _ready() -> void:
	player = CardSfx.create_flip_player()
	add_child(player)


## Call CardSfx.FLIP_PEAK_TIME before the card is edge-on.
func play_flip() -> void:
	player.play()
