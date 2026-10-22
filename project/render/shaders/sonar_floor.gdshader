shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
// Floor and ceiling: everything js/render.js draws on the ground plane around a pulse, evaluated per fragment:
//   drawRipple    the wavy dotted pulse ring (the ceiling plane gets the fainter second pass, indoors only),
//   drawFloorFront the thin front arc with the stipple trailing behind it,
//   drawFootRings the wobbly concentric footstep rings (own steps are flat scuff ellipses along the heading),
//   drawRings     the secondary echo rings (struck people, markers) as dotted circles.
// Dots are tested in screen space: the dot centre on this plane is projected and compared with the fragment (2 px squares).
// Pulse data comes from PulseTextures (rows documented there); ring_tex holds the live secondary rings.
#include "res://render/shaders/sonar_common.gdshaderinc"

uniform sampler2D ring_tex : filter_nearest, repeat_disable;
uniform int ring_count = 0;
uniform bool is_ceiling = false;
uniform bool player_indoor = true;
uniform float wscale = 1.0;
uniform float reduced_motion = 0.0; // 1 = reduce motion: weak-ping flicker becomes a static dim
uniform float boil_on = 1.0;        // line boil (config on, not reduced, quality >= 2): dot jitter
uniform float quality = 3.0;        // render quality 0..3 (js r.quality)
uniform float fx = 2.0;             // effects level after the governor cap (0..2)
uniform float mat_detail = 1.0;     // js airOn: material-shaped stipple behind the front arc

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// js hash01: seeded 0..1 from two integers.
float hash01(int a, int b) {
	uint h = uint(a) * 374761393u + uint(b) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float(h ^ (h >> 16u)) / 4294967296.0;
}

vec2 to_px(mat4 view, mat4 proj, vec3 wp, vec2 vps) {
	vec4 c = proj * (view * vec4(wp, 1.0));
	vec2 ndc = c.xy / c.w;
	return (ndc * 0.5 + 0.5) * vps;
}

float wrap_angle(vec2 d) {
	float a = atan(d.y, d.x);
	return a < 0.0 ? a + TWO_PI : a;
}

