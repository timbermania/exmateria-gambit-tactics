# Animation playback

How a single unit's animation actually runs over time. The cluster is the
direct parallel to the [effect orchestration](15-effect-orchestration.md) one —
both shapes follow the same **"pump owns time; per-output runners are
driven"** discipline (ADR-0011 / ADR-0014 for effects; ADR-0020 for
animation). Read those two clusters together: where the effect side has
`EffectTimeline` + `Subsystem`s, the animation side has `AnimationClock` +
[layer](18-sprite-layers.md) **playbacks**, all owned by one per-unit render
module, [UnitDisplay](19-animation-playback.md) (the narrow seam that lifts the
painting + playback complex off the [Unit](03-unit-roster.md) god-node). The data
side — the SEQ / SHP /
layer-priority / name JSON the playbacks read — lives in
[UnitAnimationSet](19-animation-playback.md), behind
[AnimationDatabase](19-animation-playback.md).

**UnitAnimationSet**:
The frozen per-sprite-type bundle of SEQ / SHP / layer-priority JSON the
[layer playbacks](19-animation-playback.md) read from.
Built once by [AnimationDatabase](19-animation-playback.md) and shared across
every [Unit](03-unit-roster.md) of the same `(seq_type, shp_type)` pair — two
same-typed units hold the same instance, so the per-Unit JSON footprint
stops multiplying. Fields: `type1_seq`, `type1_shp`, `wep_seq`, `wep_shp`
(both already TYPE2-resolved — callers never branch on it), `eff1_seq`,
`eff1_shp`, `layer_priority`. Plus `is_type2: bool`, exposed because
[WeaponAnimationSelector](18-sprite-layers.md)`.get_wep_frame_offset` needs
the flag as an argument — its only public consumer. One `class_name`
module (`addons/exmateria_sprite_rig/sequence/UnitAnimationSet.gd`, a `RefCounted`); fields
read-only after construction. `ANIMATION_FRAMERATE = 45.0` lives here
as the data-side constant. Per-slot human-readable labels are *not* a
field — they live in `AnimationNames` (`assets/sprites/animation_names.json`,
built by `tools/build_animation_names.py` from TacticsEngineG), keyed by
`sprite_type`. See ADR-0034.
_Avoid_: hand-constructing one outside [AnimationDatabase] (skips the
cache + the per-layer JSON path conventions + the `op_code_id`
annotation); calling fields with `Dictionary` dot notation (the Common
Mistakes line — every field on `UnitAnimationSet` is a *typed property*,
not a dict access); mirroring its fields out into
[SpriteLayerManager](18-sprite-layers.md) member vars (the old shape that
the deepening retired — `SpriteLayerManager` holds the reference and
reads through `_anims.type1_shp` etc.); branching on `is_type2` to pick
between `wep1_seq` / `wep2_seq` at a call site (`wep_seq` is already the
correct one); a `get_wep_seq()` helper (retired by the always-resolved
field); a `type1_names` / `wep1_names` / `eff1_names` field (those are
`AnimationNames.get_label(sprite_type, slot)` — the dead members on the
prior shape were a phantom that always read `{}` because no tool
produced the files they pointed at).

