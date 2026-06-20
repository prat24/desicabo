## Shared pseudo-3D card shader helpers (Balatro / JokerPoker style).
class_name CardShader
extends RefCounted

const MATERIAL := preload("res://Assets/Shaders/card_fov_material.tres")

static func apply(sprite: Sprite2D, rand_seed: float = 0.0) -> ShaderMaterial:
	var mat := MATERIAL.duplicate() as ShaderMaterial
	mat.set_shader_parameter("rand_seed", rand_seed)
	mat.set_shader_parameter("rand_trans_power", 0.0)
	sprite.material = mat
	return mat


static func get_material(sprite: Sprite2D) -> ShaderMaterial:
	return sprite.material as ShaderMaterial


static func card_half_size(sprite: Sprite2D) -> Vector2:
	var rect := sprite.get_rect()
	return rect.size * sprite.scale * 0.5


static func set_tilt(sprite: Sprite2D, local_pos: Vector2, intensity: float = 12.0) -> void:
	var mat := get_material(sprite)
	if mat == null:
		return

	var half_size := card_half_size(sprite)
	if half_size.x <= 0.0 or half_size.y <= 0.0:
		return

	mat.set_shader_parameter("y_rot", (local_pos.y / half_size.y) * -intensity)
	mat.set_shader_parameter("x_rot", (local_pos.x / half_size.x) * intensity)


static func reset_tilt(sprite: Sprite2D) -> void:
	var mat := get_material(sprite)
	if mat == null:
		return
	mat.set_shader_parameter("x_rot", 0.0)
	mat.set_shader_parameter("y_rot", 0.0)


static func set_hover(sprite: Sprite2D, amount: float) -> void:
	var mat := get_material(sprite)
	if mat == null:
		return
	mat.set_shader_parameter("hovering", amount)


static func set_inset(sprite: Sprite2D, inset: float) -> void:
	var mat := get_material(sprite)
	if mat == null:
		return
	mat.set_shader_parameter("inset", inset)


static func tween_inset(owner: Node, sprite: Sprite2D, target: float, duration: float = 0.12) -> void:
	var mat := get_material(sprite)
	if mat == null:
		return
	var tween := owner.create_tween()
	tween.tween_method(
		func(value: float) -> void: set_inset(sprite, value),
		mat.get_shader_parameter("inset") as float,
		target,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
