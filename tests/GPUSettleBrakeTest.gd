extends "res://tests/GPUSeedReproTest.gd"

# test-kind: gpu

## GPU Settle Brake Test — the battle does not end on top of a unit mid-step.
##
## `stage_victory` reports a win only when every survivor is CELEBRATING, so it was
## ALREADY an all-survivors-settled handshake. What made that a lie is the by-fiat
## flip in `stage_compute` ("THE FIGHT IS OVER, SO NOTHING A UNIT WAS MID-WAY
## THROUGH MATTERS", #897): it writes CELEBRATING over a unit that is still between
## tiles, and a state leaving the movement set is [GPUVisualBridge]'s cue to drop the
## visualizer and snap the sprite to the GPU tile — which is the DESTINATION of the
## step it just abandoned. MEASURED at Gariland: two survivors teleported 0.967 and
## 1.300 world units, and the whole thing happened one tick BEFORE `CombatLoop.victory`
## was emitted, which is why no host-side gate on that signal could ever have stopped
## it.
##
## `config.settle_brake_battle` buys the flip back for the states a unit is still
## visibly finishing, and brakes it at dispatch so it starts nothing new. Two arms,
## one process, ONE fork apart:
##
##   A. THE BRAKED BATTLE (slot 0) — with the enemy team wiped and a unit mid-step,
##      no unit goes from a settle-awaited state straight to CELEBRATING, nobody
##      starts another movement step (`move_step_id` frozen), the win is WITHHELD,
##      and when it finally lands every survivor is CELEBRATING with a drained timer.
##   B. THE FORK (slot 1) — the same image, one battle id apart, NOT named by the
##      brake. It must do the old thing: flip a mid-step walker to CELEBRATING on the
##      very next tick and report the win immediately. That is arm A's positive
##      control (a battle where nobody was walking would pass arm A vacuously), the
##      proof the field is OFF BY DEFAULT, and the proof it cannot ride a
##      `restore_battle` fork into a rollout candidate.
##   C. `CombatLoop.settling_units` names the held-open population, and empties.
##   D. The [member CombatLoop.settle_backstop_seconds] backstop disarms the brake
##      and does not fire while nothing is pending.

# seeded-break: delete the `config.settle_brake_battle == battle_id &&
# settle_awaited_state(state)` clause from the victory flip in stage_compute.glsl —
# arm A goes red with "flipped [[0, 1, 1], [1, 1, 1], [2, 1, 30]] straight to
# CELEBRATING out of a settle-awaited state" (verified, not asserted).

const SETTLE_TEST_SEED = 8181
## Two battles: slot 0 is braked, slot 1 is the unbraked fork of the same image.
const BATTLES := 2
## Ticks spent getting somebody genuinely between tiles before the fight is decided.
const WALK_SEARCH_TICKS := 400
## Ticks the arms let the decided world run. One movement step is tens of ticks, so
## this is several steps' worth — long enough that a brake which failed to terminate
## shows up as a battle that never finishes rather than as a lucky pass.
const SETTLE_TICKS := 400

## The host mirror of the kernel's `settle_awaited_state`: BETWEEN TILES, or
## ACTING. Asked rather than listed — a hand-listed mirror of a predicate drifts
## from it silently, and this one had (it was still the pre-ADR-0301 three when
## the kernel's was four).
static func _is_awaited(state: int) -> bool:
	return GPUConstants.is_movement_state(state) \
		or state == GPUConstants.LOGICAL_ACTIVITY_ACTING

var _sb_failed: bool = false
var _sb_asserts: int = 0


func get_test_name() -> String:
	return "GPU Settle Brake Test"


## The same 3v3 spread `GPUTurnMeterTest` uses -- far enough apart that everyone
## spends the opening walking — the arms
## need a unit genuinely between tiles at the moment the fight is decided, and a
## roster that starts in weapon range never gives them one.
func get_team0_unit_configs() -> Array:
	return [
		{"name": "P1", "pos_x": 3, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 12, "ma": 8, "wp": 6, "brave": 60, "faith": 50,
		 "mp": 200, "max_mp": 200, "speed": 6, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 15, "s_ev": 20, "w_ev": 10, "body_sprite_id": 0x02},
		{"name": "P2", "pos_x": 3, "pos_z": 6, "hp": 180, "max_hp": 180,
		 "pa": 10, "ma": 10, "wp": 7, "brave": 55, "faith": 60,
		 "mp": 200, "max_mp": 200, "speed": 7, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 10, "s_ev": 15, "w_ev": 5, "body_sprite_id": 0x02},
		{"name": "P3", "pos_x": 3, "pos_z": 7, "hp": 220, "max_hp": 220,
		 "pa": 14, "ma": 6, "wp": 5, "brave": 70, "faith": 40,
		 "mp": 200, "max_mp": 200, "speed": 5, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 20, "s_ev": 10, "w_ev": 15, "body_sprite_id": 0x02},
	]


