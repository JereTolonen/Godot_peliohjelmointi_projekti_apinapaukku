shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Stylized wood (kind 0) and stone (kind 1) building blocks.
// Planks / bricks, bevelled edges and a thin cartoon outline, all procedural.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform int kind = 0;
uniform vec3 box_size = vec3(1.0);
uniform vec4 base_color : source_color = vec4(0.86, 0.58, 0.30, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.80, 0.50, 1.0);
uniform vec4 dark_color : source_color = vec4(0.42, 0.24, 0.10, 1.0);
uniform float bevel = 0.08;
uniform float seed = 0.0;

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

vec3 wood(vec2 uv, vec2 dim, float fid) {
	bool long_u = dim.x >= dim.y;
	vec2 q = long_u ? uv : uv.yx;
	vec2 qd = long_u ? dim : dim.yx;
	float count = max(1.0, floor(qd.y / 0.3 + 0.5));
	float pw = qd.y / count;
	float across = (q.y + qd.y * 0.5) / pw;
	float plank = floor(across);
	float fy = fract(across);
	float r = hash21(vec2(plank + seed * 3.0, fid * 7.0 + seed));

	// Grain lines running along the plank with a little wobble.
	float wob = vnoise(vec2(q.x * 1.6 + r * 9.0, plank * 2.7)) * 0.9;
	float g = sin((fy + wob * 0.35) * 20.0 + q.x * 0.6);
	float grain = smoothstep(0.75, 1.0, g) * 0.16;

	vec3 col = mix(base_color.rgb, light_color.rgb, r * 0.45);
	col *= 1.0 - grain;
	// Slightly darker plank ends and soft shading across each plank.
	col *= 0.9 + 0.1 * sin(fy * 3.14159);

	// Seams between planks.
	float seam_w = 0.022 / pw;
	float seam = 1.0 - smoothstep(0.0, seam_w, min(fy, 1.0 - fy));
	if (count > 1.0) {
		col = mix(col, dark_color.rgb, seam * 0.85);
	}

	// A knot now and then.
	vec2 kpos = vec2((hash21(vec2(plank, seed + 4.0)) - 0.5) * qd.x * 0.7, 0.5);
	float kd = length(vec2((q.x - kpos.x) / pw, fy - kpos.y) * vec2(1.0, 1.6));
	if (hash21(vec2(plank, fid + seed)) > 0.6) {
		float ring = smoothstep(0.22, 0.18, kd) * (0.6 + 0.4 * sin(kd * 40.0));
		col = mix(col, dark_color.rgb * 1.2, ring * 0.6);
	}

	// Nails near both ends of each plank.
	if (qd.x > 0.55) {
		float nx = qd.x * 0.5 - 0.12;
		vec2 a = vec2(abs(q.x) - nx, (fy - 0.5) * pw);
		float nail = smoothstep(0.034, 0.024, length(a));
		col = mix(col, vec3(0.32, 0.3, 0.33), nail);
		col += vec3(0.25) * smoothstep(0.016, 0.0, length(a + vec2(0.008, -0.008))) * nail;
	}
	return col;
}

vec3 stone(vec2 uv, vec2 dim, float fid) {
	float rows = max(1.0, floor(dim.y / 0.34 + 0.5));
	float rh = dim.y / rows;
	float yv = (uv.y + dim.y * 0.5) / rh;
	float row = floor(yv);
	float bw = 0.58;
	float bcount = max(1.0, floor(dim.x / bw + 0.5));
	bw = dim.x / bcount;
	float off = mod(row, 2.0) * 0.5;
	float xv = (uv.x + dim.x * 0.5) / bw + off;
	float brick = floor(xv);
	vec2 f = vec2(fract(xv), fract(yv));
	float dx = min(f.x, 1.0 - f.x) * bw;
	float dy = min(f.y, 1.0 - f.y) * rh;
	// Bricks touching the block edge are not split by an offset seam.
	float edge_x = dim.x * 0.5 - abs(uv.x);
	dx = min(dx, max(edge_x, 0.0) + 1.0);
	float m = smoothstep(0.012, 0.035, min(dx, dy));

	float r = hash21(vec2(brick + seed, row * 3.1 + fid * 11.0));
	vec3 col = mix(base_color.rgb, light_color.rgb, r * 0.5);
	// Speckles and soft rounded shading on every brick.
	float sp = vnoise((uv + vec2(seed)) * 22.0);
	col *= 0.9 + sp * 0.14;
	col *= 0.88 + 0.12 * smoothstep(0.0, 0.08, min(dx, dy));
	col = mix(dark_color.rgb, col, m);
	return col;
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

	vec3 col = kind == 0 ? wood(uv, dim, fid) : stone(uv, dim, fid);
	// Light rim on the bevel, then a thin dark outline for the cartoon look.
	col = mix(col, light_color.rgb * 1.08, smoothstep(0.35, 0.9, edge) * 0.35);
	col = mix(col, dark_color.rgb * 0.8, outline * 0.9);

	ALBEDO = col;
	ROUGHNESS = kind == 0 ? 0.78 : 0.9;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
}
