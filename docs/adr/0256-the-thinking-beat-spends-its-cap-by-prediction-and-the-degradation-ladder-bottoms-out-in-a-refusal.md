# The thinking beat spends its cap by prediction, and the degradation ladder bottoms out in a refusal

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §7 asks for an enemy AI that runs
`K` candidate gambit edits × `M` common-random-number seeds for `H` ticks, ranks
the results, and applies the winner — under a **hard wall-clock cap** with
**graceful degradation in a fixed order**, and with a choice that is
**reproducible**. [ADR-0246](0246-the-rollout-fleet-is-the-whole-batch-and-the-only-thing-the-cpu-prunes-is-what-cannot-change.md)
built the machine, [ADR-0237](0237-the-rollout-budget-is-bounded-by-the-horizon-and-the-unit-count-not-the-fleet.md)
measured what it costs and [ADR-0253](0253-the-value-function-is-a-probability-fit-against-played-out-battles-and-the-horizon-is-priced-against-it.md)
fitted what ranks it. Each of the three deliberately stopped short of the next.
This is the file that joins them, and it owns the one question none of them
could: **how big a beat is allowed to be.**

Built by [#897](https://github.com/timbermania/fft-monorepo/issues/897).

## Status

accepted

## Decisions

**1. The cap is spent by PREDICTION, and the stopwatch is an instrument.** #897
asks for two things that read as contradictory: a hard wall-clock cap, and "no
wall-clock-dependent candidate truncation that changes the answer between runs on
the same position". A beat that watched a clock and stopped when it ran out would
honour the first and destroy the second — the same position, thought about twice
on the same box, would search a different number of candidates because another
process happened to be compiling, and the AI would play a different move. On this
machine that is not a rare race; it is the normal case, with a sibling session's
suite running most of the time.

So `RolloutDriver.plan(cap, U, fleet, K, M, H)` is a **pure function**. Every
input is a tunable or a property of the scenario and none of them is a clock, so
two runs on the same position plan identically, run identically (ADR-0237
measured the kernel bit-deterministic across processes) and choose identically.
The beat still times itself, and what it does with the number is **warn** —
never re-plan. The price is that the cap is only as hard as the model, which is
why decision 2 is a decision and not an implementation note.

**2. The cost model is the ADRs' own measured rows, separable in three axes, and
it is calibrated to reproduce them.** `predict_beat_ms(U, N, H)` is
`FORK_FACTOR × horizon(H) × unit(U)/unit(12) × fleet(N)/fleet(256)`.

- `horizon(H)` interpolates ADR-0253 dec. 9's measured beats at the shape it
  measured them at — `U = 12`, 256 battles — with `H = 0` anchoring the curve at
  the origin. Linear **between** knots, because the knots carry the curvature:
  cost per tick climbs 4.5× across a battle (ADR-0237 dec. 3), so 400 → 800
  costs 4.5× here, not 2×.
- `unit(U)` interpolates ADR-0237's `U ∈ {8, 16, 32}` rows linearly **in `U`**,
  because dec. 2's own reading of them is that 4× the units costs 3.9× the time:
  four of the eight passes run one thread per battle and loop over all `U`
  inside it, so `U` buys serial work.
- `fleet(N)` interpolates ADR-0237's `N ∈ {1 … 1024}` rows linearly **in
  log2(N)**, because dec. 1 measures 1024 battles costing 1.41× what one costs.
  A curve that flat over three decades is logarithmic, and interpolating it
  linearly would price a 128-battle fleet at half of a 256-battle one.
- `FORK_FACTOR = 2.0` is ADR-0237 dec. 6: the AI forks mid-battle by definition,
  and every fresh-fork row is a floor rather than an expectation.

Separability is the ADRs' own claim about these axes rather than a convenience.
At the reference shape the composition reproduces ADR-0253 dec. 9's forked column
exactly, by construction — which is also what makes `RolloutDriverTest`'s first
arm able to catch a fiction. Every other arm in that file would pass against a
model that returned `H × 0.35`.

**3. The fleet axis is read through a MONOTONE ENVELOPE, and the reason is the
ladder.** ADR-0237's measured row at 4 battles is 0.02 ms *below* its row at 1 —
repeat noise (that ADR records repeats landing within ~7%) sitting on top of a
quantity that cannot physically fall as the fleet grows. Left literal it makes
the degradation ladder a hill climb: dropping `M` from 2 to 1 would *raise* the
predicted cost, and the rung shed to save time would have spent it. The knots
stay as measured and are read through a running maximum, which is a correction
applied only where the underlying quantity is known to be non-decreasing.

**4. The ladder is implemented in §7's order, and the model reproduces ADR-0237
dec. 4's finding that it recovers almost nothing.** Drop `M` first, then `K`,
never `H`. Halving `M` at the shipping shape moves the prediction by about 4 ms
of 138 — dec. 4's number, arrived at independently — and the whole ladder from
`K = 64 × M = 4` down to `K = 2 × M = 1` recovers 25 ms of that 138. The rungs
are taken one at a time rather than solved in closed form, and each reports what
it recovered, so a `degraded` line is dec. 4 being re-measured every time it
fires. That is the only thing that would ever tell us the finding had stopped
being true.

The capacity squeeze — `K × M` may not exceed the battles the simulator actually
allocated — is a different question from the budget squeeze and runs down the
same rungs, so §7's order is not a coincidence of which limit bit first.

**5. THE LADDER'S FLOOR IS A REFUSAL, AND THAT IS THE DECISION #897 REALLY
OWNS.** The ladder bottoms out; what happens there is the choice. It cannot
shorten the horizon (the one rung §7 forbids, for a reason cost cannot overrule:
a short horizon biases toward immediate damage — the AI stops seeing heals and
repositioning pay off — and bias is worse than variance) and it cannot shrink
`units_per_battle`, which the scenario fixes. So a plan that still does not fit
**is refused**, the turn is spent unchanged, and that is exactly "wait"
([ADR-0239](0239-the-turn-director-gates-the-pump-it-does-not-own-and-stops-on-the-exact-tick.md))
— what the host already did before this file existed.

Refusing beats both alternatives. Running anyway makes the cap decoration.
Running at `K = 1` spends the entire horizon to compare the incumbent against
nothing and return the incumbent: a beat that cannot produce a decision is not a
cheap decision, it is a wasted frame. The floor is therefore `K = 2`, the first
`K` at which the word "search" means anything.

A refusal is LOUD and names the cap, the shape and the two tunables that could
move — because it is a message about the tunable and not about the position.
ADR-0237 dec. 4's own conclusion is "set the cap so degradation is never the
plan"; a refusal is the beat reporting that this was not done.

**6. The cap is 250 ms and it is priced as a FROZEN FRAME, not as a cinematic.**
The beat runs synchronously inside `turn_opened`, on the main thread, in a world
the director has already stopped — so its cost is a hitch the player sees between
the enemy's turn opening and the enemy acting. 250 ms buys the calibrated horizon
(`H = 400` predicts 138 ms at `U = 12`) with enough headroom that the ladder
never fires at Gariland, and still fits at `U = 16`.

It is deliberately **not** the several-hundred-millisecond budget design §3's
"cinematic focus beat" would eventually justify, and ADR-0237 dec. 5's "a
cinematic focus beat can hold that several times over" is not yet a fact about
this tree: there is no focus beat in it. When one lands the compute hides behind
a camera move instead of a frozen frame, and *that* is the moment to raise this —
with the animation's length as the argument, which is an argument nobody can make
today.

**7. `H = 400` is the artifact's knee, and the driver CHECKS that it still is.**
ADR-0253 dec. 12 ships `knee_horizon` in the fitted artifact as an input to this
decision rather than as the decision. A `static var` default cannot read an asset
at parse time, so the number is written twice — and the second copy is exactly
the kind that drifts invisibly: a refit that moved the knee would leave the AI
playing to a horizon its calibration was not fit for, with every score still a
probability and every candidate still ranking.
`RolloutDriver.check_horizon_against_artifact` compares the two at mount and
complains when they part. Nothing else in the tree would ever notice.

**8. Five tunables land here, because this is the first reader.** ADR-0237 dec. 8
and ADR-0253 dec. 12 both deferred them on the grounds that a default with no
reader is a number nobody chose. `rollout.cap_ms` (250.0), `rollout.horizon`
(400), `rollout.candidates` (64), `rollout.seeds` (4) and `rollout.fleet_size`
(256) are [ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md)
`static var` homes, registered from `RolloutDriver`'s own `_static_init`
(ADR-0173) and **pull-read** (R5) once per beat rather than pushed through an
`on_update`: the driver reads its whole input set at the top of a beat and picks
up a scrub the next time it runs, so a standing subscription would buy nothing —
and there is no `Node` here to scope one to.

`rollout.fleet_size` is the odd one and says so: the simulator's buffers are
sized in one call, so scrubbing it mid-battle changes nothing. `plan` therefore
treats what the simulator **actually allocated** as the ceiling rather than
trusting the slug. That is not belt-and-braces — a scrub raising `K × M` above
the allocated fleet would otherwise reach `RolloutHarness.run`'s refusal, and a
beat that refuses because a slider moved is decision 1's wall-clock dependence
wearing different clothes.

**9. `CombatLoop.rollout_fleet_size` keeps its zero default and `GambitBattle`
sizes the fleet.** The 256-battle allocation is about 8 MB at `U = 12` — not the
VRAM problem ADR-0237 dec. 8 worried about — but the principle stands for a
different reason: `GPUArena` and `NavigatorMain` never run a rollout, and a
default on the loop would charge them for a fleet nothing reads. The one host
that runs the AI is the one host that sizes it, one line before `start_battle`.

**10. The perspective is read from the PACKER'S OWN BYTE, and the midpoint does
not answer it.** `f` is scored from a team's side, and scoring an enemy's beat
from team 0's ranks every candidate exactly backwards while every score stays a
well-formed probability in [0, 1] — the AI plays to lose and nothing downstream
can see it. `CombatLoop` documents team 0 as filling `[0, units_per_battle/2)`,
but `set_battle_units` seats the two rosters **contiguously**, so team 1 begins
at `team0.size()` and the two agree only when team 0 fills exactly half.
`GambitBattle` sizes the battle as `2 × max(team0, team1)`, which holds that
invariant only while the player's side is the larger one — a 5-deployed /
6-enemy Gariland puts unit 5 on team 1 and *below* the midpoint. So the driver
reads `UnitField.TEAM` out of the snapshot it is about to fork, and cross-checks
it against the team the director announced. A disagreement refuses the beat.

**11. The CRN base seed is a function of the POSITION and of nothing else.** Two
properties have to hold at once and they pull apart. Reproducible: the same
position must derive the same seeds, or decision 1 dies at the last step.
Decorrelated across turns: a constant base hands every beat in a battle the
identical luck, so a candidate flattered by seed 0 is flattered by it all battle
— a bias averaging over `M` cannot see, because it is the same `M`. A hash over
`(battle seed, tick, taker)` gives both; all three come out of the snapshot the
beat is about to fork, and the result is kept well inside int32 because
`crn_seeds` spaces `M` seeds `(U-1) × 1000 + H` apart and the header's seed field
is an int32.

**12. The winning edit lands through `snapshot` / `restore`, and a HELD decision
is not applied.** The apply writes the same primitive the rollout installed its
candidates with, so [ADR-0235](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md)'s
bit-identity test covers it; the other three slices go back exactly as they were
read a moment earlier, which is a fact and not a hope because the world is frozen
for the length of a turn. When candidate 0 wins — ADR-0246 dec. 2's unmutated
incumbent, which a tie also falls to — nothing is written, so "the AI changed its
mind" and "the AI held" stay distinguishable at the one place that could tell.

**13. A WON BATTLE LATCHES FROM ANY STATE, NOT ONLY FROM IDLE — and wiring the
AI is what found that.** `stage_compute.glsl` checked "is the enemy team dead →
celebrate" at the bottom of its state machine, in the IDLE fall-through. A unit
with a live "attack the nearest enemy" gambit and no living enemy never reaches
idle: the gambit re-evaluates, the unit re-enters WALKING toward a target that no
longer resolves, and its timer restarts every tick. `stage_victory` reports a win
only when EVERY survivor is `LOGICAL_ACTIVITY_CELEBRATING`, so one stuck unit
holds an already-decided battle open forever.

The check moves above the state dispatch. Two details are load-bearing and both
were found by getting them wrong first:

- **It must sit AFTER the per-tick clears.** Returning above
  `U_PENDING_ACTION_TYPE = ACTION_NONE` leaves last tick's `ACTION_PATHFIND_MOVE`
  standing for `stage_pathfind` to re-run, which writes WALKING back over the
  CELEBRATING just set — every tick, invisibly. It also resets the proposed
  position, because the reset above it deliberately skips the walking states and
  this unit has just stopped being one.
- **DYING is exempt.** A unit playing out its death as the last enemy falls is
  still dying, and celebrating it would skip the animation `stage_victory`'s own
  tally is waiting on.

**This is not an AI defect and the AI is only what exposed it.** Any authored
attack gambit reaches the same loop. Gariland ended before this because a
scenario-booted cast has EMPTY gambit lists (ADR-0242), so its survivors sat in
IDLE and fell through — the mode had simply never had a unit that was still busy
when the fight ended.

## Consequences

- **The AI refuses to think above about `U = 30` under a 250 ms cap.** At `U =
  32`, `H = 400` predicts 338 ms forked with the ladder fully spent, and `H` is
  the one rung that may not move. That is the cap being honest rather than the AI
  being broken: the fix is decision 6's focus beat, or a deliberate scrub, and
  both are decisions somebody makes rather than a bias the search acquires. `U =
  12` (ADR-0237 dec. 5's shipping shape) and `U = 16` both fit with no rung
  taken, and `RolloutDriverTest` arm 5 goes red the moment a change to `cap_ms`
  or `horizon` breaks that.
- **`GambitBattleTest` plays the whole Gariland fight with the AI ON**, and that
  is decision 13's end-to-end guard: 385 turns, ended by annihilation. Its arm 4c
  reads `beats_taken` to prove the host actually calls the driver — both unit
  tests are structurally unable to see that, because a `decide` never called and
  a `decide` that held leave the gambit buffer identical (#894's own lesson).
  `GambitBattle.ai_enabled` exists so a host or rig can turn the beat off and have
  to write down why.
- **The context is built by the HOST, and its ability set is a UNION.** The
  driver does not know what a `Character` is, for the same reason `AdjustmentTurn`
  does not. The set offered to the search is what the unit has LEARNED ∪ what its
  gambit list already NAMES, sorted — the union because an ENTD-placed enemy is
  built from a ROM record and need not carry a learned-ability table at all (a
  unit whose gambits cast Fire can obviously cast Fire, and reading only
  `learned_abilities` would hand the search an empty action family), and sorted
  because `Dictionary.keys()` is insertion order, which is a property of how a
  `Character` was BUILT rather than of what it is — and candidate order is part of
  what makes the choice reproducible.
- **ADR-0253's owed refit is now collectable.** §8 asks for one refit after the
  real AI ships, because the AI changes the distribution of positions `f` is
  asked about. There is a production caller now; there was not before.
- **`ProceduralMapMountTest` 120 → 121 and `CombatCameraMountTest` 117 → 118**,
  for `tests/GPURolloutDriverTest.tscn`. That is the fourth rollout rig in a row
  with the same scene shape; a fifth is the signal to give them a shared scene
  rather than to write a sixth comment.

## What wiring it MEASURED

The beat works and the policy it optimizes does not, and those are two findings
rather than one.

**The beat, at Gariland (`U = 12`, fleet 256, `H = 400`):** 330 beats over one
battle, **37 / 54 / 68 / 87 ms** (min / median / p90 / max) against a predicted
138 ms and a 250 ms cap, with **no rung of the ladder taken and no refusal**.
The model is about 2.5× conservative here, and in the safe direction: decision
2's `FORK_FACTOR` is ADR-0237 dec. 6's *late-battle* fork, and Gariland's turns
open long before tick 600, so most of these beats are nearer a fresh fork than a
deep one. Decision 1's stopwatch never warned.

**The AI thinks, and its choices are real.** Across that battle it re-planned 86
times and held 244 — so the search discriminates rather than tying to the
incumbent, and the margins are not noise (one beat took a unit from `P(victory)`
0.088 to 0.303, another from 0.369 to 0.934).

🔴 **AND IT FOUND A BATTLE THAT COULD NOT END.** With the AI off, Gariland ends
by annihilation in **282 turns and 15 seconds**. With it on — before decision 13 —
the same battle ran to the rig's 12,000-frame bound: **1,734 turns, tick 12,178,
904 beats**, and `victory_achieved` never fired. Not because the AI lost, and not
because it refused to fight: at the bound the state read **`alive = [2, 0]`,
`team1_hp = 0`**. Team 1 was annihilated and the battle never *latched*.

The measurement that named the cause: one survivor `CELEBRATING`, the other
**`state=WALKING target=<itself> timer=48 → 47` across 800 frames** — a walk that
restarts every tick toward a target that no longer resolves. That is decision 13,
and with it Gariland ends by annihilation **with the AI on**, in 385 turns.

**The AI's choices are real and good.** Across one battle it re-planned 86 times
and held 244, so the search discriminates rather than tying to the incumbent, and
the margins are not noise (one beat took a unit from `P(victory)` 0.088 to 0.303,
another from 0.369 to 0.934).

The *shape* of what it optimizes is still worth stating, because it is what the
owed refit is for: the fitted `f` scores `mp_frac_self` **+2.23**,
`hp_frac_self` **+2.05** and `engage_self` **+0.0495 per tile of distance**, so
over a 400-tick horizon it rewards spending no MP, taking no damage and standing
off. Those are coefficients that *correlate* with winning in a corpus where
nobody was optimizing them, and they become *instructions* the moment something
maximizes them — precisely the failure §8 predicted when it asked for one refit
after the AI ships. [ADR-0253](0253-the-value-function-is-a-probability-fit-against-played-out-battles-and-the-horizon-is-priced-against-it.md)
dec. 12's owed refit now has a production caller to produce its positions.

## Soft spots

- **Decision 13 pays `is_enemy_team_dead` on every unit, every tick, in every
  state.** It used to run only for IDLE units. The loop is `O(units_per_battle)`
  and most units are idle most of the time, so the delta is small — but it lands
  in the pass the live game pays every tick, which is where ADR-0253 dec. 4's
  15-24% widening cost landed too. Not separately measured here.
- **`ai_enabled` is a live flag with one production reader.** It defaults true and
  nothing in the tree sets it false any more; it exists so a host or a rig can
  turn the beat off and say why. A flag with no user is a flag whose off-path
  rots.
- **The cost model is calibrated on one GPU.** Every knot is an RTX 5090 row from
  ADR-0237 and ADR-0253. On a slower card the model under-predicts, the cap is
  spent optimistically, and the only thing that says so is the beat's own
  post-hoc warning. That warning is deliberately not a feedback loop (decision
  1), so a mis-calibrated box hitches rather than degrades — which is the right
  failure, but it is a failure.
- **The ladder's rungs have never been exercised in a game.** `U = 12` and
  `U = 16` both fit with room, so every beat this mode currently plays takes no
  rung at all. The ladder is proved by `RolloutDriverTest` against the model and
  by nothing else, and ADR-0237 dec. 4's advice was to keep it that way.
- **The refusal at `K < 2` has never fired in production either.** It is reachable
  only through a fleet smaller than two battles or a cap below the horizon's own
  cost, and both are scrub-only states today.
- **One ply, and the horizon is the whole of the AI's foresight.** Every unit's
  gambits are frozen for the horizon and rollouts do not run the turn machine.
  §7's own assumption, and multi-ply / MCTS remains an explicit non-goal — but it
  means the AI cannot see its own next turn, and the value function is what
  carries everything past tick `H`.
