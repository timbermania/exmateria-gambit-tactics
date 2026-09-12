class_name RolloutDriver
extends RefCounted

## The ENEMY AI's thinking beat, end to end (#897, design §7).
##
## [RolloutCandidates] enumerates the edits worth trying, [RolloutHarness] runs
## them as a fleet, a [RolloutObjective] ranks the rows they produce. Each of
## those three deliberately stops short of the next (ADR-0246 dec. 6, ADR-0253's
## consequences). THIS is the file that joins them, and it owns the one thing
## none of them could: **how big the beat is allowed to be.**
##
## Pure and scene-free, exactly as [AdjustmentTurn] is: it holds no node, mounts
## nothing, and the host wires it to [TurnDirector]'s `turn_opened`. Where
## `AdjustmentTurn` is what a PLAYER may do with a frozen turn, this is what the
## enemy does with one.
##
## === THE CAP IS SPENT BY PREDICTION, NOT BY A STOPWATCH =====================
##
## 🔴 #897 asks for two things that read as contradictory: a **hard wall-clock
## cap** on the beat, and a choice that is **reproducible** — "no wall-clock-
## dependent candidate truncation that changes the answer between runs on the
## same position". A beat that watched a clock and stopped when it ran out would
## satisfy the first and destroy the second: the same position, thought about
## twice on the same box, would search a different number of candidates because
## another process happened to be compiling, and the AI would play a different
## move. Not a rare race — a busy box is the normal case here.
##
## The resolution is that the cap is a BUDGET, spent before the beat by
## [method predict_beat_ms], and the stopwatch is an INSTRUMENT that reports
## afterwards and can never change the answer. [method plan] is a pure function
## of `(cap, U, fleet, K, M, H)`; every one of those is a tunable or a property
## of the scenario, so two runs on the same position plan identically, run
## identically (the kernel is bit-deterministic across processes — ADR-0237's
## measurement section) and choose identically.
##
## The price is that the cap is only as hard as the model, so the model is
## calibrated against the ADRs' own measured rows and the beat MEASURES itself
## and warns on a residual it did not predict. A model that has drifted says so
## in the log instead of biasing the search in silence.
##
## === THE LADDER'S FLOOR IS A REFUSAL ========================================
##
## §7's degradation order — **drop `M` first, then `K`, never `H`** — is a
## decision and not a knob, and it is implemented here as one. But ADR-0237
## dec. 4 measured what it recovers and the answer is *almost nothing*: the beat
## is bounded by `H` and `units_per_battle`, so shedding the fleet sheds only the
## fill leg. This model reproduces that finding rather than papering over it —
## halving `M` at the shipping shape moves the prediction by about 4 ms of ~138.
##
## So the ladder bottoms out, and what happens at the bottom is the real
## decision. It CANNOT shorten the horizon (that is the one rung §7 forbids, and
## for a reason cost cannot overrule: a short horizon biases toward immediate
## damage — the AI stops seeing heals and repositioning pay off — and bias is
## worse than variance). It cannot shrink `units_per_battle`, which the scenario
## fixes. So a plan that still does not fit **is refused**, and the turn is spent
## unchanged — which is exactly "wait" (ADR-0239) and is what the host already
## did before this file existed.
##
## Refusing is better than the two alternatives. Running anyway would make the
## cap decoration. Running at `K = 1` would spend the entire horizon to compare
## the incumbent against nothing and return the incumbent — a beat that cannot
## produce a decision is not a cheap decision, it is a wasted frame. The floor is
## therefore `K = 2`: the first `K` at which the word "search" means anything.
##
## A refusal is LOUD, naming the cap and the shape, because it is a message about
## the tunable and not about the position. ADR-0237 dec. 4's own conclusion is
## "set the cap so degradation is never the plan"; a refusal is the beat saying
## that was not done.
##
## === WHAT THIS FILE DOES NOT DO =============================================
##
## - **Decide whose turn it is.** [TurnDirector] announces a taker and never
##   classifies sides; the host decides which takers are the AI's. `NavigatorMain`
##   puts guests on team 0 and a guest is a unit the player may not command —
##   which makes it the AI's, on team 0, scored from team 0's side.
## - **Know what a `Character` is.** The candidate context (job, usable abilities,
##   max MP) is domain knowledge only a host has, so it is passed in. Same
##   discipline as `AdjustmentTurn`, and the reason both are testable with no
##   scene.
## - **Spend the turn.** [method decide] and [method apply] leave the director
##   alone. The host commits, because the host is what knows whether anything
##   else has to happen on that edge.
## - **Search more than one ply.** Multi-ply / MCTS is an explicit non-goal
##   (§7) and nothing here is a step toward it.

const GAMBITS_PER_UNIT := GPUCombatPacker.GAMBITS_PER_UNIT


#region Tunables (ADR-0068)

