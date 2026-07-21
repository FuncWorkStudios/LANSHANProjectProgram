shader_type canvas_item;

// 模糊量：0 = 清晰，值越大越模糊（调用方传 0–15）
uniform float blur_amount : hint_range(0.0, 20.0) = 0.0;

// 步进采样：步长 3 × 半径 5 = 有效覆盖 ±15px
// 仅 11×11 = 121 次采样，比原始 1681 次快 13.9×
const int KERNEL_RADIUS = 5;
const int STEP = 3;

void fragment() {
	// 仅捕获 modulate 的 alpha 通道 —— Godot 2D 管线用预乘 Alpha，
	// RGB 不该被 modulate 二次影响，否则会产生颜色偏移和亮度损失
	float mod_a = COLOR.a;

	if (blur_amount < 0.01) {
		COLOR = texture(TEXTURE, UV);
		COLOR.a *= mod_a;
	} else {
		vec4 accumulated = vec4(0.0);
		float total_weight = 0.0;
		vec2 pixel = TEXTURE_PIXEL_SIZE;

		float sigma = blur_amount * 0.5;
		float denom = 2.0 * sigma * sigma;

		for (int x = -KERNEL_RADIUS; x <= KERNEL_RADIUS; x++) {
			for (int y = -KERNEL_RADIUS; y <= KERNEL_RADIUS; y++) {
				float dx = float(x * STEP);
				float dy = float(y * STEP);
				float d2 = dx * dx + dy * dy;
				float weight = exp(-d2 / denom);
				accumulated += texture(TEXTURE, UV + vec2(dx, dy) * pixel) * weight;
				total_weight += weight;
			}
		}

		COLOR = accumulated / total_weight;
		COLOR.a *= mod_a;
	}
}
