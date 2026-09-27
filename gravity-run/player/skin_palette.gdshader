shader_type canvas_item;

uniform float hue_shift : hint_range(0.0, 1.0) = 0.0;

vec3 rgb_to_hsv(vec3 color) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(color.bg, k.wz), vec4(color.gb, k.xy), step(color.b, color.g));
	vec4 q = mix(vec4(p.xyw, color.r), vec4(color.r, p.yzx), step(p.x, color.r));
	float delta = q.x - min(q.w, q.y);
	float epsilon = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * delta + epsilon)), delta / (q.x + epsilon), q.x);
}

vec3 hsv_to_rgb(vec3 color) {
	vec3 p = abs(fract(color.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return color.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), color.y);
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	vec3 hsv = rgb_to_hsv(pixel.rgb);
	// Shift the character's saturated purple/pink palette while preserving
	// brightness and alpha so the pixel-art shading and silhouette stay crisp.
	if (hsv.y > 0.22 && hsv.x > 0.68 && hsv.x < 0.97) {
		hsv.x = fract(hsv.x + hue_shift);
	}
	COLOR = vec4(hsv_to_rgb(hsv), pixel.a);
}
