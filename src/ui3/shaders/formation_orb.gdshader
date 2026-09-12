shader_type spatial;
// compositor-exempt: off-fork-fallback formation_orb_rim_fold.gdshader — OFF-FORK Mobile fallback for the orb-rim HALO prim — on the 4.8 Forward+ fork the
// rim folds via formation_orb_rim_fold.gdshader (compositor_layer); this in-scene blend_add runs only
// when Fold.owns() is false (ADR-0077 dec. 5). Selected by FormationScene.fold_shader_for.
// display-space: folds-on-fork formation_orb_rim_fold.gdshader
// (the orb-rim halo folds on the fork; selected by FormationScene.fold_shader_for("orb_rim").) PSX blends in DISPLAY space and this in-scene
// file blends in LINEAR — correct only because it is the off-fork path.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;

// FORMATION orb ADDITIVE pass (PSX ABR=01, back + fore) — STP=1 rim texels
// (idx 8-11, palette a=128). MIRRORS effect_particle_mode1 exactly: the dim-blue
// rim additively LIFTS the floor into the soft halo that fades into the stone.
// The formula IS the particle system's — `pow(col, psx_gamma) * modulate *
// psx_brightness` — with our gouraud pulse as the modulate and the SHARED globals
// psx_gamma (1.4) / psx_brightness (2.2). Using hardcoded pow(2.2) with no
// psx_brightness (an earlier mistake) made the halo ~12x too dim → invisible.
// The solid core is the companion formation_orb_opaque pass. See
// formation_orb.gdshaderinc / §10.
#include "res://src/ui3/shaders/formation_orb.gdshaderinc"

void fragment() {
	vec4 c = orb_sample(UV);
	if (c.a < 0.01 || c.a > 0.9) {
		discard; // keep STP=1 rim only (transparent + opaque discarded)
	}
	vec3 base = pow(c.rgb, vec3(psx_gamma));
	// 5-bit snap of the additive contribution (source-side approximation — the
	// exact snap is post-blend; see #183 / quantize5).
	ALBEDO = quantize5(base * brightness * PSX_OUTPUT_LEVEL);
	ALPHA = 1.0; // full additive intensity
}
