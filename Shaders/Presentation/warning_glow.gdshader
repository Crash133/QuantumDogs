// Restrained warm warning accent: a camera-facing disc with a role-shaped
// mask. `pulse` = 0 gives the steady reduced-motion version (no flashing).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.18, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.2;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float pulse : hint_range(0.0, 1.0) = 0.35;
uniform float pulse_hz = 3.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
// 0 = round lamp (common), 1 = lens ring (drone), 2 = chevron crown (Elite).
uniform int shape = 0;

void vertex() {
	// Billboard: keep the disc facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask;
	if (shape == 1) {
		mask = smoothstep(0.42, 0.55, r) * (1.0 - smoothstep(0.7, 0.85, r)) + (1.0 - smoothstep(0.0, 0.25, r)) * 0.6;
	} else if (shape == 2) {
		float chevron = 1.0 - smoothstep(0.08, 0.16, abs(p.y + abs(p.x) * 0.9 - 0.15));
		mask = chevron * (1.0 - smoothstep(0.7, 0.95, r)) + (1.0 - smoothstep(0.0, 0.3, r)) * 0.5;
	} else {
		mask = 1.0 - smoothstep(0.0, 0.9, r);
		mask = mask * mask;
	}
	float wave = 1.0 - pulse * (0.5 + 0.5 * sin(TIME * pulse_hz * 6.2831));
	float alpha = clamp(mask * opacity * wave * (1.0 - fade), 0.0, 1.0);
	ALBEDO = color.rgb * intensity * alpha;
	ALPHA = alpha;
}
