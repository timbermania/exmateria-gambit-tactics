extends Node3D
## Turn director test (ADR-0239) — the freeze / commit / cancel cycle, on a BARE
## `CombatLoop`.
##
## The mount is the point. Design S1 puts the director on a `CombatLoop` and not
## on a host precisely so a third host duplication never appears, and the stated
## consequence is that "a test must be able to mount the director on a bare
## `CombatLoop` with no host scene at all." This harness is that consequence: it
## extends `Node3D`, NOT `GPUCombatTestBase` (which is a `CombatHost`), and it
## stands the loop up by hand.
##
## It goes further than the ticket asked and carries **no `Unit` nodes either** —
## `_check_state_changes` and `_read_tick_columns` both clamp their loops to
## `units.size()`, so the whole CPU apply pump is skipped and what remains is the
## GPU sim, the pump, and the gate. That is the smallest thing the director can
## be wrong on top of. Every unit holds an EMPTY gambit list, so across the whole
## run the only unit field that moves is the turn meter — a battle that is a pure
## clock.
##
##   1. Exact-tick freeze — ONE `tick()` call is handed a full second (60 ticks)
##      of delta, and the world must stop on the tick the first unit crosses, not
##      at the end of the frame. This is the arm that falsifies the cheap
##      alternative: a frame here runs 60 ticks and a turn is ~13, so a
##      frame-granular stop would overrun four whole turns. The crossing tick is
##      predicted independently by `TurnQueue`'s closed form.
##   2. Commit spends and resumes — the meter drops by exactly FULL with the
##      overshoot CARRIED, the world unfreezes, and a second turn arrives later.
##   3. Cancel is bit-identical — a real `reconfigure_unit` edit is applied, is
##      PROVEN to have changed the buffer (else the arm passes vacuously), and
##      `cancel` restores all four snapshot slices byte for byte and re-opens the
##      SAME turn with the meter unspent.
##   6. The stop policy that does not stop — the SAME fat frame is driven twice,
##      once under each value of `stops_the_world`, and the two are compared. Under
##      WAIT the frame breaks off at the first crossing; under the walk's policy the
##      whole 60 ticks drain while turns are announced and SPENT inside them. This is
##      the arm that says the policy is a stop policy and not an off switch — a
##      director that simply stopped gating would pass "the frame drained" and fail
##      "turns were committed".
##
##   4. Playback rate is a viewing rate — across three stretches at 1x / 2x / 4x,
##      the tick length of each stretch equals `TurnQueue.forecast`'s closed-form
##      prediction regardless of rate, while the frame count falls with the rate.
##      This is the arm that stops someone re-coupling combat speed to frame rate.

# ADR-0211 dec. 4 — the addon's facade is its whole symbol surface, and one alias
# line per file keeps the use site's spelling. This file extends Node3D (not a
# CombatHost), so nothing up the chain declares it for us.
const Lattice = ExMateriaBattlefield.Lattice

const TICK_INTERVAL: float = 1.0 / 60.0
const FULL := GPUCombatPacker.TURN_METER_FULL
const SEED := 12345
const UNITS_PER_BATTLE := 8
## A frame big enough that a frame-granular stop is unmistakable: 60 ticks, when
## the first crossing lands inside ~13.
const FAT_FRAME: float = 1.0
## How far short of `TURN_METER_FULL` arm 6 seeds every living meter, in ticks of
## that unit's own gain. Comfortably inside `FAT_FRAME`'s 60 ticks and comfortably
## clear of 0, so the crossing lands in the MIDDLE of the frame — a seed that
## crossed on tick 1 would pass "the frame broke off short" without ever showing
## that it broke off AT the crossing.
const SEED_TICKS_SHORT: int = 10
## Belt on every drive loop. A director that never re-opens would otherwise hang,
## and a hang is a worse verdict than a failure because nothing names it.
const MAX_FRAMES: int = 4000

var _loop: CombatLoop = null
var _director: TurnDirector = null
var _sim = null
var _opened: Array = []      # taker indices, in the order turn_opened fired
var _committed: Array = []
var _cancelled: Array = []
var _resumed: int = 0
## Every (state, combat_active) pair observed from inside a director signal.
## `RUNNING` must mean the world is live, at every point an observer can look.
var _observations: Array = []


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not _build_bare_loop():
		print("[FAIL] Turn director: bare CombatLoop did not come up")
		get_tree().quit()
		return

	var failed := false
	failed = _arm_1_exact_tick_freeze() or failed
	failed = _arm_2_commit_spends_and_resumes() or failed
	failed = _arm_3_cancel_is_bit_identical() or failed
	failed = _arm_4_rate_is_a_viewing_rate() or failed
	failed = _arm_5_running_iff_live() or failed
	failed = _arm_6_the_policy_that_does_not_stop() or failed
	failed = _arm_7_the_taker_has_committed_to_nothing() or failed

	if failed:
		print("[FAIL] Turn director test")
	else:
		print("[PASS] Turn director: exact-tick freeze + commit/carry + bit-identical cancel + rate-is-viewing-only + RUNNING-iff-live + a stop policy that does not stop (spending into the buffer), over %d signal observations, on a bare CombatLoop (no host, no Unit nodes), %d turns opened" % [
			_observations.size(), _opened.size()])
	get_tree().quit()


# === Harness ==================================================================

