## BoardCard — a card displayed on the board (center draw slot or discard pile).
## Supports face-up/face-down state, a flip animation, and mouse hover signals.
extends Node2D
class_name BoardCard

signal hovered(card: Node2D)
signal hovered_off(card: Node2D)

@export var back_texture: Texture2D
@export var tilt_intensity: float = 14.0

var rank := ""
var suit := ""
var front_texture: Texture2D
var is_face_up := true
var can_drag := false
var is_shader_hovering := false
var hover_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	CardShader.apply(sprite, randf() * 1000.0)
	CardShader.set_inset(sprite, 0.02)
	_sync_shadow()

	var parent_node := get_parent()
	if parent_node.has_method("connect_card_signals"):
		parent_node.connect_card_signals(self)


func _process(_delta: float) -> void:
	if is_shader_hovering or (can_drag and get_global_mouse_position().distance_to(global_position) < 200.0):
		update_shader_tilt(get_global_mouse_position())
	elif !is_shader_hovering:
		CardShader.reset_tilt(sprite)


func _on_area_2d_mouse_entered() -> void:
	is_shader_hovering = true
	CardShader.set_hover(sprite, 1.0)
	CardShader.set_inset(sprite, 0.0)
	hovered.emit(self)


func _on_area_2d_mouse_exited() -> void:
	is_shader_hovering = false
	CardShader.set_hover(sprite, 0.0)
	CardShader.tween_inset(self, sprite, 0.02, 0.12)
	CardShader.reset_tilt(sprite)
	hovered_off.emit(self)


func setup_card(card_rank: String, card_suit: String, card_texture: Texture2D) -> void:
	rank = card_rank
	suit = card_suit
	front_texture = card_texture


func show_back() -> void:
	is_face_up = false
	sprite.texture = back_texture
	_sync_shadow()


func show_front() -> void:
	is_face_up = true
	sprite.texture = front_texture
	_sync_shadow()


func _sync_shadow() -> void:
	if shadow == null:
		return
	shadow.texture = sprite.texture
	shadow.scale = sprite.scale


func update_shader_tilt(global_mouse: Vector2) -> void:
	var local_mouse: Vector2 = sprite.to_local(global_mouse)
	CardShader.set_tilt(sprite, local_mouse, tilt_intensity)


func flip_to_front(enable_drag_after := true) -> void:
	can_drag = false
	show_back()

	var base_scale_x: float = sprite.scale.x
	var duration: float = 0.34
	var half_duration: float = duration * 0.5

	var flip_tween := create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK)
	flip_tween.set_ease(Tween.EASE_IN_OUT)
	flip_tween.tween_property(sprite, "scale:x", 0.08, half_duration)
	flip_tween.tween_callback(Callable(self, "show_front"))
	flip_tween.tween_property(sprite, "scale:x", base_scale_x, half_duration)
	await flip_tween.finished
	_sync_shadow()
	can_drag = enable_drag_after


func tween_hover_scale(target: Vector2, duration: float = 0.14) -> void:
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_BACK)
	hover_tween.set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", target, duration)


func get_card_name() -> String:
	return suit + " " + rank
