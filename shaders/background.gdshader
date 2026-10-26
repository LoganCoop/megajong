shader_type canvas_item;
// Rainy neo-Tokyo night: dithered sky, red sun, three skyline layers with blinking
// windows, neon haze, a perspective grid floor and rain. All quantized to the 480x270 pixel grid.

uniform float pulse = 0.0;

const vec2 RES = vec2(480.0, 270.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

// Returns building coverage (0/1) at pixel p for one skyline layer, and window light via `lit`.
float building(vec2 p, float cell, float min_h, float max_h, float seed, float horizon, out float lit, float t) {
	float col = floor(p.x / cell);
	float h = mix(min_h, max_h, hash(vec2(col, seed)));
	float top = horizon - h;
	lit = 0.0;
	if (p.y < top) return 0.0;
	vec2 w = vec2(mod(p.x, cell), p.y - top);
	if (mod(w.x, 4.0) >= 1.0 && mod(w.x, 4.0) < 3.0 && mod(w.y, 5.0) >= 1.0 && mod(w.y, 5.0) < 3.0 && w.x > 2.0 && w.x < cell - 2.0 && w.y > 4.0) {
		vec2 id = vec2(col * 13.0 + floor(w.x / 4.0), floor(w.y / 5.0) + seed);
		float on = step(0.55, hash(id));
		float blink = step(0.985, hash(id + floor(t * 0.5))) ;
		lit = clamp(on - blink, 0.0, 1.0) * (0.5 + 0.5 * hash(id + 7.0));
	}
	return 1.0;
}

void fragment() {
	vec2 p = floor(UV * RES);
	float t = TIME;
	float dither = bayer4(p);

	// Sky gradient, banded by dither.
	float sy = p.y / RES.y;
	vec3 sky_top = vec3(0.025, 0.015, 0.075);
	vec3 sky_mid = vec3(0.16, 0.03, 0.22);
	vec3 sky_low = vec3(0.45, 0.07, 0.30);
	float g = clamp(sy / 0.62, 0.0, 1.0);
	g = floor(g * 6.0 + dither) / 6.0;
	vec3 c = mix(sky_top, sky_mid, smoothstep(0.0, 0.6, g));
	c = mix(c, sky_low, smoothstep(0.55, 1.0, g));

	// Red sun behind the skyline.
	vec2 sun_c = vec2(360.0, 120.0);
	float sd = length(p - sun_c);
	if (sd < 34.0) {
		bool cut = p.y > sun_c.y && mod(p.y, 6.0) < (p.y - sun_c.y) * 0.12;
		if (!cut) c = mix(vec3(1.0, 0.18, 0.32), vec3(1.0, 0.62, 0.22), clamp((p.y - (sun_c.y - 34.0)) / 68.0, 0.0, 1.0)) * 0.85;
	} else if (sd < 52.0) {
		c += vec3(0.5, 0.05, 0.2) * (1.0 - (sd - 34.0) / 18.0) * 0.18;
	}

	float lit;
	float horizon = 188.0;
	// Far layer.
	float b = building(p, 18.0, 30.0, 90.0, 1.0, horizon - 4.0, lit, t);
	if (b > 0.5) c = mix(vec3(0.10, 0.04, 0.20), vec3(0.95, 0.80, 0.35), lit * 0.55);
	// Mid layer.
	b = building(p, 26.0, 20.0, 70.0, 5.0, horizon + 6.0, lit, t);
	if (b > 0.5) c = mix(vec3(0.06, 0.03, 0.13), vec3(0.15, 0.90, 1.0), lit * 0.6);
	// Near layer with neon rim at the roofline.
	float col = floor(p.x / 38.0);
	float h = mix(14.0, 48.0, hash(vec2(col, 9.0)));
	float top = horizon + 16.0 - h;
	if (p.y >= top) {
		c = vec3(0.025, 0.018, 0.06);
		if (p.y < top + 1.0) c = mix(vec3(1.0, 0.16, 0.54), vec3(0.1, 0.94, 1.0), step(0.5, hash(vec2(col, 3.0))));
		vec2 w = vec2(mod(p.x, 38.0), p.y - top);
		if (mod(w.x, 6.0) >= 2.0 && mod(w.x, 6.0) < 4.0 && mod(w.y, 6.0) >= 2.0 && mod(w.y, 6.0) < 4.0 && w.y > 4.0) {
			float on = step(0.7, hash(vec2(col * 7.0 + floor(w.x / 6.0), floor(w.y / 6.0))));
			c = mix(c, vec3(1.0, 0.7, 0.3), on * 0.7);
		}
	}

	// Floor: dark lacquer with a faint perspective grid.
	float floor_y = 206.0;
	if (p.y >= floor_y) {
		float d = p.y - floor_y + 1.0;
		float depth = 60.0 / d;
		vec3 fc = mix(vec3(0.08, 0.02, 0.14), vec3(0.02, 0.01, 0.05), clamp(d / 64.0, 0.0, 1.0));
		float gx = abs(fract((p.x - 240.0) * depth / 120.0 * 0.5 + 0.5) - 0.5);
		float gy = fract(depth * 1.2 + t * 0.15);
		float line = max(step(gx, 0.018 * depth), step(gy, 0.05 * (1.0 / depth + 0.3)));
		fc += vec3(0.05, 0.4, 0.6) * line * 0.22 * clamp(1.5 - d / 64.0, 0.0, 1.0);
		c = fc;
	}

	// Rain.
	float lane = floor(p.x / 3.0);
	float speed = 90.0 + 140.0 * hash(vec2(lane, 1.0));
	float ry = mod(p.y + p.x * 0.6 - t * speed - hash(vec2(lane, 2.0)) * 400.0, 270.0 + 40.0 * hash(vec2(lane, 3.0)));
	if (mod(p.x, 3.0) < 1.0 && ry < 6.0 && hash(vec2(lane, 4.0)) > 0.55) {
		c += vec3(0.35, 0.55, 0.75) * (1.0 - ry / 6.0) * 0.6;
	}

	c += vec3(pulse) * vec3(0.8, 0.2, 0.5);
	COLOR = vec4(c, 1.0);
}
