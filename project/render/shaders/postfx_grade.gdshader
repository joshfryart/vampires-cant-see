shader_type canvas_item;
// js/postfx.js bloom and colour grade over the finished frame (before the HUD). Static: nothing pulses.
//   bloom:  a soft additive blur of the frame (effects 2 at quality 3: alpha 0.55).
//   grade:  dusk multiplies rgb(150,140,200) at 0.10 * dusk; dawn multiplies rgb(255,205,185) at 0.12 * dawn and
//           desaturates by 0.25 * dawn. Both only at effects level 1 or 2.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float bloom_alpha = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (bloom_alpha > 0.0) {
		vec3 b = vec3(0.0);
		float wsum = 0.0;
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				float w = 1.0 / (1.0 + float(x * x + y * y));
				b += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px * 1.6).rgb * w;
				wsum += w;
			}
		}
		c += b / wsum * bloom_alpha;
	}
	if (dusk > 0.0) {
		float a = 0.10 * dusk;
		c = mix(c, c * vec3(150.0, 140.0, 200.0) / 255.0, a);
	}
	if (dawn > 0.0) {
		float a = 0.12 * dawn;
		c = mix(c, c * vec3(255.0, 205.0, 185.0) / 255.0, a);
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(c, vec3(l), 0.25 * dawn);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
