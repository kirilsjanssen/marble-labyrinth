shader_type spatial;
// One cylindrical backdrop layer. Unshaded and fogged towards the sky colour
// so distance reads as atmospheric depth. The horizontal coordinate is mirror
// repeated, so the panorama has no visible seam all the way around.
render_mode unshaded, cull_front, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D layer_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 haze_color : source_color = vec4(0.70, 0.80, 0.90, 1.0);
uniform float haze = 0.3;
uniform float repeats = 3.0;
uniform float u_offset = 0.0;
// Procedural ridge silhouette used whenever no generated texture is bound.
uniform float ridge_height = 0.55;
uniform float ridge_roughness = 0.35;
uniform float ridge_seed = 1.0;
uniform float snow_line = 0.0;
// Below this V the textured layer turns solid (ground under keyed silhouettes),
// so no gap in the cut-out ever reveals a farther layer through the slope.
uniform float solid_below = 2.0;
uniform vec4 ground_color : source_color = vec4(0.13, 0.20, 0.14, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float ridge(float u) {
	float total = 0.0;
	float amplitude = 0.5;
	float frequency = 3.0;
	for (int octave = 0; octave < 4; octave++) {
		float x = u * frequency + ridge_seed * 13.7;
		float i = floor(x);
		float f = fract(x);
		float a = hash(i);
		float b = hash(i + 1.0);
		// Sharp peaks: abs-shaped blend reads as Alpine summits.
		total += mix(a, b, f * f * (3.0 - 2.0 * f)) * amplitude;
		amplitude *= ridge_roughness + 0.3;
		frequency *= 2.2;
	}
	return total;
}

void fragment() {
	float u = fract((UV.x + u_offset) * repeats * 0.5) * 2.0;
	u = u > 1.0 ? 2.0 - u : u;
	vec4 color;
	if (use_texture) {
		// V is clamped: the sampler repeats, and a wrapped top row would draw a
		// hairline of the layer's opaque bottom across the sky.
		color = texture(layer_texture, vec2(u, clamp(UV.y, 0.004, 0.996)));
		if (UV.y > solid_below) {
			float blend = smoothstep(solid_below, solid_below + 0.06, UV.y);
			color = vec4(mix(color.rgb * color.a + ground_color.rgb * (1.0 - color.a), ground_color.rgb, blend), 1.0);
		}
	} else {
		float height = 1.0 - UV.y;
		float profile = ridge(u) * ridge_height + 0.08;
		float inside = 1.0 - smoothstep(profile - 0.006, profile + 0.006, height);
		float snow = snow_line > 0.0 ? smoothstep(profile - snow_line, profile - snow_line * 0.4, height) : 0.0;
		vec3 rock = mix(tint.rgb * 0.75, tint.rgb, height / max(profile, 0.001));
		color = vec4(mix(rock, vec3(0.94, 0.96, 1.0), snow * inside), inside);
		color.rgb *= 1.0;
	}
	vec3 hazed = mix(color.rgb * tint.rgb, haze_color.rgb, haze * (0.6 + 0.4 * UV.y));
	ALBEDO = use_texture ? hazed : mix(color.rgb, haze_color.rgb, haze * (0.6 + 0.4 * UV.y));
	ALPHA = color.a * tint.a;
}