## Stand up a `CombatLoop` with no host and no `Unit` nodes.
##
## Deliberately NOT `boot_battle`: that speaks `Unit` nodes (it connects their
## animation signals and reads `movement_component.current_cell`). The pieces it
## would do for us are done here directly, which is also what makes the bareness
## visible rather than asserted.
func _build_bare_loop() -> bool:
	# ADR-0192 dec. 3's clean fetch, and the node lands in a local FIRST: the port
	# guard resolves a receiver that is a plain identifier, not a `$NodePath`
	# expression, so `$ProceduralMap.lattice` reads to it as an un-annotated
	# duck-typed reach even with the annotation on the left.
	var map_node: Node3D = $ProceduralMap
	BattlefieldWiring.wire_map(map_node)
	var lat: Lattice = map_node.lattice
	if lat == null:
		push_error("[TurnDirectorTest] map has no lattice")
		return false

	_loop = CombatLoop.new()
	_loop.name = "CombatLoop"
	_loop.battle_name = "TurnDirectorTest"
	_loop.units_per_battle = UNITS_PER_BATTLE
	_loop.lattice = lat
	add_child(_loop)

	_loop.setup_distance_field()
	_loop.setup_gpu_simulator()
	if _loop.gpu_simulator == null:
		return false
	_sim = _loop.gpu_simulator
	_sim.set_battle_units(0, _team(0), _team(1), SEED)
	# A pure clock: nobody acts, so nothing but the meter moves all run.
	for i in range(UNITS_PER_BATTLE):
		_sim.set_unit_gambits(0, i, [])
	_loop.gpu_state_reader.initialize(_sim, 0)
	_loop._initialize_managers()

	_director = TurnDirector.mount(_loop, 0)
	_director.turn_opened.connect(func(taker: int, _team_id: int) -> void: _opened.append(taker))
	_director.turn_committed.connect(func(taker: int) -> void: _committed.append(taker))
	_director.turn_cancelled.connect(func(taker: int) -> void: _cancelled.append(taker))
	_director.resumed.connect(func() -> void: _resumed += 1)
	# Sample the invariant from INSIDE each signal — the only place a transient is
	# visible. Connected last so the counters above have already run.
	for sig in [_director.turn_opened, _director.turn_committed, _director.turn_cancelled]:
		sig.connect(func(_a = 0, _b = 0) -> void: _observe())
	_director.resumed.connect(_observe)
	# `mount` add_child's the director, whose `_ready` installs the gate — but
	# `_ready` on a node added mid-frame runs immediately, so the gate is live now.
	if not _loop.turn_gate.is_valid():
		push_error("[TurnDirectorTest] director did not install the turn gate")
		return false

	# The fat frame below is the arm, not an accident: arm 1 hands ONE `tick()` a full
	# second so that a frame-granular stop is unmistakable, and its guard accepts a
	# crossing as late as tick 59. `max_catchup_real_s` (W6) bounds a real second to 15
	# ticks on the shipped path.
	#
	# ⚠ Measured, not assumed: the suite is GREEN without this line — at SEED 12345 the
	# first crossing lands inside 15 and arm 1b's hunted stretch does too. So this is
	# not fixing a red. It restores the arm's STATED margin, which is the part that was
	# about to become luck: a different seed, a different speed table, or a stretch in
	# 16..59 would have failed on the clamp rather than on the director. A host that
	# deliberately hands the loop a fat frame is the case the knob exists to let through.
	_loop.max_catchup_real_s = INF

	_loop.combat_active = true
	return true


## Four spread-out units a side. Speeds are deliberately DISTINCT so the first
## crossing has a unique owner and arm 1's taker assertion cannot pass by
## coincidence; positions are far apart so nobody is ever in range even if a
## future default gambit stopped being empty.
func _observe() -> void:
	_observations.append({"state": _director.state(), "live": _loop.combat_active})


func _team(team_id: int) -> Array:
	var out: Array = []
	var base_x: int = 2 if team_id == 0 else 12
	var speeds: Array = [7, 9, 11, 13] if team_id == 0 else [8, 10, 12, 14]
	for i in range(4):
		out.append({
			"pos_x": base_x, "pos_z": 3 + i * 2,
			"hp": 200, "max_hp": 200, "mp": 50, "max_mp": 50,
			"speed": speeds[i], "move": 3, "jump": 3,
			"pa": 10, "ma": 10, "wp": 5, "brave": 60, "faith": 50,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		})
	return out


func _rows() -> Array:
	return TurnQueue.from_unit_states(_sim.get_battle_unit_states(0))


func _meter(unit_idx: int) -> int:
	var states: Array = _sim.get_battle_unit_states(0)
	return int(states[unit_idx].get("turn_meter", 0))


## Drive the loop until the director opens a turn. Returns the frame count, or -1
## if the belt bit. `delta` is per FRAME; how many ticks that buys is
## `playback_scale`'s business, which is exactly what arm 4 measures.
func _run_until_open(delta: float) -> int:
	var frames: int = 0
	while _director.state() != TurnDirector.State.TURN_OPEN:
		if frames >= MAX_FRAMES:
			return -1
		_loop.tick(delta)
		frames += 1
	return frames


# === 1. Exact-tick freeze =====================================================

