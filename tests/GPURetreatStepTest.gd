extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: in src/gpu/shaders/stage_pathfind.glsl's `execute_retreat_step`, write LOGICAL_ACTIVITY_WALKING instead of LOGICAL_ACTIVITY_RETREATING -- the exact "just reuse the move we already have" shortcut ADR-0301 rejects. Arms 1, 2, 3 and 5 all red; arm 1's line reads "distance FELL while retreating, 1 time(s): tick 93: 4 -> 3", which is `handle_moving_state` walking the fleeing unit back toward what it was fleeing. VERIFIED, both arms: the mirror seed (delete the `flee_from == unit_id` guard at the top of `retreat_step_cell` in stage_compute.glsl) reds arm 4 alone ("Stuck entered RETREATING") and leaves 1, 2, 3 and 5 green.

## GPU RETREAT STEP TEST — one tile away, then a fresh decision (ADR-0301, #1103).
##
## ADR-0062 deleted `RETREAT` as a verb because it named no single behaviour.
## ADR-0301 gives it one, and this is the end-to-end witness that the kernel runs
## THAT one: a real `Gambit` with `ActionKind.RETREAT` goes through
## `GambitEncoder` to `ACTION_RETREAT_STEP` and onto the GPU.
##
## FOUR arms, one battle, two team-0 units sharing the harness (test charter
## clause 13). The two units are each other's control: one has a retreat that can
## always be taken, the other a retreat that can never be.
##
##   1. **A retreat only ever OPENS distance.** Runner's manhattan distance from
##      Chaser is sampled every frame and may never fall. This is the "strictly
##      greater than `here`" rule in `retreat_step_cell`, and a fleeing unit that
##      steps sideways into the same distance -- or backwards -- fails it.
##   2. **It actually moved, and it moved MORE THAN ONCE.** The anti-vacuity arm:
##      a unit that never leaves its tile satisfies arm 1 trivially. More than one
##      tile is what shows the step repeats, which is the whole shape of
##      "one tile, then reevaluate".
##   3. **A retreat NEVER attacks.** Chaser's HP is untouched, and Runner enters
##      neither ACTING nor WALKING. The WALKING half is the sharper of the two:
##      reusing `execute_move_to_gambit` would have put the retreat in
##      LOGICAL_ACTIVITY_WALKING, and `handle_moving_state` OPENS with "is anyone
##      attackable? then stop and swing" -- so a retreat in that state breaks off
##      into an attack on the very unit it is fleeing. That is why retreat has a
##      Logical activity of its own, and the state assertion catches it even on a
##      map where the fleeing unit never happens to come back into reach.
##   4. 🔴 **A RETREAT THAT CANNOT BE TAKEN FALLS THROUGH TO THE NEXT SLOT, AND NO
##      OTHER ARM CAN BE SATISFIED IN ITS PLACE.** Stuck's slot 0 is a retreat
##      aimed at ITSELF, which `retreat_step_cell` refuses outright
##      (VERDICT_NO_RETREAT); its slot 1 is a MOVE toward the enemy. Stuck must be
##      seen APPROACHING and must never be seen RETREATING. If a declined retreat
##      committed the slot the way a movement state does, slot 1 would be
##      unreachable for the whole battle -- which is the failure mode that made
##      the pick a DECIDE-stage pre-validation rather than a pathfind-stage body,
##      and the reason a cornered unit can still reach its `Attack` row.
##
##   5. **The retreat state does not OUTLIVE the step.** Runner's retreat is
##      conditioned on the enemy being within REST_DISTANCE, so it stops firing
##      once the ground is opened; from that moment the unit must be sitting in
##      LOGICAL_ACTIVITY_IDLE, not still wearing RETREATING. This is the arm that
##      holds `stage_compute`'s RETREATING dispatch honest -- delete that block
##      and the unit still re-decides correctly (the walk falls through to the
##      gambit evaluation at the bottom of `compute_unit_state` either way), but
##      U_STATE is never written back, so the sprite walks in place forever and
##      the settle brake keeps waiting on a unit that has stopped. 🔴 ARMS 1-4 ALL
##      STAY GREEN UNDER THAT BREAK -- MEASURED, which is why this arm exists.
##
## WHY A SELF-AIMED RETREAT AND NOT A UNIT IN A CORNER. A corner is geometry, and
## the geometry here is not pinned: `MapComposer` builds the lattice per run and
## units settle onto valid cells. Aiming the retreat at the actor is the one
## "there is no cell" case that is true on every map, so arm 4 measures the
## fall-through rather than measuring the map. Every unit's cell is printed in the
## results block so a future placement change is visible rather than silent.
##
## 🔴 NOBODY STANDS ON (0, 0), AND THAT IS DELIBERATE. A unit spawned there loses
## exactly 5 HP on tick 3 -- MEASURED on this tree with all three units holding
## `Wait` gambits, so it is not this feature and not any gambit: the drop is a
## flat 5 whatever the unit's PA / WP / max HP, it lands with no ACTING state and
## no `damage_target` carrier anywhere in the battle, and it vanishes the moment
## the unit is moved to any other cell. `GPUMoveToUnitTest` has carried it since
## ADR-0062 without noticing, because the unit it puts on (0, 0) is the one whose
## HP it never asserts. Arm 3 reads HP, so this fixture keeps that cell empty
## rather than baselining around the artifact and hiding it.
##
## ⚠️ WHAT THIS FIXTURE DOES **NOT** REACH: `retreat_step_cell`'s FALLBACK branch.
## On an open procedural map the preferred cell -- one step along the dominant
## component of (me - them) -- is always steppable and always opens distance, so
## the preferred pass returns every time and the four-neighbour maximise-distance
## scan never runs. MEASURED: dropping the `d > here` / `cand > best_dist`
## strictness leaves all five arms green. Reaching it needs authored terrain that
## blocks the away-direction, which is #795's target-cursor fixture work; until
## then the fallback is covered by reading rather than by running, and this
## paragraph is the record of that rather than a silence.
##
## NEITHER TEAM CAN WIN. Chaser only WAITs and neither team-0 unit ever attacks,
## so the battle never resolves; the run quits as soon as all four arms are
## decided, and `_on_loop_timed_out` scores whatever was seen if they are not.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.

