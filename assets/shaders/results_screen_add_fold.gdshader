shader_type spatial;
// {78} Display Conditions — abr 1 — `bg + fg`: the victory-condition banner's visible gouraud text pass (records 2 and 5, tpage 0x026). ENGINE-FOLD VARIANT.
//
// The `compositor_layer` counterpart of results_screen_add.gdshader. The banner's shadow and text
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
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://assets/shaders/results_screen.gdshaderinc"

void fragment() {
	vec4 t = texture(sheet, UV);
	ALBEDO = psx_modulate(t.rgb, COLOR.rgb);   // raw display texel — the fold blends in display space
	ALPHA = t.a * src_alpha;
}
