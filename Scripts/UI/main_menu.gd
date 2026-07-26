## MainMenu — title screen. The title text matches the background color, so it
## starts invisible; card backs are thrown down beneath the text layer to
## reveal it. The title then swells, snaps back with a boom, turns white, and
## blasts the pile away. Finally a fanned hand of card buttons rises from the
## bottom: Local / Online / Settings. Picking Local slides that hand away and
## deals a second hand asking how many players (2 / 3 / 4). Online and the
## 4-player card are not live yet.
extends Control

const GAME_SCENE_PATH := "res://Scenes/Managers/game_manager.tscn"
const PLAYER_CARD_SCENE := preload("res://Scenes/Cards/player_card.tscn")
const CARD_BACK_TEXTURE := preload("res://Assets/Art/PNG/Cards/cardBack_main.png")
const UI_THEME := preload("res://Assets/Themes/clean_ui.tres")
const AIR_RISE_SOUND := preload("res://Assets/Sounds/air rise.mp3")
const BOOM_SOUND := preload("res://Assets/Sounds/boom.mp3")
const TITLE_SFX_VOLUME_DB := -20.0

# ── Title impact: the title swells, snaps back, and blasts the pile away ──────
const TITLE_GROW_SCALE := 1.07
const TITLE_GROW_TIME := 2.0
const TITLE_SNAP_TIME := 0.09
const TITLE_BLAST_TIME := 0.7
## Peak shake offset, reached just before the snap; it ramps up from nothing.
const TITLE_SHAKE_STRENGTH := 2.0

# ── Title card throw ──────────────────────────────────────────────────────────
## The pile is two staggered, jittered rows covering the two-line title —
## dense enough to back the text, scattered enough to read as thrown cards.
const TITLE_CARDS_PER_ROW := 5
const TITLE_CARD_ROW_SPACING := 260.0
const TITLE_ROW_STAGGER := 45.0
const TITLE_CARD_SPACING := 185.0
const TITLE_CARD_SCALE := 2.3
## Cards start bigger, as if flying in toward the table from the viewer.
const TITLE_CARD_START_SCALE := 3.0
const THROW_TIME := 0.5
const THROW_STAGGER := 0.11
const OFFSCREEN_MARGIN := 320.0
## When a thrown card visually touches down, as a fraction of THROW_TIME.
## The scale uses TRANS_BACK/EASE_OUT, which shrinks the card past its target
## and springs back — that squash is what the eye reads as the impact, and it
## peaks at 0.58 of the tween, not at its end. The flights that land on the
## tween's last frame (the menu hand, everything in-game) use a plain ease-out
## with no overshoot, so they need no fraction like this.
const THROW_LAND_FRACTION := 0.58

# ── Menu hands (each entry becomes one card button; `id` names its action) ────
const MAIN_HAND := [
	{"id": "local", "texture": preload("res://Assets/Art/PNG/TitleCards/Local.png"), "enabled": true},
	{"id": "online", "texture": preload("res://Assets/Art/PNG/TitleCards/Online.png"), "enabled": false},
	{"id": "settings", "texture": preload("res://Assets/Art/PNG/TitleCards/Settings.png"), "enabled": true},
]
const PLAYER_COUNT_HAND := [
	{"id": "2", "texture": preload("res://Assets/Art/PNG/Cards/cardHearts2.png"), "enabled": true},
	{"id": "3", "texture": preload("res://Assets/Art/PNG/Cards/cardHearts3.png"), "enabled": true},
	{"id": "4", "texture": preload("res://Assets/Art/PNG/Cards/cardHearts4.png"), "enabled": false},
]
const HAND_CARD_SCALE := 1.25
const HAND_CARD_SPACING := 250.0
## Card centers sit closer to the edge than the card half-height, so the
## bottoms are cut off a little — like the in-game hand.
const HAND_BOTTOM_OFFSET := 190.0
## Outer cards of the fan sit slightly lower and more rotated, like the game hand.
const HAND_ARC_DROP := 18.0
const HAND_ROTATION_STEP_DEGREES := 8.0
const HAND_FLY_TIME := 0.45
const HAND_STAGGER := 0.12
const HAND_SLIDE_OUT_TIME := 0.3
## Far enough below the screen edge that the whole card clears it.
const HAND_SLIDE_OUT_DISTANCE := 800.0
const DISABLED_CARD_MODULATE := Color(0.45, 0.45, 0.45)

# ── Scene transitions ─────────────────────────────────────────────────────────
const FADE_OVERLAY_Z := 500
const FADE_IN_TIME := 0.4
const FADE_OUT_TIME := 0.35

