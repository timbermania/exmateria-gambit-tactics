# The search maximises a NAMED objective, and the terminal verdict takes the endpoints instead of an invented weight

[ADR-0253](0253-the-value-function-is-a-probability-fit-against-played-out-battles-and-the-horizon-is-priced-against-it.md)
chose `P(victory)` over a hand-weighted score for one reason, and it is a good one:
*"a hand-weighted score needs some invented weight big enough to make winning outrank
having more HP, and that weight is unknowable."* This ADR ships a hand-written objective
anyway — and it does not pay that price, because the terminal verdicts take the **outer
0.1% of the range at each end** and every ongoing state is clamped strictly inside them. A
win is not weighted above an ongoing position; it is outside the band an ongoing position
can reach.

Status: accepted (2026-09-10). This is
[#1109](https://github.com/timbermania/fft-monorepo/issues/1109) on the rebalancing map
[#1101](https://github.com/timbermania/fft-monorepo/issues/1101). Reads
[ADR-0237](0237-the-rollout-budget-is-bounded-by-the-horizon-and-the-unit-count-not-the-fleet.md)
dec. 7 for why the objective is fed from the result record and never from a unit column,
[ADR-0246](0246-the-rollout-fleet-is-the-whole-batch-and-the-only-thing-the-cpu-prunes-is-what-cannot-change.md)
dec. 2 for the incumbent that a tie falls to and dec. 6 for why the harness does not rank,
[ADR-0253](0253-the-value-function-is-a-probability-fit-against-played-out-battles-and-the-horizon-is-priced-against-it.md)
dec. 5 for the perspective invariant, dec. 9 for the knee and dec. 12 for the owed refit,
and
[ADR-0256](0256-the-thinking-beat-spends-its-cap-by-prediction-and-the-degradation-ladder-bottoms-out-in-a-refusal.md)
dec. 6 for the 250 ms frozen frame that prices `H`.
**Supersedes nothing.** ADR-0253 stays accepted in full: `f` is still the destination and
still the shape a refit lands in. What this changes is that `f` is no longer the *only*
objective, and no longer the one running.

## Context

`f` is fitted, shipped, guarded by a cross-language pin — and stale by construction. Its
corpus was generated before #939 changed the tempo by ~48×, and #897's AI is the **first
thing that has ever maximised it**. ADR-0256 dec. 13 already wrote down what it asks for:

> `mp_frac_self` +2.23, `hp_frac_self` +2.05, `engage_self` +0.0495 PER TILE OF DISTANCE,
> so over a 400-tick horizon it rewards spending no MP, taking no damage and standing off
> — coefficients that CORRELATE with winning in a corpus where nobody was optimizing them,
> and that become INSTRUCTIONS the moment something maximizes them.

Map #1101's destination is a **balance instrument**: a rig that referees the lever set
against real rosters and reports battle length, lethality and decision count. That rig has
to be **search-driven**, because a corpus driven by anything else measures a game nobody
plays — and a search driven by `f` measures the staleness rather than the balance. The
refit is the way out and it is out of scope: it needs a corpus at the *settled* tempo,
which does not exist until the numbers are dialed, i.e. after this map.

So the map needs a stand-in. The question this ADR answers is not "is a hand-written
objective as good as a fit" — it plainly is not — but **what shape a stand-in has to have
so that nothing downstream mistakes it for one.**

## Decision

### 1. The search maximises a NAMED objective, and the name is on the interface

`RolloutObjective` is the supertype; `RolloutValueFunction` (`fitted-logistic-v1`) and
`ProvisionalObjective` (`provisional-attrition-v1`) are its two members. Every objective
answers `id()`, and `RolloutDriver.decide` returns it on every decision.

A corpus whose objective is unrecorded is **unattributable later**, and that is not a
hypothetical: this subsystem already ships one artifact whose provenance is a comment.
Putting the name on the interface makes "which objective produced this run" a field rather
than an inference.

`rank_candidates`, the averaging over the M common-random-number seeds and the incumbent
tie-break all live on the supertype, because every one of them is a property of the
**search** and not of what it maximises. A second copy would be a second place for
ADR-0246 dec. 2's tie-break to be got wrong.

### 2. The provisional objective is two mirrored shares, equal weight, ZERO free parameters

For an ongoing record, from `team`'s perspective:

```
v = 0.5 * (hp_self / (hp_self + hp_enemy) + alive_self / (alive_self + alive_enemy))
```

Both terms rise when the enemy loses and fall when we do, which is *kill the enemy, don't
die* written out. They are **shares** and not fractions of each side's own pool, so neither
roster size nor total HP has to be known to compare two states of one battle.

Two terms and not one, because HP share alone cannot tell six units at half health from
three corpses and three untouched units — the same number, and in a game where a dead unit
stops acting, very different positions.

### 3. THE TERMINAL VERDICT TAKES A BAND AT EACH END; ONGOING IS CLAMPED STRICTLY INSIDE

`TERMINAL_BAND = 0.001`. Wins land in `[1 − band, 1]`, losses in `[0, band]`, a mutual
wipe at `0.5`, and an ongoing state is clamped into `[band + ε, 1 − band − ε]` with
`ε = 1e-6`. **This is the decision the whole ADR rests on.** ADR-0253's objection to a
hand-weighted score is real and unanswered by any weight — so this does not pick one. The
ordering is lexicographic in the verdict and continuous only *within* each band.

The residual weighting — the 50/50 between the two ongoing terms — orders ongoing states
against each **other** and can never reorder a win against one. That is the entire scope of
what is invented here.

The clamp is load-bearing, not defensive: delete it and a team at full health with the
enemy wiped scores exactly `1.0`, ties an actual win, and the argument above evaporates
while every number still looks perfectly well-formed. `RolloutValueFunctionTest` arm 6
carries the seed — ⚠️ **and it only reds on the SATURATED fixture**: a merely crushing
position (enemy on 1 HP, one unit standing) scores 0.944 and stays under a win with the
clamp gone, which is how the first cut of that arm went green against its own seed.

#### 3a. Why the terminal verdict is a BAND and not a POINT — measured, not reasoned

The first cut returned exactly `1.0` and `0.0`. Instrumented at Gariland with the AI on,
the **first beat came back `result = TEAM_0_WINS` on all 64 candidate rows** with
`t1_alive = 0` — the AI's own team annihilated in every rollout. All 64 tied at `0.0` and
the beat held the incumbent by tie-break. `f` scored the same rows **0.001127** and
**0.002705**: also near-zero, but *distinct*, so it could still rank them.

That is not cosmetic. An objective flat across lost positions makes the AI **stop trying
the moment a battle is decided**, which shortens the battle — and battle length is the
quantity this whole map exists to measure. The instrument would have biased its own
reading, in the direction of its own conclusion.

So a terminal verdict orders *inside* its band by what the battle cost: the winner's
remaining health fraction. A loss that ground the winner down to 10% ranks above one that
left them at 90%; the mirrored wins order the other way. `hp_frac` and not `hp_share`,
because at a latched battle the loser's HP is `0` and every share is `1` or `0`.

The band is narrow because it is a **tie-break, not a trade**: no ordering inside a band
may ever be worth as much as changing which band you land in. And the perspectives still
sum to 1, because both sides read the same `spent` — the winner sits `band × spent` below
the top and the loser exactly that far above the bottom.

### 4. It is deliberately CRUDE, and the ranking key stops claiming to be a probability

Crude is the argument for it, not an apology: there is nothing here to over-fit to numbers
that are about to move, so nothing here has to be thrown away when they do. A "minimal
refit" would have bought precision against a tempo that is mid-change and then spent it.

Consequently `rank_candidates` and `decide` return **`value`** / **`value_incumbent`**,
not `p_victory` / `p_incumbent`, and the battle log prints `v 0.734` rather than
`P(win) 0.734`. A key name is a claim, and only one of the two objectives can honour that
one. ADR-0253's glossary warning against the words *score* and *heuristic* stands — the
word coined here is **objective**, and it is the supertype's name.

### 5. No MP term, no standoff term, no power-share term — each omission is a decision

- **MP** and **engage** are precisely the two features whose fitted coefficients became
  perverse instructions. An objective built to measure *battle length and lethality* that
  paid a unit to stand off would be measuring its own instruction.
- **`power_share`** is a function of the rosters' max HP, so it is constant across a
  battle and therefore constant across the K candidates of one beat. It cannot rank
  anything; it only compares two battles, which is not what a beat does.

`RolloutValueFunctionTest` arm 7 asserts **both halves against the same two rows**: the
provisional objective scores a full-MP and a spent-MP position identically, and the fitted
one does not. Without the control half it would be a test that an absent term is absent.

### 6. It reads `result`, and `result`'s zero is a legitimate verdict

`f` never touches `R_RESULT`; this objective is the first thing in the tree to read it off
a slot that may never have been written. `RESULT_TEAM_0_WINS == 0`, so **a zeroed record
spells a team-0 win** rather than missing data. `stage_victory` writes `R_TICKS` as
`tick + 1`, so a record claiming tick 0 was never written, and that is the refusal.

### 7. ONE selection, and BOTH callers read it

`RolloutDriver.objective_id` defaults to the provisional objective, so the game and the rig
maximise the same thing. Splitting them — the game on `f`, the referee on the stand-in —
was the tempting half-measure and it is the failure #1109 was written to avoid: the rig
would be refereeing a game nobody plays.

Deliberately **not** a `Tune` slug. A tunable is a number a scrub may move mid-run
(ADR-0068); this is a **mode** whose change invalidates every corpus already written under
the other one. Flipping it back to `fitted-logistic-v1` is the refit's landing, and it
should be a reviewable line in a diff.

`make_objective` **refuses an unknown id** rather than falling back. A typo that quietly
resolved to `f` would produce a corpus attributed to an objective that never ran.

### 8. The horizon guard has three states, and only agreement is silent

`check_horizon_against_artifact` returned `true` whenever the artifact declared no knee, on
the reading that an older artifact is not an error. A hand-written objective declares none
**by construction** — so that guard would have passed, silently, on exactly the objective
it most needed to speak about. It is now `check_horizon`, over
`RolloutObjective.horizon_stance()`:

| stance | verdict |
|---|---|
| `CALIBRATED`, knee == H | agrees — the only silent pass |
| `CALIBRATED`, knee != H | a refit moved the knee and `rollout.horizon` did not follow (ADR-0253 dec. 12) |
| `UNCALIBRATED` | no H-sweep exists, so no `H` can be checked against this objective at all |

And the substantive half: **under the provisional objective, `H = 400` is a cost number,
not a knee.** A longer horizon resolves more of the battle, so strictly more rows carry a
terminal verdict and fewer rest on the two-term guess — more information, monotonically,
with no knee to find. What holds `H` at 400 is ADR-0256 dec. 6's pricing of a 250 ms frozen
frame, which is untouched by which objective reads the rows. So #1109's own warning — *"if
the provisional objective turns out to need calibration to be usable at all, that would
pull the refit back across the scope line"* — does **not** fire: it needs no calibration
to be usable, only to be optimal, and the cost bound is doing the work either way.

## Considered alternatives

**A minimal refit, pulled into scope.** Rejected twice over: a refit needs a corpus at the
settled tempo and that corpus does not exist yet, so the fit would be against the same
moving target — and it would be thrown away by the real refit anyway. It buys precision
that cannot be spent.

**Hand-picked coefficients inside the existing logistic artifact.** The tempting
zero-code-change "drop-in": the shipped format is already a weighted sum over the feature
vector, so an attrition objective can be expressed as coefficients. Rejected because it
**fakes a probability** — `is_loaded()` would report a hand-edited file as a fit,
`calibration()` would be empty or a lie, the horizon guard would pass in silence (dec. 8),
and twelve numbers with no fit behind them is an invitation to tune them. The thing that
must not happen is a stand-in that is indistinguishable from `f`.

**Keeping the game on `f` and running only the referee on the stand-in.** Rejected: dec. 7.

**Keeping `p_victory` as the ranking key.** Rejected: dec. 4. The rename costs ~20 lines
across two GPU tests and buys a key name that is true for both objectives.

**A `Tune` slug for the selection.** Rejected: dec. 7.

**An `alive_frac` term (standing / team size) instead of `alive_share`.** Rejected on
mechanism: the result record carries no per-team slot count — `TEAM*_MAX_HP` sums all
slots but does not count them — so the fraction is not derivable without reaching past the
record, which ADR-0237 dec. 7 prices at 33-51 ms per feature across a fleet. A share needs
nothing extra and cancels the roster within one beat anyway.

**Scoring the draw as a loss.** Rejected: a mutual wipe met exactly half the objective, and
`0.5` is the only value that keeps the perspectives complementary without inventing a
preference.

**Leaving the terminal verdict flat and accepting that a lost position cannot be ranked.**
The tempting reading of dec. 3a: if every candidate loses, the gambit edit does not matter,
so holding the incumbent is a fine answer. Rejected on the measurement — "lose slower" is a
real preference in a game lost by annihilation, and an AI that gives up biases the battle
length this map is built to measure. A wider band was also rejected: past a tie-break it
becomes a trade, and then it is the invented weight again.

## Consequences

- **The enemy AI now plays a different game**, in every scene that mounts the driver. The
  mount line names the objective and its horizon stance before it reports the beat shape,
  because that is the fact a session reading the log is most likely to be wrong about —
  the subsystem's prose still describes `f`.
- `RolloutValueFunction` keeps every guard it had, including the cross-language pin against
  `tools/fit_value_function.py`. The refit is owed by the **artifact**, not the class, and
  the class has to be exactly as trustworthy on the day it lands.
- The fitted artifact and `build_artifact` now carry an `objective` key. An older artifact
  without one still loads and still attributes, because `DEFAULT_ID` is the same string.
- `RolloutValueFunctionTest` grows five arms (6-10) in the **same process** — charter
  clause 13, and the setup they share is "none", so a second scene would have bought
  nothing and cost a 2.3 s boot forever.
- #1110's corpus writer must record the objective id per run. A referee corpus and a probe
  corpus produced under different objectives are not comparable, and nothing else would
  say so.

## Soft spots

- **The 50/50 weight is still a weight.** Dec. 3 bounds what it can do — it never reorders
  a verdict against an ongoing state — but two ongoing positions that differ in HP and in
  standing count are ordered by a number nobody measured.
- **`TERMINAL_BAND = 0.001` is also a number nobody measured**, and unlike the 50/50 it has
  a failure mode in each direction: too wide and the tie-break becomes a trade against the
  verdict, too narrow and it disappears into the float noise of a mean over four seeds. It
  is three orders of magnitude clear of both today, at M = 4.
- **The objective is blind to position, MP, status and action economy.** A candidate that
  sets up a kill on the next turn looks identical to one that does not; everything past
  tick `H` is carried by the horizon alone. That is a real argument for `H` being worth its
  cost here, and it is also the sharpest thing `f` had that this does not.
- **Nothing has validated it against a played corpus**, because there is not one yet at
  this tempo — that is #1110 and #1111. The claims here are rooted **statically** (the
  formula, the clamp, the omissions, the refusals, all guarded by arm 6-10 seeds) and the
  control half of arm 7 is a **dynamic** measurement of `f`'s perversity on real fixture
  rows, and dec. 3a is a **dynamic** measurement taken inside a live Gariland beat; what is
  *not* measured is whether an AI maximising this plays a better or worse Gariland than one
  maximising `f`.
- **`RESULT_DRAW` at 0.5 collides with a level ongoing state**, which the incumbent
  tie-break then resolves toward holding. Harmless and slightly odd; a draw at `H` inside a
  rollout is a mutual wipe, which is rare.
- **The `ticks <= 0` refusal is this objective's alone.** Nothing else in the tree reads
  `result` off a possibly-unwritten slot today, but `GPUBatchSimulator.get_battle_result`
  has the same shape and no such guard.
