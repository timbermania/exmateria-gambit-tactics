# A unit's animation clock has exactly one owner; scenario→battle is an ownership handoff

## Status

Accepted (2026-08-06)

Amends [ADR-0082](0082-command-mode-is-one-frozen-navigable-battle-state.md)
(retires `battle_frozen` as the double-pump guard) and extends
[ADR-0020](0020-unit-animation-uses-one-clock-per-unit.md) /
[ADR-0065](0065-scenario-time-advances-on-one-vblank-quantized-tick.md) across
the ScenarioVM ↔ CombatLoop boundary.

## Context

Two systems call `Unit.advance_frame()`, and in `NavigatorMain` they run over the
**same** `Unit` node instances (decision #180: combat runs on the world units the
scenario built):

1. **`ScenarioVM._advance_scenario_anim`** — once per VM tick, advances every unit
   in `units_by_id` and `idle_only_units`.
2. **`CombatLoop.tick`** — once per sim tick, advances every unit in `units`.

`AnimationClock.tick_based` (ADR-0020's "one clock per unit") answered *"does
`Unit._process` self-pump on delta, or does a host pump me?"* — but it did **not**
name *which* host. So when both pumps ran over one unit, nothing on the unit said
which pump owned it, and each combat body advanced ~2×/frame during live combat.

This double-pump was the shared root of two separately-patched bugs:

- **ADR-0082 pause idle-walk leak** — a *paused* battle kept idle-walking because
  the VM pump was ungated by `combat_active`.
- **Missing melee hit-cloud traps** — *live* combat double-advanced bodies, racing
  the SEQ `0xDE` / PostGenericAttack opcode ahead of the GPU damage tick so
  `is_hit` read stale data and the trap cloud never spawned.

Each was patched with `ScenarioVM.battle_frozen`, a **single global boolean** that
freezes the *entire* VM pump whenever any CombatLoop owns bodies (Live **or**
Paused). It is correct today only because the registries overlap totally
(`units_by_id ∪ idle_only_units == CombatLoop.units`), so "freeze the whole VM
pump" happens to equal "freeze the combat units." It is a coarse all-or-nothing
gate standing in for what should be **per-unit ownership**, and it breaks the
moment a battle has a non-combatant scenario NPC (an onlooker, a caged Ovelia, a
scripted background actor) that should keep breathing during live combat.

## Decision

The three rules below were unnumbered bold paragraphs until this ADR's audit;
numbered headings were added — prose unchanged — so `ADR-0083 dec. N` citations
resolve. Amendment 1 grades each one against the tree.

### Decision 1 — one owner enum on the clock, and `tick_based` folds into it

**A unit's animation clock has exactly one owner** — an enum on `AnimationClock`:

- `SELF` — delta-driven (`Unit._process` pumps `AnimationClock.tick(delta)`);
  free-roam smoothness.
- `SCENARIO` — the `ScenarioVM` body pump owns it (openers, cutscenes, deployment
  idle-breathe).
- `COMBAT` — the `CombatLoop` tick owns it (live combat, GPUArena).

`tick_based` (host-pumped vs delta) collapses into the derived predicate
`owner != SELF`, read-only. There is now **one** clock axis with three values, not
two independent flags. Each pump drives **only** the units it owns:

- `ScenarioVM._advance_scenario_anim` **skips `COMBAT`-owned units** and claims any
  `SELF`-owned scenario unit it encounters (preserving the `{47}` mid-run
  ghost-spawn claim).
- `CombatLoop` iterates only its own `units`, so it never touches a scenario NPC —
  no filter needed there beyond the handoff.

### Decision 2 — the scenario→battle transition is one explicit handoff at `_go_live`

**The scenario→battle transition is one explicit ownership handoff.** At `_go_live`
(Deployment → Live, or a direct-seek build) `NavigatorMain` flips every
`CombatLoop.units` member `SCENARIO → COMBAT`, co-located with `combat_active = true`
and the ADR-0042 gambit arm. This is the single edge where a body changes clocks;
teardown frees the units (implicit revert). Because ownership is set once at the
handoff and persists across Pause/resume, the double-pump is **structurally
impossible** — not toggled off, but expressed away.

### Decision 3 — Pause stays a full freeze-frame, through a narrowed `survey_frozen`

**Pause is still a full freeze-frame**, via a narrowed flag. `survey_frozen`
(renamed from `battle_frozen`) is now responsible for **one** thing: during a
command-mode Pause, halt the `SCENARIO`-owned body pump so ambient scenario NPCs
freeze too. (`COMBAT`-owned bodies are already frozen by `combat_active = false`.)
It is set **only** in the Live → Paused transition and cleared on Paused → Live and
at **go-live** — it is a presentation freeze, no longer the mechanism that prevents
the double-pump. (`_set_survey_freeze` has exactly two call sites: `_set_combat_live(live)`
passes `not live`, which is the Live↔Paused pair, and `_go_live` clears it. `_go_live` is
the Deployment → Live *edge*, not Deployment; the flag is never written at Deployment in
either direction, and the code says so: *"A subsequent Live→Paused sets it; Deployment
never does."*)

## Considered options

- **Keep the global `battle_frozen` toggle.** Works while every VM-registered unit
  is also a CombatLoop unit; cannot express "this NPC is a non-combatant, keep it
  breathing during live combat." Rejected — it is the coarse gate this decision
  replaces.
- **Exclusive membership / skip-set** — have the VM pump skip any unit present in
  the live `CombatLoop.units` set. Cheaper diff, but the ownership lives in a
  membership test the VM must reach into CombatLoop for, rather than on the unit
  itself; less explicit, and it re-answers "who owns time" per frame instead of at
  the handoff. Rejected in favor of a named owner on the clock.
- **A single clock authority** that owns all units and delegates to VM/CombatLoop
  drivers. Cleanest conceptually, largest blast radius; over-engineered for a
  two-pump system. Noted and set aside.
- **Additive owner tag layered over an untouched `tick_based`.** Lower risk, but
  keeps two fields encoding one axis (`SELF` ⟺ `tick_based == false`), inviting the
  drift where `owner == COMBAT` but `tick_based == false` opens a *third* (`_process`)
  pump. Rejected in favor of folding `tick_based` into the derived predicate so the
  inconsistent state is unrepresentable.

## Consequences

- The double-pump cannot recur: the VM pump skips `COMBAT`-owned bodies
  unconditionally, so no `battle_frozen` write can be forgotten at a transition
  edge.
- A future non-combatant battle NPC left `SCENARIO`-owned keeps breathing through
  live combat — the case the global toggle could not express.
- The scattered `battle_frozen` writes (`_go_live`, `_set_combat_live` ×2) collapse
  into **one** ownership handoff at `_go_live` plus the narrowed `survey_frozen`
  toggle for Pause. "Units only ever ride one of the two clocks" is now an
  invariant of the data model, not a discipline about when to freeze.
- `Unit.tick_based` is read-only (derived from `clock_owner`); the sites that set it
  migrate to naming their host (`clock_owner = COMBAT` / `SCENARIO`). GPUArena and
  the GPU test base name `COMBAT`; scenario/deployment sites name `SCENARIO`. **Nine**
  assignment sites, measured: `SCENARIO` ×4 (`ScenarioWorld.gd:409`,
  `NavigatorMain.gd:899`, `ScenarioVM.gd:1040`, `ScenarioVM.gd:3528` — the mid-run
  claim); `COMBAT` ×2 production (`NavigatorMain.gd:1338` the handoff, `GPUArena.gd:320`)
  plus ×3 harness (`GPUCombatTestBase.gd:298`,
  `gambit_runner/GambitScenarioRunner.gd:256`, and `ScenarioUnitAnimLatchTest.gd:55`
  naming `SCENARIO`). The ADR predicted ten; ten counted the old `tick_based` setters,
  a different set, not a missing migration.
- Standalone paths degrade cleanly: GPUArena units are `COMBAT` from boot (no VM →
  no double-pump possible); pure-cutscene units are `SCENARIO` (no CombatLoop).
- **The invariant is guarded** by `NavigatorLiveCombatDoublePumpTest` (a
  `COMBAT`-owned body advances exactly once during Live while a `SCENARIO`-owned
  ambient NPC keeps breathing) and `NavigatorCommandModePauseFreezeTest`
  (`survey_frozen` freezes the ambient pump on Pause, thaws on resume;
  `COMBAT`-owned bodies never double-advance). `NavigatorDeployedIdlePumpTest`
  pins that deployed units breathe during Deployment (`SCENARIO`-owned, no
  survey freeze). **Eleven** test files cite this ADR, not three — those plus
  `ScenarioClockUnificationTest`, `ScenarioCombatPoseCarryTest`,
  `ScenarioSteppingConsistencyTest`, `ScenarioDeadUnitFadeTest`,
  `ScenarioUnitAnimLatchTest`, `GPUCombatTestBase` and the runner script. Each of the
  three named carries a duck-typed `Unit` stand-in mirroring the real shape —
  `clock_owner` settable, `tick_based` derived — so they fail if `tick_based` regains a
  setter.


## How it stands in the tree

Where each decision lives, so a reader can check it rather than trust it. Line numbers
drift; the identifiers do not.

| Dec. | Where to look |
| --- | --- |
| 1 | `AnimationClock.gd:35` is `enum Owner { SELF, SCENARIO, COMBAT }`; `:36` holds `owner`; `:42-43` is `var tick_based: bool: get: return owner != Owner.SELF` — **getter only, no setter**, so `owner == COMBAT and tick_based == false` is unrepresentable. `Unit` mirrors it: `clock_owner` (`:147-151`) is a get/set facade over `display.anim_clock.owner`, `tick_based` (`:157-158`) is getter-only, and `Unit._process` (`:1225`) reads it to no-op its delta pump. This is why the rejected "additive owner tag over an untouched `tick_based`" option was rejected. |
| 1 | The VM's per-unit filter is `_advance_unit_body_clock` (`ScenarioVM.gd:3520-3531`), called from `_advance_scenario_anim` (`:3478`): `return` on `COMBAT` (`:3525`), claim on `SELF` (`:3528`, naming the `{47}` ghost spawns). |
| 2 | `NavigatorMain._go_live` runs `arm_combat_gambits` → `_hand_off_clocks_to_combat()` → `combat_active = true`, in that order in that function. `_hand_off_clocks_to_combat` is called from **exactly one place** — which is what "the single edge where a body changes clocks" means. Its counterpart edge is the handback; see the Amendment below. |
| 3 | `ScenarioVM.gd:82` declares `survey_frozen`; `:3483` is its **only** read — an early `return` at the top of `_advance_scenario_anim`, above both loops. `battle_frozen` survives nowhere as an identifier; every remaining occurrence is prose recording what it used to be. |

### Two stale verbs in the code

`ScenarioVM.gd:1031` (*"Flip every registered unit to `tick_based` on scenario entry"*)
and `:3471` (*"are flipped to `tick_based` on `start()`"*) both describe what is now a
`clock_owner = SCENARIO` assignment nine lines below. `tick_based` cannot be flipped — it
has no setter. Harmless, but they are the two places a reader would learn the retired verb.

### Open question — what happens when the handoff's setter no-ops?

`Unit.clock_owner`'s setter is **silently a no-op while `display` is null**
(`Unit.gd:149-151`), and `_hand_off_clocks_to_combat` documents this: *"Units too raw to
own a clock (no `display` yet) no-op their setter, same as before."* But that function is
called from exactly one place and never again, so such a unit stays `SELF` past the
handoff — and the next VM tick reaches `_advance_unit_body_clock`, sees `SELF`, and
**claims it for `SCENARIO`** (`ScenarioVM.gd:3527-3528`). A `CombatLoop.units` member
would then ride the scenario clock permanently.

Two readings, and nothing in the tree settles which:

1. **Unreachable.** Every `CombatLoop.units` member is `_ready` (so has a `display`) by
   the time `_go_live` runs; the no-op branch exists only for bare-`Unit` test harnesses,
   exactly as its comment says.
2. **Reachable and silent.** If any spawn path can put a not-yet-`_ready` unit into
   `CombatLoop.units` before `_go_live`, the claim re-creates precisely the single-owner
   violation this ADR exists to prevent — no warning, no test, and a symptom identical to
   the double-pump bug that motivated it.

No test covers a raw unit crossing the handoff, and the claim at `:3528` is unconditional
on the unit's membership.

### What is left to mechanize

- **The claim's blind spot.** Make `_advance_unit_body_clock` refuse to claim a member of
  a live `CombatLoop.units`, or assert after `_hand_off_clocks_to_combat` that every
  member reports `COMBAT`. The second is a one-line addition to
  `NavigatorLiveCombatDoublePumpTest`, which already asserts both stand-ins are `COMBAT`
  after the handoff (`:129`) — it just does not exercise a unit whose setter no-ops.
- **`tick_based` has no setter.** A text arm asserting no `.gd` assigns `tick_based`
  locks in the fold that makes the bad state unrepresentable. It passes today and is the
  cheapest of the three.

## Amendment 1 — dec. 2's parenthetical is false on the victory beat, and Amendment 1 graded it correct

_2026-09-09, from a grilling of four player-reported bugs on Orbonne._

Decision 2 ends: *"This is the single edge where a body changes clocks; **teardown
frees the units (implicit revert)**."* The bolded clause is the premise, and
decision #180 refutes it.

`NavigatorMain._end_combat_and_advance` frees the `CombatLoop` and hands the walk to
the **victory beat, which plays on the same live world** — the units are not freed.
`clock_owner = ClockOwner.COMBAT` is written in exactly one place
(`_hand_off_clocks_to_combat`) and `ClockOwner.SCENARIO` in exactly one other
(spawn). So after a battle ends, every survivor is still `COMBAT`-owned with no
`CombatLoop` left to tick it, and `_advance_scenario_anim` skips it **by design** —
dec. 1's owner filter working exactly as specified.

The player-visible result is that scenario 6's opcodes move the survivors and nothing
animates the move. **They teleport.** `NavigatorMain.play_beat` already carries
`preserve_combat_poses` for that beat, so the *pose* half of the carry was thought
about and the *clock* half was not.

**Amendment 1 graded dec. 2 "yes, exactly as written."** It was right about the
mechanism — the handoff is one edge, called from one place — and it did not read the
parenthetical as a claim. A clause that names an *implicit* behaviour is exactly the
kind an audit checking explicit call sites will pass over.

### What changes

The revert becomes **explicit and symmetric**: a `_hand_off_clocks_to_scenario()`
co-located on the handback edge, mirroring `_hand_off_clocks_to_combat` on `_go_live`.
Read dec. 2's last clause as *"the reverse handoff is the counterpart edge; teardown
frees the units only when there is a teardown."*

**Deliberately not adopted:** deriving `clock_owner == COMBAT` from live-`CombatLoop`
membership, which would make the revert structural. That is this ADR's rejected
*"exclusive membership / skip-set"* option, and the rejection still stands on its own
argument — ownership belongs on the unit, answered at the handoff, not re-derived per
frame. A symmetric second edge is the smaller change and keeps dec. 1 intact.

**Not guarded yet.** `NavigatorLiveCombatDoublePumpTest` asserts the forward handoff;
nothing asserts the reverse, because until now there was no reverse to assert. The arm
is the mirror of the one at `:129` — after the handback, every surviving unit reports
`SCENARIO`.
