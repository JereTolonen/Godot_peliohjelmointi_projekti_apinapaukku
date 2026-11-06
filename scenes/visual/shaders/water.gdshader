shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Stylized water / frozen lake: gentle vertex waves, moving ripple highlights,
// fresnel tint towards the horizon.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.10, 0.45, 0.80, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.80, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform float wave_height = 0.12;
uniform float speed = 1.0;
uniform float frozen = 0.0;

varying vec3 v_world;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * speed * (1.0 - frozen);
	float h = sin(w.x * 0.5 + t) * 0.5 + sin(w.z * 0.7 + t * 1.3) * 0.35 + sin((w.x + w.z) * 1.3 + t * 2.1) * 0.15;
	VERTEX.y += h * wave_height * (1.0 - frozen);
	v_world = w;
}

void fragment() {
	float t = TIME * speed * (1.0 - frozen);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, fres * 0.8 + 0.1);
	vec2 p = v_world.xz * vec2(0.6, 1.4);
	float r1 = vnoise(p + vec2(t * 0.3, t * 0.1));
	float r2 = vnoise(p * 2.1 - vec2(t * 0.2, -t * 0.25));
	float lines = smoothstep(0.62, 0.68, r1 * 0.6 + r2 * 0.4) * (1.0 - smoothstep(0.68, 0.76, r1 * 0.6 + r2 * 0.4));
	// Frozen: cracks instead of ripples.
	float cracks = smoothstep(0.48, 0.5, vnoise(v_world.xz * 0.9)) * (1.0 - smoothstep(0.5, 0.52, vnoise(v_world.xz * 0.9)));
	col = mix(col, foam_color.rgb, mix(lines * 0.55, cracks * 0.5 + 0.08, frozen));
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.25, frozen);
	SPECULAR = 0.6;
}