func _arm_1_exact_tick_freeze() -> bool:
	var failed := false
	# The independent oracle: TurnQueue's closed form over the boot meters, which
	# knows nothing about the gate, the loop, or the GPU.
	var fc: Array = TurnQueue.forecast(_rows())
	if fc.is_empty():
		print("[FAIL] arm 1: the forecast is empty at boot — no unit can ever act")
		return true
	var expected_tick: int = int(fc[0]["ticks_from_now"])
	var expected_taker: int = int(fc[0]["index"])
	if expected_tick <= 0 or expected_tick >= 60:
		print("[FAIL] arm 1: first crossing at tick %d is outside the (0, 60) window this arm needs to be meaningful" % expected_tick)
		return true

	# ONE frame, sixty ticks of delta. A frame-granular stop lands at 60.
	_loop.tick(FAT_FRAME)

	if _loop.current_tick != expected_tick:
		print("[FAIL] arm 1: world stopped at tick %d, the crossing is at tick %d (a frame-granular stop would read 60)" % [
			_loop.current_tick, expected_tick])
		failed = true
	if _director.state() != TurnDirector.State.TURN_OPEN:
		print("[FAIL] arm 1: director is in state %d, expected TURN_OPEN" % _director.state())
		failed = true
	if _director.taker() != expected_taker:
		print("[FAIL] arm 1: taker is unit %d, the forecast says %d" % [_director.taker(), expected_taker])
		failed = true
	if _loop.combat_active:
		print("[FAIL] arm 1: the world is still live during an open turn")
		failed = true
	if _opened.size() != 1 or _opened[0] != expected_taker:
		print("[FAIL] arm 1: turn_opened fired %s, expected exactly [%d]" % [str(_opened), expected_taker])
		failed = true
	if _meter(expected_taker) < FULL:
		print("[FAIL] arm 1: the taker's meter is %d, below FULL — it was not actually ready" % _meter(expected_taker))
		failed = true
	return _arm_1b_mid_frame_stop() or failed


## Phase 2: the same claim on a stretch that is genuinely mid-frame.
##
## The BOOT crossing is always early — eight meters seeded uniformly in [0, FULL)
## put somebody within a tick or two of ready, which is domain truth rather than a
## harness artifact (no seed in 1..40000 produces a first crossing past tick 8 at
## this roster's speeds). So phase 1 discriminates tick 1 from tick 59, which is
## unmistakable but does not exercise "run 12 ticks into a 60-tick frame and stop
## there". This drains the boot burst and does exactly that.
func _arm_1b_mid_frame_stop() -> bool:
	# Drain whatever is ready at boot, then walk forward until a stretch is long
	# enough that a mid-frame stop is the only way to land on it.
	for _attempt in range(12):
		while _director.state() == TurnDirector.State.TURN_OPEN:
			if not _director.commit():
				print("[FAIL] arm 1b: commit() refused while draining the boot burst")
				return true
		var fc: Array = TurnQueue.forecast(_rows())
		if fc.is_empty():
			print("[FAIL] arm 1b: empty forecast while looking for a stretch")
			return true
		var gap: int = int(fc[0]["ticks_from_now"])
		if gap >= 3 and gap < 55:
			var start: int = _loop.current_tick
			# One frame, sixty ticks of budget, and the stop must land inside it.
			_loop.tick(FAT_FRAME)
			var ran: int = _loop.current_tick - start
			var ok := true
			if ran != gap:
				print("[FAIL] arm 1b: a 60-tick frame ran %d ticks, the crossing is %d ticks out" % [ran, gap])
				ok = false
			if _director.state() != TurnDirector.State.TURN_OPEN:
				print("[FAIL] arm 1b: the world did not stop at the crossing %d ticks into the frame" % gap)
				ok = false
			if int(fc[0]["index"]) != _director.taker():
				print("[FAIL] arm 1b: mid-frame taker is %d, the forecast says %d" % [
					_director.taker(), int(fc[0]["index"])])
				ok = false
			return not ok
		if _run_until_open(TICK_INTERVAL) < 0:
			print("[FAIL] arm 1b: no turn arrived while hunting a stretch")
			return true
	print("[FAIL] arm 1b: no stretch of 3..54 ticks appeared in 12 turns — the arm never ran")
	return true


# === 2. Commit spends and resumes =============================================

func _arm_2_commit_spends_and_resumes() -> bool:
	var failed := false
	# Arm 1b leaves the world wherever its stretch hunt ended, so open a turn if one
	# is not already open rather than assuming arm 1's.
	if _director.state() != TurnDirector.State.TURN_OPEN:
		if _run_until_open(TICK_INTERVAL) < 0:
			print("[FAIL] arm 2: no turn arrived to commit within %d frames" % MAX_FRAMES)
			return true
	var taker: int = _director.taker()
	var before: int = _meter(taker)
	var tick_at_commit: int = _loop.current_tick
	var resumed_before: int = _resumed

	if not _director.commit():
		print("[FAIL] arm 2: commit() refused an open turn")
		return true

	var after: int = _meter(taker)
	# Carry, not reset (ADR-0236): a unit that overshot by 7 is 7 ticks into its
	# next turn. Reset-to-zero would quantize turn spacing and drift fast units
	# off their true Speed ratio, and `before - FULL` is what measures that.
	if after != before - FULL:
		print("[FAIL] arm 2: meter went %d -> %d, expected %d (the overshoot was not carried)" % [
			before, after, before - FULL])
		failed = true
	if _committed.is_empty() or _committed[_committed.size() - 1] != taker:
		print("[FAIL] arm 2: the last turn_committed is %s, expected unit %d" % [
			str(_committed), taker])
		failed = true

	# Either another unit was ready at the same stop (drained without resuming) or
	# the world resumed. Both are correct; what must NOT happen is a resume with
	# somebody still ready.
	if _director.state() == TurnDirector.State.TURN_OPEN:
		if _loop.combat_active:
			print("[FAIL] arm 2: a drained second turn is open but the world is live")
			failed = true
	else:
		if not _loop.combat_active:
			print("[FAIL] arm 2: the turn was committed and nobody is up, but the world is still frozen")
			failed = true
		if _resumed != resumed_before + 1:
			print("[FAIL] arm 2: resumed fired %d time(s), expected exactly one" % (_resumed - resumed_before))
			failed = true
		if not TurnQueue.ready_now(_rows()).is_empty():
			print("[FAIL] arm 2: the world resumed with a unit still ready")
			failed = true
		# And the next turn is genuinely LATER — the clock advanced.
		if _run_until_open(TICK_INTERVAL) < 0:
			print("[FAIL] arm 2: no second turn arrived within %d frames" % MAX_FRAMES)
			return true
		if _loop.current_tick <= tick_at_commit:
			print("[FAIL] arm 2: the second turn opened at tick %d, not after the commit at %d" % [
				_loop.current_tick, tick_at_commit])
			failed = true
	return failed


