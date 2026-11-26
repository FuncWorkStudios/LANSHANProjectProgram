// menu_veil.gdshader —— 主菜单右侧「渐黑」遮罩
//
// 叠在共享背景图之上、所有页面 UI 之下：左半边全透明（露出背景照片），
// 越过 fade_start_px 之后向右逐渐压暗，到遮罩右缘达到 veil_color。
// alpha 最小恒为 0，最大是 veil_color.a × strength。
//
// 坐标：吃的是铺满视口的 ColorRect 的 UV，乘 viewport_size_px（设计分辨率）。
// 所以 x = 900 在任何窗口尺寸、任何拉伸模式下都落在构图的同一位置；
// 代价是这一层必须铺满视口，不能塞进局部容器里（那样 UV 原点会跑）。
//
// 层级（关键）：这一层是 BackgroundLayer 里的 MenuVeil 节点 —— 位于背景图 /
// Darken 之上、所有页面（SceneContainer）之下，属于屏幕空间，不跟页面滑动。
// 页面在它下面滑，接缝两侧同一屏幕列上的遮罩值恒等，所以滑动过渡不会出现
// 一条硬竖线；若把它挂在 MainMenu 里，它的右缘就是页面接缝，必然露出图二那样的线。
// 强度由 SceneManager 的过渡调用 BackgroundLayer.fade_menu_veil() 驱动：
// 主菜单 1，进子页时随滑动淡出。BackgroundLayer 在 VN 期间整层隐藏，游戏内无需另处理。
//
// 形状：圆角矩形。默认贴上 / 下 / 右三边（inset = 0），圆角被屏幕裁掉，
// 就是草图里的通高渐变。想要「浮在主菜单上的圆角卡片」，把 inset_top /
// inset_bottom / inset_right 调到 24、corner_radius 调到 24~32 即可：
// 左缘 alpha 本来就是 0，所以左圆角看不见，右半张卡片会露出圆角。
//
// 挂法：BackgroundLayer.tscn 的 MenuVeil（ColorRect，PRESET_FULL_RECT）+
// ShaderMaterial(本文件)；color = Color(0, 0, 0, 0) 是编译失败时的透明兜底，
// mouse_filter = IGNORE。节点顺序由 BackgroundLayer._build_layer() 调到
// Darken 之上、Black 之下。

shader_type canvas_item;
render_mode unshaded;

group_uniforms Gradient;
// 右端（最深处）颜色；alpha 就是渐变的最大透明度。
uniform vec4 veil_color : source_color = vec4(0.02, 0.02, 0.02, 0.85);
// 从这一列（设计像素）开始由全透明向右压暗。
uniform float fade_start_px : hint_range(0.0, 4096.0, 1.0) = 900.0;
// 再走多少像素到最大透明度；0 = 一直走到遮罩右缘（默认就是屏幕右缘）。
uniform float fade_length_px : hint_range(0.0, 4096.0, 1.0) = 0.0;
// 渐变曲线：1 = smoothstep 缓入缓出；>1 暗得更靠右；<1 更早变暗。
uniform float fade_curve : hint_range(0.25, 4.0, 0.05) = 1.0;
// 整体强度：1 = 按 veil_color.a 满强度。做淡入 / 淡出动画时改这个
// （本层会覆写 COLOR，所以节点的 modulate 不起作用）。
uniform float strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms Shape;
// 设计分辨率；ColorRect 铺满视口时，UV × 它 = 设计像素坐标。
uniform vec2 viewport_size_px = vec2(1280.0, 720.0);
uniform float inset_top_px : hint_range(0.0, 512.0, 1.0) = 0.0;
uniform float inset_bottom_px : hint_range(0.0, 512.0, 1.0) = 0.0;
uniform float inset_right_px : hint_range(0.0, 512.0, 1.0) = 0.0;
// 圆角半径；贴边时被屏幕裁掉（见文件头），内缩后才看得见。
uniform float corner_radius_px : hint_range(0.0, 256.0, 1.0) = 32.0;
// 圆角 / 直边的抗锯齿宽度（设计像素）。
uniform float edge_softness_px : hint_range(0.5, 8.0, 0.5) = 1.0;

void fragment() {
	vec2 px = UV * viewport_size_px;

	// 遮罩的可见右缘（贴边时就是屏幕右缘）。
	float right_edge = viewport_size_px.x - inset_right_px;
	// 贴边时把圆角盒子的右缘推出屏幕，右上 / 右下圆角就不会在屏幕内切出缺口。
	float box_right = right_edge;
	if (inset_right_px <= 0.0) {
		box_right += corner_radius_px + edge_softness_px * 2.0;
	}

	// 圆角矩形 SDF（内部为负、外部为正），再软化成 0..1 遮罩。
	vec2 box_min = vec2(fade_start_px, inset_top_px);
	vec2 box_max = vec2(box_right, viewport_size_px.y - inset_bottom_px);
	vec2 half_size = max((box_max - box_min) * 0.5, vec2(0.0));
	vec2 center = (box_min + box_max) * 0.5;
	float radius = min(corner_radius_px, min(half_size.x, half_size.y));
	vec2 q = abs(px - center) - half_size + vec2(radius);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float shape = 1.0 - smoothstep(-edge_softness_px, edge_softness_px, sdf);

	// 横向渐变：fade_start_px 处 0，ramp_end 处 1，之后保持 1。
	float ramp_end = right_edge;
	if (fade_length_px > 0.0) {
		ramp_end = min(fade_start_px + fade_length_px, right_edge);
	}
	float t = clamp((px.x - fade_start_px) / max(ramp_end - fade_start_px, 1.0), 0.0, 1.0);
	float ramp = pow(smoothstep(0.0, 1.0, t), fade_curve);

	COLOR = vec4(veil_color.rgb, veil_color.a * ramp * shape * strength);
}
