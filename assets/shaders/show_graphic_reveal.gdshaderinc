// Shared reveal + dither logic for the {7D} Show Graphic passes (additive text
// + subtractive drop-shadow). The card is drawn over the live scene (NOT a black
// screen): the transparent CLUT index 0 lets the scene show through, exactly as
// the PSX additive blend does (show_graphic_op7d_decode.md II.3-II.7).
//
// The fade-in is a LEFT->RIGHT wipe (II.4): a `reveal` front sweeps across the
// card with a soft gouraud edge of width `edge_frac`; behind it the card is at
// full brightness. The fade-out ramps the whole-card `grey` uniformly 1->0
// (II.6). `reveal`/`edge_frac` are normalised to the card content width by the
// controller, so this stays placement-agnostic.

// The decoded card (256x16 chapter strip); idx0 was baked to alpha 0.
uniform sampler2D tex : source_color, filter_nearest;
// Half-size of the card on screen, as a fraction of the viewport.
uniform vec2 dst_half = vec2(0.5, 0.5);
// Card centre in screen-UV. The chapter card is NOT centred -- its ISO screen
// top (row 78 of 240) puts the band in the upper third (dst_center.y ~0.36).
uniform vec2 dst_center = vec2(0.5, 0.5);
// Reveal front position, 0..1 across the card width (the L->R wipe).
uniform float reveal = 0.0;
// Soft-edge kernel width as a fraction of the card width (~32/248).
uniform float edge_frac = 0.129;
// Whole-card grey level 0..1 (the fade dim): 1 = full, 0 = gone.
uniform float grey = 0.0;

// PSX standard 4x4 ordered dither (II.7), from the shared PSX_DITHER_MATRIX so
// the card dithers identically to every other Gouraud overlay (map/background).
// Scaled to ~320px PSX density so the period-4 shimmer stays visible at the
// game's real hi-res window instead of collapsing to invisible 1px cells.
#include "res://addons/exmateria_platform/dither/psx_dither.gdshaderinc"

float ordered_dither(vec2 frag_xy, vec2 viewport_size) {
	float scale = max(1.0, round(viewport_size.x / 320.0));
	int ix = int(frag_xy.x / scale) & 3;
	int iy = int(frag_xy.y / scale) & 3;
	// Matrix is an 8-bit signed value; /8 folds it into 5-bit (0..31) steps.
	return float(PSX_DITHER_MATRIX[iy * 4 + ix]) / 8.0;
}

// Map a screen UV to the card's UV about dst_center; `inside` = within the rect.
vec2 card_uv(vec2 screen_uv, out bool inside) {
	vec2 rel = (screen_uv - dst_center) / dst_half;
	inside = abs(rel.x) <= 1.0 && abs(rel.y) <= 1.0;
	return rel * 0.5 + vec2(0.5);
}

// The gouraud level at a card UV: soft reveal front x global grey, dithered at
// the 5-bit step. Behind the front -> 1; ahead -> 0.
float reveal_level(vec2 uv, vec2 frag_xy, vec2 viewport_size) {
	float g = clamp((reveal - uv.x) / max(edge_frac, 1e-4), 0.0, 1.0) * grey;
	float d = ordered_dither(frag_xy, viewport_size);
	return clamp(floor(g * 31.0 + d + 0.5) / 31.0, 0.0, 1.0);
}
