extends "res://tests/GPUSeedReproTest.gd"

## GPU Turn Meter Test — the kernel half of the turn clock (ADR-0236).
##
## `TurnQueueTest` is the pure arm: it proves the CPU arithmetic exhaustively
## over cases a battle never reaches. This one proves the two halves are the
## SAME arithmetic, running against the real compute kernel, because the forecast
## the player reads and the rollouts the enemy AI scores are both projections of
## a rule that lives in GLSL.
##
## The roster is deliberately NOT the base 4v4: Speeds are 3..13 (FFT Speed, what
## `atb_speed` actually carries) so a turn takes tens of ticks and the per-tick
## gain is measurable, and it is a 3v3 so slots 6 and 7 are boot-dead spares —
## the only cheap way to watch a DEAD unit's meter, since a unit that dies in
## combat has long since pinned at FULL and "did not move" would be vacuous.
##
##   A. Tick-by-tick parity — every living unit gains exactly `max(1, speed)`
##      per tick while below FULL, stops dead ON FULL rather than wrapping, and
##      becomes ready on exactly the tick `TurnQueue.ticks_until_ready` named.
##      Boot-dead spares never move off zero.
##   B. `consume_turn` — carries the overshoot, refuses a unit that is not ready,
##      and the kernel resumes advancing the unit on the next tick.
##   D. The TURN BRAKE — in the one battle `config.turn_brake_battle` names, a unit at
##      FULL finishes its step and starts no other, while a `restore_battle` FORK of that
##      same pinned-at-FULL image keeps walking. The fork half is why the brake is a config
##      uniform: a unit field would ride the snapshot into every rollout candidate.
##   C. Mid-cast still gets its turn (design S3) — driven by a turn-consuming
##      loop so meters keep cycling below FULL. Asserts a CHARGING unit and a
##      cinematic-PAUSED unit were both actually observed advancing; without that
##      the arm passes by never meeting one.

const TURN_TEST_SEED = 4242
const ABILITY_FIRE = 16
const PARITY_TICKS = 60      # > 100/3, so the slowest unit reaches FULL inside it
const CAST_SEARCH_TICKS = 600

const FULL := GPUCombatPacker.TURN_METER_FULL

## Battle slots. Two, so arm D can fork battle 0 into slot 1 the way `RolloutHarness`
## forks a candidate and prove the brake does NOT ride the fork.
const BATTLES := 2
## Ticks arm D lets the world run after arming the brake. Comfortably longer than one
## movement step (tens of ticks), so a unit that was mid-step when the brake came on has
## finished it and had every chance to start another.
const BRAKE_TICKS := 180
## Ticks arm D spends getting somebody walking in the first place.
const WALK_SEARCH_TICKS := 400

var _tm_failed: bool = false
var _spare_slots: Array = []


func get_test_name() -> String:
	return "GPU Turn Meter Test"


func get_team0_unit_configs() -> Array:
	return [
		{"name": "P1", "pos_x": 3, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 12, "ma": 8, "wp": 6, "brave": 60, "faith": 50,
		 "mp": 200, "max_mp": 200, "speed": 3, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 15, "s_ev": 20, "w_ev": 10, "body_sprite_id": 0x02},
		{"name": "P2", "pos_x": 4, "pos_z": 6, "hp": 180, "max_hp": 180,
		 "pa": 10, "ma": 10, "wp": 7, "brave": 55, "faith": 60,
		 "mp": 200, "max_mp": 200, "speed": 7, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 10, "s_ev": 15, "w_ev": 5, "body_sprite_id": 0x02},
		{"name": "P3", "pos_x": 3, "pos_z": 7, "hp": 220, "max_hp": 220,
		 "pa": 14, "ma": 6, "wp": 5, "brave": 70, "faith": 40,
		 "mp": 200, "max_mp": 200, "speed": 11, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 20, "s_ev": 10, "w_ev": 15, "body_sprite_id": 0x02},
	]


