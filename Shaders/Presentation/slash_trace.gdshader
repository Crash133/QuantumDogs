// Additive layered slash: white-hot band near the outer edge, weapon-colour
// body, thin streak lines that flow along the sweep. UV.x runs tail (0) to head
// (1), UV.y inner (0) to outer (1). `reveal` sweeps the head in; `fade` eats
// the slash from its tail while dimming it (driven by the hitbox decay curve).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.85, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.87, 0.1, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float streaks = 5.0;
uniform float flow_speed = 1.5;
uniform float brightness = 1.8;
// Crescents (projectiles) taper at both tips instead of at the tail only.
uniform bool symmetric = false;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float along = UV.x;
	float across = UV.y;
	if (along > reveal) { discard; }
	float t = along / max(reveal, 0.001);                // 0 tail .. 1 head
	float tail_cut = fade * reveal;
	float alive = smoothstep(tail_cut, tail_cut + 0.2, along);
	float along_shape = symmetric ? sin(3.14159 * clamp(along, 0.0, 1.0)) : pow(max(t, 0.0001), 1.4) * alive;
	// Across: soft inner body, hot band near the rim, crisp rim falloff.
	float body = smoothstep(0.0, 0.85, across) * (1.0 - smoothstep(0.96, 1.0, across));
	float hot = smoothstep(0.62, 0.86, across) * (1.0 - smoothstep(0.93, 0.99, across));
	// Flowing streak lines with a little per-line jitter along the sweep.
	float lane = across * streaks;
	float jitter = hash(floor(lane)) * 6.2831;
	float line = pow(max(abs(sin(lane * 3.14159)), 0.0001), 18.0) * (0.55 + 0.45 * sin(along * 14.0 - TIME * flow_speed * 6.0 + jitter));
	vec3 color = mix(edge_color.rgb, core_color.rgb, clamp(hot * 1.3, 0.0, 1.0));
	color += core_color.rgb * line * 0.6;
	float alpha = clamp(body * 0.7 + hot + line * 0.5, 0.0, 1.0) * along_shape * opacity * (1.0 - fade * fade);
	// A flat ribbon seen edge-on stacks every streak into one bright smear; fade
	// it out as it turns away from the camera.
	vec3 face_cross = cross(dFdx(VERTEX), dFdy(VERTEX));
	float facing = abs(dot(face_cross, VERTEX)) / max(length(face_cross) * length(VERTEX), 0.000001);
	alpha *= smoothstep(0.1, 0.45, facing);
	ALBEDO = color * alpha * brightness;
	ALPHA = alpha;
}
