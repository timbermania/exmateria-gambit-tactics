// The range-overlay tile's CLUT SAMPLING — the half of the tile look that is the same in
// display space and in linear space, so that both the in-scene shaders and the fold twin
// can share it.
//
// WHY IT IS SPLIT OUT (it used to all live in tile_overlay.gdshaderinc). A
// `compositor_layer` shader writes into the DISPLAY-SPACE fold scratch, which has no
// tonemap after it, so an sRGB->linear `pow()` inside a fold is a colour-space round trip
// with no return leg — the gold-box bug class, and `tools/check_no_pow_in_fold.py` fails
// any file REACHABLE from a fold, includes and all. The routed tile therefore adds its RAW
// display-space CLUT colour, exactly as TileOverlayCompositor._tile_color does on the CPU
// for the flat-fill decals. The pow stays behind in tile_overlay.gdshaderinc with the
// in-scene shaders, whose linear target the pipeline does tonemap back.
//
// So: everything up to and including the palette LOOKUP lives here (raw), plus the
// mono/tint modulation that is a PSX primitive-colour multiply and not a colour space.
// Vault: [[Tile Overlay]]
// Vault: [[Range Overlay Tile Palettes]]

// ROM-ripped range-overlay tile (ADR-0022 indexed-texture pattern). `range_tex`
// is an indexed-grayscale TGA (R = index*17, from parse_range_tiles.py); the real
// color comes from `range_palette` at row `palette_row` (== BATTLE.BIN palette
// slot N: 0 blue / 1 red / 2 unnamed / 3 yellowA / 4 cursor / 5..7 unnamed /
// 8 yellowB). The shimmering "vortex" is a 15-phase barber-pole rotation of
// colors 1..15 — index 0 is the fixed transparent slot. The tile is a 14x14
// sub-rect of the 256x256 sheet, selected by tile_uv_offset/size.
uniform sampler2D range_tex : filter_nearest, repeat_disable, hint_default_black;
uniform sampler2D range_palette : filter_nearest, hint_default_transparent;
uniform int palette_row = 0;
uniform vec2 tile_uv_offset = vec2(0.0, 0.625);            // (0,160) / 256
uniform vec2 tile_uv_size = vec2(0.0546875, 0.0546875);    // 14 / 256
// --- DEBUG-PANEL-DRIVEN CONTROLS (TilesDebugPanel.gd) --------------------------
// Texture source. false = sample the indexed RANGETILE sheet (blue's textured
// barber-pole); true = uniform flat fill of `flat_index` (red/yellow tiles).
uniform bool flat_fill = false;
// Animation mode. 0 = static, 1 = barber-pole (discrete 15-phase CLUT rotation,
// the literal FUN_80088EEC mechanism — blue & red rotate; yellow is static in
// the ROM). The old "brightness pulse" stylization is gone: it existed only to
// dodge the red ramp's light-pink peak, which `tint` (the per-tile primitive-
// color modulation, below) now handles faithfully — pink * maroon = vivid red.
uniform int anim_mode : hint_range(0, 1) = 1;
uniform int flat_index : hint_range(1, 15) = 2;             // fixed CLUT hue for flat tiles
// manual_phase: -1 = animate from TIME; >=0 = freeze on that phase (pause + scrub).
uniform int manual_phase = -1;
uniform float phase_rate = 15.0;   // CLUT-rotation speed (phases/sec). FFT: speed
                                   // DAT_80045980=1, phase advances every 4 frames
                                   // => ~15 phase-steps/sec at 60fps (full cycle ~1s).
// tint: the PSX per-primitive modulation color (texel * tint / 128). This is what
// "disable textures for polygons" reveals — the flat base color of the quad. The
// CLUT shade is multiplied by it, so e.g. red's maroon base keeps the bright
// shades red instead of pink. Default white = unmodulated. NOT a colour space —
// it is the PSX primitive colour, so it applies identically in either target.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// mono: collapse the sampled CLUT shade to its brightness (value = max channel),
// so `tint` becomes the only hue. This is how we fake a tile color we don't have a
// real CLUT for (e.g. yellow): take a clean symmetric ramp (red/blue) for its
// dark<->bright pulse, strip the hue, recolor with tint. Off = use the CLUT's own
// color (the faithful red/blue path).
uniform bool mono = false;

// MUST match parse_range_tiles.py PAL_COUNT (the RANGETILE.palette.tga height).
// The parser emits all 9 BATTLE.BIN CLUT slots (was 4 before the cursor work);
// this divisor selects the row, so it has to track the texture height or
// palette_row 0/1 (blue/red) mis-index into red/yellow.
const float PALETTE_ROWS = 9.0;
const int CYCLE = 15;  // colors 1..15 rotate; index 0 stays transparent

// The RAW palette lookup for this fragment: pick the CLUT index (flat-fill or sampled
// from the indexed sheet), run the barber-pole rotation, and read `range_palette`.
// No gamma, no tint — just the CLUT entry, in whatever space the palette texture is in
// (which for the fold IS display space, and that is the point). Index 0 carries a == 0,
// so the transparent slot drops out under every blend mode. `frag_uv`/`time` are passed
// in because UV/TIME are fragment-stage built-ins, not visible inside a helper.
vec4 tile_overlay_clut(vec2 frag_uv, float time) {
	// Discrete phase 0..14 (manual_phase freezes it for pause/scrub).
	int phase = (manual_phase >= 0)
		? (manual_phase % CYCLE)
		: int(mod(time * phase_rate, float(CYCLE)));

	// Source CLUT index: flat uniform fill, or sampled from the indexed sheet.
	int idx;
	if (flat_fill) {
		idx = flat_index;
	} else {
		vec2 tuv = tile_uv_offset + frag_uv * tile_uv_size;
		idx = int(texture(range_tex, tuv).r * 15.0 + 0.5);  // 0..15
	}

	int rot = idx;
	if (anim_mode == 1 && idx > 0) {
		// Barber-pole: discrete 15-phase CLUT rotation (FUN_80088EEC). working[1..15]
		// = base rotated left by `phase`; index 0 stays the fixed/transparent slot.
		rot = ((idx - 1 + phase) % CYCLE) + 1;
	}
	return texture(range_palette, vec2(
		(float(rot) + 0.5) / 16.0,
		(float(palette_row) + 0.5) / PALETTE_ROWS));
}

// Apply the PSX per-primitive modulation to an already-space-correct CLUT colour:
// optional `mono` collapse, then `tint`. Returns rgb in .rgb and the palette coverage
// alpha (tint-modulated) in .a. Shared by the in-scene path (which passes a
// gamma-converted colour) and the fold (which passes the raw display colour).
vec4 tile_overlay_modulate(vec4 col) {
	vec3 rgb = col.rgb;
	if (mono) {
		// Value (max channel) keeps the ramp's dark<->bright pulse at full contrast
		// and brightness; tint then supplies the hue.
		rgb = vec3(max(rgb.r, max(rgb.g, rgb.b)));
	}
	return vec4(rgb * tint.rgb, col.a * tint.a);
}