@onready var solid_background: ColorRect = $Background
@onready var card_pile: Node2D = $CardPile
@onready var title_label: Label = $TitleLabel
@onready var hand_cards_root: Node2D = $HandCards

var sfx_place: AudioStreamPlayer
var sfx_slide: AudioStreamPlayer
var sfx_air_rise: AudioStreamPlayer
var sfx_boom: AudioStreamPlayer
var hand_cards: Array[PlayerCard] = []
var clickable_cards: Array[PlayerCard] = []
var hovered_card: PlayerCard
## Card buttons act on release, not press: on a phone, holding a finger on a
## card is how the player hovers it.
var pointer := TapGesture.new()
var title_rest_position: Vector2
var input_enabled := false
var is_starting_game := false


func _ready() -> void:
	sfx_place = CardSfx.create_place_player()
	sfx_slide = CardSfx.create_slide_player()
	add_child(sfx_place)
	add_child(sfx_slide)
	sfx_air_rise = make_title_sfx_player(AIR_RISE_SOUND)
	sfx_boom = make_title_sfx_player(BOOM_SOUND)
	run_intro()


func make_title_sfx_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = TITLE_SFX_VOLUME_DB
	player.bus = AudioBuses.SFX
	add_child(player)
	return player


func run_intro() -> void:
	# Wait one frame so the label's anchored layout is final.
	await get_tree().process_frame
	fade_in_from_black()
	await throw_title_cards()
	await run_title_impact()
	Music.start()
	await fly_in_hand_cards(MAIN_HAND)
	reveal_swirl_background()
	input_enabled = true


