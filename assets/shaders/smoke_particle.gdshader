// soft smoke/dust puff for CPUParticles3D billboards. tint is a uniform
// since the particle colour ramp's RGB doesn't reliably reach blended
// particle materials; each puff fades in/out over its own life.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D puff : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.8, 0.8, 0.8, 0.8);
uniform float fade_in = 0.12;
uniform float fade_out = 0.45;
// >1 makes each puff more solid (smoke grenades need to block sight).
uniform float density = 1.0;

varying float life;

void vertex() {
	// billboard, keeping the particle's own scale and spin.
	mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	m = m * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
	life = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec4 t = texture(puff, UV);
	float a = smoothstep(0.0, fade_in, life) * (1.0 - smoothstep(1.0 - fade_out, 1.0, life));
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = min(t.a * density, 1.0) * tint.a * a;
}