// Index into the per-ray tables of pulse i for angle a.
int ray_idx(float a, float n) {
	float f = floor(a / TWO_PI * n + 0.5);
	if (f >= n) {
		f -= n;
	}
	return int(f);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 outc = vec3(0.0);
	float wpp = max(length(vec2(dFdx(wpos.x), dFdx(wpos.z))), length(vec2(dFdy(wpos.x), dFdy(wpos.z))));
	wpp = max(wpp, 1e-4);
	vec2 vps = VIEWPORT_SIZE;
	vec2 fp = to_px(VIEW_MATRIX, PROJECTION_MATRIX, wpos, vps);
	float t = game_time;

	for (int i = 0; i < 64; i++) {
		if (i >= pulse_count) {
			break;
		}
		vec4 r0 = texelFetch(pulse_tex, ivec2(i, 0), 0);
		vec4 r1 = texelFetch(pulse_tex, ivec2(i, 1), 0);
		vec4 r2 = texelFetch(pulse_tex, ivec2(i, 2), 0);
		vec4 r3 = texelFetch(pulse_tex, ivec2(i, 3), 0);
		vec4 r4 = texelFetch(pulse_tex, ivec2(i, 4), 0);
		float rng = r1.x;
		float rr = (t - r0.w) * r1.y;
		float fade = r1.z;
		float str = r1.w;
		float n = r2.x;
		bool has_beam = r2.y > 0.5;
		float kind = r2.z;
		float gen = r2.w;
		float weak = r3.y;
		float age = t - r0.w;
		vec2 d = p - r0.xy;
		float dh = length(d);
		float a = wrap_angle(d);

		// ---- footstep rings (kind 1 step, 2 personStep) ----
		if (kind > 0.5 && kind < 2.5) {
			if (is_ceiling || age < 0.0 || age >= fade || quality < 0.5) {
				continue;
			}
			bool own = kind > 1.5;
			int nr = quality >= 1.5 ? 3 : 2;
			int nrk = own ? min(nr, 2) : nr;
			vec2 q = d;
			float rho = dh;
			float th = a;
			if (own && r3.z < 1e8) {
				float ch = cos(r3.z);
				float sh = sin(r3.z);
				vec2 lq = vec2(q.x * ch + q.y * sh, -q.x * sh + q.y * ch);
				lq = vec2(lq.x / 1.2, lq.y / 0.5);
				rho = length(lq);
				th = atan(lq.y, lq.x);
				if (th < 0.0) {
					th += TWO_PI;
				}
			}
			float wp_local = wpp;
			for (int m = 0; m < 3; m++) {
				if (m >= nrk) {
					break;
				}
				float u = age / fade - float(m) * 0.2;
				if (!(u > 0.0) || u >= 1.0) {
					continue;
				}
				float R = rng * 1.8 * (0.3 + 0.7 * sqrt(u));
				float al = min(1.0, pow(1.0 - u, 1.5) * (1.0 - float(m) * 0.22) * min(1.0, str * 4.0) * (own ? 0.7 : 1.2));
				if (al < 0.03) {
					continue;
				}
				float ph = float(i) * 1.7 + float(m) * 2.1;
				float rw = R * (1.0 + 0.06 * sin(5.0 * th + t * 3.0 + ph));
				float lw = (m == 0 ? 1.7 : 1.3) * wscale;
				// distance to the ring in pixels (rho is in ellipse space for own steps; scale by the mean axis)
				float scale = own && r3.z < 1e8 ? 0.85 : 1.0;
				float edge = abs(rho - rw) * scale / wp_local;
				float cov = clamp(lw * 0.5 + 0.5 - edge, 0.0, 1.0);
				if (cov > 0.0) {
					vec3 col = own ? vec3(1.0, 0.7, 0.65) : vec3(0.91, 0.95, 1.0);
					outc += col * al * cov;
				}
			}
			continue;
		}
		if (kind > 2.5) {
			continue;
		}
		if (rr < 0.2 || rr > rng) {
			continue;
		}
		bool bounce = gen > 0.5;
		if (gen > 1.5 && quality < 2.5) {
			continue; // second-generation bounces only at quality 3
		}
		int ai = ray_idx(a, n);
		vec2 vb = texelFetch(vis_tex, ivec2(ai, i), 0).rg;
		float wkw = reduced_motion > 0.5 ? 0.7 : 1.0 - 0.3 * min(1.0, weak) * (0.5 + 0.5 * sin(t * 15.0 + float(i)));

		// ---- dotted pulse ring (floor; ceiling gets the 0.4 pass indoors) ----
		bool ceil_ok = r0.z >= 0.3;
		bool ring_here = !is_ceiling || (quality >= 1.5 && player_indoor && !bounce && ceil_ok);
		if (ring_here && abs(dh - rr) < rr * 0.06 + 4.0 * wpp) {
			float alpha = 0.85 * (1.0 - rr / rng) * min(1.0, str * 1.3);
			float dotk = bounce ? 0.7 : 1.0;
			if (weak > 0.0) {
				alpha *= wkw;
				dotk *= 1.0 - 0.35 * min(1.0, weak);
			}
			if (is_ceiling) {
				alpha *= 0.4;
			}
			if (alpha > 0.04) {
				float N = bounce ? 135.0 : 270.0;
				float s = floor(a / TWO_PI * N + 0.5);
				if (s >= N) {
					s -= N;
				}
				float ths = s / N * TWO_PI;
				float wk = 5.0 + mod(float(i), 3.0);
				float rw = rr * (1.0 + 0.04 * sin(wk * ths + t * 1.4 + float(i)));
				vec2 c = r0.xy + vec2(cos(ths), sin(ths)) * rw;
				int ci = ray_idx(ths, n);
				vec2 cvb = texelFetch(vis_tex, ivec2(ci, i), 0).rg;
				bool ok = rw <= cvb.x + TOL;
				float dk = dotk;
				if (ok && has_beam && !bounce) {
					float gb = cvb.y;
					if (rr > rng * (0.3 + 0.7 * gb) || alpha * gb < 0.03) {
						ok = false;
					}
					dk = dotk * (0.55 + 0.45 * gb);
				}
				if (ok) {
					float jit = hash01(int(s) + i * 17, int(t * 10.0) % 4) - 0.5;
					vec2 cp = to_px(VIEW_MATRIX, PROJECTION_MATRIX, vec3(c.x, wpos.y, c.y), vps) + vec2(jit, -jit) * wscale * boil_on;
					float hd = 1.1 * wscale * dk;
					vec2 dd = abs(cp - fp);
					if (dd.x <= hd + 0.5 && dd.y <= hd + 0.5) {
						vec3 col = bounce ? vec3(0.5, 0.65, 1.0) : vec3(0.91, 0.95, 1.0);
						outc += col * alpha;
					}
				}
			}
		}

		// ---- thin floor front arc and the stipple behind it (floor only, primary pulses only) ----
		if (!is_ceiling && quality >= 1.5 && !bounce && r0.z <= 0.7 && rr >= 0.3) {
			float fa = 0.5 * (1.0 - rr / rng) * min(1.0, str * 1.3) * (fade > 0.0 ? max(0.0, 1.0 - age / (fade * 2.0)) : 1.0);
			if (weak > 0.0) {
				fa *= wkw;
			}
			if (fa >= 0.04 && dh <= vb.x + TOL) {
				float edge = abs(dh - rr) / wpp;
				float cov = clamp(1.5 * 0.5 + 0.5 - edge, 0.0, 1.0);
				if (cov > 0.0) {
					outc += vec3(0.91, 0.95, 1.0) * fa * cov;
				}
				// soft gradient front (fx >= 1): two fainter arcs trailing behind, static offsets (render.js drawFloorFront)
				if (fx >= 0.5) {
					for (int sq = 0; sq < 2; sq++) {
						float Rq = rr - 0.06 * float(sq + 1);
						if (Rq < 0.3) {
							break;
						}
						float covq = clamp(1.5 * 0.5 + 0.5 - abs(dh - Rq) / wpp, 0.0, 1.0);
						outc += vec3(0.91, 0.95, 1.0) * fa * (sq == 0 ? 0.45 : 0.2) * covq;
					}
				}
				bool air = mat_detail > 0.5 && quality >= 1.5;
				float rough = clamp(r4.x, 0.0, 1.0);
				float span = air ? 0.25 + 0.5 * rough : 0.5;
				float back_f = (rr - dh) / rr;
				if (back_f > 0.04 && back_f < 0.07 + span) {
					int seed = int(floor(r0.w * 1000.0 + 0.5)) + i * 7919;
					float nd_base = quality >= 2.5 ? 40.0 : 20.0;
					int nd = air ? int(min(80.0, floor(nd_base * (0.5 + 1.5 * rough) + 0.5))) : int(nd_base);
					float dw = air && r4.y > 1.5 ? 2.0 : 1.0;
					float dhh = air && r4.y > 0.5 && r4.y < 1.5 ? 2.0 : 1.0;
					for (int di = 0; di < 80; di++) {
						if (di >= nd) {
							break;
						}
						float sth = hash01(seed, di * 2) * TWO_PI;
						float back = 0.06 + span * hash01(seed, di * 2 + 1);
						float rd = rr * (1.0 - back);
						// cheap reject before projecting: the dot must be near this fragment in the ground plane
						vec2 dc = r0.xy + vec2(cos(sth), sin(sth)) * rd;
						if (distance(dc, p) > wpp * 3.0) {
							continue;
						}
						int di2 = ray_idx(sth, n);
						if (rd > texelFetch(vis_tex, ivec2(di2, i), 0).r + TOL) {
							continue;
						}
						vec2 sp = to_px(VIEW_MATRIX, PROJECTION_MATRIX, vec3(dc.x, wpos.y, dc.y), vps);
						vec2 ad = abs(sp - fp);
						if (ad.x <= 0.5 * dw + 0.5 && ad.y <= 0.5 * dhh + 0.5) {
							outc += vec3(0.91, 0.95, 1.0) * fa * 0.7;
						}
					}
				}
			}
		}
	}

	// ---- secondary echo rings (floor only): wavy dotted circles ----
	if (!is_ceiling && quality >= 1.5) {
		for (int k = 0; k < 16; k++) {
			if (k >= ring_count) {
				break;
			}
			vec4 g0 = texelFetch(ring_tex, ivec2(k, 0), 0);
			vec4 g1 = texelFetch(ring_tex, ivec2(k, 1), 0);
			float R = g0.z;
			vec2 d = p - g0.xy;
			float dh = length(d);
			if (abs(dh - R) > R * 0.07 + 4.0 * wpp) {
				continue;
			}
			float a = wrap_angle(d);
			float s = floor(a / TWO_PI * 90.0 + 0.5);
			if (s >= 90.0) {
				s -= 90.0;
			}
			float ths = s / 90.0 * TWO_PI;
			float rw = R * (1.0 + 0.05 * sin(6.0 * ths + t * 1.6 + g1.y));
			vec2 c = g0.xy + vec2(cos(ths), sin(ths)) * rw;
			vec2 cp = to_px(VIEW_MATRIX, PROJECTION_MATRIX, vec3(c.x, wpos.y, c.y), vps);
			if (boil_on > 0.5) {
				int bf = int(t * 10.0) % 4;
				cp += vec2(hash01(int(s) + k * 11, bf) - 0.5, hash01(int(s) + k * 11 + 4096, bf) - 0.5) * wscale;
			}
			vec2 dd = abs(cp - fp);
			float hd = 1.0 * wscale;
			if (dd.x <= hd + 0.5 && dd.y <= hd + 0.5) {
				float al = g1.x < 0.5 ? g0.w * 0.8 : g0.w;
				vec3 col = g1.x < 0.5 ? vec3(1.0, 0.7, 0.65) : (g1.x < 1.5 ? vec3(0.86, 0.82, 1.0) : vec3(0.91, 0.95, 1.0));
				outc += col * al;
			}
		}
	}
	ALBEDO = clamp(outc, 0.0, 1.0);
}
