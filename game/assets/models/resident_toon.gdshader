shader_type spatial;
render_mode specular_disabled;

uniform sampler2D base_palette : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	ALBEDO = texture(base_palette, UV).rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float facing = dot(normalize(NORMAL), normalize(LIGHT));
	float band = mix(0.32, 1.0, smoothstep(0.16, 0.24, facing));
	// LIGHT_COLOR includes PI. Keep the authored palette stable with actual world lights/shadows.
	// https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
}
