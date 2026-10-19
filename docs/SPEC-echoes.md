# Echoes — corrected acoustics specification v0.11

Review of "Echoes — Sound & Sonar Proposal" (Claude Docs rev 16, transcribed to `echo/proposal.md`) against the code in `/home/claude/vcs`. Every number here was recomputed in `echo/calc/spec_v011.py`; none is copied from the proposal. No game file was edited.

**Tags.** The tags below are used on every value.

- **[verified-source]** means an equation or value from a cited reference whose form and arithmetic this review checked against the standard textbook form. This review did not re-open the cited documents.
- **[computed]** means derived here by the stated formula.
- **[estimate]** means engineering judgement, with no measurement behind it.
- **[tuning]** means a gameplay knob with no physical claim.
- **[design decision]** means fixed by the user.

**Scale decision (user, after the proposal).** `cellM = 1.0 m/cell` [design decision], kept as one parameter. Movement speed (3 cells/s = 3 m/s) and sonar range (10 cells = 10 m) do not change.

---

## 1. Inconsistency list

| # | Where (proposal) | What is wrong | Fix |
|---|---|---|---|
| 1 | §3 "L_wall = … −20 log10(2d)" vs §7 "L_e = B(θ) − k_spread log10(max(d,0.5)·CELL_M) …, k_spread = 20 for walls (image distance 2d)" | §7 drops the image-source factor 2. At 1/3/10 m it gives 0.0/−9.5/−20.0 dB, but §7 test 2 expects −6.0/−15.6/−26.0. `d` is in cells, while the test is in metres (at 1.5 m/cell, 1 m is 0.667 cells). | §2.2 Eq. W: −20 log10(2r/r_ref), with r = d·cellM in metres and r_ref = 1 m. |
| 2 | §3 "L_object = … −40 log10 d + TS"; §7 L_e has no TS | Objects and people lose target strength, so a person at 1 m would be as loud as the incident click. | §2.2 Eq. O, with TS per target class and a separate calibration gain G_class. |
| 3 | §7 "B(θ) … applied to outgoing rays and to returning echoes" | The beam is counted twice: −10 dB at 90° and −36 dB at 180° instead of −5/−18. | §2.1: B_tx is applied once, on the outgoing click. The receive side B_rx is a separate model that defaults to 0 dB. |
| 4 | §1 table "0/−1/−3/−5/−8/−13 (fit avg)"; §2 "game 0/−1/−3/−6/−9/−13/−18 … sits between the bare-sphere model and the measured fit"; sphere "−4.3 (bright spot)" at 180° | There are three different tables. The §2 claim is false: at 90° and 120° the game table (−6/−9) is more directional than both the fit average (−5.1/−7.8) and the sphere (−3.4/−6.8). | One canonical table, B_tx = 0/−1/−3/−5/−8/−13/−18 (§2.1). The bright spot is excluded and the reason documented. |
| 5 | §2 "mouth at z ≈ 0.58 of wall height" | `js/data/sounds.js:12` has ping `z: 0.62`. | Use the data value 0.62. Mouth height in metres is a separate [estimate] of 1.6 m. |
| 6 | §6 "diffuse tail … total energy s × mirror"; §7 L_e already contains 10 log10(1−s) | The diffuse energy becomes s·(1−α)(1−s): s is applied twice, and a cobble's tail is 4.0 dB too low (−6.4 instead of −2.4 dB). | §2.3: E_spec = (1−α)(1−s) and E_diff = (1−α)s, each taken from the *incident* energy. |
| 7 | §6 "smooth while σ_h < λ/(8 cos θ)" together with "mirror part falls as exp(−(2kσ cos θ)²)" and table s(cobble) = 0.6 | The two disagree. At the Rayleigh limit the Kirchhoff specular fraction is already exp(−(π/2)²) = 0.085, so 91 % of the energy is scattered. Cobbles with σ = 1.5–2.5 cm at 3.4 kHz, normal incidence, give s = 0.97–1.00, not 0.6. | Pick one source for s (§2.3). The "smooth" label uses the Fraunhofer limit λ/(32 cos θ), where the specular fraction is 0.857. |
| 8 | §6 "a 2 m patch facing you at 5 m smears 2.2 ms" | 2(√(5²+1²) − 5)/343 = **0.58 ms**. | Correct the value. The 47 ms figure for a 2–10 m wall is right. |
| 9 | §4 "ΔL = 10 log10(3+20N) (N>0)"; §7 test "N = 0 → 4.8 dB"; LOS is undefined | Line of sight is not handled. Under the δ ≥ 0 geometry an unobstructed path would get N = 0, hence 4.8 dB. | §2.5: LOS clear means 0 dB exactly. LOS blocked means N ≥ 0, so grazing gives 4.77 dB. The cap is 24 dB [tuning]. |
| 10 | §4 "g(f) = 10^(−TL(500)/20)·500/f … lowpass at 125 Hz with pre-gain G = 4·10^(−TL(500)/20)" | The algebra is correct asymptotically: the error is −0.26 dB at 500 Hz and −0.02 dB at 2 kHz. It only holds for *uncapped* mass-law rows. For brick and stone, capped at 55/65 dB, the filter keeps falling and is 12 dB below the table at 2 kHz, so test 4 fails. The table's glass 6 mm dip needs the +10 dB peak. | Use the filter for door, plank and glass (+peak) only. Capped walls get a flat gain of 10^(−cap/20) (§2.6). |
| 11 | §4 "Door with 1% open gap: 20 / 20 / 20 / 20 / 20 / 20" | The composite formula gives 18.1/19.4/19.9/20.0 dB at 125/250/500/2k. | Use the computed values. The ±0.5 dB test only holds at ≥ 500 Hz. |
| 12 | §4 "f_c = c²/(1.814 c_L t)" while the text gives 3013 / 2008 Hz | The results were computed with 1.8 (calc/tl.py). With 1.814 the values are 2989 Hz (4 mm) and **1993 Hz** (6 mm). | Use 1.814 throughout. This has no gameplay effect. |
| 13 | §5 "m = a(f)/4.34" with the column "with air, 3.4 kHz" | The column was computed with m = a/17.37 (calc/tl.py: `0.0245/8.686/2`), which makes air absorption 4× too weak. At 1.5 m/cell the crypt is 2.63 s, not 3.6, and the church 3.33 s, not 5.1. | §2.7, using m = a/(10 log10 e) = a/4.343. |
| 14 | §5 "House 8 × 6 cells" | `maps.js` house1 has a 10 × 8 interior. House2 is 9 × 10 and the barn 8 × 8. | Use 10 × 8 (house1). |
| 15 | §5/§7 "1 cell = 1.5 m (est.)"; §8 Q2 "T60 ∝ V/S ∝ CELL_M" | The scale is now decided as 1.0. T60 is proportional to cellM only if room *height* also scales. Heights are fixed physical estimates in metres, because the rendered wall height of one cell is stylised. | §2.7 table at 1.0 (primary) and 1.5, with heights fixed. |
| 16 | §7 "audio echo delay keeps its 34 cells/s" | The code has three timing laws. The wall echo uses 2d/34 (`game.js:1182`). The person echo uses d/12 + d/34 + 0.02, which is the visual hit plus one way at 34 (`game.js:1109`, `people.js:961-963`). Bounce echoes use d/12, one way at visual speed (`game.js:1217`, `sonar.js:116`). The wall echo arrives **before** the ring reaches the wall: at 5 cells it plays at 0.294 s against 0.417 s. | §2.8 gives one law, behind a flag. Physical time is used only for micro-structure under 30 ms. |
| 17 | §7 "rp.maxCells 1.3"; test "physical delay at 1.3 cells = 11.4 ms" | 1.3 cells was chosen as ≈ 2 m at 1.5 m/cell. At 1.0 m/cell it is 1.3 m, and 7.58 ms. | Specify `rp.maxM = 2.0` in metres. The test is 2·r/343. |
| 18 | §7 "ping shortened to ~8 ms at 3.2 kHz" next to §2 "measured 3 ms" | An 8 ms ping is ≈ 3× the measured click (2–3 ms to 5 % energy), and §7 implies it is a physical correction. The echo path also lowpasses at `ECHO_FILTER_HZ = 2200` (`audio.js:14`), which takes ≈ 5–7 dB off a 3.2 kHz ping. | §2.9: `clickPing` mode is either `measured` (3 ms) or `stylised` (8 ms, labelled non-physical). The echo lowpass must follow the ping band. |
| 19 | §3/§5 air absorption "why the click's far hiss dulls"; §7 a_f = 0.0245 dB/m as one broadband dB term | The echo synth is a 1.8→1.1 kHz chirp lowpassed at 2.2 kHz (`audio.js:8-14,187-201`), with no 3.4 kHz or 8 kHz content. At game paths of ≤ 20 m (10 m round trip) the loss is ≤ 0.49 dB at 3.4 kHz and 2.37 dB at 8 kHz, so the claimed effect cannot be heard as built. | §2.4: a per-band gain, applied only if the ping has HF content (S6 is optional). |
| 20 | §5/§7 "Reverb per zone … feedback 10^(−3τ/T60)" | The reverb send exists only on sounds routed through `routeOut` (`audio.js:355-377`, used by `play()`). `ping()` (`audio.js:280`) and `echo()` (`audio.js:315-325`) connect to `master.out` with **no send**, so zone reverb cannot colour the click. `setRoom` takes `indoor|outdoor` only (`game.js:3217`, `audio.js:921`), not the zone. | S5 adds a ping/echo send (flagged) and passes the zone name. |
| 21 | §4/§7 "one occlusion filter per material" | The code is boolean only. `play()` applies `occluded` → LP 600 Hz with no gain change; `behind` → ×0.7 plus LP 1200, and `occluded` overrides the 1200 (`audio.js:625-629`). `breath()` applies ×0.7 behind, ×0.5 occluded and a dull buffer (`audio.js:854-866`). `occludedTo` treats glass `w` and closed doors as solid like brick (`game.js:912-926`). | S4. |
| 22 | §3 absorption table "Person 0.29 / 0.51 / 0.71 / 0.73 … −5.4 dB [21]"; "Grass … −5 dB" | Per-person values are absorption *areas* in m² (sabins per person), not a dimensionless α, so 10 log10(1−0.71) has no meaning. Grass at α = 0.6 gives −3.98 dB, not −5. | A person uses TS (§2.2), not α. Grass is −4.0 dB. |
| 23 | §7 "Ring brightness uses the same L_e mapped over 0 to −36 dB" | With TS = −15 dB a person falls below −36 dB beyond r = 3.35 m, so people vanish inside the 10 m sonar range, which breaks the game. | §2.10: a separate visual mapping with a compression κ and class gain. It stays off until approved. |
| 24 | §7 "sonar.js per-ray strength × 10^(B(θ)/20)"; wall formula applied per hit | A specular wall return to a co-located source and ear exists only at the foot of the perpendicular (θ_i = 0). Oblique ray hits return only diffuse energy (Lambert, ∝ cos²θ, −40 log r). Separately, `render.js:971-972` shades `incK = max(0.25, 1−cos θ_i)`, which makes head-on walls the *faintest*, the opposite of the acoustics. | §2.2: one specular echo per wall plane, at the perpendicular foot. Oblique patches use Eq. D. The visual shading is kept as stylisation and documented. |
| 25 | §6 "Cobbles add a short comb (1–2 ms, feedback 0.4)"; §7 comb at the physical delay | In WebAudio, a DelayNode inside a cycle is clamped to ≥ 128 frames (2.67 ms at 48 kHz, 2.90 ms at 44.1 kHz). A 1–2 ms feedback comb is impossible, and repetition pitch for r < 0.46 m is too. | Use feed-forward combs, which have no cycle (§2.9). |
| 26 | §5 tunables "zone.t60 range 0.3–2.5" vs text "clamp 0.4–2.5 s" | The clamp ranges conflict. | Clamp to 0.4–2.5 s [tuning], with the same range in data and code. |
| 27 | §1 "Every number below was checked … against the sources"; §9 "All sources … opened" | Items 8, 11, 12, 13 and 22 are arithmetic or unit errors. The claim that the Thaler fit is an intensity (which is why 10 log is used) is not re-verified here, and EE3 α remains open. | Use the tags in §3. §7 lists what is still unverified. |
| 28 | §7 "tests added to existing audio/sonar/render test files; no new test files" | Tests for a pure maths module are cleanest in their own file. | Proposed: `tests/acoustics.test.js` for S1, with integration asserts in the existing files. This reverses the published line and **needs user approval**. The alternative is a `describe('acoustics')` block in `tests/audio.test.js`. |

