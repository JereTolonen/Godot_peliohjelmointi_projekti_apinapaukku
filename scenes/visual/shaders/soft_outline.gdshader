shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Pehmeä sarjakuvamainen ääriviiva ("inverted hull"). Käytetään material_overlay-
// materiaalina apinoille ja palikoille, jotta ammuttavat kohteet erottuvat taustasta.
//
// Paksunnus tehdään mallin origosta ulospäin (ei normaalien suuntaan), jolloin
// kulmikkaisiin laatikoihin ei jää aukkoja kulmiin.

uniform vec4 outline_color : source_color = vec4(0.16, 0.08, 0.05, 1.0);
// Ääriviivan paksuus metreinä (riippumatta mallin skaalasta).
uniform float width = 0.085;

void vertex() {
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	vec3 dir = length(VERTEX) > 0.0001 ? normalize(VERTEX) : NORMAL;
	// Sekoitetaan normaalin kanssa: pyöreämpi muoto, ei aukkoja.
	dir = normalize(dir + NORMAL * 0.5);
	VERTEX += dir * (width / s);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
