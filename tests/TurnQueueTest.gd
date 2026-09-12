extends Node
## Turn queue / turn meter arithmetic test (ADR-0236). Pure GDScript — no GPU,
## no RenderingDevice, no scene setup.
##
## Guards the CPU half of the turn clock. The GPU half (does the kernel actually
## advance the meter, and does it keep advancing mid-cast) is GPUTurnMeterTest;
## split because a real battle can only exercise the meter values it happens to
## reach, while everything below is exhaustive over cases a battle never shows.
##
##   1. Seeded start — `initial_turn_meter` is pure, lands in [0, FULL), matches
##      a golden vector computed from the shader's own PCG (the 32-bit masking a
##      64-bit GDScript int makes easy to get subtly wrong), and does NOT hand
##      every unit the same value.
##   2. Speed-0 is a Speed-1 unit, not a frozen one — `gain_per_tick` mirrors the
##      kernel's `max(1, speed)`, and without it arm 5 would not terminate.
##   3. Carry, not reset — over a long run the turn COUNT equals
##      floor((start + ticks*speed) / FULL) exactly. Reset-to-zero quantizes and
##      drifts, and this is the arm that measures the drift instead of asserting
##      the implementation back at itself. Its horizons are counted in TURNS, not
##      ticks, and its control speed is coprime to FULL — both because the flat
##      tick horizon it used to have went vacuous the moment FULL changed. The
##      reasoning is at the arm.
##   4. Order — meter descending, then team, then unit index; dead units absent.
##   5. Forecast vs brute force — the closed-form projection is compared, entry
##      for entry, against a naive one-tick-at-a-time simulation of the same
##      rule. The closed form is the whole reason S6's forecast is free, and it
##      is the part that can silently skip a turn.
##   6. Round-robin depth — every living unit appears at least once, however
##      lopsided the Speed spread.

const FULL := GPUCombatPacker.TURN_METER_FULL


func _ready() -> void:
	var failed := false
	failed = _arm_1_seeded_start() or failed
	failed = _arm_2_speed_zero() or failed
	failed = _arm_3_carry_not_reset() or failed
	failed = _arm_4_order() or failed
	failed = _arm_5_forecast_vs_brute_force() or failed
	failed = _arm_6_round_robin_depth() or failed

	if failed:
		print("[FAIL] Turn queue test")
	else:
		print(("[PASS] Turn queue: seeded start + carry + order + forecast-vs-brute-force."
			+ " FULL=%d; arm 3 ran %d turns of exactness and a %d-turn control at speed %d"
			+ " (%d ticks)") % [
			FULL, EXACTNESS_TURNS, CONTROL_TURNS, CONTROL_SPEED,
			_ticks_for_turns(CONTROL_SPEED, CONTROL_TURNS)])
	get_tree().quit()


## --- 1. Seeded start ------------------------------------------------------
func _arm_1_seeded_start() -> bool:
	var failed := false
	# Golden vector: pcg_hash(seed + unit*1000) % FULL, computed independently from
	# combat_common.glslinc's `pcg_hash` / `rand_int` — NOT read back off the mirror
	# it is here to check.
	#
	# ⚠️ THE VECTOR IS MODULUS-SPECIFIC, and it went stale once. `01ae0bda7` moved
	# FULL 100 -> 3600 without recomputing it, and the four reds that produced all
	# said "the 32-bit PCG mirror is wrong" — about a mirror that was fine. Every
	# stale value was the true one mod 100 (95/295, 27/427, 44/1544, 1/201), which
	# is the signature of a changed modulus rather than a changed hash. So the
	# modulus is PINNED below: move FULL again and this arm names the recompute
	# instead of blaming the hash.
	if FULL != GOLDEN_FULL:
		print(("[FAIL] the golden vector was computed at FULL=%d and FULL is now %d."
			+ " Recompute it from combat_common.glslinc's pcg_hash — `pcg_hash(seed +"
			+ " unit*1000) %% FULL` — and update GOLDEN_FULL. Do NOT paste in what this"
			+ " run printed: that asserts the mirror back at itself.") % [GOLDEN_FULL, FULL])
		failed = true
	var golden := [[0, 0, 2], [0, 1, 295], [1234, 0, 427], [1234, 3, 1544], [99999, 7, 201]]
	for g in golden:
		var got: int = GPUCombatPacker.initial_turn_meter(g[0], g[1])
		if got != g[2]:
			print("[FAIL] initial_turn_meter(%d, %d) = %d, expected %d (32-bit PCG mirror is wrong)" % [
				g[0], g[1], got, g[2]])
			failed = true

	var distinct := {}
	for seed in range(64):
		for u in range(8):
			var v: int = GPUCombatPacker.initial_turn_meter(seed, u)
			if v < 0 or v >= FULL:
				print("[FAIL] initial_turn_meter(%d, %d) = %d, outside [0, %d)" % [seed, u, v, FULL])
				failed = true
			if v != GPUCombatPacker.initial_turn_meter(seed, u):
				print("[FAIL] initial_turn_meter(%d, %d) is not pure" % [seed, u])
				failed = true
			distinct[v] = true
	# An all-zero (or constant) start is the lockstep opening dec. 3 exists to
	# avoid, and it is what a mis-masked hash degenerates to.
	if distinct.size() < 50:
		print("[FAIL] initial_turn_meter spread is %d distinct values over 512 draws — near-constant" % distinct.size())
		failed = true
	return failed


