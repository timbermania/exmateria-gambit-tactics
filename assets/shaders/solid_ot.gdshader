shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Placeholder solid-color projectiles (bullet, potion) and load-failure
// fallbacks: primitive meshes (sphere / cylinder), not ROM ensembles. One
// object-origin OT bucket, like a sprite — no CUSTOM0, no tri/quad concern.
// Exists so NO battle mesh escapes the OT model via StandardMaterial3D (whose
// true per-fragment depth mis-sorts against flat-CUSTOM0 terrain). STANDARD mode
// (no bias). See ADR-0009 and the "Rendering depth" cluster in CONTEXT.md.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform vec3 solid_color : source_color = vec3(1.0);

void vertex() {
	// Object origin (world) -> VIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, 0);
}

void fragment() {
	ALBEDO = solid_color;
	DEPTH = ot_computed_depth;
}