func get_team1_unit_configs() -> Array:
	return [
		{"name": "E1", "pos_x": 8, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 11, "ma": 9, "wp": 7, "brave": 65, "faith": 55,
		 "mp": 200, "max_mp": 200, "speed": 5, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 12, "s_ev": 18, "w_ev": 8, "body_sprite_id": 0x05},
		{"name": "E2", "pos_x": 7, "pos_z": 6, "hp": 190, "max_hp": 190,
		 "pa": 13, "ma": 7, "wp": 6, "brave": 50, "faith": 45,
		 "mp": 200, "max_mp": 200, "speed": 8, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 18, "s_ev": 12, "w_ev": 12, "body_sprite_id": 0x05},
		{"name": "E3", "pos_x": 8, "pos_z": 7, "hp": 210, "max_hp": 210,
		 "pa": 9, "ma": 11, "wp": 5, "brave": 55, "faith": 65,
		 "mp": 200, "max_mp": 200, "speed": 13, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 8, "s_ev": 22, "w_ev": 6, "body_sprite_id": 0x05},
	]


# Cast, don't just swing: a charging unit is what arm C needs, and a cinematic
# spell is also what raises U_PAUSED on everyone else.
func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_spell_gambit(ABILITY_FIRE), make_attack_gambit()]


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_tm_fail("Map has no lattice")
		_tm_finish()
		return

	_setup_distance_field()
	# TWO battles, for arm D's fork. Arms A-C only ever touch battle 0; the second slot
	# costs a work group of boot-dead units until arm D overwrites it with a real fork.
	_ensure_loop()
	combat_loop.rollout_fleet_size = BATTLES
	_setup_gpu_simulator()
	await _create_units()

	if not gpu_simulator:
		_tm_fail("GPU simulator not available")
		_tm_finish()
		return

	_configure_turn_battle()

	_arm_a_tick_parity()
	if not _tm_failed:
		_arm_b_consume_turn()
	if not _tm_failed:
		_arm_c_mid_cast()
	if not _tm_failed:
		_arm_d_the_turn_brake()
	_tm_finish()


func _process(_delta):
	pass