## --- 2. Speed 0 ------------------------------------------------------------
func _arm_2_speed_zero() -> bool:
	var failed := false
	if TurnQueue.gain_per_tick(0) != 1:
		print("[FAIL] gain_per_tick(0) = %d, expected 1" % TurnQueue.gain_per_tick(0))
		failed = true
	if TurnQueue.gain_per_tick(7) != 7:
		print("[FAIL] gain_per_tick(7) = %d, expected 7" % TurnQueue.gain_per_tick(7))
		failed = true
	# A Speed-0 unit must still appear in the forecast, or the queue is a lie.
	var rows := [_row(0, 0, 0, 0), _row(1, 1, 10, 0)]
	var fc: Array = TurnQueue.forecast(rows)
	var seen := {}
	for e in fc:
		seen[int(e["index"])] = true
	if not seen.has(0):
		print("[FAIL] Speed-0 unit never appears in the forecast (%d entries)" % fc.size())
		failed = true
	return failed


## --- 3. Carry, not reset ---------------------------------------------------
## Arm 3's speeds and horizons. Expressed in TURNS, never in ticks — see
## `_ticks_for_turns`. `DIVISOR_SPEEDS` must divide FULL (arm 3b asserts it);
## `CONTROL_SPEED` must be COPRIME to FULL or the control cannot fire at all.
## 49 rather than a smaller coprime speed purely for cost: gcd(49, 3600) == 1 and it
## clears a whole turn of drift inside 150 turns (~11k ticks), where speed 11 needs
## 600 turns (~196k) and speed 7 needs 900 (~463k) for the same signal.
const EXACTNESS_SPEEDS := [3, 7, 8, 11, 50]
const DIVISOR_SPEEDS := [3, 8, 50]
const STARTS := [0, 37, 99]
const EXACTNESS_TURNS := 20
const CONTROL_SPEED := 49
const CONTROL_TURNS := 150

## The modulus the arm-1 golden vector was computed at. Pinned so a future change to
## `TURN_METER_FULL` reds with "recompute the vector" instead of "the PCG is wrong".
const GOLDEN_FULL := 3600

