shader_type spatial;
// #7916 DEMO — WRONG side of the side-by-side (additive).
//
// This is effect_fold_add.gdshader REMADE, minus exactly one keyword: `compositor_layer` is
// dropped. Everything else is imported verbatim from the current production fold shader — the
// clean texel×gouraud/128 (`col.rgb * COLOR.rgb`, no local psx_brightness), the dead-gamma-ternary
// removal, the OT-depth/occlusion contract — so the ONLY variable between the two sides is the
// render-layer routing, not incidental shading drift. Derived FROM the fold shader (not the stale
// tools/probe_shaders/effect_particle_mode1 copy) precisely so every principled change layered on
// top of the blend methodology rides along automatically.
//
// Without `compositor_layer` the engine does NOT route this into the display-space fold scratch;
// it renders IN-SCENE and Godot blends it with native `blend_add` into the Forward+ LINEAR HDR
// scene buffer → the muddy / unclamped result. Forward+ ONLY — this is deliberately NOT the
// Mobile/stock fallback (effect_callback_additive), so the comparison isolates "clamped display-space
// blend vs native linear blend" WITHIN Forward+, not "Forward+ vs Mobile".
//
// The per-instance COLOR (with POOL_GOURAUD_GAIN + level_scale already baked by EngineFoldCompositor)
// rides on the SHARED carrier buffer, so this side reads the identical gained COLOR the fold side does.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"

void fragment() {
	vec4 col = stp_sample(UV);
	// Identical to effect_fold_add: RAW display texel × gained COLOR. In-scene this feeds native
	// blend_add into the linear HDR buffer (the wrong side); routed through the fold it would land in
	// the display-space scratch (the right side). Same math either way — routing is the whole delta.
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
