shader_type spatial;
// Monomorphic tile-cursor fold — SUBTRACTIVE (ABR10), the shipped default (cursor.blend_mode = 2).
// Body + axes in cursor_fold.gdshaderinc; this wrapper only fixes the blend. ADR-0074 ④c.
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://addons/exmateria_battlefield/cursor/cursor_fold.gdshaderinc"
