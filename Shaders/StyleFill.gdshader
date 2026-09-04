shader_type canvas_item;

uniform vec4 unfilled_color : source_color = vec4(1.0, 0.5, 0.0, 1.0); 
uniform float fill_perc;
uniform float alpha_mult;

uniform float i;
uniform float m;

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);

    float f = fill_perc * (m - i) + i;

    if (length(original_color.rgb) > 0.5 && 1.0 - UV.y > f) {
        COLOR = unfilled_color;
        COLOR.a = original_color.a;
    } else {
        COLOR = original_color;
    }

    COLOR.a *= alpha_mult;
}