# GambitBattle — settled design

**Status:** design settled 2026-09-05 in a `/grill-me` session; **nothing built**.
This document is the input to a wayfinder map, not a record of work done. Every
statement below is a decision the user made and confirmed, or a fact read out of
the tree at the paths cited. It carries no ADR number yet — ADRs get written as
the wayfinder resolves its tickets.

---

## Destination

A second combat mode, **GambitBattle**, beside `GPUArena`: FFT's CT turn order
over the existing GPU rules kernel, where **a turn is a reconfiguration, not an
action**. Continuous gambit-driven combat fills the space between turns; the
player steers by editing gambits; the enemy steers by running massively parallel
rollouts of its own candidate gambit edits and picking the one that maximises
P(victory).

---

## The reframe this design came from

The engine is **already turnless**. `GPUBatchSimulator` (`src/gpu/`) is a
double-buffered per-tick sim: every unit reads one snapshot, decides in parallel,
writes the next. No turn order, no CT-to-act gate. Units run continuously off
gambits, rate-limited by `U_CAST_TIMER`, animation, and per-ability cooldowns
(ADR-0047). "Everyone fights at once at a manageable speed" is therefore the
*current* system.

What is new is a **control layer**: a CT gate on player adjustments, a deliberate
time scale, a speculative-rollout enemy, and real deployment. **The combat rules
kernel does not change.**

---

## Load-bearing facts read out of the tree

| Fact | Where | Consequence |
|---|---|---|
| `set_unit_gambits(battle_id, unit_idx, gambits)` is a live per-unit `buffer_update` | `src/gpu/GPUBatchSimulator.gd:1349` | Mid-battle gambit swaps already work. |
| `set_battle_units` takes **configs, not a snapshot**, and rewrites the unit's whole block in **both** ping-pong buffers | `GPUBatchSimulator.gd:856` | There is no fork-the-live-battle path today. This is the gap the keystone primitive fills. |
| The cooldown SSBO is **separate and single-buffered** | `GPUBatchSimulator.gd:925` | Must be covered by the round-trip or the AI forks into a different world. |
| `step_tick` dispatches over **all** battles | `GPUBatchSimulator.gd:1100` | Scratch battles cannot advance without the live one advancing too. |
| `MAX_UNITS_PER_BATTLE = 8` is **declared and never referenced** by any shader | `src/gpu/shaders/combat_common.glslinc:28` | Vestigial, not an enforced cap. The real shape is `CombatLoop.units_per_battle`, runtime-set. |
| Teams split at the **midpoint**; `GPUArena` sets `units_per_battle = 2 * max(t0, t1)` | `src/scenes/GPUArena.gd:174` | An asymmetric battle allocates padding, and rollout compute scales with **allocated** slots. |
| ATTACK.OUT `@ 0x10938` is the scenario table (480 records × 24B): map, weather, night, 2 songs, `entd_idx`, both squad deployment idxs, Ramza-mandatory flag, `battle_conditionals_id` | `research/wiki_articles/attack_out_scenario_table.md`, parsed to `assets/scenarios/scenarios.json` | One `scenario_id` boots a whole battle. |
| Deployment zones are the **other** ATTACK.OUT table (`0xBBD4`, 768 × 12B, start tiles + facing) | `src/data/DeploymentZoneDatabase.gd` | **Player** start tiles only. Enemy placement is ENTD per-slot coords. |
| BattleConditionals live in `EVENT/BTLEVT.BIN`, already extracted and already interpreted | `src/data/BattleConditionalDatabase.gd`, `src/scenarios/ScenarioDirector.gd` | Victory conditions are not a missing system — they need one class: a combat-backed `ScenarioDirectorState`. |
| The ROM's own `Victory` opcode (`0x80183374`) **is** annihilation: ≥1 player standing, 0 enemies standing | `src/scenarios/ScenarioDirectorState.gd` | Annihilation-as-engine-rule is the real model, not a v1 compromise. |
| `ScenarioDirectorState` already declares `is_active_turn(unit_id)`, which nothing can answer | `src/scenarios/ScenarioDirectorState.gd:50` | The CT turn machine fills a hole the director was written against. |
| `NavigatorMain` does **not** mount `GPUArena` — it builds a bare `CombatLoop` on live world units and mirrors the `CombatHost` pump by hand | `src/scenarios/NavigatorMain.gd:1452`, `:473`, `:158` | There are already **two** duplicating CombatLoop hosts. They disagree on the pause key (Tab vs Space, `:1141`). GambitBattle must not become the third. |

---

## Decisions

### 1. Architecture

