shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// PSX projectile 3D models (arrow / stone / shuriken): opaque Gouraud-shaded,
// vertex-color, untextured polygons — the per-vertex COLOR interpolates across
// each face. These are multi-face ENSEMBLES, so they sort per face like the map
// (NOT per object): ProjectileMeshBuilder bakes the AVSZ3/AVSZ4 per-face
// centroid into CUSTOM0 (local space) and we project it through MODELVIEW in
// STANDARD mode (no bias — a projectile is airborne, not tied to a tile).
// PSX has no per-pixel alpha (only the STP blend modes, which these don't use),
// so this is a plain opaque OT shader, not StandardMaterial3D. See ADR-0009 and
// the "Rendering depth" cluster in CONTEXT.md.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// PAR (ADR-0036): Pattern 2, anchor-only. A 3D projectile model (arrow / stone /
// shuriken) is multi-face but world-anchored — its faces should track the
// stretched-screen position of the projectile, but the arrow's shape stays
// authored. Anchor = MODEL_MATRIX[3] (the projectile node origin).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Per-face centroid in CUSTOM0 (local) -> MODELVIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);

	// PAR (Pattern 2, anchor-only, via the shared seam): stretch 1.0 = native
	// width, so the arrow's geometry keeps its authored proportions while its
	// anchor tracks the PAR-stretched screen position.
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, 1.0);
}

void fragment() {
	// Vertex color is already linear (matches the prior StandardMaterial3D path,
	// which used vertex_color_use_as_albedo with no sRGB flag).
	ALBEDO = COLOR.rgb;
	DEPTH = ot_computed_depth;
}