## --- D. The turn brake ------------------------------------------------------
##
## THE KERNEL HALF OF THE TURN BRAKE, and the arm that says it cannot ride a fork.
##
## Logical position is the DESTINATION for the whole duration of a movement step, so a
## host that freezes the world the instant a meter crosses stops it with the taker's
## sprite short of the cell everything else places the unit on. `config.turn_brake_battle`
## names the one battle that stops for turns; in it, a unit at `TURN_METER_FULL` finishes
## the step it is on and starts no other, which is what lets `TurnDirector`'s gate wait for
## a SETTLED taker instead of hanging on a walker that is never aligned.
##
## 🔴 THE FORK IS THE POINT OF THE SECOND BATTLE. `RolloutHarness` forks candidates with
## `restore_battle(k, snapshot_battle(0))`, which copies the header and every unit block
## verbatim. Nothing consumes turns in a candidate, so every unit in one pins at FULL
## forever — a brake carried in a unit field or a header bit would stop the whole rollout
## fleet from walking and quietly poison the value function that scores the enemy's move.
## This arm does that exact fork, with every unit pinned at FULL on both sides, and
## requires slot 1 to KEEP WALKING. It is also the arm's positive control: "battle 0 stopped
## stepping" is what a battle where nobody was walking reports too.
##
## Driven through the BATCHED `step_tick(K)` path on purpose — a live config field that only
## reaches `_config_buffer` is invisible to every batched tick, which is most ticks
## (`GPUBatchSimulator._refresh_live_config_in_pair`).
##
## # seeded-break: make `_refresh_live_config_in_pair` compare only `pair_data[9..10]` again
## # (its pre-#turn-brake form) — battle 0 keeps walking and the brake assertions red.
func _arm_d_the_turn_brake() -> void:
	# Arms A-C left battle 0 mid-fight with casualties. Re-seed, so "who is walking" is a
	# property of the roster and not of how the last arm happened to end.
	_configure_turn_battle()
	if _tm_failed:
		return

	var ticks := 0
	while ticks < WALK_SEARCH_TICKS and _movers_in(0).size() < 2:
		gpu_simulator.step_tick(1)
		ticks += 1
	if _movers_in(0).size() < 2:
		_tm_fail("arm D: only %d unit(s) were walking after %d ticks — the brake has nothing to stop"
			% [_movers_in(0).size(), ticks])
		return

	# Every living unit is READY. Set BEFORE the fork, so the candidate inherits the same
	# pinned meters a real rollout candidate has.
	var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
	for u in range(flags.size()):
		if (flags[u] & GPUConstants.FLAG_DEAD_BIT) == 0:
			gpu_simulator._set_unit_field(0, u, GPUCombatPacker.UnitField.TURN_METER, FULL)

	if not gpu_simulator.restore_battle(1, gpu_simulator.snapshot_battle(0)):
		_tm_fail("arm D: the fork into slot 1 failed")
		return

	gpu_simulator.turn_brake_battle = 0

	var step_before_0: PackedInt32Array = gpu_simulator.read_unit_column(
		0, GPUCombatPacker.UnitField.MOVE_STEP_ID)
	var step_before_1: PackedInt32Array = gpu_simulator.read_unit_column(
		1, GPUCombatPacker.UnitField.MOVE_STEP_ID)
	gpu_simulator.step_tick(BRAKE_TICKS)
	var step_after_0: PackedInt32Array = gpu_simulator.read_unit_column(
		0, GPUCombatPacker.UnitField.MOVE_STEP_ID)
	var step_after_1: PackedInt32Array = gpu_simulator.read_unit_column(
		1, GPUCombatPacker.UnitField.MOVE_STEP_ID)

	# The braked battle: nobody started another step, and nobody is between tiles.
	var restarted: Array = []
	for u in range(step_after_0.size()):
		if step_after_0[u] != step_before_0[u]:
			restarted.append(u)
	if not restarted.is_empty():
		_tm_fail("arm D: braked battle 0 — units %s started another movement step (move_step_id moved) in %d ticks"
			% [restarted, BRAKE_TICKS])
	var still_moving: Array = _movers_in(0)
	if not still_moving.is_empty():
		_tm_fail("arm D: braked battle 0 — units %s are still in a movement state after %d ticks; the brake never settled them"
			% [still_moving, BRAKE_TICKS])

	# The fork: NOT braked, and the control that says the assertions above measured
	# something. Same pinned meters, same starting image, one battle id apart.
	var fork_walked: Array = []
	for u in range(step_after_1.size()):
		if step_after_1[u] != step_before_1[u]:
			fork_walked.append(u)
	if fork_walked.is_empty():
		_tm_fail("arm D: the forked battle 1 took no movement step either — the brake rode the fork, or nobody was walking and battle 0's silence means nothing")

	if not _tm_failed:
		print("[GPUTurnMeterTest] arm D: brake armed on battle 0 — it took 0 further steps and settled every mover; the fork in slot 1 took steps for units %s."
			% [fork_walked])


## Which units in `battle_id` are between tiles right now.
func _movers_in(battle_id: int) -> Array:
	var states: PackedInt32Array = gpu_simulator.read_unit_column(
		battle_id, GPUCombatPacker.UnitField.STATE)
	var flags: PackedInt32Array = gpu_simulator.read_unit_column(
		battle_id, GPUCombatPacker.UnitField.FLAGS)
	var out: Array = []
	for u in range(mini(states.size(), flags.size())):
		if (flags[u] & GPUConstants.FLAG_DEAD_BIT) != 0:
			continue
		if GPUConstants.is_movement_state(states[u]):
			out.append(u)
	return out


func _configure_turn_battle() -> void:
	var gpu_team0: Array = []
	var gpu_team1: Array = []
	var team0_configs = get_team0_unit_configs()
	var team1_configs = get_team1_unit_configs()
	for i in range(team0_units.size()):
		gpu_team0.append(_build_gpu_config(
			team0_units[i].movement_component.current_cell, team0_configs[i]))
	for i in range(team1_units.size()):
		gpu_team1.append(_build_gpu_config(
			team1_units[i].movement_component.current_cell, team1_configs[i]))
	gpu_simulator.set_battle_units(0, gpu_team0, gpu_team1, TURN_TEST_SEED)
	var live: int = gpu_team0.size() + gpu_team1.size()
	for i in range(live):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0 if i < gpu_team0.size() else 1))
	gpu_state_reader.initialize(gpu_simulator, 0)

	var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
	for i in range(flags.size()):
		if (flags[i] & GPUConstants.FLAG_DEAD_BIT) != 0:
			_spare_slots.append(i)
	if _spare_slots.is_empty():
		_tm_fail("no boot-dead spare slot — arm A's dead-unit half would be vacuous")


