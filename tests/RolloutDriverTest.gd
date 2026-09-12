extends Node
# test-kind: logic
# seeded-break: return `H * 0.35` from `predict_beat_ms` in src/gpu/RolloutDriver.gd instead of the composed model — arm 1 reds on every knot of ADR-0253 dec. 9's measured column, and NO OTHER ARM MOVES: the curve is still monotone, the ladder still drops M before K, the refusal still fires. That is the point of arm 1. Alternatively, swap the two budget loops in `plan` so K is shed before M — arm 3 reds on the rung order while arm 5 stays green.

## The AI's BUDGET, as a pure function (#897, §7). No GPU.
##
## `RolloutDriver.plan` is the whole of #897's reproducibility requirement: a beat
## sized by a stopwatch would search a different number of candidates every time
## the box was busy, and the AI would play a different move on the same position.
## So the cap is spent by PREDICTION, and what this file proves is that the
## prediction is worth spending — and that the ladder it drives goes down §7's
## rungs and no others.
##
## PASS: the cost model reproduces ADR-0253 dec. 9's measured forked column at the
##       shape it was measured at; it is monotone in every axis; the ladder drops
##       `M` before `K` and never touches `H`; it refuses rather than run a beat
##       that cannot fit or cannot compare; and the CRN base seed is a function of
##       the position alone.
## FAIL: any of those.
##
## 🔴 ARM 1 IS THE ONE THAT CAN CATCH A FICTION. Every other arm here would pass
## against a cost model that returned `H * 0.35` — the ladder would still order
## correctly, the refusals would still fire, the monotonicity would still hold.
## Only comparing against the ADRs' own measured milliseconds can tell a model
## from a plausible-looking curve, and a model that has drifted from the box does
## not fail loudly: it mis-sizes every beat, forever, in silence.
##
## ⚠️ ARM 3 IS A DIRECTION TEST, NOT A VALUE TEST. "Dropping M is cheaper than
## dropping K" is the decision; the milliseconds it recovers are ADR-0237 dec. 4's
## finding that it recovers almost nothing, and asserting a specific saving would
## pin the model twice — once here and once in arm 1 — and go red for a legitimate
## recalibration.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/RolloutDriverTest.tscn

## ADR-0253 dec. 9's table, at the shape it was measured at (`U = 12`, 256
## battles): H -> the FORKED beat in milliseconds. This is the oracle.
const MEASURED_FORKED := {
	100: 37.8,
	200: 69.5,
	400: 138.2,
	800: 620.9,
}
## The tolerance the oracle is compared under. ADR-0237 records repeats of one
## configuration landing within ~7%; 1% is far inside that, and is what a model
## built to pass THROUGH these knots should manage.
const TOLERANCE := 0.01

const REF_U := 12
const REF_N := 256

var _failed := false


func _ready() -> void:
	_arm_1_the_model_reproduces_the_measured_column()
	_arm_2_the_model_is_monotone_in_every_axis()
	_arm_3_the_ladder_drops_m_before_k_and_never_h()
	_arm_4_the_ladder_refuses_rather_than_shorten_the_horizon()
	_arm_5_the_shipping_shape_never_degrades()
	_arm_6_the_capacity_ladder_runs_in_the_same_order()
	_arm_7_the_base_seed_is_a_function_of_the_position()
	if _failed:
		print("[FAIL] RolloutDriver test")
	else:
		print("[PASS] RolloutDriver: the model reproduces the measured column, the ladder drops M then K and never H, and refuses at its floor")
	get_tree().quit()


## The model, against ADR-0253 dec. 9's own milliseconds.
func _arm_1_the_model_reproduces_the_measured_column() -> void:
	for h in MEASURED_FORKED:
		var want: float = MEASURED_FORKED[h]
		var got := RolloutDriver.predict_beat_ms(REF_U, REF_N, h)
		_expect(absf(got - want) <= want * TOLERANCE,
			"H=%d at the reference shape predicts %.2f ms, ADR-0253 dec. 9 measured %.2f" % [h, got, want])

	# The fork factor is not decoration: ADR-0237 dec. 6 measures a mid-battle
	# fork at about twice a fresh one, and every row above is a FORKED row. A
	# model that dropped the doubling would still be smooth, still monotone, and
	# would size every beat at half its real cost.
	_expect(absf(RolloutDriver.predict_beat_ms(REF_U, REF_N, 400) / 69.1 - 2.0) <= 0.02,
		"the prediction at H=400 should be 2x ADR-0253's FRESH 69.1 ms, reads %.2f" % [
			RolloutDriver.predict_beat_ms(REF_U, REF_N, 400)])

	# And the two axes the column does not vary, against ADR-0237's own table:
	# 4x the units for ~3.9x the time (dec. 2), against 1024x the fleet for 1.4x
	# (dec. 1). Getting these the same way round is the difference between a model
	# and a shape.
	var u_ratio := RolloutDriver.predict_beat_ms(32, REF_N, 300) \
		/ RolloutDriver.predict_beat_ms(8, REF_N, 300)
	_expect(u_ratio > 3.5 and u_ratio < 4.3,
		"U 8->32 should cost ~3.9x (ADR-0237 dec. 2), the model says %.2fx" % u_ratio)
	var n_ratio := RolloutDriver.predict_beat_ms(8, 1024, 300) \
		/ RolloutDriver.predict_beat_ms(8, 1, 300)
	_expect(n_ratio > 1.2 and n_ratio < 1.6,
		"a 1024x fleet should cost ~1.4x (ADR-0237 dec. 1), the model says %.2fx" % n_ratio)


