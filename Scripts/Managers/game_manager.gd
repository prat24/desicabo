## GameManager — runs the full game loop: dealing, turns, drag-and-drop, and animations.
extends Node2D

const CARD_COLLISION_MASK = 1
const NORMAL_CARD_SCALE = Vector2(1.0, 1.0)
const HOVERED_CARD_SCALE = Vector2(1.05, 1.05)
const SNAP_TIME = 0.18
const DEAL_FLY_TIME = 0.28
const DEAL_STAGGER_TIME = 0.07

@export_range(0.0, 15.0, 0.1) var pre_game_reveal_time: float = 5.0
@export_range(0.1, 0.8, 0.01) var initial_deal_fly_time: float = DEAL_FLY_TIME
@export_range(0.0, 0.3, 0.01) var initial_deal_stagger: float = DEAL_STAGGER_TIME
@export_range(0.0, 1.0, 0.01) var pre_game_dim_alpha: float = 0.35
@export_range(0.05, 1.5, 0.01) var player_card_flip_time: float = 0.24

enum TurnState {
	DEALING,
	WAITING_FOR_DROP,
	ANIMATING,
	SPECIAL_7,
	GAME_OVER
}

var dragged_card: Node2D
var hovered_player_card: PlayerCard
var screen_size: Vector2
var is_hovering_card: bool = false
var turn_state: TurnState = TurnState.DEALING
var deck: Array[Dictionary] = []
var center_draw_position: Vector2 = Vector2.ZERO
var discard_pile_position: Vector2 = Vector2.ZERO
var intro_dim_overlay: ColorRect
var current_player: int = 1        ## 1 or 2 — whose turn it is.
var player2_revealed: bool = false ## True once Player 2 has seen their hand reveal.
var special_overlay: ColorRect
var selected_source_card: PlayerCard = null
var hovered_special_card: PlayerCard = null
var seven_selecting_opponent: bool = false
var card_highlight_tweens: Dictionary = {}

# ── Scene references ──────────────────────────────────────────────────────────
@onready var background: ColorRect = $Background
@onready var deck_sprite: Sprite2D = $DeckSprite
@onready var center_draw_card: BoardCard = $CenterDrawCard
@onready var discard_pile_sprite: Sprite2D = $DiscardPileSprite
@onready var discard_top_card: BoardCard = $DiscardTopCard
@onready var player1_hand: PlayerHand = $PlayerHand
@onready var player2_hand: PlayerHand = $Player2Hand

func _ready() -> void:
	screen_size = get_viewport_rect().size
	center_draw_position = center_draw_card.global_position
	discard_pile_position = discard_pile_sprite.global_position
	center_draw_card.visible = false
	discard_top_card.visible = false
	discard_top_card.get_node("Area2D").input_pickable = false
	discard_top_card.get_node("Area2D/CollisionShape2D").disabled = true
	setup_board_card_shaders()
	connect_center_draw_card_signals()
	randomize()
	deck = CardDeck.create_shuffled_deck()
	await deal_initial_hands_animated()
	await run_pre_game_hand_reveal()
	await start_turn()


func setup_board_card_shaders() -> void:
	CardShader.apply(deck_sprite, 12.0)
	CardShader.apply(discard_pile_sprite, 24.0)
	CardShader.set_inset(deck_sprite, 0.03)
	CardShader.set_inset(discard_pile_sprite, 0.03)


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

		await player2_hand.animate_deal_card(
			slot,
			deck.pop_front(),
			deck_pos,
			initial_deal_fly_time,
			deck_scale
		)
		if initial_deal_stagger > 0.0 and slot < slots_per_hand - 1:
			await get_tree().create_timer(initial_deal_stagger).timeout

func run_pre_game_hand_reveal() -> void:
	await run_hand_reveal(player1_hand)


func run_hand_reveal(hand: PlayerHand) -> void:
	create_intro_dim_overlay()
	dim_for_hand_reveal(hand, true)

	for card in hand.cards:
		card.show_front()

	var card_count: int = hand.cards.size()
	var flip_time_total: float = card_count * player_card_flip_time
	var hold_time: float = maxf(0.0, pre_game_reveal_time - flip_time_total)

	if hold_time > 0.0:
		await get_tree().create_timer(hold_time).timeout

	for card in hand.cards:
		await card.animate_flip_to_back(player_card_flip_time)

	dim_for_hand_reveal(hand, false)
	if intro_dim_overlay:
		intro_dim_overlay.queue_free()
		intro_dim_overlay = null


