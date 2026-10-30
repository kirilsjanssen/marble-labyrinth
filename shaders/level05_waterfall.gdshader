shader_type spatial;
// Level 05 waterfall layer (GL Compatibility). mode 0 = translucent body
// (Luma waterfall streaks RGBA), mode 1 = faster foam sheet (derived foam
// mask), mode 2 = churned spray / mist (soft noise, alpha). UVs are metres:
// U across the lip, V grows down the fall, so streaks scroll down at the
// speeds from level05_water_params.json (layers.fall_body / fall_foam).
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D layer_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform int mode = 0;
uniform float tile_u = 0.6;
uniform float tile_v = 1.2;
uniform float speed_a = 1.7;
uniform float speed_b = 2.4;
uniform vec4 water_color : source_color = vec4(0.13, 0.71, 0.75, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float opacity = 1.0;
uniform float glow = 0.6;
uniform float flow_scale = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float t = TIME * flow_scale;
	if (mode == 2) {
		float n = noise(UV * 7.0 + vec2(0.0, -t * 0.8)) * 0.6 + noise(UV * 15.0 + vec2(t * 0.3, -t * 1.4)) * 0.4;
		ALBEDO = foam_color.rgb * COLOR.rgb;
		ALPHA = smoothstep(0.3, 0.75, n) * opacity;
		EMISSION = foam_color.rgb * glow * 0.6;
		ROUGHNESS = 0.6;
	} else {
		vec2 uv_a = vec2(UV.x / tile_u, UV.y / tile_v - t * speed_a / tile_v);
		vec2 uv_b = vec2(UV.x / (tile_u * 1.6) + 0.37, UV.y / (tile_v * 1.5) - t * speed_b / (tile_v * 1.5));
		vec4 a = texture(layer_texture, uv_a);
		vec4 b = texture(layer_texture, uv_b);
		if (mode == 0) {
			vec3 color = mix(mix(a.rgb, b.rgb, 0.5), water_color.rgb, 0.25);
			ALBEDO = color;
			ALPHA = clamp(max(a.a, b.a) * 0.95, 0.0, 1.0) * opacity;
			EMISSION = color * glow;
			ROUGHNESS = 0.12;
		} else {
			float mask = clamp(max(a.r, b.r) * 1.25, 0.0, 1.0);
			ALBEDO = foam_color.rgb;
			ALPHA = mask * opacity;
			EMISSION = foam_color.rgb * glow;
			ROUGHNESS = 0.45;
		}
	}
}
