## Card — shared behavior for any playing card on screen:
## face state, textures, flip animation, shader tilt, and shadow sync.
## PlayerCard and BoardCard both extend this.
class_name Card
extends Node2D

## Card textures are 420x570, three times the 140x190 card size the layout is
## built around, so they stay sharp in the biggest hands. The card scenes draw
## their sprites at this scale (a card at scale 1 is 280x380 on screen); a bare
## Sprite2D showing a card texture multiplies it in too. Keep this in step with
## the Sprite2D/Shadow scale in player_card.tscn and board_card.tscn.
const SPRITE_SCALE := 2.0 / 3.0
## How thin a flip squashes the card, as a fraction of its width.
const FLIP_SQUASH := 0.04

@export var tilt_intensity: float = 12.0

## Taken from the player's card look (see [CardArt]) when the card is ready.
var back_texture: Texture2D

var rank := ""
var suit := ""
var front_texture: Texture2D
## The sprite's own scale, taken once before anything animates it. A flip
## squashes the live scale to almost nothing and back, so any sizing that needs
## to divide the sprite's built-in scale out has to use this instead — reading
## the live value mid-flip asks for a card twenty-six times too big.
var sprite_rest_scale: Vector2 = Vector2.ONE
## Where the shadow sits while the card lies on the table. A flight drifts the
## shadow out from here as the card lifts (see CardMotion) and back on landing.
var shadow_rest_position: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	sprite_rest_scale = sprite.scale
	if shadow:
		shadow_rest_position = shadow.position
	back_texture = CardArt.back()
	CardShader.apply(sprite, randf() * 1000.0)
	CardShader.set_inset(sprite, CardShader.RESTING_INSET)
	show_back()


func setup_card(card_rank: String, card_suit: String, card_texture: Texture2D) -> void:
	rank = card_rank
	suit = card_suit
	front_texture = card_texture
	show_back()


func show_back() -> void:
	sprite.texture = back_texture
	_sync_shadow()


func show_front() -> void:
	sprite.texture = front_texture
	_sync_shadow()


func _sync_shadow() -> void:
	if shadow == null:
		return
	shadow.texture = sprite.texture
	shadow.scale = sprite.scale


## Flip by squashing on X and swapping the face at the midpoint.
func animate_flip(to_front: bool, duration: float = 0.24) -> void:
	if front_texture == null:
		if to_front:
			show_front()
		else:
			show_back()
		return

	var half_duration: float = maxf(0.01, duration * 0.5)
	var base_scale_x: float = sprite_rest_scale.x

	var flip_tween: Tween = create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK)
	flip_tween.set_ease(Tween.EASE_IN_OUT)
	flip_tween.tween_property(sprite, "scale:x", base_scale_x * FLIP_SQUASH, half_duration)
	# The whoosh swells into its peak, so it starts early enough for that peak
	# to land edge-on, where the card turns fastest and its face swaps.
	flip_tween.parallel().tween_callback(FlipSfx.play_flip) \
		.set_delay(maxf(0.0, half_duration - CardSfx.FLIP_PEAK_TIME))
	flip_tween.tween_callback(show_front if to_front else show_back)
	flip_tween.tween_property(sprite, "scale:x", base_scale_x, half_duration)
	await flip_tween.finished
	_sync_shadow()


func update_shader_tilt(global_mouse: Vector2) -> void:
	CardShader.set_tilt(sprite, sprite.to_local(global_mouse), tilt_intensity)


func to_card_data() -> Dictionary:
	return {"rank": rank, "suit": suit, "texture": front_texture}


## Axis-aligned bounding box of the card sprite in global coordinates.
func get_global_rect() -> Rect2:
	return sprite_global_rect(sprite)


static func sprite_global_rect(card_sprite: Sprite2D) -> Rect2:
	var local_rect: Rect2 = card_sprite.get_rect()
	var corners: Array[Vector2] = [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y)
	]
	var first_corner: Vector2 = card_sprite.global_transform * corners[0]
	var min_position: Vector2 = first_corner
	var max_position: Vector2 = first_corner

	for corner_index in range(1, corners.size()):
		var global_corner: Vector2 = card_sprite.global_transform * corners[corner_index]
		min_position = min_position.min(global_corner)
		max_position = max_position.max(global_corner)

	return Rect2(min_position, max_position - min_position)