const CHASER_START_HP := 400

## Arm 2's floor. Two tiles is the smallest number that can only come from a
## REPEATED step; one is satisfied by a single committed move.
const MIN_TILES_OPENED := 2

## The manhattan distance at which Runner's retreat condition goes false, so the
## board has to give it that much room from Chaser's cell. Starting distance is 2.
const REST_DISTANCE := 4

## TICKS to wait after the retreat condition goes false before reading the
## Logical activity for arm 5. Ticks and not frames or samples, per test charter
## clause 6 -- the frame rate under an N=8 parallel run is not this test's to
## assume, and the thing being waited on is measured in ticks.
##
## 🔴 IT CANNOT BE "THE CELL STOPPED CHANGING", and the first cut of this arm was
## exactly that and was WRONG. Logical position is the DESTINATION for the whole
## of a step (`write_movement_step` sets U_TIMER and `stage_resolve` commits the
## position on the tick the step is CHOSEN), so a unit mid-stride sits on an
## unchanging cell for the whole step and reads "at rest" while it is still
## fleeing. MEASURED on this fixture: one step is ~50 ticks, and the condition
## flips as early as tick 1 of it. 120 is a little over two whole steps.
const SETTLE_TICKS := 120

var _runner_saw_retreating: bool = false
var _runner_saw_acting: bool = false
var _runner_saw_walking: bool = false
var _stuck_saw_approaching: bool = false
var _stuck_saw_retreating: bool = false
var _stuck_saw_acting: bool = false

var _start_dist: int = -1
var _last_dist: int = -1
var _max_dist: int = -1
var _regressions: Array[String] = []
var _samples: int = 0
var _settle_tick: int = -1
var _settle_cell := Vector2i(-1, -1)
var _settle_moved: bool = false
var _runner_rest_state: int = -1
var _done: bool = false


func get_test_name() -> String:
	return "GPU Retreat Step Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Runner",
		"pos_x": 3, "pos_z": 0,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 5, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02
	}, {
		"name": "Stuck",
		"pos_x": 1, "pos_z": 3,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 5, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Chaser",
		"pos_x": 1, "pos_z": 0,
		"hp": CHASER_START_HP, "max_hp": CHASER_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team != 0:
		# The enemy holds position, so the battle never resolves into combat and
		# the thing Runner is fleeing stays where the arms expect it.
		return [make_wait_gambit()]

	if unit_idx == 0:
		# RETREAT from the nearest enemy WHILE IT IS CLOSE. Encoded through the real
		# `GambitEncoder`, so this exercises the Gambit -> ACTION_RETREAT_STEP
		# projection and not a hand-built config.
		#
		# The condition is what arm 5 needs: an unconditional retreat runs until the
		# map edge and never shows the unit coming to REST, which is the second half
		# of "one tile, then reevaluate". `target_within` is MANHATTAN, the same
		# metric the arms sample in.
		var flee := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.target_within(REST_DISTANCE)],
			Gambit.ActionKind.RETREAT, -1, TargetSelector.triggering())
		# An EXPLICIT Wait under it, because ADR-0048's injected safety net sits at
		# slot 5 of every encoded list: without this the moment the retreat stops
		# firing the Runner would attack-nearest, walk back, and red arms 1 and 3
		# for a reason that is the harness rather than the kernel.
		var hold := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())
		return GambitEncoder.encode_gambits([flee, hold])

	# Stuck: a retreat that can never be taken, over a move that can.
	var impossible := Gambit.create(
		TargetSelector.self_(), [GambitCondition.always()],
		Gambit.ActionKind.RETREAT, -1, TargetSelector.self_())
	var approach := Gambit.create(
		TargetSelector.self_(), [GambitCondition.always()],
		Gambit.ActionKind.MOVE, -1, TargetSelector.enemies())
	return GambitEncoder.encode_gambits([impossible, approach])