- **New host over the same kernel.** No shader fork of the combat rules.
- The machinery — turn queue, freeze/handoff/commit cycle, adjustment UI mount,
  AI rollout driver — lives in a **component node mounted onto a `CombatLoop`**
  (working name `GambitTurnDirector`), **not** on the host scene and **not** on
  `CombatHost`.
  - Not on the host scene: `NavigatorMain` would replicate it a third time.
  - Not on `CombatHost`: `NavigatorMain` deliberately does not extend it.
  - Consequence: `GambitBattle` is a thin standalone host (boot + deployment),
    `NavigatorMain` mounts the same director in one line, and a **test can mount
    the director on a bare `CombatLoop` with no host scene at all.**
- The **snapshot/restore primitive belongs on the simulator layer**, not on any
  host, so both hosts, the rollouts, and the tests inherit it.
- `GambitBattle` is a new host scene beside `GPUArena`, not a mode flag on it —
  `GPUArena` has three subclass tests (`GPUThrashTest` / `GPUTeleportTest` /
  `GPUItemFallthroughTest`) reading state off it, and a second rules model would
  fork all of them.

### 2. The keystone: a lossless state ⇄ config round-trip

**Build this first. Everything else is downstream.** One primitive serves the
mid-turn CPU handoff, the enemy's fork, undo-on-cancel, and (free) battle
save/load.

Gated on a **bit-identity test**: `snapshot → restore → run N ticks` must be
bit-identical to running N ticks without the round trip. It must cover both
ping-pong buffers, the separate cooldown SSBO, `U_CAST_TIMER`, animation frame,
`U_DECISION_META` (incl. the thrash counter), and RNG stream position.

A lossy round trip was **rejected**: the enemy AI would fork into a world that
differs from the one it is advising on, and that divergence is invisible — it
presents as an AI that is subtly, unaccountably bad.

### 3. The turn model

- **CT is a GPU unit field**, advanced `CT += Speed` per tick by the shader — not
  a CPU accumulator. It therefore round-trips for free, is correct inside every
  rollout battle, and is visible to the value function ("who is about to act" is
  a real feature of a position). A CPU clock would be a second copy that drifts.
- Act at 100; **`CT -= 100`, carrying the remainder** (reset-to-0 quantizes turn
  spacing and drifts fast units off their true Speed ratio).
- **Seeded-random initial CT in [0,100)**, derived from the battle seed so
  rollouts reproduce. All-zero starts lock equal-Speed units in lockstep.
- Ties break **deterministically**: team, then unit index. Nothing random — the
  AI's rollouts must be reproducible.
- A unit **mid-cast still gets its turn**. The turn is a reconfiguration; mid-cast
  is exactly when you want to re-tune what happens next. Blocking it would also
  make the turn queue non-computable and break the forecast (§6).
- **The clock only ever advances from one turn to the next.** Combat is genuinely
  simultaneous and continuous inside each slice, but the world never moves except
  between decision points. "Manageable speed" is set by CT rates, not wall clock.
- **Turns freeze the world symmetrically.** Player turns open the UI; enemy turns
  get a cinematic focus beat — which is where the rollout compute hides.
- Between turns the world plays at a **tunable rate** (ADR-0068 `static var`, not
  a `const`) with 1x/2x/4x and hold-to-skip. Not instantaneous: the between-turn
  stretch is where the consequences of the player's gambits become visible, and
  skipping it severs the feedback loop.
- **Wait mode first.** Active mode is the same machine that simply does not stop
  at the next turn (or stops with a shot clock).

### 4. Adjustments

- On your turn you edit **only the unit whose turn it is**. Under any wider rule
  your fastest unit becomes a universal remote and every other CT bar is
  decoration; this is also what makes deployment a real decision, since you are
  choosing how much steering bandwidth you will have.
- **All adjustment types legal** (gambits, equipment, job, ability slots). The
  lossless round-trip is what makes this possible at all — equipment and job
  changes have no live GPU write path.
- Edits apply **on commit**; **cancel restores the pre-turn snapshot** (free —
  the snapshot primitive is the undo buffer). **Cancel must refund any imperative
  charge spent that turn**, or cancel becomes a trap.
- **Equipment changes clamp** HP/MP to the new max, never scale — scaling makes
  toggling a +HP item a free heal.
- **Job changes auto-prune** gambit slots referencing abilities the new job can't
  use, **and show what was pruned**. Rejecting makes the UI argue with the player;
  silent no-op slots are worse, because a gambit list that looks armed and isn't
  is the most confusing failure this design can produce.
- The UI is the new `ui3` formation screen (a separate agent is building it; it
  gains gambit editing during this work).

### 5. Imperative gambits

A one-shot, top-priority "lock-on" entry that self-removes.

