shader_type spatial;
// {76} Dark Screen — the IN-SCENE twin, worn off-fork. Body + rationale in
// darkscreen_mosaic.gdshaderinc; this file is the blend line.
// blend_mix does not accumulate-saturate, so this pass carries no compositor-routing
// obligation of its own — it folds because the {78} banner it sits under must.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

#include "res://assets/shaders/darkscreen_mosaic.gdshaderinc"
