shader_type spatial;
render_mode unshaded, cull_disabled;
// Vault: [[Background Opcode]]

// 4-corner Gouraud shading (PSX-style)
// TL=top-left, TR=top-right, BL=bottom-left, BR=bottom-right
uniform vec3 color_tl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_tr : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_bl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_br : source_color = vec3(0.0, 0.0, 0.0);

#include "res://addons/exmateria_platform/dither/psx_dither.gdshaderinc"

// Unified PSX colour-mode stack (ADR-0067). The additive TINT is folded through the
// shared include — ScreenEffectOverlay pushes the summed per-owner delta as one
// scale=1 affine layer (identity when no effect tints the background).
#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

void vertex() {
	// Map quad corners directly to NDC screen corners, bypassing MVP transform.
	// Makes the mesh always fill the screen regardless of camera zoom/position.
	// pixel-aspect-exempt: fullscreen NDC quad, not battle-space geometry — nothing to align to.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}

void fragment() {
	// Bilinear interpolation of 4 corner colors (base gradient)
	// SCREEN_UV: (0,0) = top-left, (1,1) = bottom-right
	vec3 top = mix(color_tl, color_tr, SCREEN_UV.x);
	vec3 bottom = mix(color_bl, color_br, SCREEN_UV.x);
	vec3 base = mix(top, bottom, SCREEN_UV.y);

	// TINT mode (additive) folds through the unified stack: the summed delta is a
	// scale=1 affine layer over the gradient base (identity when untinted). ADR-0067.
	vec3 combined = color_apply(base, 0);

	// source_color auto-linearizes inputs; convert back to sRGB for dithering, then re-linearize
	vec3 srgb = pow(max(combined, vec3(0.0)), vec3(1.0 / 2.2));
	// 256.0 = FFT's battle framebuffer width (measured, not the generic PSX 320) — see the
	// include's header. The same literal is passed by indexed_color.gdshader; both are the
	// same screen, so a dither cell has to be the same size in both.
	srgb = psx_dither_and_quantize(srgb, FRAGCOORD.xy, VIEWPORT_SIZE, 256.0);
	ALBEDO = pow(srgb, vec3(2.2));
}
