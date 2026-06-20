## PlayerHand — arranges PlayerCard children in a fan arc along a screen edge.
## @tool makes the layout visible and tweakable live in the Godot editor.
@tool
extends Node2D
class_name PlayerHand

# ── Layout — every property instantly updates the editor preview ──────────────
@export var card_spacing: float = 185.0:
	set(v): card_spacing = v; _refresh()
@export var arc_height: float = 70.0:
	set(v): arc_height = v; _refresh()
@export var bottom_offset: float = 210.0:
	set(v): bottom_offset = v; _refresh()
@export var top_offset: float = 210.0:
	set(v): top_offset = v; _refresh()
@export var max_rotation_degrees: float = 10.0:
	set(v): max_rotation_degrees = v; _refresh()
@export var card_scale: Vector2 = Vector2(1.18, 1.18):
	set(v): card_scale = v; _refresh()

# ── Identity ──────────────────────────────────────────────────────────────────
## Which player owns this hand (1 or 2). Stamped onto each card on deal.
@export var player_id: int = 1
## When true, cards are anchored to the top of the screen (Player 2).
@export var position_at_top: bool = false:
	set(v): position_at_top = v; _refresh()
## If true, deals a random hand in _ready() — handy for editor testing.
@export var auto_deal: bool = false

var cards: Array[PlayerCard] = []

func _ready() -> void:
	cards = _collect_cards()
	if auto_deal:
		deal_from_deck(CardDeck.create_shuffled_deck())
	arrange_cards()


## Consume cards from the front of deck and assign them to this hand.
func deal_from_deck(deck: Array[Dictionary]) -> void:
	for i in range(cards.size()):
		if deck.is_empty():
			return
		var d: Dictionary = deck.pop_front()
		cards[i].player_id = player_id
		cards[i].setup_card(d["rank"], d["suit"], d["texture"])


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
		card.rotation_degrees = (180.0 if position_at_top else 0.0) + t * max_rotation_degrees
		card.hover_lift_sign = -1.0 if position_at_top else 1.0
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
	if Engine.is_editor_hint():
		return Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
		)
	return get_viewport_rect().size


## Called by property setters — re-arranges cards once _ready() has run.
func _refresh() -> void:
	if is_node_ready():
		arrange_cards()
