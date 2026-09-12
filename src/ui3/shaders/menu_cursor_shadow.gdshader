shader_type spatial;
// FFT menu glove-cursor SHADOW layer — the SUBTRACTIVE drop-shadow of the START sub-menu cursor
// (§15.20, gh #73). PSX ABR mode 2 (fb = fb − texel, clamped ≥0), the SAME mechanism as the unit /
// gold-box drop shadow (formation_shadow.gdshader) — NOT an average/mix. The shadow CLUT (0x7DBC)
// is a grey ramp: the raw CLUT colour IS the per-channel amount to subtract from whatever the glove
// sits over (dark inter-panel bg → stays near black; tan frame edge → darkens). ss1-verified: the
// oracle shadow drives bg (104,112,120) down to (0,8,16)…(40,40,32), i.e. bg − greyramp.
//
// Twin of vitals_sprite.gdshader's RANGETILE index->CLUT sampling, but: (1) blend_sub instead of
// opaque discard-all-a<0.5 (which drew this as a solid grey blob), and (2) NO pow(psx_gamma) — a
// subtractive pass over-darkens with the additive gamma knob (see formation_shadow: raw ROM
// subtraction). The opaque lit hand above writes depth, so the shadow's +2,+2 overlap is hidden
// behind the hand and only peeks out as the drop shadow.
//
// CRITICAL — this layer must DEPTH-TEST (test enabled, write never): the OPAQUE lit hand above it
// (vitals_sprite, rung RP_CURSOR_LIT) writes depth NEARER, so where the hand covers the shadow the
// test fails and the shadow is HIDDEN — it only peeks out at the +2,+2 offset, the real drop shadow.
// With the test off the FULL 16×16 subtract blooms around/through the hand into a far-too-dark blob
// (the "shadow too strong" bug).
//
// THIS FILE IS NOW THE OFF-FORK FALLBACK. It used to say "there is NO fold variant", on the premise
// that folding "uses a separate scratch depth buffer the in-scene hand can't write". That premise is
// stale: EngineFoldCompositor's Pass B builds its framebuffer from the compositor scratch + the
// SHARED opaque scene depth (`rb->get_depth_texture()`, LOADed not cleared) and tests
// GREATER_OR_EQUAL, so the in-scene opaque hand DOES occlude a folded shadow. Measured on the START
// menu with the bob frozen: 0 shadow-altered pixels inside the hand's footprint, both routes.
//
// And folding is not cosmetic — it is the CORRECTNESS fix. PSX subtracts in the 8-bit FRAMEBUFFER
// (display space); this shader runs against Godot's LINEAR target, so it subtracts a
// display-magnitude constant from linear light and over-darkens as the backdrop brightens. Measured
// against the ROM's `bg − CLUT` on the glove's peek region: in-scene max |err| 104, FOLDED max 4 —
// and 4 is half an RGB555 step, i.e. exact to the framebuffer's own quantisation. The glove looked
// fine for so long only because its usual backdrop is near-black, where the two spaces agree.
// See menu_cursor_shadow_fold.gdshader; producers route with Fold.owns().
//
// psx-ot-depth-exempt: screen-space ortho UI quad — depth is the menu overlay's real camera-Z rung
// (ADR-0077), NOT a battle-OT CUSTOM0 centroid. (No `DEPTH =` write; the rung-Z comes from the
// mount holder's world position, and the opaque hand's depth is what occludes this layer.)
// compositor-exempt: off-fork-fallback — OFF-FORK in-scene fallback ONLY. On the 4.8 Forward+ fork the shadow folds via
// menu_cursor_shadow_fold.gdshader (compositor_layer); this runs only when Fold.owns() is false.
// Selected by the six glove producers (StartActionMenu, Ability/Job/Equip/LearnAbility, DetailScene).
// display-space: folds-on-fork menu_cursor_shadow_fold.gdshader
//
// This marker USED to read "the glove sits ON TOP of already-composited opaque chrome and only needs
// to blend against the final framebuffer — it does NOT belong in the fold scratch". That was FALSE,
// and it is why the defect survived a green scoreboard: blending "against the final framebuffer"
// happens in LINEAR space, whereas PSX subtracts in DISPLAY space. The guard only checked that SOME
// reason was present, never that it was true. Measured before/after routing: max |err| vs the ROM's
// `bg - CLUT` went 104 -> 4 (half an RGB555 step). See the fold twin's header.
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub;

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row (0x7DBC)

uniform vec4 cell = vec4(0.0, 0.0, 16.0, 16.0);   // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform float brightness = 1.0;

void fragment() {
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	if (idx == 0) {
		discard;  // index 0 is the transparent key everywhere in the atlas
	}
	vec4 c = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
	if (c.a < 0.004) {
		discard;  // fully-transparent CLUT entry
	}
	// Keep STP=1 ONLY — the complement of vitals_sprite's `c.a < 0.9` opaque key. A CLUT alpha of
	// 128 is the PSX STP bit set (this texel blends; under abr=2 it subtracts), 255 is opaque ink
	// that belongs to the opaque pass. Together the two keys PARTITION a mixed-STP palette, so a
	// caller can put both passes on one rect and they never cover the same texel — that is how the
	// dialogue page-turn icon draws its subtractive drop shadow (DialogueBox._setup_page_icon).
	// NO-OP for the glove cursor, the original caller: the only opaque entry in its 0x7DBC shadow
	// CLUT is idx 15, and its shadow cell (184,0,16,16) never uses index 15 (histogram tops out at
	// 14). Its ramp entries 1..14 are all a=128 and all survive.
	if (c.a > 0.9) {
		discard;
	}
	// blend_sub == PSX ABR2: the raw CLUT colour is the amount subtracted (NO pow — see header).
	ALBEDO = clamp(c.rgb * brightness, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
}
