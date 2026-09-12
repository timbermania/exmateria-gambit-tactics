shader_type spatial;
// FORMATION-screen gold selection box — SUBTRACTIVE pass (PSX tpage 0x5F, abr=2;
// FORMATION_SCREEN.md §11). Twin of formation_box.gdshader, drawn 1px LOWER: it
// darkens the framebuffer along the diamond edge just beneath the additive gold,
// which is what gives the box its embossed drop shadow (see the .gdshaderinc
// header — the two passes do NOT cancel; they are offset 1px in Y).
// MIRRORS effect_particle_mode2: same tone formula, blend_sub render mode.
// compositor-exempt: off-fork-fallback — OFF-FORK Mobile fallback for the box-sub prim — folds via
// formation_box_sub_fold.gdshader (compositor_layer) on the Forward+ fork; this runs only when
// Fold.owns() is false (ADR-0077 dec. 5). Selected by FormationScene.fold_shader_for.
render_mode unshaded, blend_sub, depth_draw_never, depth_test_disabled, cull_disabled;

// Vault: [[Gold Selection Box]]

#include "res://src/ui3/shaders/formation_box.gdshaderinc"

void fragment() {
	vec4 c = box_sample(UV);
	if (c.a < 0.25) {
		discard; // idx0 transparent exterior corners
	}
	vec3 base = pow(c.rgb, vec3(psx_gamma));
	ALBEDO = quantize5(base * brightness * PSX_OUTPUT_LEVEL);
	ALPHA = 1.0; // full subtractive intensity
}