# === 3. Cancel is bit-identical ===============================================

func _arm_3_cancel_is_bit_identical() -> bool:
	var failed := false
	if _director.state() != TurnDirector.State.TURN_OPEN:
		print("[FAIL] arm 3: no turn is open to cancel")
		return true
	var taker: int = _director.taker()
	var reference: Dictionary = _sim.snapshot_battle(0)
	var meter_before: int = _meter(taker)

	# A REAL edit through the keystone's second primitive — the same call the
	# adjustment UI makes. `pa` is a plain config field, so this is a job/equipment
	# change in miniature.
	if not _sim.reconfigure_unit(0, taker, {"pa": 99}):
		print("[FAIL] arm 3: reconfigure_unit refused unit %d" % taker)
		return true

	# The edit must have LANDED. Without this the cancel below would be comparing
	# an unchanged buffer against itself and would pass having proved nothing.
	var edited: Dictionary = _sim.snapshot_battle(0)
	if _slices_equal(reference, edited):
		print("[FAIL] arm 3: reconfigure_unit changed nothing — the cancel arm would be vacuous")
		return true

	if not _director.cancel():
		print("[FAIL] arm 3: cancel() refused an open turn")
		return true

	var restored: Dictionary = _sim.snapshot_battle(0)
	if not _slices_equal(reference, restored):
		print("[FAIL] arm 3: cancel did not restore the pre-turn image byte for byte")
		failed = true
	if _cancelled.size() != 1 or _cancelled[0] != taker:  # cancel fires exactly once in this run
		print("[FAIL] arm 3: turn_cancelled fired %s, expected [%d]" % [str(_cancelled), taker])
		failed = true
	# Cancel undoes the EDITS, not the turn: the meter was never spent, so the same
	# unit is still up and the same turn is open again.
	if _director.state() != TurnDirector.State.TURN_OPEN:
		print("[FAIL] arm 3: after cancel the director is in state %d — the turn was eaten, not undone" % _director.state())
		failed = true
	if _director.taker() != taker:
		print("[FAIL] arm 3: after cancel the taker is %d, expected the same unit %d" % [_director.taker(), taker])
		failed = true
	if _meter(taker) != meter_before:
		print("[FAIL] arm 3: after cancel the meter is %d, expected the unspent %d" % [_meter(taker), meter_before])
		failed = true
	if _loop.combat_active:
		print("[FAIL] arm 3: the world is live with a re-opened turn")
		failed = true
	return failed


func _slices_equal(a: Dictionary, b: Dictionary) -> bool:
	for key in ["battle", "cooldowns", "gambits", "results"]:
		if (a[key] as PackedInt32Array).to_byte_array() != (b[key] as PackedInt32Array).to_byte_array():
			return false
	return true


# === 4. Playback rate is a viewing rate =======================================

func _arm_4_rate_is_a_viewing_rate() -> bool:
	var failed := false
	for rate in [1.0, 2.0, 4.0]:
		if _director.state() != TurnDirector.State.TURN_OPEN:
			if _run_until_open(TICK_INTERVAL) < 0:
				print("[FAIL] arm 4: no turn arrived to start the %sx stretch" % rate)
				return true
		# Set while frozen, which is when a player picks a speed. `_resume` lands
		# it, so the stretch that follows plays at this rate.
		TurnDirector.playback_rate = rate
		var start_tick: int = _loop.current_tick
		if not _director.commit():
			print("[FAIL] arm 4: commit() refused at %sx" % rate)
			return true
		if _director.state() == TurnDirector.State.TURN_OPEN:
			# A drained same-tick turn: no stretch to measure, take the next one.
			continue
		if not is_equal_approx(_loop.playback_scale, rate):
			print("[FAIL] arm 4: the loop is running at scale %s, the director's rate is %s" % [
				_loop.playback_scale, rate])
			return true

		# The closed form predicts the stretch's length in TICKS, from the post-
		# commit meters, knowing nothing about the rate.
		var fc: Array = TurnQueue.forecast(_rows())
		if fc.is_empty():
			print("[FAIL] arm 4: empty forecast mid-run")
			return true
		var expected_ticks: int = int(fc[0]["ticks_from_now"])
		var frames: int = _run_until_open(TICK_INTERVAL)
		if frames < 0:
			print("[FAIL] arm 4: the %sx stretch never ended within %d frames" % [rate, MAX_FRAMES])
			return true
		var actual_ticks: int = _loop.current_tick - start_tick

		# THE invariant: the stretch is the same number of ticks whatever the rate.
		if actual_ticks != expected_ticks:
			print("[FAIL] arm 4: at %sx the stretch ran %d ticks, the closed form says %d — the rate changed the SIM" % [
				rate, actual_ticks, expected_ticks])
			failed = true
		# And the rate bought wall clock: at 1x a frame is a tick, above 1x it is
		# strictly fewer frames for the same ticks.
		var ceiling: int = int(ceil(float(expected_ticks) / rate)) + 1
		if frames > ceiling:
			print("[FAIL] arm 4: at %sx the stretch took %d frames for %d ticks (at most %d expected)" % [
				rate, frames, expected_ticks, ceiling])
			failed = true
		if rate > 1.0 and expected_ticks > 2 and frames >= expected_ticks:
			print("[FAIL] arm 4: at %sx the stretch took %d frames for %d ticks — the rate bought nothing" % [
				rate, frames, expected_ticks])
			failed = true
	TurnDirector.playback_rate = 1.0
	return failed


