// Shared body for the FORMATION-screen gold selection box (range-sheet sprite,
// §11), drawn EXACTLY like the effect particle / formation orb. Only a QUARTER
// diamond is on disc (BOX.tga); the scene draws it as four quadrant quads, each
// mirroring the ¼ texel via `uv_flip` (x / y / xy).
//
// The box is emitted as TWO coincident 4-quadrant passes offset 1px in Y — an
// ADDITIVE pass (PSX tpage 0x3F, abr=1) 1px higher and a SUBTRACTIVE pass (tpage
// 0x5F, abr=2) 1px lower — which together emboss the gold edge with a dark drop
// shadow beneath it. This was long mis-modelled as "the sub pass cancels the add
// (fb+gold-gold≈fb)"; the two passes are NOT coincident (structB.y = structA.y-1
// in FUN_8011712c), so they don't cancel — DYNAMICALLY CONFIRMED on the live
// framebuffer (2026-07-17): additive struct @0x8018c878 tpage 0x3F Y=135,
// subtractive struct @0x8018c864 tpage 0x5F Y=136. See §11.2.
//
// BOX.tga is indexed (R = index*17). BOX.palette.tga is a 16x1 gold CLUT (idx0
// transparent exterior corners, punched to alpha 0; the box carries no opaque
// STP=0 texels — its semi-transparency IS the add/sub blend, not the STP split).
// Each pass tones the raw sRGB palette colour with the SHARED globals
// (psx_gamma=1.4, psx_brightness=2.2 — the same knobs the particle/orb shaders
// read, scrubbable in the F3 calibration panel), mirroring effect_particle_mode1
// (add) / effect_particle_mode2 (sub).
uniform sampler2D index_tex : filter_nearest;
uniform sampler2D palette_tex : filter_nearest, hint_default_transparent;
// Per-quadrant mirror: (0,0)=none (1,0)=x-flip (0,1)=y-flip (1,1)=xy-flip.
uniform vec2 uv_flip = vec2(0.0, 0.0);
uniform float brightness = 1.0;      // PSX gouraud/128 modulate
global uniform float psx_gamma;      // shared linearization exponent (1.4)
const float PSX_OUTPUT_LEVEL = 2.2; // shared output/additive level (was the deleted
// psx_brightness global; ADR-0074 endgame). The in-scene twin blends into a LINEAR buffer,
// so it keeps this ÷255→÷128 output level (the display-space fold bakes it per-producer).

void vertex() {
	// Plain screen-space quad (the scene already places/scales it in ortho world).
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
}

// Raw palette sample under the quadrant's mirror: .rgb = sRGB gold, .a = idx0
// transparency (0) vs gold (1). Sampled RAW (no source_color) — the index/CLUT
// encoding must not be sRGB-decoded or the `index*17` lookup lands off-palette.
vec4 box_sample(vec2 raw_uv) {
	vec2 uv = mix(raw_uv, vec2(1.0) - raw_uv, uv_flip);
	int idx = int(round(texture(index_tex, uv).r * 15.0));
	return texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
}

// PSX RGB555 framebuffer quantization — snap to 5 bits/channel so the gold steps
// discretely like the real machine. Source-side approximation (the true snap is
// post-blend; global fix tracked in #183). Twin of formation_orb.gdshaderinc.
vec3 quantize5(vec3 c) {
	return floor(clamp(c, vec3(0.0), vec3(1.0)) * 31.0 + 0.5) / 31.0;
}
