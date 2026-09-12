shader_type spatial;

// Faithful FFT PSX unit shadow (see research/working_documents/UNIT_SHADOW_RENDERING.md).
//
// The PSX draws the shadow as a single POLY_FT4 (GPU code 0x2E) — a fixed 20x20
// world-unit textured quad pinned to the terrain under the unit's feet — with TPAGE
// 0x5F, i.e. ABR mode 2 = *subtractive* (framebuffer = ground - front, clamped >= 0).
// The front color is the CLUT texel modulated by a neutral 0x808080 primitive, so
// front == texel. We reproduce this with `blend_sub`: Godot's blend_sub computes
// framebuffer = framebuffer - ALBEDO*ALPHA, matching ABR mode 2 exactly.
//
// The texture (assets/materials/unit_shadow.png) already bakes the grayscale CLUT
// ramp (center idx1 = 0xE0 -> darkest subtraction, rim idx14 = 0x08 -> ~none,
// idx0/15 = transparent corners), so ALBEDO is literally the per-channel amount to
// subtract from the ground. No procedural ellipse, no height scaling, no height fade,
// no camera billboarding — this is a flat ground decal (UnitShadow.gd drapes it onto
// the terrain normal).
//
// unshaded: constant darkness, no lighting. cull_disabled: visible from either side
// (the quad may tilt on slopes). depth_draw_never: it's a transparent ground decal; its
// *tested* depth is the OT value (nudged in front of the tile, see below) so it wins the
// test against the floor, but it must not *write* depth and occlude the sprite.
// compositor-exempt: off-fork-fallback — OFF-FORK fallback for the shadow prim. On the
// 4.8 Forward+ fork UnitShadow.gd wears the `shadow_blob_fold` twin (Fold.shader) and the
// blob composites in the display-space scratch, ordered AFTER the additive tile overlays it
// overlaps so the subtraction lands last (add-then-sub — the ceiling clamp erases the shadow
// the other way round). This in-scene file only draws where the fold does not exist.
render_mode blend_sub, unshaded, cull_disabled, shadows_disabled, depth_draw_never;

// Unified Ordering-Table depth (ADR-0009). CRUCIAL: the shadow does NOT sort by its
// own geometry. Faithful to the PSX (FUN_8007d5d0 inserts the shadow packet at
// ot_base + unit[0x128]*4 — the UNIT's OWN OT slot, see UNIT_SHADOW_RENDERING.md §2),
// the shadow is projected from the SAME representative point as the sprite —
// `unit_depth_point`, pushed each frame by UnitShadow.update() = the sprite mesh
// origin + depth_center_height, exactly the point unit.gdshader projects. So the
// shadow co-sorts with the unit: it inherits the unit's front-of-terrain bucket
// (never z-fights the floor the unit stands on) and, via the SHADOW nudge (mode 9,
// one hair less forward than the sprite's UNIT mode 6), sorts just BEHIND the sprite
// where they overlap. The shadow's own ground origin (MODEL_MATRIX[3].xyz) is used
// only to place the quad geometry, never for depth. depth_draw_never (below) keeps
// the decal's *tested* depth as this OT value while it never *writes* depth.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// The unit's OT representative point (world space), pushed per-frame from
// UnitShadow.update(): sprite mesh origin + (0, depth_center_height, 0). Shared with
// the sprite so shadow-vs-world sorting == sprite-vs-world sorting.
uniform vec3 unit_depth_point = vec3(0.0);

// PAR (ADR-0036): Pattern 1, full-stretch — the shadow is a flat ground decal that
// sits on the map and MUST stretch horizontally with it, exactly like the map, the
// map skirt, and tile overlays. Without this the shadow is the one scene mesh that
// skips the project-wide pixel-aspect stretch, so it drifts out from under the
// sprite's feet (worse the further the unit is off screen-center). PAR comes from
// the shared seam (ADR-0060), so one debug scrub moves every mesh in unison.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

// The baked CLUT-gray shadow blob. filter_nearest keeps the PSX look (GPU does no
// texture filtering). source_color so it shares the sprite color pipeline.
uniform sampler2D shadow_tex : source_color, filter_nearest;

// Final darkness multiplier — tune against shadow_captures/orbonne_shadow_scene.png.
// 1.0 == the raw ROM subtraction amount.
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	// Per-object OT depth, SHADOW mode (9): project the UNIT's representative point
	// (unit_depth_point, world-space, shared with the sprite) once, flat across the
	// quad — NOT the shadow's own origin. This is what makes the shadow co-sort with
	// the unit (PSX ot_base + unit[0x128]*4). VIEW_MATRIX because the point is
	// world-space (matches unit.gdshader's per-object call).
	ot_computed_depth = ot_depth(unit_depth_point, PROJECTION_MATRIX, VIEW_MATRIX, 9);

	// PAR (Pattern 1, full-stretch, via the shared seam): the ground decal
	// stretches with the map and stays under the sprite's PAR'd feet.
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	vec4 t = texture(shadow_tex, UV);
	// idx0/15 corners are transparent in the ROM texture — don't draw them.
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb * intensity;
	ALPHA = 1.0;
	// Flat per-object OT depth (one value across the quad): tested against the floor's
	// OT depth so the decal sorts in front of the tile it drapes, no z-fight.
	DEPTH = ot_computed_depth;
}
