shader_type spatial;
render_mode unshaded;

// Debug-only tile-grid overlay. Traces each tile's edges + a center cross as
// PRIMITIVE_LINES so you can eyeball how centered a unit's feet anchor sits on
// its tile. Map-attached geometry, so it obeys the same two placement seams as
// every other battle mesh:
//   - PAR (ADR-0036/0060): Pattern 1 full-stretch, so the grid stretches WITH
//     the PAR-stretched map (else it drifts horizontally off the units/tiles).
//   - OT depth (ADR-0009): TILE_OVERLAY mode (7) — sits just in front of the
//     tile surface and behind the unit sprite, like the range-tile overlay.
// Per-vertex COLOR distinguishes tile borders from the center cross.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// CUSTOM0 = the owning tile's world centroid (flat per line), TILE_OVERLAY mode.
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 7);
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// PAR (Pattern 1, full-stretch) via the shared seam.
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	DEPTH = ot_computed_depth;
}
