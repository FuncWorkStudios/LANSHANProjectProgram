shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 200.0) = 1.0;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 tex_size = vec2(textureSize(SCREEN_TEXTURE, 0));

    if (pixel_size <= 1.0) {
        COLOR = texture(SCREEN_TEXTURE, uv);
    } else {
        float step = pixel_size / max(tex_size.x, tex_size.y);
        vec2 quantized = floor(uv / step) * step + step * 0.5;
        quantized = clamp(quantized, 0.0, 1.0); // 防止越界
        COLOR = texture(SCREEN_TEXTURE, quantized);
    }
}