---

## 2. Corrected equations

**Conventions.**

- All levels are in **dB of intensity (power)**. Amplitude gain is 10^(L/20) and power gain is 10^(L/10). A table value in dB is the same number in either reading.
- Distances in equations are in metres, with r = d·cellM, where d is in cells.
- Every echo level L is relative to the **direct-click intensity at r_ref = 1 m on the beam axis (θ = 0)**, written "dB re 1 m".
- The azimuth θ ∈ (−180°, 180°] is measured from the player's facing direction.

### 2.1 Beam: transmit vs receive

Thaler et al. Eq. 2, read as relative intensity [verified-source for the form; the intensity interpretation is unverified, §7]:

```latex
R(\theta)=\frac{1+\cos\theta}{\sqrt{\alpha^2\cos^2\theta+\beta^2\sin^2\theta}},\qquad
L_{fit}(\theta)=10\log_{10}\frac{R(\theta)}{R(0)}
```

| θ | 0 | 30 | 60 | 90 | 120 | 150 | 170 | 180 |
|---|---|---|---|---|---|---|---|---|
| EE1 / EE2 / EE3(α = 0.0963) mean [computed] | 0 | −1.1 | −3.0 | −5.1 | −7.8 | −12.6 | −21.3 | −∞ |
| rigid sphere 2–4 kHz [computed] | 0 | −0.2 | −1.2 | −3.4 | −6.8 | −10.8 | −6.1 | −4.3 |
| **B_tx canonical** | **0** | **−1** | **−3** | **−5** | **−8** | **−13** | (−16.3 interp.) | **−18** |

