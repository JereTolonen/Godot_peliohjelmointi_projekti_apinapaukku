shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// Hehkuva laavameri: tumma jähmettynyt kuori, jonka halkeamista hohkaa virtaava laava.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform vec4 hot : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 warm : source_color = vec4(0.9, 0.15, 0.05, 1.0);
uniform vec4 crust : source_color = vec4(0.12, 0.06, 0.06, 1.0);
uniform float speed = 0.15;

varying vec3 v_world;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w.x * 0.4 + TIME * 0.6) * 0.06 + sin(w.z * 0.5 + TIME * 0.45) * 0.05;
	v_world = w;
}

void fragment() {
	vec2 p = v_world.xz * 0.35;
	float t = TIME * speed;
	float n1 = vnoise(p + vec2(t, t * 0.4));
	float n2 = vnoise(p * 2.3 - vec2(t * 0.7, -t * 0.3));
	float n = n1 * 0.65 + n2 * 0.35;
	float cracks = 1.0 - smoothstep(0.3, 0.42, n);
	float glow = smoothstep(0.55, 0.85, 1.0 - n);
	vec3 lava = mix(warm.rgb, hot.rgb, glow);
	vec3 col = mix(crust.rgb, lava, cracks);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + n * 6.0);
	ALBEDO = col;
	EMISSION = lava * cracks * 1.3 * pulse;
	ROUGHNESS = 0.9;
}
