// Shared body for the MONOMORPHIC tile-cursor fold materials (ADR-0074 ④c, issue #229). The tile
// cursor's SEMI-TRANS (STP=1) outline as a DIRECT billboard MeshInstance3D wearing compositor_layer,
// folded into the display-space scratch. Its axes are BAKED, not data-driven:
//   geometry = billboard   (rebuilt from the inverse-view basis)
//   frag     = paletted     (indexed RANGETILE sheet -> its 9-row CLUT)
//   discard  = STP-window   (keep the a~=0.5 outline entries: 0.01 < a < 0.9, non-black)
//   PAR      = anchor        (Pattern 2 — art at native PSX aspect, anchor tracks the stretched map)
//   depth    = TILE_OVERLAY(7)
// The BLEND is the one thing the cursor picks at runtime (the `cursor.blend_mode` debug knob): the three
// wrapper shaders cursor_fold_{mix,add,sub} differ ONLY in the render_mode blend, and add25 is the add
// material with level_scale = 0.25. That is material SELECTION among monomorphic shaders (like the
// callback's fold-vs-plain choice), NOT in-shader axis branching — so ADR-0074 still holds.
//
// The cursor's OPAQUE body still draws in-scene (canvas + depth); this folds only the outline.
// RAW display-space texel — NO pow(psx_gamma). The fold blends in the display-space scratch with no
// tonemap after, so linearizing the outline colour would be the gold-box wrong-space bug (a half
// round-trip with no return leg). PSX subtractive ABR adds the raw CLUT texel; mirror
// formation_box_fold / feedback_hud_sprite_additive_fold. Forward+ only.
// [2026-07-31: was `srgb_to_linear ? pow(col, psx_gamma) : col.rgb` — a LIVE landmine (the fold
//  compositor never forced the flag off); see check_no_pow_in_fold.py + the DEMI2 fold-color audit.]
// Vault: [[Display Space Blend Fold]]
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

uniform sampler2D range_sheet : filter_nearest, repeat_disable;               // indexed RANGETILE sheet
uniform sampler2D palette_texture : filter_nearest, hint_default_transparent; // RANGETILE CLUT
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);  // the cursor sprite's RANGETILE sub-rect (x, y, w, h)
uniform float palette_rows = 9.0;   // RANGETILE CLUT height (9 rows) — the fold divides the CLUT V by this
uniform float palette_row = 4.0;    // the cursor's CLUT row
uniform float level_scale = 1.0;    // 0.25 for the ABR11 (add25) mode, 1.0 otherwise

// No psx_gamma / psx_brightness: the cursor is a paletted CLUT prim (col.rgb below IS the PSX display
// colour), so the faithful additive/subtractive is col × gouraud — the box's model. psx_brightness is
// the ÷255→÷128 scale conversion for the effect-POOL modulate only; applying it to a display-native
// CLUT sample double-brightens (see formation_orb_rim_fold, 2026-07-31).
// Sprite stretch (ADR-0044): horizontal billboard-WIDTH multiplier for the EFFECTS taxonomy.
// DECLARED BY THE PORT THAT PUSHES IT, not here — this addon does not own the name and
// must not ask the host for it on its own account (ADR-0190).
#include "res://addons/exmateria_platform/display_port/psx_sprite_stretch.gdshaderinc"

void vertex() {
	// TILE_OVERLAY (7) depth from the model origin (the dagger tip). Occlusion is approximate for mode 7
	// (the GPU ot_depth covers 0..5) but the cursor floats above the map with nothing to occlude it.
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, 7);
	// Camera-facing billboard: rebuild MODELVIEW from the unit inverse-view axes + the model translation.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	// PAR (Pattern 2, anchor-only): the sprite art renders at native PSX pixel aspect while its anchor
	// (model origin) tracks the stretched map. psx_fx_stretch is the EFFECTS width multiplier (ADR-0044).
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, psx_fx_stretch);
}

void fragment() {
	vec2 uv = uv_rect.xy + UV * uv_rect.zw;
	vec4 col = texture(range_sheet, uv);
	// Paletted: recover the RANGETILE index (gray*15) and sample the CLUT at (idx, palette_row).
	int idx = int(col.r * 15.0 + 0.5);
	col = texture(palette_texture, vec2((float(idx) + 0.5) / 16.0, (palette_row + 0.5) / palette_rows));
	// STP-window discard: keep only the semi-transparent outline entries (0.01 < a < 0.9, non-black).
	if (col.a < 0.01 || col.a > 0.9 || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}
	ALBEDO = col.rgb * COLOR.rgb * level_scale;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
