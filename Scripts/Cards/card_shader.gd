## Shared pseudo-3D card shader helpers (Balatro / JokerPoker style).
class_name CardShader
extends RefCounted

const MATERIAL := preload("res://Assets/Shaders/card_fov_material.tres")
## Inset every card rests at; hover/drag states animate it to 0.
const RESTING_INSET := 0.02

## The pointer position last sent to the shaders (see update_pointer()).
static var _pointer_screen_pos := Vector2.INF

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


## How big the shader draws a flat card relative to the sprite's own size. It
## grows the quad to leave room for tilting and then maps the texture in with
## perspective, so the untilted card comes out a touch smaller than the plain
## sprite would be: (1 + t·(1 − inset)) / (1 + t), with t = tan(fov / 2).
## Anything drawn plainly that has to line up with a shaded card — the deck
## pile's stack — scales itself by this.
static func flat_card_scale(sprite: Sprite2D) -> float:
	var mat := get_material(sprite)
	if mat == null:
		return 1.0
	var fov: float = mat.get_shader_parameter("fov")
	var inset: float = mat.get_shader_parameter("inset")
	var t: float = tan(deg_to_rad(fov) * 0.5)
	return (1.0 + t * (1.0 - inset)) / (1.0 + t)


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


## Hand the pointer's screen position to every card's hover tilt, which reads
## it from one global uniform. Called each frame by whichever scene is up, it
## only touches the uniform when the pointer has actually moved.
static func update_pointer(viewport: Viewport) -> void:
	var pointer_position := viewport.get_mouse_position()
	if pointer_position == _pointer_screen_pos:
		return
	_pointer_screen_pos = pointer_position
	RenderingServer.global_shader_parameter_set("mouse_screen_pos", pointer_position)
