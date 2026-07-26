## OnlinePanel — the beige card that handles getting two phones into the same
## game: host it, or join one found on the network. It slides down over the
## title screen the same way the settings card does, and closes itself once the
## table is full (the menu takes over from there and loads the game).
class_name OnlinePanel
extends Control

signal closed

const UI_THEME := preload("res://Assets/Themes/clean_ui.tres")
const BACKDROP_ALPHA := 0.75
const SLIDE_TIME := 0.35
## The card hangs from here and grows downward — every screen is a different
## number of rows, so its height follows its contents (see fit_to_contents).
const PANEL_TOP := 340.0
const PANEL_MARGIN_X := 90.0
const PANEL_PADDING := 56.0
const BUTTON_HEIGHT := 130.0
const SMALL_BUTTON_HEIGHT := 96.0

enum Screen {
	CHOOSE,   ## Host a game / Join a game.
	HOSTING,  ## Waiting for the other players to arrive.
	BROWSING, ## Games found on the network, plus an address to type.
	JOINING,  ## Connected, waiting for the host to start.
}

var player_count := 2
var screen: Screen = Screen.CHOOSE
var status_text := ""

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

	Net.lobby_changed.connect(refresh)
	Net.hosts_changed.connect(refresh)
	Net.join_failed.connect(on_join_failed)

	build_backdrop()
	build_panel()
	refresh()
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
	# Swallow taps so a press on the card never reaches the closing backdrop.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	layout = VBoxContainer.new()
	layout.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	layout.size = Vector2(panel_width - PANEL_PADDING * 2.0, 0.0)
	layout.add_theme_constant_override("separation", 28)
	panel.add_child(layout)


func make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.ACCENT
	style.set_corner_radius_all(32)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	return style


# ── Screens ───────────────────────────────────────────────────────────────────

## Rebuilt whole rather than patched: every screen is a handful of rows, and a
## lobby that changes under the player's finger stays honest this way.
func refresh() -> void:
	if is_closing:
		return

	for child in layout.get_children():
		# Unparented first: queue_free() only takes effect at the end of the
		# frame, and a container would lay the new rows out around the old ones.
		layout.remove_child(child)
		child.queue_free()

	match screen:
		Screen.CHOOSE:
			build_choose_screen()
		Screen.HOSTING:
			build_hosting_screen()
		Screen.BROWSING:
			build_browsing_screen()
		Screen.JOINING:
			build_joining_screen()

	if not status_text.is_empty():
		layout.add_child(make_label(status_text, 32, HORIZONTAL_ALIGNMENT_CENTER))

	fit_to_contents()


## Close the card around whatever screen was just built, with the same padding
## all round — a found game appearing in the list grows it, backing out of a
## screen shrinks it again.
func fit_to_contents() -> void:
	pin_wrapped_label_heights(layout, layout.size.x)
	var content_height: float = layout.get_combined_minimum_size().y
	layout.size.y = content_height
	panel.size.y = content_height + PANEL_PADDING * 2.0


## Wrapping text answers "how tall are you?" from the width it currently has,
## and a row that was just built has no width yet — it would claim a height of
## dozens of one-character lines and stretch the card to nothing but empty
## space. Each label is given the width it is about to be laid out at, then
## held to the height that turned out to be.
func pin_wrapped_label_heights(node: Node, content_width: float) -> void:
	for child in node.get_children():
		var label := child as Label
		if label and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			label.size.x = content_width
			label.custom_minimum_size.y = label.get_minimum_size().y
		pin_wrapped_label_heights(child, content_width)