## Monotone in `H`, in `U` and in the fleet.
##
## The fleet axis is the one that needs asserting rather than assuming: ADR-0237's
## measured row at 4 battles is 0.02 ms BELOW its row at 1, which is repeat noise
## sitting on a quantity that cannot physically fall. Read literally it makes the
## ladder a hill climb — dropping `M` from 2 to 1 would RAISE the predicted cost,
## and the loop that shed a rung to save time would have spent it.
func _arm_2_the_model_is_monotone_in_every_axis() -> void:
	var last := -1.0
	for h in [0, 50, 100, 200, 300, 400, 600, 800, 1600]:
		var v := RolloutDriver.predict_beat_ms(REF_U, REF_N, h)
		_expect(v >= last, "the model fell at H=%d (%.2f after %.2f)" % [h, v, last])
		last = v
	last = -1.0
	for u in [1, 4, 8, 12, 16, 24, 32, 64]:
		var v := RolloutDriver.predict_beat_ms(u, REF_N, 400)
		_expect(v >= last, "the model fell at U=%d (%.2f after %.2f)" % [u, v, last])
		last = v
	last = -1.0
	for n in [1, 2, 4, 8, 16, 64, 128, 256, 512, 1024, 2048]:
		var v := RolloutDriver.predict_beat_ms(REF_U, n, 400)
		_expect(v >= last, "the model fell at a fleet of %d (%.2f after %.2f)" % [n, v, last])
		last = v


## §7's ladder, in §7's order.
##
## Squeezed from above by a cap the starting shape cannot meet, the first thing to
## move must be `M`, the second `K`, and `H` must not move at all. The arm reads
## the plan's OWN `degraded` list as well as its numbers, because a plan that
## arrived at the right `(K, M)` by some other route would still be a different
## decision.
func _arm_3_the_ladder_drops_m_before_k_and_never_h() -> void:
	# A cap between "K=64 x M=4 fits" and "K=64 x M=3 fits": only M moves.
	var full := RolloutDriver.predict_beat_ms(REF_U, 64 * 4, 400)
	var one_rung := RolloutDriver.predict_beat_ms(REF_U, 64 * 3, 400)
	_expect(one_rung < full, "dropping M must lower the prediction (%.2f vs %.2f)" % [one_rung, full])
	var p: Dictionary = RolloutDriver.plan(one_rung, REF_U, 256, 64, 4, 400)
	_expect(bool(p["ok"]), "a cap of %.2f ms should still admit a beat" % one_rung)
	_expect(int(p["k"]) == 64, "M has rungs left, so K must not have moved — K=%d" % p["k"])
	_expect(int(p["m"]) == 3, "M should have dropped to 3, reads %d" % p["m"])
	_expect(int(p["horizon"]) == 400, "H must never move — reads %d" % p["horizon"])
	_expect(p["degraded"].size() == 1,
		"one rung taken should be one line reported, got %s" % [p["degraded"]])
	_expect(String(p["degraded"][0]).begins_with("M "),
		"the first rung must be M, the report says '%s'" % p["degraded"][0])

	# A cap below anything M alone can reach: M bottoms out at 1 FIRST, and only
	# then does K move.
	var floor_ms := RolloutDriver.predict_beat_ms(REF_U, 8, 400)
	var deep: Dictionary = RolloutDriver.plan(floor_ms, REF_U, 256, 64, 4, 400)
	_expect(bool(deep["ok"]), "a cap of %.2f ms should admit a degraded beat" % floor_ms)
	_expect(int(deep["m"]) == 1, "M must bottom out at 1 before K moves — M=%d" % deep["m"])
	_expect(int(deep["k"]) < 64 and int(deep["k"]) >= RolloutDriver.MIN_CANDIDATES,
		"K should have taken the remaining squeeze, reads %d" % deep["k"])
	_expect(int(deep["horizon"]) == 400, "H must never move — reads %d" % deep["horizon"])
	_expect(float(deep["predicted_ms"]) <= floor_ms,
		"a plan that reports ok must fit its cap (%.2f vs %.2f)" % [deep["predicted_ms"], floor_ms])


