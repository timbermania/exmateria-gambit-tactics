# The turn director gates the pump it does not own, and stops on the exact tick

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §1 puts the turn machinery in "a
**component node mounted onto a `CombatLoop`**", not on the host scene and not on
`CombatHost`, and names the consequence that proves the placement: "a **test can
mount the director on a bare `CombatLoop` with no host scene at all.**" §3 gives
it the cycle — freeze, hand off, commit, cancel — and the rule that governs all
of it: "**The clock only ever advances from one turn to the next.**" This file is
that component, built (#891).

Two things the design did not settle, and one it settled wrongly, came out of the
build. It did not say **who pumps** — and the ADR corpus turns out to have already
ruled on that twice, in a direction that makes the director strictly smaller. It
did not say **how precise the stop is**, and at this project's real numbers the
cheap answer is not merely imprecise but wrong by more than a whole turn. And its
`cancel` needed a scope the design left implicit, because two units can hold turns
inside one freeze.

## Status

accepted

## Decision

1. **The director gates; it does not pump, and it is not a second freeze
   authority.** `CombatLoop.tick()` is already the one pump — it owns the
   fixed-step accumulator, and both hosts *call* it rather than each running a
   pump of their own. ADR-0037 dec. 2 is "**One authority, no mirror.**
   `CombatLoop` owns the freeze… There is no autoload, no second copy of the
   state, and no parallel pause flag." So the director drives the existing
   `combat_active` and adds nothing. It is mounted as a child of the loop, but the
   freeze is applied **synchronously from inside the gate call**, never from
   `_process` — a child processes after its parent, so reacting in `_process`
   would make correctness a property of node order that a scene rearrangement
   could silently break.

2. **The stop is EXACT-TICK, through an optional `CombatLoop.turn_gate`
   predicate.** The tick loop drains ~16 ticks in one frame at the 15 fps these
   scenes run, and a Speed-8 unit is ready every **13 ticks** — so a stop checked
   after the frame would routinely run *past a whole turn*, and could arrive with
   two units ready and one of them 20 ticks stale. §3's "the world never moves
   except between decision points" is simply false at frame granularity. The gate
   is consulted **last in each tick-loop iteration**, so the tick that produced the
   crossing is fully applied — state edges, cinematic, projectiles, animation —
   before the world is allowed to stop, and it `break`s rather than returning so
   the frame's per-frame work still runs and the accumulator remainder survives
   into the resume.

3. **The gate costs no readback.** `_read_tick_columns` already pulls its columns
   from one `buffer_get_data` off the version-cached region every tick; the gate's
   two inputs (`turn_meter`, `flags`) join that read and are handed to the
   predicate. The predicate is a scalar scan over two `PackedInt32Array`s that
   allocates nothing; the full `TurnQueue` ordering is paid **once, on the tick it
   stops**, not sixty times a second.

4. **The gate must filter the dead, and that is load-bearing rather than
   defensive.** The kernel stops advancing a dead unit's meter (ADR-0236 dec. 5:
   only death stops the clock), so a unit that dies at or above `TURN_METER_FULL`
   keeps that meter **forever**. Without the dead-bit test the gate would trip
   every tick while `TurnQueue.ready_now` — which does filter — returned nothing,
   and the director would freeze and resume in a loop with no turn to open.

5. **The boundary is signals plus explicit `commit()` / `cancel()`, and the
   director never decides who the player is.** It announces `turn_opened(taker,
   team)` and branches on neither; `team` rides along only because `TurnQueue`
   already carries it. A team-based classification would be wrong at the first
   real roster: `NavigatorMain` composes team0 as owned units **∪ ENTD-blue**, so
   a guest sits on team 0 and is a unit the player may not command. Who is "the
   player" is the mounting host's answer. This is also what makes the bare-mount
   test small — the test *is* the subscriber.

6. **Cancel undoes the EDITS, not the turn.** The snapshot is taken at turn-open,
   **before** `consume_turn`, so `restore_battle` puts the *unspent* meter back and
   the same unit is still ready — cancel therefore **re-opens the same turn**
   rather than resuming. A cancel that spent the turn would make Escape cost you a
   turn. There is no separate "wait" verb: committing with no edits *is* waiting.

7. **One snapshot per TAKER, not per freeze.** Two units can be ready at the same
   stop and take their turns back to back (decision 8). A snapshot scoped to the
   freeze would let a cancel of the second silently revert the first's *committed*
   decision — the same invisible-divergence failure ADR-0235 rejects a lossy round
   trip to avoid.

8. **A freeze DRAINS the ready set, recomputed after each commit.** Resuming the
   world for zero ticks between two simultaneous turns is a distinction with no
   consequence in the sim that every subscriber would still have to handle as a
   spurious resume/refreeze pair. The set is recomputed and never cached, because
   a cached ready list is a claim about a world a `reconfigure_unit` just edited.

9. **Deployment is a state of this machine, and it is the one state that takes no
   snapshot.** §9 calls deployment "a turn with the clock stopped and the CT gate
   removed", so it opens through the *same* signal with `taker == -1` — if it were
   not a state here, the host would build a second freeze path and §9's point (the
   deployment screen is not new UI) would be lost at the first opportunity. It
   holds no snapshot because there is nothing yet to undo: nothing is ticking and
   the units are not in the GPU buffer at all — `boot_battle` is what puts them
   there — so placements are CPU-side and land in one write at commit. Resetting
   them is the deployment screen's business, not a director primitive.