- **B_tx** at 0–150° is the fit mean rounded to 1 dB [computed]. The 180° value of −18 dB is a floor [tuning].
- B_tx has no rear bright spot. The sphere's bright spot depends on an ideal, isolated, axisymmetric head; torso and neck break it, and the measured fit has none.
- B_tx is linear in dB between 30° nodes and symmetric: B_tx(−θ) = B_tx(θ).
- B_tx must be non-increasing in |θ|.

**Receive model.** B_rx(θ) = 0 dB by default [design choice of this spec]. Laterality comes only from the existing stereo `pan` (`game.js:907-910`, the sin of the relative azimuth).

An optional rear-hemisphere pinna shadow is available, separate and flagged `rxRear` (default off):

```latex
B_{rx}(\theta)=\begin{cases}0 & |\theta|\le 90^\circ\\ R_{rear}\,\frac{|\theta|-90^\circ}{90^\circ} & |\theta|>90^\circ\end{cases},\qquad R_{rear}=-3\ \mathrm{dB}\ [estimate]
```

This is the same order as today's `behind` ×0.7 (−3.10 dB) for world sounds (`audio.js:625-628`). That rule is the receive model for **world sounds**. It must not also be applied to echoes when `rxRear` is on.

**Combined-usage rule.** In the monostatic case the echo direction equals the ray direction, so:

```latex
L_{echo}(\theta)=B_{tx}(\theta)+B_{rx}(\theta)+L_{path}
```

- B_tx enters **once**, in `acoustics.echoLevel()`.
- `sonar.js` ray strength must not multiply by B_tx as well when the visual mapping is derived from L_echo (§2.10). Either the ray carries B_tx and audio reads it, or audio computes it; never both.
- Test: with B_rx = 0, L_echo(θ) − L_echo(0) = B_tx(θ) exactly.

### 2.2 Echo level

Here r = d·cellM in metres, and r_min = 0.5 m [tuning] clamps the near field.

**Eq. W.** A wall plane is a specular image source at distance 2r. This applies only to the perpendicular foot, at θ_i = 0 [verified-source: image method]:

```latex
L_W = B_{tx}(\theta)+B_{rx}(\theta)-20\log_{10}\!\frac{2\max(r,r_{min})}{r_{ref}}+10\log_{10}\big[(1-\alpha_m)(1-s_m)\big]-2r\,a(f)
```

**Eq. O.** A compact object or person re-radiates (the sonar equation), with TS in dB re 1 m:

```latex
L_O = B_{tx}+B_{rx}-40\log_{10}\!\frac{\max(r,r_{min})}{r_{ref}}+TS_{class}-2r\,a(f)
```

- TS already includes the target's own absorption, so α is not added for objects.
- For a rigid sphere in the geometric region (ka ≫ 1), TS = 10 log10(a²/4) [verified-source: textbook geometric sphere].
- Props, with a = PROP_R·cellM = 0.3 m: **TS = −16.5 dB** [computed].
- People: **TS = −15 dB** [estimate; plausible range −20 to −5].

**Eq. D.** A diffuse (Lambert) patch of area A at incidence θ_i:

```latex
L_D = B_{tx}+B_{rx}+10\log_{10}\!\frac{(1-\alpha_m)\,s_m\,A\cos^2\theta_i}{\pi\,r_{ref}^2}-40\log_{10}\!\frac{\max(r,r_{min})}{r_{ref}}-2r\,a(f)
```

Derivation [computed]:

1. Incident intensity is I₀B/r².
2. Scattered power is that intensity × A cos θ_i × (1−α)s.
3. Lambert radiant intensity is P cos θ_o/π, with θ_o = θ_i in the monostatic case.
4. Received intensity is that divided by r².

