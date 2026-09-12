// Shared body for the IN-SCENE range-overlay tile shaders (tile_overlay_mode0 /
// tile_overlay_opaque).
//
// PSX semi-transparency is selected by an ABR (semi-transparency rate) blend
// mode, NOT a free alpha — so, exactly like the effect_particle_mode0..3
// shaders this mirrors, each ABR mode is its own thin shader supplying only its
// `render_mode` blend + a fragment() that composites accordingly. The CLUT
// sampling itself is shared one level down, in tile_overlay_clut.gdshaderinc,
// because the routed (folded) tile needs it too and may not see the `pow` below.
// This file is the IN-SCENE half: the sRGB->linear conversion (whose return leg
// is the pipeline's tonemap), the OT depth, and the PAR stretch.
// See ADR-0022 (indexed texture), ADR-0009 (OT depth), ADR-0074 (the fold).
// Vault: [[Display Space Blend Fold]]
// Vault: [[Tile Overlay]]
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
#include "res://addons/exmateria_battlefield/overlay/tile_overlay_clut.gdshaderinc"

// srgb_gamma: the palette-linearization exponent. The CLUT is always run through
// pow(rgb, srgb_gamma) — the mechanism is uniform across every tile — but the
// exponent is a PER-TYPE tunable constant (TileOverlayConfig._params), because
// different blend modes / looks want a different conversion. 2.2 is the legacy
// default; lower values brighten + desaturate (e.g. CURSOR_ACTIVE ≈ 1.0 to match
// the in-game move-tile, which displays the palette ~as linear). See the diagnosis
// notes — our pow(2.2) over-darkened relative to the game.
//
// IN-SCENE ONLY. It has no counterpart in tile_overlay_add_fold.gdshader: a fold
// writes display space and has no tonemap to complete the round trip, so the routed
// tile adds the RAW CLUT colour (check_no_pow_in_fold.py enforces it).
uniform float srgb_gamma = 2.2;
// debug_no_psx: an isolation scene can set this true so the tile renders with
// plain MVP and the default depth (no PAR stretch, no OT-depth override) —
// isolating the LOOK from the game's world-placement math. Default false = real
// game behavior.
uniform bool debug_no_psx = false;

// PAR (ADR-0036): Pattern 1, full-stretch — overlays sit on the map and stretch
// with it, via the shared seam (ADR-0060).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Per-face centroid in CUSTOM0 (local space). TILE_OVERLAY mode (7) nudges it
	// just in front of the underlying map tile. One model: ADR-0009.
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 7);

	// PAR (Pattern 1, full-stretch, via the shared seam). debug_no_psx bypasses
	// the stretch for the isolation scene (LOOK without world-placement math).
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = debug_no_psx ? clip_pos : pixel_aspect_full(clip_pos);
}

// Resolve the tile's palette color for this fragment, IN LINEAR SPACE: the shared
// CLUT lookup, linearized by pow(srgb_gamma), then the PSX primitive modulation.
// Returns the rgb in .rgb and the palette coverage alpha (tint-modulated) in .a.
// Each mode shader composites that .a per its PSX ABR blend — index 0 carries
// a == 0 so the transparent slot drops out under every mode.
vec4 tile_overlay_color(vec2 frag_uv, float time) {
	vec4 col = tile_overlay_clut(frag_uv, time);
	return tile_overlay_modulate(vec4(pow(col.rgb, vec3(srgb_gamma)), col.a));
}
