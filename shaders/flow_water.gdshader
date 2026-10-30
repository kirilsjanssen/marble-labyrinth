shader_type spatial;
// Mobile-friendly flowing water for GL Compatibility. Two procedural detail
// layers scroll at different speeds; the slower one is offset by the view
// direction (surface parallax). Flow speed and direction come from the
// hydraulic simulation through `flow`, never from a fixed animation.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.52, 0.82);
uniform vec4 shallow_color : source_color = vec4(0.42, 0.78, 0.90, 0.70);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
// xy = surface flow in UV units per second (scaled by the simulated flux).
uniform vec2 flow = vec2(0.0, 0.0);
uniform float layer_two_ratio = 0.55;
uniform float uv_scale = 1.6;
uniform float foam_amount = 0.35;
uniform float edge_foam = 0.12;
uniform float parallax_depth = 0.06;
uniform float wave_height = 0.0;
// 1.0 turns the surface into a falling sheet: streaks stretch along UV.y.
uniform float waterfall = 0.0;
uniform float flow_phase_a = 0.0;
uniform float flow_phase_b = 0.0;
// Optional generated water/foam detail (Luma); procedural noise otherwise.
uniform sampler2D detail_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_detail = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.13 + 7.1) * 0.3 + noise(p * 4.7 + 3.3) * 0.1;
}

void vertex() {
	// Gentle swell only where wave_height > 0 (open pools); flumes stay flat so
	// the visible surface never separates from the physical water level.
	if (wave_height > 0.0) {
		VERTEX.y += (sin(VERTEX.x * 3.1 + TIME * 1.7) + cos(VERTEX.z * 2.7 + TIME * 1.3)) * wave_height;
	}
}

void fragment() {
	vec2 base_uv = UV * uv_scale;
	vec3 view_tangent = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	// Phases are integrated on the CPU from the live flux, so slowing water
	// decelerates smoothly instead of snapping the texture backwards.
	vec2 uv_a = base_uv + vec2(flow_phase_a) * normalize(flow + vec2(0.0001));
	vec2 uv_b = base_uv * 1.7 + vec2(flow_phase_b) * normalize(flow + vec2(0.0001)) + view_tangent.xz * parallax_depth;
	if (waterfall > 0.5) {
		uv_a = vec2(base_uv.x * 3.0, base_uv.y * 0.35 + flow_phase_a);
		uv_b = vec2(base_uv.x * 5.0 + 1.3, base_uv.y * 0.6 + flow_phase_b);
	}
	float layer_a = fbm(uv_a * 2.0);
	float layer_b = fbm(uv_b * 3.1);
	vec3 detail = vec3(0.0);
	if (use_detail) {
		vec3 detail_a = texture(detail_texture, uv_a * 0.35).rgb;
		vec3 detail_b = texture(detail_texture, uv_b * 0.27 + vec2(0.37, 0.11)).rgb;
		detail = mix(detail_a, detail_b, 0.45);
		float luminance = dot(detail, vec3(0.299, 0.587, 0.114));
		layer_a = mix(layer_a, luminance, 0.65);
		layer_b = mix(layer_b, dot(detail_b, vec3(0.333)), 0.5);
	}
	float ripple = layer_a * 0.6 + layer_b * 0.4;

	float speed = length(flow);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge_mask = 1.0 - smoothstep(0.0, edge_foam, edge);
	float foam = smoothstep(0.62 - foam_amount * 0.25 - min(speed, 1.5) * 0.08, 0.86, ripple) * (0.45 + min(speed, 2.0) * 0.35);
	foam = max(foam, edge_mask * (0.25 + foam_amount));
	if (waterfall > 0.5) {
		foam = smoothstep(0.35, 0.75, layer_a) * 0.9 + 0.1;
	}

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, ripple);
	if (use_detail) {
		water = mix(water, detail * vec3(0.85, 1.0, 1.05), 0.45);
	}
	ALBEDO = mix(water, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ALPHA = mix(mix(deep_color.a, shallow_color.a, ripple), foam_color.a, clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.45, foam);
	METALLIC = 0.0;
	SPECULAR = 0.65;
	// Cheap normal perturbation from the two layers gives moving glints.
	NORMAL = normalize(NORMAL + vec3(layer_a - 0.5, 0.0, layer_b - 0.5) * 0.35 * (1.0 - waterfall));
	EMISSION = foam_color.rgb * foam * 0.08;
}
