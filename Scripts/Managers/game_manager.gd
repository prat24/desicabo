## GameManager — runs the full game loop: dealing, turns, drag-and-drop,
## special card powers, scoring, and animations.
extends Node2D

const CARD_COLLISION_MASK = 1
const NORMAL_CARD_SCALE = Vector2(1.15, 1.15)
const HOVERED_CARD_SCALE = NORMAL_CARD_SCALE * 1.05
const SNAP_TIME = 0.18
const DEAL_FLY_TIME = 0.28
const DEAL_STAGGER_TIME = 0.07
const DISCARD_FLY_TIME = 0.34
const SWAP_FLY_TIME = 0.4
## Ease-out flights visually land before the tween ends; play the landing
## sound at this fraction of the flight time so audio matches the visual.
const LAND_SOUND_FRACTION = 0.65
## Horizontal offset of the deck and discard slots from the screen center.
const BOARD_SLOT_OFFSET_X = 375.0
## Special-power dim overlay z-index; the selectable hand is raised above it.
const OVERLAY_Z_INDEX = 150
const RAISED_HAND_Z_INDEX = 200
const MAIN_MENU_SCENE = "res://Scenes/UI/main_menu.tscn"

const UI_THEME = preload("res://Assets/Themes/clean_ui.tres")

@export_range(0.0, 15.0, 0.1) var pre_game_reveal_time: float = 5.0
@export_range(0.1, 0.8, 0.01) var initial_deal_fly_time: float = DEAL_FLY_TIME
@export_range(0.0, 0.3, 0.01) var initial_deal_stagger: float = DEAL_STAGGER_TIME
@export_range(0.0, 1.0, 0.01) var pre_game_dim_alpha: float = 0.35
@export_range(0.05, 1.5, 0.01) var player_card_flip_time: float = 0.24
## Reveals flip cards up much faster than they flip back down.
@export_range(0.05, 0.5, 0.01) var quick_flip_up_time: float = 0.12
@export_range(0.5, 10.0, 0.1) var reveal_prompt_time: float = 5.0
## Quick "Player X's turn" flash at the start of every turn.
@export_range(0.2, 5.0, 0.1) var turn_prompt_time: float = 1.5

enum TurnState {
	DEALING,
	WAITING_FOR_DROP,
	ANIMATING,
	SPECIAL_7,
	GAME_OVER
}

var turn_state: TurnState = TurnState.DEALING
var deck: Array[Dictionary] = []
var current_player: int = 1  ## 1 or 2 — whose turn it is.

var screen_size: Vector2
var center_draw_position: Vector2 = Vector2.ZERO
var discard_pile_position: Vector2 = Vector2.ZERO

var dragged_card: BoardCard
var hovered_player_card: PlayerCard

var intro_dim_overlay: ColorRect
var special_overlay: ColorRect
var game_over_overlay: ColorRect
var is_returning_to_menu := false

# ── Seven-power selection state ───────────────────────────────────────────────
var selected_source_card: PlayerCard = null
var hovered_special_card: PlayerCard = null
var seven_selecting_opponent: bool = false
var seven_power_done: bool = false
var seven_skip_button: Button

var sfx_place: AudioStreamPlayer
var sfx_slide: AudioStreamPlayer

# ── Scene references ──────────────────────────────────────────────────────────
@onready var deck_sprite: Sprite2D = $DeckSprite
@onready var center_draw_card: BoardCard = $CenterDrawCard
@onready var discard_pile_sprite: Sprite2D = $DiscardPileSprite
@onready var discard_top_card: BoardCard = $DiscardTopCard
## Animation-only card for flights to the discard pile, so the pile's top card
## stays visible until the new card actually lands on it.
@onready var flying_card: BoardCard = $FlyingCard
@onready var player1_hand: PlayerHand = $PlayerHand
@onready var player2_hand: PlayerHand = $Player2Hand