func get_team1_unit_configs() -> Array:
	return [
		{"name": "E1", "pos_x": 8, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 11, "ma": 9, "wp": 7, "brave": 65, "faith": 55,
		 "mp": 200, "max_mp": 200, "speed": 4, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 12, "s_ev": 18, "w_ev": 8, "body_sprite_id": 0x05},
		{"name": "E2", "pos_x": 8, "pos_z": 6, "hp": 190, "max_hp": 190,
		 "pa": 13, "ma": 7, "wp": 6, "brave": 50, "faith": 45,
		 "mp": 200, "max_mp": 200, "speed": 4, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 18, "s_ev": 12, "w_ev": 12, "body_sprite_id": 0x05},
		{"name": "E3", "pos_x": 8, "pos_z": 7, "hp": 210, "max_hp": 210,
		 "pa": 9, "ma": 11, "wp": 5, "brave": 55, "faith": 65,
		 "mp": 200, "max_mp": 200, "speed": 4, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 8, "s_ev": 22, "w_ev": 6, "body_sprite_id": 0x05},
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# TYPED, because the fetch is a lattice PORT (ADR-0164 dec. 4 / ADR-0192 dec. 2):
	# `check_lattice_ports` arm 2 is an enforcing named list, and an untyped
	# `map.lattice` is a duck-typed reach whether it is in a host or in a test.
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_sb_fail("Map has no lattice")
		_sb_finish()
		return

	_setup_distance_field()
	_ensure_loop()
	combat_loop.rollout_fleet_size = BATTLES
	_setup_gpu_simulator()
	await _create_units()

	if not gpu_simulator:
		_sb_fail("GPU simulator not available")
		_sb_finish()
		return

	_configure_settle_battle()
	if not _sb_failed:
		_run_the_arms()
	_sb_finish()


func _process(_delta):
	pass


func _configure_settle_battle() -> void:
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
	gpu_simulator.set_battle_units(0, gpu_team0, gpu_team1, SETTLE_TEST_SEED)
	for i in range(gpu_team0.size() + gpu_team1.size()):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0))
	gpu_state_reader.initialize(gpu_simulator, 0)
	# `settling_units` reads `units` for the NAME half of its report, and this
	# harness drives `set_battle_units` directly rather than through `boot_battle`,
	# which is what normally assigns it. Arm C needs the assignment `boot_battle`
	# would have made.
	combat_loop.units = units


