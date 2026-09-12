shader_type spatial;
// #7916 DEMO — WRONG side of the side-by-side (subtractive).
//
// effect_fold_sub.gdshader REMADE, minus exactly one keyword: `compositor_layer` dropped. Everything
// else imported verbatim from the current production fold shader (clean texel×gouraud/128, no local
// psx_brightness, OT-depth/occlusion contract) so the ONLY variable vs the fold side is the render
// layer. Derived FROM the fold shader (not the stale effect_particle_mode2 copy) so every principled
// change on top of the blend methodology rides along.
//
// blend_sub uses color_blend_op=REVERSE_SUBTRACT (COLOR subtracts) with alpha_blend_op=ADD (ALPHA
// accumulates). In-scene under Forward+ this subtracts in the LINEAR HDR scene buffer → the muddy /
// unclamped wrong side. Forward+ ONLY — deliberately NOT the Mobile/stock fallback, so the comparison
// isolates clamped-display-space vs native-linear blend WITHIN Forward+.
//
// Same shared carrier COLOR (POOL_GOURAUD_GAIN + level_scale baked by EngineFoldCompositor) as the
// fold side reads.
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub;

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"

void fragment() {
	vec4 col = stp_sample(UV);
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