func create_intro_dim_overlay() -> void:
	if intro_dim_overlay:
		return

	intro_dim_overlay = ColorRect.new()
	intro_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_dim_overlay.color = Color(0.0, 0.0, 0.0, pre_game_dim_alpha)
	intro_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_dim_overlay.z_index = 200
	add_child(intro_dim_overlay)


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

	if dragged_card is BoardCard:
		dragged_card.update_shader_tilt(mouse_position)
		CardShader.set_hover(dragged_card.sprite, 1.0)
		CardShader.set_inset(dragged_card.sprite, 0.0)

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
	if turn_state == TurnState.SPECIAL_7:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				await handle_seven_click()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card := check_card_click()
			if card:
				start_card_drag(card)
		else:
			if dragged_card:
				await end_card_drag()


func start_card_drag(card: Node2D) -> void:
	if turn_state != TurnState.WAITING_FOR_DROP:
		return

	if card != center_draw_card:
		return

	if card is BoardCard and !card.can_drag:
		return

	if card is BoardCard:
		card.tween_hover_scale(NORMAL_CARD_SCALE)
		CardShader.set_hover(card.sprite, 1.0)
		CardShader.set_inset(card.sprite, 0.0)

	dragged_card = card


func end_card_drag() -> void:
	var dropped_card := dragged_card
	var target_player_card := hovered_player_card

	clear_player_card_drag_hover()
	dragged_card = null

	if dropped_card != center_draw_card:
		return

	if target_player_card:
		await swap_draw_card_with_player_card(target_player_card)
	elif is_card_over_discard_pile(center_draw_card):
		await discard_center_draw_card()
	else:
		await return_center_draw_card()


## Called by BoardCard._ready() so this manager can connect its hover signals.
func connect_card_signals(_card: Node2D) -> void:
	connect_center_draw_card_signals()


func connect_center_draw_card_signals() -> void:
	if center_draw_card == null or !is_instance_valid(center_draw_card):
		return

	if center_draw_card.hovered.is_connected(on_hovered_over_card):
		return

	center_draw_card.hovered.connect(on_hovered_over_card)
	center_draw_card.hovered_off.connect(on_hovered_off_card)


func on_hovered_over_card(card: Node2D) -> void:
	if !is_hovering_card:
		is_hovering_card = true
		highlight_card(card, true)


func on_hovered_off_card(card: Node2D) -> void:
	if !dragged_card:
		highlight_card(card, false)
		var new_card_hovered := check_card_click()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_card = false


func highlight_card(card: Node2D, hovered: bool) -> void:
	if card_highlight_tweens.has(card):
		card_highlight_tweens[card].kill()

	if card is BoardCard:
		var board_card := card as BoardCard
		var target_scale := HOVERED_CARD_SCALE if hovered else NORMAL_CARD_SCALE
		board_card.tween_hover_scale(target_scale)
		board_card.z_index = 2 if hovered else 1
		CardShader.set_hover(board_card.sprite, 1.0 if hovered else 0.0)
		if hovered:
			CardShader.set_inset(board_card.sprite, 0.0)
		else:
			CardShader.tween_inset(board_card, board_card.sprite, 0.02, 0.12)
		return

	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_highlight_tweens[card] = tween
	var target_scale := HOVERED_CARD_SCALE if hovered else NORMAL_CARD_SCALE
	tween.tween_property(card, "scale", target_scale, 0.14)
	card.z_index = 2 if hovered else 1


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

	var dragged_card_rect := get_card_global_rect(dragged_card)
	var best_player_card: PlayerCard
	var best_overlap_area := 0.0

	for player_card in get_tree().get_nodes_in_group("player_cards"):
		if player_card is PlayerCard and player_card.player_id == current_player:
			var overlap_area := get_overlap_area(dragged_card_rect, player_card.get_collision_rect())
			if overlap_area > best_overlap_area:
				best_overlap_area = overlap_area
				best_player_card = player_card

	return best_player_card


func get_overlap_area(first_rect: Rect2, second_rect: Rect2) -> float:
	if !first_rect.intersects(second_rect):
		return 0.0

	var overlap_rect := first_rect.intersection(second_rect)
	return overlap_rect.size.x * overlap_rect.size.y


