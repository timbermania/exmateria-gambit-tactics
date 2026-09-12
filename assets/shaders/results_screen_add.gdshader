shader_type spatial;
// {78} Display Conditions — abr 1 — `bg + fg`: the victory-condition banner's visible gouraud text pass (records 2 and 5, tpage 0x026).
//
// compositor-exempt: off-fork-fallback — routed through the compositor on Forward+ via
// assets/shaders/results_screen_add_fold.gdshader (ScenarioResultsScreen picks that compositor_layer
// variant through Fold.shader whenever the engine fold owns compositing). This in-scene blend_add file
// is the Mobile/stock fallback only, so it is not a Forward+ lock-in blocker.
// display-space: folds-on-fork results_screen_add_fold.gdshader
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;

#include "res://assets/shaders/results_screen.gdshaderinc"

void fragment() {
	vec4 t = texture(sheet, UV);
	ALBEDO = pow(psx_modulate(t.rgb, COLOR.rgb), vec3(PSX_OUTPUT_GAMMA));
	ALPHA = t.a * src_alpha;
}