**Game calibration (not physics).** This is applied after the physics and is used only when the relevant flag is on:

```latex
L_{game}=G_{class}+\kappa\,L_{phys},\qquad \text{gain}_{amp}=10^{L_{game}/20}
```

- κ ∈ [0,1] [tuning] compresses dynamic range: κ = 1 is physical, κ = 0.5 halves all dB.
- G_class [tuning] is set per class (wall, prop, person) so that, with the flag on, a person at sonar range stays audible and visible.

### 2.3 Energy budget (per surface, per band)

Absorbed + specular + diffuse = 1, all taken from the **incident** energy [verified-source: ISO 17497-1 definition of s]:

```latex
E_{abs}=\alpha,\qquad E_{spec}=(1-\alpha)(1-s),\qquad E_{diff}=(1-\alpha)\,s
```

- The specular term enters Eq. W as 10 log10 E_spec. The diffuse term enters Eq. D through (1−α)s. No term contains s twice.
- **Source of s.** Choose exactly one per material, selected with `rough.sModel`:
  - `'table'`: a fixed s_m [estimate].
  - `'kirchhoff'`: s(f,θ_i) = 1 − exp(−(2kσ_h cos θ_i)²), with σ_h per material [estimate]. This one is the more physical.
- The binary "smooth / rough" label, used only for visuals, follows Fraunhofer: σ_h < λ/(32 cos θ_i), which is 0.315 cm at 3.4 kHz, normal incidence.

### 2.4 Air absorption (per band)

a(f) comes from the ISO 9613-1 formula at 10 °C and 70 % RH [verified-source formula; values computed], in dB/m. Note that the loss is 2r·a over the round trip.

| f (Hz) | 500 | 1k | 2k | 3.4k | 4k | 8k |
|---|---|---|---|---|---|---|
| a (dB/m) | 0.0019 | 0.0037 | 0.0097 | 0.0245 | 0.0331 | 0.1184 |
| loss over a 20 m path (dB) | 0.038 | 0.074 | 0.194 | 0.490 | 0.662 | 2.368 |

Apply this as a per-band gain, or as a one-pole HF shelf, only to signals that contain that band. One broadband a(3.4 kHz) term is acceptable only when the ping is centred at ≈ 3.4 kHz (`clickPing` on).

### 2.5 Diffraction (Maekawa, with explicit boundaries)

δ is the extra path through the diffracting edge, and N = 2δ/λ ≥ 0 [verified-source form]:

```latex
\Delta L=\begin{cases}0 & \text{line of sight clear}\\ \min\!\big(C_{cap},\,10\log_{10}(3+20N)\big) & \text{LOS blocked, edge path exists}\\ \text{no path (fully occluded)} & \text{otherwise}\end{cases}
```

- At grazing incidence (N = 0, the edge just blocks), ΔL = **4.771 dB**.
- C_cap = 24 dB [tuning; the literature range is 20–25].
- Reaching the cap needs N = 12.41.
- ΔL is frequency dependent. Evaluate it at each band centre, or at least at 500 Hz and 3.4 kHz, to keep the HF tilt.
- The 0 → 4.8 dB step at the shadow boundary is accepted. An optional smoothing (Kurze–Anderson continuation, 5 + 20 log10(x/tan x) with x = √(2π|N|) for −0.192 < N < 0) is [estimate], with the form not re-verified here.
- A doorway has ≥ 2 edges. Use the single least-loss edge [estimate]. This is an approximation.

### 2.6 Transmission and occlusion filter

The field-incidence mass law [verified-source]:

```latex
TL(f)=20\log_{10}(m f)-47
```

Composite: τ̄ = ΣS_i 10^(−TL_i/10)/ΣS_i and TL = −10 log10 τ̄ [verified-source].

For an uncapped −6 dB/oct line, g(f) = 10^(−TL(500)/20)·(500/f). A first-order lowpass at f₀ = 125 Hz with pre-gain G has

```latex
|H(f)|=\frac{G}{\sqrt{1+(f/f_0)^2}}\ \xrightarrow{f\gg f_0}\ \frac{G f_0}{f}\quad\Rightarrow\quad G=\frac{500}{125}\,10^{-TL(500)/20}=4\cdot10^{-TL(500)/20}
```

The algebra checks out [computed]. The exact error against the mass law is −0.263 dB at 500 Hz and −0.017 dB at 2 kHz. Below 125 Hz the filter is flat, while the mass law keeps rising (+3 dB at 125 Hz).

- Use it for door (G = 0.0746), plank (0.1492) and glass 6 mm (0.1194, plus a peaking filter of +10 dB at 2 kHz, Q 1.4 [estimate]).
- Capped walls are brick (55 dB) and stone (65 dB). They get a **flat gain** of 10^(−cap/20): 1.778e−3 and 5.62e−4. That is −55/−65 dB, effectively silent, so ΔL from §2.5 dominates.
- A door with a 1 % gap is a parallel flat path at 0.1 amplitude (−20 dB) [computed from the composite].

### 2.7 Rooms

Sabine and Eyring, with c = 343 m/s, so 0.161 = 24 ln 10/c [verified-source]. m = a/(10 log10 e) = a/4.343 m⁻¹:

```latex
T_{60}^{Sab}=\frac{0.161\,V}{S\bar\alpha+4mV},\qquad T_{60}^{Ey}=\frac{0.161\,V}{-S\ln(1-\bar\alpha)+4mV},\qquad L=L_c\cdot cellM,\ W=W_c\cdot cellM,\ H\ \text{in metres}
```

Room sizes are from `maps.js` interiors (`crypt` rows 1–7, the town zones). Heights H and ᾱ are [estimate]. T60 values are [computed].

