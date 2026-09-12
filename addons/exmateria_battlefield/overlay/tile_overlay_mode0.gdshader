shader_type spatial;
// PSX ABR mode 0 = 50% average (0.5*Back + 0.5*Front). PROVEN the real range
// tile by live framebuffer capture from sstate2: the green channel under a red
// tile DROPS (48->28), which pure-additive can never do. blend_mix with
// ALPHA=0.5 reproduces 0.5B+0.5F exactly. depth_draw_never: still depth-TESTS
// against terrain via the OT depth we write, but doesn't depth-WRITE, so
// overlapping tiles don't occlude each other.
// cull_disabled (not cull_back): the highlight is a flat decal whose winding
// follows the map parser's tile-vertex order; cull_back culled it when a re-parse
// flipped that winding. A flat overlay has no back face — never cull it.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

#include "res://addons/exmateria_battlefield/overlay/tile_overlay.gdshaderinc"

void fragment() {
	vec4 c = tile_overlay_color(UV, TIME);
	ALBEDO = c.rgb;
	ALPHA = c.a * 0.5;  // 50/50 average; c.a == 0 drops the transparent slot
	if (!debug_no_psx) {
		DEPTH = ot_computed_depth;
	}
}
