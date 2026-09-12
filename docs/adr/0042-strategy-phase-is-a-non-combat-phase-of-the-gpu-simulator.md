# The strategy phase is a non-combat phase of the GPU simulator

Until now the game has had **two disjoint worlds**. The strategy phase (unit
placement) is 100% CPU: units spawn as hidden `Unit` nodes and `place_on_tile`
sets `global_position` directly — an instant teleport. The combat world is the
GPU compute simulator, which the project treats as the **single source of truth**
for unit logic and movement (ADR-0017, ADR-0018; `godot-learning/CLAUDE.md`). It
only boots at `start_battle`, when `CombatLoop.combat_active` flips true.

We want units to **walk into position** during placement — to "navigate the same
way they navigate now," taking turns marching to their tiles instead of popping
into existence. The naive way is a second, CPU-side mover (a pathfinder + a
tween). That duplicates the GPU mover, won't match its step timing / haste model,
and *entrenches* the two-worlds split instead of healing it.

Instead we make the strategy phase **a non-combat phase of the same GPU
simulator**: units move in GPU state and are displayed by the same CPU bridge —
the exact data-flow combat already uses, with nothing "fighting."

## Status

**superseded by [ADR-0258](0258-the-march-is-retired-and-two-enums-lose-a-member-without-renumbering.md)**
(2026-09-07). This ADR's subject — the deployment march, and the `deploy_active` axis
that let the simulator tick outside combat to animate it — is retired outright. Its
whole `CombatLoop` surface had a single caller and went with it.

⚠️ ONE PART OUTLIVED ITS OWN AUTHOR AND IS STILL LIVE: the **`start_battle` boot/arm
split**. `boot_battle` and `arm_combat_gambits` are still two calls, because
`NavigatorMain` boots on the walk's units and arms at its own go-live. Do not read
this ADR's superseded status as licence to re-fuse them.

## Decision

- **The strategy-phase march runs on the GPU simulator, not a separate CPU
  walker.** Units are loaded into the GPU battle buffer and moved by the same
  `COMPUTE_STATE` + `PATHFIND` passes; the CPU positions/animates the `Unit`
  nodes through the existing `GPUVisualBridge` / `GPUMovementInterpreter`. The
  strategy phase is, precisely, "things moving logically in GPU state, displayed
  in CPU" — combat's data-flow with the combat *intent* removed.

