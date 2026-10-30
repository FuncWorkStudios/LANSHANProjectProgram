shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 200.0) = 1.0;
// 逻辑分辨率长边（1280x720 → 1280）。由 SceneManager 在创建材质时写入。
// pixel_size 因此以「逻辑像素」计：屏上块数恒定 = logical_max / pixel_size，
// 不随窗口/显示器分辨率变化。
uniform float logical_max : hint_range(100.0, 8192.0) = 1280.0;

void fragment() {
	vec2 uv = SCREEN_UV;

	if (pixel_size <= 1.0) {
		COLOR = texture(SCREEN_TEXTURE, uv);
	} else {
		float blk = pixel_size / max(logical_max, 1.0);
		vec2 quantized = floor(uv / blk) * blk + blk * 0.5;
		quantized = clamp(quantized, 0.0, 1.0); // 防止越界
		COLOR = texture(SCREEN_TEXTURE, quantized);
	}
}