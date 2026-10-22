shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Floor: black, with a thin ring at each pulse's wavefront radius so the 12 cells/s travel speed reads on the ground.
// Phase 1 stand-in for js/render.js drawRipple / drawFloorFront (texture and dotted arcs come in Phase 3).
#include "res://render/shaders/sonar_common.gdshaderinc"

uniform float ring_px = 1.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 outc = vec3(0.0);
	float depth = max(0.05, -VERTEX.z);
	float world_per_px = max(length(vec2(dFdx(wpos.x), dFdx(wpos.z))), length(vec2(dFdy(wpos.x), dFdy(wpos.z))));
	for (int i = 0; i < 64; i++) {
		if (i >= pulse_count) {
			break;
		}
		vec4 r0 = texelFetch(pulse_tex, ivec2(i, 0), 0);
		vec4 r1 = texelFetch(pulse_tex, ivec2(i, 1), 0);
		vec4 r2 = texelFetch(pulse_tex, ivec2(i, 2), 0);
		float rr = (game_time - r0.w) * r1.y;
		if (rr <= 0.0 || rr > r1.x) {
			continue;
		}
		vec2 d = p - r0.xy;
		float dh = length(d);
		float half_w = max(world_per_px * ring_px * 0.5, 0.02);
		float edge = abs(dh - rr);
		if (edge > half_w + world_per_px) {
			continue;
		}
		float a = atan(d.y, d.x);
		if (a < 0.0) {
			a += TWO_PI;
		}
		float n = r2.x;
		float idxf = floor(a / TWO_PI * n + 0.5);
		if (idxf >= n) {
			idxf -= n;
		}
		vec2 vb = texelFetch(vis_tex, ivec2(int(idxf), i), 0).rg;
		if (dh > vb.x + TOL) {
			continue;
		}
		float b = (1.0 - 0.5 * rr / r1.x) * r1.w * vb.y;
		float c = clamp((half_w + world_per_px * 0.5 - edge) / world_per_px, 0.0, 1.0);
		float al = line_alpha(b, depth) * 0.8 * c;
		outc = max(outc, fade_color(b) * al);
	}
	ALBEDO = outc;
}
