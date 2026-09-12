shader_type spatial;
// {78} Display Conditions — abr 2 — `bg - fg`: the victory-condition banner's two drop-shadow passes (records 0/1 and 3/4, tpage 0x046) — the same 232x31 blit the additive pass draws, once at the text's own position and once a pixel down-right.
//
// compositor-exempt: off-fork-fallback — routed through the compositor on Forward+ via
// assets/shaders/results_screen_sub_fold.gdshader (ScenarioResultsScreen picks that compositor_layer
// variant through Fold.shader whenever the engine fold owns compositing). This in-scene blend_sub file
// is the Mobile/stock fallback only, so it is not a Forward+ lock-in blocker.
// display-space: folds-on-fork results_screen_sub_fold.gdshader
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_sub;

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
	ALBEDO = pow(psx_modulate(t.rgb, COLOR.rgb), vec3(PSX_OUTPUT_GAMMA));
	ALPHA = t.a * (1.0 - text_a) * src_alpha;
}
