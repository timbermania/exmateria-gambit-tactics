shader_type spatial;
// FORMATION bottom "band" backdrop — subtractive fold variant (FUN_80112c88 iter2, §14.6.6;
// ADR-0077 fold member). The full-width vitals band the panels sit on: the oracle fg/255 trapezoid
// grey subtracted from the cobble floor.
//
// SIMPLER than the in-scene twin formation_band.gdshader — and MORE faithful. The Mobile twin had to
// RE-SAMPLE the floor and emit a linearized pow(cob) - pow(clamp(cob-fg,0)) delta, because it blends
// into a LINEAR buffer and wanted a DISPLAY-space clamp. In the fold, Pass A has already seeded the
// scratch with the DISPLAY-space (sRGB) opaque scene colour — including this same floor — so the PSX
// subtract clamp(cob_display - fg, 0) is just `scratch - fg`, UNORM-clamped at 0, with fg = the
// trapezoid grey. No floor re-sample, no gamma round-trip, no guessed floor level: ALBEDO = vec3(sub).
// (The band's spot_* / index_atlas / tile_px uniforms are therefore GONE here — the scratch carries
// the exact cobble the floor already rendered.) DEPTH from the band's rung Z keeps it behind the vitals
// panel, so the opaque panel content occludes the band where they overlap.
//
// THE ACTIVE runtime path on the fork (global-unify, 2026-08-02). The shared vitals panel it sits under
// (UIUnitInfoWindow) now WRITES DEPTH (vitals_sprite/vitals_bar are opaque, depth test + write ENABLED —
// ordered by real camera-Z, not render_priority) and mounts at a near depth-ladder rung, so this band is
// depth-occluded UNDER the panel in Pass B — it shows in the gaps but never clobbers the panel content in
// Pass C. FormationScene.fold_shader_for("band", true) selects this
// variant; the in-scene formation_band.gdshader is now only the off-fork fallback. Guard: FormationFoldRoutingTest.
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled, compositor_layer;
// psx-prim: untextured — ALBEDO = color direct (PSX flat/gouraud: no texel, no >>7). ADR-0074 color-math clause.

// The oracle fg/255 trapezoid (mirrors FormationScene.band_subtract_at) — the grey to subtract.
uniform float y_top_out;   // screen y where the top feather starts (fg 0)
uniform float y_top_in;    // screen y where the body starts (fg full)
uniform float y_bot_in;    // screen y where the body ends (fg full)
uniform float y_bot_out;   // screen y where the bottom feather ends (fg 0)
uniform float full_sub;    // body fg/255 (oracle base_rgb 120 -> 120/255)
uniform float screen_h;    // virtual framebuffer height (256x240 -> 240)
// Optional HORIZONTAL feather (§15.19 column bands): the narrow Eqp/Ability bands fade
// LEFT/RIGHT into the frame the same way the full-width stripe fades top/bottom. When
// x_right_out <= x_left_out (the default 0/0) the x profile is a no-op (1.0) — so the
// full-width vitals stripe, which sets only the y feather, is byte-unchanged.
uniform float x_left_out;  // screen x where the left feather starts (fg 0)
uniform float x_left_in;   // screen x where the body starts (fg full)
uniform float x_right_in;  // screen x where the body ends (fg full)
uniform float x_right_out; // screen x where the right feather ends (fg 0)
uniform float screen_w;    // virtual framebuffer width (256x240 -> 256) — kept for uniform parity
// The band quad's screen rect (top-left px). The feather is computed from the quad's OWN UV
// (band_x0..band_x1 across UV.x, y_top_out..y_bot_out across UV.y) instead of FRAGCOORD, so it
// is correct at ANY window aspect/resolution — a full-screen FRAGCOORD read is only right when
// the virtual 256×240 screen exactly fills the viewport (letterboxing shifts/scales it).
uniform float band_x0;
uniform float band_x1;
// Box-open scissor (DetailScene §15.17): the Eqp/Ability column bands are revealed through the
// growing window aperture (clipped, not scaled). `clip_world` is that aperture in WORLD space
// (xy = min, zw = max); default unbounded ⇒ the full-width formation stripe that shares this
// shader is byte-identical (it never sets it). See DetailScene.set_open_frame.
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

varying float fold_depth;
varying vec2 band_uv;
varying vec3 v_world;

// One trapezoid feather profile in [0,1]: 0 outside [out0,out1], ramps through the two
// feathers, 1.0 across the body. Degenerate (out1 <= out0) ⇒ 1.0 (this axis has no feather).
//
// The sample coord is QUANTIZED to its virtual-pixel row/column (floor(s)) before the ramp, so
// every virtual pixel gets ONE flat subtract level — the feather reads as the ROM's discrete
// 1px transparency steps at ANY output resolution. A continuous (half-pixel) ramp instead fades
// smoothly and, after the display-space subtract clips toward black, reads as a near-hard edge
// (the "harsh cut-off" the user saw). Sampling at the pixel LOW edge (floor, not floor+0.5) makes
// the vertical stripe reproduce FormationScene.band_subtract_at exactly at integer rows
// (band_subtract_at(169)=12/255, (177)=108/255) — the guarded oracle law.
float band_profile(float s, float out0, float in0, float in1, float out1) {
	if (out1 <= out0) return 1.0;
	float p = floor(s);
	if (p <= out0 || p >= out1) return 0.0;
	if (p < in0) return (p - out0) / (in0 - out0);
	if (p > in1) return (out1 - p) / (out1 - in1);
	return 1.0;
}

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
	band_uv = UV;
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;  // outside the box-open aperture (§15.17 scissor reveal)
	}
	// This fragment's virtual-pixel position, from the quad's OWN UV (aspect-independent):
	// UV maps 0..1 across the band rect, so sx/sy are exact regardless of viewport letterboxing.
	float sx = band_x0 + band_uv.x * (band_x1 - band_x0);
	float sy = y_top_out + band_uv.y * (y_bot_out - y_top_out);

	// The oracle fg/255 trapezoid as a product of the two axis profiles (mirrors band_subtract_at
	// on y; the x profile is 1.0 for the full-width stripe, a left/right fade for a column band).
	float sub = full_sub
		* band_profile(sy, y_top_out, y_top_in, y_bot_in, y_bot_out)
		* band_profile(sx, x_left_out, x_left_in, x_right_in, x_right_out);
	if (sub <= 0.0) {
		discard; // outside the band — subtract nothing (leave the scratch untouched, coverage 0)
	}

	// PSX display-space subtract clamp(cob_display - fg, 0): the scratch already holds cob_display, so
	// hand the hardware blend_sub the grey `sub` directly and let the UNORM scratch clamp at 0.
	ALBEDO = vec3(sub);
	ALPHA = 1.0;
	DEPTH = fold_depth;
}
