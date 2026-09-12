// Shared geometry + colour uniform for the {3E} Color Screen ABR blend family.
// Each screen_color_modeN.gdshader sets its own render_mode (blend_mix / blend_add
// / blend_sub) and the ALPHA/ALBEDO scaling for that PSX ABR equation, then
// includes this. Consolidates the full-screen NDC quad + the `screen_color`
// uniform so the four mode shaders differ ONLY in the blend line — the same
// per-mode-shader pattern as tile_overlay_mode0..3 / effect_particle_mode0..3.
// Full RE: research/working_documents/COLOR_SCREEN_OPCODE_3E.md.
//
// The PSX quad is drawn at all only when the colour is non-zero (FUN_8008f208);
// ScenarioColorScreen hides the mesh at (0,0,0), so the shader needn't guard it.

// Current ramp colour, 0..1 (ScenarioColorScreen pushes _cur / 255). Not tagged
// source_color: the controller already supplies the raw PSX 0..255 fraction, so
// no sRGB->linear reinterpretation (kept literal for the ABR blend; revisit if a
// visual A/B shows a gamma mismatch).
uniform vec3 screen_color = vec3(0.0);

void vertex() {
	// Map the quad corners straight to NDC so it fills the screen regardless of
	// camera zoom/position; depth_test_disabled makes z irrelevant (always on top).
	// pixel-aspect-exempt: fullscreen NDC overlay, not battle-space geometry.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}
