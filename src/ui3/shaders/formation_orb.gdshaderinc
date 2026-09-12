// Shared body for the FORMATION-screen glowing orb (range-sheet sprite, §10),
// drawn EXACTLY like the effect particle / tile cursor. The 12x12 orb carries
// BOTH opaque core texels (STP=0, idx 3-6/12, palette a=255) and semi-transparent
// rim texels (STP=1, idx 8-11, palette a=128). PSX picks a blend per-texel via
// the STP bit; Godot's blend mode is compile-time — so, like the particles, the
// orb is drawn in TWO coincident-surface passes that each keep only their half of
// the STP bit:
//   formation_orb_opaque — STP=0 core  (blend_mix, mirrors effect_particle_opaque)
//   formation_orb (mode1) — STP=1 rim   (blend_add, mirrors effect_particle_mode1)
//
// ORB.tga is indexed (R = index*17). ORB.palette.tga is a 16x1 CLUT row whose
// ALPHA carries the PSX STP flag (parse_formation_orb.py): a=0 idx0 transparent /
// a=128 STP=1 rim / a=255 STP=0 core. orb_sample returns the raw sRGB palette
// colour in .rgb and that STP alpha in .a; each pass applies its own tone/blend,
// using the shared globals (psx_gamma=1.4, psx_brightness=2.2 — the SAME knobs the
// particle/cursor shaders read, scrubbable in the F3 calibration panel).
uniform sampler2D index_tex : filter_nearest;
uniform sampler2D palette_tex : filter_nearest, hint_default_transparent;
uniform float brightness = 1.0;      // PSX gouraud/128 (per-cell falloff + pulse)
global uniform float psx_gamma;      // shared linearization exponent (1.4)
const float PSX_OUTPUT_LEVEL = 2.2; // shared output/additive level (was the deleted
// psx_brightness global; ADR-0074 endgame). The in-scene twin blends into a LINEAR buffer,
// so it keeps this ÷255→÷128 output level (the display-space fold bakes it per-producer).

void vertex() {
	// Plain screen-space quad (the scene already places/scales it in ortho world).
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
}

// Raw palette sample: .rgb = sRGB palette colour, .a = STP flag (0 / ~0.5 / 1).
vec4 orb_sample(vec2 uv) {
	int idx = int(round(texture(index_tex, uv).r * 15.0));
	return texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
}

// PSX RGB555 framebuffer quantization — snap to 5 bits/channel (32 levels) so the
// gouraud pulse steps discretely like the real machine instead of a smooth 8-bit
// ramp. Per-shader (source-side) approximation: the true snap is post-blend on the
// composited framebuffer, which a hardware-blended sprite can't read — the proper
// global post-process is tracked in #183; this holds until it lands.
vec3 quantize5(vec3 c) {
	return floor(clamp(c, vec3(0.0), vec3(1.0)) * 31.0 + 0.5) / 31.0;
}
