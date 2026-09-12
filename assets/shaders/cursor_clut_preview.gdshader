shader_type canvas_item;
// Cursor CLUT preview shader. Samples the 4bpp-indexed RANGETILE sheet (red
// channel = palette_index * 17, written by parse_range_tiles.py) and looks
// up the color in a multi-row palette texture. The row selector lets a test
// scene cycle through every CLUT plausible for the cursor on tpage 0x1F —
// see tools/parse_cursor_clut_candidates.py for the row layout.
render_mode unshaded;

uniform sampler2D indexed_tex : filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform int palette_row : hint_range(0, 30) = 0;
uniform int palette_count = 31;

void fragment() {
	float gray = texture(indexed_tex, UV).r;
	int idx = int(round(gray * 255.0 / 17.0));
	float pu = (float(idx) + 0.5) / 16.0;
	float pv = (float(palette_row) + 0.5) / float(palette_count);
	vec4 c = texture(palette_tex, vec2(pu, pv));
	if (idx == 0) {
		discard;
	}
	COLOR = c;
}