func _ready() -> void:
	screen_size = get_viewport_rect().size
	layout_board_for_screen()
	center_draw_position = center_draw_card.global_position
	discard_pile_position = discard_pile_sprite.global_position
	center_draw_card.visible = false
	discard_top_card.visible = false
	flying_card.visible = false
	flying_card.get_node("Area2D").input_pickable = false
	flying_card.get_node("Area2D/CollisionShape2D").disabled = true
	set_discard_takeable(false)
	setup_board_card_shaders()
	center_draw_card.hovered.connect(on_board_card_hovered)
	center_draw_card.hovered_off.connect(on_board_card_hovered_off)
	discard_top_card.hovered.connect(on_board_card_hovered)
	discard_top_card.hovered_off.connect(on_board_card_hovered_off)
	setup_audio()
	deck = CardDeck.create_shuffled_deck()
	fade_in_from_black()
	await deal_initial_hands_animated()
	await run_pre_game_reveals()
	await start_turn()


## Anchor the board to the real screen size: the scene is authored for
## 1080x1920, but stretch aspect "expand" makes the viewport taller on modern
## phones. Keeps the middle row centered and Player 2's hand pinned to the top.
func layout_board_for_screen() -> void:
	var center: Vector2 = screen_size * 0.5
	deck_sprite.position = Vector2(center.x - BOARD_SLOT_OFFSET_X, center.y)
	center_draw_card.position = center
	discard_pile_sprite.position = Vector2(center.x + BOARD_SLOT_OFFSET_X, center.y)
	discard_top_card.position = discard_pile_sprite.position
	player2_hand.position = screen_size


## Smooth arrival from the title screen: it fades to black before the scene
## change, so this scene starts black and fades in while the deal begins.
func fade_in_from_black() -> void:
	var fade := create_fullscreen_overlay(1.0, 500)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.4)
	fade_tween.tween_callback(fade.queue_free)


func setup_board_card_shaders() -> void:
	CardShader.apply(deck_sprite, 12.0)
	CardShader.apply(discard_pile_sprite, 24.0)
	CardShader.set_inset(deck_sprite, 0.03)
	CardShader.set_inset(discard_pile_sprite, 0.03)


func setup_audio() -> void:
	sfx_place = CardSfx.create_place_player()
	sfx_slide = CardSfx.create_slide_player()
	add_child(sfx_place)
	add_child(sfx_slide)


func play_place_sound() -> void:
	sfx_place.play()


func play_slide_sound() -> void:
	sfx_slide.play()


