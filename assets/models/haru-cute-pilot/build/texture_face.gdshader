shader_type spatial;
render_mode specular_disabled;
uniform sampler2D base_palette : source_color, filter_linear_mipmap, repeat_disable;
uniform float blink : hint_range(0.0,1.0) = 0.0;
uniform float smile : hint_range(0.0,1.0) = 0.0;
uniform float tired : hint_range(0.0,1.0) = 0.0;
uniform vec2 eye_l;
uniform vec2 eye_l_x;
uniform vec2 eye_l_y;
uniform vec2 eye_l_skin;
uniform vec2 eye_r;
uniform vec2 eye_r_x;
uniform vec2 eye_r_y;
uniform vec2 eye_r_skin;
uniform vec2 mouth_center;
uniform vec2 mouth_x;
uniform vec2 mouth_y;
uniform vec2 mouth_skin;
uniform vec4 original_mouth[64];
uniform vec4 smile_mouth[64];
uniform vec4 tired_mouth[64];
uniform ivec3 mouth_segment_counts;
float segment_distance(vec2 p,vec2 a,vec2 b) {
 vec2 d=b-a;return length(p-a-d*clamp(dot(p-a,d)/max(dot(d,d),.000000001),0.0,1.0));
}
vec2 local_uv(vec2 uv, vec2 center, vec2 axis_x, vec2 axis_y) {
	vec2 d = uv-center;
	float det = axis_x.x*axis_y.y-axis_x.y*axis_y.x;
	return vec2(d.x*axis_y.y-d.y*axis_y.x,axis_x.x*d.y-axis_x.y*d.x)/det;
}
vec3 eye_color(vec3 color,vec2 uv,vec2 center,vec2 axis_x,vec2 axis_y,vec2 skin_uv) {
	vec2 p = local_uv(uv,center,axis_x,axis_y);
	float closure = max(max(blink,.48*tired),.12*smile);
	float full_mask = 1.0-smoothstep(.93,1.09,length(p));
	if (closure>.001 && full_mask>.001) {
		float height = max(.035,1.0-closure);
		vec2 compressed = vec2(p.x,p.y/height);
		vec2 source_uv = center+axis_x*compressed.x+axis_y*compressed.y;
		float visible_eye = (1.0-smoothstep(.87,1.02,length(compressed)))*(1.0-smoothstep(.94,.99,closure));
		vec3 skin = texture(base_palette,skin_uv).rgb;
		vec3 warped = mix(skin,texture(base_palette,source_uv).rgb,visible_eye);
		float curve = -.08+.22*p.x*p.x;
		float line = (1.0-smoothstep(.025,.055,abs(p.y-curve)))*(1.0-smoothstep(.72,.95,abs(p.x)));
		warped = mix(warped,vec3(.045,.022,.012),line*smoothstep(.65,.95,closure));
		color = mix(color,warped,full_mask);
	}
	float cheek = 1.0-smoothstep(.25,1.0,length((p-vec2(0.0,-1.55))/vec2(1.0,.42)));
	color = mix(color,color*vec3(1.0,.78,.75),cheek*smile*.30);
	float undereye = 1.0-smoothstep(.2,1.0,length((p-vec2(0.0,-1.10))/vec2(.9,.22)));
	color = mix(color,color*vec3(.78,.73,.84),undereye*tired*.35);
	return color;
}
void fragment() {
	vec3 color = texture(base_palette,UV).rgb;
	color = eye_color(color,UV,eye_l,eye_l_x,eye_l_y,eye_l_skin);
	color = eye_color(color,UV,eye_r,eye_r_x,eye_r_y,eye_r_skin);
	float mouth_amount = max(smile,tired);
	vec2 p = local_uv(UV,mouth_center,mouth_x,mouth_y);
	if (mouth_amount>.001) {
		float old_dist=1.0;float smile_dist=1.0;float tired_dist=1.0;
		for (int i=0;i<64;i++) {
		 if (i>=max(max(mouth_segment_counts.x,mouth_segment_counts.y),mouth_segment_counts.z)) break;
		 if (i<mouth_segment_counts.x) old_dist=min(old_dist,segment_distance(UV,original_mouth[i].xy,original_mouth[i].zw));
		 if (i<mouth_segment_counts.y) smile_dist=min(smile_dist,segment_distance(UV,smile_mouth[i].xy,smile_mouth[i].zw));
		 if (i<mouth_segment_counts.z) tired_dist=min(tired_dist,segment_distance(UV,tired_mouth[i].xy,tired_mouth[i].zw));
		}
		float clear_mask=1.0-smoothstep(.0009,.0020,old_dist);
		vec3 skin=texture(base_palette,eye_l_skin).rgb;
		color=mix(color,skin,clear_mask*mouth_amount);
		float lip_dist=mix(smile_dist,tired_dist,tired);
		float line=1.0-smoothstep(.00016,.00038,lip_dist);
		color=mix(color,vec3(.12,.045,.025),line*mouth_amount);
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
void light() {
	float facing = dot(normalize(NORMAL),normalize(LIGHT));
	float band = mix(.32,1.0,smoothstep(.16,.24,facing));
	DIFFUSE_LIGHT += band*ATTENUATION*LIGHT_COLOR/PI;
}