# === 5. RUNNING iff the world is live =========================================

## The state machine's one cross-cutting invariant, sampled from inside every
## signal the director emits across the whole run.
##
## A director that flipped to RUNNING before actually resuming would hand each
## `turn_committed` subscriber a window that reads "running" while the world is
## frozen — and the drain (decision 8) makes that window REAL rather than
## theoretical, because a commit is routinely followed by another freeze rather
## than a resume. #894's UI and #897's AI both read this state; an undocumented
## transient here is something each would discover separately and separately
## work around.
func _arm_5_running_iff_live() -> bool:
	if _observations.size() < 8:
		print("[FAIL] arm 5: only %d signal observations — the arm barely ran" % _observations.size())
		return true
	var bad: int = 0
	for o in _observations:
		var running: bool = int(o["state"]) == TurnDirector.State.RUNNING
		if running != bool(o["live"]):
			bad += 1
	if bad > 0:
		print("[FAIL] arm 5: %d of %d observations had state RUNNING disagreeing with combat_active" % [
			bad, _observations.size()])
		return true
	return false


# === 6. The stop policy that does not stop ====================================

## `stops_the_world = false` (#898): the walk's policy, where a turn is announced
## and spent where it opens because nobody is there to take it.
##
## A/B on the SAME SEEDED IMAGE, so the comparison is between two policies and not
## between two moments: WAIT breaks the frame at the first crossing, the walk's
## policy drains all 60 ticks. Both halves have to hold — the drain alone would be
## satisfied by a director that stopped gating altogether, and the commits alone by
## one that froze and was resumed by somebody else.
##
## 🔴 THE SEED IS NOT SETUP CONVENIENCE, IT IS WHAT KEEPS THIS ARM CALIBRATED. Both
## halves are meaningless unless the fat frame CONTAINS a crossing, and this arm
## used to assume one by arithmetic that has since expired: its comment read "a fat
## frame is 60 ticks and a turn is ~13", which was true when `TURN_METER_FULL` was
## 100. `01ae0bda7` (#939) made the meter a dwell clock and moved FULL to 3600, so a
## turn is now ~400 ticks and a bare 60-tick frame holds no crossing at all —
## MEASURED at the top of this arm, the fullest meter was 2505/3600 and reached only
## 2985/3600 after the frame. Arm 6A had been reporting "the control is dead" ever
## since, correctly, about itself. Seeding each unit ten ticks of its OWN gain short
## of FULL puts the crossing back inside the frame and makes the arm independent of
## what FULL is next.
##
## # seeded-break: delete the two `_seed_meters_short_of_full` calls — the fat frame
## # holds no crossing at FULL=3600 and 6A reds with "the control is dead", which is
## # the state this arm was actually in on main until #1098.
func _arm_6_the_policy_that_does_not_stop() -> bool:
	var failed := false
	if _director.state() == TurnDirector.State.TURN_OPEN:
		_director.commit()
	_director.stops_the_world = true
	_director.playback_rate = 1.0
	_loop.playback_scale = 1.0

	# A. WAIT mode: the control. The seeded crossing is ~10 ticks in, so this MUST
	# break off short — arm 1 proves the exact tick, this only needs the break.
	_seed_meters_short_of_full(SEED_TICKS_SHORT)
	var t0: int = _loop.current_tick
	_loop.tick(FAT_FRAME)
	var wait_ticks: int = _loop.current_tick - t0
	if _director.state() != TurnDirector.State.TURN_OPEN:
		print("[FAIL] arm 6A: a fat frame under WAIT did not open a turn — the control is dead")
		return true
	if wait_ticks >= 60:
		print("[FAIL] arm 6A: WAIT drained %d ticks of a 60-tick frame without stopping" % wait_ticks)
		failed = true
	_director.commit()
	# THE DRAIN (decision 8) IS WHY ONE COMMIT IS NOT A RESUME. Every meter was
	# seeded, so they all cross inside the same frame and the commit hands straight
	# to the next ready unit instead of unfreezing. B measures a frame's tick drain,
	# so it has to start from a RUNNING world or it measures the freeze A left.
	var drained: int = 0
	while _director.state() == TurnDirector.State.TURN_OPEN and drained < MAX_FRAMES:
		_director.commit()
		drained += 1
	if _director.state() != TurnDirector.State.RUNNING:
		print("[FAIL] arm 6A: the world never resumed after %d commits — the drain does not terminate" % drained)
		return true

	# B. The walk's policy, on the same loop, the same size of frame, and the SAME
	# seeded image — A's commits spent every meter, so without re-seeding B would be
	# comparing two different worlds and calling the difference a policy.
	_director.stops_the_world = false
	_seed_meters_short_of_full(SEED_TICKS_SHORT)
	var opened_before: int = _opened.size()
	var committed_before: int = _committed.size()
	var t1: int = _loop.current_tick
	_loop.tick(FAT_FRAME)
	var free_ticks: int = _loop.current_tick - t1
	var opened: int = _opened.size() - opened_before
	var committed: int = _committed.size() - committed_before

	if free_ticks <= wait_ticks:
		print("[FAIL] arm 6B: the non-stopping policy drained %d ticks, no more than WAIT's %d" % [
			free_ticks, wait_ticks])
		failed = true
	if opened < 1 or committed != opened:
		print("[FAIL] arm 6B: %d turns announced and %d committed — every announced turn must be spent" % [
			opened, committed])
		failed = true
	# The world never stopped, and nobody is holding anything: no taker, and nothing
	# to cancel, because a turn nobody holds took no snapshot.
	if _director.state() != TurnDirector.State.RUNNING or not _loop.combat_active:
		print("[FAIL] arm 6B: the world is not running after a frame that stopped for nothing")
		failed = true
	if _director.taker() != -1:
		print("[FAIL] arm 6B: a taker (%d) is still holding a turn" % _director.taker())
		failed = true
	if _director.cancel():
		print("[FAIL] arm 6B: cancel() undid something — an unheld turn has nothing to undo")
		failed = true
	# C. THE SPEND REACHES THE BUFFER, and this is the arm that says so. Counting
	# distinct takers does NOT: a meter stops advancing at the crossing, and every
	# unit crosses carrying its OWN overshoot, so an unspent ready set keeps growing
	# and each bigger overshoot takes the head — the queue changes hands anyway, and
	# a "the queue moved" arm passes on a director that spends nothing.
	# Measured — that exact seed (drop the `consume_turn` call) passed this whole
	# test until the meter was read directly. So read it: the announcement fires
	# BEFORE the spend, so the meter it names is the unspent one, and one tick later
	# the buffer must show it dropped by exactly FULL with the overshoot carried —
	# arm 2's check, on the path that never freezes.
	var at_open: Dictionary = {}
	var probe: Callable = func(taker: int, _t: int) -> void: at_open[taker] = _meter(taker)
	_director.turn_opened.connect(probe)
	var before_n: int = _opened.size()
	var frames: int = 0
	while _opened.size() == before_n and frames < MAX_FRAMES:
		_loop.tick(TICK_INTERVAL)
		frames += 1
	_director.turn_opened.disconnect(probe)
	if _opened.size() == before_n:
		print("[FAIL] arm 6C: no turn was announced within %d single ticks" % MAX_FRAMES)
		return true
	var spent: int = _opened[_opened.size() - 1]
	var was: int = int(at_open.get(spent, -1))
	var now: int = _meter(spent)
	if was < FULL:
		print("[FAIL] arm 6C: unit %d was announced with meter %d, below FULL" % [spent, was])
		failed = true
	elif now != was - FULL:
		print("[FAIL] arm 6C: unit %d was announced at meter %d and reads %d — expected %d; the spend never reached the buffer" % [
			spent, was, now, was - FULL])
		failed = true

	_director.stops_the_world = true
	return failed


