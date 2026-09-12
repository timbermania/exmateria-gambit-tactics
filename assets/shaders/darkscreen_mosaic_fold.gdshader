shader_type spatial;
// {76} Dark Screen — the ENGINE-FOLD twin. Body + rationale in
// darkscreen_mosaic.gdshaderinc; this file is the blend line plus the layer.
//
// It exists for ORDER, not for colour: the dim is a half blend and would composite the
// same either side of the resolve, but {78}'s banner is add/sub and MUST fold, and a
// folded banner under an in-scene dim renders with the fog painted over it. Both in the
// fold, `Fold.add`'s order_z puts the dim underneath, which is the PSX's own order.
//
// depth_test_disabled for the same reason the {78} twins carry it: the fold pass binds
// the scene depth, and a full-screen NDC quad's own clip z fails that test.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, compositor_layer;
// psx-prim: untextured — ALBEDO = color direct (PSX POLY_F4 flat: no texel, no >>7). ADR-0074 color-math clause.

#include "res://assets/shaders/darkscreen_mosaic.gdshaderinc"
