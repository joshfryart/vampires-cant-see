shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Wall faces drawn as sonar-lit lines on black (js/render.js drawWalls, drawMat, drawDoor, drawWindow, drawWindowGlow).
// Brightness per fragment is sonar.js sample2 at the fragment's world position, read from pulse textures. Line colours
// and alphas use the JS buckets: 4 brightness colours, 8 alpha levels, a soft halo on the bright ones.
#include "res://render/shaders/sonar_common.gdshaderinc"

uniform float boil_amp = 0.8;      // px of top/bottom edge jitter while lit
uniform int boil_frame = 0;        // 0..3, advanced at 10 fps by the game
uniform float boil_on = 1.0;
uniform float line_px = 1.0;       // wall line width in px at 640x360
uniform float line_px_near = 1.5;  // width for walls closer than 1.5 cells and during the arrival flash
uniform float line_px_thin = 0.7;
uniform float halo = 1.0;          // 1 = soft glow behind bright lines (render quality 3)
uniform float mat_detail = 1.0;    // material lines (stone blocks, brick courses, wood grain, fence bars)
uniform float debug_mode = 0.0;    // 1 = output b0 in red, b1 in green (for read-back tests)
uniform float margin_px = 3.0;     // wall quads extend this many px past the top/bottom edge so boiled lines are not clipped
uniform float z_scale = 0.7305835423471995; // world metres per JS height unit (Coords.Z_SCALE)
uniform float focal_px = 492.7;    // 320 / tan(33 deg): px per metre at depth 1
uniform sampler2D light_tex : filter_nearest, repeat_disable; // R = world light per cell
uniform vec2 map_size = vec2(24.0, 16.0);
uniform int arc_trail = 4;         // wall water-ripple arcs per pulse (render quality 3: 4, quality 2: 2, 0 = off)
uniform float vib_on = 1.0;        // struck-surface vibration lines (render.js drawWallVibe)
uniform float reduced_motion = 0.0;
uniform float fx = 2.0;            // effects level after the governor cap (0..2)
uniform float fx_taper = 1.0;      // fx == 2 and quality >= 3: vertical lines thin out toward their ends
uniform float quality = 3.0;       // render quality 0..3
uniform float styled = 0.0;        // 1 = the visible mesh is the contour (ink) mesh: UV2 = grid anchor, UV.x = arc length, COLOR.g = style * 4 + face code (docs/STYLE.md)

// Per-quality switches indexed by quality 0..3. Mirrored (and checked as text) by LineStyle.wall_features.
const vec4 STRATA_Q = vec4(0.0, 0.0, 0.0, 1.0);    // strata, cracks, material ticks (these also need mat_detail)
const vec4 HALO_Q = vec4(0.0, 0.0, 1.0, 2.0);      // 0 none, 1 flash only, 2 full
const vec4 LIP_JAG_Q = vec4(0.0, 0.0, 1.0, 1.0);   // ragged lips (rock, thicket, gorse, drystone)
const vec3 INK_BONE = vec3(1.0, 0.9882, 0.9569);
const vec3 INK_HALO_WARM = vec3(1.0, 0.9255, 0.8235);

const float DOOR_GAIN = 1.35;
const vec3 COL_WOOD_DOOR = vec3(1.0, 0.8863, 0.7686);
const vec3 COL_GATE = vec3(0.9569, 0.9725, 1.0);
const vec3 COL_WIN_LIT = vec3(1.0, 0.8353, 0.5882);
const vec3 COL_WIN_DARK = vec3(0.7686, 0.8863, 1.0);
const vec3 COL_WIN_GLOW = vec3(1.0, 0.8118, 0.5412);
const float WIN_GLOW_MAX = 0.25;
const float WIN_LINGER = 1.5;
const float MAT_B = 0.35;
const float WOBBLE_DUR = 0.45;
const float WOBBLE_FREQ = 34.0;
const float VIB_DUR = 0.9;
const float VIB_HZ = 7.0;
const float VIB_DAMP = 2.6;
const float RIPPLE_V = 4.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
	vec4 vv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(0.05, -vv.z);
	float ext = margin_px * depth / (focal_px * z_scale);
	// move the quad's top/bottom vertices outward and remap v so the edges stay at v = 0 and v = 1
	if (UV.y > 0.5) {
		VERTEX.y += margin_px * depth / focal_px;
		UV.y = 1.0 + ext;
	} else {
		VERTEX.y -= margin_px * depth / focal_px;
		UV.y = -ext;
	}
}

