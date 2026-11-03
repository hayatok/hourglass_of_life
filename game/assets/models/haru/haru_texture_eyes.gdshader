shader_type spatial;
render_mode specular_disabled;

// Calibrated by each resident's UV layout. No palette-cell remapping or mouth edits.
uniform sampler2D base_palette : source_color, filter_linear_mipmap, repeat_disable;
uniform ivec3 hair_cells = ivec3(-1);
uniform float blink : hint_range(0.0,1.0) = 0.0;
uniform float tired_eyes : hint_range(0.0,1.0) = 0.0;
uniform vec2 eye_l;
uniform vec2 eye_l_x;
uniform vec2 eye_l_y;
uniform vec2 eye_l_skin;
uniform vec2 eye_r;
uniform vec2 eye_r_x;
uniform vec2 eye_r_y;
uniform vec2 eye_r_skin;
// Existing two-chart compression is the default. Additional UV islands and
// non-resampling eyelid coverage are enabled only by an explicit layout.
uniform bool eyelid_occlusion=false;
uniform int extra_eye_count=0;
uniform vec2 extra_eye_center[4];
uniform vec2 extra_eye_x[4];
uniform vec2 extra_eye_y[4];
uniform vec2 extra_eye_skin[4];

vec2 eye_local(vec2 uv,vec2 center,vec2 axis_x,vec2 axis_y) {
	vec2 d=uv-center;
	float det=axis_x.x*axis_y.y-axis_x.y*axis_y.x;
	return vec2(d.x*axis_y.y-d.y*axis_y.x,axis_x.x*d.y-axis_x.y*d.x)/det;
}

vec3 eye_color(vec3 color,vec2 uv,vec2 center,vec2 axis_x,vec2 axis_y,vec2 skin_uv) {
	vec2 p=eye_local(uv,center,axis_x,axis_y);
	float closure=max(blink,.48*tired_eyes);
	float full_mask=1.0-smoothstep(.93,1.09,length(p));
	if (closure>.001 && full_mask>.001) {
		float height=max(.035,1.0-closure);
		vec2 compressed=vec2(p.x,p.y/height);
		vec2 source_uv=center+axis_x*compressed.x+axis_y*compressed.y;
		float visible_eye=(1.0-smoothstep(.87,1.02,length(compressed)))*(1.0-smoothstep(.94,.99,closure));
		vec3 skin=texture(base_palette,skin_uv).rgb;
		vec3 warped=mix(skin,texture(base_palette,source_uv).rgb,visible_eye);
		float curve=-.08+.22*p.x*p.x;
		float line=(1.0-smoothstep(.025,.055,abs(p.y-curve)))*(1.0-smoothstep(.72,.95,abs(p.x)));
		warped=mix(warped,vec3(.045,.022,.012),line*smoothstep(.65,.95,closure));
		color=mix(color,warped,full_mask);
	}
	float undereye=1.0-smoothstep(.2,1.0,length((p-vec2(0.0,-1.10))/vec2(.9,.22)));
	return mix(color,color*vec3(.78,.73,.84),undereye*tired_eyes*.35);
}

vec3 eye_occlusion_color(vec3 color,vec2 uv,vec2 center,vec2 axis_x,vec2 axis_y,vec2 skin_uv) {
	vec2 p=eye_local(uv,center,axis_x,axis_y);
	float closure=max(blink,.48*tired_eyes);
	float full_mask=1.0-smoothstep(.93,1.09,length(p));
	if (closure>.001 && full_mask>.001) {
		float cutoff=.70-1.4*closure;
		float keep=(1.0-smoothstep(cutoff-.04,cutoff+.04,p.y))*(1.0-smoothstep(.94,.99,closure));
		vec3 skin=texture(base_palette,skin_uv).rgb;
		vec3 warped=mix(skin,color,keep);
		float curve=mix(cutoff,-.08+.22*p.x*p.x,smoothstep(.65,.95,closure));
		float line=(1.0-smoothstep(.025,.055,abs(p.y-curve)))*(1.0-smoothstep(.72,.95,abs(p.x)));
		warped=mix(warped,vec3(.045,.022,.012),line*smoothstep(.05,.20,closure));
		color=mix(color,warped,full_mask);
	}
	float undereye=1.0-smoothstep(.2,1.0,length((p-vec2(0.0,-1.10))/vec2(.9,.22)));
	return mix(color,color*vec3(.78,.73,.84),undereye*tired_eyes*.35);
}

void fragment() {
	vec3 color=texture(base_palette,UV).rgb;
	if (eyelid_occlusion) {
		color=eye_occlusion_color(color,UV,eye_l,eye_l_x,eye_l_y,eye_l_skin);
		color=eye_occlusion_color(color,UV,eye_r,eye_r_x,eye_r_y,eye_r_skin);
	} else {
		color=eye_color(color,UV,eye_l,eye_l_x,eye_l_y,eye_l_skin);
		color=eye_color(color,UV,eye_r,eye_r_x,eye_r_y,eye_r_skin);
	}
	for (int i=0;i<4;i++) {
		if (i>=extra_eye_count) break;
		if (eyelid_occlusion) color=eye_occlusion_color(color,UV,extra_eye_center[i],extra_eye_x[i],extra_eye_y[i],extra_eye_skin[i]);
		else color=eye_color(color,UV,extra_eye_center[i],extra_eye_x[i],extra_eye_y[i],extra_eye_skin[i]);
	}
	ALBEDO=color;
	ROUGHNESS=1.0;
}

void light() {
	float facing=dot(normalize(NORMAL),normalize(LIGHT));
	float band=mix(.32,1.0,smoothstep(.16,.24,facing));
	DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;
}