| Room | cells | H (m) | ᾱ | **1.0 m/cell: Sabine / Eyring / +air 3.4k** | 1.5 m/cell: Sabine / +air | game, clamp 0.4–2.5 |
|---|---|---|---|---|---|---|
| Crypt | 12 × 7 | 3.0 | 0.04 | **3.60 / 3.52 / 2.39** | 4.16 / 2.63 | 2.5 |
| Tavern | 18 × 12 | 3.5 | 0.15 | **1.26 / 1.17 / 1.07** | 1.42 / 1.18 | 1.26 |
| Church | 16 × 14 | 8.0 | 0.06 | **5.18 / 5.02 / 3.00** | 6.26 / 3.33 | 2.5 |
| House1 | 10 × 8 | 2.7 | 0.12 | **1.13 / 1.06 / 0.97** | 1.29 / 1.09 | 1.13 |

Scaling: with H fixed, T60 grows sub-linearly with cellM (crypt ×1.16 from 1.0 to 1.5). It is proportional to cellM only if H is also scaled.

**Comb reverb** [verified-source]: each comb has its own feedback gain,

```latex
g_i=10^{-3\tau_i/T_{60}}
```

- With the indoor τ = 37/61/97 ms: T60 = 1.0 s gives 0.774/0.656/0.512, and T60 = 2.5 s gives 0.903/0.845/0.765.
- Today's fixed g = 0.58 implies T60 of 0.469/0.774/1.230 s per comb.
- The outdoor g = 0.25 implies 0.095/0.154/0.234 s.
- The loop is `d → fb → d` with no filter inside it (`audio.js:123-131`), so the formula applies exactly.

### 2.8 Speeds and timing

Physical speed: c = 343 m/s [verified-source], which at cellM = 1 is 343 cells/s. Game speeds, both [tuning] and unchanged:

- Visual wavefront v_vis = 12 cells/s (`sonar.js:7`), 28.6× slower than physical at 1.0 m/cell.
- Audio echo speed v_aud = 34 cells/s, 10.1× slower than physical.

Canonical game arrival law, flag `echoTiming`, default off: an echo plays when the visual ring reaches the reflector, then travels back at v_aud.

```latex
t_{echo}=\frac{d_{out}}{v_{vis}}+\frac{d_{back}}{v_{aud}}
```

At 1/5/10 cells this gives 0.113/0.564/1.127 s. Today the three paths give, at 5 cells, 0.294 (wall), 0.584 (person) and 0.417 s (bounce).

Physical time is used **only** for micro-structure under 30 ms: comb delay τ = 2r/c and diffuse smear windows. At 1.0 m/cell, τ is 5.831 ms at 1 cell, 7.580 ms at 1.3 cells and 11.662 ms at 2 cells.

### 2.9 Click and repetition pitch

**Ping modes.** `clickPing` selects one of three [tuning]:

- `'chirp'` (today, default): 70 ms, 1800→1100 Hz, 120 ms tail.
- `'measured'`: a 3 ms burst [verified-source: 2–3 ms to 5 % energy], centre 3.4 kHz (measured peaks 2.2–3.7 kHz).
- `'stylised'`: 8 ms at 3.2 kHz. This is documented as **not physically equivalent**: it is about 3× longer than the measured click.

When `clickPing` is not `'chirp'`, the echo lowpass `ECHO_FILTER_HZ` must be raised to ≥ 5 kHz, or the echo band is cut by 5–7 dB.

**Repetition pitch.** f_rp = c/(2r) [verified-source], applied while r ≤ rp.maxM = 2.0 m [tuning]. Implement it as a feed-forward comb with no cycle:

```latex
y(t)=x(t)+g\,x(t-\tau)
```

Here τ = 2r/c and g = 10^(L_W/20) relative to the direct path. This works at any τ > 0. A feedback comb is allowed only if τ ≥ 128/f_s.

### 2.10 Visual mapping

Visual brightness v ∈ [0,1] is **not** amplitude:

```latex
v=\mathrm{clamp}\!\left(1+\frac{L_{game}}{D_{vis}},\,v_{min},\,1\right)
```

- D_vis = 36 dB [tuning].
- v_min = 0.15 [tuning] keeps the rear ghost, so it is never black.
- It is computed from L_game (§2.2), so G_class and κ protect people's visibility.
- With κ = 0.5 and G_person = +12 dB [tuning], a person at 10 m has L_game = 12 + 0.5·(−55.0) = −15.5 dB, so v = 0.57.

---

## 3. Parameter table

