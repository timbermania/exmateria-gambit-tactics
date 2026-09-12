shader_type canvas_item;
render_mode blend_sub, unshaded;
// The world map's SCREEN-IN quad — PSX ABR mode 2, `B - F` (subtractive).
//
// §24.1 measured WLDCORE's own fade pair as two full-screen monochrome rectangles,
// 256x240 at (-128,-120), OT slot 15, command `0x62` — GP0 abr 2. That is the same
// blend `{3E} Color Screen` Mode 2 uses on the way OUT of a scenario, which is why
// the screen-in mirrors it (ADR-0161).
//
// `blend_sub` with ALPHA = 1.0 is `dst - src` — the console's `B - F`, clamping at
// byte 0. A rising ramp drives the frame to black; the screen-in runs it FALLING, so
// the map emerges highlights-first out of black. That is NOT what an opaque black
// rect ramped on alpha does (`B * (1-a)`, a proportional dim), and the two look
// different: subtractive holds black until F drops below the brightest pixel.
//
// [b]Baked to 5-bit levels by the caller, and drawn BEFORE the expansion pass.[/b]
// `psx_expand_555.gdshader` states the rule this obeys: the world map composites in
// the GPU's own 5-bit channels, every quad is baked as `8 * v` for a level v in 0..31,
// and the expansion runs ONCE on the finished frame. So `WorldMapScreenIn` quantises
// the ramp and this quad is added to the tree ahead of the BackBufferCopy — otherwise
// the frame would compute `e(B) - e(F)` where the console computes `e(B - F)`.
//
// Deliberately NOT a share of `assets/shaders/screen_color_mode2.gdshader`: that one
// is `shader_type spatial` and includes a `vertex()` writing `POSITION`, which has no
// canvas_item equivalent — and the map mounts as a CanvasLayer, which composites over
// the 3D viewport the spatial quad lives in, so it could not cover the map anyway.

// Current ramp colour, 0..1, already quantised to 5-bit levels (WorldMapScreenIn
// pushes `level * 8 / 255`). Not `source_color`: this is a raw PSX framebuffer
// fraction, and an sRGB reinterpretation would move it off the console's levels.
uniform vec3 screen_color = vec3(0.0);

void fragment() {
	COLOR = vec4(screen_color, 1.0);  // B - F
}
