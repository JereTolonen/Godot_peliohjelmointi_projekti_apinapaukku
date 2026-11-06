shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, blend_mix;
// Tähtäyspiste: valkoinen keskus, tumma reunus ja pehmeä varjo. Kääntyy aina kameraan
// päin ja piirretään kaiken päälle, jotta se erottuu mistä tahansa taustasta.

uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 border_color : source_color = vec4(0.16, 0.08, 0.05, 1.0);
// Pisteen säde neliön koosta (0..1, jätetään tilaa varjolle).
uniform float radius = 0.6;
// Reunuksen paksuus säteen osuutena.
uniform float border = 0.3;
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.45;
uniform vec2 shadow_offset = vec2(0.1, 0.14);

void vertex() {
	// Billboard, mutta mallin skaala säilyy (pisteet pienenevät lentoradan lopussa).
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

float disc(float d, float r) {
	float aa = fwidth(d) * 1.2;
	return 1.0 - smoothstep(r - aa, r + aa, d);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float shadow = (1.0 - smoothstep(radius * 0.85, radius * 1.3, length(p - shadow_offset))) * shadow_alpha;
	float outer = disc(d, radius);
	float inner = disc(d, radius * (1.0 - border));

	// Kootaan: varjo -> reunus -> täyttö.
	vec3 col = vec3(0.0);
	float a = shadow;
	col = mix(col, border_color.rgb, outer);
	a = mix(a, 1.0, outer);
	col = mix(col, fill_color.rgb, inner);

	ALBEDO = col;
	ALPHA = a;
}
