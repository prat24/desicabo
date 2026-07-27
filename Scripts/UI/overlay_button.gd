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
