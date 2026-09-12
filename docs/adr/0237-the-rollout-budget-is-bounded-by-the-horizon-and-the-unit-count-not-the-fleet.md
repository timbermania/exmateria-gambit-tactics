# The rollout budget is bounded by the horizon and the unit count, not by the fleet

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §7 sizes the enemy's search as
`K × M × H` — `K` candidate gambit edits × `M` common-random-number seeds × `H`
ticks of horizon — and says the budget is "derived from a measurement, not
picked". §8's whole calibration deliverable is an accuracy-vs-cost table read
under a wall-clock cap. This file is the cost side of both, measured.

It also inverts the framing they were written in. §7 assumes the fleet is what
costs, and prescribes a degradation ladder that drops `M` first, then `K`, and
never `H`. The measurement says the fleet is nearly free and the horizon is the
only lever with a superlinear price — so that ladder has almost nothing to
recover, and the real ceiling is set by `H` and by `units_per_battle`, neither
of which the AI gets to choose.

## Status

accepted

## The measurement

`tests/GPURolloutBudgetBench.tscn` (`GPURolloutBudgetBench.gd`), a
`[NOT_A_TEST]` rig that asserts nothing. NVIDIA RTX 5090, 29.5 GB free, GPU
otherwise idle; `ProceduralMap`, 150 walkable level-0 cells; uniform roster,
Speed 8, ATTACK-only gambits; `H = 300`; every fleet slot populated. A **thinking
beat** is timed in three legs — **fill** (`restore_battle` into every slot),
**run** (one `step_tick(H)`), **score** (reading the fleet back) — and `beat` is
their sum. Times are milliseconds; `battles` is the fleet size `K × M`.

| U  | battles | per-tick µs | fill | run | score | **beat** |
|----|---------|-------------|------|-----|-------|----------|
| 8  | 1       | 113 | 0.00 | 27.62 | 0.18 | **27.80** |
| 8  | 4       | 120 | 0.07 | 27.60 | 0.20 | **27.87** |
| 8  | 16      | 103 | 0.16 | 29.81 | 0.52 | **30.49** |
| 8  | 64      | 134 | 0.90 | 31.93 | 2.01 | **34.83** |
| 8  | 256     | 130 | 2.40 | 33.81 | 10.92 | **47.14** |
| 8  | 1024    | 137 | 11.31 | 39.08 | 33.55 | **83.93** |
| 16 | 1       | 123 | 0.00 | 45.25 | 0.13 | **45.38** |
| 16 | 16      | 126 | 0.16 | 50.46 | 0.70 | **51.33** |
| 16 | 64      | 156 | 0.62 | 55.55 | 2.44 | **58.61** |
| 16 | 256     | 160 | 3.46 | 56.26 | 8.04 | **67.75** |
| 16 | 1024    | 169 | 12.12 | 67.79 | 38.05 | **117.97** |
| 32 | 1       | 152 | 0.00 | 109.05 | 0.15 | **109.21** |
| 32 | 64      | 215 | 0.99 | 196.58 | 2.56 | **200.13** |
| 32 | 256     | 216 | 3.73 | 209.44 | 13.09 | **226.26** |
| 32 | 1024    | 250 | 12.06 | 255.42 | 36.63 | **304.11** |

Horizon, at `U = 16`, `battles = 256`: `H = 100` → 22.1 ms, `200` → 44.6 / 48.0 /
47.4, `300` → 56.3, `400` → 86.5 / 86.4 / 85.6, `800` → 369.1. Repeats of one
configuration land within ~7%, and the kernel is bit-deterministic across
processes (same `H` ⇒ same survivors, every repeat).

## Decisions

**1. The fleet is nearly free; the tick is a fixed cost the whole batch shares.**
At `U = 8`, 1024 battles cost 1.41× what one battle costs — 1024× the simulated
work for 41% more wall clock. The reason is that `_run_tick` dispatches over
*every* battle in one compute list, and one tick is 8 dispatches separated by 7
full memory barriers: at `U = 8`, `N = 1` — eight threads on a 5090 — a tick
still takes 113 µs, and at `N = 1024` (8,192 threads) it takes 137 µs. The tick
is bound by dispatch and barrier overhead, not by compute, until the batch gets
large enough to matter (at `U = 32`, `N = 1024` — 32,768 slots — the run leg is
2.3× the `N = 1` cost, so saturation begins somewhere above ~2,000 allocated
slots).

**2. `units_per_battle` is the expensive axis.** At a fixed fleet, `U`
8 → 16 → 32 costs 27.6 → 45.3 → 109.1 ms for the same `H` — 4× the units for
3.9× the time, and 2.4× over the top doubling alone. Compare a **1024×** fleet
increase costing 1.4×. Four of the eight passes
(`resolve_conflicts`, `post_conflict_attacks`, `apply_damage`, `check_victory`)
run **one thread per battle** and loop over all `U` units inside it, and the
per-unit passes scan the battle's roster to pick targets. So `U` buys serial work
inside a thread while `N` buys parallel threads. §7's own note that rollout
compute scales with **allocated** slots is right, and this is why it is the
expensive way to scale.

**3. `H` is the only lever with a superlinear price, and it is the one §7
forbids moving.** Cost per tick is not constant across a battle. Timed in eight
chunks over `H = 800` at `U = 16`, `N = 256`: 29.6, 24.3, 19.4, 21.3, 29.0,
**70.1, 112.9, 134.9** ms per 100 ticks — a 4.5× climb, beginning around tick
500 as units engage and die. Doubling `H` from 400 to 800 therefore costs 4.3×,
not 2×.