## Put every LIVING unit `ticks` ticks of its own gain short of `TURN_METER_FULL`,
## so the next fat frame is guaranteed to contain a meter crossing.
##
## Per-unit rather than one shared number, because the gain IS the unit's Speed
## (`TurnQueue.gain_per_tick`, the kernel's `max(1, U_SPEED)`) — a flat offset would
## put the fast units over the line and the slow ones nowhere near it, which is a
## seed that decides WHO takes the turn instead of only WHEN.
##
## Writes the buffer directly, the way `GPUTurnMeterTest`'s brake arm does. The
## alternative is ticking until somebody is nearly ready, which costs ~400 ticks a
## side and re-introduces exactly the arithmetic-about-FULL this arm just lost.
func _seed_meters_short_of_full(ticks: int) -> void:
	var sim = _loop.gpu_simulator
	var speeds: PackedInt32Array = sim.read_unit_column(0, GPUCombatPacker.UnitField.SPEED)
	var flags: PackedInt32Array = sim.read_unit_column(0, GPUCombatPacker.UnitField.FLAGS)
	for u in range(mini(speeds.size(), flags.size())):
		if (flags[u] & GPUConstants.FLAG_DEAD_BIT) != 0:
			continue
		var short_by: int = ticks * TurnQueue.gain_per_tick(speeds[u])
		sim._set_unit_field(0, u, GPUCombatPacker.UnitField.TURN_METER,
			maxi(0, GPUCombatPacker.TURN_METER_FULL - short_by))


# === 7. The taker has committed to nothing ====================================

## Unit indices arm 7 works with. Team 0 fills 0..3 and team 1 fills 4..7, so the
## attacker is 0 and its victim is the first of the other side.
const A7_ATTACKER := 0
const A7_VICTIM := 4
## Where arm 7's `move_to` edit sends the attacker. Three tiles up the z axis from
## its seat at (2, 3), which is exactly its `move` of 3 and is nowhere near the
## victim at (3, 3) — so "it went where the edit said" cannot be confused with
## "it walked at the enemy it was already fighting".
const A7_DEST := Vector2i(2, 6)
## Ticks arm 7 gives one phase. Generous against the ~13-tick turn and the tens of
## ticks an attack animation runs, and a BELT: every loop that uses it also has a
## state it is actually waiting for (charter clause 7).
const A7_TICKS := 400
## Ticks arm 7 watches a committed turn play out. Longer than one movement step and
## than one attack, so "nothing happened" had every chance not to be true.
const A7_WATCH := 180