func _run_the_arms() -> void:
	# --- get somebody genuinely between tiles ------------------------------
	var ticks := 0
	var movers: Array = []
	while ticks < WALK_SEARCH_TICKS:
		gpu_simulator.step_tick(1)
		ticks += 1
		movers = _mid_step_units(0)
		if movers.size() >= 2:
			break
	if movers.size() < 2:
		_sb_fail("setup: only %d unit(s) were between tiles after %d ticks — every arm below would be vacuous"
			% [movers.size(), ticks])
		return

	# --- decide the fight by fiat, so the walkers are caught mid-step --------
	# Killing team 1 outright rather than letting the battle resolve is what puts the
	# deciding tick exactly where the arms need it: on a tick a survivor is provably
	# between tiles. `is_enemy_team_dead` reads FLAG_DEAD, so both halves are set.
	var flags: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
	var teams: PackedInt32Array = gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.TEAM)
	for u in range(flags.size()):
		if teams[u] == 1 and (flags[u] & GPUConstants.FLAG_DEAD_BIT) == 0:
			gpu_simulator._set_unit_field(0, u, GPUCombatPacker.UnitField.HP, 0)
			gpu_simulator._set_unit_field(0, u, GPUCombatPacker.UnitField.FLAGS,
				flags[u] | GPUConstants.FLAG_DEAD_BIT)

	# The fork BEFORE the arm, so both battles start from one image and the only
	# difference between them is which battle id the brake names.
	if not gpu_simulator.restore_battle(1, gpu_simulator.snapshot_battle(0)):
		_sb_fail("setup: the fork into slot 1 failed")
		return

	gpu_simulator.settle_brake_battle = 0

	# --- arm C, first half: the population is named while it is held --------
	var pending: Array = combat_loop.settling_units()
	if pending.is_empty():
		_sb_fail("C: settling_units() is empty with the fight decided and %d unit(s) mid-step" % movers.size())
		return
	_sb_asserts += 1
	var pending_names: Array = []
	for row in pending:
		pending_names.append(String(row["name"]))

	# --- arm D: the backstop, on a battle that IS pending -------------------
	# Run before the world is stepped on, because a settled battle would let it pass
	# by having nothing to hold. Restores the arm afterwards.
	combat_loop.settle_before_victory = true
	combat_loop.settle_backstop_seconds = 999.0
	combat_loop._tick_settle_backstop(1.0)
	if gpu_simulator.settle_brake_battle != 0:
		_sb_fail("D: the backstop disarmed the brake after 1.0s of a 999.0s budget")
		return
	_sb_asserts += 1
	combat_loop.settle_backstop_seconds = 0.5
	combat_loop._tick_settle_backstop(1.0)
	if gpu_simulator.settle_brake_battle != -1:
		_sb_fail("D: the backstop expired but left settle_brake_battle at %d"
			% gpu_simulator.settle_brake_battle)
		return
	_sb_asserts += 1
	# Re-arm for arms A/B. The setter clears the expiry, which is the whole reason a
	# host re-arming a fresh battle is not stuck with the last one's give-up.
	combat_loop.settle_before_victory = false
	combat_loop.settle_before_victory = true
	if gpu_simulator.settle_brake_battle != 0:
		_sb_fail("D: re-arming after an expiry left settle_brake_battle at %d"
			% gpu_simulator.settle_brake_battle)
		return
	_sb_asserts += 1

	# --- arms A + B: tick both battles side by side -------------------------
	var step_before := {
		0: gpu_simulator.read_unit_column(0, GPUCombatPacker.UnitField.MOVE_STEP_ID),
		1: gpu_simulator.read_unit_column(1, GPUCombatPacker.UnitField.MOVE_STEP_ID),
	}
	var prev := {0: _snap(0), 1: _snap(1)}
	var fiat_flip := {0: [], 1: []}      # battle -> [unit, state-it-was-in, timer-it-had]
	var finished_at := {0: -1, 1: -1}

	for k in range(1, SETTLE_TICKS + 1):
		gpu_simulator.step_tick(1)
		for b in [0, 1]:
			# STOP SAMPLING A BATTLE AT ITS VERDICT. `stage_compute.main` returns early
			# on `result != RESULT_ONGOING`, so a finished battle's two ping-pong halves
			# stop being copied forward and diverge — reads then ALTERNATE between the
			# last computed image and the one before it, which a transition counter reads
			# as the same flip happening once every two ticks forever. Counting past the
			# verdict inflated arm B's tally 16x on the first run of this test.
			if finished_at[b] >= 0:
				continue
			var now: Dictionary = _snap(b)
			for u in range(now["state"].size()):
				if (now["flags"][u] & GPUConstants.FLAG_DEAD_BIT) != 0:
					continue
				# THE DEFECT, stated as a transition: a unit that was still visibly
				# finishing something is CELEBRATING on the next tick. The flip zeroes
				# U_TIMER on its way past, so the timer has to be read from BEFORE it.
				if now["state"][u] == GPUConstants.LOGICAL_ACTIVITY_CELEBRATING \
						and _is_awaited(prev[b]["state"][u]):
					fiat_flip[b].append([u, int(prev[b]["state"][u]), int(prev[b]["timer"][u])])
			prev[b] = now
			if finished_at[b] < 0 and gpu_simulator.is_battle_finished(b):
				finished_at[b] = k
		if finished_at[0] > 0 and finished_at[1] > 0:
			break

	# --- arm B: the fork did the old thing ----------------------------------
	if fiat_flip[1].is_empty():
		_sb_fail("B: the UNBRAKED fork never flipped a mid-anything unit to CELEBRATING — "
			+ "so arm A's silence measures nothing (nobody was mid-step, or the fork inherited the brake)")
		return
	_sb_asserts += 1
	if finished_at[1] != 1:
		_sb_fail("B: the unbraked fork reported its win on tick %d, expected tick 1 — "
			% finished_at[1] + "the by-fiat flip is what makes the old path report immediately")
		return
	_sb_asserts += 1

	# --- arm A: the braked battle did not ------------------------------------
	if not fiat_flip[0].is_empty():
		_sb_fail("A: braked battle 0 flipped %s straight to CELEBRATING out of a settle-awaited state"
			% [fiat_flip[0]])
		return
	_sb_asserts += 1
	var step_after_0: PackedInt32Array = gpu_simulator.read_unit_column(
		0, GPUCombatPacker.UnitField.MOVE_STEP_ID)
	var restarted: Array = []
	for u in range(step_after_0.size()):
		if step_after_0[u] != step_before[0][u]:
			restarted.append(u)
	if not restarted.is_empty():
		_sb_fail("A: braked battle 0 — units %s started another movement step; the brake "
			% [restarted] + "did not stop them and the wait can never terminate")
		return
	_sb_asserts += 1
	if finished_at[0] < 0:
		_sb_fail("A: braked battle 0 never reported its win in %d ticks — the brake did not terminate"
			% SETTLE_TICKS)
		return
	if finished_at[0] <= finished_at[1]:
		_sb_fail("A: braked battle 0 reported its win on tick %d, the unbraked fork on tick %d — "
			% [finished_at[0], finished_at[1]] + "the brake withheld nothing")
		return
	_sb_asserts += 1

	# And what it settled INTO: everyone standing, drained, on their own tile.
	var final := _snap(0)
	for u in range(final["state"].size()):
		if (final["flags"][u] & GPUConstants.FLAG_DEAD_BIT) != 0:
			continue
		if final["state"][u] != GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
			_sb_fail("A: battle 0 reported a win with living unit %d in state %d, not CELEBRATING"
				% [u, final["state"][u]])
			return
		if final["timer"][u] != 0:
			_sb_fail("A: battle 0 flipped unit %d with timer %d still on the clock — "
				% [u, final["timer"][u]] + "its step had not drained, so its sprite is short of its tile")
			return
	_sb_asserts += 1

	# --- arm C, second half: the report empties ------------------------------
	if not combat_loop.settling_units().is_empty():
		_sb_fail("C: settling_units() is still non-empty after battle 0 reported its win")
		return
	_sb_asserts += 1

	print("[arm B] the unbraked fork flipped %d mid-anything unit(s) to CELEBRATING and won on tick 1 — %s"
		% [fiat_flip[1].size(), str(fiat_flip[1])])
	print("[arm A] the braked battle flipped none, took 0 further steps, and won on tick %d (%d ticks later), everyone drained"
		% [finished_at[0], finished_at[0] - finished_at[1]])
	print("[arm C] settling_units() named %s while held, and emptied" % [pending_names])
	print("[arm D] the backstop held through 1.0s of a 999.0s budget, disarmed at 0.5s, and re-armed clean")


