## ScreenShape — global autoload that keeps the board phone-shaped.
##
## Every layout in the game is built for a screen 1080 wide and at least 1920
## tall, which is what any phone held upright gives it. A window wider than
## that — a laptop's browser, say — would otherwise stretch the board sideways:
## the piles and hands would sit somewhere else than on everyone else's screen,
## and a card another player drags would land in the wrong place. So a wide
## window gets the phone-shaped board instead, centred between bars.
extends Node

## The narrowest shape the layouts are built for, width over height.
const PHONE_ASPECT := 1080.0 / 1920.0


func _ready() -> void:
	get_tree().root.size_changed.connect(fit_to_window)
	fit_to_window()


## Phones and tall windows keep growing the board downward ("expand"); anything
## wider than a phone keeps the phone's shape exactly ("keep").
func fit_to_window() -> void:
	var root := get_tree().root
	var window := Vector2(root.size)
	var too_wide := window.y > 0.0 and window.x / window.y > PHONE_ASPECT
	var aspect := Window.CONTENT_SCALE_ASPECT_KEEP if too_wide else Window.CONTENT_SCALE_ASPECT_EXPAND
	# Changing it resizes the board, which fires size_changed again; only
	# change it when it really differs, so that settles in one step.
	if root.content_scale_aspect != aspect:
		root.content_scale_aspect = aspect
