shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 cloth_color : source_color = vec4(0.53,0.66,0.63,1.0);
uniform vec4 stripe_color : source_color = vec4(0.89,0.85,0.74,1.0);
uniform float stripe_amount = 0.0;
varying vec3 cloth_position;

void vertex() { cloth_position = VERTEX; }

void fragment() {
	vec2 p = cloth_position.xz;
	float weave_filter = clamp(1.0-max(fwidth(p.x),fwidth(p.y))*180.0,0.0,1.0);
	float weave = sin(p.x*740.0)*sin(p.y*740.0)*0.018*weave_filter;
	float stripe = 1.0-smoothstep(0.015,0.022,abs(fract(p.y*5.0)-0.5));
	ALBEDO = mix(cloth_color.rgb,stripe_color.rgb,stripe*stripe_amount)*(0.99+weave);
	ROUGHNESS = 0.96;
}
