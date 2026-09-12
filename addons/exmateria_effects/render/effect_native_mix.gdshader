shader_type spatial;
// NATIVE-BLEND twin of effect_fold_mix — the "render-layer OFF" comparison side (50/50 mix). One word
// apart: no `compositor_layer`, so the engine renders this IN-SCENE and mixes in the Forward+ LINEAR
// HDR buffer (muddy / unclamped) instead of the display-space fold scratch (clamped). Body + rationale
// in effect_particle_fold.gdshaderinc. blend_mix is not add/sub, so it needs no compositor-exempt
// marker — check_compositor_routing.py inventories it rather than scoring it. ADR-0191 dec. 6.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

#define EFFECT_STP_ALPHA 0.5
#include "res://addons/exmateria_effects/render/effect_particle_fold.gdshaderinc"
