/*
	FEEDBACK-HUD SPRITE SHADER — ADDITIVE FADE TWIN, ENGINE-FOLD VARIANT  (ADR-0063 / #89, ADR-0074 / #229)

	The `compositor_layer` counterpart of feedback_hud_sprite_additive.gdshader, worn by a damage
	number's digits ONLY during the fade band (DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md Round 5.2). The
	opaque grow+steady phase stays in-scene (feedback_hud_sprite.gdshader); the fade phase — the one
	that additively adds a glow to whatever is behind it — routes through the engine fold like every
	other additive PSX prim so it clamps per-step in the display-space scratch and can no longer flash
	an overlapping routed prim (the fire-on-number artifact, #89 follow-up).

	Fragment logic is identical to the in-scene additive twin (index atlas -> CLUT/tint -> brightness
	ramp) EXCEPT the sRGB->linear gamma the in-scene twin applies is dropped BY DESIGN: the fold blends
	in DISPLAY space (the FoldSurface seed converts the linear scene to sRGB, Pass B hardware-adds
	display texels, Pass C converts back). Same as crystal_fold.gdshader. Uniforms are byte-identical to
	the in-scene twin so DamageNumber3D can swap only `.shader` and keep its ShaderMaterial's set values.

	Forward+ / fork only (compositor_layer + engine Pass B). OCCLUSION: depth_draw_never + depth-test
	ENABLED via DEPTH = ot_computed_depth — the fold pass binds the shared opaque scene depth and
	tests GREATER_OR_EQUAL, so a number behind terrain clips per-fragment while still folding against
	effects by render_layer_order. This shader IS routed (compositor_layer), so it carries no exempt marker.
*/

shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, compositor_layer, depth_draw_never;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D index_atlas : filter_nearest, repeat_disable;  // RANGETILE.tga
uniform vec4 cell = vec4(0.0, 0.0, 8.0, 14.0);   // atlas px: x, y, w, h
uniform vec2 atlas_size = vec2(256.0, 256.0);
uniform vec3 tint = vec3(1.0);                    // flat glyph colour (tint mode)
uniform float fade : hint_range(0.0, 1.0) = 1.0;  // kept for uniform parity with the in-scene twin
uniform float brightness : hint_range(0.0, 1.0) = 1.0;  // palette->black ramp
uniform sampler2D palette_tex : filter_nearest, repeat_disable;  // 16x1 CLUT row
uniform bool use_palette = false;
uniform int depth_mode = 0;

void vertex() {
	// Camera-facing billboard, identical to the in-scene twin — the scale-extracting form so the
	// per-digit trend `scale` (set every frame, still moving during the fade) keeps driving size.
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
	// Additive in DISPLAY space (no sRGB->linear gamma): the `brightness` ramp to black IS the fade — additive
	// blend makes the darkening read as a glow-out. ALPHA = 1.0 is the fold coverage flag (Pass C keeps
	// only covered texels); the discard above already dropped the transparent CLUT key / index-0 cells.
	ALBEDO = clamp(col * brightness, vec3(0.0), vec3(1.0));
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
