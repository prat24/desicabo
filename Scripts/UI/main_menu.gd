## MainMenu — title screen. The title text matches the background color, so it
## starts invisible; card backs get thrown down beneath the text layer,
## revealing it. Then a fanned hand of menu card buttons rises from the bottom
## (Local / Online / Settings) with the in-game hand-hover lift. Only Local is
## clickable for now.
extends Control

const GAME_SCENE_PATH := "res://Scenes/Managers/game_manager.tscn"
const PLAYER_CARD_SCENE := preload("res://Scenes/Cards/player_card.tscn")
const CARD_BACK_TEXTURE := preload("res://Assets/Art/PNG/Cards/cardBack_main.png")

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
## The ease-out means a card has visually arrived well before the tween ends,
## so the landing sound plays at this fraction of the flight time.
const LAND_SOUND_FRACTION := 0.65

# ── Menu hand (the card buttons) ──────────────────────────────────────────────
const MENU_HAND := [
	{"texture": preload("res://Assets/Art/PNG/TitleCards/Local.png"), "enabled": true},
	{"texture": preload("res://Assets/Art/PNG/TitleCards/Online.png"), "enabled": false},
	{"texture": preload("res://Assets/Art/PNG/TitleCards/Settings.png"), "enabled": false},
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
const DISABLED_CARD_MODULATE := Color(0.45, 0.45, 0.45)

@onready var card_pile: Node2D = $CardPile
@onready var title_label: Label = $TitleLabel
@onready var hand_cards_root: Node2D = $HandCards

var sfx: AudioStreamPlayer
var clickable_cards: Array[PlayerCard] = []
var hovered_card: PlayerCard
var intro_done := false
var is_starting_game := false


func _ready() -> void:
	sfx = CardSfx.create_place_player()
	add_child(sfx)
	run_intro()


func run_intro() -> void:
	# Wait one frame so the label's anchored layout is final.
	await get_tree().process_frame
	fade_in_from_black()
	await throw_title_cards()
	Music.start()
	await fly_in_hand_cards()
	intro_done = true


func _process(_delta: float) -> void:
	# The card shader's hover tilt reads this global uniform. The game updates
	# it every frame; without it here the menu ace tilts toward a stale point
	# far off the card and spins wildly on hover.
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", get_viewport().get_mouse_position())

	if not intro_done or is_starting_game:
		return

	var mouse_position := get_global_mouse_position()
	var new_hover: PlayerCard = null
	for card in clickable_cards:
		if get_card_resting_rect(card).has_point(mouse_position):
			new_hover = card
			break

	# Only the in-game hand-hover animation (lift + scale + glow) — no shader
	# tilt here; it reads as the card twisting around on a static menu.
	if new_hover != hovered_card:
		if hovered_card:
			hovered_card.set_drag_hovered(false)
		hovered_card = new_hover
		if hovered_card:
			hovered_card.set_drag_hovered(true)


func _input(event: InputEvent) -> void:
	if not intro_done or is_starting_game:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	# Hit-test at the tap position directly: hover state lags a frame on touch.
	var tap_position := get_global_mouse_position()
	for card in clickable_cards:
		if get_card_resting_rect(card).has_point(tap_position):
			start_game_with_card(card)
			return


## Hit-test against the card's resting spot, not its animated rect: testing
## the live rect makes the hover lift move the card out from under the pointer,
## which un-hovers it and causes a lift/drop flicker loop.
func get_card_resting_rect(card: PlayerCard) -> Rect2:
	var card_size: Vector2 = card.sprite.texture.get_size() * card.sprite.scale.abs() * card.resting_scale
	return Rect2(card.resting_position - card_size * 0.5, card_size)


## Smooth arrival (from launch or from a finished game): start black, fade in
## while the title cards begin to fly.
func fade_in_from_black() -> void:
	var fade := ColorRect.new()
	fade.color = Color(0.0, 0.0, 0.0, 1.0)
	fade.size = get_viewport_rect().size
	fade.z_index = 500
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.4)
	fade_tween.tween_callback(fade.queue_free)


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
		throw.tween_callback(play_place_sound).set_delay(THROW_TIME * LAND_SOUND_FRACTION)

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


# ── Menu hand ─────────────────────────────────────────────────────────────────

func fly_in_hand_cards() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var mid: float = (MENU_HAND.size() - 1) * 0.5

	for i in range(MENU_HAND.size()):
		var entry: Dictionary = MENU_HAND[i]
		var card: PlayerCard = PLAYER_CARD_SCENE.instantiate()
		hand_cards_root.add_child(card)
		card.setup_card("", "", entry["texture"])
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

		if entry["enabled"]:
			clickable_cards.append(card)
		else:
			card.modulate = DISABLED_CARD_MODULATE

		var fly := create_tween().set_parallel(true)
		fly.tween_property(card, "position", target, HAND_FLY_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_property(card, "rotation_degrees", target_rotation, HAND_FLY_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_callback(play_place_sound).set_delay(HAND_FLY_TIME * LAND_SOUND_FRACTION)

		await get_tree().create_timer(HAND_STAGGER).timeout

	await get_tree().create_timer(HAND_FLY_TIME).timeout


func start_game_with_card(card: PlayerCard) -> void:
	is_starting_game = true
	card.set_drag_hovered(true)
	play_place_sound()

	# Fade to black, then swap scenes; the game fades back in on its side.
	# The short delay lets the card lift read as press feedback first.
	var fade := ColorRect.new()
	fade.color = Color(0.0, 0.0, 0.0, 0.0)
	fade.size = get_viewport_rect().size
	fade.z_index = 500
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 1.0, 0.35).set_delay(0.12)
	await fade_tween.finished
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func play_place_sound() -> void:
	sfx.play()
