shader_type spatial;
// FORMATION gold selection box — ADDITIVE fold pass (PSX tpage 0x3F, abr=1; ADR-0077 fold member).
// Body + axes in formation_box_fold.gdshaderinc. Sits 1px HIGHER than the subtractive twin
// (formation_box_sub_fold) and folds at a NEARER depth-ladder rung (RP_BOX_ADD > RP_BOX_SUB), so it
// paints over the sub shadow — the embossed gold edge. depth_draw_never keeps the fold ordering the
// render_layer_order ladder (not depth), while DEPTH occludes the box behind the unit body.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, compositor_layer;

// Vault: [[Display Space Blend Fold]]
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://src/ui3/shaders/formation_box_fold.gdshaderinc"

void fragment() {
	vec4 c = box_sample(UV);
	if (c.a < 0.25) {
		discard; // idx0 transparent exterior corners
	}
	// DISPLAY-SPACE RAW additive (PSX ABR=01: dst + src·gouraud/128), NOT the particle
	// pow(psx_gamma)·psx_brightness path. The box CLUT (0x7F65) is an already-bright gold GRADIENT
	// (idx1 248,216,120 → idx15 near-black) and the fold scratch is display-space sRGB, so the palette
	// value is added RAW. The old ×2.2 clipped idx1–7 all to 1.0, collapsing the gradient into a thick
	// pale band — live PSX box median is (216,176,72) deep amber, the port read (255,255,115) pale.
	// Mirror: feedback_hud_sprite_additive_fold (clamp(col·brightness) in display space). No per-prim
	// 5-bit snap either — the resolve (foldsurface_resolve.glsl) quantizes ONCE post-accumulation.
	// [effect-parity 2026-07-30, savestate1 Ramza; supersedes the "faithful at 1.0" oracle verdict.]
	ALBEDO = clamp(c.rgb * brightness, vec3(0.0), vec3(1.0));
	ALPHA = 1.0; // full additive intensity
	DEPTH = fold_depth;
}
