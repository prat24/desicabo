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
## Slides the whole fan along the edge it hugs, in this hand's own frame, so a
## positive shift always moves toward its player's right. Four-player tables need
## it: two hands share the right edge, and the other two step aside for them.
@export var edge_shift: float = 0.0:
	set(v): edge_shift = v; _refresh()

# ── Identity ──────────────────────────────────────────────────────────────────
## Which player owns this hand, stamped onto each of its cards — drop targeting
## and power picks go by the card's stamp. The scene numbers the hands as Player
## 1 sees the table; GameManager re-seats them for every other screen.
@export var player_id: int = 1:
	set(v):
		player_id = v
		for card in cards:
			card.player_id = v
## When true, cards are anchored to the top of the screen (the top place).
@export var position_at_top: bool = false:
	set(v): position_at_top = v; _refresh()
## When true, the layout spans the screen's vertical edge instead (the local
## span uses swapped viewport dimensions). The right-edge places, 3+ players.
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
		_place_on_deck(card, deck_global_pos, deck_rotation_degrees, deck_scale)
		card.z_index = 0


## Sit `card` exactly on the deck pile: same spot, same size, and turned the
## same way on screen as the pile, whichever way this hand itself is turned.
## The card back is not symmetric under a half-turn, so the card has to match
## the pile outright — the flight out does the turning toward the hand.
func _place_on_deck(card: PlayerCard, deck_global_pos: Vector2, deck_rotation_degrees: float, deck_scale: Vector2) -> void:
	card.global_position = deck_global_pos
	card.global_rotation_degrees = deck_rotation_degrees
	# The card's child sprite is pre-scaled, so divide that out to sit at
	# exactly the deck pile's on-screen size.
	card.scale = deck_scale / card.sprite_rest_scale.x
	card.shadow.position = card.shadow_rest_position


## Deal one card from deck with a fly-in animation from the deck sprite: it
## snaps out, leaning into the move and turning to its slot's angle on the way,
## and lands already sitting in the fan. `on_landed` runs on the frame the card reads as
## arrived in the hand.
##
## Returns the flight rather than waiting on it, so the dealer can send the next
## card while this one is still in the air; await its `finished` to wait for the
## landing. The card is settled into its slot before any such await resumes.
func animate_deal_card(
	card_index: int,
	card_data: Dictionary,
	deck_global_pos: Vector2,
	fly_time: float,
	deck_scale: Vector2 = Vector2.ONE,
	deck_rotation_degrees: float = 0.0,
	on_landed: Callable = Callable()
) -> Tween:
	var card: PlayerCard = cards[card_index]
	card.player_id = player_id
	card.setup_card(card_data["rank"], card_data["suit"], card_data["texture"])
	card.visible = true
	_place_on_deck(card, deck_global_pos, deck_rotation_degrees, deck_scale)
	# Deals overlap, so a later card has to fly over the ones still in the air.
	card.z_index = 100 + card_index

	var fly := create_tween().set_parallel(true)
	CardMotion.fly(fly, card, slot_global_position(card_index), slot_global_rotation(card_index), card_scale, fly_time)
	if on_landed.is_valid():
		CardMotion.cue_on_landing(fly, on_landed, fly_time)
	# Connected before anyone can await it, so it runs first.
	fly.finished.connect(_settle_dealt_card.bind(card_index))
	return fly


## Snap a dealt card's resting state in exactly once its flight is over.
func _settle_dealt_card(card_index: int) -> void:
	var card: PlayerCard = cards[card_index]
	card.position = card.resting_position
	card.rotation_degrees = card.resting_rotation_degrees
	card.resting_scale = card_scale
	card.scale = card_scale
	card.shadow.position = card.shadow_rest_position
	card.set_resting_z_index(card_index)


## The on-screen angle, in radians, of the card resting in `card_index` — the
## hand's own turn plus that slot's tilt in the fan. A card flying in from
## elsewhere turns to this on the way, so it lands already sitting right.
func slot_global_rotation(card_index: int) -> float:
	return global_rotation + deg_to_rad(cards[card_index].resting_rotation_degrees)


## Where the card resting in `card_index` sits on screen.
func slot_global_position(card_index: int) -> Vector2:
	return to_global(cards[card_index].resting_position)


## Where the fan is centered in this hand's own space. A caller that rotates the
## whole hand needs this to know what its node rotation is pivoting away from.
func fan_center() -> Vector2:
	var screen: Vector2 = _screen_size()
	var anchor_y: float = top_offset if position_at_top else screen.y - bottom_offset
	return Vector2(screen.x * 0.5 + edge_shift, anchor_y)


## Position all cards in a fan arc anchored to the player's screen edge.
func arrange_cards() -> void:
	if cards.is_empty():
		return

	var center: Vector2 = fan_center()
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


# ── Jumble (the J power) ───────────────────────────────────────────────────────
# The fan closes into one neat stack in the middle, then the cards are dealt
# back out of it in a scrambled order — the far right, the far left, then
# working inward — each swinging out on an arc toward the table. Hand cards lie
# face down, so which card went where is never shown; the shuffled faces go on
# while the hand is closed.

