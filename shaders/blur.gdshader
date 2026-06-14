shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 20.0) = 10.0;

void fragment() {
	if (blur_amount < 0.5) {
		COLOR = texture(TEXTURE, UV);
	} else {
		float s = blur_amount * 0.0005;
		COLOR  = texture(TEXTURE, UV + vec2(-s, -s)) * 0.10;
		COLOR += texture(TEXTURE, UV + vec2(-s,  0.0)) * 0.125;
		COLOR += texture(TEXTURE, UV + vec2(-s,  s)) * 0.10;
		COLOR += texture(TEXTURE, UV + vec2(0.0, -s)) * 0.125;
		COLOR += texture(TEXTURE, UV) * 0.20;
		COLOR += texture(TEXTURE, UV + vec2(0.0,  s)) * 0.125;
		COLOR += texture(TEXTURE, UV + vec2( s, -s)) * 0.10;
		COLOR += texture(TEXTURE, UV + vec2( s,  0.0)) * 0.125;
		COLOR += texture(TEXTURE, UV + vec2( s,  s)) * 0.10;
	}
}