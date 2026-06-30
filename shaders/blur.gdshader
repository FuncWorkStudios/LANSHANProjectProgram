shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 50.0) = 10.0;

// 高斯权重表（5x5 核）
const float weights[25] = float[25](
    0.0030, 0.0133, 0.0219, 0.0133, 0.0030,
    0.0133, 0.0596, 0.0983, 0.0596, 0.0133,
    0.0219, 0.0983, 0.1621, 0.0983, 0.0219,
    0.0133, 0.0596, 0.0983, 0.0596, 0.0133,
    0.0030, 0.0133, 0.0219, 0.0133, 0.0030
);

void fragment() {
    if (blur_amount < 0.5) {
        COLOR = texture(TEXTURE, UV);  // 直接赋值，不用 return
    } else {
        float s = blur_amount * 0.001;
        vec2 offset[25] = vec2[25](
            vec2(-2.0, -2.0), vec2(-1.0, -2.0), vec2(0.0, -2.0), vec2(1.0, -2.0), vec2(2.0, -2.0),
            vec2(-2.0, -1.0), vec2(-1.0, -1.0), vec2(0.0, -1.0), vec2(1.0, -1.0), vec2(2.0, -1.0),
            vec2(-2.0,  0.0), vec2(-1.0,  0.0), vec2(0.0,  0.0), vec2(1.0,  0.0), vec2(2.0,  0.0),
            vec2(-2.0,  1.0), vec2(-1.0,  1.0), vec2(0.0,  1.0), vec2(1.0,  1.0), vec2(2.0,  1.0),
            vec2(-2.0,  2.0), vec2(-1.0,  2.0), vec2(0.0,  2.0), vec2(1.0,  2.0), vec2(2.0,  2.0)
        );
        
        COLOR = vec4(0.0);
        for (int i = 0; i < 25; i++) {
            COLOR += texture(TEXTURE, UV + offset[i] * s) * weights[i];
        }
    }
}