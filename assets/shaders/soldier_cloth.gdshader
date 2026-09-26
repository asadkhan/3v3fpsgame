// Turns the flat-coloured soldier atlas into worn field kit: scanned fabric
// weave and bumps, a team camouflage on the uniform, and dust and grime that
// build up towards the boots. Skin and near-black gear keep their own colour.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D fabric_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D camo_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 camo_a : source_color = vec3(0.34, 0.33, 0.22);
uniform vec3 camo_b : source_color = vec3(0.22, 0.2, 0.14);
uniform vec3 camo_c : source_color = vec3(0.45, 0.4, 0.3);
uniform float camo_strength = 0.75;
uniform float fabric_scale = 7.0;
uniform float camo_scale = 1.1;
uniform float dirt = 0.35;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

vec4 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void fragment() {
	vec3 base = texture(atlas, UV).rgb;
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
	// Skin: warm and bright, red clearly over blue.
	float skin = smoothstep(0.08, 0.16, base.r - base.b) * smoothstep(0.45, 0.6, base.r) * step(base.g, base.r);
	// Cloth: the khaki and olive of the uniform and webbing (not black kit).
	float cloth = (1.0 - skin) * smoothstep(0.07, 0.15, luma);

	vec3 fabric = triplanar(fabric_albedo, local_pos * fabric_scale, local_normal).rgb;
	float weave = dot(fabric, vec3(0.333)) / 0.55;

	// Camouflage: three tones from two noise lookups, laid over the cloth.
	float n1 = triplanar(camo_noise, local_pos * camo_scale, local_normal).r;
	float n2 = triplanar(camo_noise, local_pos * camo_scale * 2.3 + 7.1, local_normal).r;
	vec3 camo = mix(camo_a, camo_b, smoothstep(0.52, 0.58, n1));
	camo = mix(camo, camo_c, smoothstep(0.6, 0.66, n2) * (1.0 - smoothstep(0.52, 0.58, n1)));
	vec3 kit = mix(base, camo * (luma / 0.4 + 0.45) * 0.8, camo_strength * cloth);

	// Weave everywhere but skin; dust towards the ground; grime in patches.
	kit *= mix(1.0, clamp(weave, 0.65, 1.3), 1.0 - skin * 0.85);
	float low = 1.0 - smoothstep(0.1, 0.75, local_pos.y);
	vec3 dust = vec3(0.55, 0.49, 0.4);
	kit = mix(kit, dust * (0.6 + luma), low * dirt * (1.0 - skin));
	kit *= mix(1.0, 0.8, smoothstep(0.55, 0.75, n2) * 0.5 * (1.0 - skin));

	// Sun-weathered, grimy skin rather than clean pink.
	kit = mix(kit, base * vec3(0.78, 0.6, 0.48), skin);

	ALBEDO = kit;
	ROUGHNESS = mix(0.92, 0.78, skin);
	SPECULAR = mix(0.25, 0.3, skin);
	vec3 bump = triplanar(fabric_normal, local_pos * fabric_scale, local_normal).rgb;
	NORMAL_MAP = mix(bump, vec3(0.5, 0.5, 1.0), 0.35 + skin * 0.65);
	NORMAL_MAP_DEPTH = 1.0;
}