## THE TURN OPENS ON A TAKER THAT HAS COMMITTED TO NOTHING — and the gambit written
## while it is open is what the unit does NEXT.
##
## This is the arm the whole turn-brake change exists for, and it is the ONE place the
## invariant is stated without a live scenario in the way. The reported symptom was a
## camera travelling to an empty-looking tile, but the reason the freeze has to land on
## an uncommitted unit is not cosmetic: [AdjustmentTurn.commit] and `GambitBattle`'s
## rollout beat both REWRITE the taker's gambit list while the turn is open, and a unit
## that had already committed to an action finishes that action regardless. The edit is
## accepted, acknowledged, and silently not what the unit does.
##
## Three claims, in the order they have to hold:
##
##   A. THE REFUSAL. The attacker is driven into a real, kernel-produced ACTING state
##      (it has an enemy in reach and an attack gambit — no state is hand-forged), and
##      only THEN is its meter set to FULL. From that tick until it reaches IDLE the
##      director must not open a turn, and the moment it does reach IDLE it must. The
##      arm records the refused ticks and fails if there were none, because "no turn
##      opened on a committed taker" is also what a unit that was never committed says.
##      This is `_open_turn`'s term 2 and nothing else: term 1 quantifies over movement
##      states, and ACTING is not one.
##
##   B. THE EDIT IS OBEYED — the empty half. With that turn open, the attacker's gambit
##      list is replaced with an EMPTY one, the way a player's adjustment or the AI's
##      re-plan replaces it. After the commit the unit must do nothing at all: same
##      cell, same `move_step_id`, still IDLE. A unit that had committed mid-attack
##      would swing anyway.
##
##   C. THE POSITIVE CONTROL, which is what makes B mean anything. The same unit, one
##      turn later, is handed a `move_to` gambit instead of an empty list — and it must
##      arrive at the named cell. Without C, "the unit did nothing" is exactly what a
##      broken write, a dead unit or a battle nobody is ticking reports.
##
## Arm 7 re-seeds the battle rather than inheriting arms 1-6's clock: it needs two units
## in weapon reach of each other (the pure-clock roster is deliberately spread so nobody
## ever is) and every other meter parked, so the taker is the taker by construction and
## not by a sort. It runs last for that reason.
##
## # seeded-break: drop the IDLE test in `TurnDirector._open_turn` (term 2) — A reds
## # with a turn opened on an ACTING taker.
## # seeded-break: make `AdjustmentTurn`-style edits land after the resume instead of
## # before it — C reds, the unit never leaves its seat.
func _arm_7_the_taker_has_committed_to_nothing() -> bool:
	var failed := false
	if _director.state() == TurnDirector.State.TURN_OPEN:
		_director.commit()
	_director.stops_the_world = true
	_director.playback_rate = 1.0
	_loop.playback_scale = 1.0
	_a7_seed_the_duel()

	# --- A. the refusal ----------------------------------------------------------
	_sim.set_unit_gambits(0, A7_ATTACKER, [_a7_attack_gambit()])
	var ticks := 0
	while _a7_state(A7_ATTACKER) != GPUConstants.LOGICAL_ACTIVITY_ACTING and ticks < A7_TICKS:
		_loop.tick(TICK_INTERVAL)
		ticks += 1
	if _a7_state(A7_ATTACKER) != GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("[FAIL] arm 7A: unit %d never reached ACTING in %d ticks (state %s) — the arm cannot present the state it is about" % [
			A7_ATTACKER, ticks, _a7_state_name(A7_ATTACKER)])
		return true

	# READY, mid-swing. The order matters: the state is the kernel's, the meter is ours.
	_sim._set_unit_field(0, A7_ATTACKER, GPUCombatPacker.UnitField.TURN_METER, FULL)
	var refused := 0
	var opened_on: int = -1
	var state_at_open: int = -1
	ticks = 0
	while _director.state() != TurnDirector.State.TURN_OPEN and ticks < A7_TICKS:
		_loop.tick(TICK_INTERVAL)
		ticks += 1
		if _director.state() == TurnDirector.State.TURN_OPEN:
			opened_on = _director.taker()
			state_at_open = _a7_state(opened_on)
			break
		if _a7_state(A7_ATTACKER) != GPUConstants.LOGICAL_ACTIVITY_IDLE:
			refused += 1
	if opened_on == -1:
		print("[FAIL] arm 7A: no turn opened in %d ticks with unit %d at FULL — the brake and the gate deadlocked" % [
			ticks, A7_ATTACKER])
		return true
	if refused == 0:
		print("[FAIL] arm 7A: the taker was never observed READY-and-uncommitted-not-yet — the refusal was never exercised, so a director that opens on anything would pass here")
		failed = true
	if opened_on != A7_ATTACKER:
		print("[FAIL] arm 7A: the turn opened on unit %d, not the one holding the full meter (%d)" % [
			opened_on, A7_ATTACKER])
		return true
	if state_at_open != GPUConstants.LOGICAL_ACTIVITY_IDLE:
		print("[FAIL] arm 7A: the turn opened on a taker in %s — an edit made now is not what it does next" % [
			GPUConstants.LOGICAL_ACTIVITY_NAMES[state_at_open] if state_at_open >= 0
				and state_at_open < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(state_at_open)])
		failed = true

	# --- B. an empty list is obeyed ----------------------------------------------
	var cell_before := _a7_cell(A7_ATTACKER)
	var step_before := _a7_field(A7_ATTACKER, GPUCombatPacker.UnitField.MOVE_STEP_ID)
	_sim.set_unit_gambits(0, A7_ATTACKER, [])
	if not _director.commit():
		print("[FAIL] arm 7B: the turn did not commit")
		return true
	for _i in range(A7_WATCH):
		_loop.tick(TICK_INTERVAL)
	if _a7_cell(A7_ATTACKER) != cell_before:
		print("[FAIL] arm 7B: the taker moved from %s to %s after its gambits were emptied — it finished something it had already committed to" % [
			cell_before, _a7_cell(A7_ATTACKER)])
		failed = true
	if _a7_field(A7_ATTACKER, GPUCombatPacker.UnitField.MOVE_STEP_ID) != step_before:
		print("[FAIL] arm 7B: the taker took a movement step after its gambits were emptied")
		failed = true

	# --- C. a move_to is obeyed — and B's control --------------------------------
	_sim._set_unit_field(0, A7_ATTACKER, GPUCombatPacker.UnitField.TURN_METER, FULL)
	ticks = 0
	while _director.state() != TurnDirector.State.TURN_OPEN and ticks < A7_TICKS:
		_loop.tick(TICK_INTERVAL)
		ticks += 1
	if _director.state() != TurnDirector.State.TURN_OPEN or _director.taker() != A7_ATTACKER:
		print("[FAIL] arm 7C: no second turn opened on unit %d in %d ticks (state %s, taker %d)" % [
			A7_ATTACKER, ticks, str(_director.state()), _director.taker()])
		return true
	_sim.set_unit_gambits(0, A7_ATTACKER, [_a7_move_to_gambit(A7_DEST)])
	if not _director.commit():
		print("[FAIL] arm 7C: the second turn did not commit")
		return true
	var arrived := false
	for _i in range(A7_WATCH):
		_loop.tick(TICK_INTERVAL)
		if _a7_cell(A7_ATTACKER) == A7_DEST:
			arrived = true
			break
	if not arrived:
		print("[FAIL] arm 7C: the taker was told to move to %s during its turn and is at %s after %d ticks — the edit was accepted and is not what the unit did" % [
			A7_DEST, _a7_cell(A7_ATTACKER), A7_WATCH])
		failed = true
	if not failed:
		print("[TurnDirectorTest] arm 7: the turn was refused for %d ticks while the taker was mid-attack, opened on IDLE, an emptied list left it on %s, and a move_to written during the next turn walked it to %s." % [
			refused, cell_before, A7_DEST])
	return failed