const JUMBLE_CLOSE_TIME := 0.3
## The beat the closed stack sits still before the first card leaves it.
const JUMBLE_HOLD_TIME := 0.1
const JUMBLE_OPEN_TIME := 0.34
## The gap between one card leaving the stack and the next.
const JUMBLE_OPEN_STAGGER := 0.08
## How far a card bows toward the table on its way back out, as a fraction of
## the distance it travels.
const JUMBLE_OPEN_ARC := 0.25
## Cards in the jumble draw above the rest of the hand's layer.
const JUMBLE_Z := 50
## Each card in the closed stack sits this far up the screen from the one under
## it, so it reads as a stack rather than one card — the same light as the deck.
const JUMBLE_STACK_STEP := Vector2(0.0, -2.5)


## Shuffle this hand's cards. Afterwards slot i holds the card that was in slot
## `new_order[i]`; the caller picks the order, so an online game jumbles the same
## hand the same way on every device. `on_slide` runs as the fan closes and as
## each card leaves the stack, `on_landed` as the stack closes and as each card
## lands back in the fan.
func jumble_cards(new_order: Array, on_landed: Callable = Callable(), on_slide: Callable = Callable()) -> void:
	var count := cards.size()
	if count < 2 or new_order.size() != count:
		return

	var card_data: Array[Dictionary] = []
	for card in cards:
		card.stop_state_tweens()
		card_data.append(card.to_card_data())

	# The card dealt out first sits on top of the stack, the last at the bottom.
	var deal_order: Array[int] = _jumble_deal_order(count)
	var stack_level: Array[int] = []
	stack_level.resize(count)
	for turn in range(count):
		stack_level[deal_order[turn]] = count - 1 - turn

	# Close: every card slides in to the middle, squared up. They keep the fan's
	# layering on the way in, so none jumps over a neighbour as they converge.
	var middle: Vector2 = to_global(fan_center())
	var stack_rotation: float = global_rotation + deg_to_rad(_stack_rotation_degrees())
	if on_slide.is_valid():
		on_slide.call()
	var close := create_tween().set_parallel(true)
	for slot in range(count):
		var card: PlayerCard = cards[slot]
		card.z_index = JUMBLE_Z + slot
		CardMotion.fly(close, card, middle + JUMBLE_STACK_STEP * stack_level[slot], stack_rotation, card_scale,
			JUMBLE_CLOSE_TIME)
		if card.front_texture != null and card.sprite.texture == card.front_texture:
			card.animate_flip(false, JUMBLE_CLOSE_TIME * 0.7)
	if on_landed.is_valid():
		CardMotion.cue_on_landing(close, on_landed, JUMBLE_CLOSE_TIME)
	await close.finished

	# Closed: layer the stack for dealing (identical backs, so it can't be seen)
	# and put the shuffled faces on.
	for slot in range(count):
		var data: Dictionary = card_data[new_order[slot]]
		cards[slot].setup_card(data["rank"], data["suit"], data["texture"])
		cards[slot].show_back()
		cards[slot].z_index = JUMBLE_Z + stack_level[slot]

	# Open: deal the cards back out one at a time, each bowing toward the table.
	# A card lifts above the stack as it leaves, taking its place in the fan's
	# layering, so the fan lands layered as it rests.
	var toward_table: Vector2 = global_transform.basis_xform(_toward_table())
	var open := create_tween().set_parallel(true)
	for turn in range(count):
		var slot: int = deal_order[turn]
		var card: PlayerCard = cards[slot]
		var delay: float = JUMBLE_HOLD_TIME + turn * JUMBLE_OPEN_STAGGER
		var travel: Vector2 = slot_global_position(slot) - card.global_position
		var arc: float = JUMBLE_OPEN_ARC * signf(travel.orthogonal().dot(toward_table))
		var leaving_z: int = JUMBLE_Z + count + slot
		open.tween_callback(func() -> void: card.z_index = leaving_z).set_delay(delay)
		if on_slide.is_valid():
			open.tween_callback(on_slide).set_delay(delay)
		CardMotion.fly(open, card, slot_global_position(slot), slot_global_rotation(slot), card_scale,
			JUMBLE_OPEN_TIME, arc).set_delay(delay)
		if on_landed.is_valid():
			open.tween_callback(on_landed).set_delay(delay + CardMotion.landing_delay(JUMBLE_OPEN_TIME))
	await open.finished
	arrange_cards()


## The order cards are dealt back out of the jumble stack: from the ends inward,
## alternating sides — far right, far left, next right, next left…
static func _jumble_deal_order(count: int) -> Array[int]:
	var order: Array[int] = []
	var left := 0
	var right := count - 1
	while left <= right:
		order.append(right)
		if left != right:
			order.append(left)
		left += 1
		right -= 1
	return order


## The jumble stack's angle in this hand's space: square, facing its player.
func _stack_rotation_degrees() -> float:
	return 180.0 if position_at_top else 0.0


## Toward the middle of the table, in this hand's space — the way a hovered card
## lifts.
func _toward_table() -> Vector2:
	return Vector2(0.0, 1.0 if position_at_top else -1.0)
