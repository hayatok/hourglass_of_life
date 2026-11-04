shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 tile_color : source_color = vec4(0.77,0.83,0.78,1.0);
uniform float tile_width = 0.24;
varying vec3 tile_position;

void vertex() { tile_position = VERTEX; }

void fragment() {
	vec2 p = tile_position.xz/tile_width;
	vec2 edge = min(fract(p),1.0-fract(p))*tile_width;
	float grout = 1.0-smoothstep(0.001,0.004,min(edge.x,edge.y));
	float variation = fract(sin(dot(floor(p),vec2(12.9898,78.233)))*43758.5453);
	ALBEDO = mix(tile_color.rgb*(0.96+variation*0.055),vec3(0.76,0.76,0.69),grout*0.65);
	ROUGHNESS = 0.86;
}
