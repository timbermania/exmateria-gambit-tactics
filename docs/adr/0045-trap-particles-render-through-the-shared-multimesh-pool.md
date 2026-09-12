# Trap particles render through the shared MultiMesh pool, with palette row per-instance

ADR-0040 rewrote `EffectParticleRenderer` to render E### effect particles by
borrowing a 5-`MultiMeshInstance3D` slot (one per render_mode) from a new
`EffectMultiMeshPool`, packing per-particle-frame state into the instance
buffers instead of writing ~7 shader uniforms per particle to individual
`MeshInstance3D` nodes. That merge migrated the **shared** vertex shader,
`effect_particle_stp.gdshaderinc`, to the MultiMesh convention: corners +
depth_mode are read from `MODEL_MATRIX` basis cells and the UV rect from
`INSTANCE_CUSTOM`, and the old per-mesh `corner_*` / `uv_rect_data` /
`depth_mode` uniforms were deleted.

`TrapEffect` (Knight Break, hit clouds, the charge VFX) was **not** migrated —
it kept rendering one borrowed per-`MeshInstance3D` mesh per particle from a
parallel `EffectMeshPool` autoload, driving the now-deleted uniforms. Because it
`#include`s the same shared shader, every trap quad read garbage corners from an
ordinary `MODEL_MATRIX` and a zero UV rect from the absent `INSTANCE_CUSTOM`,
collapsing to a degenerate invisible point. (`color_modulate` had likewise gone
dead — the shader now expects `COLOR.rgb`.) The merge kept `EffectMeshPool`
"alongside the new pool" for trap, but the shared shader it depended on was
already gone — so trap particles silently disappeared.

The one obstacle to migrating trap onto the MultiMesh path is that trap needs a
**per-particle `palette_row`** (the ADR-0022 indexed-TRAP1 palette lookup
selects a different palette per emitter/element), whereas the E### path uses one
material per slot — a uniform can't vary per instance. The E### instance buffer
(basis = 8 corners + depth_mode, origin = world pos, `INSTANCE_CUSTOM` = uv_rect,
`COLOR` = rgb + semi_trans_on) is otherwise fully packed.

## Status

Accepted (2026-06-15). Completes the ADR-0039/0040 migration for the trap
taxonomy and retires `EffectMeshPool`. The E### MultiMesh path and the
`effect_particle_*` shaders' non-palette behavior are unchanged.

## Decision

**`TrapEffect` renders through `EffectMultiMeshPool` like `EffectParticleRenderer`,
and `palette_row` becomes per-instance, carried in `COLOR.a`.**

- **Trap borrows one slot and writes only the mode1 (additive) MultiMesh.** Trap
  particles are always the additive STP pass, so the slot's other four
  render-mode MultiMeshes stay at `visible_instance_count = 0`. The slot is
  borrowed lazily on first render (covers override-mode callers like
  `TrapOrbitalEffect`, which don't go through `play_at`).
- **Per-instance packing mirrors `EffectParticleRenderer._write_instance`:**
  corners + `depth_mode` in the `MODEL_MATRIX` basis, world position in the
  origin, uv_rect (normalized, texel-centered) in `INSTANCE_CUSTOM`,
  `color_modulate.rgb` in `COLOR.rgb` — plus `palette_row / 15.0` in `COLOR.a`.
- **`palette_row` moves from a shared uniform to `COLOR.a`,** recovered in the
  vertex shader as a `v_palette_row` varying (`COLOR.a * 15.0`) and used by
  `stp_sample`. It is only read inside the `if (use_palette)` branch, which only
  trap enables — so the RGBA-baked E### path (which packs `semi_trans_on` into
  `COLOR.a`) is provably unaffected.
- **`use_palette` is reset to `false` when the slot is released,** so the next
  borrower of that slot's mode1 material — which may bind an RGBA-baked
  `effect_texture` — does not accidentally palette-lookup it.
- **`EffectMeshPool` (autoload + script) is retired.** `TrapEffect` was its only
  consumer; `TrapChargeLineEffect` owns its own line `MeshInstance3D` and
  `TrapOrbitalEffect` drives `TrapEffect` in override mode, so neither used it.

## Considered options

- **Migrate trap to MultiMesh, palette_row in `COLOR.a` (chosen).** One render
  path and one shader convention for all particles; `EffectMeshPool` deleted.
  Pays a single per-instance channel (`COLOR.a`, free because trap's mode1
  fragment never reads alpha) and a shader varying gated behind `use_palette`.
- **Branch the shared shader (rejected).** Re-add the `corner_*` / `uv_rect_data`
  uniforms behind a `use_instance_corners` flag defaulting true. Smallest diff
  and zero risk to E###, but freezes two divergent particle conventions in one
  file forever and leaves `EffectMeshPool` (and its per-particle uniform-write
  cost — the very thing ADR-0040 removed) alive for trap.
- **Dedicated trap shader (rejected).** A `trap_particle_*` shader keeping the
  per-mesh uniform path. Isolates trap from the shared include but duplicates the
  STP + palette logic, and still keeps `EffectMeshPool`.
- **Group particles by palette into multiple slots (rejected).** Avoids touching
  the shader, but a slot is a 5-MM bundle, so N palettes per frame burns 4N
  unused MultiMeshes and N slot borrows — wasteful for the handful of palettes
  live at once.

## Consequences

- **`EffectMeshPool` autoload + `EffectMeshPool.gd` removed.** Only
  `EffectMultiMeshPool` remains.
- **Trap inherits the ADR-0040 draw-call win** (one MultiMesh draw for all trap
  particles in a frame vs. one `MeshInstance3D` draw each) and the ADR-0044
  `psx_fx_stretch` / PAR anchor + GTE/OT depth behavior, for free — it now runs
  the same shader and instance path as E### effects.
- **`COLOR.a` is overloaded by render mode:** `semi_trans_on` for the E###
  opaque pass, `palette_row / 15` for the trap mode1 pass. Safe because they are
  different shaders/passes and the palette read is `use_palette`-gated, but the
  channel is no longer free for a future per-instance flag without a similar gate.
- **`color_modulate` is restored** for trap (it had silently become a no-op
  uniform after the ADR-0040 shader expected `COLOR.rgb`).
