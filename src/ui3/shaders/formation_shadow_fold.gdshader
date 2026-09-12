shader_type spatial;
// FORMATION per-unit DROP SHADOW — subtractive fold variant (PSX tpage 0x5F, abr=2; ADR-0077 fold
// member). Twin of formation_shadow.gdshader: the same 20x20 radial blob (unit_shadow.png) subtracted
// from the floor, byte-identical fragment. It MUST fold (not just render in-scene) because it overlaps
// the gold box at the feet: with the box folded and the shadow left in the transparent color layer,
// Pass C's coverage-discard would clobber the shadow wherever the box drew (the E065-class bug). Folded,
// both sit in the scratch and blend together. The real-Z DEPTH write puts the shadow BEHIND the unit
// body (RP_UNIT_SHADOW < RP_UNIT_BODY), so the body occludes the blob's top and it reads as the bottom
// crescent — the ADR-0077 occlusion, out of the depth ladder. NO psx_gamma / psx_brightness / quantize5
// (those are the additive knobs; a subtractive pass over-darkens with them — see formation_shadow).
render_mode unshaded, blend_sub, depth_draw_never, cull_disabled, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

uniform sampler2D shadow_tex : source_color, filter_nearest;
uniform float intensity : hint_range(0.0, 2.0) = 1.0; // 1.0 == raw ROM subtraction (mirrors shadow_blob)

varying float fold_depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
}

void fragment() {
	vec4 t = texture(shadow_tex, UV);
	if (t.a < 0.5) {
		discard; // transparent corners of the round blob
	}
	// blend_sub == PSX ABR mode 2: scratch = scratch - ALBEDO, UNORM-clamped >= 0.
	ALBEDO = t.rgb * intensity;
	ALPHA = 1.0;
	DEPTH = fold_depth;
}
