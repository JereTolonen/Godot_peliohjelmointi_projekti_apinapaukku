shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// Stylized gravity well: glowing dashed border, slow energy stripes and a faint,
// light wave that travels from the center out to the border.

group_uniforms colors;
uniform vec4 core_color : source_color = vec4(0.18, 0.08, 0.45, 1.0);
uniform vec4 border_color : source_color = vec4(0.35, 0.95, 1.0, 1.0);
uniform vec4 wave_color : source_color = vec4(0.85, 0.8, 1.0, 1.0);

group_uniforms border;
// Thickness of the border band (fraction of the sphere as seen from the camera).
uniform float border_width : hint_range(0.0, 1.0) = 0.28;
// How soft the inner edge of the border is. Small = crisp, cartoon-like.
uniform float border_softness : hint_range(0.001, 0.3) = 0.04;
uniform float border_alpha : hint_range(0.0, 1.0) = 0.95;
uniform float border_glow : hint_range(0.0, 4.0) = 1.5;
// The border is broken into dashes that run around the sphere.
uniform float dash_count : hint_range(2.0, 80.0) = 24.0;
// Portion of each dash period that is drawn (the rest is a gap).
uniform float dash_fill : hint_range(0.1, 0.95) = 0.55;
// Full rotations of the dashes per second (negative = other direction).
uniform float dash_speed : hint_range(-2.0, 2.0) = 0.05;

group_uniforms body;
uniform float core_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float stripe_count : hint_range(1.0, 60.0) = 14.0;
uniform float stripe_speed : hint_range(-10.0, 10.0) = 1.5;
uniform float stripe_intensity : hint_range(0.0, 1.0) = 0.25;

group_uniforms wave;
// Seconds for the wave to travel from the center to the border.
uniform float wave_period : hint_range(0.5, 20.0) = 3.5;
// Thickness of the wave front. The trail behind it is wider.
uniform float wave_width : hint_range(0.02, 0.5) = 0.12;
// How visible the wave is. Low = almost transparent.
uniform float wave_alpha : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float rim = 1.0 - ndv;

	// Dashed border.
	float threshold = 1.0 - border_width;
	float border = smoothstep(threshold, threshold + border_softness, rim);
	float hairline = smoothstep(0.92, 0.97, rim);

	float angle = atan(n.y, n.x) / 6.28318 + 0.5;
	float dash_pos = fract((angle + TIME * dash_speed) * dash_count);
	float dash = smoothstep(0.0, 0.04, dash_pos) * (1.0 - smoothstep(dash_fill - 0.04, dash_fill, dash_pos));
	border *= dash;
	hairline *= dash;

	// Slowly moving energy stripes on the body.
	float stripes = 0.5 + 0.5 * sin(UV.y * stripe_count * 6.28318 - TIME * stripe_speed);
	vec3 body = core_color.rgb * (1.0 + stripes * stripe_intensity);

	// Wave: r is 0 at the center of the sphere and 1 at its outline.
	float r = sqrt(max(1.0 - ndv * ndv, 0.0));
	float t = fract(TIME / wave_period);
	float w = r < t ? wave_width * 2.5 : wave_width; // soft trail behind the front
	float d = (r - t) / w;
	float wave = exp(-d * d);
	wave *= smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.7, 1.0, t)); // fades in at the center, out at the border
	body = mix(body, wave_color.rgb, wave * 0.8);

	vec3 edge = border_color.rgb * border_glow + vec3(hairline * 0.5);

	ALBEDO = mix(body, edge, border);
	float body_alpha = core_alpha + wave * wave_alpha;
	ALPHA = clamp(mix(body_alpha, border_alpha, border), 0.0, 1.0);
}
