shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
// Koko ruudun jälkikäsittely, joka korostaa pelialuetta (z = 0 -taso):
//  - edessä oleva (etuala: maan reuna, vesi) tummuu, haalistuu ja pehmenee hieman
//  - takana oleva (tausta) haalistuu hieman
//  - pelialue itse pysyy täysin ennallaan.
// visual_director.gd päivittää focus_depth-arvon joka ruudulla (kameran etäisyys pelitasoon).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// Kameran etäisyys pelitasoon (m).
uniform float focus_depth = 30.0;
// Kuinka paljon pelitason edessä / takana pysyy täysin terävänä (m).
uniform float near_band = 1.2;
uniform float far_band = 5.0;
// Kuinka monen metrin matkalla etualan efekti kasvaa täyteen voimaan.
uniform float fg_ramp = 5.0;
// Etuala.
uniform float fg_darken : hint_range(0.0, 1.0) = 0.32;
uniform float fg_desaturate : hint_range(0.0, 1.0) = 0.38;
uniform float fg_soften : hint_range(0.0, 4.0) = 1.6;
// Tausta (vain vähän, sumu hoitaa loput).
uniform float bg_desaturate : hint_range(0.0, 1.0) = 0.14;
uniform float sky_desaturate : hint_range(0.0, 1.0) = 0.04;

void vertex() {
	// QuadMesh 2x2 kattaa koko ruudun suoraan leikkausavaruudessa.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = view_depth(uv, INV_PROJECTION_MATRIX);
	float raw_depth = texture(depth_tex, uv).r;
	vec3 col = texture(screen_tex, uv).rgb;

	// 1 = selvästi pelitason edessä / takana.
	float fg = smoothstep(focus_depth - near_band, focus_depth - near_band - fg_ramp, z);
	float bg = smoothstep(focus_depth + far_band, focus_depth + far_band + 25.0, z);
	bool is_sky = raw_depth >= 0.99999 || raw_depth <= 0.00001;

	if (fg > 0.001) {
		// Kevyt pehmennys: 4 näytettä vinottain.
		vec2 px = fg_soften * fg / VIEWPORT_SIZE;
		vec3 blur = texture(screen_tex, uv + vec2(px.x, px.y)).rgb
			+ texture(screen_tex, uv + vec2(-px.x, px.y)).rgb
			+ texture(screen_tex, uv + vec2(px.x, -px.y)).rgb
			+ texture(screen_tex, uv + vec2(-px.x, -px.y)).rgb;
		col = mix(col, blur * 0.25, 0.75 * fg);
	}

	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	float desat = fg * fg_desaturate + (is_sky ? sky_desaturate : bg * bg_desaturate);
	col = mix(col, vec3(gray), clamp(desat, 0.0, 1.0));
	col *= 1.0 - fg * fg_darken;

	ALBEDO = col;
}
