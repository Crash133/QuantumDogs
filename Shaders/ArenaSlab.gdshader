// Arena floor slabs: dark fractured blue stone with thin lights along some slab
// edges (blue/violet/amber), bright glints at lit corners and faint glowing
// cracks. Vertex data written by ArenaGroundTile:
//   COLOR   slab base tint
//   UV      0..1 across the slab top (x west->east, y north->south)
//   UV2     slab size in metres (x, y)
//   CUSTOM0 edge light mask (north, east, south, west) 0/1
//   CUSTOM1 light colour rgb, a = slab light strength
shader_type spatial;
render_mode cull_disabled;

uniform float line_falloff = 42.0;
uniform float crack_scale = 1.6;
uniform float light_energy = 2.6;
uniform float crack_glow = 0.18;

varying vec4 edge_mask;
varying vec4 light_data;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 slab_size;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// x: distance to the nearest cell point, y: distance to the second nearest,
// z: a stable random value per cell.
vec3 voronoi(vec2 p) {
	vec2 cell = floor(p);
	vec2 frac = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(cell + g);
			float d = length(g + o - frac);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = fract(dot(cell + g, vec2(12.9898, 78.233)));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2, id);
}

void vertex() {
	edge_mask = CUSTOM0;
	light_data = CUSTOM1;
	slab_size = UV2;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = world_normal.y > 0.7;
	vec3 stone = COLOR.rgb;
	vec3 vor = voronoi(world_pos.xz * crack_scale);
	vec3 fine = voronoi(world_pos.xz * crack_scale * 3.1 + 17.0);
	float crack = 1.0 - smoothstep(0.0, 0.06, vor.y - vor.x);
	float fine_crack = 1.0 - smoothstep(0.0, 0.05, fine.y - fine.x);
	stone *= 0.72 + 0.55 * vor.z;
	stone = mix(stone, stone * 0.3, clamp(crack * 0.85 + fine_crack * 0.45, 0.0, 1.0));
	vec3 emission = vec3(0.0);
	if (is_top) {
		vec4 d = vec4(UV.y * slab_size.y, (1.0 - UV.x) * slab_size.x, (1.0 - UV.y) * slab_size.y, UV.x * slab_size.x);
		float line = 0.0;
		for (int i = 0; i < 4; i++) {
			line += edge_mask[i] * exp(-d[i] * line_falloff);
		}
		// Corner glints where two lit edges meet.
		float glint = 0.0;
		for (int i = 0; i < 4; i++) {
			int j = (i + 1) % 4;
			glint += edge_mask[i] * edge_mask[j] * exp(-(d[i] + d[j]) * 28.0);
		}
		vec3 light = light_data.rgb * light_data.a;
		emission += light * (line * light_energy + glint * light_energy * 2.2);
		emission += light * crack * crack_glow * 0.5;
		// Lit edges also wash the nearby stone.
		stone += light * line * 0.08;
	} else {
		stone *= 0.45;
	}
	ALBEDO = stone;
	EMISSION = emission;
	ROUGHNESS = is_top ? 0.5 + 0.2 * vor.z : 0.8;
	METALLIC = 0.35;
	SPECULAR = 0.55;
}