## ADR-0237 dec. 8 and ADR-0253 dec. 12 both deferred every one of these to
## whoever wired the AI, on the grounds that a default with no reader is a number
## nobody chose. This file is that reader, so this is where they land — as
## `static var` homes and not `const`s, because a `const` is frozen at parse time
## and a scrub could never reach it (ADR-0068 dec. 13).

const CAP_MS_SLUG := "rollout.cap_ms"
const HORIZON_SLUG := "rollout.horizon"
const CANDIDATES_SLUG := "rollout.candidates"
const SEEDS_SLUG := "rollout.seeds"
const FLEET_SIZE_SLUG := "rollout.fleet_size"

## The hard cap on ONE thinking beat, in milliseconds of FORKED cost.
##
## Forked, not fresh: ADR-0237 dec. 6 measures a mid-battle fork at about twice a
## fresh one, and the AI forks mid-battle by definition. Pricing against a
## fresh-fork row would buy a beat the bench can afford and the game cannot.
##
## 🔴 250 ms IS A FROZEN FRAME, AND THAT IS WHAT IT IS PRICED AS. The beat runs
## synchronously inside `turn_opened`, on the main thread, in a world the director
## has already stopped — so its cost is a hitch the player sees between "the
## enemy's turn opens" and "the enemy acts". 250 ms buys the calibrated horizon
## (`H = 400` predicts 138 ms at the shape this mode ships) with enough headroom
## that the ladder never fires at Gariland, which is ADR-0237 dec. 4's
## instruction taken literally.
##
## It is deliberately NOT the several-hundred-millisecond budget design §3's
## "cinematic focus beat" would eventually justify. There is no focus beat in the
## tree yet; when one lands the compute hides behind a camera move instead of a
## frozen frame, and THAT is the moment to raise this — with the animation's
## length as the argument, which is an argument nobody can make today.
static var cap_ms: float = 250.0

## `H`, the rollout horizon in ticks. `CombatLoop` ticks at 60/s, so 400 ticks is
## about 6.7 seconds of simulated battle.
##
## ADR-0253 dec. 9's calibrated knee, and the fitted artifact carries the same
## number in its `calibration()["knee_horizon"]`. [method check_horizon] compares
## the two and complains when they part, because a refit that moves the knee and
## a code default that does not is a divergence with no symptom: every score
## stays in [0, 1], every candidate still ranks, and the AI simply plays to a
## horizon its calibration was not fit for.
##
## ⚠️ AND UNDER THE OBJECTIVE ACTUALLY RUNNING, 400 IS A COST NUMBER, NOT A KNEE.
## [ProvisionalObjective] has no H-sweep behind it: a longer horizon resolves
## more of the battle, so strictly more rows carry a terminal verdict and fewer
## rest on the two-term guess, and there is no knee to find. What holds `H` at
## 400 is ADR-0256 dec. 6's pricing of a 250 ms frozen frame, which is untouched
## by which objective reads the rows. [method check_horizon] says so on every
## mount rather than passing in silence.
static var horizon: int = 400

## `K`, the candidate count offered to [method RolloutCandidates.generate] — the
## incumbent plus up to `K - 1` one-step edits. §7's starting shape, measured at
## `K = 64 × M = 4` by ADR-0237 dec. 5 and by ADR-0253's whole table.
##
## The generator may return FEWER than this (duplicates are dropped), and fewer
## is correct: a duplicated candidate spends a battle slot to learn a number it
## already has.
static var candidates: int = 64

## `M`, the common-random-number seeds each candidate is run under. The SAME `M`
## seeds across all `K`, which is what makes the comparison between two
## candidates the gambit edit and nothing else.
static var seeds: int = 4

## Battles the host allocates, `K × M` at the default shape.
##
## 🔴 READ ONCE, AT BOOT. The simulator's buffers are sized in one call
## (`CombatLoop.rollout_fleet_size`, consumed by `setup_gpu_simulator`), so
## scrubbing this mid-battle changes nothing — and [method plan] treats whatever
## the simulator actually allocated as the ceiling rather than trusting this.
## That is not belt-and-braces: a scrub that raised `K × M` above the allocated
## fleet would otherwise reach `RolloutHarness.run`'s refusal, and a beat that
## refuses because a *slider moved* is the wall-clock-dependence #897 forbids,
## wearing different clothes.
static var fleet_size: int = 256

