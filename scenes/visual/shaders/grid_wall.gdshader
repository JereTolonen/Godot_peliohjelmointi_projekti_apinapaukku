shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Neonruudukko pelialueen takana. Näkymätön, paitsi missä "roiske" (rengasaalto) kulkee.
// grid_wall.gd lisää roiskeet: räjähdykset, osumat, kyvyt, pomon laskeutumiset ja
// satunnaiset välähdykset.

const int MAX_RIPPLES = 16;

uniform vec4 grid_color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
// Ruudun koko metreinä (1 m = palikan koko).
uniform float cell = 1.0;
// Viivan paksuus (m) ja hehku viivan ympärillä.
uniform float line_width = 0.035;
uniform float glow_width = 0.16;
// Kirkkaus (yli 1 = kukkii glow-efektissä).
uniform float brightness = 1.05;
// Roiskeet: xy = paikka, z = alkamisaika, w = voimakkuus (0 = ei käytössä).
uniform vec4 ripples[MAX_RIPPLES];
// Roiskeen väri (rgb) ja nopeus (a, m/s).
uniform vec4 ripple_colors[MAX_RIPPLES];
// Skriptin aika sekunteina (sama kello kuin ripples.z).
uniform float now = 0.0;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Pehmeä häivytys (m): ruudukko himmenee sitä mukaa kuin se lähestyy maata tai muuta
// sen takana/läpi menevää pintaa, joten leikkauskohtiin ei jää teräviä reunoja.
uniform float soft_distance = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xy;

	// Ruudukon viivat: etäisyys lähimpään viivaan (x- ja y-suunnassa).
	vec2 g = abs(fract(p / cell + 0.5) - 0.5) * cell;
	float d_line = min(g.x, g.y);
	float aa = fwidth(d_line) * 1.5;
	float core = 1.0 - smoothstep(line_width - aa, line_width + aa, d_line);
	float halo = exp(-d_line / glow_width) * 0.35;
	// Risteyskohdat hieman kirkkaammiksi.
	float cross_pt = (1.0 - smoothstep(0.0, line_width * 3.0, max(g.x, g.y))) * 0.8;
	float lines = core + halo + cross_pt;

	vec3 col = vec3(0.0);
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) {
			continue;
		}
		float age = now - r.z;
		if (age < 0.0) {
			continue;
		}
		float speed = max(ripple_colors[i].a, 0.1);
		float max_radius = 2.5 + r.w * 7.0;
		float life = max_radius / speed + 0.6;
		if (age > life) {
			continue;
		}
		float d = distance(p, r.xy);
		float radius = age * speed;
		// Etenevä rengas + himmeä täyttö sen sisällä.
		float ring = exp(-pow((d - radius) / (0.6 + r.w * 0.25), 2.0));
		// Täyttö häipyy pehmeästi kohti rengasta (ei kovaa reunaa).
		float fill = exp(-pow(d / max(radius, 0.5), 2.0) * 2.0) * 0.25;
		float fade = 1.0 - smoothstep(life * 0.3, life, age);
		// Gaussinen häivytys ulkoreunalle: ei koskaan terävää rajaa.
		float edge = exp(-pow(d / max_radius, 4.0) * 3.0);
		float k = r.w * (ring + fill) * fade * edge;
		col += ripple_colors[i].rgb * k;
	}

	// Värit tulevat roiskeilta (teeman väri tai kyvyn oma väri). Tavallinen sekoitus
	// (ei additiivinen), jotta värit näkyvät myös kirkasta taivasta vasten.
	float k = max(col.r, max(col.g, col.b));
	ALBEDO = (col / max(k, 0.0001)) * brightness;
	// Pehmeä häivytys lähellä muuta geometriaa (soft particles -periaate).
	float scene_d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_d);
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -v.z / v.w;
	float own_z = -VERTEX.z;
	float soft = smoothstep(0.0, 1.0, clamp((scene_z - own_z) / soft_distance, 0.0, 1.0));
	ALPHA = clamp(lines * k, 0.0, 0.9) * soft;
}
