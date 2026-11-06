shader_type sky;
// Kevyt taivas Compatibility-renderöijälle (web): sama väriliuku, auringon hehku ja
// tähdet kuin stylized_sky.gdshaderissa, mutta ilman säteenkulkupilviä ja
// puolen resoluution passia (joita Compatibility ei tue).
// visual_director.gd vaihtaa tämän käyttöön automaattisesti.

uniform vec3 top_color : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 bottom_color : source_color = vec3(0.75, 0.9, 1.0);
uniform vec3 sun_scatter : source_color = vec3(0.4, 0.35, 0.25);
uniform float stars_intensity = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float horizon_mask = abs(EYEDIR.y);
	vec3 col = mix(bottom_color, top_color, clamp(EYEDIR.y, 0.0, 1.0));
	col += sun_scatter * (1.0 - horizon_mask);
	// Pehmeä aurinko / kuu ensimmäisen suunnatun valon suunnassa.
	if (LIGHT0_ENABLED) {
		float sun = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(sun, 400.0) * 1.5 + pow(sun, 12.0) * 0.08);
	}
	if (stars_intensity > 0.0) {
		vec3 cell = floor(EYEDIR * 160.0);
		float h = hash(cell);
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + h * 40.0);
		col += step(0.996, h) * twinkle * stars_intensity * 0.5;
	}
	COLOR = clamp(col, 0.0, 4.0);
}
