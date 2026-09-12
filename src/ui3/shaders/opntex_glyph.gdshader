shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// OPNTEX1 title-menu glyph (NEW GAME / CONTINUE / TUTORIAL / SOUND /
// © 1997/1998 SQUARE). Same indexed-bitmap-through-CLUT pattern as
// vitals_sprite.gdshader (#119) — different transparent semantics so it
// lives in its own file: vitals' CLUTs hard-code idx 0 as the transparent
// key, but OPNTEX1 actually uses idx 0 as the body of every menu letter,
// and discrimination happens entirely through the CLUT's alpha channel
// (parse_opntex.py encodes PSX semi-trans semantics: word==0x0000 → a=0,
// STP=1 → a=128, STP=0 → a=255). The default blend_mix render_mode then
// reproduces PSX SPRT semi-trans mode 0 (B/2 + F/2) at ALPHA=0.5 and
// opaque rendering at ALPHA=1.0 in a single shader.

uniform sampler2D index_atlas : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;  // 16x1 CLUT row

// Source cell in atlas px: (x, y, w, h). Each menu item names its own rect
// from tools/parse_opntex.py's opntex1_cells.json.
uniform vec4 cell = vec4(0.0, 0.0, 54.0, 10.0);
uniform vec2 atlas_size = vec2(256.0, 256.0);

void fragment() {
	vec2 px = cell.xy + UV * cell.zw;
	vec2 texel = (floor(px) + 0.5) / atlas_size;
	int idx = int(floor(texture(index_atlas, texel).r * 15.0 + 0.5));
	vec4 c = texture(palette_tex, vec2((float(idx) + 0.5) / 16.0, 0.5));
	if (c.a < 0.01) {
		discard;
	}
	// pow(.,2.2) to match the rest of ui3 (ui_font_char, vitals_sprite) —
	// keeps the cream/navy at the same perceptual brightness as the
	// frame/font texels rendered alongside.
	ALBEDO = pow(c.rgb, vec3(2.2));
	ALPHA = c.a;
}