func _arm_3_carry_not_reset() -> bool:
	var failed := false

	# (a) CARRY IS EXACT, over every speed — divisors of FULL and coprimes alike.
	for speed in EXACTNESS_SPEEDS:
		for start in STARTS:
			var ticks: int = _ticks_for_turns(speed, EXACTNESS_TURNS)
			var want: int = int(floor(float(start + ticks * speed) / float(FULL)))
			var carried: int = _turns_over(speed, start, true, ticks)
			# The last tick's gain may or may not have been consumed depending on
			# where the boundary falls; one turn of slack, no more.
			if absi(carried - want) > 1:
				print("[FAIL] carry drift: speed %d start %d over %d ticks took %d turns, Speed ratio says %d" % [
					speed, start, ticks, carried, want])
				failed = true

	# (b) THE MECHANISM, asserted rather than worked around. A speed that DIVIDES
	# FULL lands on the boundary with zero overshoot, so there is nothing for reset
	# to throw away and the two policies are identical — at every horizon. This is
	# why (c) cannot use such a speed, so it is proved here rather than assumed.
	for speed in DIVISOR_SPEEDS:
		if FULL % speed != 0:
			print("[FAIL] %d was listed as a divisor of FULL=%d and is not — the arm below picks its control speed on this basis" % [speed, FULL])
			failed = true
			continue
		var ticks: int = _ticks_for_turns(speed, EXACTNESS_TURNS)
		for start in STARTS:
			var carried: int = _turns_over(speed, start, true, ticks)
			var reset: int = _turns_over(speed, start, false, ticks)
			if carried != reset:
				print("[FAIL] speed %d divides FULL=%d so carry and reset must agree exactly; got %d vs %d" % [
					speed, FULL, carried, reset])
				failed = true

	# (c) THE CONTROL — the rejected alternative is measurably worse. Without this the
	# arm asserts arithmetic back at itself.
	var reset_ever_drifted := false
	var control_ticks: int = _ticks_for_turns(CONTROL_SPEED, CONTROL_TURNS)
	for start in STARTS:
		var want: int = int(floor(float(start + control_ticks * CONTROL_SPEED) / float(FULL)))
		var reset: int = _turns_over(CONTROL_SPEED, start, false, control_ticks)
		if absi(reset - want) > 1:
			reset_ever_drifted = true
	if not reset_ever_drifted:
		print(("[FAIL] reset-to-zero never drifted off the Speed ratio over %d turns at speed %d"
			+ " — this arm proves nothing. Reset loses the overshoot `meter - FULL`, which is in"
			+ " [0, speed), so it costs ~speed/2 per turn against FULL=%d and needs ~2*FULL/speed"
			+ " turns to lose a whole one. Raise CONTROL_TURNS, or pick a CONTROL_SPEED coprime"
			+ " to FULL — not one that divides it, which can never drift at all.") % [
			CONTROL_TURNS, CONTROL_SPEED, FULL])
		failed = true
	return failed


## Ticks needed for `speed` to take about `turns` turns at the CURRENT FULL. Everything
## in arm 3 is expressed in TURNS rather than ticks for one reason: a flat tick horizon
## is a horizon whose meaning changes whenever FULL does, which is exactly how the
## control above went vacuous when FULL moved 100 -> 3600.
func _ticks_for_turns(speed: int, turns: int) -> int:
	return int(ceil(float(turns * FULL) / float(TurnQueue.gain_per_tick(speed))))


func _turns_over(speed: int, start: int, carry: bool, ticks: int) -> int:
	var meter: int = start
	var turns: int = 0
	for _t in range(ticks):
		if meter < FULL:
			meter += TurnQueue.gain_per_tick(speed)
		if meter >= FULL:
			# The turn is taken the moment it is available.
			meter = (meter - FULL) if carry else 0
			turns += 1
	return turns


## --- 4. Order --------------------------------------------------------------
func _arm_4_order() -> bool:
	var failed := false
	# Same meter, same speed: team then index.
	var tied := [
		_row(3, 1, 8, FULL), _row(1, 0, 8, FULL), _row(2, 1, 8, FULL), _row(0, 0, 8, FULL),
	]
	var order: Array = []
	for r in TurnQueue.ready_now(tied):
		order.append(int(r["index"]))
	if order != [0, 1, 2, 3]:
		print("[FAIL] tie-break order %s, expected [0, 1, 2, 3] (team then index)" % str(order))
		failed = true

	# Overshoot wins over team/index: unit 3 on team 1 crossed the line earliest.
	var overshot := [_row(0, 0, 8, FULL), _row(3, 1, 8, FULL + 9)]
	var first: int = int(TurnQueue.ready_now(overshot)[0]["index"])
	if first != 3:
		print("[FAIL] ready_now put unit %d first; the unit with the larger overshoot (3) waited longer" % first)
		failed = true

	# Dead units are not in the queue at any depth.
	var with_dead := [_row(0, 0, 8, FULL), _row(1, 1, 90, FULL + 5, false)]
	if TurnQueue.ready_now(with_dead).size() != 1:
		print("[FAIL] ready_now included a dead unit")
		failed = true
	for e in TurnQueue.forecast(with_dead):
		if int(e["index"]) == 1:
			print("[FAIL] forecast included dead unit 1")
			failed = true
			break

	# No living units at all: an empty queue, not a crash or a spin.
	if not TurnQueue.forecast([_row(0, 0, 8, 0, false)]).is_empty():
		print("[FAIL] forecast over an all-dead battle is not empty")
		failed = true
	return failed


