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

	THE FLAT VARIANT (ADR-0189): the unit sprite as drawn on the formation/roster
	screen, a flat ORTHOGRAPHIC UI scene. It differs from the two battle variants
	in exactly three ways:

	  (a) no PAR anchor stretch (ADR-0036/0044) — there is no horizontally
	      stretched map here for the billboard to track;
	  (b) no OT DEPTH write (ADR-0009) — depth comes from native geometry Z,
	      because the vertex writes a plain POSITION;
	  (c) it owns the change-job commit modulation (the cj_* uniforms below).

	IT DOES WRITE AND TEST DEPTH. The render_mode below carries neither
	depth_draw_never nor depth_test_disabled — Godot's defaults (depth_draw_opaque,
	depth test on) apply. ADR-0077 dropped them, and the note on the render_mode
	says why. This block used to claim the opposite — that the variant "composites
	by render_priority like the orb/box/bg" — which described the pre-ADR-0077
	world that ADR was written to abolish; it was read as evidence this shader
	would break the compositor, and it is deleted here (#634).

	Its rung on the formation depth ladder is RP_UNIT_BODY, materialized into real
	world Z by FormationScene (DepthMode.rung_z) — not by a paint-order priority.

	The tile-compositing body, the uniform names, palette handling and
	color_apply all come from the SHARED include, so SpriteLayerManager drives
	this identically to the battle material. This file was a 1,018-line hand-synced
	fork of that include until ADR-0189 dec. 1; there is no fork to re-sync now.
*/

shader_type spatial;
// ADR-0077: the OPAQUE body now WRITES DEPTH (dropped depth_draw_never / depth_test_disabled) at its
// unit rung. This REPLACES the old stencil-silhouette hack: the box is a compositor_layer member at a
// FARTHER rung, so the fold's depth test occludes it BEHIND the body per-fragment (PSX OT bucket 3-4 box
// behind body 6) directly from the real-Z ladder — the "box under body" occlusion, no stencil needed.
// The earlier "OT depth culled the sprite against the depth-off background" problem is gone now that the
// background also writes depth (same reversed-Z convention). The body's vertex writes a plain POSITION,
// so native geometry Z is the depth. Any residual stencil write is vestigial (Mobile-composite era).
render_mode unshaded, cull_disabled;
stencil_mode write, compare_always, 1;

// The sprite compositor — uniforms, the tile-compositing body, billboard(), and the published
// stages unit_paint / unit_colour / unit_light — is shared with the two battle variants
// (ADR-0189 dec. 1/2). This file was a 1,018-line FORK of it whose own header asked a human to
// "re-sync this fork" when the compositor changed materially; 558 of its 619 code lines were
// already byte-identical to the include. What actually differs is below: no PAR, no OT DEPTH
// write, and the change-job commit modulation.
//
// PAR is deliberately NOT included (ADR-0189 dec. 6): this variant applies none, and reaching
// the seam while never using it is the state check_par_shaders.py exists to prevent.
#include "res://addons/exmateria_sprite_rig/render/unit_sprite_body.gdshaderinc"

// --- Change-Job COMMIT cutscene (CHANGE_JOB_COMMIT.md §§7-8) --------------------------------
// Two mechanisms the ROM runs over the centre-unit quads during the 240-frame commit beat.
// Both default INERT, so every other body on the screen renders byte-identically.
//
// The quad's UV maps to sprite LOC space isotropically (pxl_pt_to_mesh collapses both axes to
// loc/atlas_w), so `loc = (UV - 0.5) * 256 - cj_loc_bias` recovers the sprite pixel under this
// fragment — the space both mechanisms below are authored in.
uniform bool cj_active = false;
// Revealed fraction of the DISSOLVE, 0 -> 1 over the beat. The ROM shuffles the sprite's 480
// bytes and consumes 2 per frame; a byte is TWO pixels at 4bpp, which is why the grain is a
// 2x1 loc-pixel cell and why the dissolve reads granular rather than as a blend.
uniform float cj_dissolve = 0.0;
// 0 = this is the OLD job's body (show cells NOT yet consumed), 1 = the NEW job's (show the
// consumed ones). The two senses are exact complements, so no pixel shows both or neither.
uniform float cj_dissolve_sense = 0.0;
// The four gouraud CORNER multipliers (already /128 — PSX 0x80 is neutral 1.0x), bilinear over
// the sprite's visible bbox: TL, TR, BL, BR. They drive to RED/GREEN/BLUE/YELLOW, so this is a
// prismatic shimmer across the sprite, not a uniform brighten.
uniform vec3 cj_tint_tl = vec3(1.0);
uniform vec3 cj_tint_tr = vec3(1.0);
uniform vec3 cj_tint_bl = vec3(1.0);
uniform vec3 cj_tint_br = vec3(1.0);
// The composited frame's visible bbox in LOC space (x, y, w, h) — the tint's gradient domain.
// The ROM's quad IS the 24x40 sprite, so the ramp must span the sprite, not the 256-loc quad.
uniform vec4 cj_bbox_loc = vec4(0.0, 0.0, 24.0, 40.0);
uniform vec2 cj_loc_bias = vec2(0.0, -2.0);

// A stable per-cell random field. The ROM's order is one specific shuffled permutation of that
// sprite's 480 bytes; here the same 0->100% random-order discard comes from hashing the cell,
// which the spec names as the port's other option ("a threshold shader against a per-pixel
// random field"). The MODEL still owns the permutation, the 2-cells-per-frame rate and the
// exact-exhaustion property — this only needs a fixed random ORDER to threshold against.
float cj_cell_noise(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453123);
}


