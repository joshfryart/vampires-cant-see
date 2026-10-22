shader_type canvas_item;
// js css #vignette and #grain: radial dark edges and a film-grain noise tile, normal blend, over everything in the frame.
// Vignette: transparent inside 0.1575 W, alpha 0.6 at 0.5967 W (W = the frame width), scaled by vig_opacity.
// Grain: grey-blue noise at grain_opacity, stepping twice a second.
uniform float vig_opacity = 1.0;
uniform float grain_opacity = 0.0;
uniform float grain_time = 0.0;
uniform vec2 frame_size = vec2(640.0, 360.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * frame_size;
	float w = frame_size.x;
	float d = length(p - frame_size * 0.5);
	float t = clamp((d - 0.1575 * w) / (0.5967 * w - 0.1575 * w), 0.0, 1.0);
	float va = 0.6 * t * vig_opacity;
	vec4 col = vec4(0.0, 0.0, 0.0, va);
	if (grain_opacity > 0.0) {
		float step_i = floor(grain_time * 2.0);
		float v = 0.47 + 0.53 * hash(floor(p) + vec2(step_i * 37.0, step_i * 61.0));
		vec3 g = vec3(v * 0.8, v * 0.9, v);
		float ga = grain_opacity;
		col.rgb = mix(col.rgb, g, ga / max(va + ga * (1.0 - va), 1e-4));
		col.a = va + ga * (1.0 - va);
	}
	COLOR = col;
}
