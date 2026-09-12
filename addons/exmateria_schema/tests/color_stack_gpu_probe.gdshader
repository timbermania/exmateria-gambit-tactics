// GPU parity probe for ADR-0067: renders color_apply(probe_base, 0) so a test
// can read the pixel back and compare it to ColorStack.fold on the CPU — proving the
// GLSL include matches the CPU fold (and thus the byte-exact oracle) on real hardware.
// canvas_item so a plain ColorRect in a SubViewport exercises it (the include is
// shader-type agnostic — it only declares the color_layer_* uniforms + color_apply).
shader_type canvas_item;
render_mode unshaded;

#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

uniform vec3 probe_base = vec3(0.0);

void fragment() {
	COLOR = vec4(color_apply(probe_base, 0), 1.0);
}
