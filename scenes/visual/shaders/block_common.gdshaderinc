// Shared helpers for the stylized building blocks (wood, stone, ice).
// Everything is computed from the block's local position, so no textures are needed
// and every block size gets correctly sized planks / bricks and bevelled edges.

varying vec3 v_pos;
varying vec3 v_nrm;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 2D coordinates on the face the fragment is on (in metres, centred), the face
// dimensions, the face axes and an id per face (0..5).
void face_coords(vec3 p, vec3 n, vec3 size, out vec2 uv, out vec2 dim, out vec3 au, out vec3 av, out float fid) {
	vec3 an = abs(n);
	if (an.x > an.y && an.x > an.z) {
		uv = vec2(p.z, p.y);
		dim = vec2(size.z, size.y);
		au = vec3(0.0, 0.0, 1.0);
		av = vec3(0.0, 1.0, 0.0);
		fid = n.x > 0.0 ? 0.0 : 1.0;
	} else if (an.y > an.z) {
		uv = vec2(p.x, p.z);
		dim = vec2(size.x, size.z);
		au = vec3(1.0, 0.0, 0.0);
		av = vec3(0.0, 0.0, 1.0);
		fid = n.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = vec2(p.x, p.y);
		dim = vec2(size.x, size.y);
		au = vec3(1.0, 0.0, 0.0);
		av = vec3(0.0, 1.0, 0.0);
		fid = n.z > 0.0 ? 4.0 : 5.0;
	}
}

// Fake bevel: tilts the normal near the edges so they catch the light.
// `edge` returns 0 in the middle of the face and 1 right at the edge.
// `outline` returns 1 inside a thin cartoon outline along the edges.
vec3 bevel_normal(vec2 uv, vec2 dim, vec3 au, vec3 av, vec3 n, float bev, out float edge, out float outline) {
	vec2 d = dim * 0.5 - abs(uv);
	float eu = clamp(1.0 - d.x / bev, 0.0, 1.0);
	float ev = clamp(1.0 - d.y / bev, 0.0, 1.0);
	edge = max(eu, ev);
	outline = 1.0 - smoothstep(0.012, 0.03, min(d.x, d.y));
	vec3 nn = n + au * sign(uv.x) * eu * 0.85 + av * sign(uv.y) * ev * 0.85;
	return normalize(nn);
}
