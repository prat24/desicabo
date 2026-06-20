## PlayerCard — a card held in a player's hand.
## Handles face state, drag-hover lift animation, and resting position.
extends Node2D
class_name PlayerCard

@export var back_texture: Texture2D
@export var drag_hover_lift: float = 45.0
@export var drag_hover_time: float = 0.12
@export var hover_scale_multiplier: float = 1.06
@export var tilt_intensity: float = 10.0

var rank: String = ""
var suit: String = ""
var front_texture: Texture2D
var is_face_down: bool = true
var resting_position: Vector2 = Vector2.ZERO
var resting_rotation_degrees: float = 0.0
var resting_scale: Vector2 = Vector2.ONE
var resting_z_index: int = 0
var is_drag_hovered: bool = false
var is_special_selected: bool = false
var drag_hover_tween: Tween
var scale_tween: Tween
var player_id: int = 1
var hover_lift_sign: float = 1.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	add_to_group("player_cards")
	resting_position = position
	resting_scale = scale
	resting_z_index = z_index
	CardShader.apply(sprite, randf() * 1000.0)
	CardShader.set_inset(sprite, 0.02)
	_sync_shadow()
	show_back()


func _sync_shadow() -> void:
	if shadow == null:
		return
	shadow.texture = sprite.texture
	shadow.scale = sprite.scale


func setup_card(card_rank: String, card_suit: String, card_texture: Texture2D) -> void:
	rank = card_rank
	suit = card_suit
	front_texture = card_texture
	show_back()


func show_back() -> void:
	is_face_down = true
	sprite.texture = back_texture
	_sync_shadow()


func show_front() -> void:
	is_face_down = false
	sprite.texture = front_texture
	_sync_shadow()


func animate_flip_to_back(duration: float = 0.24) -> void:
	if front_texture == null:
		show_back()
		return

	var half_duration: float = maxf(0.01, duration * 0.5)
	var base_scale: Vector2 = sprite.scale

	var flip_tween: Tween = create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK)
	flip_tween.set_ease(Tween.EASE_IN_OUT)
	flip_tween.tween_property(sprite, "scale:x", 0.08, half_duration)
	flip_tween.tween_callback(Callable(self, "show_back"))
	flip_tween.tween_property(sprite, "scale:x", base_scale.x, half_duration)
	await flip_tween.finished
	_sync_shadow()


func animate_flip_to_front(duration: float = 0.24) -> void:
	if front_texture == null:
		show_front()
		return

	var half_duration: float = maxf(0.01, duration * 0.5)
	var base_scale: Vector2 = sprite.scale

	var flip_tween: Tween = create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK)
	flip_tween.set_ease(Tween.EASE_IN_OUT)
	flip_tween.tween_property(sprite, "scale:x", 0.08, half_duration)
	flip_tween.tween_callback(Callable(self, "show_front"))
	flip_tween.tween_property(sprite, "scale:x", base_scale.x, half_duration)
	await flip_tween.finished
	_sync_shadow()


func get_card_name() -> String:
	return suit + " " + rank


func set_resting_position(new_position: Vector2) -> void:
	resting_position = new_position
	if !is_drag_hovered:
		position = resting_position


func set_resting_z_index(new_z_index: int) -> void:
	resting_z_index = new_z_index
	if !is_drag_hovered:
		z_index = resting_z_index


func set_special_selected(selected: bool) -> void:
	is_special_selected = selected
	set_drag_hovered(selected)


func set_drag_hovered(hovered: bool) -> void:
	if is_drag_hovered == hovered:
		return

	is_drag_hovered = hovered

	if drag_hover_tween:
		drag_hover_tween.kill()
	if scale_tween:
		scale_tween.kill()

	var target_position: Vector2 = resting_position
	var target_scale: Vector2 = resting_scale

	if hovered:
		target_position.y -= drag_hover_lift * hover_lift_sign
		target_scale = resting_scale * hover_scale_multiplier
		z_index = 100
		CardShader.set_inset(sprite, 0.0)
		CardShader.set_hover(sprite, 0.6)
	else:
		z_index = resting_z_index
		CardShader.tween_inset(self, sprite, 0.02, drag_hover_time)
		CardShader.set_hover(sprite, 0.0)
		CardShader.reset_tilt(sprite)

	drag_hover_tween = create_tween()
	drag_hover_tween.set_trans(Tween.TRANS_BACK)
	drag_hover_tween.set_ease(Tween.EASE_OUT)
	drag_hover_tween.tween_property(self, "position", target_position, drag_hover_time)

	scale_tween = create_tween()
	scale_tween.set_trans(Tween.TRANS_BACK)
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", target_scale, drag_hover_time)


func update_shader_tilt(global_mouse: Vector2) -> void:
	var local_mouse: Vector2 = sprite.to_local(global_mouse)
	CardShader.set_tilt(sprite, local_mouse, tilt_intensity)


func get_collision_rect() -> Rect2:
	return get_sprite_global_rect(sprite)


func get_sprite_global_rect(card_sprite: Sprite2D) -> Rect2:
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
