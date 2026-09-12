/*
	UNIT SPRITE COMPOSITOR — ADDITIVE VARIANT

	Used ONLY for the battle→scenario-6 dead-unit fade ({43} Call Function
	4): the fading corpse is swapped onto this shader while its palette ramps to
	black, so `blend_add` adds progressively less until it contributes nothing —
	the sprite dissolves INTO the background instead of turning into a black
	silhouette. This mirrors the PSX behaviour (FUN_8008945c sets the sprite's
	tpage ABR to mode 1 = additive; the palette darkens to near-black + STP).
	See research/working_documents/SCENARIO6_DEAD_UNIT_FADE.md §5 / §6.1.

	The compositor body lives in unit_sprite_body.gdshaderinc, shared with the opaque
	unit.gdshader and the flat formation variant. This file differs from unit.gdshader in
	exactly two places: the render_mode above, and a single `ALPHA = sprite_alpha;` in the
	fragment (ADR-0189 dec. 1 — this used to be a `#define UNIT_ADDITIVE` + `#ifdef` in
	the shared body).
*/
// Vault: [[Display Space Blend Fold]]

shader_type spatial;
// blend_add: framebuffer += ALBEDO * ALPHA. depth_draw_never: an additive,
// dematerialising sprite must not write opaque depth (it still depth-TESTS
// against the map, so walls occlude it correctly).
// compositor-exempt: pre-clamped-single-layer — dead-unit fade ({43}). The corpse sprite's ALBEDO is palette-clamped to [0,1]
// in-shader (unit_sprite_body.gdshaderinc, after color_apply) BEFORE the blend, and its CLUT ramps
// to black so the additive contribution decays to zero — a SINGLE fading sprite layer, not a stack of
// overlapping additives, so it needs no Mobile UNORM per-step clamp. COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_add;

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

	if (sprite_alpha < UNIT_ALPHA_CUTOFF) {
		discard;
	}

	// The one line the opaque variant does not have. blend_add computes
	// `framebuffer += ALBEDO * ALPHA`, so emitting coverage scales the sprite by it. The
	// dead-unit fade ({43} Call Function 4) ramps the palette to black through
	// unit_colour() below, so the additive contribution decays to zero and the corpse
	// dissolves INTO the background instead of turning into a black silhouette.
	// research/working_documents/SCENARIO6_DEAD_UNIT_FADE.md §5 / §6.1.
	ALPHA = sprite_alpha;

	ALBEDO = unit_light(unit_colour(albedo));

	DEPTH = ot_computed_depth;

	if (debug_show_depth) {
		ALBEDO = vec3(ot_computed_depth);
	}
}

