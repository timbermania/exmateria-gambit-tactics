# UnitDisplay extraction — refactor handoff

Handoff brief for `/refactor-plan`. Produced via `/improve-codebase-architecture`
→ `/grilling`. The architecture is **converged**; this document records the
locked decisions and the coupling map so the refactor plan can be authored
without re-litigating them. Domain vocabulary is in
[`CONTEXT.md` → Animation playback → UnitDisplay](context/19-animation-playback.md).

## Goal

Lift the ~470-line painting + playback complex off the `Unit` god-node
(`src/units/Unit.gd`, 2,334 lines, 12+ responsibilities) into a deep module,
**UnitDisplay** (`RefCounted`), with a narrow "told-what-to-render" interface.
The painters are untestable today (need a live scene + shader + camera); behind
the seam they become pure functions of `(intent, view)`.

This extraction also **implements ADR-0020 and ADR-0025**, which are *accepted
but never landed*: there is no `AnimationClock.gd`; `AnimationPlayback` still
owns `accumulator` / `tick_based` / `playback_speed_multiplier`; and the
six-way pump is still hand-written. The live `playback_speed_multiplier` drift
bug ADR-0020 describes is still present.

## Locked decisions (from the grilling)

| # | Decision | Resolution |
|---|----------|-----------|
| 1 | Clock vs set sequencing | **AnimationClock + PlaybackSet land together first** (discharges ADR-0020, kills the drift bug) |
| 2 | Facade stance | **Unit is the sole facade**; `UnitDisplay` is a private field. Consumers never name it (extends the `unit.activity_complete` precedent). Debug tools may still reach in. |
| 3 | Module form | **`RefCounted`** referencing existing Node children (`sprite_layers`, `material`). Scene tree + every `.tscn` untouched. |
| 4 | Boundary | **Narrow — told what to render.** Unit keeps: the resolution-map call (`attack`/`cast_spell`, ADR-0024), `AnimationStateController` (`anim_state`, the activity machine CombatLoop drives), and `CameraRelativeRenderer` (`camera_renderer`, the shared quadrant source). |
| 5 | Intent shape | **`current_anim_id` + the clock move into display.** Everything funnels through `display.play_body(anim_id)`. `attack()`/`cast_spell()` stay on Unit (resolve via `AnimationResolutionMap`, store `last_resolution`), then call it. `set_weapon`/`set_shield` push cached offset/palette. |
| 6 | View params | **Pushed in per advance** — `advance_frame(view={facing, quadrant, psx_angle})`. Paint is a pure fn; the `PSXDisplay.live_camera_angle` global read leaves the hot painter. |
| 7 | Safety net | **Characterize first** — golden over `(current_anim_id × facing × quadrant × react)` capturing resolved SEQ key / frame id / palette row / reversion via a spy on `sprite_layers.load_frame_by_id`. Converts to the clean UnitDisplay unit test at the end. |

## Interface (the whole test surface)

```
display.play_body(anim_id: int)          # current_anim_id funnel; re-arms clock
display.play_reaction(seq_id: int)       # starts the react PlaybackSet
display.advance_frame(view)              # view={facing, quadrant, psx_angle}; pumps clock → both sets → paint
display.set_weapon(offset, palette, v_offset) / set_shield(...)
display.force_complete_body()            # ScenarioVM
signal body_side_effect / body_paused / animation_complete   # Unit forwards these up
property is_reacting, anim_frame (read)  # for Unit facades
```

## Commit sequence

- **C0 — Characterize.** Golden test + `load_frame_by_id` spy. Oracle for every later commit.
- **C1 — AnimationClock + PlaybackSet.** New `AnimationClock` (owns accumulator, `tick_based`, speed) pumping two `PlaybackSet`s (each: body/wep1/eff1 + cascade). `AnimationPlayback` loses accumulator/tick_based/speed; `advance_tick`→`advance_frame`. Collapse the six-way pump at every call site (below). De-dup the normal↔react handler pairs.
- **C2 — Extract UnitDisplay.** Move clock + sets + painters + react cascade behind the narrow interface. `current_anim_id` + react countdown become display-internal. Push view in.
- **C3 — Facade forwarding.** Unit re-emits `body_side_effect`/`body_paused`; `is_reacting`, `force_complete_body()`, semantic verbs delegate. Migrate reach-ins (below).
- **C4 — Convert golden** into a first-class UnitDisplay unit test (no scene/camera). The payoff.

