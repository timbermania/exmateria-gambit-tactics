shader_type spatial;
// PSX ABE off = OPAQUE. The tile draws solid (no framebuffer blend) — this is the
// red range tile, which the emulator shows fully opaque, cycling its CLUT shades
// (dark<->bright red) with no transparency. The transparent slot (index 0, c.a==0)
// is discarded so the tile's diamond shape still shows the terrain around it.
// depth_draw_never: depth-TEST only (see tile_overlay_mode0), so overlapping tiles
// don't occlude each other.
// cull_disabled (NOT cull_back): the highlight is a flat decal quad built from the
// tile's vertices with fixed indices, so its winding depends on the map parser's
// vertex order / handedness. A re-parse that flips that winding made cull_back
// cull the whole quad (the active-cursor tile vanished). A flat overlay has no
// meaningful back face, so never cull it — keeps it visible under any winding.
render_mode depth_draw_never, cull_disabled, unshaded;

#include "res://addons/exmateria_battlefield/overlay/tile_overlay.gdshaderinc"

void fragment() {
	vec4 c = tile_overlay_color(UV, TIME);
	if (c.a < 0.5) {
		discard;  // transparent CLUT slot -> show terrain, not opaque black
	}
	ALBEDO = c.rgb;
	if (!debug_no_psx) {
		DEPTH = ot_computed_depth;
	}
}
