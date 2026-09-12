shader_type spatial;
// {7D} Show Graphic — SUBTRACTIVE drop-shadow pass. The card is drawn a second
// time offset ~(+1,+1) px with PSX semi-transparency mode 2 (B-F, subtractive),
// darkening the scene just below/right of the text to give the title card its
// drop-shadow (show_graphic_op7d_decode.md II.3/II.9). Shares the reveal + dither
// logic with the additive text pass; only the blend mode + UV offset differ.
// compositor-exempt: pre-clamped-single-layer — Cat C2 full-screen title-card drop-shadow. reveal_level() emits a quantized
// clamp([0,1]) alpha and the shadow is a SINGLE subtractive full-screen NDC layer, so the final display
// clamp equals the PSX per-step clamp — no Mobile UNORM dependency. COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md §C2.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_sub;

#include "res://assets/shaders/show_graphic_reveal.gdshaderinc"

// Shadow UV offset (~1 screen px) in card-UV space; the card is 256x16 texels
// (1/256, 1/16). Literal-folded — Godot uniform defaults must be constant.
uniform vec2 shadow_uv = vec2(0.00390625, 0.0625);

void vertex() {
	// pixel-aspect-exempt: fullscreen NDC quad, not battle-space geometry.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}

void fragment() {
	bool inside;
	vec2 uv_here = card_uv(SCREEN_UV, inside);
	vec2 uv = uv_here - shadow_uv;
	// Alpha of the text AT this pixel: 1 on the glyph body, 0 in negative space.
	float here_a = inside ? texture(tex, uv_here).a : 0.0;
	vec4 t = (inside && uv.x >= 0.0 && uv.y >= 0.0) ? texture(tex, uv) : vec4(0.0);
	// blend_sub subtracts ALBEDO*ALPHA. Gate on (1 - here_a) so the shadow falls
	// ONLY in the glyph's negative space — never over the bright body. Without
	// this the ~1px-offset shadow cancels the additive text and guts the letters
	// (PSX keeps the body bright; the shadow is a subtle drop in the gaps).
	ALBEDO = t.rgb;
	ALPHA = reveal_level(uv, FRAGCOORD.xy, VIEWPORT_SIZE) * t.a * (1.0 - here_a);
}