## The title swells against the card pile, snaps back with a boom, turns white
## (it was background-colored until now), and blows the pile off screen.
func run_title_impact() -> void:
	title_label.pivot_offset = title_label.size * 0.5
	title_rest_position = title_label.position

	sfx_air_rise.play()
	var grow := create_tween()
	grow.tween_property(title_label, "scale", Vector2(TITLE_GROW_SCALE, TITLE_GROW_SCALE), TITLE_GROW_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var shake := shake_title_while_growing()
	await grow.finished
	shake.kill()
	title_label.position = title_rest_position

	var snap := create_tween()
	snap.tween_property(title_label, "scale", Vector2.ONE, TITLE_SNAP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await snap.finished

	sfx_air_rise.stop()
	sfx_boom.play()
	title_label.add_theme_color_override("font_color", Color.WHITE)
	await blow_away_title_cards()


## Jitter the title while it swells, ramping from still to TITLE_SHAKE_STRENGTH
## so the strain builds. The caller kills this tween and restores the position.
func shake_title_while_growing() -> Tween:
	var shake := create_tween()
	shake.tween_method(
		func(strength: float) -> void:
			title_label.position = title_rest_position + Vector2(
				randf_range(-strength, strength),
				randf_range(-strength, strength)
			),
		0.0,
		TITLE_SHAKE_STRENGTH,
		TITLE_GROW_TIME
	)
	return shake


## Every card in the pile flies straight out from the title and is freed.
func blow_away_title_cards() -> void:
	var title_center: Vector2 = title_label.get_global_rect().get_center()
	var blast_distance: float = get_viewport_rect().size.length()

	var blast := create_tween().set_parallel(true)
	for card: Sprite2D in card_pile.get_children():
		var direction: Vector2 = card.global_position - title_center
		if direction.length() < 1.0:
			direction = Vector2.RIGHT.rotated(randf() * TAU)
		direction = direction.normalized()

		blast.tween_property(card, "position", card.position + direction * blast_distance, TITLE_BLAST_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		blast.tween_property(card, "rotation_degrees", card.rotation_degrees + randf_range(-200.0, 200.0), TITLE_BLAST_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await blast.finished

	for card in card_pile.get_children():
		card.queue_free()


## Once the menu is fully assembled, the solid backdrop dissolves to reveal
## the animated swirl background (same shader as the game) beneath it.
func reveal_swirl_background() -> void:
	var fade_tween := create_tween()
	fade_tween.tween_property(solid_background, "modulate:a", 0.0, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Smooth arrival (from launch or from a finished game): start black, fade in
## while the title cards begin to fly.
func fade_in_from_black() -> void:
	var fade := add_fade_overlay(1.0)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, FADE_IN_TIME)
	fade_tween.tween_callback(fade.queue_free)


## Full-screen black rect above everything, used for scene transitions.
func add_fade_overlay(alpha: float) -> ColorRect:
	var fade := ColorRect.new()
	fade.color = Color(0.0, 0.0, 0.0, alpha)
	fade.size = get_viewport_rect().size
	fade.z_index = FADE_OVERLAY_Z
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	return fade


func _process(_delta: float) -> void:
	# The card shader's hover tilt reads this global uniform. The game updates
	# it every frame; without it here the menu cards tilt toward a stale point
	# far off the card and spin wildly on hover.
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", get_viewport().get_mouse_position())

	if not input_enabled or is_starting_game:
		return

	var mouse_position := get_global_mouse_position()
	var new_hover: PlayerCard = null
	# A lifted finger leaves the pointer parked on its last spot, so on touch
	# the hover has to end with the press instead of following that ghost.
	if TapGesture.is_pointer_hovering():
		for card in clickable_cards:
			if get_card_resting_rect(card).has_point(mouse_position):
				new_hover = card
				break

	# Only the in-game hand-hover animation (lift + scale + glow) — no shader
	# tilt here; it reads as the card twisting around on a static menu.
	if new_hover != hovered_card:
		# Resting on one card long enough presses it on release, so the clock
		# only runs while the hover stays put.
		pointer.hover_target_changed(new_hover != null)
		if hovered_card:
			hovered_card.set_drag_hovered(false)
		hovered_card = new_hover
		if hovered_card:
			hovered_card.set_drag_hovered(true)


func _input(event: InputEvent) -> void:
	if not input_enabled or is_starting_game:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	# The press only hovers the card; the button fires when a quick tap lifts
	# off it, so a press-and-hold can show the hover without picking anything.
	var tap_position := get_global_mouse_position()
	if mouse_event.pressed:
		pointer.press(mouse_event, tap_position)
		return

	if not pointer.release(tap_position):
		return

	# Hit-test at the tap position directly: hover state lags a frame on touch.
	for card in clickable_cards:
		if get_card_resting_rect(card).has_point(tap_position):
			# _input runs before GUI input, so without this the same tap would
			# also land on any panel this opens (closing it instantly).
			get_viewport().set_input_as_handled()
			handle_card_pressed(card)
			return


## Card buttons carry their action in `rank` (set from the hand entry's id).
func handle_card_pressed(card: PlayerCard) -> void:
	match card.rank:
		"local":
			show_player_count_picker(card)
		"settings":
			open_settings(card)
		"2":
			start_game_with_card(card, 2)
		"3":
			start_game_with_card(card, 3)


func open_settings(card: PlayerCard) -> void:
	input_enabled = false
	play_place_sound()

	var panel := SettingsPanel.new()
	add_child(panel)
	await panel.closed

	# Drop the hover the card kept while the panel was open.
	card.set_drag_hovered(false)
	hovered_card = null
	input_enabled = true


## Hit-test against the card's resting spot, not its animated rect: testing
## the live rect makes the hover lift move the card out from under the pointer,
## which un-hovers it and causes a lift/drop flicker loop.
func get_card_resting_rect(card: PlayerCard) -> Rect2:
	var card_size: Vector2 = card.sprite.texture.get_size() * card.sprite.scale.abs() * card.resting_scale
	return Rect2(card.resting_position - card_size * 0.5, card_size)


# ── Title card throw ──────────────────────────────────────────────────────────

func throw_title_cards() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var title_center: Vector2 = title_label.get_global_rect().get_center()

	# Shuffled landing order so the pile builds up randomly, not in a sweep.
	var land_spots := build_title_card_spots(title_center)
	land_spots.shuffle()

	for spot in land_spots:
		var card := Sprite2D.new()
		card.texture = CARD_BACK_TEXTURE
		card_pile.add_child(card)

		var land_rotation: float = spot["rotation"]
		card.position = random_offscreen_start(screen)
		card.rotation_degrees = land_rotation + randf_range(-150.0, 150.0)
		card.scale = Vector2(TITLE_CARD_START_SCALE, TITLE_CARD_START_SCALE)

		var throw := create_tween().set_parallel(true)
		throw.tween_property(card, "position", spot["position"], THROW_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		throw.tween_property(card, "rotation_degrees", land_rotation, THROW_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		throw.tween_property(card, "scale", Vector2(TITLE_CARD_SCALE, TITLE_CARD_SCALE), THROW_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Throws overlap, so the landing sound rides on each card's own tween
		# instead of an awaited one — same clock, so it still fires on the
		# exact frame that card touches down.
		throw.tween_callback(play_place_sound).set_delay(THROW_TIME * THROW_LAND_FRACTION)

		await get_tree().create_timer(THROW_STAGGER).timeout

	# Let the last card finish landing.
	await get_tree().create_timer(THROW_TIME).timeout


func build_title_card_spots(title_center: Vector2) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var mid: float = (TITLE_CARDS_PER_ROW - 1) * 0.5

	for row in range(2):
		var row_y: float = title_center.y + (row - 0.5) * TITLE_CARD_ROW_SPACING
		var row_x_shift: float = -TITLE_ROW_STAGGER if row == 0 else TITLE_ROW_STAGGER

		for i in range(TITLE_CARDS_PER_ROW):
			spots.append({
				"position": Vector2(
					title_center.x + (i - mid) * TITLE_CARD_SPACING + row_x_shift + randf_range(-25.0, 25.0),
					row_y + randf_range(-35.0, 35.0)
				),
				"rotation": randf_range(-22.0, 22.0),
			})

	return spots


## A start position off the left, right, or top edge — never from the bottom.
func random_offscreen_start(screen: Vector2) -> Vector2:
	match randi() % 3:
		0:
			return Vector2(-OFFSCREEN_MARGIN, randf_range(-OFFSCREEN_MARGIN, screen.y * 0.5))
		1:
			return Vector2(screen.x + OFFSCREEN_MARGIN, randf_range(-OFFSCREEN_MARGIN, screen.y * 0.5))
		_:
			return Vector2(randf_range(0.0, screen.x), -OFFSCREEN_MARGIN)


# ── Menu hands ────────────────────────────────────────────────────────────────

func fly_in_hand_cards(entries: Array) -> void:
	var screen: Vector2 = get_viewport_rect().size
	var mid: float = (entries.size() - 1) * 0.5

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var card: PlayerCard = PLAYER_CARD_SCENE.instantiate()
		hand_cards_root.add_child(card)
		card.setup_card(entry["id"], "", entry["texture"])
		card.show_front()

		var fan_offset := i - mid
		var target := Vector2(
			screen.x * 0.5 + fan_offset * HAND_CARD_SPACING,
			screen.y - HAND_BOTTOM_OFFSET + absf(fan_offset) * HAND_ARC_DROP
		)
		var target_rotation := fan_offset * HAND_ROTATION_STEP_DEGREES

		card.scale = Vector2(HAND_CARD_SCALE, HAND_CARD_SCALE)
		card.resting_scale = card.scale
		card.resting_position = target
		card.resting_rotation_degrees = target_rotation
		card.resting_z_index = i
		card.z_index = i
		card.position = Vector2(target.x, screen.y + 500.0)
		card.rotation_degrees = 0.0

		hand_cards.append(card)
		if entry["enabled"]:
			clickable_cards.append(card)
		else:
			card.modulate = DISABLED_CARD_MODULATE

		var fly := create_tween().set_parallel(true)
		fly.tween_property(card, "position", target, HAND_FLY_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_property(card, "rotation_degrees", target_rotation, HAND_FLY_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_callback(play_place_sound).set_delay(HAND_FLY_TIME)

		await get_tree().create_timer(HAND_STAGGER).timeout

	await get_tree().create_timer(HAND_FLY_TIME).timeout


## The current hand drops off the bottom of the screen and is freed.
func slide_out_hand_cards() -> void:
	hovered_card = null
	clickable_cards.clear()

	play_slide_sound()
	var slide := create_tween().set_parallel(true)
	for card in hand_cards:
		slide.tween_property(card, "position:y", card.position.y + HAND_SLIDE_OUT_DISTANCE, HAND_SLIDE_OUT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await slide.finished

	for card in hand_cards:
		card.queue_free()
	hand_cards.clear()


func show_player_count_picker(pressed_card: PlayerCard) -> void:
	input_enabled = false
	pressed_card.set_drag_hovered(true)
	play_place_sound()
	await get_tree().create_timer(0.15).timeout

	await slide_out_hand_cards()
	show_player_count_label()
	await fly_in_hand_cards(PLAYER_COUNT_HAND)
	input_enabled = true


func show_player_count_label() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var label := Label.new()
	label.text = "How many players?"
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", 60)
	label.add_theme_color_override("font_color", UiPalette.ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(screen.x, 80.0)
	label.position = Vector2(0.0, screen.y - 560.0)
	label.modulate.a = 0.0
	add_child(label)

	var fade_tween := create_tween()
	fade_tween.tween_property(label, "modulate:a", 1.0, 0.3)


func start_game_with_card(card: PlayerCard, player_count: int) -> void:
	is_starting_game = true
	GameConfig.player_count = player_count
	card.set_drag_hovered(true)
	play_place_sound()

	# Fade to black, then swap scenes; the game fades back in on its side.
	# The short delay lets the card lift read as press feedback first.
	var fade := add_fade_overlay(0.0)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 1.0, FADE_OUT_TIME).set_delay(0.12)
	await fade_tween.finished
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func play_place_sound() -> void:
	sfx_place.play()


func play_slide_sound() -> void:
	sfx_slide.play()