func schedule_place_sound(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(play_place_sound)


func deal_initial_hands_animated() -> void:
	turn_state = TurnState.DEALING

	player1_hand.arrange_cards()
	player2_hand.arrange_cards()

	var deck_pos: Vector2 = deck_sprite.global_position
	var deck_scale: Vector2 = deck_sprite.scale
	player1_hand.stack_cards_at_deck(deck_pos)
	player2_hand.stack_cards_at_deck(deck_pos)

	var slots_per_hand: int = player1_hand.cards.size()
	for slot in range(slots_per_hand):
		if deck.is_empty():
			break

		schedule_place_sound(initial_deal_fly_time * LAND_SOUND_FRACTION)
		await player1_hand.animate_deal_card(
			slot,
			deck.pop_front(),
			deck_pos,
			initial_deal_fly_time,
			deck_scale
		)
		if initial_deal_stagger > 0.0:
			await get_tree().create_timer(initial_deal_stagger).timeout

		if deck.is_empty():
			break

		schedule_place_sound(initial_deal_fly_time * LAND_SOUND_FRACTION)
		await player2_hand.animate_deal_card(
			slot,
			deck.pop_front(),
			deck_pos,
			initial_deal_fly_time,
			deck_scale
		)
		if initial_deal_stagger > 0.0 and slot < slots_per_hand - 1:
			await get_tree().create_timer(initial_deal_stagger).timeout


## Both players peek at their hands before Player 1's first turn; a prompt
## before each reveal warns the other player to look away.
func run_pre_game_reveals() -> void:
	await show_reveal_prompt(1)
	await run_hand_reveal(player1_hand)
	await show_reveal_prompt(2)
	await run_hand_reveal(player2_hand)


func show_reveal_prompt(player_number: int) -> void:
	var other_player := 3 - player_number
	await show_fullscreen_prompt(
		"Time for Player %d to see their cards!\nPlayer %d look away!" % [player_number, other_player],
		reveal_prompt_time,
		0.25,
		other_player
	)


func show_turn_prompt() -> void:
	var other_player := 3 - current_player
	await show_fullscreen_prompt(
		"Player %d's turn now.\nPlayer %d should look away!" % [current_player, other_player],
		turn_prompt_time,
		0.15,
		other_player
	)


## Near-black full-screen overlay with centered white text that fades in,
## holds, fades out, and cleans itself up. The text is rotated toward
## `facing_player` — the one who must act on it (Player 2 sits at the top of
## the screen, so text facing them is upside down).
func show_fullscreen_prompt(prompt_text: String, hold_time: float, fade_time: float = 0.25, facing_player: int = 1) -> void:
	var overlay := create_fullscreen_overlay(0.9, 400)
	var label := make_overlay_label(prompt_text, 56)
	label.position = Vector2.ZERO
	label.size = overlay.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if facing_player == 2:
		label.pivot_offset = label.size * 0.5
		label.rotation_degrees = 180.0
	overlay.add_child(label)

	overlay.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(overlay, "modulate:a", 1.0, fade_time)
	await fade_in.finished

	await get_tree().create_timer(hold_time).timeout

	var fade_out := create_tween()
	fade_out.tween_property(overlay, "modulate:a", 0.0, fade_time)
	await fade_out.finished
	overlay.queue_free()


func run_hand_reveal(hand: PlayerHand) -> void:
	create_intro_dim_overlay()
	dim_for_hand_reveal(hand, true)

	for card in hand.cards:
		await card.animate_flip(true, quick_flip_up_time)

	var card_count: int = hand.cards.size()
	var flip_time_total: float = card_count * (quick_flip_up_time + player_card_flip_time)
	var hold_time: float = maxf(0.0, pre_game_reveal_time - flip_time_total)

	if hold_time > 0.0:
		await get_tree().create_timer(hold_time).timeout

	for card in hand.cards:
		await card.animate_flip(false, player_card_flip_time)

	dim_for_hand_reveal(hand, false)
	if intro_dim_overlay:
		intro_dim_overlay.queue_free()
		intro_dim_overlay = null


func create_intro_dim_overlay() -> void:
	if intro_dim_overlay:
		return
	intro_dim_overlay = create_fullscreen_overlay(pre_game_dim_alpha, 200)


func dim_for_hand_reveal(active_hand: PlayerHand, dimmed: bool) -> void:
	var target_modulate := Color(1.0, 1.0, 1.0, 1.0)
	if dimmed:
		target_modulate = Color(0.6, 0.6, 0.6, 1.0)

	deck_sprite.modulate = target_modulate
	center_draw_card.modulate = target_modulate
	discard_pile_sprite.modulate = target_modulate
	discard_top_card.modulate = target_modulate

	var inactive_hand: PlayerHand = player2_hand if active_hand == player1_hand else player1_hand
	inactive_hand.modulate = target_modulate
	active_hand.z_index = 300 if dimmed else 0


func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", get_viewport().get_mouse_position())

	if turn_state == TurnState.SPECIAL_7:
		update_seven_hover()
		if hovered_special_card and hovered_special_card != selected_source_card:
			hovered_special_card.update_shader_tilt(get_global_mouse_position())
		return

	if dragged_card == null:
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	dragged_card.update_shader_tilt(mouse_position)

	if hovered_player_card:
		hovered_player_card.update_shader_tilt(mouse_position)

	var collision_shape: CollisionShape2D = dragged_card.get_node("Area2D/CollisionShape2D")
	var shape: RectangleShape2D = collision_shape.shape as RectangleShape2D
	if shape == null:
		return

	var half_size: Vector2 = shape.size * dragged_card.global_scale * 0.5
	dragged_card.global_position = Vector2(
		clamp(mouse_position.x, half_size.x, screen_size.x - half_size.x),
		clamp(mouse_position.y, half_size.y, screen_size.y - half_size.y)
	)
	update_player_card_drag_hover()


func _input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	match turn_state:
		TurnState.GAME_OVER:
			# The overlay marks that final scores are on screen; any tap exits.
			if mouse_event.pressed and game_over_overlay:
				return_to_main_menu()
		TurnState.SPECIAL_7:
			if mouse_event.pressed:
				await handle_seven_click()
		_:
			if mouse_event.pressed:
				var card := check_card_click()
				if card:
					start_card_drag(card)
			elif dragged_card:
				await end_card_drag()


func start_card_drag(card: Node2D) -> void:
	if turn_state != TurnState.WAITING_FOR_DROP:
		return

	var board_card := card as BoardCard
	if board_card == null or not board_card.can_drag:
		return

	board_card.tween_hover_scale(NORMAL_CARD_SCALE)
	CardShader.set_hover(board_card.sprite, 1.0)
	CardShader.set_inset(board_card.sprite, 0.0)
	dragged_card = board_card


func end_card_drag() -> void:
	var dropped_card := dragged_card
	var target_player_card := hovered_player_card

	clear_player_card_drag_hover()
	dragged_card = null

	if dropped_card == discard_top_card:
		if target_player_card:
			await take_discard_card(target_player_card)
		else:
			await return_discard_card()
		return

	if target_player_card:
		await swap_draw_card_with_player_card(target_player_card)
	elif is_card_over_discard_pile(center_draw_card):
		await discard_center_draw_card()
	else:
		await return_center_draw_card()


func on_board_card_hovered(card: BoardCard) -> void:
	if card.can_drag:
		highlight_card(card, true)


func on_board_card_hovered_off(card: BoardCard) -> void:
	if dragged_card == null:
		highlight_card(card, false)


func highlight_card(card: BoardCard, is_hovered: bool) -> void:
	card.tween_hover_scale(HOVERED_CARD_SCALE if is_hovered else NORMAL_CARD_SCALE)
	card.z_index = 2 if is_hovered else 1
	CardShader.set_hover(card.sprite, 1.0 if is_hovered else 0.0)
	if is_hovered:
		CardShader.set_inset(card.sprite, 0.0)
	else:
		CardShader.tween_inset(card, card.sprite, CardShader.RESTING_INSET, 0.12)


func check_card_click() -> Node2D:
	var space_state := get_world_2d().direct_space_state
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = CARD_COLLISION_MASK
	var result := space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_top_card(result)
	return null


func get_top_card(cards: Array[Dictionary]) -> Node2D:
	var top_card: Node2D = cards[0]["collider"].get_parent()
	var highest_z_index := top_card.z_index

	for i in range(1, cards.size()):
		var current_card: Node2D = cards[i]["collider"].get_parent()
		if current_card.z_index > highest_z_index:
			top_card = current_card
			highest_z_index = current_card.z_index

	return top_card


func update_player_card_drag_hover() -> void:
	var best_player_card := get_best_overlapped_player_card()

	if hovered_player_card == best_player_card:
		return

	if hovered_player_card:
		hovered_player_card.set_drag_hovered(false)

	hovered_player_card = best_player_card

	if hovered_player_card:
		hovered_player_card.set_drag_hovered(true)


func clear_player_card_drag_hover() -> void:
	if hovered_player_card:
		hovered_player_card.set_drag_hovered(false)
		hovered_player_card = null


func get_best_overlapped_player_card() -> PlayerCard:
	if dragged_card == null:
		return null

	var dragged_card_rect := dragged_card.get_global_rect()
	var best_player_card: PlayerCard
	var best_overlap_area := 0.0

	for player_card in get_tree().get_nodes_in_group("player_cards"):
		if player_card is PlayerCard and player_card.player_id == current_player:
			var overlap_area := get_overlap_area(dragged_card_rect, player_card.get_global_rect())
			if overlap_area > best_overlap_area:
				best_overlap_area = overlap_area
				best_player_card = player_card

	return best_player_card


func get_overlap_area(first_rect: Rect2, second_rect: Rect2) -> float:
	if not first_rect.intersects(second_rect):
		return 0.0

	var overlap_rect := first_rect.intersection(second_rect)
	return overlap_rect.size.x * overlap_rect.size.y


func start_turn() -> void:
	if deck.is_empty():
		await end_game()
		return

	turn_state = TurnState.DEALING
	await show_turn_prompt()
	await deal_center_draw_card()
	await check_special_card_effect()
	set_discard_takeable(true)
	turn_state = TurnState.WAITING_FOR_DROP


## While waiting for a drop, the discard pile's top card may be taken into the
## hand instead of the drawn card. Disabling also clears any stale hover state,
## since a disabled Area2D never fires mouse_exited.
func set_discard_takeable(takeable: bool) -> void:
	var enabled := takeable and discard_top_card.visible
	discard_top_card.can_drag = enabled
	discard_top_card.get_node("Area2D").input_pickable = enabled
	discard_top_card.get_node("Area2D/CollisionShape2D").set_deferred("disabled", not enabled)

	if not enabled:
		discard_top_card.is_shader_hovering = false
		CardShader.set_hover(discard_top_card.sprite, 0.0)
		CardShader.set_inset(discard_top_card.sprite, CardShader.RESTING_INSET)
		CardShader.reset_tilt(discard_top_card.sprite)


## Queen: reveal the active player's own hand.
## King: reveal the other player's hand.
## Jack: jumble the other player's cards randomly.
## Seven: swap one of the active player's cards with an opponent's card.
func check_special_card_effect() -> void:
	match center_draw_card.rank:
		"Q":
			await run_hand_reveal(get_active_hand())

		"K":
			await run_hand_reveal(get_other_hand())

		"J":
			play_slide_sound()
			await get_other_hand().jumble_cards()

		"7":
			await run_seven_swap_power()


func deal_center_draw_card() -> void:
	var card_data: Dictionary = deck.pop_front()

	center_draw_card.setup_card(
		card_data["rank"],
		card_data["suit"],
		card_data["texture"]
	)
	center_draw_card.visible = true
	center_draw_card.z_index = 10
	center_draw_card.can_drag = false
	center_draw_card.global_position = deck_sprite.global_position
	# The card's child sprite is pre-scaled, so divide that out to spawn at
	# exactly the deck pile's on-screen size.
	center_draw_card.scale = deck_sprite.scale / center_draw_card.sprite.scale.x

	play_slide_sound()
	var move_tween := create_tween().set_parallel(true)
	move_tween.tween_property(center_draw_card, "global_position", center_draw_position, initial_deal_fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(center_draw_card, "scale", NORMAL_CARD_SCALE, initial_deal_fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await move_tween.finished

	await center_draw_card.flip_to_front()
	center_draw_card.z_index = 1


func discard_center_draw_card() -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)

	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", discard_pile_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	place_card_on_discard(center_draw_card)
	play_place_sound()
	center_draw_card.visible = false
	current_player = 3 - current_player  # Toggle between players 1 and 2.
	await start_turn()


func swap_draw_card_with_player_card(player_card: PlayerCard) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)

	var old_card_data := player_card.to_card_data()
	var new_card_data := center_draw_card.to_card_data()

	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", player_card.global_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	player_card.setup_card(
		new_card_data["rank"],
		new_card_data["suit"],
		new_card_data["texture"]
	)
	player_card.set_drag_hovered(false)
	play_place_sound()
	center_draw_card.visible = false

	await animate_card_to_discard(old_card_data, player_card.global_position)
	current_player = 3 - current_player  # Toggle between players 1 and 2.
	await start_turn()


