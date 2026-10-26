shader_type canvas_item;
// Light CRT post effect: scanlines, chromatic fringe, vignette, hit flash.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float flash = 0.0;
uniform float aberration = 0.0015;

void fragment() {
	vec2 uv = SCREEN_UV;
	float r = texture(screen_tex, uv + vec2(aberration, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(aberration, 0.0)).b;
	vec3 c = vec3(r, g, b);

	float line = mod(FRAGCOORD.y, 2.0) < 1.0 ? 1.0 : 0.86;
	c *= line;

	vec2 d = uv - 0.5;
	c *= 1.0 - dot(d, d) * 1.1;
	c += vec3(flash);
	COLOR = vec4(c, 1.0);
}
