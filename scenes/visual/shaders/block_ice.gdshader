shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Stylized ice / glass block: tinted, partly see-through, frosty bevelled edges,
// diagonal glints and a bright fresnel rim.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform vec3 box_size = vec3(1.0);
uniform vec4 base_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.92, 0.99, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.62;
uniform float bevel = 0.09;
uniform float seed = 0.0;

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec2 uv;
	vec2 dim;
	vec3 au;
	vec3 av;
	float fid;
	face_coords(v_pos, v_nrm, box_size, uv, dim, au, av, fid);

	float edge;
	float outline;
	vec3 n = bevel_normal(uv, dim, au, av, v_nrm, bevel, edge, outline);
	vec3 vn = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);

	float fres = pow(1.0 - clamp(dot(vn, VIEW), 0.0, 1.0), 3.0);
	// Two diagonal glint stripes across each face.
	float diag = uv.x * 0.8 + uv.y + seed;
	float glint = smoothstep(0.93, 1.0, sin(diag * 5.0)) + smoothstep(0.985, 1.0, sin(diag * 11.0 + 1.3)) * 0.6;
	// Frosty inner cracks.
	float frost = smoothstep(0.62, 0.72, vnoise((uv + vec2(fid * 3.0 + seed)) * 6.0));

	vec3 col = base_color.rgb;
	col = mix(col, rim_color.rgb, frost * 0.25 + edge * 0.55 + glint * 0.6);
	col = mix(col, base_color.rgb * 0.55, outline * 0.8);

	ALBEDO = col;
	EMISSION = rim_color.rgb * (fres * 0.25 + glint * 0.15);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	ALPHA = clamp(opacity + edge * 0.3 + fres * 0.3 + glint * 0.3 + outline * 0.3, 0.0, 0.97);
	NORMAL = vn;
}
