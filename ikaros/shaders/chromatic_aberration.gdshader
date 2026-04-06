shader_type canvas_item;

/** Edge color bleed; driven from ScreenJuice (player speed). */
uniform float aberration_strength : hint_range(0.0, 0.035) = 0.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float dist = length(dir);
	vec2 offs = vec2(0.0);
	if (dist > 0.0001) {
		offs = normalize(dir) * aberration_strength * dist * 3.0;
	}
	vec4 c = textureLod(screen_texture, uv, 0.0);
	float r = textureLod(screen_texture, uv + offs, 0.0).r;
	float b = textureLod(screen_texture, uv - offs, 0.0).b;
	COLOR = vec4(r, c.g, b, c.a);
}
