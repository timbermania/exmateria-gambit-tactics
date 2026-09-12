shader_type spatial;

// Vault: [[Formation Screen Compositing]]
// Vault: [[PSX GPU Primitives]]
// FORMATION orb ADDITIVE rim HALO — fold variant (PSX ABR=01; ADR-0077 fold member). The STP=1 rim
// texels (idx 8-11, palette a=128) additively LIFT the floor into the soft blue halo — the effect that
// SILENTLY VANISHED when the Mobile FormationDisplaySpaceComposite was clobbered by the engine-fold
// autopilot on the Forward+ fork. As a `compositor_layer` member the halo blends in the display-space
// scratch with the PSX per-step UNORM clamp instead. RAW display-space add: NO pow(psx_gamma) — the
// fold has no tonemap after it, so linearizing the halo colour is the gold-box wrong-space bug (a half
// round-trip with no return leg). This completes the ADR-0077 box-family fix: the box fold twins were
// corrected to raw display-space (formation_box_fold) but this rim was left on the old in-scene pow.
// The per-prim 5-bit snap is also dropped — the fold resolve quantizes ONCE post-accumulation (see
// effect_fold_add). Also differs in render_mode (compositor_layer, dropped depth_test_disabled) + real-Z.
// [2026-07-31: was `pow(c.rgb, psx_gamma) * brightness * psx_brightness`; see check_no_pow_in_fold.py.]
// The opaque orb CORE (STP=0) still draws in-scene (formation_orb_opaque); this folds only the rim.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

uniform sampler2D index_tex : filter_nearest;
uniform sampler2D palette_tex : filter_nearest, hint_default_transparent;
uniform float brightness = 1.0;      // PSX gouraud/128 (per-cell falloff + pulse) — ALREADY the faithful modulate

// The orb quad's reversed-Z NDC depth from its materialized rung Z (ADR-0077): occlusion vs the opaque
// scene (the halo sits at RP_ORB, in FRONT of the unit body, so nothing occludes it — but the write
// keeps the fold on the one shared depth convention).
varying float fold_depth;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;
	fold_depth = clip.z / clip.w;
}

// Raw palette sample: .rgb = sRGB palette colour, .a = STP flag (0 / ~0.5 / 1). Twin of
// formation_orb.gdshaderinc.orb_sample.
vec4 orb_sample(vec2 uv) {
	int idx = int(round(texture(index_tex, uv).r * 15.0));
	return texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
}

void fragment() {
	vec4 c = orb_sample(UV);
	if (c.a < 0.01 || c.a > 0.9) {
		discard; // keep STP=1 rim only (transparent + opaque core discarded)
	}
	// Faithful PSX additive = display CLUT texel × gouraud/128. `brightness` IS gouraud/128
	// (ORB_BASE_LEVEL=128 identity), so NO ×psx_brightness — that global is the ÷255→÷128 scale
	// conversion for the effect-POOL modulate (particle/crystal), and applying it to an already-÷128
	// modulate double-brightens (the overbright halo, 2026-07-31). Matches formation_box_fold exactly.
	// No per-prim 5-bit snap: the fold resolve (foldsurface_resolve.glsl) quantizes ONCE post-accumulation.
	ALBEDO = c.rgb * brightness;
	ALPHA = 1.0; // full additive intensity
	DEPTH = fold_depth;
}
