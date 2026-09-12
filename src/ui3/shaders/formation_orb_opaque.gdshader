shader_type spatial;
// ADR-0077: OPAQUE orb core now WRITES DEPTH (dropped depth_draw_never / depth_test_disabled) at the
// orb rung, so the additive rim HALO — a compositor_layer member at the same rung — composites over it
// and the core seeds the fold scratch. depth from the shared reversed-Z convention (native geometry Z).
render_mode unshaded, cull_disabled, blend_mix;

// FORMATION orb OPAQUE pass — STP=0 core texels (idx 3-6/12, palette a=255).
// Mirror of effect_particle_opaque: the solid bright-cyan centre, drawn opaque so
// it is NOT blown out by additive-over-linear. The additive rim halo is the
// companion formation_orb (mode1) pass. See formation_orb.gdshaderinc / §10.
//
// Gouraud (brightness) modulates INSIDE pow(2.2) — gamma space, matching PSX
// (8-bit texel × gouraud/128) and validated against the live framebuffer to
// within ~1 RGB555 step.
#include "res://src/ui3/shaders/formation_orb.gdshaderinc"

void fragment() {
	vec4 c = orb_sample(UV);
	if (c.a < 0.9) {
		discard; // keep STP=0 core only
	}
	// Quantize the display-space colour to RGB555, then linearize — reproduces the
	// real 5-bit framebuffer stepping of the pulse (opaque core: matches exactly).
	ALBEDO = pow(quantize5(c.rgb * brightness), vec3(2.2));
	// Do NOT assign ALPHA (ADR-0077): writing it opts into Godot's transparent pipeline, so the opaque
	// core would skip the fold's PRE_TRANSPARENT seed. The idx0/rim texels are already `discard`ed above,
	// so the core is opaque via alpha-test — it seeds the scratch and writes depth for the rim to fold over.
}
