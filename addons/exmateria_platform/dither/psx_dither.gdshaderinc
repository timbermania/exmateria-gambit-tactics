// PSX ordered dithering and 15-bit color quantization.
// Included by shaders that render Gouraud-shaded polygon output (map terrain, background).
// NOT included by sprite shaders — PSX sprites are VRAM copies and bypass the dither unit.
//
// Two independent gates decide whether the real GPU dithers a primitive, and this
// include is the GDScript side of "both gates passed":
//   1. Primitive class. Only Gouraud primitives reach the dither unit — Gouraud-shaded
//      untextured polys and Gouraud+textured polys. Sprites (GP0 0x60-0x7F rects) and
//      flat-textured polys never touch it, which is why no sprite shader includes this.
//   2. The DTD bit — bit 9 (0x200) of the texpage word.
// Measured on hardware-accurate emulation of a live FFT battle (see the header of
// psx_dither_and_quantize below): map terrain and the battle background gradient both
// dither; the flat-rect UI windows do not.
//
// PROVENANCE, and a trap for anyone A/B-ing against an emulator. The matrix below is the
// DOCUMENTED HARDWARE one, not pcsx-redux's. Redux stores unsigned thresholds
// (`s_dithertable = {7,0,6,1, 2,5,3,4, 1,6,0,7, 4,3,5,2}`, bump the 5-bit value when the
// low 3 bits exceed the threshold) which reduce to the additive offsets
// `0 7 1 6 / 5 2 4 3 / 6 1 7 0 / 3 4 2 5` — the same set of ranks as ours, arranged
// differently. The two agree on WHETHER a pixel dithers and by how much on average; they
// disagree on which cell gets which offset. So an emulator capture is a referee for
// "does this surface dither", never for byte-exact pattern phase.

global uniform bool psx_dither_enabled;

// PSX 4x4 signed dither matrix (hardware; values range -4 to +3 — see PROVENANCE above).
// The GPU adds this value to each 8-bit channel before truncating to 5-bit.
const int PSX_DITHER_MATRIX[16] = int[16](
	-4,  0, -3,  1,
	 2, -2,  3, -1,
	-3,  1, -4,  0,
	 3, -1,  2, -2
);

// Apply PSX dithering and 15-bit color quantization.
// Input: sRGB color (0.0-1.0), screen pixel position, viewport size, and the PSX
//        horizontal resolution the caller's content was authored at.
// Output: quantized color (32 levels per channel, mapped back to 0.0-1.0).
//
// On hardware one dither cell is one framebuffer pixel, so screen_pos is divided down
// to PSX pixel density before indexing the matrix — otherwise the 4x4 pattern is
// sub-pixel noise at a modern viewport. `native_width` is what that density is, and it
// is NOT a universal constant: the PSX display width is a per-title (indeed per-screen)
// mode, so the caller has to say. Passing the wrong one makes the cell the wrong SIZE
// and, on an integer-scaled presentation, misaligns it from the pixel grid: FFT's
// battle framebuffer measures 256x240, and at this project's 1024-wide viewport (a
// clean 4x) assuming 320 would round the cell to 3 device px instead of 4.
vec3 psx_dither_and_quantize(vec3 color, vec2 screen_pos, vec2 viewport_size, float native_width) {
	if (!psx_dither_enabled) {
		return color;
	}

	// Scale screen coords to PSX resolution so dither cells are visible at high res.
	// Round to the nearest integer scale — a fractional one beats against the art grid.
	float scale = max(1.0, round(viewport_size.x / native_width));
	int x = int(screen_pos.x / scale) & 3;
	int y = int(screen_pos.y / scale) & 3;
	int dither = PSX_DITHER_MATRIX[y * 4 + x];

	vec3 result;
	for (int ch = 0; ch < 3; ch++) {
		// PSX algorithm: add signed dither to 8-bit value, clamp, then truncate to 5-bit
		int c8 = clamp(int(color[ch] * 255.0) + dither, 0, 255);
		int c5 = c8 >> 3;
		result[ch] = float(c5) / 31.0;
	}

	return result;
}