## Two units in weapon reach, everybody else parked. `speed` 1 on the six bystanders is
## what makes the taker unambiguous: at TURN_METER_FULL they need thousands of ticks to become
## ready, so nothing arm 7 does can be explained by somebody else's crossing.
func _a7_seed_the_duel() -> void:
	var team0: Array = []
	var team1: Array = []
	for i in range(4):
		team0.append(_a7_unit(2, 3 + i * 2, 7 if i == 0 else 1))
		team1.append(_a7_unit(3 if i == 0 else 13, 3 + i * 2, 1))
	_sim.set_battle_units(0, team0, team1, SEED)
	for i in range(UNITS_PER_BATTLE):
		_sim.set_unit_gambits(0, i, [])
	_loop.gpu_state_reader.initialize(_sim, 0)


func _a7_unit(x: int, z: int, speed: int) -> Dictionary:
	return {
		"pos_x": x, "pos_z": z,
		"hp": 500, "max_hp": 500, "mp": 50, "max_mp": 50,
		"speed": speed, "move": 3, "jump": 3,
		"pa": 10, "ma": 10, "wp": 5, "brave": 60, "faith": 50,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
	}


func _a7_attack_gambit() -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_ATTACK,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_THEM,
	}


## The destination is packed `x * 256 + z`, the encoding `handle_move_to` unpacks —
## the same one `GPUCombatTestBase.make_move_to_gambit` writes. Spelled here because
## this file extends `Node3D` and not that base (the bareness IS arm 1's claim).
func _a7_move_to_gambit(dest: Vector2i) -> Dictionary:
	return {
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_SELF,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_MOVE_TO,
		"action_id": dest.x * 256 + dest.y,
		"action_target_type": GPUConstants.TARGET_SELF,
	}


func _a7_field(unit_idx: int, field: int) -> int:
	var col: PackedInt32Array = _sim.read_unit_column(0, field)
	return col[unit_idx] if unit_idx >= 0 and unit_idx < col.size() else -1


func _a7_state(unit_idx: int) -> int:
	return _a7_field(unit_idx, GPUCombatPacker.UnitField.STATE)


func _a7_state_name(unit_idx: int) -> String:
	var s := _a7_state(unit_idx)
	if s < 0 or s >= GPUConstants.LOGICAL_ACTIVITY_NAMES.size():
		return str(s)
	return GPUConstants.LOGICAL_ACTIVITY_NAMES[s]


func _a7_cell(unit_idx: int) -> Vector2i:
	return Vector2i(_a7_field(unit_idx, GPUCombatPacker.UnitField.POS_X),
		_a7_field(unit_idx, GPUCombatPacker.UnitField.POS_Z))
