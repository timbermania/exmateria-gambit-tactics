# React playback is a parallel three-set, not a BODY hijack

The React layer used to be one `AnimationPlayback` that "hijacks BODY's
render" — `_paint_body_variant` checked `_react_active` and substituted
React's frame for BODY's, while the normal WEAPON / EFFECT playbacks
kept painting unchanged. That's why mid-attack weapon trails and effect
overlays kept showing through a flinch reaction: react owned the BODY
pixel but not the WEAPON / EFFECT pixels. The fix used to look like
either snapshot/restore at react entry+exit or a paint-time
"owner" flag on the shared WEAPON playback — both leak state across the
react boundary.

We restructure to a **symmetric** model: React owns its own
three-playback set (`react_playback`, `react_wep1_playback`,
`react_eff1_playback`) that mirrors the normal set
(`type1_playback`, `wep1_playback`, `eff1_playback`). The
[Body lead rule](../context/19-animation-playback.md) applies inside each
set independently. Painting picks its source set by `_react_active` —
no per-layer ownership flag, no entry/exit re-derivation.

## Status

accepted

## Decision

- **Six playbacks per Unit**, in two symmetric sets:
  - Normal set: `type1_playback` (BODY), `wep1_playback` (WEAPON), `eff1_playback` (EFFECT).
  - React set: `react_playback` (BODY), `react_wep1_playback` (WEAPON), `react_eff1_playback` (EFFECT).

  Both sets are pumped under the same clock (per [ADR-0020]; six
  registrations instead of four) — **shared tick cadence, independent
  per-playback counters**. The clock signal advances each playback's
  own `anim_frame` by 1 (or zero, if the playback has no `anim_id` and
  the tick is a no-op for it); the playbacks do not share counter
  values. An idle playback (no `anim_id` set) consumes the tick as a
  no-op.

- **Painting picks its source set.** While `_react_active`, `_paint_body_variant`
  reads from `react_playback`, `_paint_secondary_variant` reads from
  `react_wep1_playback` / `react_eff1_playback`. Otherwise it reads from
  the normal set. The switch is a one-liner per paint function; there is
  no per-playback "owner" or "active" flag — `_react_active` is the
  single coordinator.

- **Body lead rule applies inside each set.** `type1_playback`'s
  `QUEUE_SPRITE_ANIM` opcodes drive `wep1_playback` and `eff1_playback`
  (normal cascade, unchanged); `react_playback`'s opcodes drive
  `react_wep1_playback` and `react_eff1_playback` (react cascade, new).
  WEAPON triggers EFFECT in each set the same way. Cross-set side-effects
  are explicitly forbidden — `type1_playback` never starts
  `react_wep1_playback`, and `react_playback` never starts
  `wep1_playback`.

- **React = display-only.** React has no logical meaning — it does not
  flip `UnitActivity`, does not gate gameplay opcodes, does not modify the
  normal set's state. `type1_playback` keeps advancing through the react
  window so its **gameplay** side-effects still fire (`POST_GENERIC_ATTACK`
  trap spawns, sound triggers, projectile spawns); its **visual** side-effects
  (`QUEUE_SPRITE_ANIM`, `SET_LAYER_PRIORITY`) still mutate the normal set
  but their pixels go unpainted during react.

- **React overlap = newest wins (replace).** When a second
  `play_reaction_animation` call arrives while a React is in flight,
  it restarts the React set with the new animation. No queueing, no
  priority, no two-slot compositing. This resolves the open question
  CONTEXT.md previously flagged under "React overlap." The
  symmetric-set design makes restart cheap and unambiguous: stop and
  re-start three playbacks instead of one.