func build_choose_screen() -> void:
	layout.add_child(make_title("%d PLAYERS" % player_count))
	layout.add_child(make_label(
		"One phone hosts the game and the others join it over the same Wi-Fi.",
		32, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_spacer(20.0))
	layout.add_child(make_button("Host a Game", start_hosting))
	layout.add_child(make_button("Join a Game", start_browsing))


func build_hosting_screen() -> void:
	layout.add_child(make_title("HOSTING"))
	layout.add_child(make_label(
		"Waiting for players… %d of %d" % [Net.joined_count(), player_count],
		40, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_label(
		"On the other phone, tap Online → %d → Join a Game." % player_count,
		30, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_label("This device: %s" % local_address_text(), 28, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_spacer(20.0))
	layout.add_child(make_button("Cancel", back_to_choose, SMALL_BUTTON_HEIGHT))


func build_browsing_screen() -> void:
	layout.add_child(make_title("JOIN A GAME"))

	var hosts: Array = Net.found_hosts.keys()
	hosts.sort()
	if hosts.is_empty():
		layout.add_child(make_label("Looking for games on this network…", 32, HORIZONTAL_ALIGNMENT_CENTER))
	for host_ip: String in hosts:
		var host: Dictionary = Net.found_hosts[host_ip]
		var label := "%s  (%d/%d)" % [host_ip, int(host["joined"]), int(host["expected"])]
		layout.add_child(make_button(label, connect_to.bind(host_ip), SMALL_BUTTON_HEIGHT, 34))

	layout.add_child(make_spacer(12.0))
	layout.add_child(make_address_row())
	layout.add_child(make_button("Back", back_to_choose, SMALL_BUTTON_HEIGHT))


func build_joining_screen() -> void:
	layout.add_child(make_title("JOINED"))
	if Net.local_player > 0:
		layout.add_child(make_label("You are Player %d." % Net.local_player, 40, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_label(
		"Waiting for players… %d of %d" % [Net.joined_count(), Net.expected_players],
		34, HORIZONTAL_ALIGNMENT_CENTER))
	layout.add_child(make_spacer(20.0))
	layout.add_child(make_button("Leave", back_to_choose, SMALL_BUTTON_HEIGHT))


## Typing an address by hand is the fallback for networks that block the
## broadcast the search uses (and for hosts that could not open the search port).
func make_address_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var address_field := LineEdit.new()
	address_field.theme = UI_THEME
	address_field.placeholder_text = "Host address"
	address_field.add_theme_font_size_override("font_size", 34)
	address_field.custom_minimum_size = Vector2(0.0, SMALL_BUTTON_HEIGHT)
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address_field)

	var on_go_pressed := func() -> void:
		var typed: String = address_field.text.strip_edges()
		if not typed.is_empty():
			connect_to(typed)

	var connect_button := make_button("Go", on_go_pressed, SMALL_BUTTON_HEIGHT, 34)
	connect_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	connect_button.custom_minimum_size = Vector2(180.0, SMALL_BUTTON_HEIGHT)
	row.add_child(connect_button)

	return row


# ── Actions ───────────────────────────────────────────────────────────────────

func start_hosting() -> void:
	status_text = Net.host_game(player_count)
	screen = Screen.HOSTING if status_text.is_empty() else Screen.CHOOSE
	refresh()


func start_browsing() -> void:
	status_text = ""
	screen = Screen.BROWSING
	Net.start_probing()
	refresh()


func connect_to(address: String) -> void:
	Net.stop_probing()
	status_text = Net.join_game(address)
	screen = Screen.JOINING if status_text.is_empty() else Screen.BROWSING
	refresh()


func back_to_choose() -> void:
	Net.leave()
	status_text = ""
	screen = Screen.CHOOSE
	refresh()


func on_join_failed(reason: String) -> void:
	status_text = reason
	screen = Screen.CHOOSE
	refresh()


## The addresses this phone can be reached on, so a player can type one into
## the other phone when the search comes up empty.
func local_address_text() -> String:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if address.get_slice_count(".") == 4 and not address.begins_with("127."):
			addresses.append(address)
	return ", ".join(addresses) if not addresses.is_empty() else "no network"


# ── Widgets ───────────────────────────────────────────────────────────────────

func make_title(text: String) -> Label:
	return make_label(text, 56, HORIZONTAL_ALIGNMENT_CENTER)


func make_label(text: String, font_size: int, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiPalette.INK)
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer


## Buttons on the beige card are the inverse of the in-game ones: dark ink on a
## light panel, so they read as pressable without a second accent colour.
func make_button(text: String, on_pressed: Callable, height := BUTTON_HEIGHT, font_size := 44) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = UI_THEME
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size = Vector2(0.0, height)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true

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


# ── Show and hide ─────────────────────────────────────────────────────────────

func animate_in() -> void:
	slide_tween = create_tween().set_parallel(true)
	slide_tween.tween_property(panel, "position:y", PANEL_TOP, SLIDE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide_tween.tween_property(backdrop, "modulate:a", 1.0, SLIDE_TIME * 0.6)
	await slide_tween.finished
	is_open = true


func on_backdrop_input(event: InputEvent) -> void:
	# Ignore taps until the card has finished sliding in, so the tap that opened
	# the panel cannot immediately dismiss it.
	if not is_open:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		close()


## Closing gives up whatever connection the panel had — the one exception is the
## game starting, which closes the panel from the menu with `keep_connection`.
func close(keep_connection := false) -> void:
	if is_closing:
		return
	is_closing = true

	if not keep_connection:
		Net.leave()

	if slide_tween:
		slide_tween.kill()
	slide_tween = create_tween().set_parallel(true)
	slide_tween.tween_property(panel, "position:y", -panel.size.y, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	slide_tween.tween_property(backdrop, "modulate:a", 0.0, SLIDE_TIME)
	await slide_tween.finished

	closed.emit()
	queue_free()
