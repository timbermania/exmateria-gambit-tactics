shader_type spatial;
// MONOMORPHIC crystal fold material (ADR-0074 ④a, issue #229): the {92} "turn to crystal" diamond as a
// direct camera-facing billboard MeshInstance3D wearing `compositor_layer`, folded additively into the
// display-space scratch. Its four axes are BAKED, never data-driven — this producer is ALWAYS a
// billboard / alpha-key / NO-PAR / additive sprite, so there is no branching übershader:
//   geometry = billboard   (rebuilt from the inverse-view basis in vertex())
//   discard  = alpha_key    (drop the index-0 key: tex.a < 0.5)
//   PAR      = none          (a billboard needs no map-stretch)
//   blend    = additive      (the bright cyan glow)
// Replaces the pool-borrow + UnifiedPrimStager publish path (COMPOSITOR retirement). The in-scene
// pow(2.2) sRGB->linear is dropped BY DESIGN — the fold blends in display space.
//
// Forward+ / fork only (compositor_layer + the engine Pass B). OCCLUSION: depth_draw_never + depth-test
// ENABLED, DEPTH = ot_computed_depth (reversed-Z) — same contract as effect_fold_add /
// effect_callback_fold: the fold pass binds the shared opaque depth and tests GREATER_OR_EQUAL, so a
// crystal half-behind terrain clips per-fragment while still folding against effects by render_layer_order.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

// Unified PSX Ordering-Table depth (ADR-0009), STANDARD mode.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D crystal_sheet : filter_nearest, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x, y, w, h (normalized) — the current frame's cell

// Display-space gouraud gain (the retired `psx_brightness` global, ADR-0074 endgame). This
// monomorphic producer folds a fixed white-modulated billboard, so the ÷255→÷128 display-gouraud
// scale is a plain constant — baked here as a shader-local const (mirrors the particle path, where
// EngineFoldCompositor.POOL_GOURAUD_GAIN bakes the same value into COLOR). Value is the exact retired
// 2.2 — net-neutral relocation off the global so psx_brightness can be deleted (check the guard
// check_no_psx_brightness_in_fold.py). The name carries no `PSX_` prefix: inside this producer the
// whole fold is a PlayStation reproduction, so the prefix distinguishes nothing (ADR-0129 dec. 10),
// and the compromise it used to record is stated right here in prose, where goal #7 scores zero.
const float FOLD_GAIN = 2.2;

void vertex() {
	// Centred billboard: the QuadMesh is centred on the model origin, so its OT representative point is
	// the model origin (all four corners share it), STANDARD mode. Compute depth BEFORE the billboard
	// rewrite — the origin's view-space position (MODELVIEW translation) is unchanged by the rotation.
	ot_computed_depth = ot_depth(vec3(0.0), PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);
	// Camera-facing billboard preserving the QuadMesh's own size: rebuild MODELVIEW from the unit
	// inverse-view axes + the model translation (the standard Godot manual billboard).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = uv_rect.xy + UV * uv_rect.zw;
	vec4 tex = texture(crystal_sheet, uv);
	// Alpha-key discard: keep semi/opaque texels, drop the index-0 key (the in-scene shader's tex.a < 0.5).
	if (tex.a < 0.5) {
		discard;
	}
	// PSX texture blend: texel * vertex_color (white) * gouraud gain, in display space.
	ALBEDO = tex.rgb * COLOR.rgb * FOLD_GAIN;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
