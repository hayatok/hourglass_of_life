shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 timber_color : source_color = vec4(0.67,0.45,0.29,1.0);
uniform float board_width = 0.18;
uniform float board_length = 1.65;
uniform bool floor_boards = false;
uniform bool vertical_grain = false;
varying vec3 timber_position;

float random_line(float key) { return fract(sin(key*127.1+9.2)*43758.5453); }

void vertex() { timber_position = VERTEX; }

void fragment() {
	vec2 p = vertical_grain ? timber_position.xy : timber_position.xz;
	float row = floor(p.x/board_width);
	float shift = random_line(row)*board_length;
	float footprint = max(fwidth(p.x),fwidth(p.y));
	float grain_filter = clamp(1.0-footprint*90.0,0.0,1.0);
	float fine_filter = clamp(1.0-footprint*230.0,0.0,1.0);
	float grain = (sin(p.x*390.0 + sin(p.y*7.0+row)*1.8)*0.5+0.5)*grain_filter;
	float fine_grain = (sin(p.x*1130.0+p.y*3.1)*0.5+0.5)*fine_filter;
	float tint = 0.95 + (random_line(row)-0.5)*0.13 + grain*0.035 + fine_grain*0.015;
	float joint = 0.0;
	if (floor_boards) {
		float across = min(fract(p.x/board_width),1.0-fract(p.x/board_width))*board_width;
		float along = min(fract((p.y+shift)/board_length),1.0-fract((p.y+shift)/board_length))*board_length;
		float edge_filter = max(0.0022,footprint*0.6);
		joint = (1.0-smoothstep(0.0007,edge_filter,min(across,along)))*min(1.0,0.003/max(footprint,0.003));
	}
	ALBEDO = timber_color.rgb * mix(tint,0.66,joint);
	ROUGHNESS = 0.82;
}
