# Particle renderer batches per-effect via MultiMesh; L2 frame-stack order rides instance-buffer order (extends ADR-0015)

## Status

Proposed (2026-06-13)

Extends [ADR-0015](0015-particle-draw-order-uses-godot-native-sort.md). ADR-0015
retired the CPU sort and pinned L1/L2/L3 on three different Godot mechanisms;
this ADR preserves **L1** (`psx_ot_depth` in the fragment shader) and **L3**
(`render_mode` queue split) unchanged, and migrates **L2** from per-
`MeshInstance3D` `sorting_offset` to **instance-buffer write order** inside a
`MultiMesh`. The motivation is performance: the per-effect draw-call count
captured during 4v4 combat with effects on screen (300-580 draws on render-
heavy spike frames, 50-80 draws per active combat-visual) drives a CPU spike
to 50-80 ms frame times, well above the 16.67 ms 60 fps target.

## Context (before this decision)

After ADR-0015 landed (2026-06-03) the renderer iterates particles in build
order and submits two `MeshInstance3D` draws per particle frame (opaque +
conditional semi-trans). Each draw carries one transform write, one shader-
pointer swap, six to seven `set_shader_parameter` writes (corners, UV rect,
depth_mode, color modulate), and a `sorting_offset` (ADR-0015's L2). With
~30 particles per active effect × 2 passes × 7-10 effects on screen, that is
~600 draw calls and 2,500-8,400 uniform writes per frame.

The `EffectMeshPool` autoload (pre-warmed 8192 `MeshInstance3D` nodes,
borrowed on effect spawn) eliminated the `add_child` spawn spike. But draw-
call submission remains O(particles × passes × effects), and each
`MeshInstance3D` with per-instance shader parameters is a distinct draw call
(Godot cannot batch when uniforms differ).

The session-2026-06-13 perf monitor data established three things:
- 51-53 fps mean across 60s trials, 8 ms sustained gap to 60 fps target.
- Render-heavy spikes 50-80 ms with 300-580 draw calls, scaling linearly with
  `combat_visuals` group size.
- The dominant cost the engine's `Process` counter captures during spikes
  tracks draw-call submission, not the GDScript build-loop time
  (`[PARTICLE_PERF]`'s timer window closes before draws actually submit).

The file header rationale on `EffectParticleRenderer.gd:5-9` ("`gl_compatibility`
mode GLES3 can't use `MultiMesh`/`INSTANCE_CUSTOM` because `floatBitsToInt`
is unavailable") is **stale on two counts**:
1. The project is `Forward Plus` (Vulkan) per `project.godot:19` — GLES3
   compatibility is not a constraint.
2. `floatBitsToInt` is only needed when packing integer per-instance data;
   every per-instance value in this renderer (transforms, UV corners, depth_mode
   as a small int promotable to float) is already float-representable, so the
   constraint would not have applied regardless.

## Decision

### Decision 1 — One `EffectMultiMeshPool` autoload, lending 5 `MultiMeshInstance3D` nodes per effect

**One `EffectMultiMeshPool` autoload, lending 5 `MultiMeshInstance3D` nodes per
effect.** Each effect's slot set covers the existing five shaders:

- 1 opaque-pass `MultiMesh` — `effect_particle_opaque.gdshader` (`render_mode
  depth_draw_opaque`).
- 4 semi-trans-pass `MultiMesh`es — one per blend mode, using the existing
  `effect_particle_mode{0..3}.gdshader` files (`render_mode blend_mix /
  blend_add / blend_sub / blend_add` per mode).

`MultiMesh.instance_count` is grown on demand (mirroring today's
`_grow_pool`). The 5 materials each carry `effect_texture` and `texture_size`
once at `initialize` — no per-frame texture set.

### Decision 2 — The per-frame loop writes instance buffers, not shader parameters

Per-frame loop walks particles in build order; for each frame of each
particle, slot the instance into the `MultiMesh` matching its (pass,
blend_mode) tuple:

```gdscript
# Today (per frame):
mesh.global_transform = ...
mat.shader = _opaque_shader        # or _blend_shaders[mode]
mat.set_shader_parameter("corner_tl", ...)
# ... 5 more set_shader_parameter calls

# After this ADR (per frame):
multimesh.set_instance_transform(slot, transform_with_world_pos)
multimesh.set_instance_custom_data(slot, packed_vec4_with_uv_corners)
# Possibly a second INSTANCE_CUSTOM via VS-side reinterpretation if one vec4
# is too tight; corners + uv_rect total 12 floats. Likely split as two vec4s
# delivered via custom_aabb / packed-uvec encoding tricks, or via a small
# per-instance texture if needed. Shape settled at implementation time.
```

### Decision 3 — L1 unchanged

**L1 unchanged.** Fragment shader still writes `DEPTH = psx_ot_depth(point,
depth_mode)`. Per-instance world position reaches the fragment shader via
`MODEL_MATRIX` (Godot threads it through transparently for `MultiMesh`
instances); `point` is derived from the per-instance origin as before. Each
instance writes its own DEPTH — inter-particle depth ordering is identical.

### Decision 4 — L3 unchanged in spirit

**L3 unchanged in spirit.** Each `MultiMesh`'s material has one shader, one
`render_mode`. The opaque `MultiMesh` lands on Forward+'s opaque queue; the
4 blend-mode `MultiMesh`es land on the transparent queue. Pipeline draws
opaque first, then transparent — same rule ADR-0015 named, just with one
batched draw per (effect × render_mode) instead of N draws per particle frame.

### Decision 5 — L2 migrates from `sorting_offset` to instance-buffer write order

**L2 migrates from `sorting_offset` to instance-buffer write order.** Today's
`mesh.sorting_offset = fi * 0.0001` is replaced by writing frame instances
into contiguous slots in `for fi in range(frames.size())` order. For ADD (the
commutative dominant case) order is irrelevant. For MIX / SUB / ADD25 with
multi-frame framesets, the per-particle frame stack is preserved because
buffer order **is** submission order — Godot does not reorder instances within
a `MultiMesh`. ADR-0015 explicitly rejected "punt L2 entirely" as risky
because Godot's tiebreak between identical-`sorting_offset` meshes is not a
documented stability guarantee; instance-buffer order is a stronger guarantee
than that tiebreak, so the protection ADR-0015 added survives.

### Decision 6 — Draw-call math

**Draw-call math.** 600 → `5 × N_effects` (50 at 10 effects on screen). ~10×
reduction. Sits well below the 300-580 draw-count seen on the spike frames
2026-06-13, so the (c) bottleneck is closed.

### Decision 7 — Pool shape survives

**Pool shape survives.** `EffectMeshPool`'s borrowed-index contract becomes
"borrow a 5-`MultiMeshInstance3D` set." `EffectInstance` calls
`borrow_multimesh_set()` instead of indirectly relying on the per-mesh borrow.
The class-name surface `EffectParticleRenderer` survives so `EffectInstance`
integration above it is unchanged.

### Decision 8 — File header rewritten

**File header rewritten.** `EffectParticleRenderer.gd:5-9`'s GLES3 /
`floatBitsToInt` comment block is removed. The new header names MultiMesh +
Forward+ as the design context. Stale rationale does not stay in file headers
when the design moves.

## Considered options

- **One global texture atlas + 5 `MultiMesh`es scene-wide.** Draw calls drop
  to 5 total. Rejected for now: requires an offline atlas build, per-instance
  atlas-rect data via `INSTANCE_CUSTOM`, and the `(uv + 0.5) / texture_size`
  texel-center math has to thread atlas regions. The per-effect option already
  takes draws from 600 → 50, well below the spike floor — the further drop to
  5 is not load-bearing for the perf goal. Atlas is preserved as a future fold
  if `5 × N_effects` ever becomes the bottleneck.

- **Keep per-`MeshInstance3D` design; cut per-instance uniform writes by
  promoting per-frame state into a packed buffer the shader samples.** Rejected:
  addresses (b) GDScript loop cost but not (c) draw-call count. The perf
  signature (573 draws / 7 visuals on the spike frame captured 2026-06-13)
  names (c) as the load-bearing cost.

- **Stay with per-`MeshInstance3D`; accept the perf cost.** Rejected: 51-53 fps
  mean with sustained 8 ms gap to 60 fps target and 50-80 ms during-combat
  spikes is not acceptable for the game's playable target.

- **Encode the L2 frame-stack order via a per-`MultiMesh`-instance
  `sorting_offset` analogue (e.g. small Y-offset).** Rejected: there is no
  per-instance `sorting_offset` for `MultiMesh`, and faking it via Y-shift
  would interact with the L1 `psx_ot_depth` calculation. Instance-buffer order
  is the cleaner mechanism and stronger guarantee.

## Consequences

- `EffectParticleRenderer.gd` rewrites its per-particle loop. The borrowed-
  pool shape survives — `EffectMeshPool` becomes (or is replaced by)
  `EffectMultiMeshPool`, `_grow_pool` becomes `MultiMesh.instance_count`
  resize, and the per-mesh `material_override` shader-swap dance disappears
  (each MultiMesh's material is fixed at borrow time by its render_mode slot).

- The 5 effect-particle shaders gain per-instance plumbing: `MODEL_MATRIX`
  carries per-instance transform; `INSTANCE_CUSTOM` (one or two `vec4`s)
  carries the per-frame state today set via `set_shader_parameter` (corners,
  UV rect, depth_mode, color modulate). `psx_ot_depth(point, mode)` derives
  `point` from `MODEL_MATRIX * vec4(0,0,0,1)` and `mode` from the packed
  custom data instead of a uniform.

- ADR-0015's L2 mechanism (`sorting_offset = fi * 0.0001`) is **replaced**, not
  removed in spirit. The deterministic intra-particle frame-stack order
  ADR-0015 protected against Godot's undocumented `sorting_offset`-tiebreak
  stability is preserved by writing instances in iteration order into a buffer
  Godot has no opportunity to reorder.

- `Particle.channel_index` / `ActiveEmitter.channel_index` unchanged
  (ADR-0015 already clarified its lane-identifier role).

- `disabled_emitters` debug-time filter survives — per-emitter mute becomes
  "skip writing instances for those emitters" in the build loop; pool slots
  are just not advanced for skipped particles.

- Verification gate before merging:
  - Headful replay of E317 (Choco Ball — ADR-0009 / ADR-0015 regression
    effect), E019 (Fire 4 — 78 of 84 multi-frame framesets), and one
    MIX/SUB/ADD25 multi-frame frameset effect. Visual parity vs current main.
  - Perf monitor session over 60s 4v4 combat at seed 42. Acceptance vs the
    2026-06-13 baseline (mean 19.40 ms / 108 spikes / 573 peak draws):
    `draw_calls` peak < 100, spike count < 30, mean frame time < 17 ms.
  - If the 8 ms sustained gap to 60 fps survives the rewrite, it confirms the
    handoff's "separate finding" — `Unit._process` / animation tick / sound
    mixer — as the next investigation, untangled from the particle-draw cost.

- Follow-ups deferred:
  - Global texture atlas + 5 `MultiMesh`es scene-wide — only if `5 ×
    N_effects` becomes the bottleneck.
  - GDScript-side build-loop cost ((b)) — the rewrite makes its share of the
    frame budget directly measurable (the buffer-write call surface is
    smaller and more uniform than today's per-particle shader-parameter
    plumbing).
  - The `[PARTICLE_PERF]` self-log on `EffectParticleRenderer.gd:324-329` is
    rebracketed (or removed) to match the new loop shape; today's bracket is
    inherited from the per-mesh path.

- Not part of `bootstrap_assets.sh` — hand-authored runtime code.

## Amendment 1 — built and load-bearing while its Status still says *Proposed*; the five slots collapsed to one, and the method the ADR named by hand never existed

*Audited 2026-08-28 against the tree at `docs/adr-consolidation`. The Decision
paragraphs above were given `### Decision N` headings in the same pass — prose
untouched — so `ADR-0040 dec. N` citations resolve.*

The headline is the Status line. This ADR reads **Proposed (2026-06-13)**, but
it is built, and it is cited as settled by an *Accepted* ADR: ADR-0200 (accepted
2026-08-21) names "the 24-float ADR-0040 record layout" as the thing it is
deleting a batch payload in favour of, and ADR-0045's whole Context is "ADR-0040
rewrote `EffectParticleRenderer` … that merge migrated the shared vertex
shader". Two tests cite it (`tests/TrapUnifiedPublishTest.gd`,
`tests/UnifiedPrimStagerTest.gd`). The autoload it proposes is registered at
`project.godot:42`. Nothing about this document is still a proposal.

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | One `EffectMultiMeshPool` autoload lending **5** `MultiMeshInstance3D` per effect | autoload yes; **5 → 1** | `EffectMultiMeshPool.gd:2-23`: "each slot is now ONE MultiMeshInstance3D — RM_OPAQUE (canvas + depth), the only in-scene draw… The four RM_MODE0..3 blend-mode carriers were retired". The four named `effect_particle_mode{0..3}.gdshader` files do not exist; `assets/shaders/` has `effect_particle_opaque.gdshader` plus the `_stp` / `_fold` includes. `instance_count` growth holds (`INITIAL_INSTANCE_COUNT`/`GROWTH_INSTANCE_COUNT` = 32, `_ensure_capacity`). |
| 2 | The per-frame loop writes instance buffers, not shader parameters | holds; the shape settled differently | `EffectParticleRenderer.gd:363-366` writes `set_instance_transform` / `set_instance_custom_data` / `set_instance_color`. "Shape settled at implementation time" landed as: corners + `depth_mode` packed into the **`MODEL_MATRIX` basis** (`:326`), `INSTANCE_CUSTOM` = uv_rect only (`effect_particle_stp.gdshaderinc:83-84`), modulate + `semi_trans_on` in `COLOR` — not the "one or two vec4 `INSTANCE_CUSTOM`" the ADR guessed at. |
| 3 | L1 unchanged — `DEPTH = psx_ot_depth(point, depth_mode)` | rule holds, seam moved | The shared seam is now `psx_ot_depth(vec3 point, mat4 proj, mat4 to_view, int mode)` in `addons/exmateria_schema/compositing_key/psx_ot_depth.gdshaderinc` (four args, addon home — see ADR-0009's audit). `check_depth_shaders.py` is green over it. |
| 4 | L3 unchanged in spirit — opaque MM on the opaque queue, 4 blend MMs on the transparent queue | opaque half holds; transparent half is gone | Transparent prims never reach Godot's transparent queue: they are staged into the slot's unified 24-float SSBO and folded by the combat display-space compositor (`_publish_unified`, `EffectParticleRenderer.gd:387-393`). |
| 5 | L2 rides instance-buffer write order instead of `sorting_offset` | superseded a second time | `sorting_offset` is gone from `src/` (prose only, at `DepthMode.gd:45`, plus two tests and three `tools/probe_*.gd`). But plain submission order was itself replaced: `OTDepthPrimOrder.order()` depth-orders the staged prims far→near with same-direction runs collapsed, and `DepthMode.gd:45` records `render_layer_order` as `sorting_offset`'s actual successor. Submission order survives only as the **tie-break**. |
| 6 | Draw-call math 600 → `5 × N_effects` | wrong, in the good direction | `EffectParticleRenderer.gd:13-14`: "1 opaque MultiMesh per effect + the compositor's folded transparent passes". |
| 7 | Pool shape survives; `EffectInstance` calls `borrow_multimesh_set()` | class surface holds; **the named method never existed** | `borrow_multimesh_set` has zero hits repo-wide. The pool's API is `borrow_slot()` / `release_slot(idx)` / `get_multimesh(idx)` / `get_material(idx)` / `set_effect_texture(idx, tex)` / `set_palette_texture(idx, tex)`. `EffectParticleRenderer`'s `class_name` did survive, as promised. `EffectMeshPool` is fully gone — it survives as one word of prose in `EffectMultiMeshPool.gd:23`. |
| 8 | File header rewritten; the GLES3 / `floatBitsToInt` block removed | holds | Zero hits for `floatBitsToInt`, `GLES3`, or `gl_compatibility` anywhere under `src/effects/`. `EffectParticleRenderer.gd:3-14` names the pool, #227, and the compositor. |

The per-instance record also grew: the ADR reasons about ~20 floats; the shipped
record is **24 floats** "since slice C" (`EffectMultiMeshPool.gd:233`, and the
same number in `UnifiedPrimStager.gd:16`, `OTDepthPrimOrder.gd:69`,
`TrapEffect.gd:114`). ADR-0200 cites that 24-float layout by this ADR's number,
so the record layout is the part of ADR-0040 that downstream documents actually
address.

### The one deferred follow-up that did not land, and what it now prints

Consequences deferred three follow-ups. The third — "the `[PARTICLE_PERF]`
self-log on `EffectParticleRenderer.gd:324-329` is rebracketed (or removed) to
match the new loop shape" — did **not** land. The log moved (it is now at
`:249-254`) but still prints `opaque=%d mode0=%d mode1=%d mode2=%d mode3=%d`
from `_used_counts[0..4]`. Those four mode counters are reset to `0` at
`:190-191` and incremented **only inside `if rm == _RM_OPAQUE`** (`:358-360`),
so since #227/slice D they are structurally always zero. Every
`[PARTICLE_PERF]` line the game can emit reads `mode0=0 mode1=0 mode2=0
mode3=0`.

`get_active_count()` (`:403-408`) has the same shape — its docstring still says
"total active instance count across all 5 render_modes" while it sums the
opaque count plus four permanent zeros. It has **zero callers**:
`ParticleSubsystem.gd:377/626/645` and `tests/ChildSpawnSuppressionTest.gd` all
call `ParticlePool.get_active_count()`, a different class with the same method
name. So this is a stale docstring on dead API, not a live defect.

The other two consequences survive as written: `channel_index` is still a lane
identifier and not a Z-order key (`ActiveEmitter.gd:22`, `:201`), and
`disabled_emitters` is still a per-emitter build-loop skip
(`EffectParticleRenderer.gd:69`, `:213`).

### The verification gate was never discharged in writing

"Verification gate before merging" names a headful E317 / E019 / multi-frame
replay and a perf acceptance — `draw_calls` peak < 100, spike count < 30, mean
frame time < 17 ms, against the 2026-06-13 baseline of mean 19.40 ms / 108
spikes / 573 peak draws. Those numbers appear in **no other document in
`docs/`**, and no ADR or handoff records the replay. The rewrite merged anyway.
Note that the gate is also no longer measurable as written: it prices `5 ×
N_effects` in-scene draws, and the shipped path draws one MultiMesh per effect
with the rest folded by the compositor, so a re-run would be scoring a different
design against a two-month-old baseline.

### Recorded question — is this ADR amended or superseded?

Not resolved here, because it decides how ADR-0040 should be cited from now on
and the two readings lead to different corpus edits:

- **Amended.** The ADR's *load-bearing* content — the per-instance record
  layout, the instance-buffer-order argument against `sorting_offset`, the
  pool-borrow contract — is what ADR-0200 and ADR-0045 cite, and all of it is
  live. On this reading the Status line should become Accepted and the fold work
  (#218/#219/#220/#221/#227) reads as amendment, which is what this document now
  is.
- **Superseded.** The Decision's central artefact — five per-blend-mode
  MultiMeshes on Forward+'s transparent queue — no longer exists in any form.
  What ships is one opaque MultiMesh plus a display-space compositor fold, a
  design ADR-0040 does not describe and did not choose. On this reading ADR-0040
  should be marked superseded by the compositor-fold ADRs, with the 24-float
  record layout re-homed where ADR-0200 can cite it directly.

The Status line stays **Proposed** until that call is made, rather than being
flipped to Accepted on my own authority for a design that only half shipped.

### On mechanizing this ADR

Two arms are cheap and would have caught real drift:

1. **The named-API arm.** Assert that every backtick-quoted method name in an
   ADR's Decision section that looks like a call (`\w+\(\)`) resolves to a
   `func` in `src/` or is explicitly marked as never-built.
   `borrow_multimesh_set()` has been fiction in an ADR for two and a half
   months, and nothing reads it.
2. **The named-file arm.** Assert that every `assets/shaders/*.gdshader` path
   named in an ADR exists. `effect_particle_mode{0..3}.gdshader` is named four
   times here and zero times on disk.

A perf arm is not worth writing: the acceptance thresholds above are keyed to a
draw-call shape the tree no longer has.
