shader_type spatial;
// {91} Show Map Title — ADDITIVE location-name pass. The uploaded strip is drawn
// over the live scene with PSX semi-transparency mode 1 (B+F, additive), so the
// white serif place-name lights up while the transparent background lets the
// scene show through (show_map_title_op91_decode.md §6.3). vertex() maps the quad
// to NDC so it fills the screen regardless of camera. Paired with a SUBTRACTIVE
// drop-shadow pass (show_map_title_shadow.gdshader, VRAM-confirmed offset ~(+1,+1),
// same as {7D}); the reveal AND erase are both L->R wipes driven by `reveal`/`erase`.
// compositor-exempt: pre-clamped-single-layer — Cat C2 full-screen title card. reveal_level() emits a quantized clamp([0,1])
// alpha (show_map_title_reveal.gdshaderinc) and the strip is a SINGLE additive full-screen NDC layer, so
// the final display clamp equals the PSX per-step clamp — no Mobile UNORM dependency. COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md §C2.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;

#include "res://assets/shaders/show_map_title_reveal.gdshaderinc"

void vertex() {
	// pixel-aspect-exempt: fullscreen NDC quad, not battle-space geometry.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}

void fragment() {
	bool inside;
	vec2 uv = card_uv(SCREEN_UV, inside);
	vec4 t = inside ? texture(tex, uv) : vec4(0.0);
	// Additive contribution = texel colour x gouraud level, masked by the strip
	// alpha (idx0 -> 0 = scene shows straight through). blend_add adds ALBEDO*ALPHA.
	ALBEDO = t.rgb;
	ALPHA = inside ? reveal_level(uv, FRAGCOORD.xy, VIEWPORT_SIZE) * t.a : 0.0;
}
