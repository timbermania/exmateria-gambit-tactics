shader_type spatial;
// NATIVE-BLEND twin of effect_fold_add — the "render-layer OFF" comparison side (#7916 demo). One word
// apart: no `compositor_layer`, so the engine renders this IN-SCENE and Godot blends it into the
// Forward+ LINEAR HDR buffer (muddy / unclamped) instead of the display-space fold scratch (clamped).
// Body + rationale in effect_particle_fold.gdshaderinc. ADR-0191 dec. 6.
// compositor-exempt: off-fork-fallback effect_fold_add.gdshader — the deliberate NOT-routed half of a routed/not-routed PAIR (#7916).
// This shader exists ONLY to render in-scene: it is `effect_fold_add` minus `compositor_layer`,
// selected when native_blend = true so the muddy native-blend result can be compared against
// the display-space fold. Routing it would delete the comparison. ADR-0147 dec. 7.
// display-space: folds-on-fork effect_fold_add.gdshader
// (the deliberate NOT-routed half of the #7916 comparison pair; production folds.) PSX blends in DISPLAY space and this in-scene
// file blends in LINEAR — correct only because it is the off-fork path.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

#define EFFECT_STP_ALPHA 1.0
#include "res://addons/exmateria_effects/render/effect_particle_fold.gdshaderinc"
