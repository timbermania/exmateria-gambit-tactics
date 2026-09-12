shader_type spatial;
render_mode unshaded;

// Minimal shader for untextured black geometry (map border/skirt polygons).
// Uses the unified OT depth model (ADR-0009), MAP_SKIRT mode (8), which nudges
// the skirt just BEHIND textured map faces to break depth ties — the same
// per-face centroid path the map shader (indexed_color) uses.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// FFT per-polygon visible-angles cull (PSX renderer Stage 4).
// CUSTOM1.r carries the polygon's 16-bit bitfield, gated by F3 toggle.
#include "res://addons/exmateria_battlefield/terrain/fft_visible_angles.gdshaderinc"

// PAR (ADR-0036): Pattern 1, full-stretch — the skirt's shape must follow the
// stretched map. Multiplies clip_pos.x only; CUSTOM0 stays PAR-blind. Via the
// shared seam (ADR-0060).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Per-face centroid in CUSTOM0 (local space) -> MODELVIEW; fixed MAP_SKIRT mode.
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 8);

	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// FFT visible-angles cull, gated by VISIBLE_ANGLES_CULL_MODE in the seam
	// (a `const`, not a runtime toggle — ADR-0190 dec. 1). Runs
	// BEFORE PAR so the final POSITION write is the seam helper; a culled vertex
	// is already off-screen (2,2,2,1), and scaling its x keeps it off-screen.
	fft_apply_visible_angles_cull(clip_pos, CUSTOM1.r);
	// PAR (Pattern 1, full-stretch, via the shared seam).
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	ALBEDO = vec3(0.0);
	DEPTH = ot_computed_depth;
}
