# Body anim id is one field with two writers

Combat and event-script playback need to render the same unit through the
same renderer, but they decide *which* anim to play in very different ways.
Combat derives the anim from a unit's activity (IDLE, ATTACKING, …) through
the [Animation resolution map](../context/18-sprite-layers.md); event-script
opcodes (FFT's 0x11 Unit Anim and friends) write an explicit anim id
directly. Pre-this-ADR Godot had only the combat path; `ScenarioVM` faked
event-script writes by routing through `activity` and `facing`, which works
for some opcodes but cannot express the per-cinematic-pose EVTCHR ids and
silently loses the PSX-faithful per-direction idle dispatch.

The static + dynamic RE work in
`research/working_documents/chapel_opcode_trace/SPRITE_PIPELINE_INVESTIGATION.md`
showed PSX's actual factoring: **one anim-id field on the unit struct
(`unit+0x0c`), written by both paths, consumed by one renderer
(`FUN_80085c0c`)** that dispatches on the field's value range. The field
is the marriage point — not the activity, not the SEQ slot, not a
`{front, back}` pair.

The chapel cinematic exposed the failure mode: Agrias's 180° Rotate Unit
cascade (scenario chunk PC 95, `0xC00 → 0x400` over 8 byte-steps) visibly
under-rotates her sprite by ~half the arc because Godot's cardinal-only
collapse loses 3 of 5 PSX-faithful idle frame bases.

## Status

accepted

## Decision

**Add a single `current_anim_id: int` field to Unit. Both the combat
resolver and `ScenarioVM` write it. The renderer in `_paint_body_variant`
owns the dispatch from anim id to SEQ slot.** The dispatch mirrors PSX
`FUN_80085c0c` 1:1:

| `current_anim_id` | Path | SEQ slot | Camera precision |
|---|---|---|---|
| `0` | idle | 1..5 from Sub-table A indexed by **pose_octant** (4-bit) | pose-octant |
| `1..0x1f4` | SEQ-range | `(anim_id-1)*2 + Sub-table E[cardinal_idx]` | cardinal |
| `>=0x1f5` | EVTCHR | walker spawned on `_op_unit_anim`; bytecode at `script_ptr_table[anim_id-0x258]` emits `frame_bytes` per tick (TYPE1.SHP for `< 0xD2`, EVTCHR atlas for `>= 0xD2`) | bypass |

Sub-tables A (frame-base tent), B (idle mirror flag), E (cardinal
offset), F (cardinal mirror flag) are read at battle-load from BATTLE.BIN
`0x800680dc..0x8006812b` (40 halfwords) and baked as Godot
`PackedInt32Array` constants — they are static rodata in PSX, not
runtime-populated. The full LUT bytes are in `SPRITE_PIPELINE_INVESTIGATION.md`.

Both `pose_octant` and `cardinal_idx` derive from the same
camera-relative angle `(facing_angle + camera_offset) & 0xfff`, sampled
at different precisions: `cardinal_idx = pose_octant >> 2`. The
`AnimationStateController` exposes both so each consumer takes the
precision it wants — see the rewritten
[Camera variant](../context/22-sprite-variants.md) entry.

Concretely — the six rules below were an unnumbered bullet list until this
ADR's audit; they were numbered, text unchanged, so `ADR-0053 dec. N`
citations resolve. Amendment 1 grades each one against the tree.

1. **Unit**: `current_anim_id: int` (default `0` = idle). Setter calls
   `type1_playback.start()` to restart the playback clock (mirrors PSX's
   `FUN_80084818` arm — pose state zeroed, frame counter seeded). Pose
   resampling does **not** restart the clock — paint-time only.
2. **`CombatLoop._update_unit_animation`**: calls
   `AnimationResolutionMap.resolve_for_activity(...)` as today, then writes
   `unit.current_anim_id = resolution.slot`.
3. **`ScenarioVM._op_unit_anim`**: writes `unit.current_anim_id =
   anim_id` directly. The event opcode 0x11 anim id flows through with
   no transformation — `>=0x1f5` is an EVTCHR id, the renderer handles
   it (today: stub).
4. **`Resolution`**: shape simplifies from `{body_slot, body_back_slot}`
   to a single `body_slot: int`. The `body_back_slot` field is retired —
   all front/back duality is rebuilt by the renderer from `body_slot +
   Sub-table E[cardinal_idx]`. Audit of `map.tres` (2026-06-27) confirmed
   every authored row was already `(N, N+1)` or `(1, 1)` stub; no
   non-adjacent pair survives Path D.
5. **`_paint_body_variant`**: 3-way switch on `current_anim_id` range,
   each branch picks slot + mirror flag, paints. EVTCHR branch is a
   `push_error` stub for now (see "Out of scope" below).
6. **`AnimationStateController`**: `get_camera_variant` keeps returning
   `{use_back, revert}` for callers that want the cardinal precision; a
   new `get_pose_octant(face_dir, camera_quad) -> int` returns the 4-bit
   pose_octant for the idle dispatcher.

## Consequences

**The renderer is now the single owner of front/back/mirror dispatch.**
The pre-this-ADR shape had three places computing front-vs-back: the
resolver populated `body_slot`/`body_back_slot`; the painter picked via
`use_back`; the camera-variant entry documented it as
`{use_back, revert}`. Post-this-ADR there's one dispatcher in
`_paint_body_variant` keyed off `current_anim_id`.

**`ScenarioVM` and `CombatLoop` are equal-status writers.** Neither
codepath is privileged; the field is owned by `Unit` (the data) but
written from both consumers. Order: last writer wins. In chapel the
combat resolver doesn't fire while `ScenarioVM` is active (no
`CombatLoop.start_battle` yet), so contention is not yet a real issue;
when scenarios eventually overlap a battle, the rule will need to be
codified ("scenario writes preempt combat for the duration of the
script").

**The Camera variant CONTEXT.md entry was rewritten.** Pre-this-ADR it
documented a 2-bool pair as the universal shape and explicitly said
"two authored variants cover the four camera-relative facings." That
line was a documentation of the buggy collapse, not a load-bearing
invariant. The rewritten entry admits two precisions: cardinal (2-bit)
for SEQ-range, pose-octant (4-bit) for idle.

**The historical `Resolution.body_back_slot` field is retired.** The
2026-06-27 `map.tres` audit confirmed all authored pairs were already
`(N, N+1)` or `(1, 1)` stub; the field's "non-adjacent pair override"
purpose was theoretical from day one. Removing it tightens the Path D
boundary: the renderer is the *only* place that knows what "back" means
relative to "front."

**Naming**: the event-script writer path must not be called "cinematic"
anywhere in code or docs. The word is taken by `CinematicManager` /
ADR-0037, the per-cast in-combat spell spotlight that pauses combat
visuals — a distinct subsystem. The new writer is named after FFT's
own term: **event-script** (`ScenarioVM`, event opcodes 0x11 etc.).

## Out of scope (deferred)

- ~~**EVTCHR rendering (`anim_id >= 0x1f5`)**.~~ **Landed 2026-06-27.**
  Implementation: `ScenarioVM.CinematicWalkState` walks the bytecode at
  `script_ptr_table[anim_id - 0x258]` (from `cinematic_seq.json`) and
  emits per-frame bytes to the BODY shader — `< 0xD2` via TYPE1.SHP,
  `>= 0xD2` via EVTCHR atlas. Palette mirrors combat: V14 routes the
  ENTD slot's `palette` byte into the unit's existing `body_palette_row`
  uniform at spawn, and both TYPE1.SHP and EVTCHR pixels sample the
  unit's own SPR palette — no per-segment EVTCHR palette is bound by
  default. The `{7F} EVTCHRPalette` override opcode (unused in chapel)
  remains future scope.
- **Sub-tables C+D** (sub-part-index dispatch for `anim_state >= 6`).
  The semantics of `a2` (sub-part index) at the caller of
  `FUN_80085c0c` are not yet decoded; chapel does not fire this path
  (`+0x1dc < 6` throughout). Combat-side renderer work will need it
  eventually.
- **Combat-side renderer convergence**. The combat renderer
  `FUN_8017a290` is dormant in chapel but live in normal combat. Whether
  it dispatches the same way as `FUN_80085c0c` is an open question (the
  combat path's `FUN_8017fddc` writes a different sprite-table format).
  Path D as scoped here updates the cinematic dispatch only; combat
  rendering keeps its existing shape.

## Alternatives considered

- **Two parallel activity tracks** (`activity` + `event_activity` or
  `script_anim_override`). Rejected because PSX has one field on the
  unit struct, not two; this would invent a Godot-side bifurcation that
  doesn't exist in the source material and leaks the bifurcation into
  every consumer that has to pick which to read.
- **`ScenarioVM` drives `SpriteLayerManager` directly**, bypassing
  Unit's animation machinery. Rejected because the camera-variant
  resampling (pose_octant, the whole point of Path D) and the playback
  clock both live on Unit; pulling event-script renderers out of that
  boundary would either duplicate them or fork the renderer.
- **Keep `Resolution.body_back_slot`**. Rejected because the data
  audit found zero non-adjacent pairs and PSX's SEQ-range dispatch is
  uniformly `(anim-1)*2 + offset` — the override field has no
  authored or PSX-faithful consumer.

## References

- `research/working_documents/chapel_opcode_trace/SPRITE_PIPELINE_INVESTIGATION.md`
  — full static + dynamic analysis, the per-direction LUT bytes, the
  Sub-table decode, the live captures from chapel.
- `reference_cinematic_lut_2026_06_27.md` — compact memory summary of
  the LUT.
- `reference_cinematic_renderer_subbranches_2026_06_27.md` — the
  `FUN_80085c0c` sub-branch decode.
- `reference_cinematic_renderer_2026_06_27.md` — combat-vs-cinematic
  renderer split (the dormant-in-chapel finding).
- ADR-0021 — animation-resolution-is-per-state-one-atlas (the resolver
  shape this ADR extends).
- ADR-0020 — unit-animation-uses-one-clock-per-unit (the clock-restart
  rule this ADR generalises).
- ADR-0037 — combat-pause-is-domain-scoped-via-process-mode-group
  (defines the "cinematic spell" usage of the word; this ADR
  deliberately avoids that word for the event-script writer).

## Amendment 1 — the field left `Unit`, the write half was retired, the EVTCHR boundary is off by one, and the naming rule is broken in 20 files

_Audit, 2026-08-28. Every decision above graded against the tree. The six
decisions were numbered in the same pass; the Decision text itself is
unchanged._

Every rule in this ADR still holds. Three of the six moved home or spelling, one
Consequence is violated outright, and one number in the Decision table disagrees
with the code by exactly one. This ADR is unusually well covered — **eight tests
cite it**: `UnitCurrentAnimIdTest`, `GetPoseOctantTest`, `CinematicPoseLUTTest`,
`UnitDisplayPaintGoldenTest`, `UnitCinematicIdleModeTest`,
`UnitThrowBodyDispatchTest`, `ScenarioFacingAnimDecodeTest`,
`UnitEffectCleanupOnStateChangeTest`.

### What is current, per decision

| Dec. | Rule | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | `Unit` gains `current_anim_id: int`; its **setter** re-arms the clock | rule yes, **home and shape both moved** | The field is declared on `UnitDisplay.gd:67`, not on `Unit`. `Unit.gd:345` is a **read-only forwarding property** (`get:` only) — the write half was retired under issue #152 because "every driver … funnels through `play_body`". So there is no setter to call: `UnitDisplay.play_body(anim_id)` (`:201-217`) is the single funnel, and it calls `_arm_anim_id_clock()` (`:262`). This is a **strengthening**, not drift — a driver can no longer assign the field and forget the clock. Same-value idempotence holds exactly as written, including the DYING → DEAD case (`:207-208`). |
| 1 (cont.) | "**one** field" | **one and a half** | `play_body` also repopulates `_unit.current_animation_front` and `_unit.current_animation_index` (`:215-216`) as declared back-compat for tests and viewer readouts; `current_animation_front` is still read at `Unit.gd:1066`. The second field is derived and never authoritative, but it exists and is read, so "one field" is a claim about ownership, not about count. |
| 2 | `CombatLoop._update_unit_animation` writes `unit.current_anim_id = resolution.slot` | rule yes, **one level down** | `CombatLoop` does not write the field. It calls `unit.update_animation()`, which resolves through `AnimationResolutionMap.resolve_for_activity` and ends at `display.play_body(r.body_slot)` (`Unit.gd:904-924`). Same single write, reached through the funnel. |
| 3 | `ScenarioVM._op_unit_anim` writes `unit.current_anim_id = anim_id` **directly** | rule yes, **three hops now, and there is a second opcode** | `_op_unit_anim` (`:3923-3927`) is one line: `ScenarioApply.unit_anim(ScenarioDecode.unit_anim(...), _world)`. Its own comment records that "the range-dispatch animation machine (`_apply_unit_animation`) stays VM-side, reached via the `play_unit_anim` verb" — decode / apply / verb, not a direct assignment. And the event side now has **two** writers, not one: `{8C} Unit Anim Rotate` (`_op_unit_anim_rotate`, `:4061-4063` → `ScenarioApply.unit_anim_rotate`) is documented at `:794-796` as mirroring `{11}`'s animation path. The ADR's title says "two writers"; on the event side alone there are two opcodes. |
| 4 | `Resolution` collapses to a single `body_slot`; `body_back_slot` retired | **yes, in full** | `AnimationResolutionMap.gd:33` declares `body_slot: int = -1` and nothing else; `body_back_slot` has **zero hits** tree-wide. |
| 5 | `_paint_body_variant` is a 3-way switch; EVTCHR branch is a `push_error` stub | **yes, and the stub is gone** — but see the boundary below | `UnitDisplay._paint_body_variant` (`:317`) dispatches idle / SEQ-range / EVTCHR, and the EVTCHR branch is real (`:390-397`), matching the *Out of scope* entry's "Landed 2026-06-27". The docstring **one screen above it** (`:330`) still reads "`>= 0x1f5` → EVTCHR (deferred — push_error stub)". |
| 6 | `get_camera_variant` kept; new `get_pose_octant(face_dir, camera_quad) -> int` | **yes, plus a member the ADR does not name** | Both exist and are used (`UnitDisplay.gd:341`/`:416` and `:367`). `AnimationStateController` also gained `pose_octant_to_atlas_cardinal(pose_octant)` (`:140`), documented at `:132-139` as the route **every** `pose_octant >> 2` should take — because it is `(pose_octant >> 2) & 0x3`, and this ADR's bare `cardinal_idx = pose_octant >> 2` is missing the mask. `:82-87` records a facing-enum mismatch corrected along the way. |

### The Decision table's EVTCHR boundary is off by one against the code

The table above says SEQ-range is `1..0x1f4` and EVTCHR is `>= 0x1f5`. The code
branches on `current_anim_id < 0x1f4` (`UnitDisplay.gd:287` and `:376`), so
**`0x1f4` itself takes the EVTCHR branch**, not the SEQ branch. The code explains
why at `:390-397`: `0x1F4` is the PSX band boundary, with a **mid** band
`[0x1F4, 0x258)` and a **high** band `[0x258, …)`. This ADR knows only the high
band — its EVTCHR row indexes `script_ptr_table[anim_id - 0x258]`, and the code's
clock key is `str(current_anim_id - 1)` (`:290`).

Two readings, and this amendment does not pick one:

1. **The ADR is off by one and the code is right.** The mid-band decode
   post-dates this ADR (`SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`), and `0x1F4` was
   never a valid SEQ id. Then the Decision table's third row should be amended to
   `>= 0x1f4` and gain the two-band split.
2. **The code is off by one.** `0x1f4` is the last SEQ-range id as originally
   decoded, and `<` should be `<=`. An anim id of exactly `0x1f4` would then be
   painting through the wrong branch.

Nothing in the tree distinguishes them without going back to the ROM, and no
test exercises `anim_id == 0x1f4`. **The tell that this matters**: the same file
carries *both* spellings — `UnitDisplay.gd:323`/`:330` and
`AnimationResolutionMap.gd:30-31` restate the ADR's `1..0x1f4` / `>= 0x1f5`,
while `:287`/`:376`/`:390` implement `< 0x1f4` / `>= 0x1f4`. A reader gets a
different boundary depending on which line they land on.

### The naming Consequence is violated, and this ADR violates it itself

> *"the event-script writer path must not be called 'cinematic' anywhere in code
> or docs. The word is taken by `CinematicManager` / ADR-0037 …"*

Measured: **20 files** under `src/animation/` + `src/scenarios/` use the word,
across at least eighteen distinct identifiers on the event-script path —
`CinematicPoseLUT` (a `class_name`, with its own test), `CinematicWalkState`,
`is_cinematic_unit`, `cinematic_idle`, `cinematic_place`, `cinematic_seq`,
`cinematic_frame_override`, `cinematic_segment_override`,
`_play_cinematic_unit_anim`, and more. ADR-0037's owner of the word is
`src/gpu/CinematicManager.gd`, so the collision the rule was written to prevent
is live.

This is not late drift. **The rule was already broken inside this ADR** — its own
*Out of scope* entry, updated when EVTCHR landed on 2026-06-27, names
`ScenarioVM.CinematicWalkState`. A naming rule that its own document breaks in
the same file has no chance downstream, and nothing mechanized it.

### On mechanizing this ADR

Decisions 1, 4, 5 and 6 already have direct test coverage (see the eight tests
above). Three arms are missing:

- **Decision 1's funnel is mechanizable and is the highest-value arm.** Assert
  that no `.gd` outside `UnitDisplay.gd` assigns `current_anim_id` — the property
  on `Unit` is getter-only, so any such assignment is either dead or a second
  write path. This is a cheap text net over the walk and it locks in the
  strengthening that issue #152 already landed.
- **Decision 4 is trivially mechanizable**: assert `body_back_slot` has zero
  occurrences. Today it does; nothing stops it coming back.
- **The naming Consequence is mechanizable and would land RED** — an arm
  asserting no `cinematic` identifier outside `src/gpu/CinematicManager.gd` fails
  on 20 files. That makes it a *decision*, not a guard: either the rule is
  retired as lost (and the Consequence amended to say so), or a rename is
  scheduled. Filing the guard before that call would be filing a permanent red.
