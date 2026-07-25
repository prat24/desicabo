## BoardCard — a card displayed on the board (center draw slot or discard pile).
## Adds mouse hover signals and a drag flag on top of Card.
extends Card
class_name BoardCard

signal hovered(card: BoardCard)
signal hovered_off(card: BoardCard)

var can_drag := false
var is_shader_hovering := false
var hover_tween: Tween


func _init() -> void:
	tilt_intensity = 14.0


func _process(_delta: float) -> void:
	if is_shader_hovering or (can_drag and get_global_mouse_position().distance_to(global_position) < 200.0):
		update_shader_tilt(get_global_mouse_position())
	else:
		CardShader.reset_tilt(sprite)


func _on_area_2d_mouse_entered() -> void:
	is_shader_hovering = true
	CardShader.set_hover(sprite, 1.0)
	CardShader.set_inset(sprite, 0.0)
	hovered.emit(self)


func _on_area_2d_mouse_exited() -> void:
	is_shader_hovering = false
	CardShader.set_hover(sprite, 0.0)
	CardShader.tween_inset(self, sprite, CardShader.RESTING_INSET, 0.12)
	CardShader.reset_tilt(sprite)
	hovered_off.emit(self)


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