- **Removed host-side** on the existing `CombatLoop.action_committed` signal, or
  by **watchdog** when it becomes uncompletable: target dead/removed, or N ticks
  elapsed without a commit. Deliberately **no cleverer predicate** (reachability,
  LOS, affordability) — those duplicate shader logic on the CPU and the two copies
  will disagree; a watchdog cannot disagree with anything.
- **No refund** on watchdog expiry: a wasted lock-on is a real mistake.
- **Finite charges, per unit per battle**, from a `Tune` constant now
  (ADR-0068 tunable), job-derived later.
- **Independent of the turn's gambit edit** — charges are already the scarcity;
  double-taxing makes the imperative feel bad to use at all.

### 6. Turn queue forecast

Shown **one full round-robin deep**: extend the queue until every living unit
appears at least once. Self-scaling, so a slow unit's long wait is visible rather
than implied, and exactly computable from CT arithmetic alone with no battle
simulation. Wrong only under Haste/Slow, deaths, or reinforcements — the same
caveat every turn-queue game carries.

### 7. The enemy AI

On an enemy turn: **snapshot battle 0, fill the fleet with K candidates, run,
restore battle 0.** No shader change and no per-battle active mask needed — the
live battle is already frozen during a turn, and the restore is the keystone
primitive's second consumer (so the bit-identity test guards the thing the AI
depends on). Upgrades to a widened `1 + K` simulator with an active mask if
Active mode later needs rollouts to overlap live play.

- **One ply.** Every unit's gambits are frozen for the whole horizon; rollouts do
  **not** run the turn machine. This is the user's own stated assumption ("assuming
  no one else changes their gambits at that point in time") and is what makes it
  tractable.
- **Candidate set** = one-step **mutation operators on the unit's current gambit
  list** (swap slot priority, replace a condition, replace an action with another
  learned ability, delete a slot, insert one) **+ a per-job authored playbook**
  (to be expanded) **+ imperative-issue** when charges remain. Mutation alone gets
  stuck refining a posture it can never abandon; a playbook alone caps the AI at
  what was authored. Legality prefilter reuses `spell_pre_validate` /
  `cooldown_pre_validate` — that is the "common sense" pruning, not new judgment.
- **Common random numbers**: the *same* M seeds across all K candidates, so
  candidates differ only by the gambit change and luck cancels in the comparison.
  Large variance reduction at zero cost; also makes the AI's choice reproducible.
- **Budget** `K × M × H` derived from a measurement, not picked. Starting shape to
  measure against: K ≈ 32–64, M ≈ 4, H ≈ 300 ticks. Hard wall-clock cap on the
  thinking beat with **graceful degradation in a fixed order: drop M first, then
  K, never H.** A shortened horizon systematically biases toward immediate damage
  — the AI stops seeing heals and repositioning pay off — whereas fewer seeds only
  adds noise. Bias is worse than variance.
- **Multi-ply / MCTS is an explicit non-goal.** A genuinely good idea and a
  genuinely good way to never ship this mode.

### 8. Calibration

**H and f are substitutes.** At `H → ∞` no formula is needed (you observe the
winner); at `H → 0` the formula carries everything. Every tick simulated is a tick
not predicted. So `(H, f)` is one joint choice trading compute against predictive
error, and neither can be picked alone. Ground truth for both is the same thing:
**recorded outcomes of battles played to completion** — which makes this a
data-fitting problem, not a game-design one.

A tournament of weight vectors was **rejected as the instrument**: it scores the
whole AI, so it cannot say whether a bad result came from f, from H, or from the
mutation set. Scoring f against known winners measures f alone.

- **f predicts P(victory)**, so the terminal win/loss bonus **disappears** — the
  score *is* the probability of winning, already calibrated, already comparable,
  needing no hand-tuned weight to make winning outrank having more HP.
- **Logistic regression** over a few hand-picked features (HP fractions, standing
  counts, MP, aggregate distance-to-enemy). Chosen for **readable coefficients** —
  when the AI does something stupid you can see which term did it — not for speed:
  f runs ~K×M ≈ 256 times per turn at the horizon, not per tick, so a boosted tree
  would also be affordable. Escalate only if the H-sweep shows the linear model
  cannot separate positions.
- Fitted coefficients ship as a **committed JSON artifact emitted by a `tools/`
  script**, the same pattern as `deployment_zones.json` and
  `battle_conditionals.json`.
- **Corpus** played by the current gambit AI with adjustments disabled. **One
  refit** after the real AI ships (it changes the position distribution it was fit
  to). One refit, not a loop — self-play refinement is a research project.
