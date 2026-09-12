#[vertex]
#version 450

// Fullscreen triangle (no vertex buffer). Pass C of the combat display-space
// composite (#209): resolve the DISPLAY-SPACE fold accumulator back into the LINEAR
// color layer. Runs once per frame after all mode buckets have folded into the
// scratch (pass A copy-in + pass B per-bucket blend). Mirrors the atom's "only touch
// effect pixels" property so the untouched 3D background keeps its full precision.
void main() {
	vec2 v = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(v * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450

layout(set = 0, binding = 0) uniform sampler2D scratch_tex;   // display-space fold accumulator

layout(location = 0) out vec4 frag_color;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float quantize_levels;   // steps-1 per channel; 31.0 == PSX RGB555. <= 0 disables (ADR-0152)
	float _pad;              // still 16 bytes: GDScript sends [x,y,levels,0]; the size is enforced exactly
} params;

vec3 srgb_to_lin(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
// Framebuffer quantization — snap the display-space result to `levels+1` steps per
// channel. Applied ONCE here (not per prim): within a same-direction run integer add/sub
// has no rounding, so grouped-then-quantized == the per-prim fold (proto_ordered_fold Q3).
//
// The LEVEL is a policy the bracket is given, not a constant it owns (ADR-0152, goal #8).
// 31.0 is the PSX RGB555 framebuffer and is what this game runs; `levels <= 0` is a
// consumer that wants the fold without the 5-bit crush, and costs a branch, not a fork.
vec3 quantize(vec3 c, float levels) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	if (levels <= 0.0) {
		return c;
	}
	return floor(c * levels + 0.5) / levels;
}

void main() {
	vec2 uv = gl_FragCoord.xy / max(params.raster_size, vec2(1.0));
	vec4 s = texture(scratch_tex, uv);
	// Coverage gate: pass A seeded alpha to a BASELINE of 0.5 (not 0); a prim that drew here moved it
	// OFF the baseline in EITHER direction — add/mix push it up (→1.0/0.75), sub pushes it down (→0,
	// via Godot's blend_sub REVERSE_SUBTRACT on alpha). "Touched" = any deviation from the baseline, so
	// subtractive coverage survives (a plain `s.a <= 0` gate would treat sub→0 as untouched and discard
	// the whole subtractive fold). Untouched pixels stay at 0.5 and are left exactly as the scene
	// rendered them (no round-trip, no 5-bit crush of the 3D background).
	if (abs(s.a - 0.5) <= 0.1) {
		discard;
	}
	frag_color = vec4(srgb_to_lin(quantize(s.rgb, params.quantize_levels)), 1.0);
}
