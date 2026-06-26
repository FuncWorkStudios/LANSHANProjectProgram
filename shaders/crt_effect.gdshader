shader_type canvas_item;

// CRT / VHS retro monitor effect
// Samples the screen behind the node via SCREEN_TEXTURE.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float scanline_count : hint_range(100.0, 1000.0) = 300.0;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.3;
uniform float noise_opacity : hint_range(0.0, 1.0) = 0.1;
uniform float pixel_distortion : hint_range(0.0, 0.1) = 0.002;
uniform float roll_speed : hint_range(0.0, 10.0) = 2.0;
uniform float saturation : hint_range(0.0, 3.0) = 1.4;

// Pseudo-random function
float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// 1. VHS tape-roll pixel distortion
	float time_roll = TIME * roll_speed;
	float line_noise = rand(vec2(uv.y * 100.0, time_roll)) * pixel_distortion;

	// 2. Chromatic aberration — split R/B channels
	vec4 col_r = texture(SCREEN_TEXTURE, vec2(uv.x + line_noise, uv.y));
	vec4 col_g = texture(SCREEN_TEXTURE, vec2(uv.x, uv.y));
	vec4 col_b = texture(SCREEN_TEXTURE, vec2(uv.x - line_noise, uv.y));

	vec4 base_color = vec4(col_r.r, col_g.g, col_b.b, 1.0);

	// 3. Saturation boost
	float lum = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
	base_color.rgb = mix(vec3(lum), base_color.rgb, saturation);

	// 4. Scanlines
	float scanline = sin(uv.y * scanline_count * 3.14159265359 * 2.0);
	scanline = (scanline + 1.0) / 2.0; // remap to 0-1
	base_color.rgb -= scanline * scanline_opacity;

	// 5. Static white noise
	float static_noise = rand(uv + vec2(TIME, 0.0));
	base_color.rgb += (static_noise - 0.5) * noise_opacity;

	COLOR = base_color;
}
