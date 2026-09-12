shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Cursor OPAQUE pass — STP=0 body texels only (palette a > 0.9). No blend,
// writes depth. Mirror of effect_particle_opaque. See tile_cursor.gdshaderinc.
#include "res://addons/exmateria_battlefield/cursor/tile_cursor.gdshaderinc"

void fragment() {
	vec4 c = cursor_sample(UV);
	// Drop transparent (a≈0) + STP=1 outline (a≈0.5) — the semi pass owns those.
	if (c.a < 0.9) {
		discard;
	}
	ALBEDO = c.rgb;          // c.rgb already tint-modulated + gamma-corrected
	DEPTH = ot_computed_depth;
}