float tent(float d_px, float width) {
	// anti-aliased line of the given width centred where d_px = 0
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

float cell_hash(int cx, int cy, int k) {
	uint x = uint(cx + 7) * 374761393u + uint(cy + 13) * 668265263u + uint(k + 1) * 1274126177u;
	x = (x ^ (x >> 13u)) * 1103515245u;
	return float(x ^ (x >> 16u)) / 4294967296.0;
}

float jitter(float col, float axis) {
	float k = floor(col / 4.0);
	float f = fract(col / 4.0);
	float a = hash11(k * 2.0 + axis + float(boil_frame) * 17.0) * 2.0 - 1.0;
	float b = hash11((k + 1.0) * 2.0 + axis + float(boil_frame) * 17.0) * 2.0 - 1.0;
	return mix(a, b, f);
}

// accumulate one line sample: colour * quantised alpha * coverage, plus the soft halo on bright lines
void put(inout vec3 acc, vec3 col, float a, float cov, float halo_cov) {
	float aq = qalpha(a);
	acc = max(acc, col * aq * cov);
	if (halo > 0.5 && aq >= 0.6) {
		acc = max(acc, col * aq * 0.2 * halo_cov);
	}
}


// ---- ink-etched natural / built walls (styled maps, style ids 1..9; docs/STYLE.md section 3) ----

// smooth 1D value noise on a world-anchored coordinate
float vn1(float x, int sd) {
	int i = int(floor(x));
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(cell_hash(i, 97, sd), cell_hash(i + 1, 97, sd), f);
}

// ink brightness curve (LineStyle.ping_lit): keeps faint echoes legible
float ink_lit(float b, float d, float flash) {
	return min(1.0, max(1.15 * pow(b, 0.65), 0.2 + 0.6 * b)) / (1.0 + 0.10 * d) + 0.6 * flash;
}

// the top edge of a wall as a fraction of its height; the material is readable from this alone
float wall_lip(int st, float s, float facing, bool jag) {
	if (st == 1) { // rock: full height, a slightly ragged ceiling line
		return jag ? 1.0 - 0.07 * vn1(s * 2.5, 1) : 1.0;
	} else if (st == 2) { // thicket: spiky peaks every 0.25
		if (!jag) {
			return 0.92;
		}
		float c = s * 4.0;
		float h = 0.5 + 0.5 * cell_hash(int(floor(c)), 31, 2);
		return 0.85 + 0.15 * h * (1.0 - abs(2.0 * fract(c) - 1.0));
	} else if (st == 3) { // gorse: low, with thorn spikes
		float base = 0.70 + 0.15 * vn1(s * 0.8, 3);
		if (!jag) {
			return base;
		}
		float c = s * 4.0;
		float h = cell_hash(int(floor(c)), 32, 3) * 2.0 - 1.0;
		return clamp(base + 0.08 * h * (1.0 - abs(2.0 * fract(c) - 1.0)), 0.6, 0.95);
	} else if (st == 5) { // cairn: conical, high where it faces you
		return 0.75 + 0.25 * sqrt(clamp(facing, 0.0, 1.0));
	} else if (st == 6) { // milestone: domed
		return 0.75 + 0.10 * sqrt(clamp(facing, 0.0, 1.0));
	} else if (st == 9 && jag) { // drystone: nearly level
		return 1.0 - 0.03 * vn1(s * 3.0, 9);
	}
	return 1.0;
}

// rock: strata (x) and cracks / seeps (y) as coverage. s = arc length, v = height from the floor, tilt = strata slope per cell of s.
vec2 rock_detail(float s, float v, float lip, float fws, float fwy, float tilt, float curv, float wd) {
	const float GL = 0.6;
	float g = floor(s / GL);
	int gi = int(g);
	float f = (s - g * GL) / GL;
	float strata = 0.0;
	for (int k = 0; k < 3; k++) {
		if (cell_hash(gi, 21, k) < 0.5) {
			float fs = 0.03 + 0.2 * cell_hash(gi, 22, k);
			float fe = min(1.0, fs + 0.55 + 0.45 * cell_hash(gi, 23, k));
			if (f >= fs && f <= fe) {
				float vk = 0.12 + 0.76 * cell_hash(gi, 24, k) + tilt * (s - (g + 0.5) * GL);
				float endk = clamp(min(f - fs, fe - f) / 0.08, 0.0, 1.0);
				strata = max(strata, tent((v - vk) / fwy, wd) * endk);
			}
		}
	}
	float crack = 0.0;
	float pk = curv > 1.5 ? 0.6 : (curv < -1.5 ? 0.1 : 0.25);
	if (cell_hash(gi, 25, 0) < pk) {
		float cx = (g + 0.2 + 0.6 * cell_hash(gi, 26, 0)) * GL;
		float len = 0.12 + 0.2 * cell_hash(gi, 27, 0);
		float vv = lip - v;
		if (vv >= 0.0 && vv <= len) {
			float wob = 0.03 * sin(v * 22.0 + float(gi));
			crack = tent((s - cx + wob) / fws, wd) * clamp((len - vv) / 0.05, 0.0, 1.0);
		}
	}
	if (curv < -1.5 && cell_hash(gi, 28, 0) < 0.4) { // seeps rise from the floor in recesses
		float cx = (g + 0.25 + 0.5 * cell_hash(gi, 29, 0)) * GL;
		float len = 0.12 + 0.2 * cell_hash(gi, 30, 0);
		if (v >= 0.0 && v <= len) {
			float wob = 0.025 * sin(v * 19.0 + float(gi) * 1.7);
			crack = max(crack, tent((s - cx + wob) / fws, wd) * clamp((len - v) / 0.05, 0.0, 1.0));
		}
	}
	return vec2(strata, crack);
}

// material marks of the other styles (quality 3 + mat_detail); u = position along the cell face 0..1
float mat_marks(int st, float s, float u, float v, float lip, float facing, float al, float fwal, float fws, float fwu, float fwy, float wd) {
	float cov = 0.0;
	if (st == 2) { // thicket: V-shaped leaf ticks in the top 40%, two per cell
		float c = s * 2.0;
		int gi = int(floor(c));
		float x0 = (float(gi) + 0.25 + 0.5 * cell_hash(gi, 61, 0)) * 0.5;
		float vc = max(0.6, lip - 0.28) + 0.12 * cell_hash(gi, 62, 0);
		float dx = abs(s - x0);
		if (dx < 0.07 && vc < lip) {
			cov = tent((v - (vc + 1.1 * dx)) / fwy, wd);
		}
	} else if (st == 3) { // gorse: thorn ticks at 60 degrees, three per cell, upper half
		float c = s * 3.0;
		int gi = int(floor(c));
		float x0 = (float(gi) + 0.15 + 0.4 * cell_hash(gi, 63, 0)) / 3.0;
		float vb = 0.45 + 0.2 * cell_hash(gi, 64, 0);
		float dx = s - x0;
		if (dx >= 0.0 && dx <= 0.08 && vb < lip) {
			cov = tent((v - (vb + 1.73 * dx)) / fwy, wd);
		}
	} else if (st == 4) { // trunk: two wavy bark lines per cell
		float c = s * 2.0;
		int gi = int(floor(c));
		float x0 = (float(gi) + 0.3 + 0.4 * cell_hash(gi, 65, 0)) * 0.5 + 0.012 * sin(v * 13.0 + cell_hash(gi, 66, 0) * 6.0);
		if (v >= 0.3 && v <= 0.7) {
			cov = tent((s - x0) / fws, wd) * clamp(min(v - 0.3, 0.7 - v) / 0.06, 0.0, 1.0);
		}
	} else if (st == 5) { // cairn: stacked lens courses, staggered joints, narrowing upward
		for (int k = 0; k < 4; k++) {
			float hk = 0.2 * float(k + 1);
			if (facing > 0.15 + 0.17 * float(k) && hk < lip - 0.04) {
				cov = max(cov, tent((v - hk) / fwy, wd));
			}
		}
		int band = clamp(int(floor(v / 0.2)), 0, 3);
		float off = 0.225 * float(band & 1);
		float x0 = (floor((s - off) / 0.45) + 0.5) * 0.45 + off;
		float vlo = 0.2 * float(band);
		if (facing > 0.15 + 0.17 * float(band) && vlo + 0.2 < lip && v > vlo + 0.02 && v < vlo + 0.18) {
			cov = max(cov, tent((s - x0) / fws, wd));
		}
	} else if (st == 6) { // milestone: one incised line and three mile ticks
		if (u >= 0.12 && u <= 0.88) {
			cov = tent((v - 0.6) / fwy, wd);
		}
		if (v >= 0.6 && v <= 0.72) {
			cov = max(cov, max(tent((u - 0.38) / fwu, wd), max(tent((u - 0.5) / fwu, wd), tent((u - 0.62) / fwu, wd))));
		}
	} else if (st == 8) { // timber: weatherboard every 0.2 h, studs every 2 cells
		for (int k = 1; k < 5; k++) {
			cov = max(cov, tent((v - 0.2 * float(k)) / fwy, wd));
		}
		cov = max(cov, tent(abs(al - 2.0 * round(al * 0.5)) / fwal, wd));
	} else if (st == 9) { // drystone: three irregular courses, one staggered joint per 0.8 cell
		float c1 = 0.33 + 0.05 * (vn1(s * 1.1, 11) - 0.5);
		float c2 = 0.66 + 0.05 * (vn1(s * 1.1, 12) - 0.5);
		cov = max(tent((v - c1) / fwy, wd), tent((v - c2) / fwy, wd));
		int course = v < c1 ? 0 : (v < c2 ? 1 : 2);
		int gi = int(floor(s / 0.8));
		float xj = (float(gi) + 0.15 + 0.7 * cell_hash(gi, 67, course)) * 0.8;
		float lo = course == 0 ? 0.0 : (course == 1 ? c1 : c2);
		float hi = course == 0 ? c1 : (course == 1 ? c2 : 1.0);
		if (v > lo + 0.02 && v < hi - 0.02) {
			cov = max(cov, tent((s - xj) / fws, wd));
		}
	}
	return cov;
}

// put() with a configurable halo strength (ink uses 0.16)
void put_k(inout vec3 acc, vec3 col, float a, float cov, float halo_cov, float halo_k) {
	float aq = qalpha(a);
	acc = max(acc, col * aq * cov);
	if (halo > 0.5 && aq >= 0.6) {
		acc = max(acc, col * aq * halo_k * halo_cov);
	}
}

void fragment() {
	// styled (contour) mesh: COLOR.g = style * 4 + face code, UV2 = grid anchor, UV.x = arc length. Light, cell and ripple maths use the anchor and grid normal.
	bool sty = styled > 0.5;
	int gc = int(floor(COLOR.g * 255.0 + 0.5));
	int style = sty ? gc / 4 : 0;
	vec3 ngv = wnorm;
	if (sty) {
		int fc = gc - style * 4;
		ngv = fc == 0 ? vec3(0.0, 0.0, -1.0) : (fc == 1 ? vec3(0.0, 0.0, 1.0) : (fc == 2 ? vec3(-1.0, 0.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	}
	vec2 p = sty ? UV2 : wpos.xz;
	bool x_face = abs(ngv.x) > 0.5;
	float along = x_face ? p.y : p.x;
	float u = UV.x;
	if (sty) {
		float sg = x_face ? ngv.x : -ngv.z;
		float ca = floor(along - sg * 1e-4);
		u = sg > 0.0 ? along - ca : ca + 1.0 - along;
	}
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	int qi = int(clamp(quality, 0.0, 3.0) + 0.5);
	vec2 nvv = vec2(0.0, 1.0);
	float sil = 0.0;
	float lip = 1.0;
	if (style > 0) {
		nvv = normalize(wnorm.xz + vec2(1e-6));
		sil = dot(nvv, normalize(cam_pos.xz - wpos.xz + vec2(1e-6)));
		lip = wall_lip(style, UV.x, abs(sil), LIP_JAG_Q[qi] > 0.5);
		if (lip < 0.999 && UV.y > lip) {
			discard; // low walls (gorse, cairns, milestones) read by their outline
		}
	}
	int code = int(floor(COLOR.b * 255.0 + 0.5));
	bool is_door = code == 68 || code == 71;
	bool is_gate = code == 71;
	bool is_window = code == 119;
	// window faces linger longer (render.js drawWalls: pf * WIN_LINGER)
	vec4 L = sonar_wall_light(p, game_time, is_window ? WIN_LINGER : 1.0);
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
		float vt = 1.0 - UV.y;                 // height fraction, top 0 .. bottom 1 (as the JS detail code)
		float fwy = max(fwidth(UV.y), 1e-5);
		float fwx = max(fwidth(u), 1e-5);
		float col_i = floor(FRAGCOORD.x / 2.0);
		float jb = boil_on * boil_amp * jitter(col_i, 1.0);
		float jt = boil_on * boil_amp * jitter(col_i, 0.0);
		float flash = (age >= 0.0 && age < FLASH_AGE) ? 1.0 - age / FLASH_AGE : 0.0;
		float hp_px = 360.0 / depth;           // projected wall height in px
		// the struck surface quivers for a moment after the front passes (render.js Ripple.wobble on both edges)
		float wob_px = 0.0;
		if (age >= 0.0 && age < WOBBLE_DUR) {
			float wk = 1.0 - age / WOBBLE_DUR;
			wob_px = sin(age * WOBBLE_FREQ + (wpos.x + wpos.z) * 5.0) * wk * wk * clamp(hp_px * 0.02, 0.8, 3.5);
		}
		float w_wall = (depth < 1.5 || flash > 0.0) ? line_px_near : line_px;

		ivec2 cell = ivec2(floor(p - ngv.xz * 0.01));
		vec3 outc = vec3(0.0);

		if (style == 0) {
		// ---- top and bottom edge lines (a crooked door's top edge sags like the JS tilt) ----
		float tilt_px = is_door ? hp_px * 0.05 * (u * (1.0 - u) * 4.0) * (0.4 + 0.6 * u) : 0.0;
		vec3 edge_col_door = is_gate ? COL_GATE : COL_WOOD_DOOR;
		if (b0 > 0.01) {
			float a = line_alpha(b0, depth);
			if (is_door && flash <= 0.0) {
				a = min(1.0, a * DOOR_GAIN);
			}
			a = min(1.0, a + 0.6 * flash);
			vec3 col = flash > 0.0 ? vec3(1.0) : (is_door ? edge_col_door : bucket_col(b0));
			float d = (UV.y / fwy + jb + wob_px) - w_wall * 0.5;
			put(outc, col, a, tent(d, w_wall), tent(d, w_wall * 3.4));
		}
		if (b1 > 0.01) {
			float a = line_alpha(b1, depth);
			if (is_door && flash <= 0.0) {
				a = min(1.0, a * DOOR_GAIN);
			}
			a = min(1.0, a + 0.6 * flash);
			vec3 col = flash > 0.0 ? vec3(1.0) : (is_door ? edge_col_door : bucket_col(b1));
			float d = ((1.0 - UV.y) / fwy + jt - tilt_px + wob_px) - w_wall * 0.5;
			put(outc, col, a, tent(d, w_wall), tent(d, w_wall * 3.4));
		}

		// ---- vertical lines at the face ends: full strength at corners, 0.35 where the wall continues flush ----
		float side_u = u < 0.5 ? u : 1.0 - u;
		float strength = sty ? COLOR.r : (u < 0.5 ? COLOR.r : COLOR.g);
		float bv = vt < 0.5 ? mix(b0, b1, 0.75) : mix(b0, b1, 0.25);
		if (bv > 0.01) {
			float a = line_alpha(bv, depth) * strength;
			a = min(1.0, a + 0.5 * flash * strength);
			vec3 col = flash > 0.0 ? vec3(1.0) : bucket_col(bv);
			float wv = w_wall;
			if (fx_taper > 0.5 && (vt < 0.15 || vt > 0.85)) {
				wv = line_px_thin; // JS vert(): outer 30% of each half goes to the thin width class
			}
			float d = side_u / fwx - wv * 0.5;
			put(outc, col, a, tent(d, wv), tent(d, wv * 3.4));
		}

		} else {
			// ---- ink walls (styles 1..9): contour edges, silhouette, corner posts, lit body ----
			float fdetail = line_px * 0.8;
			float cw = qi >= 2 ? 1.25 + 0.5 * clamp((2.5 - depth) / 1.5, 0.0, 1.0) : (qi == 1 ? 1.25 : 1.0);
			cw = (cw + 0.5 * flash) * line_px;
			float jbi = jb * 0.625;
			float jti = jt * 0.625;
			float halo_f = HALO_Q[qi];
			bool has_top = style != 4 && style != 7;
			if (b0 > 0.01) {
				bool gap = style == 2 && cell_hash(int(floor(UV.x / 0.3)), 55, 1) < 0.15; // thicket: the foot is broken
				if (!gap) {
					float a = ink_lit(b0, depth, flash);
					vec3 col = flash > 0.0 ? INK_BONE : bucket_col(b0);
					float d = (UV.y / fwy + jbi + wob_px) - cw * 0.5;
					put_k(outc, col, a, tent(d, cw), halo_f > 1.5 ? tent(d, cw * 3.0) : 0.0, 0.16);
				}
			}
			if (b1 > 0.01 && has_top) {
				float a = ink_lit(b1, depth, flash);
				vec3 col = flash > 0.0 ? INK_BONE : bucket_col(b1);
				float d = ((lip - UV.y) / fwy + jti + wob_px) - cw * 0.5;
				put_k(outc, col, a, tent(d, cw), halo_f > 1.5 ? tent(d, cw * 3.0) : 0.0, 0.16);
				if (flash > 0.0 && halo_f > 0.5) {
					outc = max(outc, INK_HALO_WARM * 0.35 * flash * tent(d, cw * 3.0));
				}
			}
			// silhouette: where the surface turns edge-on (pillars, passage mouths); thins toward both ends
			float bm = 0.5 * (b0 + b1);
			if (bm > 0.01 && UV.y >= 0.0 && UV.y <= min(lip, 1.0)) {
				float wv = fx_taper > 0.5 ? cw * clamp(min(UV.y, lip - UV.y) / 0.14, 0.35, 1.0) : cw;
				float d = abs(sil) / max(fwidth(sil), 1e-5) - wv * 0.5;
				vec3 col = flash > 0.0 ? INK_BONE : bucket_col(bm);
				put_k(outc, col, ink_lit(bm, depth, flash), tent(d, wv), halo_f > 1.5 ? tent(d, wv * 3.0) : 0.0, 0.16);
			}
			// built faces: a post only at real convex corners (COLOR.r = 1)
			if (style >= 6 && bm > 0.01 && UV.y <= min(lip, 1.0)) {
				float dr = (1.0 - COLOR.r) / max(fwidth(COLOR.r), 1e-4) - cw * 0.5;
				put_k(outc, bucket_col(bm), ink_lit(bm, depth, flash), tent(dr, cw), 0.0, 0.16);
			}
			// dark body with a faint lit tint (quality 2 and 3)
			if (qi >= 2 && UV.y >= 0.0 && UV.y <= min(lip, 1.0)) {
				outc = max(outc, C_MID * 0.06 * sqrt(min(b, 1.0)) / (1.0 + 0.08 * depth));
			}
		}

		if (vt >= 0.0 && vt <= 1.0) {
			// brightness at this height for detail lines: top edge = b1, bottom edge = b0 (JS matH / matV / dH / dV)
			float bd = mix(b1, b0, vt);

			// ---- material detail ----
			if (style == 0 && mat_detail > 0.5 && b > MAT_B && !is_door && !is_window) {
				float a = line_alpha(bd, depth) * 0.6;
				if (bd >= 0.1 && a >= 0.04) {
					vec3 col = bucket_col(bd);
					float wd = code == 73 ? line_px : line_px_thin;
					float cov = 0.0;
					if (code == 35) { // stone: irregular blocks
						float v1 = 0.3 + 0.14 * (cell_hash(cell.x, cell.y, 1) - 0.5);
						float v2 = 0.66 + 0.14 * (cell_hash(cell.x, cell.y, 2) - 0.5);
						float w1 = boil_on * jitter(col_i, 1.0) * 0.006;
						float l1 = mix(v1 + w1, v1 + 0.015 * (cell_hash(cell.x, cell.y, 5) - 0.5) - w1, u);
						float l2 = mix(v2, v2 + 0.02 * (cell_hash(cell.x, cell.y, 6) - 0.5) + w1, u);
						cov = max(tent((vt - l1) / fwy, wd), tent((vt - l2) / fwy, wd));
						if (fx >= 0.5) {
							// texture: two short slanted hatch strokes per block, low in the block (render.js drawMat, fx >= 1)
							for (int hk = 0; hk < 2; hk++) {
								float hu = 0.1 + 0.7 * cell_hash(cell.x, cell.y, 9 + hk);
								if (u >= hu && u <= hu + 0.1) {
									float hv = 0.7 + 0.12 * float(hk) + 0.08 * cell_hash(cell.x, cell.y, 11 + hk);
									cov = max(cov, tent((vt - (hv + 0.5 * (u - hu))) / fwy, wd));
								}
							}
						}
						float j0 = 0.2 + 0.6 * cell_hash(cell.x, cell.y, 3);
						float j1 = 0.2 + 0.6 * cell_hash(cell.x, cell.y, 4);
						float j2 = 0.2 + 0.6 * cell_hash(cell.x, cell.y, 7);
						if (vt >= 0.02 && vt <= v1) {
							cov = max(cov, tent((u - j0) / fwx, wd));
						} else if (vt > v1 && vt <= v2) {
							cov = max(cov, tent((u - j1) / fwx, wd));
						} else if (vt > v2 && vt <= 0.98) {
							cov = max(cov, tent((u - j2) / fwx, wd));
						}
					} else if (code == 66) { // brick: coursing and staggered joints
						cov = max(tent((vt - 0.25) / fwy, wd), max(tent((vt - 0.5) / fwy, wd), tent((vt - 0.75) / fwy, wd)));
						float row = floor(vt * 4.0);
						float in_row = vt - row * 0.25;
						if (in_row >= 0.01 && in_row <= 0.24 && row < 4.0) {
							if (mod(row, 2.0) > 0.5) {
								cov = max(cov, tent((u - 0.5) / fwx, wd));
							} else {
								cov = max(cov, max(tent((u - 0.25) / fwx, wd), tent((u - 0.75) / fwx, wd)));
							}
						}
					} else if (code == 87) { // wood: grain squiggles
						float ph = cell_hash(cell.x, cell.y, 8) * 6.0;
						// texture: grain drawn as dashes, skipped on every other column pair (render.js drawMat)
						bool dash_gap = fx >= 0.5 && (int(floor((col_i + 1.0) * 0.5)) & 1) != 0;
						for (int k = 0; k < 3; k++) {
							if (dash_gap) {
								break;
							}
							float lv = 0.2 + float(k) * 0.3 + 0.03 * sin(along * 11.0 + ph + float(k) * 2.1);
							cov = max(cov, tent((vt - lv) / fwy, wd));
						}
					} else if (code == 73) { // iron fence: rails and bars
						cov = max(tent((vt - 0.14) / fwy, wd), tent((vt - 0.86) / fwy, wd));
						if (vt >= 0.14 && vt <= 0.86) {
							for (int k = 0; k < 5; k++) {
								cov = max(cov, tent((u - (0.1 + float(k) * 0.2)) / fwx, wd));
							}
						}
					}
					if (cov > 0.0) {
						put(outc, col, a, cov, 0.0);
					}
				}
			}

				// ---- ink material detail (styles 1..9) ----
				if (style > 0 && !is_door && !is_window) {
					float fws = max(fwidth(UV.x), 1e-5);
					float fwu = max(fwidth(u), 1e-5);
					float fwal = max(fwidth(along), 1e-5);
					float facing = abs(sil);
					float wd = line_px * 0.8;
					if (style == 7 && bd >= 0.1) { // fence: two rails and posts (always drawn)
						float a = ink_lit(bd, depth, 0.0) * 0.85;
						float cov = max(tent((UV.y - 0.3) / fwy, wd), tent((UV.y - 0.7) / fwy, wd));
						if (UV.y >= 0.08 && UV.y <= 0.9) {
							cov = max(cov, max(tent((u - 0.04) / fwu, wd), max(tent((u - 0.5) / fwu, wd), tent((u - 0.96) / fwu, wd))));
						}
						put_k(outc, bucket_col(bd), a, cov, 0.0, 0.16);
					}
					if (STRATA_Q[qi] > 0.5 && mat_detail > 0.5 && b > MAT_B && bd >= 0.2) {
						float a = ink_lit(bd, depth, 0.0) * 0.6;
						vec3 col = bucket_col(bd);
						float curv = (COLOR.r - 0.5) * 8.0; // signed curvature per cell: convex > 0 (ContourField.CURV_RANGE = 4)
						if (style == 1) {
							float ang = TWO_PI * cell_hash(int(floor(p.x / 8.0)), int(floor(p.y / 8.0)), 41);
							float dip = radians(5.0 + 8.0 * cell_hash(int(floor(p.x / 8.0)), int(floor(p.y / 8.0)), 42));
							vec2 tg = vec2(-nvv.y, nvv.x);
							float tilt = tan(dip) * dot(tg, vec2(cos(ang), sin(ang))) / z_scale;
							vec2 rc = rock_detail(UV.x, UV.y, lip, fws, fwy, tilt, curv, line_px * 0.7);
							float fk = (0.35 + 0.65 * facing);
							float st_a = a * fk * (1.0 - smoothstep(5.0, 7.0, depth));
							float cr_a = a * (1.0 - smoothstep(3.5, 5.0, depth));
							if (rc.x > 0.0 && st_a >= 0.04) {
								put_k(outc, col, st_a, rc.x, 0.0, 0.16);
							}
							if (rc.y > 0.0 && cr_a >= 0.04) {
								put_k(outc, col, cr_a, rc.y, 0.0, 0.16);
							}
						} else {
							float cov = mat_marks(style, UV.x, u, UV.y, lip, facing, along, fwal, fws, fwu, fwy, wd);
							if (cov > 0.0) {
								put_k(outc, col, a, cov, 0.0, 0.16);
							}
						}
					}
				}

			// ---- doors and gates ----
			if (is_door && b > 0.12 && bd >= 0.08) {
				float pm = (reduced_motion < 0.5 && age >= 0.0 && age < 0.4) ? 1.0 + 0.5 * sin(PI * age / 0.4) : 1.0;
				vec3 col = is_gate ? COL_GATE : COL_WOOD_DOOR;
				float f = pm * DOOR_GAIN;
				float d_ = DOOR_GAIN;
				float a_line = line_alpha(bd, depth);
				float cov = 0.0;
				// outer frame: lintel and jambs (thick), inset inner frame (thin)
				if (u >= 0.1 && u <= 0.9) {
					cov = max(cov, tent((vt - 0.07) / fwy, line_px_near));
				}
				if (vt >= 0.07) {
					cov = max(cov, max(tent((u - 0.1) / fwx, line_px_near), tent((u - 0.9) / fwx, line_px_near)));
				}
				put(outc, col, min(1.0, a_line * f), cov, 0.0);
				cov = 0.0;
				if (u >= 0.17 && u <= 0.83) {
					cov = max(cov, tent((vt - 0.16) / fwy, line_px_thin));
				}
				if (vt >= 0.16) {
					cov = max(cov, max(tent((u - 0.17) / fwx, line_px_thin), tent((u - 0.83) / fwx, line_px_thin)));
				}
				put(outc, col, min(1.0, a_line * d_ * 0.8), cov, 0.0);
				if (is_gate) {
					// spear-tipped bars with gaps, three crossbars
					if (u >= 0.17 && u <= 0.83) {
						put(outc, col, min(1.0, a_line * d_), max(tent((vt - 0.22) / fwy, line_px), tent((vt - 0.55) / fwy, line_px)), 0.0);
						put(outc, col, min(1.0, a_line * d_ * 0.8), tent((vt - 0.9) / fwy, line_px_thin), 0.0);
					}
					float bars = 0.0;
					float tips = 0.0;
					for (int k = 0; k < 7; k++) {
						float ub = 0.23 + float(k) * 0.09;
						if (vt >= 0.22) {
							bars = max(bars, tent((u - ub) / fwx, line_px_thin));
						} else if (vt >= 0.08) {
							tips = max(tips, tent((u - ub) / fwx, line_px));
						}
					}
					put(outc, col, min(1.0, a_line * d_), bars, 0.0);
					put(outc, col, min(1.0, a_line * d_ * pm), tips, 0.0);
				} else {
					// planks, hinge straps (left), ring handle (right)
					if (vt >= 0.16) {
						float pl = max(tent((u - 0.33) / fwx, line_px_thin), max(tent((u - 0.5) / fwx, line_px_thin), tent((u - 0.67) / fwx, line_px_thin)));
						put(outc, col, min(1.0, a_line * d_ * 0.7), pl, 0.0);
					}
					if (u >= 0.17 && u <= 0.42) {
						put(outc, col, min(1.0, a_line * d_), max(tent((vt - 0.3) / fwy, line_px_near), tent((vt - 0.78) / fwy, line_px_near)), 0.0);
					}
					if (vt >= 0.5 && vt <= 0.62) {
						put(outc, col, min(1.0, a_line * d_), max(tent((u - 0.6) / fwx, line_px_near), tent((u - 0.7) / fwx, line_px_near)), 0.0);
					}
					if (u >= 0.6 && u <= 0.7) {
						put(outc, col, min(1.0, a_line * d_), max(tent((vt - 0.5) / fwy, line_px_near), tent((vt - 0.62) / fwy, line_px_near)), 0.0);
					}
				}
				// link doors (lead to another map): keystone on the lintel and two stud ticks
				if (COLOR.a > 0.5) {
					float ks = 0.0;
					if (vt <= 0.07) {
						ks = max(ks, max(tent((u - 0.44) / fwx, line_px_near), tent((u - 0.56) / fwx, line_px_near)));
					}
					if (u >= 0.44 && u <= 0.56) {
						ks = max(ks, tent(vt / fwy, line_px_near));
					}
					put(outc, col, min(1.0, a_line * f), ks, 0.0);
					if (vt <= 0.05) {
						put(outc, col, min(1.0, a_line * f), max(tent((u - 0.3) / fwx, line_px), tent((u - 0.7) / fwx, line_px)), 0.0);
					}
				}
			}

			// ---- windows ----
			if (is_window) {
				vec2 beyond = vec2(float(cell.x) + 0.5 - ngv.x, float(cell.y) + 0.5 - ngv.z);
				float lit_v = 0.0;
				if (beyond.x >= 0.0 && beyond.y >= 0.0 && beyond.x < map_size.x && beyond.y < map_size.y) {
					lit_v = texelFetch(light_tex, ivec2(int(beyond.x), int(beyond.y)), 0).r;
				}
				lit_v = lit_v > 0.05 ? min(1.0, lit_v) : 0.0;
				bool lit = lit_v > 0.0;
				if (b > 0.12 && bd >= 0.08) {
					vec3 col = lit ? COL_WIN_LIT : COL_WIN_DARK;
					float pm = (reduced_motion < 0.5 && age >= 0.0 && age < 0.4) ? 1.0 + 0.4 * sin(PI * age / 0.4) : 1.0;
					float G = 1.25 * pm;
					float bow = (u - 0.5) * 0.05;
					float a_line = line_alpha(bd, depth);
					if (u >= 0.16 && u <= 0.84) {
						float cov = max(tent((vt - (0.16 + bow)) / fwy, line_px_near), tent((vt - (0.8 + bow * 0.6)) / fwy, line_px_near));
						put(outc, col, min(1.0, a_line * G), cov, 0.0);
						put(outc, col, min(1.0, a_line * G * 0.8), tent((vt - (0.48 + bow * 0.8)) / fwy, line_px_thin), 0.0);
					}
					if (vt >= 0.16 && vt <= 0.8) {
						put(outc, col, min(1.0, a_line * G), max(tent((u - 0.16) / fwx, line_px_near), tent((u - 0.84) / fwx, line_px_near)), 0.0);
						put(outc, col, min(1.0, a_line * G * 0.8), tent((u - 0.5) / fwx, line_px_thin), 0.0);
					}
					if (u >= 0.08 && u <= 0.92) {
						put(outc, col, min(1.0, a_line * G), tent((vt - (0.87 + bow * 0.5)) / fwy, line_px_near), 0.0);
					}
					if (vt >= 0.85 && vt <= 0.9) {
						put(outc, col, min(1.0, a_line * G), max(tent((u - 0.08) / fwx, line_px), tent((u - 0.92) / fwx, line_px)), 0.0);
					}
					if (!lit) {
						// two diagonal glints in the top-left pane
						if (u >= 0.22 && u <= 0.4) {
							float dl = (vt - (0.22 + (u - 0.22) * 1.3)) / fwy / sqrt(1.0 + 1.69);
							put(outc, col, min(1.0, a_line * G), tent(dl, line_px), 0.0);
						}
						if (u >= 0.22 && u <= 0.32) {
							float dl2 = (vt - (0.32 + (u - 0.22) * 1.3)) / fwy / sqrt(1.0 + 1.69);
							put(outc, col, min(1.0, a_line * G), tent(dl2, line_px_thin), 0.0);
						}
					}
				}
				// one seeded glint per window: two crossed strokes that fade once with the afterglow (fx 2, quality >= 2; render.js drawWindow)
				if (fx > 1.5 && quality >= 1.5 && age >= 0.0) {
					float ga = 0.3 * glow(age, glow_dur(L.w)) * min(1.0, line_alpha(b, depth) * 2.0);
					if (ga >= 0.04) {
						float gu = 0.2 + 0.6 * cell_hash(cell.x, cell.y, 11);
						float gv = 0.2 + 0.5 * cell_hash(cell.x, cell.y, 12);
						float gx = (u - gu) / fwx;
						float gy = (vt - gv) / fwy;
						if (abs(gx) <= 1.5 && abs(gy) <= 1.5) {
							float gd = min(abs(gx - gy), abs(gx + gy)) * 0.7071;
							put(outc, (lit ? COL_WIN_LIT : COL_WIN_DARK), min(0.25, ga), tent(gd, line_px_thin), 0.0);
						}
					}
				}
				// candle glow in the panes of a lit window while a ripple passes
				if (lit && hp_px >= 6.0 && u > 0.17 && u < 0.83 && !(u > 0.47 && u < 0.53)) {
					float v = lit_v * min(b, 1.0);
					float ga = min(WIN_GLOW_MAX, (0.06 + 0.19 * v) / (1.0 + 0.05 * depth));
					float sk = (u - 0.5) * 0.05;
					bool in_pane = (vt >= 0.17 + sk && vt <= 0.47 + sk) || (vt >= 0.51 + sk && vt <= 0.79 + sk);
					if (in_pane) {
						outc = max(outc, COL_WIN_GLOW * ga);
					}
				}
			}
		}

		if (vt >= 0.0 && vt <= 1.0 && b >= 0.04 && !is_door) {
			// camera heading and the ray from the camera to this fragment (render.js h.rayAngle)
			vec2 fwd2 = normalize(-INV_VIEW_MATRIX[2].xz);
			vec2 ray = normalize(wpos.xz - cam_pos.xz);
			float cinc = abs(x_face ? ray.x : ray.y);
			float inc_k = max(0.25, 1.0 - cinc);
			float sc = 640.0 / 800.0;

			// ---- struck surfaces shiver: horizontal contour lines, a damped 7 Hz sine for ~0.9 s (drawWallVibe) ----
			if (vib_on > 0.5) {
				for (int i = 0; i < 64; i++) {
					if (i >= pulse_count) {
						break;
					}
					vec4 r0 = texelFetch(pulse_tex, ivec2(i, 0), 0);
					vec4 r1 = texelFetch(pulse_tex, ivec2(i, 1), 0);
					vec4 r2 = texelFetch(pulse_tex, ivec2(i, 2), 0);
					if (r2.y < 0.5 || r2.w > 0.5) {
						continue; // primary pings only (those have a mouth beam)
					}
					float el = game_time - r0.w;
					if (el < 0.0 || el > r1.x / r1.y + VIB_DUR) {
						continue;
					}
					vec2 dd = p - r0.xy;
					float dist_p = length(dd);
					float age_v = el - dist_p / r1.y;
					if (age_v < 0.0 || age_v > VIB_DUR) {
						continue;
					}
					float n = r2.x;
					float aa = atan(dd.y, dd.x);
					if (aa < 0.0) {
						aa += TWO_PI;
					}
					int ri = int(min(n - 1.0, floor(aa / TWO_PI * n + 0.5)));
					vec2 vb = texelFetch(vis_tex, ivec2(ri, i), 0).rg;
					float gb = vb.y;
					if (dist_p > r1.x * (0.3 + 0.7 * gb) || dist_p > vb.x + TOL) {
						continue;
					}
					float env = exp(-age_v * VIB_DAMP) * (1.0 - age_v / VIB_DUR);
					float kv = env * gb * max(0.0, 1.0 - dist_p / r1.x) * (0.5 + 0.5 * inc_k) * min(1.0, r1.w);
					if (kv < 0.015) {
						continue;
					}
					float sh = reduced_motion > 0.5 ? 0.0 : sin(TWO_PI * VIB_HZ * age_v);
					float amp = min(14.0 * sc, 0.11 * focal_px / max(0.3, depth)) * sh;
					float vy_px = (ngv.x * fwd2.x + ngv.z * fwd2.y) * 0.8 * amp;
					float a = min(1.0, 2.2 * kv);
					float cov = 0.0;
					for (int j = 0; j < 5; j++) {
						float f = float(j) * 0.25;
						cov = max(cov, tent((UV.y - f) / fwy - vy_px, line_px_thin));
					}
					put(outc, vec3(0.91, 0.95, 1.0), a, cov, 0.0);
				}
			}

			// ---- water ripples spreading over the wall face from the point nearest the sound (drawWallArcs) ----
			if (arc_trail > 0) {
				int pi_best = -1;
				float b_best = 0.0;
				for (int i = 0; i < 64; i++) {
					if (i >= pulse_count) {
						break;
					}
					vec4 r0 = texelFetch(pulse_tex, ivec2(i, 0), 0);
					vec4 r1 = texelFetch(pulse_tex, ivec2(i, 1), 0);
					vec4 r2 = texelFetch(pulse_tex, ivec2(i, 2), 0);
					vec2 dd = p - r0.xy;
					float dist_p = length(dd);
					if (dist_p > r1.x) {
						continue;
					}
					float age_p = game_time - (r0.w + dist_p / r1.y);
					if (age_p < 0.0 || age_p >= r1.z) {
						continue;
					}
					float kb = 1.0 - age_p / r1.z;
					kb = kb * kb * (1.0 - 0.5 * dist_p / r1.x) * r1.w;
					if (kb <= b_best) {
						continue;
					}
					float aa = atan(dd.y, dd.x);
					if (aa < 0.0) {
						aa += TWO_PI;
					}
					int ri = int(min(r2.x - 1.0, floor(aa / TWO_PI * r2.x + 0.5)));
					if (dist_p > texelFetch(vis_tex, ivec2(ri, i), 0).r + TOL) {
						continue;
					}
					b_best = kb;
					pi_best = i;
				}
				if (pi_best >= 0) {
					vec4 r0 = texelFetch(pulse_tex, ivec2(pi_best, 0), 0);
					vec4 r2 = texelFetch(pulse_tex, ivec2(pi_best, 2), 0);
					float spd = texelFetch(pulse_tex, ivec2(pi_best, 1), 0).y;
					float D = x_face ? abs(p.x - r0.x) : abs(p.y - r0.y);
					float s_al = x_face ? abs(p.y - r0.y) : abs(p.x - r0.x);
					float t0p = r0.w + D / spd;
					if (game_time > t0p) {
						bool bounce = r2.w > 0.5;
						int tk = (depth < 3.0 && arc_trail > 2) ? 2 : arc_trail;
						float ring = (game_time - t0p) * RIPPLE_V;
						float cov6 = 0.0;
						float a_k = 0.0;
						for (int k = 0; k < 4; k++) {
							if (k >= tk) {
								break;
							}
							float R = ring - float(k) * 0.35;
							if (!(R > 0.0 && R * R > s_al * s_al)) {
								continue;
							}
							float dz = sqrt(R * R - s_al * s_al);
							float zl = max(0.0, r0.z - dz);
							float zh = min(1.0, r0.z + dz);
							float ak = min(1.0, line_alpha(b, depth) * 0.9 * inc_k * (1.0 - float(k) / float(tk)) * (bounce ? 0.8 : 1.0));
							if (ak <= 0.03) {
								continue;
							}
							float wcls = bounce ? line_px_thin : (depth < 1.5 ? line_px_near : line_px);
							float cv = 0.0;
							if (zl > 0.002 && zl < 0.998) {
								cv = max(cv, tent((UV.y - zl) / fwy, wcls));
							}
							if (zh > 0.002 && zh < 0.998 && zh != zl) {
								cv = max(cv, tent((UV.y - zh) / fwy, wcls));
							}
							if (cv > cov6) {
								cov6 = cv;
								a_k = ak;
							}
						}
						if (cov6 > 0.0) {
							put(outc, bounce ? vec3(0.4980, 0.6510, 1.0) : vec3(0.8118, 0.8902, 1.0), a_k, cov6, 0.0);
						}
					}
				}
			}
		}

		// the margin past the face only exists so boiled lines are not clipped; do not black out the floor with it
		if ((UV.y < 0.0 || UV.y > 1.0) && max(outc.r, max(outc.g, outc.b)) < 0.004) {
			discard;
		}
		ALBEDO = outc;
	}
}
