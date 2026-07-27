## OverlayButton — the small dark-glass buttons that sit in a screen's corner
## over whatever is already there: Back on the title screen, and the menu button
## in a game. Built here rather than in each screen so the two always match.
class_name OverlayButton
extends RefCounted

const UI_THEME := preload("res://Assets/Themes/clean_ui.tres")
## Comfortably tappable with a thumb without taking up any real room.
const HEIGHT := 92.0
const CORNER_RADIUS := 26
## Distance from the two screen edges it tucks into.
const MARGIN := 40.0
## Corner buttons arrive and leave by sliding out of the top edge rather than
## blinking on and off, which reads as being handed something.
const SLIDE_TIME := 0.28
## Where the resting spot is kept, so repeated shows never drift.
const REST_POSITION_META := "rest_position"

# ── Bars of the menu icon ─────────────────────────────────────────────────────
const BAR_SIZE := Vector2(40.0, 5.0)
const BAR_GAP := 13.0


## A labelled button. It has no width of its own — the side padding gives it
## one, so it comes out however wide its text needs.
static func create_text(text: String, on_pressed: Callable, font_size := 38) -> Button:
	var button := make_button(on_pressed)
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size = Vector2(0.0, HEIGHT)
	button.size = Vector2(0.0, HEIGHT)
	return button


## A square button carrying the usual three-bar menu mark. Drawn from plain
## rectangles, so it needs no glyph the interface font might not have.
static func create_menu_icon(on_pressed: Callable) -> Button:
	var button := make_button(on_pressed)
	button.size = Vector2(HEIGHT, HEIGHT)
	button.custom_minimum_size = button.size

	for i in range(3):
		var bar := ColorRect.new()
		bar.color = UiPalette.ACCENT
		bar.size = BAR_SIZE
		bar.position = Vector2(
			(HEIGHT - BAR_SIZE.x) * 0.5,
			(HEIGHT - BAR_SIZE.y) * 0.5 + (i - 1) * BAR_GAP
		)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(bar)

	return button


## Show or hide a corner button by sliding it through the top of the screen.
## The resting spot is wherever it was placed, remembered the first time so a
## button that comes and goes always lands back in the same place.
static func set_shown(button: Button, shown: bool) -> void:
	if not button.has_meta(REST_POSITION_META):
		button.set_meta(REST_POSITION_META, button.position)

	var rest: Vector2 = button.get_meta(REST_POSITION_META)
	var offscreen := Vector2(rest.x, -button.size.y)

	# Already where it was asked to be, and not part-way through getting there.
	var target := rest if shown else offscreen
	if button.visible == shown and button.position.is_equal_approx(target):
		return

	var slide := button.create_tween().set_parallel(true)
	if shown:
		button.position = offscreen
		button.modulate.a = 0.0
		button.visible = true
		slide.tween_property(button, "position", rest, SLIDE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		slide.tween_property(button, "modulate:a", 1.0, SLIDE_TIME * 0.6)
		return

	slide.tween_property(button, "position", offscreen, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	slide.tween_property(button, "modulate:a", 0.0, SLIDE_TIME)
	# Hidden outright at the end, so it cannot be tapped on its way out.
	slide.tween_callback(func() -> void: button.visible = false).set_delay(SLIDE_TIME)


static func make_button(on_pressed: Callable) -> Button:
	var button := Button.new()
	button.theme = UI_THEME
	button.focus_mode = Control.FOCUS_NONE
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, UiPalette.ACCENT)

	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.GLASS
	style.set_corner_radius_all(CORNER_RADIUS)
	# Wide side margins give a labelled button its width; the vertical ones stay
	# under HEIGHT so text and icon buttons come out the same height.
	style.set_content_margin_all(28.0)
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = UiPalette.GLASS_PRESSED
	button.add_theme_stylebox_override("pressed", pressed_style)

	button.pressed.connect(on_pressed)
	return button