- **Sample only at the states the AI will actually query** (H ticks after an enemy
  turn), and **stratify by remaining battle length**: a predictor scored across all
  states looks excellent by nailing trivially-decided endgames while being useless
  in the mid-game where decisions matter.
- **Metric: log-loss**, not accuracy — accuracy cannot distinguish a confidently
  wrong predictor from a hedging one.
- **The tool's primary deliverable is the accuracy-vs-cost table across
  H ∈ {100, 200, 400, 800, …}**; pick the knee under the wall-clock cap.
- Predicted failure worth pre-empting: with HP-only terms the AI will never heal,
  buff, or reposition, because those score zero at the horizon. If calibration
  produces a suicidally aggressive AI, **that** is the cause, and the fix is a
  term, not a weight.
- The harness is a `tools/` script, not a test, and wants its own roster path
  (ADR-0180 retired the arena's rosters).

### 9. Deployment

ENTD offers n units, the ATTACK.OUT zone offers m tiles; **the player assigns
which unit goes on which tile and configures it.** Mechanically this is **a turn
with the clock stopped and the CT gate removed** — so the deployment screen is
not new UI, it is the turn UI in a different mode. Auto-fill survives as a
test/debug path (mirroring the existing `--combat-autostart` /
`simulation.skip_march` pattern).

Enemies spawn at their authored ENTD coords. Honour the ATTACK.OUT flags bit 0
(*Ramza mandatory during deployment*). `second_squad_deployment_idx` is out of
scope for v1.

### 10. Boot and victory

- Boot from a **`scenario_id`**, which hands over map, song, weather, cast, and
  both deployment zones from one integer. `GPUArena.default_scenario_id = 9`
  already does a thin version of this.
- **Annihilation ends the battle** — the ROM's own rule, not a compromise.
- Boot path is **scenario-agnostic from day one**, so "which scenarios" stays a
  roster/config question rather than a code question. Develop against **Gariland
  (scenario 9)**; let the H-sweep measurement set the ceiling. **Do not hardcode a
  size cap** — a cap discovered by measurement belongs in a tunable, not a guard.

### 11. Must plug into `NavigatorMain`

`GambitBattle` must drop into the `NavigatorMain` walk the way combat does today.
Given that NavigatorMain runs a **bare `CombatLoop`** (not `GPUArena`), this is
exactly the requirement that forces §1's component-node decision.

---

## Explicit non-goals

- **No rollout advisor for the player.** Written into the ADR as a non-goal rather
  than silently omitted: if the player can query the same oracle the enemy uses,
  the game collapses into "whoever's value function is tuned better," and every
  interesting decision becomes a button press. It will be tempting to add once the
  machinery exists.
- **No multi-ply / MCTS search.**
- **No `BattleConditionals` wiring in v1** — though it is now one class away (a
  combat-backed `ScenarioDirectorState`, which the CT clock also finally lets
  answer `is_active_turn`).
- **No `second_squad_deployment_idx`.**
- **No Active (real-time) mode in v1** — the machine is built so it is a later
  switch, not a rewrite.

---

## Suggested build order (dependency order)

1. **Lossless state ⇄ config round-trip on the simulator + the bit-identity test.**
   The keystone; nothing else is safe until this is green.
2. **CT as a GPU unit field**, turn queue, deterministic tiebreak, seeded initial CT.
3. **`GambitTurnDirector`** component: freeze / handoff / commit / cancel, mounted
   on a bare `CombatLoop`. Test mounts it with no host scene.
4. **`GambitBattle` host scene**: boot from `scenario_id`, deployment assignment
   and per-unit config, auto-fill debug path.
5. **Adjustment UI integration** (new `ui3` formation screen) + imperative gambits
   + charges + clamp/prune rules.
6. **Turn queue forecast HUD.**
7. **Rollout harness**: snapshot/restore battle 0, K candidates, CRN seeds,
   mutation operators + job playbook.
8. **Measurement ticket**: ticks/sec at K battles → the budget.
9. **Calibration tool**: corpus, logistic fit, H-sweep table → committed JSON.
10. **Wire the AI** to the fitted model with the budget and its degradation order.
11. **`NavigatorMain` mounts the director.**
12. Later: combat-backed `ScenarioDirectorState`, fleshed-out deployment UI,
    Active mode.

---

## Open items deliberately deferred (not fog — decided to defer)

- Imperative charge count as a job-derived value rather than a `Tune` constant.
- Expanding the seeded job playbook (the user flagged this as needing growth).
- Reinforcements / units joining mid-battle (changes allocated slot count).
- Reconciling the `GPUArena` (Space) vs `NavigatorMain` (Tab) pause-key
  disagreement.