## Coupling map — external reach-ins that must be absorbed

The six-way pump + playback/react reach-ins (all collapse to Unit-facade calls or one `advance_frame`):

- `src/gpu/CombatLoop.gd`
  - 276–277: connects `unit.type1_playback.animation_paused` / `.side_effect` → become `unit.body_paused` / `unit.body_side_effect`
  - 410–415, 467–474: six `advance_tick()` per unit → one `unit.advance_frame(view)` (or `unit.display.advance_frame`)
  - 476–478: manual `_react_ticks_remaining` decrement → **retires** (display owns the countdown)
  - 1265: `target_unit._react_active` → `target_unit.is_reacting`
- `src/gpu/CombatLoop.gd:1072` `_on_unit_type1_side_effect` — POST_GENERIC_ATTACK → `effect_manager.fire_pending_trap` + `_trigger_physical_reaction`. Stays; just re-sourced from Unit's forwarded signal.
- `tests/GPUCombatTestBase.gd:273–278`, `src/scenes/GPUArena.gd:287–292`, `tests/gambit_runner/GambitScenarioRunner.gd:247–252`: six `tick_based=true` → one clock flag.
- `tests/GPUReactDurationTest.gd:124–137`: six `advance_tick` + manual react countdown → one `advance_frame` (countdown internal).
- `tests/GPURiseTimingTest.gd:126–129`: reads `type1_playback.anim_frame` → `unit.anim_frame`.
- `tests/GPUSEQMovementTest.gd:65–66`: `type1_playback.move_offset_changed` → route through Unit (or display signal).
- `tests/UnitEffectCleanupOnStateChangeTest.gd:111–112`: starts `wep1_playback`/`eff1_playback` directly — update to the new set API.
- `src/scenarios/ScenarioVM.gd:3033, 3141–3142, 3403`: `type1_playback` null-checks + `force_complete()` → `unit.force_complete_body()`.
- `src/scenes/EffectViewerScene.gd:336, 359`: `_target._react_active` → `is_reacting`.
- `src/debug/CinematicDebugProbe.gd:78, 155, 255`: reads `_react_active`, `type1_playback.is_paused/anim_frame` — debug, may reach in (allowed).

## Painters being moved (source of truth)

- `Unit._paint_body_variant()` (`src/units/Unit.gd:919–1001`) — Path-D dispatch on `current_anim_id` (ADR-0053): idle pose-octant (A+B LUT), low-range SEQ (`resolve_low_range_seq_key`), EVTCHR stub; react body substitution. Reads `get_camera_quadrant()`, `facing_angle`, `PSXDisplay.live_camera_angle`.
- `Unit._paint_secondary_variant(playback, layer)` (`1004–1031`) — wep1/eff1 back-variant pick, frame offset + palette row + v_offset, shield vs weapon swap.
- `Unit._apply_variant_layer_priority()` (`1034–1057`).
- Six frame-changed / side-effect handlers (`_on_type1_*`, `_on_wep1_*`, `_on_eff1_*`, `_on_react_*` at 1220–1474) — collapse into the two `PlaybackSet`s' cascade.
- `_arm_anim_id_clock()` (`829`) and the `current_anim_id` setter (`231–243`) — move into display.

## Boundary — what stays on Unit (do NOT move)

- Progression / equip / learn / job mutation surface (ADR-0005 / 0007) — Unit is the durable-progression reference holder + mutation surface.
- `attack()`/`cast_spell()`/`use_item()`/`charge_ability()` (`609–690`) — resolve via `AnimationResolutionMap`, store `last_resolution`, then call `display.play_body(...)` + `set_weapon(...)`.
- `activity` property → `anim_state.set_state`; `facing_direction`/`facing_angle`; `get_camera_quadrant()` (forwards to `camera_renderer`).
- `AnimationStateController` and `CameraRelativeRenderer` (Node children with non-display consumers).

## Open items for the refactor plan

- Exact signal set Unit re-exposes (`body_side_effect`, `body_paused`, `animation_complete`, `move_offset_changed`, `distort_requested`?) — enumerate from `AnimationPlayback` signals and current consumers.
- Whether C1 can land as one commit or needs a split (clock, then PlaybackSet grouping).
- `--import` class-cache rebuild after adding `class_name AnimationClock` / `PlaybackSet` / `UnitDisplay` (per CLAUDE.md Common Mistakes).
- Verification each commit: `bash tests/run_all_tests.sh` (sequential GPU tests) + the C0 golden.