func get_card_global_rect(card: Node2D) -> Rect2:
	var card_sprite := card.get_node_or_null("Sprite2D") as Sprite2D
	if card_sprite == null:
		return Rect2()

	var local_rect := card_sprite.get_rect()
	var corners := [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y)
	]
	var first_corner: Vector2 = card_sprite.global_transform * corners[0]
	var min_position := first_corner
	var max_position := first_corner

	for corner_index in range(1, corners.size()):
		var global_corner: Vector2 = card_sprite.global_transform * corners[corner_index]
		min_position = min_position.min(global_corner)
		max_position = max_position.max(global_corner)

	return Rect2(min_position, max_position - min_position)


func start_turn() -> void:
	if deck.is_empty():
		turn_state = TurnState.GAME_OVER
		center_draw_card.visible = false
		await reveal_all_cards()
		return

	if current_player == 2 and not player2_revealed:
		player2_revealed = true
		await run_hand_reveal(player2_hand)

	turn_state = TurnState.DEALING
	await deal_center_draw_card()
	await _check_special_card_effect()
	if turn_state != TurnState.SPECIAL_7:
		turn_state = TurnState.WAITING_FOR_DROP


## Queen: reveal the active player's own hand.
## King: reveal the other player's hand.
## Jack: jumble the other player's cards randomly.
func _check_special_card_effect() -> void:
	match center_draw_card.rank:
		"Q":
			await run_hand_reveal(get_active_hand())

		"K":
			await run_hand_reveal(get_other_hand())

		"J":
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
	center_draw_card.scale = NORMAL_CARD_SCALE
	center_draw_card.z_index = 10
	center_draw_card.show_back()
	center_draw_card.can_drag = false
	center_draw_card.global_position = deck_sprite.global_position
	center_draw_card.scale = deck_sprite.scale

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

	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", discard_pile_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	copy_draw_card_to_discard(center_draw_card)
	center_draw_card.visible = false
	current_player = 3 - current_player
	await start_turn()


func swap_draw_card_with_player_card(player_card: PlayerCard) -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false

	var old_card_data := get_player_card_data(player_card)
	var new_card_data := get_draw_card_data(center_draw_card)

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
	center_draw_card.visible = false

	await animate_card_to_discard(old_card_data, player_card.global_position)
	current_player = 3 - current_player
	await start_turn()


