/*
	FEEDBACK-HUD SPRITE SHADER — ADDITIVE FADE TWIN  (ADR-0063 / issue #89)

	The additive counterpart of feedback_hud_sprite.gdshader, used ONLY for the
	damage-number "trending" fade band (DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md
	Round 5.2). In FFT the number renders opaque (GP0 0x2C) during grow+steady,
	then at phase 0x32 the primitive switches to additive semi-transparent (GP0
	0x2E, tpage ABR 1 = B+F) WHILE the palette ramps toward black. Additive +
	palette->black = adds nothing = fade to nothing.

	So DamageNumber3D swaps its digit materials onto THIS shader at the fade
	switch and ramps `brightness` 1->0: additive blend makes the darkening read
	as a glow-out instead of an alpha crossfade. Fragment logic is identical to
	the opaque shader; only the blend mode differs (blend_add vs blend_mix).
*/

shader_type spatial;
// compositor-exempt: off-fork-fallback — routed through the compositor on Forward+ via
// assets/shaders/feedback_hud_sprite_additive_fold.gdshader (DamageNumber3D loads that compositor_layer
// variant for the fade band when CompositorAutopilot owns compositing). This in-scene blend_add file is
// the Mobile/stock fallback only, so it is not a Forward+ lock-in blocker. (It was previously exempted
// on the false premise that a damage number "never overlaps other routed prims" — Fire landing on a
// unit with a fading number flashed exactly that overlap, ADR-0063 / #89, which is why the fade is now
// folded; see feedback_hud_sprite_additive_fold.gdshader.)
// blend_add is the fade-band twin: ALBEDO is ADDED to the background, so
// brightness->0 (palette to black) adds nothing = invisible. depth_draw_opaque
// + explicit DEPTH keeps it in the OT model (occluded behind terrain).
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_opaque;

#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D index_atlas : filter_nearest, repeat_disable;  // RANGETILE.tga
uniform vec4 cell = vec4(0.0, 0.0, 8.0, 14.0);   // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform vec3 tint = vec3(1.0);                    // flat glyph colour (tint mode)
uniform float fade : hint_range(0.0, 1.0) = 1.0;  // kept for uniform parity
uniform float brightness : hint_range(0.0, 1.0) = 1.0;  // palette->black ramp
uniform sampler2D palette_tex : filter_nearest, repeat_disable;  // 16x1 CLUT row
uniform bool use_palette = false;
uniform int depth_mode = 0;

void vertex() {
	// Camera-facing billboard, identical to the opaque shader.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, depth_mode);
}

void fragment() {
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
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
	// Additive: the darkening `brightness` ramp is the fade. sRGB->linear pow to
	// match the rest of the battle render.
	ALBEDO = pow(clamp(col * brightness, vec3(0.0), vec3(1.0)), vec3(2.2));
	ALPHA = fade;
	DEPTH = ot_computed_depth;
}
