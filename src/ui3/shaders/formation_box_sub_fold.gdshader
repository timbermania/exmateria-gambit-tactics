shader_type spatial;
// FORMATION gold selection box — SUBTRACTIVE fold pass (PSX tpage 0x5F, abr=2; ADR-0077 fold member).
// Twin of formation_box_fold, blend_sub, drawn 1px LOWER and folded one rung BEHIND the additive gold
// (RP_BOX_SUB < RP_BOX_ADD) — the dark drop shadow that embosses the edge. Body in
// formation_box_fold.gdshaderinc. Subtracts in the display-space scratch (PSX ABR mode 2, UNORM-clamped
// at 0); DEPTH occludes it behind the unit body like its additive twin.
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://src/ui3/shaders/formation_box_fold.gdshaderinc"

void fragment() {
	vec4 c = box_sample(UV);
	if (c.a < 0.25) {
		discard; // idx0 transparent exterior corners
	}
	// DISPLAY-SPACE RAW subtractive (PSX ABR=10: dst − src·gouraud/128) — same display-space fix as the
	// additive twin formation_box_fold: subtract the raw gold gradient from the display-space scratch to
	// darken the emboss shadow, NOT pow(psx_gamma)·psx_brightness (whose ×2.2 over-subtracts). No per-prim
	// 5-bit snap — the resolve quantizes ONCE post-accumulation.
	ALBEDO = clamp(c.rgb * brightness, vec3(0.0), vec3(1.0));
	ALPHA = 1.0; // full subtractive intensity
	DEPTH = fold_depth;
}
