shader_type spatial;
// Monomorphic tile-cursor fold — ADDITIVE (ABR01, cursor.blend_mode = 1; also the ABR11 add25 mode,
// selected as this material with level_scale = 0.25). Body + axes in cursor_fold.gdshaderinc. ADR-0074 ④c.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://addons/exmateria_battlefield/cursor/cursor_fold.gdshaderinc"
