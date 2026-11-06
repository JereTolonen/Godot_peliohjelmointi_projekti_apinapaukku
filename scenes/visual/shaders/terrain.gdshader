shader_type spatial;
render_mode diffuse_burley;
// Stylized ground: grassy / snowy / sandy top with a wavy lip running down the sides,
// and layered rock / soil strata on the sides. Works in world space so any mesh
// (the kit ground blocks, floating islands, backdrop terrain) gets a matching look.

#include "res://scenes/visual/shaders/block_common.gdshaderinc"

uniform vec4 top_a : source_color = vec4(0.45, 0.78, 0.30, 1.0);
uniform vec4 top_b : source_color = vec4(0.62, 0.86, 0.36, 1.0);
uniform vec4 side_a : source_color = vec4(0.78, 0.52, 0.34, 1.0);
uniform vec4 side_b : source_color = vec4(0.66, 0.42, 0.27, 1.0);
uniform vec4 deep_color : source_color = vec4(0.38, 0.24, 0.18, 1.0);
uniform vec4 speck_color : source_color = vec4(0.9, 0.72, 0.5, 1.0);
// Height (in the mesh's own units) of the top surface. Fragments within `lip`
// below it are painted as top material, with a wavy edge.
uniform float top_local_y = 1.0;
uniform float lip = 0.1;
uniform float strata_scale = 1.6;
uniform float top_from_normal = 0.55;
uniform float world_top_y = -1000.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float wave = vnoise(vec2(v_world.x * 2.3 + v_world.z * 1.7, v_world.z * 0.5)) ;
	float depth_local = top_local_y - v_local.y;
	float drip = lip * (0.45 + 0.9 * wave);
	float depth_world = world_top_y > -999.0 ? world_top_y - v_world.y : 1e5;
	bool top = v_wn.y > top_from_normal || depth_local < drip || depth_world < drip * 4.0;

	vec3 col;
	if (top) {
		float patches = vnoise(v_world.xz * 0.45);
		float fine = vnoise(v_world.xz * 6.0 + vec2(v_world.y));
		col = mix(top_a.rgb, top_b.rgb, smoothstep(0.3, 0.7, patches));
		col *= 0.93 + fine * 0.12;
		// Darker underside of the lip.
		float under = smoothstep(drip * 0.6, drip, depth_local) * step(v_wn.y, top_from_normal);
		col *= 1.0 - under * 0.25;
	} else {
		float s = v_world.y * strata_scale + vnoise(vec2(v_world.x * 0.35, v_world.z * 0.35)) * 1.4;
		float band = floor(s);
		float r = hash21(vec2(band, 3.7));
		col = mix(side_a.rgb, side_b.rgb, r);
		// Thin line between strata.
		float fs = fract(s);
		col *= 0.86 + 0.14 * smoothstep(0.0, 0.08, fs);
		// Pebbles.
		float pb = vnoise(vec2(v_world.x + v_world.z, v_world.y) * 7.0);
		col = mix(col, speck_color.rgb, smoothstep(0.78, 0.84, pb) * 0.6);
		// Deeper = darker, blends into the abyss / water below.
		float lip_shadow = 1.0 - smoothstep(0.0, lip * 2.5, depth_local - drip) * 0.0;
		col = mix(col, deep_color.rgb, clamp(depth_local * 0.18, 0.0, 0.6));
		col *= mix(0.7, 1.0, smoothstep(drip, drip + lip * 1.5, depth_local)) * lip_shadow;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
