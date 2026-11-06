## DeckPile — the draw pile. The sprite itself is the top card's back; under it
## sit the edges of the cards beneath, each a few pixels lower and a shade
## darker, so the pile reads as a real stack with some thickness to it. The
## stack thins as cards are dealt and drawn, and the pile is gone once it is
## empty.
##
## The layers step straight down the *screen* whichever way the pile is turned
## (it lies sideways on three- and four-player tables), so the stack is lit the
## same way as every card's shadow.
class_name DeckPile
extends Sprite2D

const FULL_DECK := 52
## Edge layers under the top card for a full deck; each stands for a few cards.
const MAX_LAYERS := 5
## How far each layer sits below the one above it, in screen pixels. Kept small
## so the stack is a clean sliver of edges, not a tower.
const LAYER_STEP := Vector2(0.0, 3.0)
## Brightness of the first layer under the top card and of the bottom one.
## Darker going down, so each edge reads as its own card.
const TOP_LAYER_SHADE := 0.78
const BOTTOM_LAYER_SHADE := 0.58
## The pile's drop shadow, matching the one under every card (see the Shadow
## node in board_card.tscn): offset in screen pixels, and its opacity.
const SHADOW_OFFSET := Vector2(5.0, 9.0)
const SHADOW_ALPHA := 0.32

var cards_left := FULL_DECK
## Bottom layer first, so the deeper cards draw first.
var layers: Array[Sprite2D] = []
var shadow: Sprite2D


func _ready() -> void:
	shadow = _make_layer(Color(0.0, 0.0, 0.0, SHADOW_ALPHA))
	for i in range(MAX_LAYERS):
		var depth: float = float(MAX_LAYERS - i) / MAX_LAYERS
		var shade: float = lerpf(TOP_LAYER_SHADE, BOTTOM_LAYER_SHADE, depth)
		layers.append(_make_layer(Color(shade, shade, shade)))
	texture_changed.connect(_sync_texture)
	set_notify_transform(true)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_refresh()


## How many cards are left to draw. The stack shows one edge layer per few
## cards, and the pile disappears when it reaches zero.
func set_cards_left(count: int) -> void:
	cards_left = maxi(count, 0)
	_refresh()


## Re-fit the layers to the top card. Call after changing the pile's shader
## settings (its inset sets how big the top card is drawn).
func refresh() -> void:
	_refresh()


## A copy of the card back drawn behind the top card. Drawn plainly, not with
## the pile's card shader: that shader writes its colour outright, so a layer
## sharing it would lose its tint — the shadow came out as a bright white card
## jutting from under the pile. _refresh() sizes it to the shaded top card.
func _make_layer(tint: Color) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.texture = texture
	layer.texture_filter = texture_filter
	layer.show_behind_parent = true
	layer.self_modulate = tint
	add_child(layer)
	return layer


func _sync_texture() -> void:
	shadow.texture = texture
	for layer in layers:
		layer.texture = texture


func _refresh() -> void:
	visible = cards_left > 0
	if layers.is_empty():
		return

	var shown: int = ceili(float(cards_left) / FULL_DECK * MAX_LAYERS)
	# The top card is drawn through the card shader, a hair smaller than the
	# plain sprite; the layers match it so no edge peeks out at the sides.
	var layer_scale := Vector2.ONE * CardShader.flat_card_scale(self)
	# Offsets are given on screen; the layers live in the pile's own space,
	# which is scaled and may be turned sideways.
	var to_local := global_transform.affine_inverse()
	var step: Vector2 = to_local.basis_xform(LAYER_STEP)
	for i in range(MAX_LAYERS):
		# Layer i is (MAX_LAYERS - i) cards down from the top.
		var depth: int = MAX_LAYERS - i
		layers[i].visible = depth <= shown
		layers[i].position = step * depth
		layers[i].scale = layer_scale
	shadow.position = step * shown + to_local.basis_xform(SHADOW_OFFSET)
	shadow.scale = layer_scale
