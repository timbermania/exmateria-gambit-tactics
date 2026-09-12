// Shared reveal + ERASE + dither logic for the {91} Show Map Title pass. The
// location-name strip is drawn over the live scene (NOT a black screen): the
// transparent CLUT index 0 lets the scene show through, exactly as the PSX
// additive blend does (show_map_title_op91_decode.md §6.3-§6.5).
//
// Two LEFT->RIGHT wipes (§6.4/§6.5), the key difference from {7D}:
//   * fade-in  = a `reveal` front sweeps L->R; behind it the strip is full.
//   * fade-out = an `erase`  front sweeps L->R (SAME direction); behind it the
//     strip turns back off. So the visible band is between the two fronts —
//     the left end vanishes first, matching the captured erase.
// Both fronts share a soft gouraud edge `edge_frac`; both are normalised to the
// strip content width by the controller, so this stays placement-agnostic.

// The decoded strip (256x16 map-title); idx0 was baked to alpha 0.
uniform sampler2D tex : source_color, filter_nearest;
// Half-size of the strip on screen, as a fraction of the viewport.
uniform vec2 dst_half = vec2(0.5, 0.5);
// Strip centre in screen-UV (the strip sits near the top-centre, y ~0.42).
uniform vec2 dst_center = vec2(0.5, 0.5);
// Reveal front position, 0..1 across the strip width (the fade-in L->R wipe).
uniform float reveal = 0.0;
// Erase front position, 0..1 across the strip width (the fade-out L->R wipe).
uniform float erase = 0.0;
// Soft-edge kernel width as a fraction of the strip width (~32/248).
uniform float edge_frac = 0.129;

// PSX standard 4x4 ordered dither (§6.4), shared with every other Gouraud
// overlay so the strip dithers identically to the map/background.
#include "res://addons/exmateria_platform/dither/psx_dither.gdshaderinc"

float ordered_dither(vec2 frag_xy, vec2 viewport_size) {
	float scale = max(1.0, round(viewport_size.x / 320.0));
	int ix = int(frag_xy.x / scale) & 3;
	int iy = int(frag_xy.y / scale) & 3;
	return float(PSX_DITHER_MATRIX[iy * 4 + ix]) / 8.0;
}

// Map a screen UV to the strip's UV about dst_center; `inside` = within rect.
vec2 card_uv(vec2 screen_uv, out bool inside) {
	vec2 rel = (screen_uv - dst_center) / dst_half;
	inside = abs(rel.x) <= 1.0 && abs(rel.y) <= 1.0;
	return rel * 0.5 + vec2(0.5);
}

// The gouraud level at a strip UV: revealed to the LEFT of `reveal`, erased to
// the LEFT of `erase`, so the lit band is (reveal - erase), dithered at 5-bit.
float reveal_level(vec2 uv, vec2 frag_xy, vec2 viewport_size) {
	float e = max(edge_frac, 1e-4);
	float g_reveal = clamp((reveal - uv.x) / e, 0.0, 1.0);
	float g_erase  = clamp((erase  - uv.x) / e, 0.0, 1.0);
	float g = clamp(g_reveal - g_erase, 0.0, 1.0);
	float d = ordered_dither(frag_xy, viewport_size);
	return clamp(floor(g * 31.0 + d + 0.5) / 31.0, 0.0, 1.0);
}
