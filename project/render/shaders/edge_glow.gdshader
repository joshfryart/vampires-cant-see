shader_type canvas_item;
render_mode blend_add;
// js render.js warmSide: warm (255,150,50) linear gradients from the left (45% of W), right (45% of W) and top (50% of H) edges,
// alpha 0.55 * smoothstep falloff, each scaled by its own strength, added to the frame.
uniform float left_a = 0.0;
uniform float right_a = 0.0;
uniform float top_a = 0.0;

float fall(float u) {
	u = clamp(u, 0.0, 1.0);
	return 1.0 - u * u * (3.0 - 2.0 * u);
}

void fragment() {
	float a = 0.55 * (left_a * fall(UV.x / 0.45) + right_a * fall((1.0 - UV.x) / 0.45) + top_a * fall(UV.y / 0.5));
	COLOR = vec4(1.0, 150.0 / 255.0, 50.0 / 255.0, a);
}