- **Deployment is driven by move-to-tile gambits, not a new command path.** Each
  placement hands the placed unit a single absolute-tile move via the existing,
  already-tested gambit-config (`ACTION_MOVE_TO` + packed `DEST_X`/`DEST_Z` —
  `tests/GPUCombatTestBase.gd::make_move_to_gambit`), pushed with
  `GPUBatchSimulator.set_unit_gambits(battle_id, unit_idx, [move_gambit])`.
  Unplaced units carry an **empty gambit set** so they idle. ("Push a tile → the
  unit goes there" is "set that unit's move-to-tile gambit.")

- **No "movement-only" mode and no pass-gating.** We do **not** disable the
  combat passes. With only move gambits in play, no unit ever resolves an
  attack/spell, so `ATTACK`/`SPELL`/`RESOLVE_CONFLICTS`/`APPLY_DAMAGE`/
  `CHECK_VICTORY` run but no-op. The gambit set is the only constraint needed —
  adding a parallel "movement-only" simulator mode would be redundant machinery.
  (Rejected: a sim flag that skips the combat passes.)

- **`start_battle` splits into boot vs go-live.** Booting the simulator, loading
  units into the GPU buffer, and building the distance field move **before** the
  strategy phase. Arming each unit's **real** combat gambits and going fully live
  happen **after** placement completes. This decoupling is what erases the
  two-worlds split: the sim is alive across placement *and* combat; only the
  gambit sets and the "combat is live" intent differ.

- **The sim ticks during placement via the existing tick path.** `CombatLoop.tick`
  gates `step_tick` behind `combat_active`; we widen that gate so the simulator
  also steps during the deployment sub-phase, rather than spinning up a second
  tick loop. Because deployment units only move, widening the gate cannot leak
  combat.

- **The march is a free cutscene with granted jump.** Deployment pathfinding is
  given a generous jump so any authored tile is reachable regardless of a unit's
  combat `jump` (see ADR-0043 for why every authored tile must stay usable).
  Stat-accurate jump applies only once combat goes live.

- **Placement is turn-sequenced on the existing order.** The 1-2-2-1 turn flow is
  unchanged; the CPU issues one move-to-tile gambit per turn and waits for
  `GPUMovementInterpreter` to report arrival (a `NO_MOVE` verdict at the
  destination) before advancing to the next placement.

## Consequences

- One mover, one source of truth. The deployment march inherits the GPU
  pathfinder, step timing, and animation for free; there is no CPU walker to keep
  in sync.
- A reader of `start_battle` finds it **two-staged** (boot/load/distance-field vs
  arm-gambits/go-live). The seam exists so the simulator can span the strategy
  phase — not an accident.
- The **gambit system becomes the single command surface** for both deployment
  ("move here") and combat ("fight"). A unit's placement "AI" is just a
  hand-issued order, not a special subsystem.
- `combat_active` no longer means "the simulator is running" — it means "combat
  intent is live." The simulator can tick with `combat_active` false during
  deployment. Code that conflated the two must read the right axis.
- The placement turn flow now **blocks on movement completion** (arrival), where
  it previously completed instantly. Pacing/feel is a tuning surface, not a
  teleport.
- Rejected alternatives, recorded so they aren't re-proposed: a **CPU walker**
  (duplicates the mover, re-entrenches two worlds, mismatched timing); a
  **movement-only simulator mode** that gates the combat passes (unnecessary —
  the gambit set already constrains behaviour).

## Addendum — the move-to-tile gambit targets a contested tile, not the scenario tile

The decision-body above says "each placement hands the placed unit a single
absolute-tile move via the existing gambit-config" — and implicitly that move's
destination was the unit's *placement* (scenario) tile. The same
pre-implementation grill that reframed ADR-0043 (2026-06-13) re-targets the
march: the scenario tile is now where the unit is **loaded into the GPU buffer**
(its spawn), and the `ACTION_MOVE_TO` destination is the **contested tile** the
player (or `AIPlacementController`) chooses for it. Spawn and destination are
two different tiles; the march is the walk between them.

Concretely, the two-stage `start_battle` split is unchanged, but the stages
now read:

- **Boot stage (before the strategy phase):** boot the sim, load every unit
  into the GPU battle buffer **on its scenario tile** (`set_battle_from_units`
  with the deployment-zone / ENTD positions as initial `(grid_x, grid_z)`),
  build the deploy distance field with granted jump. Units stand on their
  authored tiles, idle (empty gambit set).

- **Deployment sub-phase (the new bit):** per placement turn, push the active
  unit a single move-to-tile gambit whose `DEST_X`/`DEST_Z` are the **chosen
  contested tile**, not the spawn. Wait for `GPUMovementInterpreter` to report
  arrival (`NO_MOVE` at the destination) before advancing the turn. Unplaced
  units keep the empty gambit set and idle on their spawn tiles.

- **Go-live stage (after deployment):** swap each unit's empty/move gambit for
  its real combat gambits and flip combat intent live.

This does **not** change the "no movement-only mode, no pass-gating" decision,
the "free cutscene with granted jump" decision, or the "sim ticks during
placement" decision — only *which tile* the deployment move aims at. The gambit
is still the single command surface ("push a tile → the unit goes there"); the
tile it goes to is the destination the deployment minigame assigns, while the
tile it came from is the scenario's authored spawn. See ADR-0043's matching
addendum for why the scenario tile is a spawn and the contested tile is the
objective.
