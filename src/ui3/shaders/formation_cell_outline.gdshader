shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Placeholder 1px cell-outline for the FORMATION grid skeleton (#171): draws only
// the perimeter of a cell so the 2x4 grid placement can be A/B'd against t04.png
// before the cells carry real contents (body sprite / orb / gold box). Replaced/
// hidden once those land — it is scaffolding, not shipped chrome.

uniform vec2 size_px = vec2(56.0, 48.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 0.4, 0.7);
uniform float border_px = 1.0;

void fragment() {
	vec2 p = UV * size_px;
	bool edge = p.x < border_px || p.x > size_px.x - border_px
		|| p.y < border_px || p.y > size_px.y - border_px;
	if (!edge) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