## The floor is a REFUSAL, and it refuses for the right reason.
##
## When the horizon alone blows the cap there is nothing left to shed: `H` is the
## one rung §7 forbids and `units_per_battle` belongs to the scenario. Running
## anyway would make the cap decoration; running at `K = 1` would spend the whole
## horizon comparing the incumbent against nothing.
func _arm_4_the_ladder_refuses_rather_than_shorten_the_horizon() -> void:
	var impossible := RolloutDriver.predict_beat_ms(REF_U, 2, 400) * 0.5
	var p: Dictionary = RolloutDriver.plan(impossible, REF_U, 256, 64, 4, 400)
	_expect(not bool(p["ok"]), "a cap below the horizon's own cost must refuse")
	_expect(int(p["horizon"]) == 400,
		"a refusal must refuse at the FULL horizon, not a shortened one — reads %d" % p["horizon"])
	_expect(int(p["k"]) == RolloutDriver.MIN_CANDIDATES,
		"the ladder should be exhausted at its floor K=%d, reads %d" % [
			RolloutDriver.MIN_CANDIDATES, p["k"]])
	_expect(String(p["reason"]).length() > 0, "a refusal must say why")

	# A fleet too small to seat even the floor is the other refusal, and it is a
	# message about `rollout_fleet_size` rather than about the cap.
	var tiny: Dictionary = RolloutDriver.plan(10000.0, REF_U, 1, 64, 4, 400)
	_expect(not bool(tiny["ok"]),
		"a one-battle fleet cannot seat a comparison, however generous the cap")

	# ...and the same fleet with room for two candidates is NOT a refusal. Without
	# this the arm above would pass against a driver that refused everything.
	var two: Dictionary = RolloutDriver.plan(10000.0, REF_U, 2, 64, 4, 400)
	_expect(bool(two["ok"]) and int(two["k"]) == 2 and int(two["m"]) == 1,
		"a two-battle fleet seats exactly K=2 x M=1, reads K=%d M=%d ok=%s" % [
			two["k"], two["m"], two["ok"]])


## ADR-0237 dec. 4 is an instruction to whoever set the cap: "set the cap so
## degradation is never the plan". At the shape this mode ships against — Gariland,
## `U` near 12 (dec. 5) — the shipped defaults must therefore take NO rung at all.
##
## This is the arm that goes red when somebody lowers `cap_ms` or raises `horizon`
## without noticing that the two are one decision.
func _arm_5_the_shipping_shape_never_degrades() -> void:
	var p: Dictionary = RolloutDriver.plan(RolloutDriver.cap_ms, REF_U,
		RolloutDriver.fleet_size, RolloutDriver.candidates, RolloutDriver.seeds,
		RolloutDriver.horizon)
	_expect(bool(p["ok"]), "the shipped defaults must admit a beat at U=%d: %s" % [REF_U, p["reason"]])
	_expect(p["degraded"].is_empty(),
		"the shipped defaults degrade at U=%d, which ADR-0237 dec. 4 says the cap exists to prevent: %s" % [
			REF_U, p["degraded"]])
	_expect(int(p["k"]) == RolloutDriver.candidates and int(p["m"]) == RolloutDriver.seeds,
		"the shipped shape should run K=%d x M=%d, plans K=%d x M=%d" % [
			RolloutDriver.candidates, RolloutDriver.seeds, p["k"], p["m"]])
	# The fleet the host allocates has to hold the shape the plan wants, or the
	# capacity ladder degrades a beat that the budget would have admitted.
	_expect(RolloutDriver.candidates * RolloutDriver.seeds <= RolloutDriver.fleet_size,
		"K=%d x M=%d does not fit the default fleet of %d battles" % [
			RolloutDriver.candidates, RolloutDriver.seeds, RolloutDriver.fleet_size])
	# ...and one shape up, because the ENTD's records are 16 wide and a battle
	# padded to U=16 is not exotic.
	var wider: Dictionary = RolloutDriver.plan(RolloutDriver.cap_ms, 16,
		RolloutDriver.fleet_size, RolloutDriver.candidates, RolloutDriver.seeds,
		RolloutDriver.horizon)
	_expect(bool(wider["ok"]), "the shipped defaults must still admit a beat at U=16: %s" % wider["reason"])