func on_state_changed(unit_idx: int, _old_state: int, new_state: int) -> void:
	if unit_idx == 0:
		if new_state == GPUConstants.LOGICAL_ACTIVITY_RETREATING:
			_runner_saw_retreating = true
		elif new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
			_runner_saw_acting = true
		elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
			_runner_saw_walking = true
	elif unit_idx == 1:
		if new_state == GPUConstants.LOGICAL_ACTIVITY_APPROACHING:
			_stuck_saw_approaching = true
		elif new_state == GPUConstants.LOGICAL_ACTIVITY_RETREATING:
			_stuck_saw_retreating = true
		elif new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
			_stuck_saw_acting = true


## Any HP change at all, named. Arm 3 scores Chaser's HP at the end; this prints
## WHEN and to WHOM so a red reads as an event instead of a final number -- which
## is how the (0, 0) artifact above was pinned down rather than guessed at.
func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta_hp: int) -> void:
	var names := ["Runner", "Stuck", "Chaser"]
	var who: String = names[unit_idx] if unit_idx < names.size() else str(unit_idx)
	print("[hp] tick %d %s %d -> %d (%d)" % [current_tick, who, old_hp, new_hp, delta_hp])


func _process(delta: float) -> void:
	super._process(delta)
	if _done or not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 3:
		return

	var runner = states[0]
	var chaser = states[2]
	var dist: int = (abs(int(runner["pos_x"]) - int(chaser["pos_x"]))
		+ abs(int(runner["pos_z"]) - int(chaser["pos_z"])))
	_samples += 1

	if _start_dist < 0:
		_start_dist = dist
		_max_dist = dist
	else:
		# Arm 1. Every sample, not only the ones taken mid-step: Chaser never
		# moves, so nothing but Runner's own step can change this number, and a
		# fall is a retreat that closed distance.
		if dist < _last_dist:
			_regressions.append("tick %d: %d -> %d" % [current_tick, _last_dist, dist])
		_max_dist = maxi(_max_dist, dist)
	_last_dist = dist

	# Arm 5's sampler. The clock starts when the retreat CONDITION goes false --
	# distance >= REST_DISTANCE -- not when the cell stops changing, for the reason
	# on SETTLE_SAMPLES. From that point no new step may be chosen, so a cell that
	# moves afterwards is itself a failure worth naming.
	var cell := Vector2i(int(runner["pos_x"]), int(runner["pos_z"]))
	if _settle_tick < 0:
		if dist >= REST_DISTANCE:
			_settle_tick = current_tick
			_settle_cell = cell
	else:
		# A cell change AFTER the clock starts is not automatically a failure --
		# the step that was already in flight when the condition flipped still
		# lands. It is only a failure if it happens once the clock has run out,
		# which is what arm 5's second branch scores.
		if cell != _settle_cell:
			_settle_cell = cell
			if current_tick - _settle_tick >= SETTLE_TICKS:
				_settle_moved = true
		if current_tick - _settle_tick >= SETTLE_TICKS:
			_runner_rest_state = int(runner.get("state", -1))

	# All five arms are decided the moment Runner has opened enough ground and
	# settled, AND Stuck has been seen falling through. Quitting here rather than
	# at max_ticks is what keeps this a ~15 s test instead of a 2000-tick one.
	if (_stuck_saw_approaching and _runner_rest_state >= 0
			and (_max_dist - _start_dist) >= MIN_TILES_OPENED):
		_score()


func on_victory(_winning_team: int) -> void:
	_score()


func _on_loop_timed_out(tick: int) -> void:
	# Score before the base quits, so a run that never reached the quit condition
	# reports WHICH arm was still open rather than only TIMEOUT.
	_score()
	super._on_loop_timed_out(tick)


