## SwirlBackground — the animated swirl behind the title screen and the table,
## drawn at the resolution it actually shows.
##
## The swirl shader snaps its pattern to a grid of blocks set by pixel_filter,
## about 523 a side and stretched over the whole screen whatever its size, so
## each block covers several screen pixels. Drawn as a full-screen ColorRect,
## the shader still ran once for every screen pixel: over two million times a
## frame, eight or so per block, which made it the heaviest thing the game
## drew. Here it runs once per block into a small SubViewport, and that picture
## is stretched over the screen with nearest filtering: the same blocks for an
## eighth of the work.
##
## Set it up in the scene as before, with the swirl material and the tint on
## this node. It moves both onto the swirl it draws in the viewport, so the
## tinted swirl blends over black exactly as it did when drawn on screen.
class_name SwirlBackground
extends TextureRect

var viewport: SubViewport
## Simple Cards' backdrop, drawn instead of the swirl (see show_plain()).
var plain_color := Color.TRANSPARENT


func _ready() -> void:
	var swirl := ColorRect.new()
	swirl.material = material
	swirl.modulate = modulate
	swirl.self_modulate = self_modulate
	swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = null
	modulate = Color.WHITE
	self_modulate = Color.WHITE

	viewport = SubViewport.new()
	viewport.size = Vector2i.ONE * grid_size(swirl.material as ShaderMaterial)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	swirl.size = viewport.size
	viewport.add_child(swirl)
	add_child(viewport)

	texture = viewport.get_texture()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Blocks along each side of the swirl. The shader makes a block
## length(screen_size) / pixel_filter wide in UV, and screen_size is the size of
## the drawn texture: a ColorRect has none of its own, so it is 1 by 1, and the
## grid is pixel_filter / √2 blocks each way, square on any screen.
static func grid_size(swirl_material: ShaderMaterial) -> int:
	var pixel_filter: float = swirl_material.get_shader_parameter("pixel_filter")
	return maxi(1, roundi(pixel_filter / sqrt(2.0)))


## A plain backdrop of `color` in place of the swirl, which stops rendering.
func show_plain(color: Color) -> void:
	plain_color = color
	texture = null
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	queue_redraw()


func _draw() -> void:
	if texture == null and plain_color.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), plain_color)