**4. §7's degradation ladder has nothing to recover, and that is the finding.**
"Drop `M` first, then `K`, never `H`" is sound *reasoning* — a shortened horizon
biases toward immediate damage, and bias is worse than variance — but as a
wall-clock remedy it barely registers: at the Gariland shape below, halving `M`
from 4 to 2 (fleet 256 → 128) recovers about 10 ms of a 65 ms beat, and half of
that 10 ms is the score leg that decision 7 deletes outright — against a bulk
scorer the recovery is ~4 ms of ~54 ms. **The ladder is kept
for its reasoning and must not be relied on for its rungs.** If a beat blows its
cap, the levers that actually move are `H` (biasing) and `units_per_battle`
(fixed by the scenario) — so the cap must be set generously enough that
degradation is never the plan.

**5. The measured budget at the shape this mode ships against.** Gariland's ENTD
record (388) holds 6 occupied slots of 16 — ENTD records are always 16 wide, and
the busiest in the corpus fills all 16 — so with the player's deployed squad the
padded `units_per_battle` lands near 12. At `U = 12`, `H = 300`, fleet 256
(`K = 64 × M = 4`, §7's starting shape): **beat 64.7 ms** — fill 2.6, run 51.3,
score 10.8. `H = 300` is 5 seconds of simulated battle, since `CombatLoop`
ticks at 60/s. A cinematic focus beat can hold that several times over, so the
starting shape is affordable and `K × M` has room to grow into the thousands
before the fleet costs what the horizon already does.

**6. A rollout forked from a mid-battle position costs about twice a fresh one,
and the headline number understates the real case.** §7 forks the *live* battle
at an enemy turn — units already engaged, some already dead — which by decision 3
is the expensive regime. `prefork=T` advances the live battle `T` ticks before
snapshotting. At `U = 12`, fleet 256, `H = 300`: fresh 51.3 ms of run, forked at
tick 600 **105.1 ms** (beat 124.6). Every fresh-fork row above is therefore a
**floor**, not an expectation. Budget against roughly 2× the table.

**7. Scoring reads the RESULT buffer in bulk; it does not read unit blocks per
battle.** `read_unit_column` is a blocking `buffer_get_data` per battle, so one
column across 1024 battles costs 33–51 ms — as much as the run leg, for one
feature. The whole result buffer reads in **0.11 ms**, and `stage_victory` writes
that record **every tick for every ongoing battle**: result, tick, and living-unit
HP totals per team. Two of §8's four named feature families are already there.
So the value function's features belong in the result record — widening a
write-only per-battle record is cheap and touches no combat rule — and a scorer
that loops `read_unit_column` (or worse, `get_battle_result`, which re-reads and
re-parses the entire buffer per call) is the shape to reject. #896 and #897
inherit this.

**8. No size cap is hardcoded here, and no tunable is published yet.** §10 is
explicit that a discovered ceiling belongs in an ADR-0068 `static var`, not a
`const`. Nothing in the tree reads a fleet size yet — `CombatLoop` initialises the
simulator with **one** battle (`CombatLoop.gd:312`), so the multi-battle path this
measures has no production caller at all. Publishing a tunable now would ship a
default with no reader. #897 owns it, with these numbers as its input.

**9. `MAX_UNITS_PER_BATTLE = 8` remains vestigial and did not bound the sweep.**
It has one reference in the tree, its own declaration, and no shader enforces it.
The structural ceiling on a battle's roster is the ENTD's 16 slots (decision 5),
so `U = 32` covers the padded worst case, and the sweep ran there.

**10. The empty-fleet trap is real but small, and `restore_battle` erases it.**
An unconfigured battle's result word is zero, which reads as `RESULT_TEAM_0_WINS`,
and every stage opens `if (result != RESULT_ONGOING) return;` — so a sweep that
allocates 1024 battles and configures one measures an empty machine. Measured, it
is worth only 22% (`N = 1024`, `U = 8`: 30.5 ms empty vs 39.1 ms populated),
because by decision 1 the tick is not compute-bound. The bench's own
`populate=first` arm found this by falsifying the warning in its docstring — and
only after the arm was fixed: the **fill leg installs battle 0's header, result
word and all, into every slot**, so filling an "empty" fleet makes it live and the
first version of the arm measured nothing.

**11. Roster composition is not a budget lever.** A CAST roster (Fire, MP 200,
witnessed by a nonzero `cooldown_ready_at` on every sampled unit) costs
23.8–35.4 ms of run against ATTACK's 27.6–33.8 at the same shapes — inside the
repeat spread, and *cheaper* at `N = 1`, because a charging unit stands still
while an attacking one re-paths. The workload the horizon buys is dominated by
movement and target search, not by which action fires.

## Consequences

- `GPUBatchSimulator.cleanup()` now frees `_effect_timings_buffer`. It was the
  one buffer `_create_buffers` made and `cleanup` never gave back — "1 RID of
  type StorageBuffer was leaked" on every teardown, once per battle in a campaign
  (`CombatLoop._exit_tree`) and once per configuration in the bench, which is
  where it became visible.
- The bench is machine-specific by construction and re-taking it is one command.
  It writes `res://tests/logs/rollout_budget_<roster>_<populate>.csv` and one
  `BENCH_ROW` line per configuration for scripted diffing.
- `CombatLoop` still hard-codes one battle. #895 is where the fleet first gets
  allocated, and decision 8 is why no cap precedes it.
