shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
// The ink cave's rock vault (VaultMesh, docs/STYLE.md 0.21.5): a ceiling height field plus hanging stalactite cones, drawn like the ink walls:
// brightness is sonar.js sample2 at the fragment's ground position (the ceiling-edge value), lines are quantised in 8 alpha levels on the blue-white
// ramp. The vault covers the whole cave, so the lit band behind a ping front is a continuous rock surface, not scattered marks.
// Per quality (STRATA_Q mirrors the wall shader): boss contours at every quality; jointed cracks, bedding and stalactite ink at quality 3 with mat_detail.
#include "res://render/shaders/sonar_common.gdshaderinc"

uniform float mat_detail = 1.0;
uniform float quality = 3.0;
uniform float line_px = 1.0;
uniform float reduced_motion = 0.0;
uniform float fx = 2.0;
uniform float vault_seed = 0.0;   // per-map offset of the noise lattice (World.map_seed mod 997)

const vec4 STRATA_Q = vec4(0.0, 0.0, 0.0, 1.0);
const vec3 INK_BONE = vec3(1.0, 0.9882, 0.9569);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
}

float cell_hash(int cx, int cy, int k) {
	uint x = uint(cx + 7) * 374761393u + uint(cy + 13) * 668265263u + uint(k + 1) * 1274126177u;
	x = (x ^ (x >> 13u)) * 1103515245u;
	return float(x ^ (x >> 16u)) / 4294967296.0;
}

float tent(float d_px, float width) {
	return clamp(width * 0.5 + 0.5 - abs(d_px), 0.0, 1.0);
}

float qalpha(float a) {
	float ai = clamp(ceil(a * 8.0) - 1.0, 0.0, 7.0);
	return (ai + 1.0) / 8.0;
}

vec3 bucket_col(float b) {
	float k = min(3.0, floor(b * 4.0));
	return fade_color((k + 0.5) / 4.0);
}

float ink_lit(float b, float d, float flash) {
	return min(1.0, max(1.15 * pow(b, 0.65), 0.2 + 0.6 * b)) / (1.0 + 0.10 * d) + 0.6 * flash;
}

// smooth 2D value noise on world coordinates
float vn2(vec2 x, int sd) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	int ix = int(i.x);
	int iy = int(i.y);
	float a = cell_hash(ix, iy, sd);
	float b = cell_hash(ix + 1, iy, sd);
	float c = cell_hash(ix, iy + 1, sd);
	float d = cell_hash(ix + 1, iy + 1, sd);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void accum(inout vec3 acc, vec3 col, float a, float cov) {
	if (cov > 0.0 && a >= 0.04) {
		acc = max(acc, col * qalpha(a) * cov);
	}
}

