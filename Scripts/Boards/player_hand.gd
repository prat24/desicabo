## PlayerHand — arranges PlayerCard children in a fan arc along a screen edge.
## @tool makes the layout visible and tweakable live in the Godot editor.
@tool
extends Node2D
class_name PlayerHand

# ── Layout — every property instantly updates the editor preview ──────────────
# Defaults match the two-player table; GameManager overrides them per player
# count, since three hands share the same screen edge.
@export var card_spacing: float = 290.0:
	set(v): card_spacing = v; _refresh()
@export var arc_height: float = 55.0:
	set(v): arc_height = v; _refresh()
@export var bottom_offset: float = 240.0:
	set(v): bottom_offset = v; _refresh()
@export var top_offset: float = 240.0:
	set(v): top_offset = v; _refresh()
@export var max_rotation_degrees: float = 10.0:
	set(v): max_rotation_degrees = v; _refresh()
@export var card_scale: Vector2 = Vector2(1.4, 1.4):
	set(v): card_scale = v; _refresh()

# ── Identity ──────────────────────────────────────────────────────────────────
## Which player owns this hand. Stamped onto each card on deal.
@export var player_id: int = 1
## When true, cards are anchored to the top of the screen (Player 2).
@export var position_at_top: bool = false:
	set(v): position_at_top = v; _refresh()
## When true, the layout spans the screen's vertical edge instead (the local
## span uses swapped viewport dimensions). The side player in 3-player mode.
@export var sideways: bool = false:
	set(v): sideways = v; _refresh()
## If true, deals a random hand in _ready() — handy for editor testing.
@export var auto_deal: bool = false

var cards: Array[PlayerCard] = []

func _ready() -> void:
	cards = _collect_cards()
	# Stamp ownership up front. Dealing also sets this, but a hand that is
	# never dealt (Player 3 in a 2-player game) would otherwise keep the
	# default id of 1 and answer to Player 1's drop targeting.
	for card in cards:
		card.player_id = player_id
	if auto_deal:
		deal_from_deck(CardDeck.create_shuffled_deck())
	arrange_cards()
	if not Engine.is_editor_hint() and not auto_deal:
		for card in cards:
			card.visible = false


## Consume cards from the front of deck and assign them to this hand.
func deal_from_deck(deck: Array[Dictionary]) -> void:
	for i in range(cards.size()):
		if deck.is_empty():
			return
		var d: Dictionary = deck.pop_front()
		cards[i].player_id = player_id
		cards[i].setup_card(d["rank"], d["suit"], d["texture"])


## Move every slot to the deck so cards can fly in one at a time. Hand cards are
## drawn larger than cards on the board, so the stack shrinks to the pile's size
## and each card grows back on its way out.
func stack_cards_at_deck(deck_global_pos: Vector2, deck_rotation_degrees: float, deck_scale: Vector2) -> void:
	for card in cards:
		card.visible = true
		card.global_position = deck_global_pos
		card.rotation_degrees = _deck_local_rotation(deck_rotation_degrees)
		# The card's child sprite is pre-scaled, so divide that out to sit at
		# exactly the deck pile's on-screen size.
		card.scale = deck_scale / card.sprite.scale.x
		card.z_index = 0


## Local rotation that visually matches the deck pile's orientation (card
## backs are 180°-symmetric, so the nearest half-turn keeps flights short).
func _deck_local_rotation(deck_rotation_degrees: float) -> float:
	return wrapf(deck_rotation_degrees - global_rotation_degrees, -90.0, 90.0)


