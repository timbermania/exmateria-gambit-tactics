shader_type spatial;

// FOLD TWIN of shadow_blob.gdshader — the unit's ground shadow as a display-space
// fold member (ADR-0074). Byte-identical fragment to its in-scene twin; the ONLY
// differences are `compositor_layer` in the render_mode and the `Fold.add` stamp
// UnitShadow.gd puts on the carrier. Off-fork the in-scene twin draws instead
// (Fold.shader picks; Fold.owns() is the predicate).
//
// WHY IT MUST FOLD. The shadow is PSX ABR mode 2 — `ground - blob`, clamped >= 0 in
// the 8-bit DISPLAY framebuffer. In-scene on Forward+ it subtracts a display-magnitude
// constant from LINEAR light, and worse, it lands in the wrong ORDER relative to the
// additive tile overlays it overlaps: the routed cursor/placement decals composite in
// the fold scratch AFTER the whole in-scene pass, so an in-scene shadow was always
// sub-then-add. Clamping is non-commutative and the CEILING is what bites — over a
// bright additive tile, `clamp(g + c)` and `clamp(clamp(g - s) + c)` both saturate to
// white and the shadow VANISHES. Folded, both prims sit in the same clamping scratch
// and DepthMode's order key paints the tile first, the shadow second (add-then-sub),
// which is also what PSX does: the tile panel sits at the tile's OT slot and the
// shadow packet at the UNIT's own slot (ot_base + unit[0x128]*4), one bucket nearer,
// and the OT paints back-to-front. See UNIT_SHADOW_RENDERING.md §2 and
// COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md (this retires its Category-B row: the quad
// drapes by rotating its whole BASIS to the terrain normal — UnitShadow.gd — so it is
// a rigid quad, not the arbitrary mesh that scoping pass assumed).
render_mode blend_sub, unshaded, cull_disabled, shadows_disabled, depth_draw_never, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7; the ROM
// modulates this blob by a neutral 0x808080, so the texel passes through unscaled).
// ADR-0074 color-math clause. NO pow, NO psx_brightness: the baked CLUT ramp in
// unit_shadow.png IS the display-space amount to subtract.

// Unified Ordering-Table depth (ADR-0009), identical to the in-scene twin: the shadow
// does NOT sort by its own geometry, it projects the SAME representative point the
// sprite does (`unit_depth_point`), so it inherits the unit's front-of-terrain bucket
// and sorts one hair behind the sprite (SHADOW mode 9 vs UNIT mode 6).
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// The unit's OT representative point (world space), pushed per-frame from
// UnitShadow.update(): sprite mesh origin + (0, depth_center_height, 0).
uniform vec3 unit_depth_point = vec3(0.0);

// PAR (ADR-0036): Pattern 1, full-stretch — a flat ground decal stretches with the map.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

// The baked CLUT-gray shadow blob (assets/materials/unit_shadow.png).
uniform sampler2D shadow_tex : source_color, filter_nearest;

// Final darkness multiplier. 1.0 == the raw ROM subtraction amount.
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	// Per-object OT depth, SHADOW mode (9): the UNIT's representative point, flat
	// across the quad. VIEW_MATRIX because the point is world-space.
	ot_computed_depth = ot_depth(unit_depth_point, PROJECTION_MATRIX, VIEW_MATRIX, 9);

	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	vec4 t = texture(shadow_tex, UV);
	// idx0/15 corners are transparent in the ROM texture — don't draw them.
	if (t.a < 0.5) {
		discard;
	}
	// blend_sub == PSX ABR mode 2: scratch = scratch - ALBEDO, UNORM-clamped >= 0.
	ALBEDO = t.rgb * intensity;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
