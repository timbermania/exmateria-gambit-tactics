shader_type spatial;
// {78} Display Conditions — the results text and the gil reel. Both draw SOLID: the
// reel's cells are GP0 0x2C POLY_FT4, which is not the semi-transparent opcode, and
// the glyph quads read solid in ss4/ss5 even though §4.2 decodes their packets as
// 0x3E (PSX gates semi-transparency per texel on the CLUT entry's STP bit, and one
// of CLUT 0x3F9A's sixteen entries carries it). blend_mix does not
// accumulate-saturate, so this pass is Forward+-safe as it stands and carries no
// routing obligation — only the banner's add/sub passes have one.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

#include "res://assets/shaders/results_screen.gdshaderinc"

void fragment() {
	vec4 t = texture(sheet, UV);
	ALBEDO = pow(psx_modulate(t.rgb, COLOR.rgb), vec3(PSX_OUTPUT_GAMMA));
	ALPHA = t.a * src_alpha;
}