func return_center_draw_card() -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false

	play_slide_sound()
	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", center_draw_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	center_draw_card.scale = NORMAL_CARD_SCALE
	center_draw_card.can_drag = true
	# Only keep the hover look if the pointer actually rests on the card.
	var pointer_on_card := center_draw_card.get_global_rect().has_point(get_global_mouse_position())
	highlight_card(center_draw_card, pointer_on_card)
	turn_state = TurnState.WAITING_FOR_DROP


## Take the discard pile's top card into the hand instead of the drawn card:
## the drawn card goes onto the pile, then the replaced hand card lands on top.
func take_discard_card(player_card: PlayerCard) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false
	set_discard_takeable(false)

	var old_hand_data := player_card.to_card_data()
	var taken_data := discard_top_card.to_card_data()

	var move_tween := create_tween()
	move_tween.tween_property(discard_top_card, "global_position", player_card.global_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	player_card.setup_card(taken_data["rank"], taken_data["suit"], taken_data["texture"])
	player_card.set_drag_hovered(false)
	play_place_sound()
	discard_top_card.visible = false

	play_slide_sound()
	var center_tween := create_tween()
	center_tween.tween_property(center_draw_card, "global_position", discard_pile_position, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await center_tween.finished
	place_card_on_discard(center_draw_card)
	play_place_sound()
	center_draw_card.visible = false

	await animate_card_to_discard(old_hand_data, player_card.global_position)

	current_player = 3 - current_player  # Toggle between players 1 and 2.
	await start_turn()


func return_discard_card() -> void:
	turn_state = TurnState.ANIMATING

	play_slide_sound()
	var move_tween := create_tween()
	move_tween.tween_property(discard_top_card, "global_position", discard_pile_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	discard_top_card.scale = NORMAL_CARD_SCALE
	# Only keep the hover look if the pointer actually rests on the card.
	var pointer_on_card := discard_top_card.get_global_rect().has_point(get_global_mouse_position())
	highlight_card(discard_top_card, pointer_on_card)
	turn_state = TurnState.WAITING_FOR_DROP


func animate_card_to_discard(card_data: Dictionary, start_position: Vector2) -> void:
	flying_card.visible = true
	flying_card.setup_card(
		card_data["rank"],
		card_data["suit"],
		card_data["texture"]
	)
	flying_card.global_position = start_position
	flying_card.scale = NORMAL_CARD_SCALE
	flying_card.z_index = 6

	var move_tween := create_tween()
	move_tween.tween_property(flying_card, "global_position", discard_pile_position, DISCARD_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	flying_card.flip_to_front(false)

	await move_tween.finished
	place_card_on_discard(flying_card)
	flying_card.visible = false
	play_place_sound()


## Stamp `card`'s face onto the discard pile's top-card slot.
func place_card_on_discard(card: BoardCard) -> void:
	discard_top_card.visible = true
	discard_top_card.setup_card(card.rank, card.suit, card.front_texture)
	discard_top_card.show_front()
	discard_top_card.can_drag = false
	discard_top_card.global_position = discard_pile_position
	discard_top_card.scale = NORMAL_CARD_SCALE
	discard_top_card.z_index = 5


func is_card_over_discard_pile(card: Card) -> bool:
	return get_overlap_area(card.get_global_rect(), Card.sprite_global_rect(discard_pile_sprite)) > 0.0


func create_fullscreen_overlay(alpha: float, overlay_z_index: int) -> ColorRect:
	# Sized explicitly: anchor presets don't reliably fill the viewport for
	# Controls parented to a Node2D, which left overlays collapsed at (0,0).
	var overlay := ColorRect.new()
	overlay.position = Vector2.ZERO
	overlay.size = screen_size
	overlay.color = Color(0.0, 0.0, 0.0, alpha)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = overlay_z_index
	add_child(overlay)
	return overlay


func create_special_overlay() -> void:
	if special_overlay:
		return
	special_overlay = create_fullscreen_overlay(0.65, OVERLAY_Z_INDEX)


func remove_special_overlay() -> void:
	if special_overlay:
		special_overlay.queue_free()
		special_overlay = null


func set_hand_enabled(hand: PlayerHand, enabled: bool) -> void:
	for card in hand.cards:
		card.modulate = Color.WHITE if enabled else Color(0.35, 0.35, 0.35)


func run_seven_swap_power() -> void:
	turn_state = TurnState.SPECIAL_7

	selected_source_card = null
	hovered_special_card = null
	seven_selecting_opponent = false
	seven_power_done = false

	create_special_overlay()
	show_seven_skip_button()
	set_seven_phase_hands(get_active_hand(), get_other_hand())

	# Block until the swap animation finishes or the player skips, so the
	# turn cannot resume while cards are still flying.
	while not seven_power_done:
		await get_tree().process_frame

	remove_seven_skip_button()
	remove_special_overlay()
	set_hand_enabled(player1_hand, true)
	set_hand_enabled(player2_hand, true)
	player1_hand.z_index = 0
	player2_hand.z_index = 0


func show_seven_skip_button() -> void:
	seven_skip_button = Button.new()
	seven_skip_button.text = "Skip (don't swap)"
	seven_skip_button.theme = UI_THEME
	seven_skip_button.add_theme_font_size_override("font_size", 48)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		seven_skip_button.add_theme_color_override(color_name, Color(0.08, 0.07, 0.05))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.9, 0.82)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28.0)
	seven_skip_button.add_theme_stylebox_override("normal", style)
	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.85, 0.8, 0.7)
	seven_skip_button.add_theme_stylebox_override("pressed", pressed_style)
	seven_skip_button.add_theme_stylebox_override("hover", style)
	seven_skip_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	seven_skip_button.focus_mode = Control.FOCUS_NONE
	seven_skip_button.z_index = OVERLAY_Z_INDEX + 10
	seven_skip_button.size = Vector2(580.0, 130.0)
	seven_skip_button.position = (screen_size - seven_skip_button.size) * 0.5
	seven_skip_button.pivot_offset = seven_skip_button.size * 0.5
	# Face the active player: Player 2 sits at the top of the screen.
	if current_player == 2:
		seven_skip_button.rotation_degrees = 180.0
	seven_skip_button.pressed.connect(on_seven_skip_pressed)
	add_child(seven_skip_button)

	# Quick pop-in.
	seven_skip_button.scale = Vector2(0.6, 0.6)
	seven_skip_button.modulate.a = 0.0
	var pop := create_tween().set_parallel(true)
	pop.tween_property(seven_skip_button, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(seven_skip_button, "modulate:a", 1.0, 0.18)


func remove_seven_skip_button() -> void:
	if seven_skip_button:
		seven_skip_button.queue_free()
		seven_skip_button = null


func on_seven_skip_pressed() -> void:
	if turn_state != TurnState.SPECIAL_7:
		return

	if selected_source_card:
		selected_source_card.set_special_selected(false)
		selected_source_card = null
	if hovered_special_card:
		hovered_special_card.set_drag_hovered(false)
		hovered_special_card = null

	seven_power_done = true


## Light up and raise the hand the player may pick from; dim and lower the other.
func set_seven_phase_hands(selectable: PlayerHand, locked: PlayerHand) -> void:
	set_hand_enabled(selectable, true)
	set_hand_enabled(locked, false)
	selectable.z_index = RAISED_HAND_Z_INDEX
	locked.z_index = 0


## The card under `point` in whichever hand is currently selectable.
func get_seven_card_at(point: Vector2) -> PlayerCard:
	var hand := get_other_hand() if seven_selecting_opponent else get_active_hand()
	var best_card: PlayerCard = null
	var highest_z := -9999

	for card in hand.cards:
		if card.get_global_rect().has_point(point) and card.z_index > highest_z:
			highest_z = card.z_index
			best_card = card

	return best_card


func update_seven_hover() -> void:
	var new_hover := get_seven_card_at(get_global_mouse_position())

	if hovered_special_card == new_hover:
		return

	if hovered_special_card and hovered_special_card != selected_source_card:
		hovered_special_card.set_drag_hovered(false)

	hovered_special_card = new_hover

	if hovered_special_card and hovered_special_card != selected_source_card:
		hovered_special_card.set_drag_hovered(true)


func handle_seven_click() -> void:
	# Resolve the card at the tap position directly: on touch screens the
	# hover state tracked in _process lags one frame behind the finger.
	var clicked_card := get_seven_card_at(get_global_mouse_position())
	if clicked_card == null:
		return

	if not seven_selecting_opponent:
		selected_source_card = clicked_card
		selected_source_card.set_special_selected(true)
		seven_selecting_opponent = true
		hovered_special_card = null

		set_seven_phase_hands(get_other_hand(), get_active_hand())
		# Keep the chosen card lit and above the dim overlay while picking a target.
		selected_source_card.modulate = Color.WHITE
		selected_source_card.z_index = RAISED_HAND_Z_INDEX
		return

	var source_card := selected_source_card
	var target_card := clicked_card

	turn_state = TurnState.ANIMATING
	source_card.set_special_selected(false)
	target_card.set_drag_hovered(false)
	selected_source_card = null
	hovered_special_card = null

	await animate_swap_player_cards(source_card, target_card)
	seven_power_done = true


## Fly two cards to each other's slots, then swap their data and snap back.
## Both cards are face-down, so the snap-back is invisible to the players.
func animate_swap_player_cards(first: PlayerCard, second: PlayerCard) -> void:
	var first_data := first.to_card_data()
	var second_data := second.to_card_data()

	var first_global := first.global_position
	var second_global := second.global_position

	first.z_index = RAISED_HAND_Z_INDEX
	second.z_index = RAISED_HAND_Z_INDEX

	play_slide_sound()
	var swap_tween := create_tween().set_parallel(true)
	swap_tween.tween_property(first, "global_position", second_global, SWAP_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	swap_tween.tween_property(second, "global_position", first_global, SWAP_FLY_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await swap_tween.finished

	first.setup_card(second_data["rank"], second_data["suit"], second_data["texture"])
	second.setup_card(first_data["rank"], first_data["suit"], first_data["texture"])
	play_place_sound()

	player1_hand.arrange_cards()
	player2_hand.arrange_cards()


func get_active_hand() -> PlayerHand:
	return player1_hand if current_player == 1 else player2_hand


func get_other_hand() -> PlayerHand:
	return player2_hand if current_player == 1 else player1_hand


func end_game() -> void:
	turn_state = TurnState.GAME_OVER
	center_draw_card.visible = false
	await reveal_all_cards()
	show_game_over_overlay()


func reveal_all_cards() -> void:
	var all_cards: Array[PlayerCard] = []
	all_cards.append_array(player1_hand.cards)
	all_cards.append_array(player2_hand.cards)

	for card in all_cards:
		await card.animate_flip(true, player_card_flip_time)


## Cabo scoring: A=1, number cards face value, J=11, Q=12, K=13.
func get_card_value(card_rank: String) -> int:
	match card_rank:
		"A": return 1
		"J": return 11
		"Q": return 12
		"K": return 13
		_: return int(card_rank)


func get_hand_score(hand: PlayerHand) -> int:
	var total := 0
	for card in hand.cards:
		total += get_card_value(card.rank)
	return total


func show_game_over_overlay() -> void:
	var player1_score := get_hand_score(player1_hand)
	var player2_score := get_hand_score(player2_hand)

	# Lowest total wins.
	var title := "It's a tie!"
	if player1_score < player2_score:
		title = "Player 1 wins!"
	elif player2_score < player1_score:
		title = "Player 2 wins!"

	game_over_overlay = create_fullscreen_overlay(0.9, 400)

	# The winner line runs vertically through the center so both players can
	# read it from their side of the phone.
	var title_label := make_overlay_label(title, 72)
	title_label.size = Vector2(screen_size.y, 110.0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.pivot_offset = title_label.size * 0.5
	title_label.rotation_degrees = 90.0
	title_label.position = (screen_size - title_label.size) * 0.5
	game_over_overlay.add_child(title_label)

	var layout := VBoxContainer.new()
	layout.position = Vector2(0.0, screen_size.y * 0.72)
	layout.size = Vector2(screen_size.x, screen_size.y * 0.24)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 24)
	game_over_overlay.add_child(layout)

	layout.add_child(make_overlay_label("Player 1: %d points" % player1_score, 40))
	layout.add_child(make_overlay_label("Player 2: %d points" % player2_score, 40))
	layout.add_child(make_overlay_label("Tap anywhere for the main menu", 30))


func make_overlay_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.theme = UI_THEME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func return_to_main_menu() -> void:
	if is_returning_to_menu:
		return
	is_returning_to_menu = true

	# Fade to black, then swap scenes; the menu fades back in on its side.
	var fade := create_fullscreen_overlay(0.0, 500)
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 1.0, 0.35)
	await fade_tween.finished
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
