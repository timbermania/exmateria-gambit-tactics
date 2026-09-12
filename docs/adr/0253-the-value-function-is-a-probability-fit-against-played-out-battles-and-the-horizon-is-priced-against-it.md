# The value function is a probability fit against played-out battles, and the horizon is priced against it

[GambitBattle](../GAMBIT-BATTLE-DESIGN.md)'s §8 asks for a calibration tool: a
corpus of battles played to completion, a logistic fit on `P(victory)`, and an
accuracy-vs-cost table across the horizon `H`. [ADR-0237](0237-the-rollout-budget-is-bounded-by-the-horizon-and-the-unit-count-not-the-fleet.md)
measured the cost axis and [ADR-0246](0246-the-rollout-fleet-is-the-whole-batch-and-the-only-thing-the-cpu-prunes-is-what-cannot-change.md)
built the machine that produces the positions. This file is the accuracy axis,
and the joint `(H, f)` choice the two of them make possible.

Built by [#896](https://github.com/timbermania/fft-monorepo/issues/896).

## Status

accepted

## Decisions

**1. A corpus battle is a GPU FLEET battle, and it is a faithful game rather
than a model of one.** §8 wants battles "played by the current gambit AI with
adjustments disabled", and the first real question this ticket had to answer was
whether that means `CombatLoop` runs or fleet runs. It means fleet runs, on two
grounds. The shader IS the gambit AI — `stage_compute` evaluates the gambit
rows and `CombatLoop` only drives the clock — so nothing about a fleet battle is
a simulation of the game; it is the game, minus the rendering. And `CombatLoop`
ticks at 60/s, which puts one 5,000-tick battle at 83 seconds of wall clock and
a thousand of them at a day, against ADR-0237 dec. 1's measurement that 1024
battles cost 1.4x what one costs. #890's corpus note supplies the other half: a
finished battle stops costing, because every stage opens
`if (result != RESULT_ONGOING) return;`, so a to-completion run is far cheaper
per battle than `ticks × battles` suggests. Measured, 1,536 battles produced
31,991 sampled states with nothing dropped.

**2. Sampling on a fixed tick GRID is what makes one corpus serve the whole
sweep.** §8 asks to sample "only at the states the AI will actually query" — `H`
ticks after a decision — and to stratify by remaining battle length. A grid at
`stride = 100` gives both at once and neither costs a second run: any grid state
is reachable as `D + H` from the grid state `H` earlier, so one corpus covers
every `H` in {100, 200, 400, 800}, and `terminal_tick - tick` is the stratifier
exactly rather than approximately. Only LIVE states are sampled — a decided
battle's record stops being rewritten, so sampling past the end would stack
identical copies of the terminal record, and the AI never queries a decided
position anyway.

**3. The features live in the RESULT RECORD, which widens from 4 ints to 14.**
ADR-0237 dec. 7 already decided this and #896 is its first consumer: the record
is written by `stage_victory` every tick for every ongoing battle and read whole
in 0.11 ms, while `read_unit_column` is a blocking readback per battle costing
33-51 ms across 1024 battles — as much as running the entire horizon, for one
feature. The record is write-only from the shader's side, so a new field touches
no combat rule.

It also stops being three hand-written copies of one number on the way. A GD-only
`RESULT_SIZE = 4` in `GPUBatchSimulator` sat opposite a literal `battle_id * 4`
in `stage_victory.glsl`, with `RolloutHarness` holding a third copy of the field
offsets. `tools/gen_gpu_layout.py` now emits `GPUCombatPacker.RESULT_SIZE` and
`GPUCombatPacker.ResultField` from `combat_common.glslinc`, so the shader is the
one author ([ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)),
and `RolloutHarness` derives its row keys from the enumeration instead of listing
them again beside it.

**4. The engagement term is a CENTROID distance, and the O(U²) version was
rejected on a measurement rather than on taste.** The feature this wants to be is
distance to the NEAREST living enemy. That is an O(U²) scan inside a function
that runs once per battle per tick — in the live game as well as in a rollout
fleet. Benched against ADR-0237's table at `H = 300` it cost **1.9x** the run leg
at `U = 16` fleet 256 (56.3 → 105.0 ms) and **2.2x** at `U = 32`
(209.4 → 455.2 ms), against that ADR's documented ~7% repeat spread. Dec. 5 there
sizes the shipping beat at 64.7 ms; doubling its run leg to buy one feature is
not a trade the budget can pay.

The O(U) centroid reproduces ADR-0237's `U = 8` fleet-256 row to within 0.2%
(33.81 → 33.89), which is what makes the residual real signal rather than drift:
the widened record costs **15-24% of the run leg at U ≥ 16**, and ADR-0237's
table should be read as that much optimistic from here on. §8's escalation rule
says which way to spend if it ever matters — if the H-sweep shows the linear
model cannot separate positions, the distance term is the first thing to sharpen.

**5. Every feature is PER TEAM, because `f` is read from a perspective.** `f`
answers "what is the probability that THIS team wins", so swapping the team roles
must describe the same battle from the other side. A battle-wide scalar cannot
do that: it says how decided a battle is but never who is winning, and mirrored
training rows drive its coefficient to zero. The first cut of the engagement term
was one battle-wide sum for exactly this reason and had to be split. The
consequence is that the fitted coefficients come out exactly antisymmetric and
the intercept is 0 — the model has six free parameters, not twelve — and
`f(state, team0) + f(state, team1) = 1` is an identity the design rests on rather
than a coincidence.

**6. §8's four feature families were NOT sufficient, and the shortfall was only
visible in the stratification.** Fit on HP fractions, standing counts, MP and
distance alone, `f` scored **0.7210** in the early stratum against a base-rate
model's 0.6931 — worse than a coin flip, and confidently so, which is precisely
what §8 says stratifying exists to expose and what log-loss can see and accuracy
cannot. The cause is that a fraction normalises absolute power away: at full
health a 262-HP team and a 1690-HP team both read `hp_frac = 1.0`, so early on
the only thing left to look at is the standing count, and the model duly learned
"the bigger team wins" — false whenever the small team is the strong one. Adding
an HP-share and a power-share pair takes that stratum to **0.6495** and the whole
held-out loss from 0.3492 to **0.3214**. §8's own rule for this shape: the fix is
**a term, not a weight**.

**7. Every horizon is scored on the SAME held-out decision points.** Taking each
horizon's pairs independently changes the population underneath the table — a
long horizon can only pair a decision point far enough from the end of its
battle — so the losses would differ for two reasons at once and the table could
attribute the difference to neither. Under that error the sweep looked nearly
flat (0.3451 → 0.3353 across a 16x cost increase), which reads as "the horizon
buys nothing". On a common row set the horizon plainly buys accuracy:
**0.4234 at H = 0 → 0.3073 at H = 800**. `H = 0` is in the table as the
reference end of §8's trade — the formula alone, simulating nothing — because
without it the table can only compare horizons to each other and never say what
the horizon BUYS.

Splits are by BATTLE and never by row. Samples from one battle share a label and
a roster, so a row-wise split puts near-duplicates on both sides and reports a
score the model did not earn.

**8. The knee is a rule about the RATE, read under a cap on the FORKED beat.**
"Knee" means the point where marginal return collapses, so a rule that returns
the last horizon which improved *at all* selects the largest horizon in any
monotone table — the first version did exactly that and chose H = 800 off a step
buying 0.0022 of log-loss for 241 ms, a rate 22x worse than the step before it.
The rule is now the last step still returning at least 20% of the best step's
log-loss-per-millisecond.

The cap is applied to the forked cost, not the bench cost: ADR-0237 dec. 6
measures a mid-battle fork at ~2x a fresh one, and the AI forks mid-battle, so
pricing against a fresh-fork row chooses a horizon the bench can afford and the
game cannot.

**9. The measured answer, at `U = 12` and fleet 256 with the widened record.**

| H | held-out log-loss | beat (ms) | forked (ms) | gain per ms |
|---|---|---|---|---|
| 0 | 0.4234 | — | — | — |
| 100 | 0.4092 | 18.9 | 37.8 | — |
| 200 | 0.3955 | 34.7 | 69.5 | 0.000864 |
| 400 | 0.3688 | 69.1 | 138.2 | 0.000778 |
| 800 | 0.3073 | 310.5 | 620.9 | 0.000255 |

**The knee under a 200 ms forked cap is `H = 400`.** Ignoring the cap it is
H = 800, which is why the cap is part of the rule and not decoration.

**10. The horizon buys nothing in the EARLY game, and that is worth knowing
before anyone spends it there.** Stratified, `H` improves the late and mid
strata monotonically (0.2832 → 0.1392 and 0.4723 → 0.3464 from H = 0 to
H = 800) and does not help the early stratum at all
(0.6495 → 0.6561 → 0.6597 → 0.6652 → 0.6444). 800 ticks is a small fraction of a
3,500-tick battle, so the landed state is barely closer to the outcome than the
decision point was. The endgame stratum is absent from that table BY
CONSTRUCTION rather than for want of data: the common row set needs a landed
state at `D + 800`, so every decision point in it has at least 800 ticks left.

**11. The artifact ships the ROUNDED fit, and everything downstream reads those
same numbers.** The JSON rounds coefficients to 6 dp. A first cut built the
cross-language fixture from the raw fit instead, so the pin compared
GDScript-with-rounded-coefficients against Python-with-full-precision ones and
the rounding alone cost 6.4e-7 of disagreement — under the test's 1e-6 tolerance,
so it passed, while consuming most of the budget the tolerance existed to spend
on real errors. Rounding once takes the worst disagreement to 4.95e-10 and the
tolerance to 1e-8, with the headroom measured rather than assumed.

**12. No fleet size and no horizon tunable is published here.** ADR-0237 dec. 8
and ADR-0246 dec. 8 both hold: a discovered ceiling belongs in an
[ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md)
`static var` published by whoever wires the AI (#897). `knee_horizon` is in the
artifact's calibration block as an input to that decision, not as the decision.

## Rejected

**A tournament of weight vectors as the instrument.** §8 rejects it and the
reason survives contact: a tournament scores the whole AI, so it cannot say
whether a bad result came from `f`, from `H`, or from the mutation set. Scoring
`f` against known winners measures `f` alone, which is what makes the H-sweep
readable.

**A hand-weighted score with a terminal win/loss bonus.** The bonus has to be
big enough to make winning outrank having more HP, and no principled value
exists: too small and the AI trades the win for damage, too large and every
non-terminal difference is noise. A probability is already calibrated and
already comparable, so the bonus does not need to exist — which is the whole
reason §8 chose `P(victory)`.

**Nearest-living-enemy distance.** Decision 4. Better feature, measured at 1.9x
to 2.2x the run leg, in a pass the live game pays every tick.

**A heal in the corpus roster.** The corpus wants MP to move, and a first pass
reached for ability 8 as a heal. Ability 8 is **Regen**, and `make_spell_gambit`
targets the nearest ENEMY by default, so the roster was regenerating the people
it was fighting: 19% of battles never reached a verdict and 48% of samples were
dropped for want of a label. Two offensive spells at different MP costs move MP
without ever making a battle unable to end. The drop rate looked exactly like a
tick cap set too low, and those two causes are indistinguishable from the drop
count alone.

**Scoring a draw as 0.5.** The model is binary and a half-label is a third
outcome smuggled into a two-outcome fit. Draws are dropped and counted (174 of
63,982 perspective rows), so a corpus that was mostly draws could not pass
unnoticed.

**Returning 0.5 when the scorer cannot score.** Every value in [0, 1] is a
legitimate probability, so an error that returned one would rank a broken
candidate at the median and nothing downstream could tell it from a genuine coin
flip. `score` returns -1.0.

## Consequences

- **`RolloutValueFunction` scores; `RolloutHarness` still does not.** ADR-0246
  dec. 6 keeps ranking out of the harness so the H-sweep can vary the scorer,
  and that held: the sweep varies `H` and the feature set against one unchanged
  machine. #897 is what joins them.
- **Ranking averages over the CRN seeds, and a tie falls to the incumbent.**
  Averaging is what the seeds are FOR — two candidates under seed `m` faced
  identical luck — and ranking individual slots would hand the win to whichever
  candidate drew the kindest seed. The tie-break to candidate 0 is ADR-0246
  dec. 2's unmutated incumbent: without it the AI re-plans a working posture
  every turn on a score it never beat.
- **FOUND: a latent non-idempotence in `tools/gen_gpu_layout.py`, with no
  symptom until a second enum reused a member name.** Preserved trailing
  comments were keyed by bare member name, so `BattleHeaderField.RESULT` and the
  new `ResultField.RESULT` collided; the bled comment was scraped back on the
  next pass and the generator stopped converging. `--check` reported STALE
  immediately after a successful regeneration — which reads as "somebody forgot
  to run the generator", not as "the generator cannot finish". Keys are now
  scoped by enum, and `tools/test_gen_gpu_layout.py` tests IDEMPOTENCE against
  the real tree rather than testing the comments, because a comment assertion
  passes on pass one and leaves the loop open.
- **The cross-language pin is the only thing that can see the defect it exists
  for.** `RolloutValueFunction.feature_vector` and `features_from` in
  `tools/fit_value_function.py` are one function written twice. A divergence
  fails invisibly: every score stays a probability in [0, 1], every candidate
  still ranks, no assertion goes red, and the AI simply plays worse than its
  calibration report claims. The fixture therefore carries input rows and
  expected SCORES, not feature vectors — a fixture of vectors would leave the
  intercept and the coefficient lookup unpinned, and those are half the
  arithmetic.
- **Eight seeded defects, all caught, and one of them proves an arm the others
  could not.** Six single-language seeds (a diverging denominator, a
  non-mirroring feature, a plausible 0.5 on a malformed row, ranking the best
  slot instead of the seed mean, a tie-break away from the incumbent, a declared
  feature with no coefficient) each reddened the guard; a seventh restored the
  generator's bare-name keying and reddened `test_gen_gpu_layout`. The eighth
  broke the mirror in BOTH languages and refit, so the cross-language pin AGREED
  — arm 1 stayed green at 4.9e-10 — and only the perspectives-sum-to-1 arm went
  red. That is the case where both sides are wrong the same way, and it is why
  arm 2 is not a restatement of arm 1.
- **`assets/gambit/` is a new asset store**, named for the system that reads it
  per [ADR-0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md)
  and committed, being a small JSON table rather than bulk ROM-derived media.
- **The corpus rig lives in `tools/`, not `tests/`**, per #896's own scope note —
  it is an offline instrument, not a suite guard, and it asserts nothing. It
  still costs the two census guards a row each
  (`ProceduralMapMountTest` 119 → 120, `CombatCameraMountTest` 116 → 117), which
  walk `res://` and do not care which directory a scene sits in.
- **One refit is owed after the real AI ships**, per §8: the AI changes the
  distribution of positions it is asked about. One refit, not a loop —
  self-play refinement is a research project and not this ticket.

## Soft spots

- **The corpus roster is randomised, not real.** Team sizes, stats and placement
  are drawn to span positions, which is what makes the label informative, but no
  battle in it is an ENTD encounter. `f` is calibrated to the shape of FFT combat
  rather than to any scenario the player will meet, and decision 12's owed refit
  is the intended correction.
- **The engagement coefficient is small (+0.0495 per tile of mean distance)** and
  its feature is the one that had to be cheapened for cost. Whether the AI
  positions well is the thing this term is supposed to carry, and the H-sweep
  cannot tell a weak term from a well-priced one.
- **The early stratum still barely beats a coin flip** (0.6495 against 0.6931)
  and the horizon does not rescue it. An opening position genuinely may not
  predict its own outcome — but decision 6 showed one apparent floor there was a
  missing term, so this one is worth suspecting before it is accepted.
- **Nothing has run this against a live battle.** There is still no production
  caller: #897 wires the beat to a turn, and until then "the scorer ranks what
  the harness returns" is proved on fixtures and a corpus, not in a game.