- **Post-react sync is free.** After react ends, painting flips back to
  the normal set. `wep1_playback` / `eff1_playback` are exactly where
  BODY's cascade put them — they rode along the whole time. No re-derive
  function, no SEQ walker, no "initialize at frame T" helper. The bug
  this ADR fixes (WEAPON / EFFECT not clearing during react and not
  cleanly resuming after) is dissolved by the dual-set cadence (both
  sets get the same clock signal, so the normal set's WEAPON / EFFECT
  counters are exactly where BODY's cascade put them when react ends),
  not patched.

## Consequences

- The cross-layer ownership question goes away. There is no time at
  which "who owns `wep1_playback` right now" needs to be answered —
  React never touches it. The shared-state hazards CONTEXT.md noted on
  `evade_type` corruption do not recur here because the React set's
  state is wholly separate from the normal set's.
- React's own WEAPON cascade is **first-class**, not a side car. The
  `shield_block` reaction (BODY's React SEQ embeds a `QUEUE_SPRITE_ANIM`
  to raise a shield) now routes to `react_wep1_playback` the same way
  normal attacks route to `wep1_playback`. No special-case
  `_wep1_showing_shield` flag is needed at the dispatch layer (it
  remains as a paint-time palette/offset selector, but its meaning is
  local to `react_wep1_playback`).
- The "React playback" CONTEXT.md cluster's wording — currently
  "hijacks BODY's render" — is rewritten alongside this ADR
  ([CONTEXT.md "Animation react"](../context/20-animation-react.md)).
  The "React overlap" subsection moves from open-question to one-line
  rule (newest-wins).
- ADR-0020 (one clock per unit) gets a numeric correction: the clock
  pumps six playbacks, not four. The shared-cadence invariant is the
  same; there are just two more registrations.
- Memory: two more `AnimationPlayback` instances per Unit (a few hundred
  bytes each). At combat-scene unit counts, irrelevant.

## Considered options

- **Snapshot/restore at react boundary** (rejected). Save `wep_enable` /
  `eff_enable` on react entry; restore on exit. Doesn't work — those
  uniforms are auto-asserted every paint by
  `SpriteLayerManager.load_frame_by_id`, so the snapshot reflects a stale
  derivation. And the underlying cascade keeps moving through the react
  window: at exit, the "should be on" answer isn't a snapshot, it's a
  function of the BODY cascade's state at that moment — which the
  snapshot can't capture.
- **Per-paint owner flag on shared `wep1_playback`** (rejected).
  Track "WEP1 currently driven by BODY vs. React"; gate paint by
  `_react_active` matching the owner. Introduces a per-side-effect
  bookkeeping field, a paint-time branch on it, and an asymmetry
  (BODY's cascade vs. React's cascade both have to update the same
  `wep1_playback` while marking it differently). The user grilling
  this surfaced the asymmetry as a code smell — symmetry was the
  better design.
- **Bake BODY + WEAPON + EFFECT into a composite SEQ** (rejected).
  Pre-flatten the data-driven cascade so the runtime is a pure
  per-frame lookup. Combinatorial: WEAPON's anim id depends on
  equipment (`WeaponAnimationSelector.remap_wep_anim_id`) and BODY's
  anim id depends on ability + vertical + sprite_type. Either N × M
  precomputed tables or symbolic-bake plus runtime substitution; either
  way the bake's bookkeeping outweighs the clock-side simplification
  it would buy.
- **Per-activation re-derive helper** (rejected — close call). At
  react end, walk BODY's SEQ from frame 0 to current frame to
  reconstitute `wep1_playback` / `eff1_playback` state. Works in
  principle but requires suppressing BODY's visual cascade during
  react (so the playbacks don't drift) and a new SEQ-walker function.
  Symmetric-set drops both — visual cascade is *naturally* suppressed
  by paint-source switching, no walker needed.

## Migration

Single-file rewrite of `Unit.gd`:

1. Add `react_wep1_playback: AnimationPlayback` and
   `react_eff1_playback: AnimationPlayback` field declarations next to
   the existing `react_playback`.
2. Construct them in `_ready` mirroring how `react_playback` is
   constructed; connect their signals to new handlers
   (`_on_react_wep1_frame_changed`, `_on_react_wep1_side_effect`,
   `_on_react_wep1_complete`; same shape for `react_eff1`).
3. `_on_react_side_effect`'s `QUEUE_SPRITE_ANIM` for WEAPON: route to
   `react_wep1_playback.start(...)` (was `wep1_playback.start(...)`).
4. New `_on_react_wep1_side_effect`: handle WEAPON → EFFECT cascade
   within the React set (routes to `react_eff1_playback`), mirroring
   `_on_wep1_side_effect`.
5. `_paint_secondary_variant`: take a "use react set" boolean (or
   read `_react_active` directly) and pick `react_wep1_playback` /
   `react_eff1_playback` vs `wep1_playback` / `eff1_playback`. One
   branch.
6. `play_reaction_animation` entry: stop and reset
   `react_wep1_playback` / `react_eff1_playback` to a clean slate
   (so a prior react's cascade doesn't bleed into this one). This is
   also the overlap=replace behavior.
7. `_on_react_complete`: stop both new playbacks. Painting flips back
   to the normal set on the next frame via `_render_camera_variant`.
8. `_process` (until [ADR-0020]'s clock lands): add
   `react_wep1_playback.process(delta)` and
   `react_eff1_playback.process(delta)` calls next to the existing
   four.

No data-format changes, no shader changes, no test setup changes. The
existing `GPUReactDurationTest` keeps passing; new tests can exercise
the React-cascade path (e.g., shield_block raises the shield on the
React set's WEP1) without touching the normal set's machinery.

[ADR-0020]: 0020-unit-animation-uses-one-clock-per-unit.md

## Addendum — cinematic-pause clock split (known smell)

`CombatLoop.tick()` currently advances the React-set playbacks inside the
per-unit gameplay speed-multiplier loop, alongside the normal set. During a
cinematic, `CinematicManager.is_active()` triggers `U_PAUSED` on every
non-caster unit, which the speed-multiplier function reads as
`speed == 0` — so the loop ticks neither the normal set nor the React set.
A four-line carve-out compensates: when `speed == 0 and unit._react_active`,
re-advance the React set at 1 so the AoE target's flinch stays visible while
the rest of the world is frozen.

That carve-out is a **symptom**, not the structural fix. The cause is that
React advance was coupled to the gameplay speed multiplier at all — this
ADR's Decision names React as **display-only** ("does not flip
`UnitActivity`, does not gate gameplay opcodes"), so its cadence should not
be modulated by gameplay-side multipliers (`MOVE_SEQ_SPEED`,
`CHARGE_SEQ_SPEED`, `ABILITY_SEQ_SPEED`). The cinematic case is the loudest
symptom; the walking case (React ticked 3-4× faster than authored when an
AoE catches a walking unit) is a quieter one.

**Structural fix:** lift the three `react_*.advance_tick()` calls out of
`for _s in range(speed):` and advance them once unconditionally per IRQ.
The carve-out dissolves; "shared tick cadence" survives in spirit because
the React set advances at the single per-IRQ rate, decoupled from the
gameplay multiplier above it.

**Landed:** [issue #54][gh-54] — see PR linking this addendum.

[gh-54]: https://github.com/timbermania/fft-monorepo/issues/54