void vertex() {
	billboard(
		MODELVIEW_MATRIX,
		VIEW_MATRIX,
		INV_VIEW_MATRIX,
		MODEL_MATRIX,
		MODELVIEW_NORMAL_MATRIX
	);

	// Flat ortho UI: no OT depth (the depth test is off — the sprite composites by
	// render_priority against the orb/box/bg) and no PAR x-stretch. billboard() above still
	// faces the quad at the camera and preserves the holder's basis scale, which is all a
	// screen-space roster cell needs. The varying is still written, because the shared
	// debug_show_depth path reads it.
	ot_computed_depth = 0.0;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
}


void fragment() {
	vec3 albedo;
	float sprite_alpha;
	unit_paint(UV, albedo, sprite_alpha);

	if (sprite_alpha < UNIT_ALPHA_CUTOFF) {
		discard;
	}

	// The commit DISSOLVE. Cells are 2x1 loc pixels (a 4bpp byte); a cell is "consumed" once
	// its noise falls under the revealed fraction, at which point the OLD body stops drawing
	// it and the NEW body starts. Runs before the stencil note below deliberately: a
	// dissolved-away texel must not write depth either, or the old body would keep occluding.
	if (cj_active) {
		vec2 cj_loc = (UV - vec2(0.5)) * 256.0 - cj_loc_bias;
		float n = cj_cell_noise(floor(vec2(cj_loc.x * 0.5, cj_loc.y)));
		bool consumed = n < cj_dissolve;
		if (consumed != (cj_dissolve_sense > 0.5)) {
			discard;
		}
	}
	// (Only opaque sprite texels reach here — transparent ones discarded above — so the
	// STENCIL buffer receives the unit SILHOUETTE, which the formation composite tests for
	// occlusion.)

	albedo = unit_colour(albedo);

	// The commit GOURAUD TINT: four corner multipliers bilinear over the sprite's visible
	// bbox (PSX POLY_GT4 corner order TL/TR/BL/BR). This is the whole reason the stages are
	// published separately rather than the fragment being shared — the PSX applies gouraud
	// as a modulate on the texel BETWEEN the colour stack and the ambient term, and only a
	// seam at exactly that point lets this screen have it without forking the compositor.
	if (cj_active) {
		vec2 cj_loc = (UV - vec2(0.5)) * 256.0 - cj_loc_bias;
		vec2 cj_n = clamp((cj_loc - cj_bbox_loc.xy) / max(cj_bbox_loc.zw, vec2(1.0)), vec2(0.0), vec2(1.0));
		vec3 cj_top = mix(cj_tint_tl, cj_tint_tr, cj_n.x);
		vec3 cj_bot = mix(cj_tint_bl, cj_tint_br, cj_n.x);
		albedo = clamp(albedo * mix(cj_top, cj_bot, cj_n.y), vec3(0.0), vec3(1.0));
	}

	ALBEDO = unit_light(albedo);

	// No DEPTH write: depth test/draw are off for this variant.

	// Debug: visualize depth as grayscale (white = near, black = far in reversed-Z).
	if (debug_show_depth) {
		ALBEDO = vec3(ot_computed_depth);
	}
}
