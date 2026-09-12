/*
	UNIT SPRITE COMPOSITOR SHADER

	This shader renders PSX-era sprite animations on a 3D billboarded quad mesh.
	It composites multiple sprite tiles from texture atlases, applying transformations
	(translation, rotation, flipping) to each tile to recreate the tile-based sprite
	system from legacy games.

	COORDINATE SPACES:
	- Pixel Space: Raw pixel coordinates from original sprite data (e.g., x=24, y=288)
	- Texture Space: UV coordinates (0.0-1.0) on the sprite atlas texture
	- Mesh Space: UV coordinates (0.0-1.0) on the quad mesh being rendered

	The shader constantly converts between these spaces because texture and mesh
	aspect ratios differ, requiring Y-coordinate adjustments.

	RENDERING LAYERS:
	- type1: Character body sprites
	- wep1: Weapon sprites
	- eff1: Effect sprites (magic, impacts, etc.)

	Each layer can have up to 10 tiles composited together per frame.
*/
// Vault: [[Cinematic Palette Pipeline]]
// Vault: [[Color Tint Luma Modes]]
// Vault: [[Color Unit Opcode]]
// Vault: [[Display Space Blend Fold]]
// Vault: [[Scenario Camera Framing]]

shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_opaque;

// The sprite compositor — uniforms, the tile-compositing body, billboard(), and the
// published stages unit_paint / unit_colour / unit_light. Shared with the additive
// variant and with the flat formation variant (ADR-0189 dec. 1/2); this file is the
// OPAQUE entry point and owns only its render_mode and its two stage functions.
#include "res://addons/exmateria_sprite_rig/render/unit_sprite_body.gdshaderinc"

// PAR (ADR-0036): Pattern 2, anchor-only. The unit's anchor (object origin) projects
// through MVP, its clip.x gets PAR'd, then the per-vertex billboard offset is added
// un-stretched — so the unit tracks the stretched map but the sprite art renders at
// native PSX pixel aspect. `pixel_aspect` comes from the shared seam (ADR-0060), the same one
// Pattern 1 shaders read, so one debug scrub drives every opt-in subsystem in unison.
// Included HERE and not in the shared body (ADR-0189 dec. 6): the flat formation variant
// applies no PAR, and a body that pulled the seam in would have it reach PAR transitively
// while never using it.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

// Sprite stretch (ADR-0044): horizontal billboard-WIDTH multiplier for the UNIT taxonomy,
// layered on the pixel_aspect anchor below. 1.0 = native art (the ADR-0036 default — units
// don't stretch unless the Unit scrub opts in).
#include "res://addons/exmateria_platform/display_port/unit_stretch.gdshaderinc"


void vertex() {
	billboard(
		MODELVIEW_MATRIX,
		VIEW_MATRIX,
		INV_VIEW_MATRIX,
		MODEL_MATRIX,
		MODELVIEW_NORMAL_MATRIX
	);

	// Unified OT depth: per-object path, UNIT mode (6). Sample at the sprite's visual
	// CENTER (origin + world-up * depth_center_height), not the feet, so the billboard
	// competes with wall mid-height centroids fairly. Elevated tiles still sort correctly
	// (the full 3D point is projected). See ADR-0009.
	vec3 depth_point = MODEL_MATRIX[3].xyz + vec3(0.0, depth_center_height, 0.0);
	ot_computed_depth = ot_depth(depth_point, PROJECTION_MATRIX, VIEW_MATRIX, 6);

	// In NDC: ndc.x = (vertex.x + anchor.x * (pixel_aspect - 1)) / w. With our ortho camera
	// (constant w) and a billboarded quad (all vertices share w in view space), this
	// cleanly stretches only the anchor's screen position; the sprite art's footprint
	// stays at native PSX pixel aspect. Both clips use the billboarded MODELVIEW_MATRIX
	// above, so the billboard's view-space layout is preserved. ADR-0044.
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, unit_stretch);
}


void fragment() {
	vec3 albedo;
	float sprite_alpha;
	unit_paint(UV, albedo, sprite_alpha);

	// Transparent texels are DISCARDED, never emitted with a low ALPHA. That keeps this
	// material genuinely opaque, so it writes depth and seeds the fold scratch (ADR-0077).
	if (sprite_alpha < UNIT_ALPHA_CUTOFF) {
		discard;
	}

	ALBEDO = unit_light(unit_colour(albedo));

	// Flat per-object OT depth (the same value across the billboard), so the sprite sorts
	// against adjacent geometry by its tile origin, not by its mesh face.
	DEPTH = ot_computed_depth;

	// Debug: visualize depth as grayscale (white = near, black = far in reversed-Z).
	if (debug_show_depth) {
		ALBEDO = vec3(ot_computed_depth);
	}
}

