shader_type canvas_item;

// ── 背景模糊（采样屏幕，渐进式两趟） ────────────────────────────────────
//
// 与 shaders/blur.gdshader 的分工：
//   blur.gdshader  模糊「节点自己的 TEXTURE」—— 用于背景图层贴图；
//   本着色器        模糊「屏幕」（本节点之前已画好的帧）—— 用于半透明叠加层
//                   背后的画面：叠加层本身没有贴图，只能采样屏幕。
//
// 为什么要两趟（见 BackdropBlur）：
//   单趟大半径 = 抽头间距被拉大（这里能到 8~10 物理像素），间距大于信号带宽
//   就会欠采样，背景里的噪点/文字笔画会折叠成规则网格 —— 也就是颗粒感。
//   正确做法是「先小半径密采样压掉高频，再大半径稀采样」：
//     PassFine → BackBufferCopy → PassWide
//   第二趟的输入已经是平滑图，稀采样也不会再出网格纹。
//
// 用法：挂到覆盖整个视口的 ColorRect 上，且该节点的 mouse_filter 必须是
//       MOUSE_FILTER_IGNORE —— 它只负责画，不能吃掉滚轮与点击。
//       alpha 固定输出 1（不透明），模糊强度只由 blur_radius 控制。
//
// 提醒：Godot 的 fragment() 里不能用 return；本文件刻意只用工程里已跑通的
// 写法（blur.gdshader 同款：常量下标的循环 + exp 权重 + 显式 float() 转换），
// 并且不留分支。工程启用了 warnings/treat_warnings_as_errors，必须零警告。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 采样范围半径（物理像素）。脚本按「逻辑像素 × 屏幕缩放 × 动画强度」写入。
// 默认值故意留非零：万一脚本侧没写进来（材质拿不到），至少还是「糊」的，
// 而不是悄悄退回清晰 —— 叠加层半透明，看起来会像没生效。
uniform float blur_radius : hint_range(0.0, 96.0) = 20.0;

void fragment() {
	// 半径 0 时所有抽头落在同一 UV，归一化后正好等于原始像素，
	// 所以不需要「半径 0 就直接输出」的额外分支。
	vec2 tex_step = SCREEN_PIXEL_SIZE * (blur_radius / 3.0);

	vec3 sum = vec3(0.0);
	float weight_sum = 0.0;

	for (int x = -3; x <= 3; x++) {
		float dx = float(x);
		// 高斯权重：exp(-d² / 2σ²)，σ = 1.5 个抽头 → 2σ² = 4.5
		float wx = exp(-(dx * dx) / 4.5);
		for (int y = -3; y <= 3; y++) {
			float dy = float(y);
			float w = wx * exp(-(dy * dy) / 4.5);
			sum += texture(screen_tex, SCREEN_UV + vec2(dx, dy) * tex_step).rgb * w;
			weight_sum += w;
		}
	}

	COLOR = vec4(sum / weight_sum, 1.0);
}
