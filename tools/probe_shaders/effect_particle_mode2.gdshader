shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub;

// STP Semi-Trans Pass - PSX Mode 2: back - fore (subtractive)
//
// ADR-0039: color_modulate from COLOR.rgb (per-instance)

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"
// psx_brightness and psx_gamma: plain local consts on these throwaway probe copies. The
// shared psx_brightness global went in the ADR-0074 endgame (the production folds bake
// their gain per-producer); psx_gamma followed in #1217 (c) / #1198, because its only
// declaration was inside the extraction-#7 membership and ADR-0190 dec. 3 lets only a
// NON-SYSTEM addon declare a `global uniform`. These four probes are the only code
// readers outside `src/ui3/shaders/`, which declares its own. Values track
// `project.godot [shader_globals]` — psx_brightness 2.2, psx_gamma 1.4 (`:882`).
const float psx_brightness = 2.2;
const float psx_gamma = 1.4;

void fragment() {
	vec4 col = stp_sample(UV);

	// PSX-style: raw sRGB by default; toggle srgb_to_linear for linear-correct blending
	ALBEDO = (srgb_to_linear ? pow(col.rgb, vec3(psx_gamma)) : col.rgb) * COLOR.rgb * psx_brightness;
	// Full subtractive intensity
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;  // unified OT depth (ADR-0009)
}
