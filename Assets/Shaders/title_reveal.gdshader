// The title on the Simple Cards pile. The title starts in the background's own
// colour, so only the cards thrown down behind it reveal it. Navy cards are as
// dark as the title, so the title also gets a white outline. That outline is
// drawn only where a card is behind it: over the bare background the title
// stays hidden, the same reveal the watercolour cards give. The fill is left
// alone.
shader_type canvas_item;

// The solid backdrop's colour, as set on its node: no colour conversion, so it
// compares straight against what is on screen.
uniform vec4 background_color;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	// The label draws the white outline pass and the dark fill pass separately,
	// so the colour says which one this is.
	float is_outline = step(0.5, COLOR.r);
	vec3 behind = texture(screen_texture, SCREEN_UV).rgb;
	// Navy cards have no red at all, while the backdrop has a little, so any
	// card pixel lands well clear of this band.
	float over_card = smoothstep(0.015, 0.035, distance(behind, background_color.rgb));
	COLOR.a *= mix(1.0, over_card, is_outline);
}
