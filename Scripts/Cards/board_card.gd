## BoardCard — a card displayed on the board (center draw slot or discard pile).
## Adds mouse hover signals and a drag flag on top of Card.
extends Card
class_name BoardCard

signal hovered(card: BoardCard)
signal hovered_off(card: BoardCard)

var can_drag := false
## The pointer is inside this card's Area2D — geometry alone. Whether that
## reads as a hover is decided in update_hover().
var is_pointer_inside := false
var is_hovered := false
var hover_tween: Tween


func _init() -> void:
	tilt_intensity = 14.0


func _process(_delta: float) -> void:
	update_hover()

	var pointer_near_card: bool = can_drag \
		and get_global_mouse_position().distance_to(global_position) < 200.0
	if TapGesture.is_pointer_hovering() and (is_hovered or pointer_near_card):
		update_shader_tilt(get_global_mouse_position())
	else:
		CardShader.reset_tilt(sprite)


## A hover needs the pointer inside the card *and* actually pointing at it. A
## lifted finger leaves the pointer parked where it was and the Area2D never
## reports it leaving, so without this the card lights up on its own — which is
## what made the discard pile look hovered at the start of a turn, the moment
## it became takeable again under a finger that was no longer there.
func update_hover() -> void:
	var hovering: bool = is_pointer_inside and TapGesture.is_pointer_hovering()
	if hovering == is_hovered:
		return

	is_hovered = hovering
	if hovering:
		HoverSfx.play_hover()
		CardShader.set_hover(sprite, 1.0)
		CardShader.set_inset(sprite, 0.0)
		hovered.emit(self)
	else:
		CardShader.set_hover(sprite, 0.0)
		CardShader.tween_inset(self, sprite, CardShader.RESTING_INSET, 0.12)
		CardShader.reset_tilt(sprite)
		hovered_off.emit(self)


## Drop the hover outright: a disabled Area2D never reports the pointer
## leaving, so a card that stops being interactive has to be told.
func clear_hover() -> void:
	is_pointer_inside = false
	is_hovered = false
	CardShader.set_hover(sprite, 0.0)
	CardShader.set_inset(sprite, CardShader.RESTING_INSET)
	CardShader.reset_tilt(sprite)


func _on_area_2d_mouse_entered() -> void:
	is_pointer_inside = true


func _on_area_2d_mouse_exited() -> void:
	is_pointer_inside = false


func flip_to_front(enable_drag_after := true) -> void:
	can_drag = false
	show_back()
	await animate_flip(true, 0.34)
	can_drag = enable_drag_after


func tween_hover_scale(target: Vector2, duration: float = 0.14) -> void:
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_BACK)
	hover_tween.set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", target, duration)