## WHICH OBJECTIVE THE SEARCH MAXIMISES. [method make_objective] resolves it.
##
## 🔴 THE PROVISIONAL OBJECTIVE, FOR THE LENGTH OF THE REBALANCING MAP (#1101),
## AND SAID OUT LOUD RATHER THAN DEFAULTED INTO. ADR-0274: `f` was fit before
## #939 changed the tempo ~48x and pays a unit to spend no MP, take no damage and
## stand off; refitting it needs a corpus at the SETTLED tempo, which does not
## exist until the numbers are dialed. Leaving the game on `f` while the referee
## rig measured something else would have been worse than either — the rig would
## be measuring a game nobody plays, which is the exact failure #1109 was written
## to avoid. So there is ONE selection and both callers read it.
##
## Deliberately NOT a `Tune` slug: a tunable is a number a scrub may move mid-run
## (ADR-0068), and this is a MODE whose change invalidates every corpus already
## written under the other one. Flipping it back to [constant
## RolloutValueFunction.DEFAULT_ID] is the refit's landing, and it should be a
## reviewable line in a diff.
static var objective_id: String = ProvisionalObjective.ID


## The objective named by `id`, or `null` when nothing answers to that name.
##
## Refusing an unknown name rather than falling back to a default is the point: a
## typo'd id that quietly resolved to `f` would produce a corpus attributed to an
## objective that never ran, and nothing downstream could tell.
static func make_objective(id: String) -> RolloutObjective:
	if id == ProvisionalObjective.ID:
		return ProvisionalObjective.new()
	if id == RolloutValueFunction.DEFAULT_ID:
		return RolloutValueFunction.new()
	push_error("[RolloutDriver] no objective answers to '%s' — known: '%s', '%s'" % [
		id, ProvisionalObjective.ID, RolloutValueFunction.DEFAULT_ID])
	return null


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## This owner's named registration entry point (ADR-0173): `_static_init` calls it
## at class load — the only thing that does — and the guards call it to read back
## which slugs this owner binds.
static func register_tunables() -> void:
	Tune.bind(CAP_MS_SLUG, cap_ms, {"min": 16.0, "max": 2000.0, "step": 1.0})
	Tune.bind(HORIZON_SLUG, horizon, {"min": 1, "max": 2000, "step": 10})
	Tune.bind(CANDIDATES_SLUG, candidates, {"min": 1, "max": 512, "step": 1})
	Tune.bind(SEEDS_SLUG, seeds, {"min": 1, "max": 32, "step": 1})
	Tune.bind(FLEET_SIZE_SLUG, fleet_size, {"min": 1, "max": 2048, "step": 1})


## The fleet size a host should allocate, coalesced. Its own accessor rather than
## a field of [method settings] because it is read at a different TIME — once, at
## boot, before any beat exists — and reading the other four there would stamp
## them as consumed on a frame no beat looked at them.
static func fleet_size_now() -> int:
	return int(Tune.get_value(FLEET_SIZE_SLUG))


## The coalesced tunable values, pull-read (ADR-0068 R5).
##
## A pull and not a `Tune.on_update` write-back, for the reason `get_value`'s own
## documentation gives: this reads its whole input set ONCE per beat and picks up
## a scrub the next time it runs, so a standing subscription would buy nothing —
## and there is no `Node` here to scope one to.
static func settings() -> Dictionary:
	return {
		"cap_ms": float(Tune.get_value(CAP_MS_SLUG)),
		"horizon": int(Tune.get_value(HORIZON_SLUG)),
		"candidates": int(Tune.get_value(CANDIDATES_SLUG)),
		"seeds": int(Tune.get_value(SEEDS_SLUG)),
		"fleet_size": int(Tune.get_value(FLEET_SIZE_SLUG)),
	}

#endregion


#region The cost model

## ADR-0237 dec. 6: a rollout forked from a mid-battle position costs about twice
## a fresh one, and the fresh rows are therefore a floor rather than an
## expectation. Every number below is a FRESH measurement; this is what turns
## them into the quantity the cap is written in.
const FORK_FACTOR := 2.0

## `H` → fresh beat in ms, at the reference shape (`U = 12`, 256 battles), from
## ADR-0253 dec. 9's measured table — the freshest rows in the tree and the only
## ones taken at the shape this mode ships against.
##
## `H = 0` anchors the curve at the origin: a beat that simulates nothing costs
## nothing. Interpolation is LINEAR BETWEEN KNOTS and the knots are the whole
## curvature — cost per tick climbs 4.5× across a battle (ADR-0237 dec. 3), which
## is why 400 → 800 costs 4.5× here and not 2×, and why extrapolating above 800
## carries the last segment's steep slope rather than the average.
const HORIZON_KNOTS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(100.0, 18.9),
	Vector2(200.0, 34.7),
	Vector2(400.0, 69.1),
	Vector2(800.0, 310.5),
]

## `units_per_battle` → run leg in ms, at one battle and `H = 300` (ADR-0237's
## table). Interpolated LINEARLY IN `U`, because dec. 2's own reading of these
## rows is that 4× the units costs 3.9× the time: four of the eight passes run one
## thread per battle and loop over all `U` inside it, so `U` buys serial work.
const UNIT_KNOTS: Array[Vector2] = [
	Vector2(8.0, 27.62),
	Vector2(16.0, 45.25),
	Vector2(32.0, 109.05),
]

