/*
	PROJECTILE SPRITE SHADER

	Renders billboarded sprite quads for thrown weapon and item projectiles.
	Supports spin rotation around the face normal while maintaining billboard
	orientation toward the camera.

	Color pipeline matches unit.gdshader and indexed_color.gdshader:
	- No source_color hint (PSX textures are not sRGB)
	- Unshaded (no Godot lighting)
	- Manual sRGB-to-linear conversion via pow(2.2) for Forward+
*/

shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

// Single billboard quad (thrown weapon / item sprite) -> per-OBJECT OT depth
// from the node origin, like a unit sprite (ADR-0009 per-object path). Alpha is
// scissor-tested (discard) so the quad is opaque and writes depth. STANDARD mode
// (no tile nudge — a projectile is airborne). See the "Rendering depth" cluster.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// Sprite texture (no source_color - PSX textures need manual sRGB-to-linear).
// When use_palette is false, this is straight RGBA (item icons). When true,
// it's an indexed-grayscale TGA (R=G=B=index*17, A=255 always) and the actual
// color comes from palette_texture[palette_row]. WEP1.tga uses this path
// since the ADR-0022 sprite-extract refactor.
uniform sampler2D albedo_texture : filter_nearest, hint_default_transparent;

// Spin angle in radians (set per-tick from GDScript)
uniform float spin_angle : hint_range(-6.283, 6.283) = 0.0;

// Alpha scissor threshold
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.1;

// Paletted sampling for WEP1 weapon-sprite projectiles. Mirrors the unit
// shader's add_tile_paletted path: index 0 is FFT-magic transparent, so we
// discard it; otherwise we sample palette_texture at (idx, palette_row).
uniform bool use_palette = false;
uniform sampler2D palette_texture : filter_nearest, hint_default_transparent;
uniform int palette_row = 0;

// PAR (ADR-0036): Pattern 2, anchor-only. The projectile tracks a PAR'd caster/
// target through world space; its sprite art renders at native PSX pixel aspect.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"
// Sprite stretch (ADR-0044): EFFECTS-taxonomy billboard-WIDTH multiplier. 1.0 = native.
global uniform float psx_fx_stretch;

void vertex() {
	// Spin vertices around local Z (face normal) before billboard
	float c = cos(spin_angle);
	float s = sin(spin_angle);
	float x = VERTEX.x;
	float y = VERTEX.y;
	VERTEX.x = x * c - y * s;
	VERTEX.y = x * s + y * c;

	// Billboard: face camera while preserving scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	// Preserve original mesh scale
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);

	// OT depth from the node origin (unaffected by the billboard MODELVIEW above).
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, 0);

	// PAR (Pattern 2, anchor-only, via the shared seam): anchor tracks the map
	// (pixel_aspect); the billboard offset stretches by EFFECTS width (ADR-0044).
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, psx_fx_stretch);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec4 final_color;

	if (use_palette) {
		// Indexed-grayscale -> palette. Recovers 0..15 index from the *17
		// grayscale convention, drops FFT-magic transparent index 0, then
		// samples palette_texture at (idx, palette_row).
		int idx = int(tex.r * 15.0 + 0.5);
		if (idx == 0) {
			discard;
		}
		vec2 palette_uv = vec2(
			(float(idx) + 0.5) / 16.0,
			(float(palette_row) + 0.5) / 16.0
		);
		final_color = texture(palette_texture, palette_uv);
		if (final_color.a < alpha_scissor_threshold) {
			discard;
		}
	} else {
		if (tex.a < alpha_scissor_threshold) {
			discard;
		}
		final_color = tex;
	}

	// sRGB-to-linear conversion for Forward+ (matches unit.gdshader / indexed_color.gdshader)
	ALBEDO = pow(final_color.rgb, vec3(2.2));
	DEPTH = ot_computed_depth;
}
