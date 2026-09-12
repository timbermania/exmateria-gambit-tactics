shader_type spatial;
// ADR-0077: the flat UI materializes its render_priority ladder into real Z, so this OPAQUE floor
// now WRITES DEPTH (dropped depth_draw_never / depth_test_disabled) at its background rung. That seeds
// the display-space fold scratch (Pass A) with the cobble the band subtracts from, and gives folded
// prims a depth buffer to occlude against.
render_mode unshaded, cull_disabled;

// Vault: [[Formation Screen Compositing]]

// FORMATION-screen tiled stone background. Samples the 128x32 indexed BACKGROUND
// tile (value = index*15/255 in R) through its 16-colour CLUT, tiled across the
// 256x240 virtual screen, then darkened by a SELECTED-UNIT floor SPOTLIGHT — an
// oval light pool centred on the cursor unit's floor-contact point that slides as
// the selection moves (FORMATION_SCREEN.md §14.6.3; the floor gradient is dynamic,
// NOT the static vertical ramp the port shipped first). The falloff mirrors the
// orb (§10): base − swing·sqrt(dx² + vfac·dy²), vfac = 4 ⇒ a 2:1 horizontally-
// elongated pool. Mirrors vitals_sprite.gdshader's index/palette recovery
// (filter_nearest, no source_color, pow(.,2.2) to match ui3 brightness). This is an
// OPAQUE background (CLUT slot 14), so index 0 is a real colour — no key discard.

uniform sampler2D index_atlas : filter_nearest, repeat_enable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;   // 16x1 CLUT row

uniform vec2 tile_px = vec2(128.0, 32.0);
uniform vec2 screen_px = vec2(256.0, 240.0);
uniform float flip_v = 0.0;                         // set 1.0 if the quad's V runs bottom->top

// Selected-unit floor spotlight (virtual-px screen space, top-left origin).
uniform vec2 spot_center_px = vec2(37.0, 76.0);     // oval centre = selected unit's feet
// Oracle-grounded (§16): the PSX floor gouraud is base 0xFF / floor 0x50, applied as
// texture × gouraud/128 ⇒ a BRIGHTENING pool up to ~2× near the selected unit (NOT a
// darken-only vignette). spot_base > 1.0 by design; c·dark is clamped to 1.0 below,
// mirroring the PSX per-channel clamp of texture×gouraud to 255.
uniform float spot_base = 1.72;                      // centre multiplier (gouraud 0xFF/128 ≈ 2×, fit peak)
uniform float spot_swing = 0.0068;                   // brightness units lost per px of oval distance
uniform float spot_vfac = 4.0;                       // vertical falloff weight (4 ⇒ 2:1 wide oval)
uniform float spot_min = 0.64;                       // far floor clamp ≈ 0x50/128 = 0.625 (non-black)

void fragment() {
	float v = mix(UV.y, 1.0 - UV.y, flip_v);
	vec2 rep = screen_px / tile_px;             // (2, 7.5) tiles across the screen
	vec2 tuv = fract(vec2(UV.x, v) * rep);
	int idx = int(floor(texture(index_atlas, tuv).r * 15.0 + 0.5));
	vec4 c = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));

	// Oval spotlight: this fragment's virtual-px position vs the selected-unit centre.
	vec2 frag_px = vec2(UV.x, v) * screen_px;
	vec2 d = frag_px - spot_center_px;
	float dist = sqrt(d.x * d.x + spot_vfac * d.y * d.y);
	float dark = clamp(spot_base - spot_swing * dist, spot_min, spot_base);

	ALBEDO = pow(clamp(c.rgb * dark, vec3(0.0), vec3(1.0)), vec3(2.2));
	// Do NOT assign ALPHA: writing it (even = 1.0) opts a spatial material into Godot's TRANSPARENT
	// pipeline, so it would render AFTER the fold's PRE_TRANSPARENT seed and never reach the scratch —
	// leaving folded prims (the gold box's filled interior) composited over flat gray. Not writing ALPHA
	// keeps the floor OPAQUE, so Pass A seeds the cobble the box/halo blend against (ADR-0077).
}
