shader_type spatial;
// FORMATION-screen gold selection box — ADDITIVE pass (PSX tpage 0x3F, abr=1;
// FORMATION_SCREEN.md §11). This pass sits 1px HIGHER than the subtractive twin
// (formation_box_sub) — together they emboss the gold edge (see the .gdshaderinc
// header). Selected cell only. Screen-space overlay: no depth.
// MIRRORS effect_particle_mode1 / formation_orb: raw sample + pow(c, psx_gamma) *
// brightness * psx_brightness + 5-bit snap. (NOT the old `c.rgb * brightness`.)
// compositor-exempt: off-fork-fallback — OFF-FORK Mobile fallback for the box-add prim — on the 4.8 Forward+ fork the
// box folds via formation_box_fold.gdshader (compositor_layer); this in-scene blend_add runs only when
// Fold.owns() is false (ADR-0077 dec. 5). Selected by FormationScene.fold_shader_for.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;

// Vault: [[Gold Selection Box]]

#include "res://src/ui3/shaders/formation_box.gdshaderinc"

void fragment() {
	vec4 c = box_sample(UV);
	if (c.a < 0.25) {
		discard; // idx0 transparent exterior corners
	}
	vec3 base = pow(c.rgb, vec3(psx_gamma));
	ALBEDO = quantize5(base * brightness * PSX_OUTPUT_LEVEL);
	ALPHA = 1.0; // full additive intensity
}
