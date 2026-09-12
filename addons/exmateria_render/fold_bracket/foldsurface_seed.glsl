#[vertex]
#version 450

// Fullscreen triangle (no vertex buffer). Pass A of the combat display-space
// composite: copy the presented color layer into an owned scratch that the fold
// (pass B) accumulates into with HARDWARE BLEND, then the composite-out (pass C)
// reads back. The Mobile color layer can't be both read and written in one pass
// (no subpass self-dependency; see FORMATION_ORB_ADDITIVE_COLORSPACE.md +
// COMPOSITOR_MULTIMESH_INTEGRATION_SCOPING.md).
//
// #209 CHANGE from the #208 scaffold: the scratch is now a DISPLAY-SPACE
// ACCUMULATOR, not a linear frozen background. The fold blends its per-prim
// display-space contributions straight onto the scratch with fixed-function blend
// (UNORM saturation == the exact per-prim clamp, proto_ordered_fold Q3), so the
// scratch must hold sRGB/display values. This pass therefore converts the linear
// color layer to display space on the way in, and seeds the coverage channel
// (alpha = 0 = "no effect here") so pass C can leave untouched background pristine.
void main() {
	vec2 v = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(v * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

layout(set = 0, binding = 0) uniform sampler2D src_tex;

layout(location = 0) out vec4 frag_color;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 _pad;   // pad to 16 bytes: GDScript sends [x,y,0,0]; Godot 4.7 enforces exact push-constant size
} params;

vec3 lin_to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
	vec2 uv = gl_FragCoord.xy / max(params.raster_size, vec2(1.0));
	vec3 bg_lin = texture(src_tex, uv).rgb;
	// scratch = display-space background, coverage = 0 (untouched).
	// Coverage baseline = 0.5 (NOT 0). Godot's blend_sub uses alpha_blend_op=REVERSE_SUBTRACT, so a
	// subtractive carrier DRIVES the coverage-alpha DOWN (0.5 → 0), whereas add/mix drive it UP
	// (→ 1.0 / 0.75). Seeding a mid baseline lets Pass C detect "touched" as ANY deviation from 0.5,
	// so subtractive fold coverage survives without the engine forcing coverage-alpha (which the clean
	// compositor_layer primitive drops — coverage stays 100% userland). See foldsurface_resolve.glsl.
	frag_color = vec4(lin_to_srgb(bg_lin), 0.5);
}
