/*
	FEEDBACK-HUD SPRITE SHADER  (ADR-0063 / issues #89, #90)

	Over-unit feedback billboards — floating damage/heal numbers and the
	status/charge bubbles. Camera-facing quad, CUSTOM0-based Ordering-Table
	depth (ADR-0009) so it sorts against battlefield geometry, drawn from the
	RANGETILE system atlas (an 8bpp INDEX bitmap stored as grayscale, value =
	index*17 — the same atlas the vitals panel and status-icon extractor use).

	Faithful FFT visuals, our data: the digit / icon SHAPES come from the ROM
	atlas cell; the value / colour is the game's. Colour is a flat `tint`
	(damage=white, heal=green, MP=blue) with a `fade` alpha the caller ramps —
	FFT's two-tone look is reproduced by drawing this twice (a dark shadow layer
	behind a tinted fill layer), matching the ROM's shadow-sprite + fill-sprite
	digit render (spec §"Digits: two-layer render").

	Does NOT write POSITION, so it is outside the PAR seam (ADR-0060): pixel
	aspect is baked into the quad geometry at build time (DamageNumber3D /
	StatusBubble3D size their cells by w/h), not stretched in-shader.
*/

shader_type spatial;
// OPAQUE (PSX GP0 0x2C — the number's grow/steady phase and the status/charge
// bubble are drawn opaque on the machine, NOT alpha-blended: the PSX GPU has no
// alpha channel, only opaque + four fixed semi-transparency rates). The glyph is
// hard-edged and alpha-KEYED (the fragment `discard`s the transparent index), so
// it renders opaque with an alpha-test, never `blend_mix` (which was a non-PSX
// Godot-ism that also parked this prim in the transparent queue — see below).
//
// Being opaque is what makes it composite correctly with folded battle effects:
// the display-space compositor SEEDS its scratch from the OPAQUE color buffer
// (Pass A, PRE_TRANSPARENT), folds the additive/subtractive effect prims into it
// (Pass B), then resolves back wherever an effect drew (Pass C). Anything opaque
// is in that seed by default and gets rebuilt correctly; a `blend_mix` prim draws
// in the transparent queue AFTER the seed and is clobbered by Pass C wherever an
// effect overlaps it (the Fire-on-a-charging-caster / fading-number artifact,
// ADR-0063 / #89). The rule: opaque = in the scratch (default); a PSX semi-
// transparency mode = opt into the fold. This is opaque, so it needs neither
// `blend_add`/`blend_sub` nor `compositor_layer`. The number's genuinely-additive
// FADE band opts into the fold via feedback_hud_sprite_additive_fold.gdshader.
//
// depth_draw_opaque + explicit DEPTH keeps it in the OT model (occluded by terrain).
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

// OT depth from the node origin (WORLD point) — same per-object path a unit
// sprite / projectile uses (ADR-0009). Provides ot_depth + the varying.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D index_atlas : filter_nearest, repeat_disable;  // RANGETILE.tga
uniform vec4 cell = vec4(0.0, 0.0, 8.0, 14.0);   // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform vec3 tint = vec3(1.0);                    // flat glyph/icon colour (tint mode)
uniform float fade : hint_range(0.0, 1.0) = 1.0;  // popup fade (caller-ramped)
// CLUT mode (the damage number): look the glyph index up in a 16-colour palette
// (the ROM number CLUT 0x7d7c) instead of flat-tinting, so the outline / fill /
// AA shading come out faithfully in ONE pass. StatusBubble3D leaves this off and
// uses the flat `tint`. Mirrors vitals_sprite.gdshader.
uniform sampler2D palette_tex : filter_nearest, repeat_disable;  // 16x1 CLUT row
uniform bool use_palette = false;
// Colour brightness multiplier. The damage-number trending (NumberPopupTrend)
// ramps this 1->0 across its fade band to darken the palette toward black; the
// additive twin (feedback_hud_sprite_additive) then makes black = invisible.
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
// DepthMode selector (0 STANDARD). Over-unit billboards sort at their world
// point like a unit sprite; STANDARD keeps the number co-planar with the unit.
uniform int depth_mode = 0;

void vertex() {
	// Camera-facing billboard: replace the model basis with the inverse-view
	// basis, keeping the model translation (node origin) — identical to the
	// projectile billboard, minus the PAR POSITION write.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	// Preserve the mesh's own scale (billboard basis above dropped it).
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);

	// OT depth from the node origin (unaffected by the billboard MODELVIEW).
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, depth_mode);
}

void fragment() {
	// Sample the atlas cell (index bitmap). Recover the 0..15 index from the
	// *17 grayscale convention; index 0 is the transparent key everywhere in
	// the atlas (matches vitals_sprite.gdshader).
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	// CLUT mode: index -> 16-colour palette; else flat tint. Index 0 (or a
	// transparent palette entry) is the key everywhere in the atlas.
	vec3 col;
	if (use_palette) {
		vec4 pc = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
		if (pc.a < 0.5) {
			discard;
		}
		col = pc.rgb;
	} else {
		if (idx == 0) {
			discard;
		}
		col = tint;
	}
	// sRGB-to-linear (pow 2.2) so brightness matches the rest of the battle
	// render (unit.gdshader / indexed_color). This opaque prim writes into the
	// LINEAR scene color buffer (unlike the display-space fold twin, which drops
	// the pow). `brightness` is 1 here; the fade->black ramp lives on the fold twin.
	// No ALPHA write: this is opaque (alpha-KEYED by the discards above), so it
	// lands in the compositor's opaque seed. `fade` is kept as a uniform only for
	// swap-parity with the additive twin (the mesh reuses one ShaderMaterial).
	ALBEDO = pow(clamp(col * brightness, vec3(0.0), vec3(1.0)), vec3(2.2));
	DEPTH = ot_computed_depth;
}
