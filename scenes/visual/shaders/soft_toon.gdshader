shader_type spatial;
render_mode diffuse_toon, specular_disabled;
// Soft two-tone shading for backdrop props (clouds, hills, mountains, foliage).
// Uses vertex colour when present, otherwise `color`. Height tint adds a soft
// gradient from base to top.

uniform vec4 color : source_color = vec4(1.0);
uniform vec4 top_tint : source_color = vec4(1.0);
uniform float use_vertex_color = 0.0;
uniform float tint_height = 10.0;
uniform float tint_base = 0.0;
uniform float emission_amount = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = mix(color.rgb, COLOR.rgb * color.rgb, use_vertex_color);
	float h = clamp((v_world.y - tint_base) / max(tint_height, 0.001), 0.0, 1.0);
	vec3 col = mix(base, base * top_tint.rgb, h);
	ALBEDO = col;
	EMISSION = col * emission_amount;
	ROUGHNESS = 1.0;
}
