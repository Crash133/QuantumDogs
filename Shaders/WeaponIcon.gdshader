shader_type canvas_item;

// Recolors a black silhouette icon (only its alpha is kept) and can add an
// outline, so a blacked-out "locked" weapon still reads against a dark HUD.
// The outline is the widest alpha found on two rings around the pixel, then the
// body is blended over it, so diagonal edges stay smooth instead of stair-stepping.
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 outline : source_color = vec4(0.0);
uniform float outline_size = 4.0;

const int RING_TAPS = 16;
const float TAU_STEP = 6.28318530718 / float(RING_TAPS);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 px = TEXTURE_PIXEL_SIZE * outline_size;
	float edge = 0.0;
	for (int i = 0; i < RING_TAPS; i++) {
		vec2 dir = vec2(cos(float(i) * TAU_STEP), sin(float(i) * TAU_STEP));
		edge = max(edge, texture(TEXTURE, UV + dir * px).a);
		edge = max(edge, texture(TEXTURE, UV + dir * px * 0.5).a);
	}
	float body_a = a * tint.a;
	float rim_a = edge * outline.a;
	float out_a = body_a + rim_a * (1.0 - body_a);
	vec3 rgb = (tint.rgb * body_a + outline.rgb * rim_a * (1.0 - body_a)) / max(out_a, 0.0001);
	COLOR = vec4(rgb, out_a);
}
