shader_type spatial;
// FORMATION bottom "band" backdrop (FORMATION_SCREEN.md §14.6.6) — the dark,
// top/bottom-faded band the vitals + info panels sit on. STATICALLY GROUNDED +
// ORACLE-VERIFIED: it is iter 2 of FUN_80112c88 (@0x80112c88, the sister of the
// top sort-tab header backdrop), a full-width 256px UNTEXTURED gouraud region drawn
// ABR mode 2 (SUBTRACTIVE) over the cobble floor. Read BYTE-EXACT from the settled-
// roster RAM packet @0x801C02A8: base_rgb (120,120,120); the top feather (y169..177)
// ramps the subtracted grey 12->108 and the bottom feather (y228..236) ramps it
// 108->12, so the fg (grey subtracted from the floor) profiles 0 -> 120 -> 120 -> 0.
//
// PRINCIPLED (no guessed floor level): the PSX result is clamp(cobble_display - fg, 0)
// PER PIXEL against the REAL cobble under the band, not a single average. So instead of
// a hand-tuned floor_ref constant, this shader RE-SAMPLES the floor itself — the exact
// same index/palette/tile/spotlight computation as formation_background.gdshader — at
// this fragment, recovering the true per-pixel cobble_display. The two shaders MUST stay
// in sync (identical sampling + the same spot_* uniforms pushed to both); a shared
// .gdshaderinc would be the clean way if they drift.
//
// The screen y comes from FRAGCOORD (the literal framebuffer pixel), normalised by
// VIEWPORT_SIZE to the 256x240 virtual space — the FormationScene camera is ORTHOGRAPHIC,
// so this is exact and matches the background quad's UV-derived frag_px. The fg trapezoid
// is FormationScene.band_subtract_at (the single source of truth the guard checks). PSX
// subtracts in DISPLAY (gamma) space but the Mobile buffer blends in LINEAR, so the
// display-space result pow(cob) - pow(clamp(cob-fg,0)) is emitted as the LINEAR delta the
// hardware blend_sub needs: fb = pow(cob) - delta = pow(clamp(cob-fg,0)) = the exact PSX
// subtract, per channel. Grout (dark cobble) -> black; bright stones survive as very-dark
// texture — the textured band the oracle shows (dark-pixel fraction fluctuates 10-100%),
// NOT a solid-black wall. SUBTRACTIVE sibling of formation_shadow.gdshader.
// compositor-exempt: off-fork-fallback — OFF-FORK in-scene fallback ONLY (ADR-0077). On the 4.8 Forward+ fork the band FOLDS
// through the display-space scratch like every other PSX add/sub prim (formation_band_fold.gdshader, wired
// by FormationScene.fold_shader_for("band", true) — its faithful pure-black core is oracle-verified). This
// in-scene twin is the degraded path when the engine-fold does NOT own compositing (stock 4.7 / test
// runner): it fakes the display-space subtract on the linear RGBA16F buffer by RE-SAMPLING the floor and
// emitting a pow(cob)-pow(clamp(cob-fg,0)) delta — brittle (must mirror formation_background per pixel) and
// it UNDER-subtracts off the exact floor, but it degrades to slightly-wrong-but-present, never blank. The
// fork path (fold + the depth-writing vitals panel that occludes it) is the faithful one.
render_mode unshaded, blend_sub, depth_draw_never, depth_test_disabled, cull_disabled;

// --- band trapezoid (the fg/255 subtract, oracle @0x801C02A8) -----------------------------
uniform float y_top_out;   // screen y where the top feather starts (fg 0)
uniform float y_top_in;    // screen y where the body starts (fg full)
uniform float y_bot_in;    // screen y where the body ends (fg full)
uniform float y_bot_out;   // screen y where the bottom feather ends (fg 0)
uniform float full_sub;    // body fg/255 (oracle base_rgb 120 -> 120/255)
uniform float screen_h;    // virtual framebuffer height (256x240 -> 240)
// Optional HORIZONTAL feather (§15.19 column bands) — see formation_band_fold.gdshader.
// Default 0/0 ⇒ no-op (1.0), so the full-width stripe (y feather only) is unchanged.
uniform float x_left_out;
uniform float x_left_in;
uniform float x_right_in;
uniform float x_right_out;

