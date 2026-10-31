// map_load_reveal.gdshader —— 地图入场加载揭幕
//
// 把贴图按 grid_size × grid_size（默认 8×8 = 64 块）切开，每块从纯黑渐显到原图。
// 每块的"开始时间"由脚本写进 block_starts 纹理的 R 通道（0..1，归一化到整段加载时长），
// 因此随机顺序、分批、错峰都在 CPU 侧决定，shader 只做查表 + smoothstep。
//
// 只作用于地图贴图本身：标题栏 / 返回栏 / 信息面板都是独立节点，不受影响。

shader_type canvas_item;
render_mode unshaded;

// 8×8 的"区块开始时间"查找表（R = 0..1），必须最近邻采样
uniform sampler2D block_starts : filter_nearest, repeat_disable;
// 全局进度 0..1（由脚本逐帧驱动）
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 单块淡入时长，同样是归一化到总时长的比例（0.19 ≈ 完整版 190ms）
uniform float fade : hint_range(0.001, 1.0) = 0.19;
// 每行 / 每列切几块
uniform int grid_size = 8;

void fragment() {
	vec2 fg = vec2(float(grid_size));
	// UV 正好落在 1.0 时要夹到最后一格，避免越界
	vec2 cell = clamp(floor(UV * fg), vec2(0.0), fg - vec2(1.0));
	// 取该区块的中心点采样，配合 filter_nearest 保证块内取值恒定（硬边）
	float t0 = texture(block_starts, (cell + vec2(0.5)) / fg).r;
	float reveal = smoothstep(0.0, 1.0, clamp((progress - t0) / fade, 0.0, 1.0));
	// 只压 RGB，保留原来的 alpha
	COLOR.rgb = mix(vec3(0.0), COLOR.rgb, reveal);
}