## Fleet size → run leg in ms, at `U = 8` and `H = 300` (ADR-0237's table).
##
## Interpolated linearly in **log2(N)**, not in `N`, and that is the difference
## between a model and a fiction: dec. 1 measures 1024 battles costing 1.41× what
## one costs, because a tick is 8 dispatches and 7 barriers and is bound by that
## overhead rather than by compute. A curve that flat over three decades is
## logarithmic, and interpolating it linearly would price a 128-battle fleet at
## half of a 256-battle one.
##
## 🔴 READ THROUGH A MONOTONE ENVELOPE — see [method _monotone]. The measured row
## at `N = 4` is 0.02 ms BELOW the row at `N = 1`, which is repeat noise (ADR-0237
## records repeats landing within ~7%) sitting on top of a quantity that cannot
## physically fall as the fleet grows. Left alone it makes the degradation ladder
## a hill climb: dropping `M` from 2 to 1 would *raise* the predicted cost, and a
## rung that costs more than the rung above it is not a ladder.
const FLEET_KNOTS: Array[Vector2] = [
	Vector2(1.0, 27.62),
	Vector2(4.0, 27.60),
	Vector2(16.0, 29.81),
	Vector2(64.0, 31.93),
	Vector2(256.0, 33.81),
	Vector2(1024.0, 39.08),
]

## The shape [constant HORIZON_KNOTS] was measured at. The unit and fleet axes
## are expressed as RATIOS against these, so at the reference shape they are both
## exactly 1.0 and the prediction is ADR-0253's own row.
const REFERENCE_UNITS := 12
const REFERENCE_BATTLES := 256


## Predicted cost of one thinking beat, in milliseconds, FORKED.
##
## 🔴 THIS IS AN ESTIMATE AND THE BEAT MEASURES THE TRUTH. Its job is to order
## the degradation ladder and to keep the cap out of the wall clock, not to be
## right to the millisecond. [method decide] times itself and reports the
## residual, so a model that has drifted — a new GPU, a shader change, a wider
## record — is visible in the log rather than silently mis-sizing every beat.
##
## Separable in its three axes, which is the ADRs' own claim about them rather
## than a convenience: the fleet is nearly free (dec. 1), `U` is the expensive
## axis (dec. 2), and `H` is the only superlinear one (dec. 3). At the reference
## shape it reproduces ADR-0253 dec. 9's forked column exactly, by construction.
static func predict_beat_ms(units_per_battle: int, battles: int, p_horizon: int) -> float:
	var base := _interpolate(HORIZON_KNOTS, maxf(0.0, float(p_horizon)))
	var unit_factor := _interpolate(UNIT_KNOTS, maxf(1.0, float(units_per_battle))) \
		/ _interpolate(UNIT_KNOTS, float(REFERENCE_UNITS))
	var fleet_factor := _interpolate_log2(FLEET_KNOTS, maxf(1.0, float(battles))) \
		/ _interpolate_log2(FLEET_KNOTS, float(REFERENCE_BATTLES))
	return FORK_FACTOR * base * unit_factor * fleet_factor


## Piecewise-linear over the knots, extrapolating past either end along that
## end's own segment. Extrapolation is deliberate rather than a clamp: a clamp
## would price `H = 1600` at `H = 800`'s cost and hand the ladder a plan that
## cannot possibly fit, which is the one direction an estimate must not err in.
static func _interpolate(knots: Array[Vector2], x: float) -> float:
	if knots.size() == 1:
		return knots[0].y
	var i := 0
	while i < knots.size() - 2 and x > knots[i + 1].x:
		i += 1
	var a: Vector2 = knots[i]
	var b: Vector2 = knots[i + 1]
	if is_equal_approx(a.x, b.x):
		return a.y
	return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)


static func _interpolate_log2(knots: Array[Vector2], x: float) -> float:
	var logged: Array[Vector2] = []
	for k in _monotone(knots):
		logged.append(Vector2(log(maxf(1.0, k.x)) / log(2.0), k.y))
	return _interpolate(logged, log(maxf(1.0, x)) / log(2.0))


