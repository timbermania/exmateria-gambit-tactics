shader_type spatial;
// The ROUTED, TEXTURED range-overlay tile — the ACTIVE CURSOR tile — as a display-space
// fold member (ADR-0074). Sibling of tile_decal_fold.gdshader, and the difference between
// them is the whole reason this file exists:
//
//   tile_decal_fold  — flat_fill types (the blue Move / red Attack placement decals). One
//                      solid CPU-resolved colour per (type, phase), baked into vertex COLOR.
//                      MANY tiles, ONE batched carrier, `psx-prim: untextured`.
//   this file        — the cursor tile, which is the ONE overlay that SAMPLES the RANGETILE
//                      sheet (flat_fill = false): its barber-pole is a real 13x13 texel
//                      diamond, not a colour. So it keeps the GPU CLUT path and gets its
//                      OWN carrier — which is also what gives it its own fold-order key,
//                      instead of the batch's mean-centroid one.
//
// BLEND. The ROM draws the range/cursor tile panels with a literal tpage 0x3F
// (FUN_8007DB1C), and bits 5-6 of a texpage word are the ABR (semi-transparency rate):
// (0x3F >> 5) & 3 == 1 == B + F, ADDITIVE. (The same decode reads the shadow's 0x5F as
// (0x5F >> 5) & 3 == 2 == B - F, which is the subtraction UNIT_SHADOW_RENDERING.md measured
// live — so the decode is not being invented for this file.)
//
// AND THE WHOLE PANEL IS SEMI-TRANSPARENT, so a fully additive quad is faithful, not an
// approximation. PSX gates ABR per TEXEL on the CLUT entry's STP bit, which
// tools/parse_range_tiles.py preserves in the palette's alpha (a = 128 if stp else 255).
// Row 0 of assets/sprites/textures/RANGETILE.palette.tga — the row this tile samples — reads
// [0, 128 x15]: index 0 transparent, every other entry STP=1. No opaque texels, so this needs
// none of the two-surface opaque/semi split the DAGGER cursor needs (row 4 is the mixed one:
// 128 x6 then 255 x9, the "edges blend, body opaque" CLUT). It was blend mode 4 (opaque) here until
// 2026-09-08: a port choice, never ROM parity, and it made the panel paint over the unit
// shadow that overlaps it. Additive + folded puts both in one clamping scratch in the
// right order (the shadow's OT bucket is the UNIT's, one nearer than the tile's, so it
// subtracts LAST — see UnitShadow.FOLD_RANK for why that order and not the other).
//
// Forward+ / fork only (compositor_layer + engine Pass B). Off-fork the tile falls back to
// the in-scene shaders in TileOverlayConfig.MODE_SHADERS.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). The "texel" is
// the RANGETILE CLUT entry and `tint` is the primitive colour. ADR-0074 color-math clause.

// The CLUT sampling, shared with the in-scene shaders. NOTE the include is the CLUT half
// only, NOT tile_overlay.gdshaderinc: that file carries the sRGB->linear `pow`, which a
// fold must not reach (no tonemap after the fold = a round trip with no return leg;
// tools/check_no_pow_in_fold.py scans the include closure). The routed tile adds the RAW
// display-space CLUT colour, exactly as TileOverlayCompositor._tile_color does on the CPU.
#include "res://addons/exmateria_battlefield/overlay/tile_overlay_clut.gdshaderinc"

// Unified Ordering-Table depth (ADR-0009): per-tile lifted centroid baked in CUSTOM0.
// STANDARD mode (0) — the CPU-side DECAL_LIFT is baked into the vertex Y so the decal wins
// the depth test against its own opaque map tile, exactly as tile_decal_fold does.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
// PAR (ADR-0036): Pattern 1, full-stretch — the map-attached decal shares the map's stretch.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	// RAW CLUT entry (no gamma), then the PSX primitive modulation (mono/tint).
	vec4 c = tile_overlay_modulate(tile_overlay_clut(UV, TIME));
	if (c.a < 0.5) {
		discard;  // CLUT index 0 — the transparent slot; show the terrain, add nothing.
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