| Name | Value | Unit | Tag | Ref | Used in |
|---|---|---|---|---|---|
| cellM | 1.0 | m/cell | [design decision] | user | everywhere r = d·cellM |
| c | 343 | m/s | [verified-source] | [12][15] | delays, f_rp, Sabine 0.161 |
| v_vis | 12 | cells/s | [tuning] | `sonar.js:7` | rings, t_echo |
| v_aud | 34 | cells/s | [tuning] | `game.js:1109,1182` | t_echo |
| moveSpeed / sonarRange | 3 / 10 | cells/s / cells | [tuning] unchanged | `config.js:13,22` | — |
| r_ref | 1 | m | [verified-source] convention | [6] | all L |
| r_min | 0.5 | m | [tuning] | — | Eq. W/O/D |
| B_tx | 0/−1/−3/−5/−8/−13/−18 at 0…180° | dB (int.) | [computed] 0–150, [tuning] 180 | [1][2] | Eq. W/O/D, ring |
| B_rx | 0 | dB | [design choice] | — | echo |
| R_rear (flag rxRear) | −3 | dB | [estimate] | — | echo |
| TS_person | −15 (−20…−5) | dB re 1 m | [estimate] | — | Eq. O |
| TS_prop | −16.5 | dB re 1 m | [computed] a = 0.3 m | sphere a²/4 | Eq. O |
| G_class (wall/prop/person) | 0 / +6 / +12 | dB | [tuning] | — | L_game |
| κ | 1.0 when the flag is on for physics tests; 0.5 suggested for gameplay | — | [tuning] | — | L_game |
| α (2 kHz): stone/brick/plaster/glass/wood | 0.03/0.03/0.04/0.02/0.10 | — | [verified-source] values | [18][19] | Eq. W/D |
| α grass (2 kHz) | 0.6 | — | [estimate] | [26] (to 1.6 kHz) | Eq. W/D |
| s: glass/stone/brick/wood/roughStone/cobble/grass/iron | 0.05/0.1/0.15/0.3/0.35/0.6/0.7/0.5 | — | [estimate] (glass, wood from [23]) | [18][23] | `sModel = 'table'` |
| σ_h: smooth/roughStone/cobble/grass | 0.002/0.015/0.025/0.04 | m | [estimate] | [27][28] | `sModel = 'kirchhoff'` |
| a(f) | §2.4 table | dB/m | [computed] ISO 9613-1 | [15] | S6 |
| TL mass law constant | −47 (field), −42.4 (normal) | dB | [verified-source]/[computed] | [7][8] | §2.6 |
| TL caps brick/stone | 55 / 65 | dB | [estimate] | — | flat occlusion gain |
| occlusion f₀, G | 125 Hz; door 0.0746, plank 0.1492, glass 0.1194 | Hz, — | [computed] | §2.6 | S4 |
| glass peak | +10 dB, 2 kHz, Q 1.4 | — | [estimate] | [10] | S4 |
| door gap path | 0.1 (−20 dB) | amp | [computed] 1 % gap | §2.6 | S4 |
| Maekawa cap | 24 | dB | [tuning] | [11] | S4 |
| H crypt/tavern/church/house | 3.0/3.5/8.0/2.7 | m | [estimate] | — | §2.7 |
| ᾱ crypt/tavern/church/house | 0.04/0.15/0.06/0.12 | — | [estimate] | — | §2.7 |
| T60 clamp | 0.4–2.5 | s | [tuning] | — | S5 |
| comb τ indoor / outdoor | 37,61,97 / 19,31,47 | ms | [tuning] existing | `audio.js:88-89` | S5 |
| rp.maxM | 2.0 | m | [estimate] from [16][17] | — | S8 |
| click duration measured / stylised | 3 / 8 | ms | [verified-source] / [tuning] | [1][2] | S9 |
| click centre | 3.4 (measured) / 3.2 (stylised) | kHz | [verified-source] / [tuning] | [1] | S9 |
| D_vis, v_min | 36, 0.15 | dB, — | [tuning] | — | S10 |
| mouth height | 1.6 | m | [estimate] | — | ground θ_i |
| ping z | 0.62 | wall heights | [tuning] | `sounds.js:12` | sonar |

---

## 4. Code-path map

| Path (file:line) | Current behaviour | Stage that changes it |
|---|---|---|
| `audio.js:8-14` | Ping and echo constants: 1800→1100 Hz, 70 ms, tail 120 ms, `ECHO_FILTER_HZ` 2200 | S9 |
| `audio.js:67` ROOMS | indoor/outdoor `delayMul` 1/1.8, `gainMul` 1/0.7, cutoff 2200/1400. Outdoor echoes are delayed ×1.8, which is another timing law | S5 (gain), S11 (delay) |
| `audio.js:87-90` REVERB | 3 combs with fixed fb 0.58 / 0.25 | S5 |
| `audio.js:94-145` master | Compressor (−18 dB, 4:1). Combs `send→d→fb→d→lp→out` | S5 |
| `audio.js:147-159` tuneReverb(kind) | Two presets only | S5 (per-zone g_i) |
| `audio.js:187-201` chirp | Echo voice equals the ping chirp | S8, S9 |
| `audio.js:265-288` ping | Connects to `master.out`, **no reverb send** | S5, S9 |
| `audio.js:298-329` echo(a, delay, strength, pan) | LP 2200, gain = vol·0.35·strength·gainMul, **no reverb send**, no material | S2, S5, S7, S8 |
| `audio.js:355-377` routeOut | Pan + optional LP + reverb send | S4 |
| `audio.js:597-648` play | dist → ×1/(1+d/4); behind → ×0.7 + LP 1200; occluded → LP 600 (overrides), no gain change; material only picks the footstep timbre | S4 |
| `audio.js:416-447` KINDS (footsteps) | stone/grass/wood timbres | none (timbre stays) |
| `audio.js:843-866` breath | behind ×0.7, occluded ×0.5, dull buffer | S4 |
| `audio.js:921-929` setRoom(kind) | indoor/outdoor | S5 (zone name) |
| `game.js:906-910` panTo | sin(relative azimuth) | none (receive laterality) |
| `game.js:912-926` occludedTo | Boolean solid-cell sampling every 0.25 cell. Glass and closed doors count like brick | S4 (returns `{material, edgeDelta}`) |
| `game.js:929-941` spatial | Builds dist/behind/occluded | S4 |
| `game.js:944-950` stepMaterial | `materialAt` → stone/grass/wood | none |
| `game.js:1093-1113` simulateWorld | Person echo: delay = d/34 + 0.02 after the visual hit; strength = clamp(0.7·e.strength, 0.1, 0.7) | S2 (Eq. O), S11 |
| `game.js:1152-1186` pulse | Wall echo: one echo for the nearest wall; delay 2d/34; strength = clamp(1 − d/range, 0.15, 1); pan to the nearest wall | S2 (Eq. W at the perpendicular foot), S3, S11 |
| `game.js:1205-1222` bounceEchoes | Up to 4 echoes; delay = child t0 (d/12); strength = clamp(0.35·0.45^gen …) | S2, S11 |
| `game.js:3194-3218` roomProfile / setRoom | kind only | S5 |
| `sonar.js:7` | speed 12, range 10 | none |
| `sonar.js:52-54, 87-128` | Pulse strength ∈ [0,1], children ×0.45, no material or normal | S3 (optional B_tx on visual), S7 |
| `sonar.js:146-152` nearestDist | Min over `vis` | S2 (also needs the angle → B_tx) |
| `sonar.js:186-188, 251-252` | Brightness b = (1 − age/fade)²·(1 − 0.5 d/range)·strength | S10 |
| `people.js:946-967` updateEchoes | Strength = (1 − 0.5 d/range)·pulse strength | S2/S10 |
| `raycast.js:8-44` trace | Hit carries `side`, `cellX/Y`, `hitX/Y`, `wallX`, `rayAngle`. Normal = side 0 ? (−sign cos a, 0) : (0, −sign sin a). No material | S2/S7 (material via `world.materialAt(cellX, cellY)`) |
| `world.js:17-20` MATERIAL | `#` stone, B brick, W wood, I iron, w glass; floors stone/wood/grass; D wood, G iron | S7 (adds `cobble` and `roughStone` tiles; needs map edits, so it is separate) |
| `world.js:473-476` materialAt | Tile → material | none |
| `world.js:552-553` | Glass passes light only | S4 (glass transmits sound with TL) |
| `render.js:840` | matOn gate (`matDetail`, quality ≥ 2) | S10 (speckles behind the same gate) |
| `render.js:971-972` | incK = max(0.25, 1 − cos θ_i): head-on walls faintest | S10 (documented stylisation; optional) |
| `render.js:1146` | Seeded stipple behind the floor front | S10 |
| `ripple.js:167-170` | Ring alpha = strength·(1 − f)^1.5 | S10 |
| `data/sounds.js:5-49` | Levels, rooms, `maxBounceEchoes` | S1 (`acoustics` block + flags) |