## --- A. Tick-by-tick parity ------------------------------------------------
func _arm_a_tick_parity() -> void:
	var rows: Array = TurnQueue.from_unit_states(gpu_simulator.get_battle_unit_states(0))

	# The seeded start is what the CPU thinks it is, before a single tick runs.
	for row in rows:
		if not bool(row["alive"]):
			continue
		var want: int = GPUCombatPacker.initial_turn_meter(TURN_TEST_SEED, int(row["index"]))
		if int(row["turn_meter"]) != want:
			_tm_fail("A: unit %d booted with turn_meter %d, initial_turn_meter says %d" % [
				int(row["index"]), int(row["turn_meter"]), want])
			return
	var starts: Array = []
	for row in rows:
		starts.append(int(row["turn_meter"]))
	if starts.slice(0, 6).min() == starts.slice(0, 6).max():
		_tm_fail("A: every unit booted on the same meter (%d) — the seeded start is inert" % starts[0])
		return

	# The prediction, taken ONCE up front: after k ticks, unit u is ready iff
	# k >= ticks_until_ready(u). Nothing consumes a turn here, so the kernel's
	# clamp is what has to hold it there.
	var predicted := {}
	for row in rows:
		if bool(row["alive"]):
			predicted[int(row["index"])] = TurnQueue.ticks_until_ready(row)

	var clamped_seen: int = 0
	var prev: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
	var speeds: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.SPEED)
	for k in range(1, PARITY_TICKS + 1):
		gpu_simulator.step_tick(1)
		var now: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
		var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
		for u in range(now.size()):
			var dead: bool = (flags[u] & GPUConstants.FLAG_DEAD_BIT) != 0
			var want: int = prev[u]
			if dead:
				pass  # a dead unit's clock has stopped
			elif prev[u] >= FULL:
				clamped_seen += 1
			else:
				want = prev[u] + TurnQueue.gain_per_tick(speeds[u])
			if now[u] != want:
				_tm_fail("A: tick %d unit %d (speed %d, dead=%s): meter %d -> %d, expected %d" % [
					k, u, speeds[u], str(dead), prev[u], now[u], want])
				return
			if not dead:
				var ready_now: bool = now[u] >= FULL
				var ready_want: bool = k >= int(predicted[u])
				if ready_now != ready_want:
					_tm_fail("A: tick %d unit %d readiness %s, TurnQueue.ticks_until_ready said %d" % [
						k, u, str(ready_now), int(predicted[u])])
					return
		prev = now
	for s in _spare_slots:
		if prev[s] != 0:
			_tm_fail("A: boot-dead spare slot %d advanced to %d — the clock ignored FLAG_DEAD" % [s, prev[s]])
			return
	if clamped_seen == 0:
		_tm_fail("A: no unit ever sat at FULL in %d ticks — the clamp branch is untested" % PARITY_TICKS)
		return
	print("[arm A] %d ticks: exact gain, %d clamped-at-FULL observations, %d dead spares frozen, readiness matched the CPU prediction for all %d living units" % [
		PARITY_TICKS, clamped_seen, _spare_slots.size(), predicted.size()])