10. **`playback_rate` is a VIEWING rate, and that is a testable invariant, not a
    hope.** An ADR-0068 `static var` home on the director (dec. 13: never a
    `const`, which is frozen at parse time so a scrub could never reach its
    readers), forwarded into a `CombatLoop.playback_scale` that multiplies the
    delta fed to the accumulator. Because the drain is in whole `TICK_INTERVAL`
    steps and the stop is exact-tick, **a between-turn stretch is a fixed number of
    ticks** — it ends when the next unit crosses — so the rate changes only how
    long you spend watching it and can never change an outcome. This is ADR-0065's
    principle (a beat is a function of tick count, not wall clock) holding in the
    combat context that ADR-0065 explicitly left untouched. The rate is landed in
    `_resume` as well as `_process`: the rate a player picks during a turn is the
    rate the *next* stretch should play at, and a harness driving `tick()` by hand
    never renders a frame for `_process` to run on.

11. **The name is `TurnDirector`, not `GambitTurnDirector`** (§1's working name).
    What it directs is turns; the gambit-specific parts — the adjustment UI, the
    rollout driver — are what mount *on* it, and §11 has `NavigatorMain` mounting
    the same object, where "gambit" is not the word for what is happening. It sits
    in `src/gpu/` beside `TurnQueue` and `CombatLoop`. The mild overlap with
    `ScenarioDirectorState`'s scenario-director sense was accepted:
    different domain, and `TurnQueue` / `TurnDirector` read as a pair.

12. **The test mounts on a bare `CombatLoop` with no host scene AND no `Unit`
    nodes.** `TurnDirectorTest` extends `Node3D`, not `GPUCombatTestBase` (which
    *is* a `CombatHost`) — no existing test did this, so the mount is proved by the
    harness's shape rather than asserted about. It goes past what §1 asked because
    `_check_state_changes` and `_read_tick_columns` both clamp their loops to
    `units.size()`: with zero units the whole CPU apply pump is skipped and what
    remains is the sim, the pump and the gate. Every unit holds an empty gambit
    list, so across the run the only unit field that moves is the meter — a battle
    that is a pure clock. Four arms: the exact-tick freeze (one frame is handed 60
    ticks of delta and must stop on the crossing tick, which a frame-granular stop
    would report as 60), commit's carry, a bit-identical cancel over all four
    snapshot slices, and the rate arm. The cancel arm asserts the edit **landed**
    before cancelling it, because a `reconfigure_unit` that changed nothing would
    make the comparison a buffer against itself and the arm would pass having
    proved nothing.

## Considered options

- **The director claims the pump** (hosts stop calling `tick()`; the director's
  own `_process` drives it). Rejected: it makes the director a third thing able to
  advance `COMBAT`-owned bodies, which is exactly the condition ADR-0083 dec. 1
  designed away by giving each unit clock exactly one owner so the double-pump is
  "**structurally impossible — not toggled off, but expressed away**". It also
  requires editing `CombatHost`, `GPUArena` *and* `NavigatorMain`, each with an
  "is a director mounted?" check — the third duplication §1 exists to prevent.

- **Unify the pump properly: one clock authority over both call sites.** This is
  the honest version of the question, and ADR-0083 already weighed it: "**A single
  clock authority** that owns all units and delegates to VM/CombatLoop drivers.
  Cleanest conceptually, largest blast radius; over-engineered for a two-pump
  system. Noted and set aside." Its premise is the count, and this decision
  *preserves* the count — the director adds zero pumps — so the set-aside stands
  unamended. Not re-opened here because folding `CombatHost`, `GPUArena`,
  `NavigatorMain` and `ScenarioVM` into one authority would make #891 a pump
  refactor rather than a director. Recorded on map #886 as fog.

- **`Engine.time_scale` as the playback rate.** Rejected twice over: ADR-0037
  dec. 1 rules combat pause combat-scoped and not engine-scoped ("Nothing on the
  combat path writes `get_tree().paused`"), and the test harness already owns the
  knob — `NavigatorGarilandVictoryTest` sets `Engine.time_scale = SIM_TIME_SCALE`
  and `ProjectileManager` deliberately decouples its flight from it.

- **A frame-granular stop.** Rejected by measurement, not by taste: 16 ticks a
  frame against a 13-tick turn.

- **An injected per-side strategy object** (`take_turn(context) -> edits`) instead
  of signals. Not rejected on merit — it can be layered on top of the signals
  later without touching the director — but it would have made the bare-mount test
  build a strategy double to prove the cycle, when the signals let the test be the
  subscriber directly.

- **`taker` as a new word.** Rejected: `TurnQueue.forecast` already spells it that
  way, and a second word for the same thing is how a glossary rots.

## Consequences

`CombatLoop` grows exactly three things: `playback_scale` (a multiply),
`turn_gate` (an optional `Callable`, unset everywhere today except under a
director), and two more lean per-tick columns on a read it already performs.
Neither host changes, and with no director mounted the loop's behaviour is
byte-for-byte what it was — `playback_scale` defaults to 1.0 and an invalid
`Callable` is never called.

The gate is a general per-tick stop hook, and Active mode (§3's "the same machine
that simply does not stop") is therefore a *policy* change inside the predicate
rather than a rewrite — which is what "must not need a rewrite" was asking for.

`_read_tick_columns`'s docstring counted its own outputs; that count moved from
five columns / four outputs to seven / five.

The rollout fleet's candidate battles have no director: `battle_id` scopes one
director to the real battle, and only the real battle has turns.

**The tick-to-turn rate is still open**, and this build does not close it. The
director makes the between-turn stretch playable, but at 60 ticks/sec a Speed-8
unit is ready every 0.22 s, which is not a pace any playback rate makes readable.
Which lever moves — the playback rate, a tick divisor on the meter, or
`TURN_METER_FULL` itself — needs #892 to exist and somebody to feel it. Carried on
map #886, where ADR-0236 first recorded it.