---

## 5. Staged implementation plan

Every stage has a flag in `SoundData.acoustics.flags`. **All flags default to `false`**, which reproduces today's behaviour bit for bit. No stage changes movement, sonar range, cooldown or `v_vis`.

| Stage | Files | Behaviour when the flag is on | Flag | Tests |
|---|---|---|---|---|
| **S1** pure maths + data | new `js/acoustics.js` (UMD like the other modules), `js/data/sounds.js` (`acoustics` block: params from §3 + `flags`), `index.html` script tag | None: the functions are unused | — | `tests/acoustics.test.js` (or a block in `audio.test.js`, pending approval §1 #28): all of §6 |
| **S2** echo level | `game.js` (pulse, simulateWorld, bounceEchoes), `audio.js` echo accepts `levelDb` | Eq. W (perpendicular foot), Eq. O (TS), L_game → amplitude | `echoLevel` | §6 T2–T4; audio.test asserts gain = 10^(L/20)·vol·0.35 |
| **S3** beam | `game.js` (θ of the echo), `acoustics.js` | B_tx once; B_rx = 0; optional rear shelf | `beam`, `rxRear` | T5–T7 |
| **S4** occlusion / Maekawa | `game.js` occludedTo → `{blocked, material, delta}`, `audio.js` play/breath/routeOut | Per-material G + LP 125 Hz (flat for brick/stone), glass peak, door gap, Maekawa; LOS = 0 | `occlusion` | T10–T13 |
| **S5** reverb per zone | `audio.js` tuneReverb(zone, t60), send on ping/echo; `game.js` setRoom passes the zone | g_i = 10^(−3τ_i/T60), clamp 0.4–2.5; ping and echo get a send | `reverbZones` | T14–T16 |
| **S6** air absorption | `audio.js` echo (per-band shelf) | HF loss 2r·a(f); a no-op for the chirp ping | `airBands` | T17 |
| **S7** roughness / diffuse | `acoustics.js`, `audio.js` grain tail (feed-forward), `world.js` tiles (map edit is a sub-step) | Energy split §2.3; diffuse grains in the physical smear window | `rough` | T8, T9, T18 |
| **S8** repetition pitch | `audio.js` feed-forward comb | Comb at τ = 2r/c for r ≤ 2 m | `repPitch` | T19, T20 |
| **S9** ping option | `audio.js` ping/chirp, ECHO_FILTER_HZ | `'measured'` 3 ms / `'stylised'` 8 ms (labelled non-physical) | `clickPing` (`'chirp'` default) | audio.test: duration, centre frequency, echo LP ≥ 5 kHz when not chirp |
| **S10** visuals | `sonar.js`/`people.js` strength from L_game, `render.js`, `ripple.js` | v = clamp(1 + L_game/36, 0.15, 1); speckles on rough cells (`matOn` gate) | `visuals` | T21; render.test seeded speckles; smoke ≤ 96 voices |
| **S11** echo timing | `game.js` (three echo paths), `audio.js` ROOMS.delayMul | t_echo = d/v_vis + d/v_aud for all three | `echoTiming` | T22 |

Order: S1 → S2 → S3 → S11 → S4 → S5 → (S6, S7, S8, S9, S10 in any order). Each stage merges with its flag off and is switched on separately after the user approves it.

---

## 6. Automated tests (expected values computed in `calc/spec_v011.py`)

All tests run with cellM = 1.0 unless stated, κ = 1, G_class = 0 and B_rx = 0. Tolerances are ±0.05 dB for dB values and ±0.001 for ratios, unless stated.

| # | Test | Expected |
|---|---|---|
| T1 | `r = d·cellM`: d = 3, cellM 1.0 / 1.5 | 3.000 / 4.500 m |
| T2 | Wall Eq. W, θ = 0, α = s = 0, no air; r = 1 / 3 / 10 m | −6.0 / −15.6 / −26.0 (−6.021 / −15.563 / −26.021) |
| T2b | Regression: the §7 formula without the 2 must **not** pass | −20 log10(r) = 0.000 / −9.542 / −20.000 ≠ T2 |
| T3 | Object Eq. O, TS = 0; r = 1 / 3 / 10 | 0.0 / −19.1 / −40.0 (0.000 / −19.085 / −40.000) |
| T3b | Person TS = −15; r = 1 / 3 / 10 | −15.0 / −34.1 / −55.0 |
| T3c | Prop TS = 10 log10(0.3²/4) | −16.478 |
| T4 | Wall at 3 m with α 0.03, s 0.1 | −16.153 |
| T5 | B_tx symmetry and monotonicity: B(θ) = B(−θ) for θ in 0..180 step 5; B non-increasing in \|θ\|; B(0) = 0, B(180) = −18; B(45) = −2.0, B(75) = −4.0, B(135) = −10.5, B(165) = −15.5 | exact |
| T6 | No double beam: L_echo(θ) − L_echo(0) with B_rx = 0 at 90 / 180 | −5.000 / −18.000 (a double beam would give −10 / −36) |
| T7 | rxRear on, R_rear = −3: total at 90 / 135 / 180 | −5.000 / −12.000 / −21.000 |
| T8 | Energy: α + (1−α)(1−s) + (1−α)s for (0.03, 0.1), (0.05, 0.6), (0.6, 0.7), (0.02, 0.05) | 1.000 each. Cobble E_spec = 0.380 (−4.202 dB), E_diff = 0.570 (−2.441 dB); stone E_diff = −10.132 dB (not −10.590) |
| T9 | Lambert Eq. D: A = 1 m², cobble (0.05, 0.6), r = 2, θ_i = 0 / 60°; stone (0.03, 0.1), r = 1, θ_i = 0 | −19.454 / −25.475; −15.104 |
| T10 | Maekawa: LOS clear → 0.000; blocked N = 0 → 4.771; N = 1 → 13.617; δ = 0.5 m @ 3.4 kHz (N = 9.913) → 23.037; δ = 1.0 m → 24.000 (capped; uncapped 26.015); N = 100 → 24.000 | ±0.01 |
| T11 | Occlusion filter, door (m 24): \|H\| at 500 / 2000 Hz | −34.847 / −46.642 dB (mass law −34.584 / −46.625; within 0.3 dB) |
| T12 | Brick: the flat gain is used, not the filter; gain at 2 kHz | −55.000 dB (the filter would give −67.058, so assert it is not used) |
| T13 | Door 1 % gap composite at 125 / 250 / 500 / 2000 Hz | 18.093 / 19.439 / 19.853 / 19.991 |
| T14 | Sabine, cellM 1.0: crypt / tavern / church / house1 | 3.60 / 1.26 / 5.18 / 1.13 s (±0.01) |
| T15 | Sabine, cellM 1.5: same rooms; crypt with air at 3.4 kHz (m = 0.005641) at 1.0 / 1.5 | 4.16 / 1.42 / 6.26 / 1.29; 2.39 / 2.63 |
| T16 | Comb g = 10^(−3τ/T60): τ 37/61/97 ms at T60 = 1.0 and 2.5; fixed 0.58 → implied T60 | 0.774 / 0.656 / 0.512; 0.903 / 0.845 / 0.765; 0.469 / 0.774 / 1.230 s |
| T17 | Air loss over a 20 m path at 500 / 1k / 2k / 3.4k / 4k / 8k | 0.038 / 0.074 / 0.194 / 0.490 / 0.662 / 2.368 dB (±0.005) |
| T18 | Kirchhoff s at 3.4 kHz: σ 0.002 m, 0° → 0.060; σ 0.015, 0° → 0.970; σ 0.025, 80° → 0.254. Fraunhofer limit λ/32 at 3.4 kHz → 0.315 cm | ±0.001 |
| T19 | Physical delay 2r/c at cellM 1.0: d = 1 / 1.3 / 2 cells | 5.831 / 7.580 / 11.662 ms; f_rp = 171.5 / 131.9 / 85.8 Hz |
| T20 | Comb gating: r = 2.0 m → on; 2.01 m → off; comb node graph has no cycle (feed-forward) | — |
| T21 | Visual v: L_game = 0 → 1.000; −18 → 0.500; −36 → 0.150 (floor); person r = 10, κ 0.5, G +12 → L −15.5, v 0.569 | ±0.001 |
| T22 | Timing (S11): d = 1 / 5 / 10 cells → 0.113 / 0.564 / 1.127 s; and t_echo ≥ d/v_vis always | ±0.001 |
| T23 | Flags: with all flags false, `game.js` echo calls receive the same (delay, strength, pan) as today for a fixed seed (golden record) | equal |

---

## 7. Remaining approximations and unresolved issues

1. **Passing these tests proves only that the code matches this spec.** It does not prove physical validity. No measurement of the game's output against real echoes has been made.
2. **Sources were not re-opened in this review.** [verified-source] means the equation form and arithmetic were checked, not that the citation was re-read. Two points rest only on the proposal's reading of Thaler 2017:
   - that the fit is relative *intensity* (if it is amplitude, every B_tx value doubles in dB);
   - that EE3 α = 0.963 is a misprint for 0.0963.
3. TS_person = −15 dB, every s and σ_h value, the TL caps, the glass peak, room heights and ᾱ are estimates. G_class, κ, D_vis, v_min and r_min are pure tuning.
4. The model is monostatic: source and ear are co-located 0.1 cell apart, so the ear offset and binaural cues are ignored. Pan uses the sine law only.
5. Walls are treated as infinite planes for Eq. W. A short wall segment (Fresnel zone radius √(λr/2) ≈ 0.50 m at 3.4 kHz and 5 m) gives less than the image-source level. This is not modelled.
6. Maekawa assumes a thin semi-infinite edge, with the single least-loss edge for doorways. Room-to-room transmission through open doors (coupled spaces) is not modelled. Zone T60 assumes diffuse fields, which a 12 × 7 m crypt only roughly satisfies.
7. Sabine and Eyring with a single ᾱ at 2 kHz, applied to a stylised 3-comb reverb, give only the decay *rate*. The combs also impose flutter-like periodicity that a real room lacks.
8. Game timing (v_vis, v_aud) is deliberately non-physical, 10–29× slower than sound. Mixing physical micro-timing (comb, smear) with game macro-timing is a documented stylisation.
9. Air absorption is audible only with an HF ping (S9). With the default chirp, S6 is a no-op by design.
10. New tiles (`cobble`, `roughStone`) need map and level edits outside this spec, plus save-compatibility checks.
11. Open decisions for the user:
    - approve the separate test file (§1 #28);
    - choose `sModel` (`'table'` or `'kirchhoff'`);
    - choose κ and G_class for gameplay;
    - choose whether S11 (timing) should ever ship, since it makes wall echoes later than today.
