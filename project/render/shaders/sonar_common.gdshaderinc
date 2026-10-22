// Shared sonar maths for the wall and floor shaders. Mirrors js/sonar.js sample2 and js/render.js colour/afterglow.
// Pulse data comes from PulseTextures (row layout documented there).

uniform sampler2D pulse_tex : filter_nearest, repeat_disable;
uniform sampler2D vis_tex : filter_nearest, repeat_disable;
uniform int pulse_count = 0;
uniform float game_time = 0.0;

const float TWO_PI = 6.283185307179586;
const float TOL = 0.35;
const float FLASH_AGE = 0.12;
const vec3 C_LOW = vec3(91.0, 127.0, 214.0) / 255.0;
const vec3 C_MID = vec3(207.0, 227.0, 255.0) / 255.0;
const vec3 C_HI = vec3(242.0, 248.0, 255.0) / 255.0;

// Afterglow (render.js glowDur / glow / glowMul): the sonar's long fade is replaced by a short glow behind the front.
float glow_dur(float fade) {
	float f = fade > 0.0 ? fade : 3.0;
	return clamp(f * 0.18, 0.2, 1.0);
}

float glow(float age, float dur) {
	if (!(age >= 0.0) || age >= dur) {
		return 0.0;
	}
	float k = 1.0 - age / dur;
	return k * k * (3.0 - 2.0 * k);
}

float glow_mul(float age, float fade) {
	float g = glow(age, glow_dur(fade));
	if (g <= 0.0) {
		return 0.0;
	}
	float f = fade > 0.0 ? fade : 3.0;
	float kf = 1.0 - age / f;
	return kf > 0.05 ? g / (kf * kf) : g;
}

// render.js fadeStyle: cool blue tail to pale white.
vec3 fade_color(float b) {
	if (b < 0.12) {
		return C_LOW;
	} else if (b < 0.45) {
		return mix(C_LOW, C_MID, (b - 0.12) / 0.33);
	} else if (b < 0.8) {
		return mix(C_MID, C_HI, (b - 0.45) / 0.35);
	}
	return C_HI;
}

// render.js lineAlpha: brightness and distance depth cue.
float line_alpha(float b, float dist) {
	return min(1.0, 1.15 * pow(b, 0.65)) / (1.0 + 0.12 * dist);
}

// sonar.js sample2 for the wall point p (JS x, y) at time t: (b0 floor edge, b1 ceiling edge, age, fade), before afterglow.
vec4 sonar_sample2(vec2 p, float t) {
	float b0 = 0.0;
	float b1 = 0.0;
	float a0 = -1.0;
	float a1 = -1.0;
	float f0 = 0.0;
	float f1 = 0.0;
	for (int i = 0; i < 64; i++) {
		if (i >= pulse_count) {
			break;
		}
		vec4 r0 = texelFetch(pulse_tex, ivec2(i, 0), 0);
		vec4 r1 = texelFetch(pulse_tex, ivec2(i, 1), 0);
		vec4 r2 = texelFetch(pulse_tex, ivec2(i, 2), 0);
		float rr = (t - r0.w) * r1.y;
		if (rr < 0.0) {
			continue;
		}
		vec2 d = p - r0.xy;
		float dh2 = dot(d, d);
		float rng = r1.x;
		if (dh2 > rng * rng || dh2 > rr * rr + 1.5) {
			continue;
		}
		float n = r2.x;
		float a = atan(d.y, d.x);
		if (a < 0.0) {
			a += TWO_PI;
		}
		float idxf = floor(a / TWO_PI * n + 0.5);
		if (idxf >= n) {
			idxf -= n;
		}
		vec2 vb = texelFetch(vis_tex, ivec2(int(idxf), i), 0).rg;
		if (sqrt(dh2) > vb.x + TOL) {
			continue;
		}
		float mul = r1.w * vb.y;
		for (int e = 0; e < 2; e++) {
			float dz = float(e) - r0.z;
			float d2 = dh2 + dz * dz;
			if (d2 > rng * rng || d2 > rr * rr) {
				continue;
			}
			float dist = sqrt(d2);
			float age = t - (r0.w + dist / r1.y);
			if (age >= r1.z) {
				continue;
			}
			float b = 1.0 - age / r1.z;
			b = b * b * (1.0 - 0.5 * dist / rng) * mul;
			if (e == 0) {
				if (b > b0) {
					b0 = b;
					a0 = age;
					f0 = r1.z;
				}
			} else if (b > b1) {
				b1 = b;
				a1 = age;
				f1 = r1.z;
			}
		}
	}
	bool lit = b0 > 0.0 || b1 > 0.0;
	bool use_lo = b0 >= b1;
	return vec4(b0, b1, lit ? (use_lo ? a0 : a1) : -1.0, lit ? (use_lo ? f0 : f1) : 0.0);
}

// Same, with the afterglow applied (render.js drawWalls): returns (b0, b1, age, 0); zeroed when dark.
vec4 sonar_wall_light(vec2 p, float t, float fade_scale) {
	vec4 s = sonar_sample2(p, t);
	float b = max(s.x, s.y);
	if (b <= 0.01) {
		return vec4(0.0, 0.0, -1.0, 0.0);
	}
	float g = glow_mul(s.z, s.w * fade_scale);
	float c0 = s.x * g;
	float c1 = s.y * g;
	if (max(c0, c1) <= 0.01) {
		return vec4(0.0, 0.0, -1.0, 0.0);
	}
	return vec4(c0, c1, s.z, 0.0);
}

float hash11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}