## The running maximum over a knot list's `y`, so a measured dip inside the
## repeat noise cannot make the curve fall. Applied only where the underlying
## quantity is known to be non-decreasing — see [constant FLEET_KNOTS].
static func _monotone(knots: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var high := -INF
	for k in knots:
		high = maxf(high, k.y)
		out.append(Vector2(k.x, high))
	return out

#endregion


#region The plan

## The `K` below which a beat has stopped being a search. `K = 1` is the
## incumbent alone: the whole horizon spent to compare it against nothing and
## return it. See the class header — the floor is a refusal, not a rung.
const MIN_CANDIDATES := 2


## Size the beat: the largest `(K, M)` at this `H` that the cap and the allocated
## fleet both admit, degraded in §7's fixed order.
##
## Pure and total. Every input is a tunable or a property of the scenario, and
## none of them is a clock — which is the whole of #897's reproducibility
## requirement, discharged here rather than defended downstream.
##
## The two ladders are the same ladder run for two different reasons, and both
## run in §7's order:
##
##   1. **Capacity.** `K × M` may not exceed the battles the simulator actually
##      allocated. Not a budget question at all — the harness cannot fill slots
##      that do not exist — but degrading in a different order here would make
##      the order a coincidence of which limit bit first.
##   2. **Budget.** Then, while the prediction exceeds the cap: drop `M` to 1,
##      then `K` to [constant MIN_CANDIDATES], then refuse.
##
## `H` is never touched on either ladder. It is not that `H` is expensive to
## change — it is the ONLY lever that would actually recover the time — it is
## that shortening it biases the search, and every other rung only adds noise.
##
## Returns `{ok, k, m, horizon, battles, predicted_ms, cap_ms, degraded, reason}`.
## `degraded` is a list of the rungs taken, in order, and it is empty on the
## happy path — ADR-0237 dec. 4's "set the cap so degradation is never the plan"
## is a claim this field can be read against.
static func plan(p_cap_ms: float, units_per_battle: int, fleet_battles: int,
		k: int, m: int, p_horizon: int) -> Dictionary:
	var degraded: Array[String] = []
	if k < 1 or m < 1 or p_horizon < 1 or fleet_battles < 1 or units_per_battle < 1:
		return _refuse(k, m, p_horizon, p_cap_ms, 0.0, degraded,
			"a beat needs K>=1 M>=1 H>=1 in a fleet of >=1 battle at U>=1 — got K=%d M=%d H=%d fleet=%d U=%d" % [
				k, m, p_horizon, fleet_battles, units_per_battle])
	var k0 := k
	var m0 := m

	# --- 1. Capacity: fit inside the fleet the simulator really allocated.
	while k * m > fleet_battles and m > 1:
		m -= 1
	if m != m0:
		degraded.append("M %d->%d (the fleet holds %d battles)" % [m0, m, fleet_battles])
	while k * m > fleet_battles and k > 1:
		k -= 1
	if k != k0:
		degraded.append("K %d->%d (the fleet holds %d battles)" % [k0, k, fleet_battles])

	# --- 2. Budget: fit inside the cap, by prediction. One rung at a time and not
	# solved in closed form, because the rungs ARE the decision: a `degraded` line
	# reading "M 4->1 recovered 7.7 ms of a 138 ms beat" is ADR-0237 dec. 4 being
	# re-measured every time it fires, which is the only thing that would ever
	# tell us the finding had stopped being true.
	var predicted := predict_beat_ms(units_per_battle, k * m, p_horizon)
	var before := predicted
	var m1 := m
	while predicted > p_cap_ms and m > 1:
		m -= 1
		predicted = predict_beat_ms(units_per_battle, k * m, p_horizon)
	if m != m1:
		degraded.append("M %d->%d (recovered %.1f ms toward a %.1f ms cap)" % [
			m1, m, before - predicted, p_cap_ms])
	before = predicted
	var k1 := k
	while predicted > p_cap_ms and k > MIN_CANDIDATES:
		k -= 1
		predicted = predict_beat_ms(units_per_battle, k * m, p_horizon)
	if k != k1:
		degraded.append("K %d->%d (recovered %.1f ms toward a %.1f ms cap)" % [
			k1, k, before - predicted, p_cap_ms])

	if k < MIN_CANDIDATES:
		return _refuse(k, m, p_horizon, p_cap_ms, predicted, degraded,
			"the fleet holds %d battles, which cannot seat %d candidates x 1 seed — a beat below K=%d compares the incumbent against nothing (CombatLoop.rollout_fleet_size / %s)" % [
				fleet_battles, MIN_CANDIDATES, MIN_CANDIDATES, FLEET_SIZE_SLUG])
	if predicted > p_cap_ms:
		return _refuse(k, m, p_horizon, p_cap_ms, predicted, degraded,
			"H=%d at U=%d predicts %.1f ms forked and the cap is %.1f ms — the ladder is exhausted at K=%d M=1 and H is the one rung it may not take (§7). Raise %s or lower %s; do NOT shorten the horizon, which biases the search toward immediate damage" % [
				p_horizon, units_per_battle, predicted, p_cap_ms, k, CAP_MS_SLUG, HORIZON_SLUG])

	return {
		"ok": true,
		"k": k,
		"m": m,
		"horizon": p_horizon,
		"battles": k * m,
		"predicted_ms": predicted,
		"cap_ms": p_cap_ms,
		"degraded": degraded,
		"reason": "",
	}


static func _refuse(k: int, m: int, p_horizon: int, p_cap_ms: float, predicted: float,
		degraded: Array[String], reason: String) -> Dictionary:
	return {
		"ok": false,
		"k": k,
		"m": m,
		"horizon": p_horizon,
		"battles": maxi(0, k) * maxi(0, m),
		"predicted_ms": predicted,
		"cap_ms": p_cap_ms,
		"degraded": degraded,
		"reason": reason,
	}

#endregion


#region Wiring

var _sim: GPUBatchSimulator = null
var _live_battle: int = 0
var _value: RolloutObjective = null
var _harness: RolloutHarness = null


func _init(sim: GPUBatchSimulator, live_battle: int = 0,
		value: RolloutObjective = null) -> void:
	_sim = sim
	_live_battle = live_battle
	_value = value if value != null else make_objective(objective_id)
	_harness = RolloutHarness.new(sim, live_battle)


## Is this driver able to think at all? A driver whose objective did not load
## ranks by a constant and every candidate ties, so the beat would spend the whole
## horizon and then return the incumbent by tie-break — an expensive way to do
## nothing, and indistinguishable in the log from a search that considered its
## options and held.
func is_ready() -> bool:
	return _sim != null and _sim.is_initialized() and _value != null and _value.is_loaded()


## What this driver maximises. Its [method RolloutObjective.id] is what a run
## records so the corpus it produced stays attributable.
func objective() -> RolloutObjective:
	return _value


## Is `H` a horizon this objective can vouch for? Returns
## `{"agrees": bool, "kind": RolloutObjective.Horizon, "message": String}`.
##
## 🔴 THE UNCALIBRATED CASE IS AN ANSWER, NOT A PASS. This guard used to return
## `true` whenever the artifact declared no knee, on the reading that an older
## artifact is not an error — and that reading is exactly how a hand-written
## objective would have walked through it in silence. A guard that passes because
## there was nothing to check against is worse than no guard, so the three states
## are now distinct and two of them say so in the log:
##
## - **CALIBRATED and equal** — the only silent pass. ADR-0253 dec. 12 ships
##   `knee_horizon` as an INPUT to this file's `horizon` default, so a refit that
##   moves the knee is supposed to move the default; nothing else in the tree
##   would notice that it had not.
## - **CALIBRATED and different** — a refit moved the knee and the default did
##   not follow. The original complaint, unchanged.
## - **UNCALIBRATED** — no H-sweep exists, so no `H` can be checked against this
##   objective at all. Under [ProvisionalObjective] that is the DESIGN and not a
##   defect (`H` is bounded by cost, ADR-0256 dec. 6) — but a run has to carry
##   the sentence, because "H = 400 is the calibrated knee" is the claim the rest
##   of the subsystem's prose still makes.
static func check_horizon(value: RolloutObjective, h: int) -> Dictionary:
	var stance := value.horizon_stance()
	var kind := int(stance.get("kind", RolloutObjective.Horizon.UNCALIBRATED))
	if kind == RolloutObjective.Horizon.CALIBRATED:
		var knee := int(stance.get("knee", -1))
		if knee == h:
			return {"agrees": true, "kind": kind,
				"message": "H=%d is objective '%s'’s calibrated knee" % [h, value.id()]}
		var diverged := "H=%d but '%s' calibrated its knee at %d — a refit moved the knee and %s did not follow it (ADR-0253 dec. 12)" % [
			h, value.id(), knee, HORIZON_SLUG]
		push_warning("[RolloutDriver] %s" % diverged)
		return {"agrees": false, "kind": kind, "message": diverged}
	var uncalibrated := "H=%d is NOT calibration-backed: objective '%s' is uncalibrated — %s" % [
		h, value.id(), stance.get("why", "no reason given")]
	push_warning("[RolloutDriver] %s" % uncalibrated)
	return {"agrees": false, "kind": kind, "message": uncalibrated}

#endregion


#region The beat

## Think about `taker`'s turn and return the decision. Changes nothing.
##
## `team` is the taker's side, as [signal TurnDirector.turn_opened] emits it, and
## it is the PERSPECTIVE the value function scores from. It is passed rather than
## derived because the director already knows it — and it is checked against the
## GPU's own team split, because scoring from the wrong side is the exact shape of
## silent defect this subsystem keeps producing: every score stays a probability
## in [0, 1], every candidate still ranks, and the AI plays to lose.
##
## `ctx` is [method RolloutCandidates.make_context] — the taker's job, its usable
## abilities and its max MP. Host knowledge; see the class header.
##
## Returns `{ok, held, candidate, objective, value, value_incumbent, rows, plan,
## beat_ms, ranked, reason}`. `ok` false means the turn should be spent
## unchanged, and `reason` says why in a sentence a log can carry.
##
## `value` is the WINNER's objective value, not a probability — only one of the
## two objectives returns one, and a key named `p_victory` was a claim the
## provisional objective could not honour (ADR-0274 dec. 4).
func decide(taker: int, team: int, ctx: Dictionary) -> Dictionary:
	if not is_ready():
		return _no_decision("the driver is not ready — %s" % (
			"no initialized simulator" if _sim == null or not _sim.is_initialized()
			else "objective '%s' is not loaded" % objective_id))

	var units_per_battle := _sim.get_units_per_battle()
	if taker < 0 or taker >= units_per_battle:
		return _no_decision("unit %d is not in a %d-unit battle" % [taker, units_per_battle])

	var s := settings()
	var sized: Dictionary = plan(s["cap_ms"], units_per_battle, _sim.get_num_battles(),
		s["candidates"], s["seeds"], s["horizon"])
	if not bool(sized["ok"]):
		push_warning("[RolloutDriver] no beat: %s" % sized["reason"])
		return _no_decision(sized["reason"], sized)
	if not sized["degraded"].is_empty():
		push_warning("[RolloutDriver] the beat degraded before it ran — %s. ADR-0237 dec. 4: the cap should be set so this never happens, and the rungs recover almost nothing" % [
			", ".join(sized["degraded"])])

	var pristine: Dictionary = _sim.snapshot_battle(_live_battle)
	if pristine.is_empty():
		return _no_decision("could not snapshot the live battle %d" % _live_battle, sized)
	var rows: PackedInt32Array = RolloutHarness.rows_from_snapshot(pristine, taker)
	if rows.size() != GAMBITS_PER_UNIT:
		return _no_decision("unit %d's gambit image read back as %d ints, expected %d" % [
			taker, rows.size(), GAMBITS_PER_UNIT], sized)

	# The perspective, cross-checked against the shader's own byte. See
	# `team_in_snapshot` for why the announced team is not simply trusted, and why
	# the midpoint is not what answers this.
	var gpu_team := team_in_snapshot(pristine, taker)
	if gpu_team < 0:
		return _no_decision("unit %d has no team field in the snapshot" % taker, sized)
	if team != gpu_team:
		push_error("[RolloutDriver] unit %d was announced on team %d and its GPU unit block says team %d — the value function would score this beat from the wrong side, and every score would still be a probability" % [
			taker, team, gpu_team])
		return _no_decision("taker %d's announced team (%d) disagrees with its GPU unit block (%d)" % [
			taker, team, gpu_team], sized)

	var pool: Array = RolloutCandidates.generate(rows, ctx, int(sized["k"]))
	if pool.size() < MIN_CANDIDATES:
		# Not a failure of the budget: this unit's gambit list admits no distinct
		# edit at all (every slot full of the same row, no usable ability). The
		# incumbent is the only candidate and running it would learn nothing.
		return _no_decision("unit %d's list yields %d distinct candidate(s) — nothing to compare the incumbent against" % [
			taker, pool.size()], sized)

	var crn := RolloutHarness.crn_seeds(int(sized["m"]), units_per_battle,
		int(sized["horizon"]), base_seed_for(pristine, taker))

	var t0 := Time.get_ticks_usec()
	var beat: Dictionary = _harness.run(taker, pool, crn, int(sized["horizon"]))
	var beat_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if beat.is_empty():
		return _no_decision("the harness refused the beat — see its error", sized, beat_ms)

	var ranked: Array = _value.rank_candidates(beat["rows"], team)
	if ranked.is_empty():
		return _no_decision("no candidate scored — objective '%s' refused every row" % _value.id(), sized, beat_ms)

	# The stopwatch, reporting only. It is read AFTER every decision this method
	# makes, and nothing downstream branches on it — see the class header for why
	# that separation is the whole design and not an oversight.
	if beat_ms > float(sized["cap_ms"]):
		push_warning("[RolloutDriver] the beat took %.1f ms against a %.1f ms cap (predicted %.1f) — the cost model has drifted from the box, and the cap is only as hard as the model" % [
			beat_ms, sized["cap_ms"], sized["predicted_ms"]])

	var best: Dictionary = ranked[0]
	var incumbent := _value_of(ranked, 0)
	var winner := int(best["candidate"])
	return {
		"ok": true,
		"held": winner == 0,
		"candidate": winner,
		"objective": _value.id(),
		"value": float(best["value"]),
		"value_incumbent": incumbent,
		"rows": (pool[winner] as PackedInt32Array).duplicate(),
		"plan": sized,
		"ranked": ranked,
		"beat_ms": beat_ms,
		"predicted_ms": float(sized["predicted_ms"]),
		"reason": "",
	}


## Land a decision's gambit image on the live battle.
##
## Writes through `snapshot_battle` / `restore_battle` rather than a raw gambit
## poke, so the edit goes in by the SAME primitive the rollout installed its
## candidates with and ADR-0235's bit-identity test covers it. The other three
## slices are written back exactly as they were read a moment earlier — the world
## is frozen for the length of a turn, so "exactly as they were" is a fact and not
## a hope.
##
## A held decision is not applied: the winning image IS the incumbent, so the
## write would be a no-op, and skipping it keeps "the AI changed its mind" and
## "the AI held" distinguishable at the one place that could tell.
func apply(taker: int, rows: PackedInt32Array) -> bool:
	if _sim == null or not _sim.is_initialized():
		push_error("[RolloutDriver] no initialized simulator to apply a decision to")
		return false
	if rows.size() != GAMBITS_PER_UNIT:
		push_error("[RolloutDriver] a decision's image is %d ints, expected %d" % [
			rows.size(), GAMBITS_PER_UNIT])
		return false
	var snap: Dictionary = _sim.snapshot_battle(_live_battle)
	if snap.is_empty():
		push_error("[RolloutDriver] could not snapshot the live battle %d to apply a decision" % _live_battle)
		return false
	var gambits: PackedInt32Array = (snap["gambits"] as PackedInt32Array).duplicate()
	if not RolloutCandidates.write_unit_rows(gambits, taker, rows):
		return false
	snap["gambits"] = gambits
	return _sim.restore_battle(_live_battle, snap)


## The CRN base seed for one beat, derived from the POSITION and nothing else.
##
## Two properties have to hold at once and they pull in opposite directions.
## **Reproducible**: the same position must produce the same seeds, or #897's
## requirement is lost at the last step. **Decorrelated across turns**: a constant
## base would hand every beat in a battle the identical luck, so a candidate that
## happened to be flattered by seed 0 would be flattered by it on every turn, for
## the whole battle — a bias that averaging over `M` cannot see, because it is
## the same `M`.
##
## A hash over `(battle seed, tick, taker)` gives both. All three come out of the
## snapshot the beat is about to fork, so it is a function of the position; the
## tick moves every turn, so the luck does.
##
## Kept well inside 32 bits: `crn_seeds` spaces `M` seeds `(U-1) * 1000 + H`
## apart, and the battle header's seed field is an int32.
## Which team does `taker`'s unit block say it is on? `-1` when the snapshot is
## too short to hold the field.
##
## 🔴 THE MIDPOINT DOES NOT ANSWER THIS, AND BELIEVING IT DOES IS A LIVE HAZARD.
## `CombatLoop` documents team 0 as filling `[0, units_per_battle/2)` — but
## `set_battle_units` seats the two rosters CONTIGUOUSLY, so team 1 begins at
## `team0.size()`, and the two agree only when `team0.size()` is exactly
## `units_per_battle / 2`. `GambitBattle` sizes the battle as
## `2 x max(team0, team1)`, which holds that invariant only while the player's
## side is the larger one — a 5-deployed / 6-enemy Gariland puts unit 5 on team 1
## and BELOW the midpoint. Reading the field the packer wrote is right in every
## seating; reading the midpoint is right in most of them, which is worse.
static func team_in_snapshot(snap: Dictionary, taker: int) -> int:
	var battle: PackedInt32Array = snap.get("battle", PackedInt32Array())
	var offset := GPUCombatPacker.BATTLE_HEADER_SIZE \
		+ taker * GPUCombatPacker.UNIT_SIZE + GPUCombatPacker.UnitField.TEAM
	if taker < 0 or offset >= battle.size():
		return -1
	return battle[offset]


static func base_seed_for(snap: Dictionary, taker: int) -> int:
	var header: PackedInt32Array = snap.get("battle", PackedInt32Array())
	var battle_seed := 0
	var tick := 0
	if header.size() > GPUCombatPacker.BattleHeaderField.SEED:
		battle_seed = header[GPUCombatPacker.BattleHeaderField.SEED]
		tick = header[GPUCombatPacker.BattleHeaderField.TICK]
	return 1 + absi(hash([battle_seed, tick, taker])) % 1000000


func _value_of(ranked: Array, candidate: int) -> float:
	for row in ranked:
		if int((row as Dictionary)["candidate"]) == candidate:
			return float(row["value"])
	return RolloutObjective.CANNOT_SCORE


func _no_decision(reason: String, sized: Dictionary = {}, beat_ms: float = 0.0) -> Dictionary:
	return {
		"ok": false,
		"held": true,
		"candidate": -1,
		"objective": _value.id() if _value != null else "",
		"value": RolloutObjective.CANNOT_SCORE,
		"value_incumbent": RolloutObjective.CANNOT_SCORE,
		"rows": PackedInt32Array(),
		"plan": sized,
		"ranked": [],
		"beat_ms": beat_ms,
		"predicted_ms": float(sized.get("predicted_ms", 0.0)),
		"reason": reason,
	}

#endregion
