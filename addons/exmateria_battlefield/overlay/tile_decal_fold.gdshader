shader_type spatial;
// MONOMORPHIC tile-decal fold material (ADR-0074 ④b, issue #229): the routed additive tile overlays
// (PLACEMENT_PLAYER / ENEMY / CONTESTED — the blue Move / red Attack highlights) as a SINGLE baked
// world-space ArrayMesh wearing `compositor_layer`, folded additively into the display scratch. Its
// four axes are BAKED, never data-driven:
//   geometry = world_quad  — the verts are baked GROUND positions, a FLAT map decal, NEVER billboarded.
//              THIS bake IS the fix: the engine fold read only `mode` and billboard-interpreted the old
//              pool-staged prims, so the Move/Attack tiles VANISHED on Forward+ (the live bug, ADR-0074).
//   PAR      = full         — Pattern 1 map-attached horizontal stretch (pixel_aspect_full).
//   discard  = none         — solid CPU-colored quads (barber-pole via TileOverlayColor), no texture.
//   blend    = additive.
//
// Forward+ / fork only (compositor_layer + engine Pass B). OCCLUSION: depth_draw_never + depth-test
// ENABLED, DEPTH = ot_computed_depth from the per-tile CUSTOM0 centroid (STANDARD; the CPU
// DECAL_LIFT is baked into the vertex Y so the decal wins the depth test against its opaque map tile).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: untextured — ALBEDO = color direct (PSX flat/gouraud: no texel, no >>7). ADR-0074 color-math clause.

// Unified PSX Ordering-Table depth (ADR-0009): per-tile centroid baked in CUSTOM0, STANDARD mode.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
// PAR (ADR-0036): Pattern 1, full-stretch — the map-attached decal shares the map's horizontal stretch.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

// No color calibration global (ADR-0074 endgame). This is an UNTEXTURED display-color prim: COLOR is
// the RAW resolved barber-pole CLUT value (TileOverlayColor.flat_color, pow(gamma) pulled out), added
// straight in display space. The old `* psx_brightness` (2.2) was a SPURIOUS double-count on an
// already-absolute display color — the same overbright bug the formation box/orb/cursor shed. Dropped.

void vertex() {
	// Per-tile centroid (lifted) in CUSTOM0 (local == world here) -> MODELVIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);
	// PAR (Pattern 1, full-stretch): the decal rides the map's horizontal stretch.
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	// Solid additive decal: the per-vertex COLOR is the tile's RAW resolved barber-pole CLUT color,
	// added straight in display space (PSX flat/gouraud: no texel, no >>7, no ×brightness).
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
