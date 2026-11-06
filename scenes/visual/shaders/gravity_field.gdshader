shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Gravity field: soft disc with rings that flow inwards (pull) or outwards (push).

uniform vec4 tint : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float direction = 1.0;
uniform float intensity = 0.35;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float radius = length(MODEL_MATRIX[0].xyz) * 0.5;
	float d = clamp(length(v_world.xy - center.xy) / radius, 0.0, 1.0);
	float rings = fract(d * 4.0 + TIME * 0.45 * direction);
	float ring_line = smoothstep(0.0, 0.12, rings) * (1.0 - smoothstep(0.12, 0.3, rings));
	float fade = (1.0 - smoothstep(0.75, 1.0, d)) * smoothstep(0.08, 0.3, d);
	float rim = smoothstep(0.88, 0.97, d) * (1.0 - smoothstep(0.97, 1.0, d));
	ALBEDO = tint.rgb * (ring_line * fade * 0.8 + rim * 0.9 + 0.12 * fade) * intensity;
}
