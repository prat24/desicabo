## SettingsPanel — beige settings card that slides down over the title screen,
## dimming everything behind it. Tapping outside the card closes it.
class_name SettingsPanel
extends Control

signal closed

const UI_THEME := preload("res://Assets/Themes/clean_ui.tres")
const TRACK_COLOR := Color(0.76, 0.72, 0.64)
const FILL_COLOR := Color(0.35, 0.3, 0.24)
const BACKDROP_ALPHA := 0.75
const SLIDE_TIME := 0.35
## Resting distance from the top of the screen once the card has slid in. The
## card's height is whatever its contents need — see fit_to_contents().
const PANEL_TOP := 300.0
const PANEL_MARGIN_X := 90.0
const PANEL_PADDING := 56.0
const GRABBER_DIAMETER := 56

var backdrop: ColorRect
var panel: Panel
var layout: VBoxContainer
var slide_tween: Tween
var is_open := false
var is_closing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 600
	build_backdrop()
	build_panel()
	fit_to_contents()
	panel.position.y = -panel.size.y
	animate_in()


func build_backdrop() -> void:
	backdrop = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, BACKDROP_ALPHA)
	backdrop.size = get_viewport_rect().size
	backdrop.modulate.a = 0.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(on_backdrop_input)
	add_child(backdrop)


func build_panel() -> void:
	var panel_width: float = get_viewport_rect().size.x - PANEL_MARGIN_X * 2.0

	panel = Panel.new()
	panel.add_theme_stylebox_override("panel", make_panel_style())
	panel.size = Vector2(panel_width, 0.0)
	panel.position = Vector2(PANEL_MARGIN_X, 0.0)
	# Swallow taps so clicks on the card never reach the closing backdrop.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	layout = VBoxContainer.new()
	layout.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	layout.size = Vector2(panel_width - PANEL_PADDING * 2.0, 0.0)
	layout.add_theme_constant_override("separation", 44)
	panel.add_child(layout)

	var title := make_label("SETTINGS", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)

	layout.add_child(make_slider_row("Music", AudioSettings.music_volume, AudioSettings.set_music_volume, format_percent))
	layout.add_child(make_slider_row("Sound Effects", AudioSettings.sfx_volume, AudioSettings.set_sfx_volume, format_percent))
	layout.add_child(make_slider_row("Bot Difficulty", GameSettings.bot_difficulty, GameSettings.set_bot_difficulty, format_difficulty))


## Close the card around whatever it holds, with the same padding all round.
## Nothing here wraps, so every row can say how tall it is right away.
func fit_to_contents() -> void:
	var content_height: float = layout.get_combined_minimum_size().y
	layout.size.y = content_height
	panel.size.y = content_height + PANEL_PADDING * 2.0


func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.ACCENT
	style.set_corner_radius_all(32)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	return style


func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


## One labelled slider row. `describe` turns the 0..1 value into the readout
## beside the name, which tracks the slider live.
func make_slider_row(row_name: String, value: float, apply_value: Callable, describe: Callable) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var header := HBoxContainer.new()
	var name_label := make_label(row_name, 40)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var value_label := make_label(describe.call(value), 40)
	header.add_child(value_label)
	row.add_child(header)

	var slider := make_slider(value)
	slider.value_changed.connect(func(new_value: float) -> void:
		apply_value.call(new_value)
		value_label.text = describe.call(new_value)
	)
	row.add_child(slider)

	return row


func format_percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


## Difficulty reads as a word, not a number — what the slider moves is how well
## the bots remember their cards, and no percentage says that. The two ends are
## named for the ends themselves, not for the band leading up to them.
func format_difficulty(value: float) -> String:
	if value <= 0.0:
		return "Dumbass"
	if value >= 1.0:
		return "Bot, James Bot"
	if value < 0.2:
		return "Forgetful"
	if value < 0.45:
		return "Casual"
	if value < 0.7:
		return "Sharp"
	if value < 0.9:
		return "Ruthless"
	return "Card Counter"


func make_slider(value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(0.0, GRABBER_DIAMETER)

	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	track.set_corner_radius_all(10)
	track.set_content_margin_all(10.0)
	slider.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = FILL_COLOR
	fill.set_corner_radius_all(10)
	fill.set_content_margin_all(10.0)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	# The default theme's grabber is a few pixels wide — far too small to drag
	# on a phone, so the knob is drawn at touch size instead.
	var grabber := make_grabber_texture(GRABBER_DIAMETER, FILL_COLOR)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)

	return slider


func make_grabber_texture(diameter: int, color: Color) -> ImageTexture:
	var image := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var radius := diameter * 0.5
	for y in range(diameter):
		for x in range(diameter):
			var distance := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			if distance <= radius - 1.0:
				image.set_pixel(x, y, color)
			elif distance <= radius:
				# Feather the last pixel so the circle edge is not jagged.
				image.set_pixel(x, y, Color(color.r, color.g, color.b, radius - distance))

	return ImageTexture.create_from_image(image)


func animate_in() -> void:
	slide_tween = create_tween().set_parallel(true)
	slide_tween.tween_property(panel, "position:y", PANEL_TOP, SLIDE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide_tween.tween_property(backdrop, "modulate:a", 1.0, SLIDE_TIME * 0.6)
	await slide_tween.finished
	is_open = true


func on_backdrop_input(event: InputEvent) -> void:
	# Ignore taps until the card has finished sliding in, so the tap that
	# opened the panel cannot immediately dismiss it.
	if not is_open:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		close()


func close() -> void:
	if is_closing:
		return
	is_closing = true

	AudioSettings.save_settings()
	GameSettings.save_settings()

	if slide_tween:
		slide_tween.kill()
	slide_tween = create_tween().set_parallel(true)
	slide_tween.tween_property(panel, "position:y", -panel.size.y, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	slide_tween.tween_property(backdrop, "modulate:a", 0.0, SLIDE_TIME)
	await slide_tween.finished

	closed.emit()
	queue_free()
