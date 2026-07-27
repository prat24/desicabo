## GameMenuPanel — the small card behind the in-game corner button: start the
## game over, or leave for the title screen. It pops in the middle of the board
## rather than sliding from an edge, since the player who opened it may be
## holding the phone upside down or sideways — `facing_degrees` turns it to
## them. Tapping anywhere outside puts it away.
class_name GameMenuPanel
extends Control

signal restart_requested
signal quit_requested
signal closed

const UI_THEME := preload("res://Assets/Themes/clean_ui.tres")
const BACKDROP_ALPHA := 0.6
const POP_TIME := 0.2
const PANEL_WIDTH := 640.0
const PANEL_PADDING := 48.0
const BUTTON_HEIGHT := 124.0

## Which way is up for the player who opened this, in degrees.
var facing_degrees := 0.0
## Passed in: a Control parented to a Node2D gets no viewport size of its own.
var screen: Vector2 = Vector2(1080.0, 1920.0)

var backdrop: ColorRect
var panel: Panel
var layout: VBoxContainer
var is_open := false
var is_closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_backdrop()
	build_panel()
	animate_in()


func build_backdrop() -> void:
	backdrop = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, BACKDROP_ALPHA)
	backdrop.position = Vector2.ZERO
	backdrop.size = screen
	backdrop.modulate.a = 0.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(on_backdrop_input)
	add_child(backdrop)


func build_panel() -> void:
	panel = Panel.new()
	panel.add_theme_stylebox_override("panel", make_panel_style())
	panel.size = Vector2(PANEL_WIDTH, 0.0)
	# Swallow taps so a press on the card never reaches the closing backdrop.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	layout = VBoxContainer.new()
	layout.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	layout.size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2.0, 0.0)
	layout.add_theme_constant_override("separation", 24)
	panel.add_child(layout)

	layout.add_child(make_button("Restart Game", on_restart_pressed))
	layout.add_child(make_button("Return to Main Menu", on_quit_pressed))
	layout.add_child(make_hint("Tap anywhere else to close"))

	# Sized to its rows, then turned and centred about its own middle so it
	# reads the right way up from its player's side of the table.
	var content_height: float = layout.get_combined_minimum_size().y
	layout.size.y = content_height
	panel.size.y = content_height + PANEL_PADDING * 2.0
	panel.pivot_offset = panel.size * 0.5
	panel.rotation_degrees = facing_degrees
	panel.position = (screen - panel.size) * 0.5


func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.ACCENT
	style.set_corner_radius_all(32)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	return style


func make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = UI_THEME
	button.add_theme_font_size_override("font_size", 44)
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE

	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, UiPalette.ACCENT)

	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.INK
	style.set_corner_radius_all(16)
	style.set_content_margin_all(18.0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.25, 0.22, 0.18)
	button.add_theme_stylebox_override("pressed", pressed_style)

	button.pressed.connect(on_pressed)
	return button


func make_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", UiPalette.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func on_restart_pressed() -> void:
	if not is_open:
		return
	restart_requested.emit()


func on_quit_pressed() -> void:
	if not is_open:
		return
	quit_requested.emit()


func on_backdrop_input(event: InputEvent) -> void:
	# Ignore taps until the card is fully up, so the tap that opened it cannot
	# immediately dismiss it again.
	if not is_open:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		close()


func animate_in() -> void:
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var pop := create_tween().set_parallel(true)
	pop.tween_property(backdrop, "modulate:a", 1.0, POP_TIME)
	pop.tween_property(panel, "scale", Vector2.ONE, POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(panel, "modulate:a", 1.0, POP_TIME * 0.7)
	await pop.finished
	is_open = true


func close() -> void:
	if is_closing:
		return
	is_closing = true
	is_open = false

	var fade := create_tween().set_parallel(true)
	fade.tween_property(backdrop, "modulate:a", 0.0, POP_TIME * 0.7)
	fade.tween_property(panel, "modulate:a", 0.0, POP_TIME * 0.7)
	fade.tween_property(panel, "scale", Vector2(0.9, 0.9), POP_TIME * 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await fade.finished

	closed.emit()
	queue_free()
