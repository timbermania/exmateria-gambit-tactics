shader_type spatial;
// FORMATION-screen per-unit DROP SHADOW — subtractive feet decal (FORMATION_SCREEN.md
// §12). STATICALLY GROUNDED: the roster body builder FUN_8011814c draws the sprite at
// OT bucket 6 and then a SECOND sprite at the feet (struct 0x8018c704, Y = sprite-top +
// 0x1e/0x23) whose tpage = GetTPage(abr=2, 0x3c0,0x100) = 0x5F — ABR mode 2, subtractive
// — inserted one bucket in front (param_3-1 = 5), i.e. behind the body (6) and above the
// gold box (3/4). That is exactly the battle unit shadow (TPAGE 0x5F, the 20x20 radial
// blob unit_shadow.png), so we reuse the same ROM texel here, but as a flat screen-space
// sprite (no terrain drape, no OT depth, no billboard — this whole screen is a 2D overlay
// ordered purely by render_priority; see the RP_* ladder in FormationScene.gd).
//
// This is the SAME shadow as the normal (battle/map) scene — VRAM-verified same 20x20
// radial texel, same tpage 0x5F. So the fragment is a byte-for-byte MIRROR of
// shadow_blob.gdshader: the texel's baked grayscale ramp IS the per-channel amount to
// subtract from the floor, at full `intensity` (1.0). NO psx_gamma / psx_brightness /
// quantize5 — those are the ADDITIVE gold/orb knobs and over-darken a subtractive pass;
// shadow_blob applies none of them, and the oracle roster shadow reaches pure black on
// the dark cobblestone exactly as full subtraction (dark_floor - 0.88 -> clamp 0) does.
// The ONLY intentional divergence from shadow_blob is depth: this flat 2D overlay sorts
// by render_priority (RP_UNIT_SHADOW) with depth off, not by the OT-depth/PAR seam.
// compositor-exempt: off-fork-fallback — OFF-FORK Mobile fallback for the drop-shadow prim — on the 4.8 Forward+ fork the
// shadow folds via formation_shadow_fold.gdshader (compositor_layer); this in-scene blend_sub runs only
// when Fold.owns() is false (ADR-0077 dec. 5). Selected by FormationScene.fold_shader_for.
render_mode unshaded, blend_sub, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D shadow_tex : source_color, filter_nearest;
uniform float intensity : hint_range(0.0, 2.0) = 1.0; // 1.0 == raw ROM subtraction (mirrors shadow_blob)

void vertex() {
	// Plain screen-space quad (the scene already places/scales it in ortho world).
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
}

void fragment() {
	vec4 t = texture(shadow_tex, UV);
	if (t.a < 0.5) {
		discard; // transparent corners of the round blob
	}
	// blend_sub == PSX ABR mode 2: fb = fb - ALBEDO, clamped >=0 (identical to shadow_blob).
	ALBEDO = t.rgb * intensity;
	ALPHA = 1.0;
}
