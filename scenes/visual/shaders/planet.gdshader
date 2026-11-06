shader_type spatial;
render_mode diffuse_burley;
// Banded cartoon planet with a glowing rim. Used for the gravity wells and the
// decorative planets of the space levels.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform vec4 rim : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float bands = 6.0;
uniform float seed = 0.0;
uniform float glow = 0.35;
uniform float spin = 0.05;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 p = normalize(v_obj);
	float lon = atan(p.z, p.x) + TIME * spin;
	float b = p.y * bands + vnoise(vec2(lon * 2.0 + seed, p.y * 3.0)) * 1.2;
	float band = floor(b);
	float r = hash21(vec2(band, seed));
	vec3 col = mix(color.rgb * 0.7, color.rgb * 1.25, r);
	col = mix(col, vec3(1.0), smoothstep(0.82, 0.95, vnoise(vec2(lon * 3.0, p.y * 9.0) + seed)) * 0.25);
	// Craters / spots.
	float spots = smoothstep(0.75, 0.8, vnoise(vec2(lon * 4.0 + seed * 2.0, p.y * 6.0)));
	col = mix(col, color.rgb * 0.5, spots * 0.5);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = col;
	EMISSION = rim.rgb * fres * 1.2 + col * glow;
	ROUGHNESS = 0.8;
}
