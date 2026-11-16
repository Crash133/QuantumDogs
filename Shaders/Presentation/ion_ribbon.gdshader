// Additive, unlit ribbon for weapon arcs/lines/shocks. UV.x runs along the
// sweep, UV.y across the width. `reveal` sweeps the ribbon in, `fade` fades it
// out; `edge_color` tints the outer edge (Saber violet plasma edge).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform float edge_width : hint_range(0.0, 1.0) = 0.2;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float tail_softness : hint_range(0.01, 1.0) = 0.6;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	// Head is brightest; tail softens toward the start of the sweep.
	float head = smoothstep(reveal - tail_softness, reveal, along) * step(along, reveal);
	float body = 1.0 - smoothstep(0.55, 1.0, across);
	float edge = smoothstep(1.0 - edge_width * 2.0, 1.0, across);
	vec3 color = mix(core_color.rgb, edge_color.rgb, edge);
	float alpha = head * body * opacity * (1.0 - fade);
	ALBEDO = color * alpha;
	ALPHA = alpha;
}