## The per-unit columns the arms compare across a tick, in one cached region read.
func _snap(battle_id: int) -> Dictionary:
	return {
		"state": gpu_simulator.read_unit_column(battle_id, GPUCombatPacker.UnitField.STATE),
		"timer": gpu_simulator.read_unit_column(battle_id, GPUCombatPacker.UnitField.TIMER),
		"flags": gpu_simulator.read_unit_column(battle_id, GPUCombatPacker.UnitField.FLAGS),
	}


## Living units that are BETWEEN TILES right now — in a movement state with a step
## still on the clock. Not `is_movement_state` alone: a walker whose timer has just
## drained is standing on its tile, and flipping THAT one costs nothing.
func _mid_step_units(battle_id: int) -> Array:
	var snap: Dictionary = _snap(battle_id)
	var out: Array = []
	for u in range(snap["state"].size()):
		if (snap["flags"][u] & GPUConstants.FLAG_DEAD_BIT) != 0:
			continue
		if GPUConstants.is_movement_state(snap["state"][u]) and snap["timer"][u] > 0:
			out.append(u)
	return out


func _sb_fail(reason: String) -> void:
	_sb_failed = true
	print("[FAIL] %s" % reason)


func _sb_finish() -> void:
	if _sb_failed:
		print("[FAIL] %s (%d assertion(s) reached)" % [get_test_name(), _sb_asserts])
	elif _sb_asserts == 0:
		print("[FAIL] %s reached ZERO assertions — a green summary is not a run" % get_test_name())
	else:
		print("[PASS] Settle brake: %d assertions — the braked battle withheld its win until "
			% _sb_asserts + "every survivor had drained, the unbraked fork flipped mid-step and won at once")
	get_tree().quit()
