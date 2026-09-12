shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Flat-colour fill for the sort-tab header chrome (#174, FORMATION_SCREEN.md
// §12.3.1): the tan window bar + its bevel frame, the active-tab dark box, and the
// L2/R2 button bodies. Colours are authored in target sRGB (measured from the
// settled roster oracle — tan (152,144,120), active box (32,24,16), L2/R2
// (176,184,192)); the pow(.,2.2) matches the other ui3 formation shaders
// (background/orb/shadow) so the fills land at the right on-screen luma. This
// REPLACES formation_header_bar.gdshader — the header is menu windows, not a
// subtractive gradient band (the first pass's model was wrong).
uniform vec4 color = vec4(0.6, 0.565, 0.47, 1.0);

void fragment() {
	ALBEDO = pow(clamp(color.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
	ALPHA = color.a;
}
