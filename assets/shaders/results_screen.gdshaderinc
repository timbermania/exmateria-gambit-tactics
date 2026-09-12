// Shared core for the {78} Display Conditions screens — the battle intro banner
// and the whole results sequence (BATTLE_RESULTS_SCREEN.md §4/§6/§8/§13).
//
// Unlike the other scenario screen overlays, these are NOT one full-screen quad
// with the layout in the shader: the PSX builds an actual prim list — sixteen
// POLY_GT4 glyph quads for "CONGRATULATIONS!", one pre-composed blit for line 2,
// two per reel column, six for the banner — so ScenarioResultsScreen builds the
// same list as an ArrayMesh whose vertices ARE PSX framebuffer pixels. Each
// results_screen_*.gdshader includes this and writes only its own fragment(), the
// same per-mode-shader split screen_color_mode0..3 uses.
//
// Colour is PSX vertex MODULATION, not tinting: `out = texel × colour / 128`, so
// 0x80 is 1.0 and the settled glyph bottom (148,128,208) is deliberately pushed
// PAST 1.0 on blue — which is what makes the text read as bright cream while it is
// still a blended primitive. The fade is the same multiplication with a per-line
// level (`0x801C8B94`), applied by the mesh builder when it writes the vertex
// colours, so what arrives here is already the faded value.
//
// ⚠️ `psx_modulate()` RETURNS A DISPLAY-SPACE VALUE and this file performs no
// colour-space conversion at all — deliberately. An engine-fold twin blends in the
// display-space scratch and must add the raw texel; an in-scene twin converts for
// Forward+'s linear target and does so in its own fragment(). Putting the
// conversion here would make it reachable from a `compositor_layer` shader, which
// `check_fold_pow` fails on sight, and rightly: that is the error class the fold
// exists to remove.

// The page's 4bpp sheet decoded under one of its two CLUTs; index 0 carries alpha
// 0 so the dimmed battlefield shows through every gap.
uniform sampler2D sheet : filter_nearest, repeat_disable;
// The primitive's blend weight. The glyph quads and the reel cells draw solid; the
// banner's additive and subtractive passes scale their contribution by ALPHA, so
// every caller leaves this at 1.0 today. Kept because the abr-0 half blend is one
// value away if a capture ever settles the per-texel STP question (§4.2 decodes the
// glyph packets as semi-transparent; ss4/ss5 show the letters solid).
uniform float src_alpha = 1.0;
// PSX native framebuffer the prim list is laid out in.
uniform vec2 fb_size = vec2(256.0, 240.0);

// 0x80 = 1.0, and the vertex colour arrives as byte/255.
const float PSX_MODULATION = 255.0 / 128.0;
// The exponent an IN-SCENE twin applies to reach Forward+'s linear target — the same
// convention as bitmap_char_3d.gdshader and every other PSX-sourced sprite here. A
// fold twin never uses it.
const float PSX_OUTPUT_GAMMA = 2.2;

void vertex() {
	// VERTEX.xy is already in PSX framebuffer pixels with y DOWN; map straight to
	// clip space so the screen fills regardless of camera zoom/position.
	// pixel-aspect-exempt: screen-space prim list, not battle-space geometry.
	POSITION = vec4(VERTEX.x / fb_size.x * 2.0 - 1.0,
			VERTEX.y / fb_size.y * 2.0 - 1.0, 0.0, 1.0);
}

// `out = texel x colour / 128` in DISPLAY space, saturating — the boosted blue on the
// settled glyph bottom (208/128 = 1.63) is meant to clip, not to wrap.
vec3 psx_modulate(vec3 texel, vec3 vertex_colour) {
	return min(texel * vertex_colour * PSX_MODULATION, vec3(1.0));
}