## --- B. consume_turn -------------------------------------------------------
func _arm_b_consume_turn() -> void:
	var before: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
	var speeds: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.SPEED)
	var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
	var ready: Array = []
	var max_overshoot: int = 0
	for u in range(before.size()):
		if (flags[u] & GPUConstants.FLAG_DEAD_BIT) == 0 and before[u] >= FULL:
			ready.append(u)
			max_overshoot = maxi(max_overshoot, before[u] - FULL)
	if ready.is_empty():
		_tm_fail("B: nobody is ready after arm A — nothing to consume")
		return
	# A unit whose Speed happens to land it exactly ON 100 carries nothing, and a
	# reset-to-zero implementation would pass on that unit alone. At least one of
	# the ready set has to have overshot, or the arm cannot tell carry from reset.
	if max_overshoot == 0:
		_tm_fail("B: every ready unit sits exactly on FULL — carry and reset are indistinguishable here")
		return

	for u in ready:
		var overshoot: int = before[u] - FULL
		var got: int = gpu_simulator.consume_turn(0, u)
		if got != overshoot:
			_tm_fail("B: consume_turn(0, %d) returned %d, expected the carried overshoot %d" % [u, got, overshoot])
			return
		var after: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
		if after[u] != overshoot:
			_tm_fail("B: unit %d meter is %d after consume_turn, expected %d" % [u, after[u], overshoot])
			return
		# Refuses a unit that is not ready — otherwise the meter goes negative and
		# the unit waits longer than its Speed earns.
		if gpu_simulator.consume_turn(0, u) != -1:
			_tm_fail("B: consume_turn accepted unit %d at %d, below FULL" % [u, after[u]])
			return
		if gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)[u] != overshoot:
			_tm_fail("B: the refused consume_turn still moved unit %d" % u)
			return

	# And the kernel picks every one of them back up on the very next tick.
	var mid: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
	gpu_simulator.step_tick(1)
	var resumed: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
	for u in ready:
		var want: int = mid[u] + TurnQueue.gain_per_tick(speeds[u])
		if resumed[u] != want:
			_tm_fail("B: after consume_turn the kernel advanced unit %d to %d, expected %d" % [
				u, resumed[u], want])
			return
	print("[arm B] consume_turn over %d ready units: carry exact (max overshoot %d), non-ready refused, kernel resumed all" % [
		ready.size(), max_overshoot])


## --- C. Mid-cast still gets its turn ---------------------------------------
func _arm_c_mid_cast() -> void:
	var charging_advances: int = 0
	var paused_advances: int = 0
	var ticks: int = 0
	# Column reads, not get_battle_unit_states: all five share ONE cached region
	# read per tick, where the dict path rebuilds 8 x UNIT_SIZE string keys twice.
	# At several hundred ticks that difference is the whole runtime of this arm.
	var meters: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
	while ticks < CAST_SEARCH_TICKS and (charging_advances == 0 or paused_advances == 0):
		if gpu_simulator.is_battle_finished(0):
			break
		# Drain the queue the way the director will, so meters keep cycling below
		# FULL instead of pinning -- a pinned meter cannot show an advance.
		var flags_pre: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
		for u in range(meters.size()):
			if (flags_pre[u] & GPUConstants.FLAG_DEAD_BIT) == 0 and meters[u] >= FULL:
				gpu_simulator.consume_turn(0, u)

		var before: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
		var speeds: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.SPEED)
		var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
		var casting: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.CAST_TIMER)
		var paused: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.PAUSED)
		gpu_simulator.step_tick(1)
		ticks += 1
		meters = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TURN_METER)
		for u in range(before.size()):
			if (flags[u] & GPUConstants.FLAG_DEAD_BIT) != 0 or before[u] >= FULL:
				continue
			var want: int = before[u] + TurnQueue.gain_per_tick(speeds[u])
			if meters[u] != want:
				_tm_fail("C: tick %d unit %d (cast_timer=%d paused=%d) meter %d -> %d, expected %d" % [
					ticks, u, casting[u], paused[u], before[u], meters[u], want])
				return
			if casting[u] > 0:
				charging_advances += 1
			if paused[u] != 0:
				paused_advances += 1

	if charging_advances == 0:
		_tm_fail("C: no unit was ever mid-cast in %d ticks -- the design's 'mid-cast still gets its turn' is untested here" % ticks)
		return
	if paused_advances == 0:
		_tm_fail("C: no unit was ever cinematic-PAUSED in %d ticks -- the pause-gate half is untested here" % ticks)
		return
	print("[arm C] %d ticks: %d charging-unit advances and %d paused-unit advances, all exact" % [
		ticks, charging_advances, paused_advances])


func _tm_fail(reason: String) -> void:
	_tm_failed = true
	print("[FAIL] %s" % reason)


func _tm_finish() -> void:
	if _tm_failed:
		print("[FAIL] %s" % get_test_name())
	else:
		print("[PASS] Turn meter: kernel advance, clamp, consume_turn carry and mid-cast all match TurnQueue (FULL=%d)" % FULL)
	get_tree().quit()