## Deal one card from deck with a fly-in animation from the deck sprite.
func animate_deal_card(
	card_index: int,
	card_data: Dictionary,
	deck_global_pos: Vector2,
	fly_time: float,
	deck_scale: Vector2 = Vector2.ONE,
	deck_rotation_degrees: float = 0.0
) -> void:
	var card: PlayerCard = cards[card_index]
	card.player_id = player_id
	card.setup_card(card_data["rank"], card_data["suit"], card_data["texture"])
	card.visible = true
	card.global_position = deck_global_pos
	card.rotation_degrees = _deck_local_rotation(deck_rotation_degrees)
	# The card's child sprite is pre-scaled, so divide that out to spawn at
	# exactly the deck pile's on-screen size.
	card.scale = deck_scale / card.sprite.scale.x
	card.z_index = 100

	var target_global: Vector2 = to_global(card.resting_position)
	var fly := create_tween().set_parallel(true)
	fly.tween_property(card, "global_position", target_global, fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fly.tween_property(card, "rotation_degrees", card.resting_rotation_degrees, fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fly.tween_property(card, "scale", card_scale, fly_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await fly.finished

	card.position = card.resting_position
	card.rotation_degrees = card.resting_rotation_degrees
	card.resting_scale = card_scale
	card.scale = card_scale
	card.set_resting_z_index(card_index)


## Position all cards in a fan arc anchored to the player's screen edge.
func arrange_cards() -> void:
	if cards.is_empty():
		return

	var screen: Vector2 = _screen_size()
	var anchor_y: float = top_offset if position_at_top else screen.y - bottom_offset
	var center := Vector2(screen.x * 0.5, anchor_y)
	var mid: float = (cards.size() - 1) * 0.5

	for i in range(cards.size()):
		var card: PlayerCard = cards[i]
		var t: float = (i - mid) / mid if mid > 0.0 else 0.0
		var arc: float = pow(abs(t), 2.0) * arc_height
		card.set_resting_position(Vector2(center.x + (i - mid) * card_spacing, center.y + arc * (-1.0 if position_at_top else 1.0)))
		card.resting_rotation_degrees = (180.0 if position_at_top else 0.0) + t * max_rotation_degrees
		card.rotation_degrees = card.resting_rotation_degrees
		card.hover_lift_sign = -1.0 if position_at_top else 1.0
		card.resting_scale = card_scale
		card.scale = card_scale
		card.set_resting_z_index(i)


# ── Private helpers ────────────────────────────────────────────────────────────

func _collect_cards() -> Array[PlayerCard]:
	var result: Array[PlayerCard] = []
	for child in get_children():
		if child is PlayerCard:
			result.append(child)
	return result


## Returns the game resolution in both editor and runtime contexts.
func _screen_size() -> Vector2:
	var size: Vector2
	if Engine.is_editor_hint():
		size = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
		)
	else:
		size = get_viewport_rect().size
	return Vector2(size.y, size.x) if sideways else size


## Called by property setters — re-arranges cards once _ready() has run.
func _refresh() -> void:
	if is_node_ready():
		arrange_cards()


## Animate all cards flying to shuffled positions and swap their underlying data.
## Called when the active player draws a Jack (affects the opponent's hand).
func jumble_cards() -> void:
	var count := cards.size()
	if count < 2:
		return

	# Snapshot positions and data before anything moves.
	var rest_positions: Array[Vector2] = []
	var card_data: Array[Dictionary] = []
	for card in cards:
		rest_positions.append(card.resting_position)
		card_data.append(card.to_card_data())

	# Build a shuffled index mapping (guaranteed to change at least one card).
	var new_order: Array = range(count)
	new_order.shuffle()
	var all_fixed := true
	for idx in range(count):
		if new_order[idx] != idx:
			all_fixed = false
			break
	if all_fixed:
		new_order[0] = 1
		new_order[1] = 0

	# Fly all cards to their new slot positions simultaneously.
	for card in cards:
		card.z_index = 50
	var fly := create_tween().set_parallel(true)
	for idx in range(count):
		fly.tween_property(cards[idx], "position", rest_positions[new_order[idx]], 0.45) \
		   .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await fly.finished

	# Apply shuffled data and restore card state.
	for idx in range(count):
		cards[idx].setup_card(
			card_data[new_order[idx]]["rank"],
			card_data[new_order[idx]]["suit"],
			card_data[new_order[idx]]["texture"]
		)
		cards[idx].show_back()
	arrange_cards()
