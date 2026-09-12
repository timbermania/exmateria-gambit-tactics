shader_type spatial;
// {3E} Color Screen — PSX ABR mode 1 = B + F (additive). blend_add with ALPHA=1.0
// adds the full foreground colour to the backdrop (out = B + F) — a fade-to-white
// / glow flash. Foreground overlay (see mode0).
// compositor-exempt: pre-clamped-single-layer — Cat D screen tint. CPU-folded to one pre-clamped [0,1] full-screen value
// (ScenarioColorScreen.gd `_cur/255.0`); a SINGLE additive layer, so the final display clamp equals
// the PSX per-step clamp — no Mobile UNORM dependency. COMPOSITOR_UNIVERSAL_ROUTING_SCOPING.md §D.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add;

#include "res://assets/shaders/psx_screen_blend.gdshaderinc"

void fragment() {
	ALBEDO = screen_color;
	ALPHA = 1.0;  // B + F
}
