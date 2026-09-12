shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Expand the PSX framebuffer from 5-bit levels to 8 bits, ONCE, after every blend.
//
// The world map composites in the GPU's own 5-bit channels. Every quad is baked as
// `8 * v` for a level v in 0..31, so the framebuffer byte carries the level in its top
// five bits and fixed-function blending lands exactly where the console's does:
//
//     abr 1  B + F        blend_add  -> clamps at byte 255, i.e. level 31
//     abr 2  B - F        blend_sub  -> clamps at byte 0
//     abr 0  (B + F) / 2  blend_mix alpha 0.5 -> byte 4(B+F), and floor(.../8) is the
//                         console's `(B + F) >> 1` including its truncation
//
// Expanding per-quad instead — which is what the scaffold did — computes `e(B) op e(F)`
// where the console computes `e(B op F)`. With e(v) = (v<<3)|(v>>2) those differ by 0 or
// 1 in the two `>>2` terms, which is the ±1 on 25.9% of the frame that this closes.
//
// This runs once, on a BackBufferCopy of the finished frame, with blending OFF so it
// REPLACES rather than composites.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	// Back to the integer byte first: s * 255 is exact in principle and 254.99997 in
	// practice, and a floor() on that reads a whole level low.
	vec3 b = floor(texture(screen_tex, SCREEN_UV).rgb * 255.0 + 0.5);
	vec3 v = floor(b / 8.0);
	COLOR = vec4((v * 8.0 + floor(v / 4.0)) / 255.0, 1.0);
}