## The capacity squeeze is a different question from the budget squeeze — the
## harness cannot fill slots that do not exist — but it goes down the same rungs.
## Degrading in a different order here would make §7's order a coincidence of
## which limit happened to bite first.
func _arm_6_the_capacity_ladder_runs_in_the_same_order() -> void:
	# 64 x 4 = 256 candidates-seeds into a 64-battle fleet: M drops to 1 and K is
	# left whole, because 64 x 1 fits exactly.
	var p: Dictionary = RolloutDriver.plan(10000.0, REF_U, 64, 64, 4, 400)
	_expect(bool(p["ok"]), "a 64-battle fleet should still admit a beat")
	_expect(int(p["m"]) == 1, "M should have dropped to 1 first, reads %d" % p["m"])
	_expect(int(p["k"]) == 64, "K should be untouched once M=1 fits, reads %d" % p["k"])
	_expect(int(p["battles"]) <= 64, "the plan seats %d in a 64-battle fleet" % p["battles"])
	_expect(int(p["horizon"]) == 400, "H must never move — reads %d" % p["horizon"])

	# 20 battles cannot seat 64 x 1, so K takes the rest of it.
	var q: Dictionary = RolloutDriver.plan(10000.0, REF_U, 20, 64, 4, 400)
	_expect(int(q["m"]) == 1 and int(q["k"]) == 20,
		"a 20-battle fleet should seat K=20 x M=1, reads K=%d M=%d" % [q["k"], q["m"]])
	_expect(int(q["battles"]) <= 20, "the plan seats %d in a 20-battle fleet" % q["battles"])


## The CRN base seed must be a function of the POSITION and of nothing else.
##
## Two properties at once, and they pull apart. Reproducible: the same position
## twice gives the same seeds, or #897's requirement dies at the last step.
## Decorrelated across turns: a constant base hands every beat in a battle the
## identical luck, so a candidate flattered by seed 0 is flattered by it all
## battle — a bias averaging over `M` cannot see, because it is the same `M`.
func _arm_7_the_base_seed_is_a_function_of_the_position() -> void:
	var a := _snapshot_like(4242, 600)
	_expect(RolloutDriver.base_seed_for(a, 3) == RolloutDriver.base_seed_for(a, 3),
		"the same position must derive the same base seed")
	_expect(RolloutDriver.base_seed_for(a, 3) != RolloutDriver.base_seed_for(_snapshot_like(4242, 700), 3),
		"a different tick must derive a different base seed, or every beat shares one battle's luck")
	_expect(RolloutDriver.base_seed_for(a, 3) != RolloutDriver.base_seed_for(_snapshot_like(9999, 600), 3),
		"a different battle seed must derive a different base seed")
	_expect(RolloutDriver.base_seed_for(a, 3) != RolloutDriver.base_seed_for(a, 4),
		"a different taker must derive a different base seed")

	# And it must stay inside int32 once `crn_seeds` has spaced M seeds off it:
	# the battle header's seed field is an int32, and a seed that wrapped would
	# alias another slot's stream in a way nothing downstream could see.
	for tick in [0, 1, 600, 3500, 100000]:
		var base := RolloutDriver.base_seed_for(_snapshot_like(4242, tick), 3)
		var seeds := RolloutHarness.crn_seeds(RolloutDriver.seeds, 32,
			RolloutDriver.horizon, base)
		_expect(base > 0, "the base seed must be positive, reads %d at tick %d" % [base, tick])
		for s in seeds:
			_expect(s > 0 and s < 0x7FFFFFFF,
				"a CRN seed left int32 at tick %d: %d" % [tick, s])
		_expect(RolloutHarness.seeds_are_disjoint(seeds, 32, RolloutDriver.horizon),
			"the seeds derived at tick %d alias each other at the worst-case shape" % tick)


## A battle slice shaped like `snapshot_battle`'s, carrying only the header this
## reads. Built by hand rather than by a simulator: the arm is about the
## derivation, and a GPU would make it a slower test of the same arithmetic.
func _snapshot_like(battle_seed: int, tick: int) -> Dictionary:
	var battle := PackedInt32Array()
	battle.resize(GPUCombatPacker.BATTLE_HEADER_SIZE
		+ 32 * GPUCombatPacker.UNIT_SIZE)
	battle[GPUCombatPacker.BattleHeaderField.SEED] = battle_seed
	battle[GPUCombatPacker.BattleHeaderField.TICK] = tick
	return {"battle": battle}


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)