func _score() -> void:
	if _done:
		return
	_done = true

	var states = gpu_state_reader.get_all_unit_states()
	var runner = states[0]
	var stuck = states[1]
	var chaser = states[2]
	var chaser_hp: int = int(chaser.get("hp", -1))
	var opened: int = _max_dist - _start_dist

	print("\n=== RETREAT STEP TEST RESULTS ===")
	print("  samples          : %d over %d ticks" % [_samples, current_tick])
	print("  Chaser           : (%d,%d) hp %d (start %d)" % [
		chaser["pos_x"], chaser["pos_z"], chaser_hp, CHASER_START_HP])
	print("  Runner           : (%d,%d), dist %d -> %d (max %d, opened %d)" % [
		runner["pos_x"], runner["pos_z"], _start_dist, _last_dist, _max_dist, opened])
	print("  Runner states    : RETREATING seen=%s ACTING seen=%s WALKING seen=%s" % [
		_runner_saw_retreating, _runner_saw_acting, _runner_saw_walking])
	print("  Stuck            : (%d,%d) APPROACHING seen=%s RETREATING seen=%s ACTING seen=%s" % [
		stuck["pos_x"], stuck["pos_z"], _stuck_saw_approaching, _stuck_saw_retreating,
		_stuck_saw_acting])

	var checks := 0
	var ok := true

	# --- Arm 1: a retreat only ever opens distance ---------------------------
	checks += 1
	if not _regressions.is_empty():
		ok = false
		print("  [x] arm 1: distance FELL while retreating, %d time(s): %s"
			% [_regressions.size(), ", ".join(_regressions.slice(0, 5))])
	else:
		print("  [ok] arm 1: distance never fell across %d samples" % _samples)

	# --- Arm 2: it moved, repeatedly ----------------------------------------
	checks += 1
	if not _runner_saw_retreating:
		ok = false
		print("  [x] arm 2: Runner was never seen in LOGICAL_ACTIVITY_RETREATING")
	elif opened < MIN_TILES_OPENED:
		ok = false
		print("  [x] arm 2: Runner opened %d tiles of distance, wanted >= %d"
			% [opened, MIN_TILES_OPENED])
	else:
		print("  [ok] arm 2: Runner retreated and opened %d tiles" % opened)

	# --- Arm 3: a retreat never attacks -------------------------------------
	checks += 1
	if _runner_saw_acting:
		ok = false
		print("  [x] arm 3: Runner entered ACTING — a retreat must never attack")
	elif _runner_saw_walking:
		ok = false
		print("  [x] arm 3: Runner entered WALKING — that state carries "
			+ "handle_moving_state's opportunistic attack, which a retreat must not")
	elif chaser_hp != CHASER_START_HP:
		ok = false
		print("  [x] arm 3: Chaser took damage (%d -> %d)" % [CHASER_START_HP, chaser_hp])
	else:
		print("  [ok] arm 3: Chaser untouched, Runner never acted and never WALKED")

	# --- Arm 4: an impossible retreat falls through -------------------------
	checks += 1
	if _stuck_saw_retreating:
		ok = false
		print("  [x] arm 4: Stuck entered RETREATING — a self-aimed retreat must be refused")
	elif not _stuck_saw_approaching:
		ok = false
		print("  [x] arm 4: Stuck never entered APPROACHING — slot 1 was never reached, "
			+ "so the declined retreat committed the slot instead of falling through")
	else:
		print("  [ok] arm 4: Stuck fell through its impossible retreat to slot 1")

	# --- Arm 5: the unit comes to REST when the retreat stops ----------------
	checks += 1
	var rest_name: String = (GPUConstants.LOGICAL_ACTIVITY_NAMES[_runner_rest_state]
		if _runner_rest_state >= 0 else "never settled")
	if _runner_rest_state < 0:
		ok = false
		print("  [x] arm 5: Runner never reached distance %d, so the retreat condition "
			% REST_DISTANCE
			+ "never went false and the arm never got a reading")
	elif _runner_rest_state != GPUConstants.LOGICAL_ACTIVITY_IDLE:
		ok = false
		print("  [x] arm 5: Runner stopped moving but its Logical activity is %s, not IDLE — "
			% rest_name
			+ "the retreat state outlived its step")
	elif _settle_moved:
		ok = false
		print("  [x] arm 5: Runner kept stepping after its retreat condition went false")
	else:
		print("  [ok] arm 5: Runner settled to IDLE once its retreat condition went false")

	print("  Runner at rest   : %s (settle clock from tick %d, moved after=%s)" % [
		rest_name, _settle_tick, _settle_moved])
	print("  assertions checked: %d" % checks)
	if ok:
		print("[PASS] retreat is one tile away, repeated, and declines to a fall-through")
	else:
		print("[FAIL] retreat step behaviour incorrect")
	print("=== END RESULTS ===")
	get_tree().quit()