**AnimationDatabase**:
The cluster's single seam between disk JSON and runtime
[UnitAnimationSet](19-animation-playback.md). A `class_name` static module
(`addons/exmateria_sprite_rig/sequence/AnimationDatabase.gd`) with the
[JobDatabase](03-unit-roster.md) shape — lazy `_ensure_loaded`, static cache
keyed by `(seq_type, shp_type)`, one entry point: `get_set(seq_type,
shp_type) → UnitAnimationSet`. Owns the per-layer JSON path constants
(no `@export_file` on the consumer), the `op_code_id` annotation pass
for SEQ files, the type1 fallback when an unknown unit type is
requested, and `clear_cache()` for hot-reload. Lives in
`addons/exmateria_sprite_rig/` (the [SfxCatalog](14-audio.md) co-location precedent — the
asset is part of the animation cluster's vocabulary, not a generic
table-of-records in `src/data/`). **Not an autoload** — the
static-cache + `class_name` pattern replaces the previous
`AnimationDataLoader` autoload `Node`. See ADR-0034.
_Avoid_: hand-loading a JSON path from any caller (the only path goes
through this database — the duplicate-loading-path bug class CLAUDE.md's
Common Mistakes table documents); exposing its private `_load_json` as
a generic reader (it carries SEQ-specific `op_code_id` annotation
behavior — bypassing it silently breaks enum-based opcode matching);
growing past the get / clear trio (cache lifecycle only — gameplay
logic stays on [UnitAnimationSet] consumers); restoring the
`AnimationDataLoader` autoload (the `Node` base was vestigial — there
were no signals, no `_process`, no scene-tree role).

**UnitDisplay**:
The per-unit **render module** — the single owner of everything between an
*animation intent* and pixels on the shader. A `RefCounted`
(`addons/exmateria_sprite_rig/render/UnitDisplay.gd`, matching the cluster's
[AnimationPlayback](19-animation-playback.md) / [UnitAnimationSet](19-animation-playback.md)
convention), held as a private field on [Unit](03-unit-roster.md); it references
the existing [SpriteLayerManager](18-sprite-layers.md) Node and the body
`ShaderMaterial` rather than owning scene nodes, so the scene tree is
untouched. It owns the [animation clock](19-animation-playback.md), both
[playback sets](19-animation-playback.md) (normal + React), the body / secondary
painters (pose-octant / cardinal dispatch, frame lookup, palette + frame
offset, layer priority), the React cascade and its `_react_active` /
countdown, and all `load_frame_by_id` wiring. Its interface is **narrow and
told-what-to-render**: `play_body(anim_id)` (the single `current_anim_id`
funnel — re-arms the clock), `play_reaction(seq_id)`,
`advance_frame(view)` where `view = {facing, facing_angle, camera_quadrant,
psx_angle}` is **pushed in** (paint is a pure function of intent + view — no
camera, `anim_state`, or `DebugConfig` global read inside the painter; landed
in C2b: [Unit](03-unit-roster.md) snapshots the view via `_build_view()` and calls
`set_view()` on every repaint trigger — the four camera/facing handlers, the
delta-mode `_process` tick, and `advance_frame` — while `get_camera_variant` /
`_calculate_camera_relative_direction` on `AnimationStateController` became
`static` so the painter no longer reads the `anim_state` instance),
`set_weapon(offset, palette, v_offset)` / `set_shield(...)`, and
`force_complete_body()`. It re-emits the BODY layer's **gameplay**
side-effects (`POST_GENERIC_ATTACK`, `animation_paused`,
`animation_complete`) which [Unit](03-unit-roster.md) forwards to its own signals
— consumers never name `UnitDisplay`. What it deliberately does **not**
own stays on Unit: the resolution-map call (`attack` / `cast_spell`, ADR-0024),
the [animation-state](19-animation-playback.md) machine
(`AnimationStateController`), and [CameraRelativeRenderer](22-sprite-variants.md)
(the shared camera-quadrant source read by shadow / cinematic / scenario, not
display-exclusive). This is the deep-module extraction that lifts the ~470-line
painting + playback complex off the [Unit](03-unit-roster.md) god-node; the
painters become testable through the interface with plain values (the
characterize-first golden over `anim_id × facing × quadrant × react`
becomes the clean unit test). Planned — see the pending refactor plan and
ADR-0020 / ADR-0025 (which this extraction finally implements: the clock and
the two-set model are spec here but not yet in code).
_Avoid_: any combat / scenario / effect consumer naming `unit.display`
(Unit is the sole facade — the display module is private; reach-ins go
through Unit members, the pattern `unit.activity_complete` already sets);
making `UnitDisplay` a `Node` and reparenting `$SpriteLayerManager` under it
(churns every `.tscn` for no gain — it *references* the Node); widening the
boundary to swallow `AnimationStateController` or `CameraRelativeRenderer`
(both have gameplay / shadow / scenario consumers — the narrow boundary is
what keeps the painter a pure function of intent + view); reading
`PSXDisplay.live_camera_angle` or a live `camera_renderer` *inside* the
painter (the view is pushed in — reintroducing the global / live dep is the
untestability the extraction sheds); pre-resolving pose-octant / cardinal on
the Unit side and passing final slot ids (that resolution is per-frame
camera-reactive and **must** run at paint time, inside `UnitDisplay`).

