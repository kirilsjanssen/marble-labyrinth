shader_type spatial;
// Level 05 channel / pool water for GL Compatibility (mobile). Mirrors the
// Blender v4 material: two scrolling samples of the Luma water/foam texture
// at different scale, angle and speed (never line up), foam from their
// brightness, Fresnel-lit turquoise body. UVs are metres with +U downstream;
// COLOR.r is the flow factor baked per water body (1 channel, 0.1 still pool).
// No fluid simulation: everything is UV offsets. The two phases are integrated
// on the CPU from the live hydraulic flux (Level05Visuals.set_flow), so water
// speeds up, slows and stops smoothly with the simulated flow.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 water_color : source_color = vec4(0.13, 0.71, 0.75, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.42, 0.50, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.0, 1.0);
// level05_water_params.json, layers.channel (metres / metres per second).
uniform float tile_a = 1.6;
uniform float speed_a = 0.45;
uniform float tile_b = 0.9;
uniform float speed_b = 0.75;
// Texture-space offsets along +U (downstream), advanced by the CPU.
uniform float phase_a = 0.0;
uniform float phase_b = 0.0;
// Live flow 0..1+: foam and glints fade out in a dry or stagnant channel.
uniform float flow = 1.0;
uniform float alpha = 0.86;
uniform float glow = 0.35;
// 0 on Low quality: one texture layer, no normal map.
uniform float detail = 1.0;

void fragment() {
	float factor = COLOR.r;
	vec2 uv_a = UV / tile_a - vec2(phase_a * factor, 0.0);
	float c = cos(0.35);
	float s = sin(0.35);
	vec2 uv_b = mat2(vec2(c, s), vec2(-s, c)) * (UV / tile_b) - vec2(phase_b * factor, 0.0);
	vec3 a = texture(foam_texture, uv_a).rgb;
	vec3 b = detail > 0.5 ? texture(foam_texture, uv_b).rgb : a;
	vec3 both = mix(a, b, 0.5);
	float lum = dot(both, vec3(0.299, 0.587, 0.114));
	float foam = smoothstep(0.62, 0.9, lum) * clamp(0.35 + flow * 0.65, 0.0, 1.0);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 body = mix(water_color.rgb, water_color.rgb * both * 1.6, 0.45);
	body = mix(body * deep_color.rgb / max(water_color.rgb, vec3(0.01)), body, 1.0 - facing * 0.6);
	ALBEDO = mix(body, foam_color.rgb, foam);
	ALPHA = mix(alpha, 1.0, foam);
	ROUGHNESS = mix(0.03, 0.45, foam);
	SPECULAR = 0.6;
	EMISSION = mix(body, foam_color.rgb, foam) * glow;
	if (detail > 0.5) {
		vec3 n = texture(normal_texture, uv_a * 1.3).xyz * 0.5 + texture(normal_texture, uv_b).xyz * 0.5;
		NORMAL_MAP = n;
		NORMAL_MAP_DEPTH = 0.6;
	}
}
