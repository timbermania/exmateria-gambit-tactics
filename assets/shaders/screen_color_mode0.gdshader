shader_type spatial;
// {3E} Color Screen — PSX ABR mode 0 = ½·B + ½·F (50/50 mix). blend_mix with
// ALPHA=0.5 does the average in hardware (out = 0.5·F + 0.5·B). Foreground
// overlay: high render_priority + depth_test_disabled to composite over the frame.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

#include "res://assets/shaders/psx_screen_blend.gdshaderinc"

void fragment() {
	ALBEDO = screen_color;
	ALPHA = 0.5;  // ½·B + ½·F
}