**Animation clock**:
The per-unit pump that owns the fixed-timestep accumulator, the
tick-vs-delta mode choice, and the `playback_speed_multiplier`. It
fires a "tick" signal to each of the unit's **layer playbacks** once
per pumped frame — **shared cadence, independent per-playback
counters** (each playback owns its own `anim_id` and `anim_frame`;
the clock's job is to keep their cadence aligned, not to share values).
There is **one** clock per
unit, mirroring the [effect timeline](15-effect-orchestration.md) one-clock
invariant — never six independent accumulators, one per
[playback](19-animation-playback.md) (the historical model this cluster
retires; see ADR-0020 for the latent drift bug between BODY's sped-up
walk animation and the un-multiplied WEAPON / EFFECT playbacks). **Who the
clock is pumping for is published as `ExMateriaSchema.ClockOwner.Kind`** —
the subject noun is carried because a bare `Owner` in the kernel tells a stranger
nothing, and `AnimationClock` keeps its class name and every line of its behaviour
([ADR-0217](../adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
dec. 7).
_Avoid_: a per-Playback `tick_based` flag (one mode decision lives on the
clock, not duplicated six times); calling this a "logical clock" (the
historical docstring term — collides with Lamport / vector clocks in
distributed systems); confusing this with the [effect
timeline](15-effect-orchestration.md) (different scope: unit's animation vs.
one effect cast's playback).

**Layer playback** (a.k.a. `AnimationPlayback`):
A per-[layer](18-sprite-layers.md) opcode runner — owns the layer's current
`anim_id`, the integer `anim_frame` *within that anim_id*, the sequences
reference, and the side-effect emission for opcodes in the sequence
(`QUEUE_SPRITE_ANIM`, `SET_LAYER_PRIORITY`, `POST_GENERIC_ATTACK`,
`QUEUE_DISTORT_ANIM` / `WAIT_FOR_DISTORT`, the eight fixed-offset move
opcodes, the four parameterised move opcodes). Per [ADR-0020], it does
**not** own a clock — the [animation clock](19-animation-playback.md) pumps it.
Each unit has **six** layer playbacks, in two symmetric
[playback sets](19-animation-playback.md) of three (BODY / WEAPON / EFFECT):
the **normal set** (`type1_playback` / `wep1_playback` / `eff1_playback`)
and the **React set** (`react_playback` / `react_wep1_playback` /
`react_eff1_playback`); see [ADR-0025]. `STATUS_TEXT` gets one in each
set when implemented.
_Avoid_: a Playback owning its own accumulator or its own
`playback_speed_multiplier` — these are clock concerns; calling the
React set a "fifth layer" (there are still four layers; React is a
parallel **set** painting onto the same four shader slots when active);
cross-set side-effects (the normal set's `QUEUE_SPRITE_ANIM` never
starts a React-set playback, and vice versa — see [ADR-0025]).

**Playback set**:
A `(BODY, WEAPON, EFFECT)` triple of [layer playbacks](19-animation-playback.md)
that share a [Body lead rule](19-animation-playback.md) lineage — BODY's
cascade triggers WEAPON within the set, WEAPON triggers EFFECT within
the set, cross-set triggers are forbidden. Each Unit owns two sets: the
**normal set** drives normal play; the **React set** drives the visual
during [React](20-animation-react.md). Painting picks which set's frames go
to the shader by `_react_active` — when true, the React set; otherwise,
the normal set. Both sets advance every frame under one [animation
clock](19-animation-playback.md); pumping is unconditional, source-selection
is conditional. See [ADR-0025] for the rationale (the previous
single-React-playback model leaked the WEAPON/EFFECT cascade across the
react boundary).
_Avoid_: calling a single playback a "set" (a set is the triple);
implementing a third set ("react-of-react" — there is no such concept);
believing a set's BODY can drive another set's WEAPON (the body-lead
rule is intra-set only).

**Body lead rule**:
The BODY layer's playback is the **lead** track: state changes restart it
(facing / camera changes do not), and its opcodes can trigger the WEAPON
and EFFECT layer playbacks via `QUEUE_SPRITE_ANIM` side-effects. WEAPON
can in turn trigger EFFECT. EFFECT triggers nothing further. The cascade
is **data-driven** (lives in the SEQ opcode stream), not hard-coded —
removing a `QUEUE_SPRITE_ANIM` from a BODY sequence silently disables that
unit's weapon-trail or hit-spark for that animation. The trigger order is
fixed (BODY → WEAPON → EFFECT) and asymmetric: EFFECT cannot start BODY,
WEAPON cannot start BODY, etc.
_Avoid_: putting "what triggers what" rules anywhere outside the SEQ data
+ the `_process_side_effects` dispatch; calling WEAPON or EFFECT
"independent" (they're peer playbacks under the clock, but they're
*triggered* by BODY, never freestanding); inventing a generic "any layer
can trigger any other" model (FFT is BODY → WEAPON → EFFECT, full stop).

**React playback**:
The mechanism — the **React [playback set](19-animation-playback.md)** on
every Unit, mirroring the normal set. The React set's BODY (`react_playback`)
uses the same `type1_seq` data as the normal BODY but plays its own
`anim_id`; the React set's WEAPON (`react_wep1_playback`) and EFFECT
(`react_eff1_playback`) are driven by the React BODY's cascade via the
same [Body lead rule](19-animation-playback.md). While `_react_active`,
`Unit._paint_body_variant` paints from `react_playback` and
`_paint_secondary_variant` paints from the React set's WEAPON / EFFECT
playbacks — the normal set's pixels are skipped entirely. The normal
set's playbacks **keep advancing** under the clock (and their **gameplay**
side-effects still fire — `POST_GENERIC_ATTACK` trap spawns, sound
triggers, projectile spawns), but their **visual** side-effects
(`QUEUE_SPRITE_ANIM`, `SET_LAYER_PRIORITY`) merely mutate state that
goes unpainted during the react window. After react ends, painting flips
back to the normal set; WEAPON / EFFECT cut back in sync because they
rode along the whole time — no re-derive needed. Two modes:
**timer-bound** (melee reactions count down `_react_ticks_remaining`
ticks then end), **untimed** (spell reactions end on
`animation_complete` from the React BODY). State changes cancel React
(`_cancel_react_if_active`); unit death force-completes it. **What runs
on it — the trigger sources, the animation-resolution path, and the
overlap rule — lives in the separate [Animation react](20-animation-react.md)
cluster**; this entry is about the playback machinery alone. See
[ADR-0025] for the parallel-set rationale.
_Avoid_: thinking of React as overriding BODY's *playback* — the normal
set's opcodes keep firing, only the rendered set switches; calling React
a "layer" (there are four [layers](18-sprite-layers.md); React is a parallel
[set](19-animation-playback.md) painting onto the same four shader slots when
active); driving a React-set playback from the normal set's side-effects
(or vice versa — [ADR-0025] forbids cross-set triggers); having any
other system reach into the React set's state — the React-related fields
are owned by `Unit` and the React set's playbacks alone.
