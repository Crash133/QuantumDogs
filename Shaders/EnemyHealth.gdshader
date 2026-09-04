shader_type spatial;
render_mode blend_mix, unshaded;

uniform bool use_billboard;
uniform float height;
uniform float alp;
uniform vec3 fill_color;
uniform sampler2D albedo_texture : source_color;

void vertex() {
    if (use_billboard) {
        vec3 scale;

        scale.x = length(MODEL_MATRIX[0].xyz);
        scale.y = length(MODEL_MATRIX[1].xyz);
        scale.z = length(MODEL_MATRIX[2].xyz);

        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
            vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0),
            vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0),
            vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0),
            MODEL_MATRIX[3]
        );
    }
}

void fragment() {
    vec4 tex = texture(albedo_texture, UV);

    ALBEDO = tex.rgb;
    ALPHA = tex.a;
	
	float h = 0.055 + height * (0.9 - 0.055);
	
	float x = UV.x;

	float zigzag = abs(fract(x * 7.0 + TIME * 0.4) - 0.5) * 2.0 - 0.5;

	float ripple = sin(x * 35.0 - TIME * 4.0) * 0.004;

	float wave = zigzag * 0.025 + ripple;

	float wave_height = h + wave;

    if (1.0 - UV.y < wave_height && length(tex.rgb) > 0.5) {
        ALBEDO = fill_color;
    }
	
	ALPHA *= alp;
}