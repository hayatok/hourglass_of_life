shader_type spatial;
render_mode specular_disabled;

uniform sampler2D base_palette : source_color, filter_linear_mipmap, repeat_disable;
uniform ivec3 hair_cells = ivec3(-1);
uniform float hair_age : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = texture(base_palette, UV).rgb;
	// glTF flips V when exporting Blender's palette UVs. Match the source swatch index.
	int cell = int(floor(UV.x * 8.0)) + 8 * int(floor((1.0 - UV.y) * 8.0));
	if (cell == hair_cells.x || cell == hair_cells.y || cell == hair_cells.z) {
		ALBEDO = mix(ALBEDO, vec3(0.48, 0.50, 0.52), hair_age);
	}
	ROUGHNESS = 1.0;
}

void light() {
	float facing = dot(normalize(NORMAL), normalize(LIGHT));
	float band = mix(0.32, 1.0, smoothstep(0.16, 0.24, facing));
	// LIGHT_COLOR includes PI. Keep the authored palette stable with actual world lights/shadows.
	// https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
}
