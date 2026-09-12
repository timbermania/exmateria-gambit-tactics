// Shared body for the MONOMORPHIC formation gold-box FOLD materials (ADR-0077 / ADR-0074 ④c).
// Twin of formation_box.gdshaderinc, but a `compositor_layer` MEMBER: the 4.8 Forward+ engine Pass B
// collects it into the display-space scratch and blends it with the PSX per-step UNORM clamp — so the
// gold box no longer needs the retired Mobile-era FormationDisplaySpaceComposite. It differs from the
// in-scene twin in THREE ways:
//   * render_mode gains `compositor_layer` and drops `depth_test_disabled` (the fold pass binds the
//     shared opaque scene depth and tests GREATER_OR_EQUAL), so the box is occluded BEHIND the unit
//     body per-fragment — the ADR-0077 "box under body" occlusion, which falls out of the real-Z ladder.
//   * the fragment writes `DEPTH = fold_depth` (the box's materialized rung Z, reversed-Z NDC).
//   * TONE (effect-parity 2026-07-30): the fold scratch is DISPLAY-space sRGB and the engine hardware-adds
//     into it, so the box adds its RAW palette gradient (PSX ABR dst±src·gouraud/128) — NOT the particle
//     pow(psx_gamma)·psx_brightness. The Mobile in-scene twin blends into a LINEAR buffer so it keeps the
//     pow tone; here that ×2.2 clipped the bright gold indices (idx1–7 → 1.0) and collapsed the gradient
//     into a thick pale band (live PSX median (216,176,72) vs the port's (255,255,115)). No per-prim 5-bit
//     snap either — the resolve pass quantizes ONCE post-accumulation. The two wrappers
// formation_box_fold / formation_box_sub_fold differ ONLY in the render_mode blend — material
// SELECTION among monomorphic shaders (ADR-0074), not in-shader axis branching.
uniform sampler2D index_tex : filter_nearest;
uniform sampler2D palette_tex : filter_nearest, hint_default_transparent;
// Per-quadrant mirror: (0,0)=none (1,0)=x-flip (0,1)=y-flip (1,1)=xy-flip.
uniform vec2 uv_flip = vec2(0.0, 0.0);
uniform float brightness = 1.0;      // PSX gouraud/128 modulate (per-slot trail fade)
// No psx_gamma / psx_brightness: the box adds its raw display-space CLUT gradient (PSX ABR dst±src),
// NOT the particle pow(gamma)·2.2 tone — that ×2.2 clipped the bright gold indices and collapsed the
// gradient. See the fragment shaders (formation_box_fold / _sub_fold) and effect-parity 2026-07-30.

// The box quad's reversed-Z NDC depth, materialized from its depth-ladder rung Z (ADR-0077): the
// whole flat quad is coplanar at one Z, so the vertex clip Z is the fragment DEPTH for occlusion.
varying float fold_depth;

void vertex() {
	// The scene places/scales the quad in ortho world at its rung Z; project it and keep the NDC depth.
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
}

// Raw palette sample under the quadrant's mirror: .rgb = sRGB gold, .a = idx0 transparency (0) vs
// gold (1). Sampled RAW (no source_color) — the index/CLUT lookup must not be sRGB-decoded.
vec4 box_sample(vec2 raw_uv) {
	vec2 uv = mix(raw_uv, vec2(1.0) - raw_uv, uv_flip);
	int idx = int(round(texture(index_tex, uv).r * 15.0));
	return texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
}