void fragment() {
	bool cone = COLOR.a > 0.25;
	bool bead = COLOR.a > 0.75;
	vec2 p = cone ? UV2 : wpos.xz;
	vec4 L = sonar_wall_light(p, game_time, 1.0);
	float b = L.y;
	if (b <= 0.01) {
		ALBEDO = vec3(0.0);
	} else {
		int qi = int(clamp(quality, 0.0, 3.0) + 0.5);
		bool detail = STRATA_Q[qi] > 0.5 && mat_detail > 0.5;
		float depth = max(0.05, -VERTEX.z);
		float age = L.z;
		float flash = (age >= 0.0 && age < FLASH_AGE) ? 1.0 - age / FLASH_AGE : 0.0;
		vec3 col = flash > 0.0 ? INK_BONE : bucket_col(b);
		float al = ink_lit(b, depth, flash);
		float wd = line_px * 0.8;
		vec3 outc = vec3(0.0);
		if (cone) {
			vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
			if (bead) {
				outc = col * qalpha(al * 0.9);
			} else {
				float v = UV.y;
				float u = UV.x;
				float fwv = max(fwidth(v), 1e-5);
				float fwu = max(fwidth(u), 1e-5);
				vec2 nh = normalize(wnorm.xz + vec2(1e-6));
				float sil = dot(nh, normalize(cam_pos.xz - wpos.xz + vec2(1e-6)));
				float cw = (qi >= 2 ? 1.25 : 1.0) * line_px;
				float cov = tent(v / fwv, cw);                          // the lip where it leaves the vault
				cov = max(cov, tent((v - 0.55) / fwv, wd));              // one ring
				cov = max(cov, tent(abs(sil) / max(fwidth(sil), 1e-5), wd) * (1.0 - 0.5 * v));
				if (detail) {
					float tp = 1.0 - 0.7 * v;
					for (int k = 0; k < 3; k++) {
						cov = max(cov, tent((u - (0.17 + 0.33 * float(k))) / fwu, wd * tp));
					}
				}
				accum(outc, col, al * (1.0 - smoothstep(6.0, 9.5, depth)), cov);
			}
		} else {
			float wpp = max(fwidth(p.x), fwidth(p.y)); // cells per px
			float dn = 1.0 - smoothstep(0.07, 0.14, wpp);
			vec2 sp = p + vec2(vault_seed, vault_seed * 0.7);
			// rock bosses: broken closed contour lines of a smooth relief
			float g = vn2(sp * 0.7, 11) + 0.5 * vn2(sp * 1.5 + vec2(7.3, 2.9), 12) + 0.3 * vn2(sp * 3.1 + vec2(1.7, 5.1), 17);
			float gl = g * 7.0;
			float fg = max(fwidth(gl), 1e-4);
			float bd = abs(fract(gl + 0.5) - 0.5) / fg;
			float bmask = smoothstep(0.28, 0.44, vn2(sp * 1.7 + vec2(4.1, 8.8), 13));
			float bf = (1.0 - smoothstep(6.0, 9.5, depth)) * (1.0 - smoothstep(0.3, 0.6, fg));
			accum(outc, col, al * 0.8 * bf, tent(bd, wd) * bmask);
			if (detail) {
				// jointed cracks: broken Voronoi borders of a domain-warped lattice
				vec2 wp = sp + 0.55 * (vec2(vn2(sp * 0.7, 5), vn2(sp * 0.7 + vec2(31.0, 17.0), 6)) - 0.5);
				vec2 q = wp * 1.1;
				vec2 qf = fract(q);
				ivec2 qc = ivec2(floor(q));
				float f1 = 8.0;
				float f2 = 8.0;
				for (int j = -1; j <= 1; j++) {
					for (int i = -1; i <= 1; i++) {
						vec2 o = vec2(cell_hash(qc.x + i, qc.y + j, 81), cell_hash(qc.x + i, qc.y + j, 82));
						float d = length(vec2(float(i), float(j)) + o - qf);
						if (d < f1) {
							f2 = f1;
							f1 = d;
						} else if (d < f2) {
							f2 = d;
						}
					}
				}
				float e = f2 - f1;
				float fe = max(fwidth(e), 1e-5);
				float cmask = smoothstep(0.14, 0.3, vn2(sp * 2.3, 9));
				float cf = (1.0 - smoothstep(5.0, 8.0, depth)) * dn;
				accum(outc, col, al * 0.7 * cf, tent(e / fe * 0.5, wd) * cmask);
				// bedding: dashed courses along the world-anchored dip (rock_tilt's cells), only close by
				int gx = int(floor(p.x / 8.0));
				int gy = int(floor(p.y / 8.0));
				float ang = TWO_PI * cell_hash(gx, gy, 41);
				vec2 dv = vec2(cos(ang), sin(ang));
				float sb = dot(sp, dv) / 0.4 + 1.2 * vn2(sp * 0.45, 14);
				float kb = floor(sb);
				float fb = min(fract(sb), 1.0 - fract(sb)) / max(fwidth(sb), 1e-5);
				float ab = dot(sp, vec2(-dv.y, dv.x)) / 1.1 + 5.0 * cell_hash(int(kb), 15, 0);
				float on = (cell_hash(int(kb), 16, 0) < 0.6 && fract(ab) < 0.55) ? 1.0 : 0.0;
				float bdf = (1.0 - smoothstep(3.5, 6.5, depth)) * dn;
				accum(outc, col, al * 0.5 * bdf, tent(fb, wd) * on);
			}
			// a faint lit body so the lit band reads as a surface
			if (qi >= 2) {
				outc = max(outc, C_MID * 0.05 * sqrt(min(b, 1.0)) / (1.0 + 0.08 * depth));
			}
			outc *= COLOR.r;
		}
		ALBEDO = outc;
	}
}
