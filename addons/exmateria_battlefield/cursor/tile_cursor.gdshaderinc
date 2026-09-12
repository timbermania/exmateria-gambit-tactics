// Shared body for the floating tile-cursor sprite — drawn EXACTLY like an
// effect particle (effect_particle_opaque + effect_particle_mode0), not as a
// special case. The cursor sprite (BATTLE.BIN CLUT slot 4) carries BOTH opaque
// body texels (STP=0, idx 7..15) and semi-transparent outline texels (STP=1,
// idx 1..6) in one sprite. PSX semi-transparency picks a blend per-texel via
// the STP bit, but Godot's `render_mode blend_*` is compile-time (one blend per
// material) — so, like the particles, the cursor is drawn in TWO passes that
// each keep only their half of the STP bit:
//   tile_cursor_opaque  — STP=0 body  (no blend, writes depth)
//   tile_cursor_semi    — STP=1 outline (blend_mix, ALPHA=0.5 == PSX ABR=00)
//
// `range_tex` is the indexed-grayscale RANGETILE TGA (R = index*17);
// `range_palette` is the 16x9 BATTLE.BIN CLUT atlas. Each palette entry carries
// its PSX STP flag in alpha (parse_range_tiles.py::bgr555_to_rgba):
//   a=0    idx 0 transparent slot -> discarded by both passes
//   a=128  STP=1 outline          -> kept by the semi pass only
//   a=255  STP=0 body             -> kept by the opaque pass only
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D range_tex : filter_nearest, repeat_disable, hint_default_black;
uniform sampler2D range_palette : filter_nearest, hint_default_transparent;
uniform int palette_row = 4;                              // BATTLE.BIN slot 4 (cursor)
uniform int palette_count = 9;                            // RANGETILE.palette.tga height
uniform vec2 cursor_uv_offset = vec2(0.2578125, 0.5);     // (66, 128) / 256
uniform vec2 cursor_uv_size = vec2(0.05078125, 0.09375);  // (13, 24) / 256
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Linearize the sRGB-encoded CLUT for Forward+ display — matches the overlay
// and particle-opaque shaders that sample the SAME raw-imported palette.
uniform bool srgb_to_linear = true;
// PAR (ADR-0036/0044): shared pixel_aspect anchor (the cursor tracks the PAR-stretched
// map like every sprite) + the CURSOR-taxonomy billboard-WIDTH stretch
// psx_cursor_stretch (1.0 = native art; scrubbed in the Display debug panel).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"
#include "res://addons/exmateria_platform/display_port/psx_sprite_stretch.gdshaderinc"

// Camera-facing billboard — the SAME function unit.gdshader uses, so the cursor
// faces the screen like every other sprite in the game: replace the model
// rotation with the camera axes, keep the world translation, re-apply the
// original mesh scale (so cursor_scale / bob still drive size + position).
void billboard(inout mat4 mv, in mat4 view, in mat4 inv_view, in mat4 model, inout mat3 mv_normal) {
	mv = view * mat4(inv_view[0], inv_view[1], inv_view[2], model[3]);
	mv = mv * mat4(
		vec4(length(model[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(model[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(model[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	mv_normal = mat3(mv);
}

void vertex() {
	billboard(MODELVIEW_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX, MODELVIEW_NORMAL_MATRIX);

	// OT depth: per-object path from the world anchor (origin), TILE_OVERLAY
	// mode (7) so the floating cursor sorts in front of the tile + range tiles.
	// (Per-object like units — CUSTOM0-through-MODELVIEW is invalid once the
	// billboard rebuilds MODELVIEW.)
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, 7);

	// PAR (ADR-0044): anchor tracks the map via the shared pixel_aspect (Pattern 2,
	// like units); the billboard offset stretches by the CURSOR width multiplier
	// psx_cursor_stretch (1.0 = native art).
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, psx_cursor_stretch);
}

// Sample this fragment's cursor palette color. Returns the (gamma-corrected,
// tinted) rgb in .rgb and the raw palette STP alpha (0.0 / ~0.5 / 1.0) in .a so
// each pass can gate on the STP bit. idx 0's palette alpha is already 0.
vec4 cursor_sample(vec2 frag_uv) {
	vec2 atlas_uv = cursor_uv_offset + frag_uv * cursor_uv_size;
	float gray = texture(range_tex, atlas_uv).r;
	int idx = int(round(gray * 255.0 / 17.0));
	float pu = (float(idx) + 0.5) / 16.0;
	float pv = (float(palette_row) + 0.5) / float(palette_count);
	vec4 c = texture(range_palette, vec2(pu, pv));
	vec3 rgb = srgb_to_linear ? pow(c.rgb, vec3(2.2)) : c.rgb;
	return vec4(rgb * tint.rgb, c.a);
}
