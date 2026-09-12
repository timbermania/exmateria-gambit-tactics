# Particle draw order: three-level hierarchy via Godot-native mechanisms; CPU sort retired (extends ADR-0009)

## Status

Proposed (2026-06-03) — **partially superseded 2026-07** by the display-space
compositor (ADR-0009 dec. 6, tickets #207–221).

Extends [ADR-0009](0009-ordering-table-depth-is-one-model.md): preserves its
one-OT-model and `psx_ot_depth()` seam unchanged. Completes the particle-renderer
migration the per-shader pass of ADR-0009 (commit `95448765`) left half-done.

> **Status note (2026-07).** L2/L3 (frame-stack `sorting_offset`, pass-split via
> `render_mode`) still describe opaque and non-compositor draws. But L1's
> reliance on **Godot's native transparent-queue sort** for the effect blend
> modes (add/sub/mix/add25) is **superseded**: those prims are now depth-ordered
> explicitly by `OTDepthPrimOrder` and folded by the engine-fold compositor
> (`EngineFoldCompositor`, which retired the raw-GLSL `CombatDisplaySpaceComposite`
> in #228 Phase 3), which owns the blend sequence and does its own
> `GREATER_OR_EQUAL` occlusion test against the opaque depth buffer. The #212
> work also showed the sort key for that fold is **linear view-space Z**
> (`DepthMode.ot_order_z`), not reversed-Z NDC. Now that the compositor migration
> has settled onto the engine-fold (Forward+ 4.8 fork), this ADR stands as
> **accepted-as-amended**: native sort still governs opaque/non-compositor draws.

## Context (before this decision)

ADR-0009 unified shader-side depth: every battle primitive writes `DEPTH` via
`psx_ot_depth(point, mode)`, with the calibration in `DepthMode.gd`. The
particle-shader migration commit `95448765` replaced the un-anchored
`PULL_FORWARD_8 = 1.0` / `_16 = 2.5` literals with the ROM-anchored
`bucket_count × UNITS_PER_OT_BUCKET`. That commit changed shaders only.

`EffectParticleRenderer` retained a CPU sort that pre-dates ADR-0009. It
encodes four bands into one float comparator:

- `OPAQUE_PASS_OFFSET` vs `SEMI_TRANS_PASS_OFFSET` (opaque-before-semi-trans pass split)
- `p.channel_index * 1000.0` (designated inter-particle Z-order)
- `DEPTH_MODE_Z_OFFSETS[depth_mode]` (per-mode bias, parallel to the shader bias)
- `frame_idx * Z_EPSILON` (intra-particle frame stacking)

After running the comparator, particles are assigned to consecutive
`MeshInstance3D` pool slots, and Godot draws meshes in pool/scene-tree order at
similar depths — so pool-slot order is the load-bearing draw-order mechanism,
implicitly.

Investigation in the grilling session that produced this ADR found:

1. **`depth_mode` band duplicates the shader.** Since `95448765` the shader
   handles the per-mode bias via `psx_ot_depth(mode)`. The CPU array
   `DEPTH_MODE_Z_OFFSETS` (`-0.05`, `-0.15`, `0.5`, `-0.1`, `-0.1`) is a
   second source of magnitudes that doesn't even agree with the shader's
   bucket math (`8 × 0.19 = 1.52` ≠ `-0.05`). It survived only because the
   sort is band-ordinal — magnitudes are arbitrary subject to rank
   preservation.

2. **`channel_index` is a lane identifier, not a Z-order key.** Grepping the
   ROM research notes (`research/wiki_articles/`, `research/key_documents/`)
   for any FFT mechanism that designates channel as a sort key returned
   zero hits. `TimelineData.gd` (`channel_index: int = 0  # 0-4 for particle
   channels`), the parser (`channel_idx` as a parser-side counter), and the
   FEDS sound-track path all use `channel_index` as an emitter-lane index.
   The "particle Z-order key" framing in `Particle.gd:31`,
   `ActiveEmitter.gd:22`, and (before this ADR) `CONTEXT.md`'s **Channel**
   entry was an inherited misinterpretation. FFT's actual model: all
   particles compete in one OT; intra-bucket ordering is OT linked-list
   insertion order, a side effect of emitter iteration, not a deliberate
   key.
   > **Superseded (2026-07), for the compositor path.** "Not a deliberate key"
   > was right about `channel_index` but wrong to generalize to *all* intra-bucket
   > order. #212/#214 established that the OT linked-list insertion order **is**
   > load-bearing and IS reproduced deliberately: within a depth bucket the
   > **newest-spawned prim folds on top** (particle **age** tie-break, mirroring
   > PSX's double-head-insert `AddPrim` @ `0x80023bb4`). For DEMI (E046), where
   > every prim shares one bucket, age is the *entire* order. The compositor
   > implements this as `OTDepthPrimOrder`'s secondary sort pass. So: insertion
   > order is not *arbitrary* — it is a faithful, ROM-grounded contract. See the
   > ADR-0009 dec. 7 (within-bucket order is the age tie-break).

3. **`frame_idx` band is real, but it isn't a depth axis.** Per the ROM wiki
   (`research/wiki_articles/effect_frames_section.txt` lines 240-242):
   *"When a frameset contains multiple frames, ALL frames are rendered
   simultaneously for the same particle. The frames overlap, creating
   layered visual effects."* And lines 547-555: depth_mode is read from the
   **animation sequence opcode**, not from individual frames — so every
   frame in a frameset shares one OT bucket. The frame iteration order is
   the **same-bucket stack order** used by the PSX OT linked-list iteration
   for blend composition. It matters for non-commutative blend modes (MIX,
   SUB, ADD25); ADD (mode 1, the most common) is commutative. CONTEXT.md
   names the per-particle multi-quad composite **Frameset**.

4. **The pass-split band is real and is already Godot's job.**
   `effect_particle_opaque.gdshader` uses `render_mode … depth_draw_opaque`
   (opaque queue); `effect_particle_mode{0..3}.gdshader` use
   `render_mode … blend_mix/_add/_sub` (transparent queue). Godot Forward+
   draws opaque queue first, then transparent. The CPU sort's
   `OPAQUE_PASS_OFFSET` vs `SEMI_TRANS_PASS_OFFSET` is redundant with the
   pipeline.

The cleaner mental model is a **three-level hierarchy** with one mechanism
per level. The CPU sort fuses all three plus a fourth (the redundant
`depth_mode` band) into one float; deleting it and using the native
mechanisms collapses ~90 LoC of buffer machinery and removes the
pool-slot-order-as-draw-order implicit contract.

## Decision

**Three-level particle draw-order hierarchy, each level on a different Godot
mechanism:**

- **L1 — inter-particle macro depth.** Shader `DEPTH` via `psx_ot_depth(point,
  mode)`. Already in place per ADR-0009. The only place depth_mode lives.
  Covers map, units, particles, overlays, traps in one axis.
- **L2 — intra-particle frame stack.** `MeshInstance3D.sorting_offset =
  float(frame_idx) * 0.0001` per frame mesh. Godot's transparent queue sorts
  by `render_priority` → `sorting_offset` → AABB distance; with shared
  `render_priority` (default 0) across particles, `sorting_offset` is the
  deciding tiebreak. Encodes the **Frameset** stack order (the data-specified
  iteration order) deterministically.
- **L3 — intra-particle pass split.** Shader `render_mode` declarations
  (`depth_draw_opaque` vs `blend_*`) place opaque draws on the opaque queue
  and semi-trans draws on the transparent queue. Godot's pipeline draws the
  opaque queue first (writing depth), then the transparent queue (reading
  depth). No code change — already correct.

**Delete the CPU sort.** Remove `DEPTH_MODE_Z_OFFSETS`, `Z_EPSILON` (in this
file), `OPAQUE_PASS_OFFSET` / `SEMI_TRANS_PASS_OFFSET`, all `_sort_*` buffers,
`_ensure_sort_capacity`, `_setup_sort_buffers`'s buffer-resize block, the
two-phase build-sort loop, and the `indices.sort_custom(...)` callable.
Replace with a single direct loop that iterates particles in build order,
iterates frames in `for fi in range(frames.size())` order, and sets
`mesh.sorting_offset = float(fi) * 0.0001` per frame mesh.

The pool-slot-order mechanism is no longer load-bearing for draw order; the
pool's only job is mesh allocation (with growth).

**`channel_index` becomes purely a lane identifier in render code.** No
particle-renderer code reads `channel_index` for sort purposes after this ADR.
`Particle.gd` and `ActiveEmitter.gd` comments are corrected; `CONTEXT.md`'s
**Channel** entry was already updated in the grilling session that produced
this ADR.

## Considered options

- **Encode all three levels into shader `DEPTH`** (a per-level epsilon stack
  in `psx_ot_depth`). Rejected: Godot Forward+ does **not** sort transparent
  meshes by fragment `DEPTH`. It sorts by `render_priority` → `sorting_offset`
  → AABB center distance. Fragment `DEPTH` only drives the depth-buffer test,
  not transparent draw order. Encoding the hierarchy into `DEPTH` would
  change occlusion correctness against opaque pixels (incorrectly) without
  affecting the transparent-sort order it was meant to fix.

- **Encode the hierarchy into `render_priority`** (an int packed as
  `channel * 16 + frame_idx` or similar). Rejected on two counts: the int
  range is narrow (`[0, 127]`) and the L1 magnitude (per-particle macro
  depth) doesn't fit at all — it's a continuous world-distance quantity, not
  a packed band. Once L1 falls out, only L2 (frame_idx, ≤ ~10 in practice)
  is left, and a per-frame `render_priority = fi` would work — but
  `sorting_offset` is the documented Godot-4 mechanism for sub-priority
  ordering and avoids any cross-particle priority-collision concern.

- **Keep the CPU sort with the magnitudes rewritten as integer ranks**
  (`(pass, channel, blend_rank, frame_idx)` lexicographic). Rejected after
  finding (a) `channel` isn't a designated key, (b) `blend_rank` /
  `depth_mode` band is shader-redundant, (c) pass split is engine-redundant.
  Once those drop, only `frame_idx` remains — and at one band, the entire
  CPU sort apparatus is overhead.

- **Punt L2 entirely** (trust submission order; don't set `sorting_offset`).
  Rejected as risky: Godot 4 Forward+ transparent-queue tiebreak at
  identical `sorting_offset` is not a documented stability guarantee. For
  the rare non-commutative blend mode with intra-particle frame overlap,
  the pixel output could vary between point releases. `sorting_offset =
  float(fi) * 0.0001` is one line per draw to be deterministic.

## Consequences

- `EffectParticleRenderer` loses ~90 LoC (sort buffers, ensure_sort_capacity,
  build-sort loop). Gains a single direct render loop plus a per-frame-mesh
  `sorting_offset` write. The pool-slot-as-draw-order implicit contract is
  removed; pool slots are pure allocation.

- The `_setup_sort_buffers` function is renamed (or its non-buffer half — the
  per-emitter `align_to_velocity` / `color_curve` cache — moves to a new name)
  so it remains called from `initialize()` for the cache, without resizing
  buffers that no longer exist.

- `Particle.channel_index` and `ActiveEmitter.channel_index` survive (used by
  the timeline for lane identification, callbacks, debug logging) but no
  longer feed render order. Comments calling them "for Z-ordering" are
  corrected to "timeline lane identifier."

- `DepthMode` becomes the single GDScript source of truth for both per-mode
  depth bias **and** any future CPU-side projection needs — but for L2 we
  use a render-side constant (`0.0001`) that has no FFT analogue (it's a
  Godot-sort tiebreak), so it stays in `EffectParticleRenderer` rather than
  in `DepthMode.gd`. If a second consumer ever needs the same tiebreak,
  promote then.

- Behavior verification gate before merging: `DepthDebugScene` + headful
  replays of E317 (Choco Ball, ADR-0009's regression effect), E019 (Fire 4,
  78/84 multi-frame framesets via same-UV-offset-vertices technique), and
  one non-ADD-blend effect from the 6/84 different-UV cases. Compare
  visually to current main. If a non-ADD case visibly regresses, fall back
  to also offsetting the semi-trans mesh's `sorting_offset` by half a step
  above the opaque (`+ 0.00005`) so semi-trans-of-frame-N composites above
  the prior frame's semi-trans.

- Follow-ups (separate work, ADR-0009 pending items): verify migration
  status of `effect_callback_additive` / `trap_charge_line` shaders; sweep
  surviving scattered constants (`TrapEffect.debug_depth_bias`, unit
  `depth_bias`, overlay `+0.0001`, particle `world_bias` literals).

- Not part of `bootstrap_assets.sh` — hand-authored runtime code.
