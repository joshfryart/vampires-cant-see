shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Wall faces drawn as sonar-lit edge lines on black (js/render.js drawWalls).
// Brightness per fragment is sonar.js sample2 at the fragment's world position, read from pulse textures.
#include "res://render/shaders/sonar_common.gdshaderinc"

uniform float boil_amp = 0.8;      // px of top/bottom edge jitter while lit
uniform int boil_frame = 0;        // 0..3, advanced at 10 fps by the game
uniform float boil_on = 1.0;
uniform float line_px = 1.0;       // line width in px at 640x360
uniform float line_px_near = 1.5;  // width for walls closer than 1.5 cells
uniform float debug_mode = 0.0;    // 1 = output b0 in red, b1 in green (for read-back tests)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cover(float px_from_edge, float width) {
	// line centred half a width inside the face so the whole stroke is visible
	return clamp(width * 0.5 + 0.5 - abs(px_from_edge - width * 0.5), 0.0, 1.0);
}

float jitter(float col, float axis) {
	float k = floor(col / 4.0);
	float f = fract(col / 4.0);
	float a = hash11(k * 2.0 + axis + float(boil_frame) * 17.0) * 2.0 - 1.0;
	float b = hash11((k + 1.0) * 2.0 + axis + float(boil_frame) * 17.0) * 2.0 - 1.0;
	return mix(a, b, f);
}

void fragment() {
	vec2 p = wpos.xz;
	vec4 L = sonar_wall_light(p, game_time);
	float b0 = L.x;
	float b1 = L.y;
	float b = max(b0, b1);
	float age = L.z;
	if (debug_mode > 0.5) {
		ALBEDO = vec3(b0, b1, 0.0);
	} else if (b <= 0.01) {
		ALBEDO = vec3(0.0);
	} else {
		float depth = max(0.05, -VERTEX.z);
		float v = UV.y;
		float fwy = max(fwidth(v), 1e-5);
		float fwx = max(fwidth(UV.x), 1e-5);
		float width = depth < 1.5 ? line_px_near : line_px;
		float col = floor(FRAGCOORD.x / 2.0);
		float jb = boil_on * boil_amp * jitter(col, 1.0);
		float jt = boil_on * boil_amp * jitter(col, 0.0);
		float flash = (age >= 0.0 && age < FLASH_AGE) ? 1.0 - age / FLASH_AGE : 0.0;

		vec3 outc = vec3(0.0);
		// bottom edge lit by the floor-height brightness, top edge by the ceiling-height brightness
		if (b0 > 0.01) {
			float a = line_alpha(b0, depth);
			a = min(1.0, a + 0.6 * flash);
			float c = cover(v / fwy + jb, width) * a;
			outc = max(outc, mix(fade_color(b0), vec3(1.0), flash) * c);
		}
		if (b1 > 0.01) {
			float a = line_alpha(b1, depth);
			a = min(1.0, a + 0.6 * flash);
			float c = cover((1.0 - v) / fwy + jt, width) * a;
			outc = max(outc, mix(fade_color(b1), vec3(1.0), flash) * c);
		}
		// vertical lines at face ends: full strength at corners, 0.35 where the wall continues flush
		float side_u = UV.x < 0.5 ? UV.x : 1.0 - UV.x;
		float strength = UV.x < 0.5 ? COLOR.r : COLOR.g;
		float bv = v > 0.5 ? mix(b0, b1, 0.75) : mix(b0, b1, 0.25);
		if (bv > 0.01) {
			float a = line_alpha(bv, depth) * strength;
			a = min(1.0, a + 0.5 * flash * strength);
			float c = cover(side_u / fwx, width) * a;
			outc = max(outc, mix(fade_color(bv), vec3(1.0), flash) * c);
		}
		ALBEDO = outc;
	}
}
