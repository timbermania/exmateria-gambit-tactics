# probe_shaders

Reference-only copies of the retired `effect_particle_mode0..3.gdshader` blend-mode
shaders. These were production render carriers until **#227** collapsed the
`EffectMultiMeshPool` slot to a single opaque MultiMesh and moved the transparent
fold into the display-space compositor.

**Orphaned as of #228 Phase 3 (2026-07-29):** their only consumers — the
`probe_combat_*` validation probes — were deleted with the raw-RD GLSL compositor
(`CombatDisplaySpaceComposite`). Nothing loads these four shaders any more. Per the
original note (below), this directory should be deleted in a follow-up sweep; it is
left in place here so the retirement commit stays focused on the compositor itself.

They still `#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"` (shared
with the production opaque shader, which stays in `assets/`) — deleting the dir is
harmless to that include.