// One trapezoid feather profile in [0,1]; degenerate (out1 <= out0) ⇒ 1.0 (no feather on axis).
// Quantized to the virtual-pixel column (floor(s)) so the feather reads as the ROM's discrete
// 1px transparency steps — mirrors the runtime formation_band_fold.gdshader (off-fork fallback).
float band_profile(float s, float out0, float in0, float in1, float out1) {
	if (out1 <= out0) return 1.0;
	float p = floor(s);
	if (p <= out0 || p >= out1) return 0.0;
	if (p < in0) return (p - out0) / (in0 - out0);
	if (p > in1) return (out1 - p) / (out1 - in1);
	return 1.0;
}

// --- floor replication (MUST mirror formation_background.gdshader exactly) -----------------
uniform sampler2D index_atlas : filter_nearest, repeat_enable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row
uniform vec2 tile_px = vec2(128.0, 32.0);
uniform vec2 screen_px = vec2(256.0, 240.0);
// Selected-unit floor spotlight (virtual-px screen space, top-left origin) — pushed from
// _apply_floor_spotlight in lockstep with the background so the cobble matches per pixel.
uniform vec2 spot_center_px = vec2(37.0, 76.0);
uniform float spot_base = 1.0;
uniform float spot_swing = 0.0033;
uniform float spot_vfac = 4.0;
uniform float spot_min = 0.35;

const float GAMMA = 2.2;

// Box-open scissor (DetailScene §15.17) — off-fork twin of the fold band's clip. `clip_world`
// is the growing window aperture in WORLD space (xy = min, zw = max); default unbounded ⇒ the
// full-width formation stripe is byte-identical (it never sets it).
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
// The SCREEN's inverse global transform. `clip_world` is an axis-aligned rect in the SCREEN's own
// space (display px * ppu), but MODEL_MATRIX * VERTEX is GLOBAL — the two only coincide while the
// screen root happens to sit at the world origin, unrotated and unscaled. That held for as long as
// every UI3 screen had its own camera; it stops holding the moment a screen mounts as a CHILD of
// the map's camera (ADR-0137), where the UI plane is rotated and scaled in world space and every
// clipped fragment silently falls outside the box. Mapping the fragment back into screen space
// first makes the comparison space-correct on any host. Identity default ⇒ unchanged where the
// screen already is the origin.
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;  // outside the box-open aperture (§15.17 scissor reveal)
	}
	// This fragment's virtual-pixel position (top-left origin), exact under the ortho camera.
	vec2 frag_px = (FRAGCOORD.xy / VIEWPORT_SIZE) * screen_px;
	float sy = frag_px.y;

	// The oracle fg/255 trapezoid (mirrors band_subtract_at) — the grey to subtract. Snap y to the
	// virtual-pixel row (floor) so the feather reads as discrete 1px steps, like the fork shader.
	float py = floor(sy);
	float sub = full_sub;
	if (py < y_top_in) {
		sub = full_sub * (py - y_top_out) / (y_top_in - y_top_out);
	} else if (py > y_bot_in) {
		sub = full_sub * (y_bot_out - py) / (y_bot_out - y_bot_in);
	}
	sub = clamp(sub, 0.0, full_sub);
	// Multiply in the horizontal feather (a column band fades left/right; the full-width
	// stripe leaves x_* at 0 ⇒ this is 1.0). frag_px.x is the virtual screen x.
	sub *= band_profile(frag_px.x, x_left_out, x_left_in, x_right_in, x_right_out);

	// Re-sample the REAL cobble under this fragment — the exact formation_background compute:
	// tiled indexed texture through its CLUT, dimmed by the selected-unit floor spotlight.
	vec2 tuv = fract(frag_px / tile_px);
	int idx = int(floor(texture(index_atlas, tuv).r * 15.0 + 0.5));
	vec3 base = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5)).rgb;
	vec2 d = frag_px - spot_center_px;
	float dist = sqrt(d.x * d.x + spot_vfac * d.y * d.y);
	float dark = clamp(spot_base - spot_swing * dist, spot_min, spot_base);
	vec3 cob = clamp(base * dark, vec3(0.0), vec3(1.0));   // display-space cobble, 0..1

	// PSX display-space subtract clamp(cob - fg, 0), emitted as the LINEAR delta blend_sub
	// applies: fb(=pow(cob)) - delta = pow(max(cob-sub,0)). Zero free parameters — fg from the
	// packet, cob re-derived from the floor itself, so the band is a faithful cobble - fg.
	vec3 out_d = max(cob - vec3(sub), vec3(0.0));
	vec3 albedo = pow(cob, vec3(GAMMA)) - pow(out_d, vec3(GAMMA));

	// blend_sub == PSX ABR mode 2: fb = fb - ALBEDO, clamped >= 0.
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
