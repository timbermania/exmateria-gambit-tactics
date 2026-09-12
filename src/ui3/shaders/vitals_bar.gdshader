shader_type spatial;
// ADR-0077 depth-ladder member (see vitals_sprite.gdshader): OPAQUE, WRITES DEPTH from its real
// camera-Z so the folded band fails the fold's Pass B depth test where the fill is nearer and can't
// clobber it. No render_priority, no depth_test_disabled. Two traps threaded: depth test must stay
// enabled (Vulkan disables depth writes when the test is off), and the shader must NOT write ALPHA
// (writing ALPHA opts into the transparent pass and misses the fold seed — ADR-0077 impl note); it
// stays opaque via the `discard`s below.
//
// psx-ot-depth-exempt: screen-space ortho UI quad — depth is the intra-panel ladder's real camera-Z
// (ADR-0077), NOT a battle-OT CUSTOM0 centroid, so it opts out of ADR-0009's CUSTOM0 rule. (No
// `DEPTH =` write, so check_depth_shaders.py doesn't flag it; this marks the opt-out for readers.)
render_mode unshaded, cull_disabled;

// Faithful FFT HP/MP/CT vitals bar — the FILL layer. The ROM (BATTLE.BIN
// draw_vitals_bars @0x801352BC) draws each bar as a textured SPRT swatch (the
// 38x6 casing + dim empty background, vitals_sprite.gdshader) with an untextured
// gouraud quad (PSX POLY_G4) inset inside it. That swatch interior is NOT a
// rectangle — it is a slanted parallelogram (RANGETILE swatch index 3: rows 1-3,
// 32px wide, left edge stepping -1px per row), with the border (index 2 top, 1
// bottom) framing it. A plain rectangular fill can't fit those angled ends.
//
// So this fill samples the SAME swatch cell and paints the gradient ONLY over the
// interior body pixels (index == body_index), masked pixel-for-pixel to the
// swatch art — the border is never overdrawn, the angled start/end fit perfectly
// by construction. The horizontal fill cut follows the slant (the interior left
// edge shifts `slant_per_row` per row), and the dark->bright ramp is compressed
// into the filled width exactly like the ROM's POLY_G4 (g = t / fill_frac).
//
// This quad is drawn over the WHOLE swatch (same rect as the track); fill_frac
// selects how much of the interior is painted (0 = empty, the dim track shows).

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform vec4 cell = vec4(216.0, 202.0, 38.0, 6.0);   // swatch atlas px: x, y, w, h

uniform float body_index = 3.0;        // RANGETILE interior (fillable) index
uniform float interior_left0 = 3.0;    // interior left edge px at row interior_row0
uniform float interior_row0 = 1.0;     // first interior row (within the swatch)
uniform float interior_width = 32.0;   // interior width in px (constant per row)
uniform float slant_per_row = -1.0;    // interior left-edge shift per row downward

uniform float fill_frac = 1.0;                         // 0..1 of the interior filled
uniform vec3 color_left = vec3(0.282, 0.408, 0.471);   // dark endpoint (fill start)
uniform vec3 color_right = vec3(0.659, 0.722, 0.439);  // bright endpoint (fill end)
uniform float brightness = 1.0;

void fragment() {
	vec2 pxf = cell.xy + UV * cell.zw;
	vec2 texel = (floor(pxf) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	if (idx != int(body_index)) {
		discard;  // only the dim interior body is fillable; border/background stay
	}
	// Position of this body pixel along the (slanted) interior, 0..1.
	float col = floor(pxf.x - cell.x);
	float row = floor(pxf.y - cell.y);
	float left = interior_left0 + (row - interior_row0) * slant_per_row;
	float t = (col + 0.5 - left) / interior_width;
	if (t > fill_frac) {
		discard;  // beyond the fill: the dim track (drawn behind) shows through
	}
	float g = clamp(t / max(fill_frac, 0.0001), 0.0, 1.0);
	vec3 c = mix(color_left, color_right, g);
	ALBEDO = pow(clamp(c * brightness, vec3(0.0), vec3(1.0)), vec3(2.2));
	// OPAQUE: the fill is either painted (fully opaque) or discarded, so it stays in the opaque pass and
	// lands in the fold seed + shared depth buffer. Deliberately NO ALPHA write (ADR-0077 trap).
}
