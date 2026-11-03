shader_type spatial;
render_mode specular_disabled;

uniform bool paving = true;
uniform vec4 main_color : source_color = vec4(0.74, 0.69, 0.58, 1.0);
varying vec3 world_position;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	if (paving) {
		float row = floor(p.y/0.34);
		vec2 q = vec2(p.x/0.52+mod(row,2.0)*0.5,p.y/0.34);
		vec2 edges = min(fract(q),1.0-fract(q));
		vec2 aa = max(fwidth(q),vec2(0.001));
		vec2 interior = smoothstep(vec2(0.018),vec2(0.018)+aa*1.1,edges);
		float stone = interior.x*interior.y;
		float shade = mix(0.87,1.07,hash21(floor(q)));
		ALBEDO = main_color.rgb*mix(0.65,shade,stone);
	} else {
		float patch = smooth_noise(p*0.55);
		float blade = smoothstep(0.78,0.93,hash21(floor(p*25.0)));
		ALBEDO = main_color.rgb*(0.91+patch*0.12+blade*0.06);
	}
	ROUGHNESS = 0.95;
}
