shader_type spatial;
// {78} Display Conditions — abr 2 — `bg - fg`: the victory-condition banner's two drop-shadow passes (records 0/1 and 3/4, tpage 0x046) — the same 232x31 blit the additive pass draws, once at the text's own position and once a pixel down-right. ENGINE-FOLD VARIANT.
//
// The `compositor_layer` counterpart of results_screen_sub.gdshader. The banner's shadow and text
// passes are PSX display-space blends, so they route through the engine fold like every other
// additive/subtractive PSX prim: the fold seeds a display-space scratch, Pass B hardware-blends
// display texels there, and Pass C converts back. That is what makes the per-step saturation the
// ROM's `bg ± fg` relies on actually happen — Godot's own Forward+ target is LINEAR and UNCLAMPED,
// which is how a literal replay of the two shadow passes drove the pixel negative and the additive
// text could not recover it.
//
// Fragment logic is identical to the in-scene twin EXCEPT that it writes the RAW display texel:
// the fold's scratch already IS display space, so a colour-space conversion here would be the
// exact error the fold removes. Same as formation_box_fold and feedback_hud_sprite_additive_fold.
// Uniforms match the in-scene twin so ScenarioResultsScreen can swap only `.shader` and keep its
// ShaderMaterial's values.
//
// OCCLUSION: none, deliberately — `depth_test_disabled`. These are full-screen NDC overlays that
// draw over the settled {76} dim, never inside the battlefield's depth model, and the fold pass
// binds the scene depth: without the opt-out the quad's own clip z fails the test and the banner
// renders NOTHING (measured — that is exactly what the first fold twin did).
// This shader IS routed (compositor_layer), so it carries no exempt marker.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_sub, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://assets/shaders/results_screen.gdshaderinc"

void fragment() {
	vec4 t = texture(sheet, UV);
	// UV2 is where the ADDITIVE text pass samples the sheet for this same screen
	// pixel — the mesh builder writes it per vertex from the two records' `dx`/`dy`
	// difference, which is (0,0) for record 0 and (+1,+1) for record 1.
	//
	// 🔴 GATE ON (1 - text_a) SO THE SHADOW FALLS ONLY IN THE GLYPH'S NEGATIVE
	// SPACE. The PSX clamps every blend step at 0, so `bg - fg - fg' + text`
	// resolves to the bright text wherever the text is inked. Off the fork this
	// runs in-scene against a LINEAR, UNCLAMPED target, where replaying the
	// subtraction literally drives the pixel to a large negative value the additive
	// pass cannot recover — measured, the composite read (0,0,0) where the additive
	// pass alone read (201,142,37). Gating is the same fix
	// show_graphic_shadow.gdshader already carries for {7D}'s drop shadow, and it
	// leaves exactly the 1 px fringe the PSX draws.
	float text_a = texture(sheet, UV2).a;
	ALBEDO = psx_modulate(t.rgb, COLOR.rgb);   // raw display texel — the fold blends in display space
	ALPHA = t.a * (1.0 - text_a) * src_alpha;
}