## --- 5. Forecast vs brute force -------------------------------------------
func _arm_5_forecast_vs_brute_force() -> bool:
	var failed := false
	var cases := [
		[_row(0, 0, 8, 0), _row(1, 0, 8, 0), _row(2, 1, 8, 0), _row(3, 1, 8, 0)],
		[_row(0, 0, 5, 12), _row(1, 0, 13, 3), _row(2, 1, 7, 88), _row(3, 1, 9, 41)],
		[_row(0, 0, 1, 0), _row(1, 1, 47, 0)],
		[_row(0, 0, 8, FULL + 3), _row(1, 1, 8, FULL + 3)],
		[_row(0, 0, 0, 0), _row(1, 1, 3, 50)],
	]
	for ci in range(cases.size()):
		var rows: Array = cases[ci]
		var got: Array = TurnQueue.forecast(rows)
		var want: Array = _brute_force(rows, got.size())
		if got.size() != want.size():
			print("[FAIL] case %d: forecast %d entries, brute force %d" % [ci, got.size(), want.size()])
			failed = true
			continue
		for i in range(got.size()):
			if int(got[i]["index"]) != int(want[i]["index"]) \
					or int(got[i]["ticks_from_now"]) != int(want[i]["ticks_from_now"]) \
					or int(got[i]["turn_meter"]) != int(want[i]["turn_meter"]):
				print("[FAIL] case %d entry %d: closed form %s, brute force %s" % [ci, i, str(got[i]), str(want[i])])
				failed = true
				break
	return failed


## The same rule, simulated one tick at a time. Deliberately dumb: it is the
## oracle for the closed-form jump, so it must not share its arithmetic.
func _brute_force(rows: Array, want_entries: int) -> Array:
	var work: Array = []
	for r in rows:
		if bool(r["alive"]):
			work.append({"index": int(r["index"]), "team": int(r["team"]),
				"speed": int(r["speed"]), "turn_meter": int(r["turn_meter"]), "alive": true})
	var out: Array = []
	var elapsed: int = 0
	while out.size() < want_entries and elapsed <= 100000:
		var ready: Array = TurnQueue.ready_now(work)
		if ready.is_empty():
			for row in work:
				if int(row["turn_meter"]) < FULL:
					row["turn_meter"] = int(row["turn_meter"]) + TurnQueue.gain_per_tick(int(row["speed"]))
			elapsed += 1
			continue
		var taker: Dictionary = ready[0]
		out.append({"index": int(taker["index"]), "team": int(taker["team"]),
			"ticks_from_now": elapsed, "turn_meter": int(taker["turn_meter"])})
		taker["turn_meter"] = int(taker["turn_meter"]) - FULL
	return out


## --- 6. Round-robin depth --------------------------------------------------
func _arm_6_round_robin_depth() -> bool:
	var failed := false
	var lopsided := [
		_row(0, 0, 40, 0), _row(1, 0, 38, 0), _row(2, 0, 35, 0), _row(3, 0, 30, 0),
		_row(4, 1, 4, 0), _row(5, 1, 5, 0), _row(6, 1, 6, 0), _row(7, 1, 3, 0),
	]
	var fc: Array = TurnQueue.forecast(lopsided)
	var seen := {}
	var last_ticks: int = -1
	for e in fc:
		seen[int(e["index"])] = true
		if int(e["ticks_from_now"]) < last_ticks:
			print("[FAIL] forecast is not monotone in ticks_from_now: %d after %d" % [
				int(e["ticks_from_now"]), last_ticks])
			failed = true
		last_ticks = int(e["ticks_from_now"])
	if seen.size() != 8:
		print("[FAIL] round-robin depth: %d of 8 living units appear in %d entries" % [seen.size(), fc.size()])
		failed = true
	# The slowest unit is last, and the queue is deep enough to show the wait.
	if not fc.is_empty() and int(fc[fc.size() - 1]["index"]) != 7:
		print("[FAIL] the slowest unit (7) is not the entry that closes the round robin")
		failed = true
	return failed


func _row(index: int, team: int, speed: int, meter: int, alive: bool = true) -> Dictionary:
	return {"index": index, "team": team, "speed": speed, "turn_meter": meter, "alive": alive}
