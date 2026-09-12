shader_type spatial;

// Vault: [[Dialogue Pagination]]
// ADR-0077 depth-ladder member: the panel is OPAQUE and WRITES DEPTH from its real camera-Z (the
// depth ladder rung it mounts at), so a folded display-space prim beneath it (the formation vitals
// band, or a combat effect) fails the engine fold's Pass B depth test where the panel is nearer and
// never clobbers the panel in Pass C. Occlusion + ordering fall out of that ONE Z — no render_priority,
// no depth_test_disabled "always on top", no per-shader magic depth (ADR-0077 §Decision).
//
// TWO traps this render_mode threads, both spelled out in ADR-0077:
//   1. depth_test_disabled (the old contract) was a Vulkan no-op — the spec disables depth WRITES
//      whenever the depth TEST is disabled, so `depth_draw_always` wrote nothing and the band folded
//      straight over the panel. Depth test MUST stay enabled for the write to land.
//   2. writing ALPHA at all (even =1.0) opts a spatial material into the TRANSPARENT pipeline, so it
//      renders after the fold's PRE_TRANSPARENT seed and never lands in the scratch (ADR-0077 impl
//      note). So this shader stays opaque via the alpha-key `discard` below and NEVER writes ALPHA.
//
// psx-ot-depth-exempt: screen-space ortho UI quad — its depth is the intra-panel ladder's real
// camera-Z (ADR-0077), NOT a battle-OT CUSTOM0 centroid, so it opts out of ADR-0009's CUSTOM0 rule.
// (No `DEPTH =` write, so check_depth_shaders.py doesn't flag it; this marks the opt-out for readers.)
render_mode unshaded, cull_disabled;

// Faithful FFT vitals-readout sprite (#91). Samples one cell of the RANGETILE
// system atlas (an 8bpp INDEX bitmap stored as grayscale, value = index*17) and
// looks the index up in a 16-colour CLUT texture. The panel uses three CLUTs:
// labels (menu 0x7cbc), cur/max digits (a remap of the (168,49) strip so it reads
// cream-body + dark-edge, matching the live PCSX framebuffer), and HP/MP/CT bars
// (per-stat 0x7efc/0x7f3c/0x7f7c). Mirrors ui_font_char.gdshader: filter_nearest,
// NO source_color, pow(.,2.2) so brightness matches the rest of ui3.

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row
uniform sampler2D palette_bg_tex : filter_nearest, repeat_disable; // §15.21 backgrounded CLUT (default unset → never sampled unless backgrounded)
uniform float backgrounded = 0.0; // 0 = foreground palette_tex; 1 = palette_bg_tex

uniform vec4 cell = vec4(0.0, 0.0, 8.0, 8.0);    // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform float brightness = 1.0;                   // bars are authored dark (~2x)

// Box-open scissor (DetailScene §15.17): the unit-detail box-open is a growing rectangular
// APERTURE that reveals the fully-rendered panel — nothing scales; fragments outside the
// aperture are clipped. `clip_world` is that aperture in WORLD space (xy = min, zw = max);
// the default is unbounded so every OTHER call site (formation grid, battle HUD) is
// byte-identical (they never set it → the test below is always false). See set_open_frame.
uniform vec4 clip_world = vec4(-1e20, -1e20, 1e20, 1e20);
// The SCREEN's inverse global transform. `clip_world` is an axis-aligned rect in the SCREEN's own
// space (display px * ppu), but MODEL_MATRIX * VERTEX is GLOBAL — the two only coincide while the
// screen root happens to sit at the world origin, unrotated and unscaled. That held for as long as
// every UI3 screen had its own camera; it stops holding the moment a screen mounts as a CHILD of
// the map's camera (ADR-0137), where the UI plane is rotated and scaled in world space and every
// clipped fragment silently falls outside the box. Mapping the fragment back into screen space
// first makes the comparison space-correct on any host. Identity default ⇒ unchanged where the
// screen already is the origin.
uniform mat4 clip_basis_inv = mat4(1.0);
varying vec3 v_world;

void vertex() {
	v_world = (clip_basis_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (v_world.x < clip_world.x || v_world.y < clip_world.y
			|| v_world.x > clip_world.z || v_world.y > clip_world.w) {
		discard;  // outside the box-open aperture (§15.17 scissor reveal)
	}
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	if (idx == 0) {
		discard;  // index 0 is the transparent key everywhere in the atlas
	}
	vec2 _pc = vec2((float(idx) + 0.5) / 16.0, 0.5);
	vec4 c = (backgrounded > 0.5) ? texture(palette_bg_tex, _pc) : texture(palette_tex, _pc);
	// The alpha key means "STP=0 ONLY". A CLUT entry's alpha carries the PSX **STP bit**: the
	// extractor writes a=255 for STP=0 (opaque ink) and a=128 for STP=1 (a texel the ROM blends
	// — under abr=2, SUBTRACTED from the framebuffer). This shader is opaque by contract
	// (ADR-0077: never write ALPHA), so it can only draw the STP=0 half; the STP=1 half belongs
	// to a second, `blend_sub` pass (menu_cursor_shadow.gdshader) over the same rect.
	//
	// The threshold is 0.9, NOT 0.5: 128/255 = 0.502, so at `< 0.5` an STP=1 texel SURVIVED this
	// discard and drew as opaque ink — that is what rendered the dialogue page-turn icon's drop
	// shadow as a black blob. 0.9 partitions the two halves cleanly (nothing sits between 128
	// and 255), and the sub pass takes the complementary `> 0.9` key.
	//
	// Safe for every other consumer: across all cells bound into this shader, page_turn_icon is
	// the ONLY cell set whose CLUT-indices reach an STP=1 entry (4/4 of its cells). window_tabs,
	// word_labels, sort_header labels+buttons and bars.swatch top out at index 6.
	if (c.a < 0.9) {
		discard;
	}
	ALBEDO = pow(clamp(c.rgb * brightness, vec3(0.0), vec3(1.0)), vec3(2.2));
	// OPAQUE: every surviving pixel is fully opaque ink (index 0 / a<0.5 already discarded above). We
	// deliberately do NOT write ALPHA — that keeps the material in the OPAQUE pass so it lands in the
	// fold's PRE_TRANSPARENT seed + the shared depth buffer the fold reads (ADR-0077 ALPHA-write trap).
}
