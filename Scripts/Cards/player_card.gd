## PlayerCard — a card held in a player's hand.
## Adds drag-hover lift animation and resting layout state on top of Card.
extends Card
class_name PlayerCard

@export var drag_hover_lift: float = 45.0
@export var drag_hover_time: float = 0.12
@export var hover_scale_multiplier: float = 1.06
## Lift used for the calm "selected for swap" state (no glow/tilt/scale).
@export var selected_lift: float = 30.0

var resting_position: Vector2 = Vector2.ZERO
var resting_rotation_degrees: float = 0.0
var resting_scale: Vector2 = Vector2.ONE
var resting_z_index: int = 0
var is_drag_hovered: bool = false
var is_special_selected: bool = false
var drag_hover_tween: Tween
var scale_tween: Tween
var player_id: int = 1
## +1 lifts the card up-screen (bottom hand); -1 lifts it down-screen (top hand).
var hover_lift_sign: float = 1.0


func _init() -> void:
	tilt_intensity = 10.0


func _ready() -> void:
	super()
	add_to_group("player_cards")
	resting_position = position
	resting_scale = scale
	resting_z_index = z_index


func set_resting_position(new_position: Vector2) -> void:
	resting_position = new_position
	if not is_drag_hovered:
		position = resting_position


func set_resting_z_index(new_z_index: int) -> void:
	resting_z_index = new_z_index
	if not is_drag_hovered:
		z_index = resting_z_index


## Calm selection state for the 7-swap: the card sits slightly lifted and
## steady — no hover glow, tilt, or scale — while the player picks the target.
func set_special_selected(selected: bool) -> void:
	if is_special_selected == selected:
		return

	is_special_selected = selected

	# Clear any hover look the card had when it was clicked.
	is_drag_hovered = false
	CardShader.set_hover(sprite, 0.0)
	CardShader.reset_tilt(sprite)
	CardShader.set_inset(sprite, CardShader.RESTING_INSET)

	var target_position: Vector2 = resting_position
	if selected:
		target_position.y -= selected_lift * hover_lift_sign
		z_index = 100
	else:
		z_index = resting_z_index

	tween_toward(target_position, resting_scale)


func set_drag_hovered(hovered: bool) -> void:
	if is_drag_hovered == hovered:
		return

	is_drag_hovered = hovered

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
		CardShader.tween_inset(self, sprite, CardShader.RESTING_INSET, drag_hover_time)
		CardShader.set_hover(sprite, 0.0)
		CardShader.reset_tilt(sprite)

	tween_toward(target_position, target_scale)


func tween_toward(target_position: Vector2, target_scale: Vector2) -> void:
	if drag_hover_tween:
		drag_hover_tween.kill()
	if scale_tween:
		scale_tween.kill()

	drag_hover_tween = create_tween()
	drag_hover_tween.set_trans(Tween.TRANS_BACK)
	drag_hover_tween.set_ease(Tween.EASE_OUT)
	drag_hover_tween.tween_property(self, "position", target_position, drag_hover_time)

	scale_tween = create_tween()
	scale_tween.set_trans(Tween.TRANS_BACK)
	scale_tween.set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", target_scale, drag_hover_time)