func return_center_draw_card() -> void:
	turn_state = TurnState.ANIMATING
	center_draw_card.can_drag = false

	var move_tween := create_tween()
	move_tween.tween_property(center_draw_card, "global_position", center_draw_position, SNAP_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move_tween.finished

	center_draw_card.scale = NORMAL_CARD_SCALE
	center_draw_card.tween_hover_scale(HOVERED_CARD_SCALE)
	center_draw_card.can_drag = true
	turn_state = TurnState.WAITING_FOR_DROP


func animate_card_to_discard(card_data: Dictionary, start_position: Vector2) -> void:
	discard_top_card.visible = true
	discard_top_card.setup_card(
		card_data["rank"],
		card_data["suit"],
		card_data["texture"]
	)
	discard_top_card.show_back()
	discard_top_card.can_drag = false
	discard_top_card.global_position = start_position
	discard_top_card.scale = NORMAL_CARD_SCALE
	discard_top_card.z_index = 5

	var move_tween := create_tween()
	move_tween.tween_property(discard_top_card, "global_position", discard_pile_position, 0.34) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	discard_top_card.flip_to_front(false)

	await move_tween.finished
	discard_top_card.global_position = discard_pile_position

func copy_draw_card_to_discard(card: BoardCard) -> void:
	discard_top_card.visible = true
	discard_top_card.setup_card(card.rank, card.suit, card.front_texture)
	discard_top_card.show_front()
	discard_top_card.can_drag = false
	discard_top_card.global_position = discard_pile_position
	discard_top_card.scale = NORMAL_CARD_SCALE
	discard_top_card.z_index = 5


func is_card_over_discard_pile(card: Node2D) -> bool:
	return get_overlap_area(get_card_global_rect(card), get_sprite_global_rect(discard_pile_sprite)) > 0.0

func create_special_overlay() -> void:
	if special_overlay:
		return

	special_overlay = ColorRect.new()
	special_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	special_overlay.color = Color(0, 0, 0, 0.65)
	special_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	special_overlay.z_index = 150

	add_child(special_overlay)


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

	create_special_overlay()
	set_hand_enabled(get_active_hand(), true)
	set_hand_enabled(get_other_hand(), false)

	while turn_state == TurnState.SPECIAL_7:
		await get_tree().process_frame


func update_seven_hover() -> void:
	var hand := get_other_hand() if seven_selecting_opponent else get_active_hand()

	var mouse_position := get_global_mouse_position()

	var new_hover: PlayerCard = null
	var highest_z := -9999

	for card in hand.cards:
		if card.get_collision_rect().has_point(mouse_position):
			if card.z_index > highest_z:
				highest_z = card.z_index
				new_hover = card

	if hovered_special_card == new_hover:
		return

	if hovered_special_card:
		if hovered_special_card != selected_source_card:
			hovered_special_card.set_drag_hovered(false)

	hovered_special_card = new_hover

	if hovered_special_card:
		if hovered_special_card != selected_source_card:
			hovered_special_card.set_drag_hovered(true)


func handle_seven_click() -> void:
	if hovered_special_card == null:
		return

	if !seven_selecting_opponent:
		selected_source_card = hovered_special_card
		selected_source_card.set_special_selected(true)

		set_hand_enabled(get_active_hand(), false)
		set_hand_enabled(get_other_hand(), true)

		seven_selecting_opponent = true

		hovered_special_card = null
		return

	var source_card := selected_source_card
	var target_card := hovered_special_card

	turn_state = TurnState.ANIMATING

	source_card.set_special_selected(false)
	source_card.set_drag_hovered(false)
	target_card.set_drag_hovered(false)

	selected_source_card = null
	hovered_special_card = null

	await animate_swap_player_cards(
		source_card,
		target_card
	)

	remove_special_overlay()

	set_hand_enabled(player1_hand, true)
	set_hand_enabled(player2_hand, true)

	turn_state = TurnState.WAITING_FOR_DROP

func animate_swap_player_cards(
	first: PlayerCard,
	second: PlayerCard
) -> void:

	var first_data := get_player_card_data(first)
	var second_data := get_player_card_data(second)

	var first_global := first.global_position
	var second_global := second.global_position

	first.z_index = 200
	second.z_index = 200

	var tween := create_tween().set_parallel(true)

	tween.tween_property(
		first,
		"global_position",
		second_global,
		0.4
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		second,
		"global_position",
		first_global,
		0.4
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	first.setup_card(
		second_data["rank"],
		second_data["suit"],
		second_data["texture"]
	)

	second.setup_card(
		first_data["rank"],
		first_data["suit"],
		first_data["texture"]
	)

	first.show_back()
	second.show_back()

	first.set_special_selected(false)

	player1_hand.arrange_cards()
	player2_hand.arrange_cards()


func get_active_hand() -> PlayerHand:
	return player1_hand if current_player == 1 else player2_hand


func get_other_hand() -> PlayerHand:
	return player2_hand if current_player == 1 else player1_hand

func get_player_card_data(player_card: PlayerCard) -> Dictionary:
	return {
		"rank": player_card.rank,
		"suit": player_card.suit,
		"texture": player_card.front_texture
	}


func get_draw_card_data(card: BoardCard) -> Dictionary:
	return {
		"rank": card.rank,
		"suit": card.suit,
		"texture": card.front_texture
	}


func get_sprite_global_rect(card_sprite: Sprite2D) -> Rect2:
	var local_rect := card_sprite.get_rect()
	var corners := [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y)
	]
	var first_corner: Vector2 = card_sprite.global_transform * corners[0]
	var min_position := first_corner
	var max_position := first_corner

	for corner_index in range(1, corners.size()):
		var global_corner: Vector2 = card_sprite.global_transform * corners[corner_index]
		min_position = min_position.min(global_corner)
		max_position = max_position.max(global_corner)

	return Rect2(min_position, max_position - min_position)

func reveal_all_cards() -> void:
	var all_cards: Array[PlayerCard] = []

	all_cards.append_array(player1_hand.cards)
	all_cards.append_array(player2_hand.cards)

	for card in all_cards:
		await card.animate_flip_to_front(player_card_flip_time)
