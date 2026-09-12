extends "res://src/scenes/GPUArena.gd"

## Units INTERPOLATE between tiles — they do not teleport.
##
## The regression this locks: `GPUVisualBridge.update_visual_positions` hands the
## per-frame snapshot ONE HOP further out, into
## `GPUMovementInterpreter.classify()`, which reads `prev_move_pos` and
## `move_step_id`. W1's lean snapshot (`SNAPSHOT_HOT_UNION`) omitted both, so
## `prev_move_pos` fell to its `.get()` default of -1, the `from_packed >= 0`
## clause went false, and classify() returned `NO_MOVE` for every unit on every
## frame. The bridge's NO_MOVE branch snaps to the destination tile, so a battle
## rendered as tile-to-tile teleports with no walk animation and no
## facing-from-movement. Reported by the player as "battles got all chunky".
##
## ⚠ WHY THIS SCENE EXISTS ALONGSIDE `GPUSnapshotUnionTest`. That test could not
## see this, and the reason generalises. It poisons every NON-union field and
## fails when a poisoned value REACHES a unit's stats or a visual position. Here
## the poisoned `prev_move_pos` is never propagated — it is COMPARED, fails the
## comparison, and suppresses interpolation. Every position the bridge writes
## stays a legitimate lattice coordinate. A guard that watches for an absurd
## VALUE is blind to a field whose only job is to gate a branch.
##
## So this arm asserts the BEHAVIOUR instead: over a seeded battle, movement is
## interpolated rather than snapped. It is pacing-independent — it asserts ratios
## and existence, never a per-tick trace or a literal frame count.
##
## PASS: at least one unit gets a live GPUMovementVisualizer, and the visual
##       positions move in sub-tile steps far more often than in tile-sized ones.
## FAIL: no visualizer is ever built (classify() never said NEW_STEP), or the
##       position deltas are dominated by whole-tile jumps.
##
## ── SECOND REGRESSION, SAME SCENE (#1206, ADR-0292) ──────────────────────────
## Interpolating between TILES is not enough if the thing sampling it is quantised to
## the TICK. `CombatLoop` drains whole `TICK_INTERVAL` steps out of an accumulator, and
## the visual path used to recompute from the resulting INTEGER tick — so any rendered
## frame that banked less than one tick redrew every walking unit at a bit-identical
## position. Measured on Gariland: 100.0% of zero-tick frames were duplicates. It is
## invisible at 60 Hz (4% of frames) and constant at 144 Hz (58%), which is why it was
## reported as "the whole game jitters" and not as a movement bug.
##
## The arms below are attached HERE rather than in a new scene on purpose: the charter
## prices a test in PROCESSES, and this scene already boots the exact battle they need.
## They are deterministic and load-independent — they hold the sim state STILL and move
## only the render clock, so they never depend on the box producing a zero-tick frame.
##
## Run headful (never --headless):
##   godot --path . tests/GPUVisualBridgeInterpolationTest.tscn

# Same seed as GPUSnapshotUnionTest / GPUTeleportTest — a battle already known to
# run a full engagement with movement, melee and projectiles.
const MOVE_SEED: int = 3601067600983631927
const CHECK_TICKS: int = 900

# A tile is 1.0 world unit. Interpolated motion advances a fraction of that per
# frame; a NO_MOVE snap moves the whole remaining distance in one frame. 0.35 sits
# well clear of both — MEASURED on this seed, the broken arm's smallest jump was a
# full tile and its largest 4.0, while the fixed arm's largest was 0.573 (one
# frame of a fast cliff arc), and 2272 of its 2279 deltas were under 0.35.
const SNAP_THRESHOLD := 0.35

var _done := false
var _frames := 0
var _frames_with_viz := 0
var _units_with_viz := {}
var _lerp_deltas := 0
var _snap_deltas := 0
var _max_jump := 0.0
var _prev_pos := {}
var _hot_has_fields := false
var _hot_sampled := false

# --- #1206 sub-tick arms -------------------------------------------------------------
## Samples of a LIVE visualizer asked for the same move at two different points inside one
## tick. `_subtick_moved` is how many of them answered with a different position.
var _subtick_samples := 0
var _subtick_moved := 0
## Cliff / pass-through visualizers, which are allowed to hold still — counted, not gated.
var _subtick_plateau_shapes := 0
## Diagnosis only (see `_finish`): how the run's real zero-tick frames actually behaved.
var _prev_tick_seen := -1
var _zero_tick_frames := 0
var _zero_tick_moving := 0
var _zero_tick_redrew := 0


func _ready():
	DebugConfig.combat_seed = MOVE_SEED
	DebugConfig.combat_autostart = true
	# Straight into the battle. This used to set `use_strategy_phase = false` because the
	# march was a separate CPU path that did not exercise the bridge and, on this seed,
	# did not finish inside CHECK_TICKS — a run that spent every tick marching observed
	# nothing. ADR-0258 retired the march, so the arena boots straight into the battle
	# for every host and the opt-out has nothing to opt out of.
	regression_logging = false
	max_ticks = CHECK_TICKS
	super._ready()


func get_test_name() -> String:
	return "GPU Visual Bridge Interpolation Test"


func _process(delta):
	super._process(delta)
	if _done:
		return

	# The union membership itself, asserted directly rather than inferred: the
	# behaviour arm below is the proof, this is the diagnosis printed beside it.
	if not _hot_sampled and combat_loop and combat_loop.gpu_state_reader:
		var hot: Array = combat_loop.gpu_state_reader.get_all_unit_states_hot()
		if hot.size() > 0:
			var s: Dictionary = hot[0]
			_hot_has_fields = s.has("prev_move_pos") and s.has("move_step_id")
			_hot_sampled = true

	if combat_active and _visual_bridge:
		_frames += 1
		_sample_subtick()
		# BEFORE `_prev_pos` is refreshed below — it needs last frame's positions.
		_count_zero_tick_frame()
		if _visual_bridge.movement_visualizers.size() > 0:
			_frames_with_viz += 1
			for k in _visual_bridge.movement_visualizers:
				_units_with_viz[k] = true
		for i in _visual_bridge.visual_positions:
			var p: Vector3 = _visual_bridge.visual_positions[i]
			if _prev_pos.has(i):
				var d: float = _prev_pos[i].distance_to(p)
				if d > 0.001:
					if d < SNAP_THRESHOLD:
						_lerp_deltas += 1
					else:
						_snap_deltas += 1
					_max_jump = maxf(_max_jump, d)
			_prev_pos[i] = p

	if victory_achieved or current_tick >= CHECK_TICKS:
		_finish()


## Hold the SIM still; move only the RENDER clock.
##
## This is the whole defect in two calls: a live visualizer is asked for the same move at
## two points inside ONE tick, and the answers must differ. Nothing here depends on the box
## producing a zero-tick frame, so it says the same thing under suite load as it does idle —
## which the observational counters below emphatically do not.
##
## 🔴 IT SAMPLES ONLY THE PLAIN ADJACENT WALK, AND THAT IS NOT A DODGE. A cliff move is a
## three-phase curve whose JUMPING phase holds `start_pos` and whose LANDING phase holds
## `end_pos` — those plateaus are STILL BY DESIGN, and `_scale_phase`'s own comment records
## budgets where a phase swallows the entire move. A pass-through's legs inherit the same
## shapes. Demanding motion there would assert that a correct plateau is a defect: measured
## on this seed, an indiscriminate sampler found 3998 of 4359 samples moving and the 361
## were all legitimate. So the arm asks the one shape that has NO licence to stand still —
## `_legs` empty and not a cliff, i.e. `calculate_position` reduced to a pure lerp between
## two distinct points — and demands EVERY such sample respond. The plateaued shapes are
## counted separately and printed, never gated.
func _sample_subtick() -> void:
	for k in _visual_bridge.movement_visualizers:
		var viz = _visual_bridge.movement_visualizers[k]
		if viz == null or not is_instance_valid(viz):
			continue
		var total: int = viz.gpu_total_ticks if viz.gpu_total_ticks > 0 else viz.total_ticks
		if total <= 2:
			continue
		if viz.start_pos.distance_to(viz.end_pos) < 0.01:
			continue
		# 🔴 BOTH SAMPLES MUST FALL INSIDE THE SAME INTEGER TICK, and getting this wrong is
		# not theoretical — the first version of this arm sampled `mid` and `mid - 0.5`,
		# which STRADDLE an integer. A re-quantised `calculate_position` (seeded with
		# `floorf(timer)`) still answered those two differently, so the arm passed 1644/1644
		# while the run's real zero-tick frames redrew 0 of 240. It asserted "a half-tick
		# change moves the unit", which integer truncation satisfies. What it has to assert
		# is "a change WITHIN one tick moves the unit", which only a fractional timer can.
		var base := floorf(float(total) * 0.5) + 0.25
		var a: Vector3 = viz.calculate_position(base)
		var b: Vector3 = viz.calculate_position(base + 0.5)
		if not viz._legs.is_empty() or viz.is_cliff_move:
			_subtick_plateau_shapes += 1
			continue
		_subtick_samples += 1
		if a.distance_to(b) > 0.0:
			_subtick_moved += 1


## Observational only. The run's REAL zero-tick frames and whether movers redrew on them —
## the end-to-end quantity, and the one the box gets a vote in. At ~60 fps against a 60 Hz
## tick only ~4% of frames bank no tick, and under suite load that share collapses further,
## so this is PRINTED and never gates PASS. The arms that gate PASS are deterministic.
func _count_zero_tick_frame() -> void:
	if _prev_tick_seen >= 0 and current_tick == _prev_tick_seen:
		_zero_tick_frames += 1
		for i in _visual_bridge.visual_positions:
			if not _prev_pos.has(i):
				continue
			if _visual_bridge.movement_visualizers.has(i):
				_zero_tick_moving += 1
				if _prev_pos[i].distance_to(_visual_bridge.visual_positions[i]) > 0.0:
					_zero_tick_redrew += 1
	_prev_tick_seen = current_tick


## `_render_timer` is the DECISION, so it is asserted as one (ADR-0292).
##
## Two properties, and the pair is the design: the mapping is CONTINUOUS across a tick
## boundary (alpha 1 at timer t must land exactly where alpha 0 at timer t-1 lands, because
## the tick firing and the alpha resetting have to cancel), and it interpolates BEHIND —
## it never returns a timer the sim has not reached. Extrapolating ahead would flip the
## second inequality, which is exactly the regression this arm exists to catch.
func _render_timer_arms() -> Array:
	var fails: Array = []
	var bridge = GPUVisualBridge
	for t in [0, 1, 7, 23]:
		var at_one: float = bridge._render_timer(t, 1.0)
		var next_at_zero: float = bridge._render_timer(t - 1, 0.0)
		if absf(at_one - next_at_zero) > 1e-6:
			fails.append("discontinuous at timer %d: alpha=1 -> %.6f but timer %d alpha=0 -> %.6f"
				% [t, at_one, t - 1, next_at_zero])
		for a in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var r: float = bridge._render_timer(t, a)
			# timer counts DOWN, so "behind" means >= the sim's own value.
			if r < float(t) - 1e-6:
				fails.append("EXTRAPOLATES AHEAD at timer %d alpha %.2f -> %.6f" % [t, a, r])
			if r > float(t) + 1.0 + 1e-6:
				fails.append("lags more than one tick at timer %d alpha %.2f -> %.6f" % [t, a, r])
	return fails


func _finish():
	_done = true

	# A run where nothing moved proves nothing — do not let it print PASS.
	var observed_movement: bool = (_lerp_deltas + _snap_deltas) > 0
	var built_visualizers: bool = _units_with_viz.size() > 0
	var interpolated: bool = _lerp_deltas > _snap_deltas
	# #1206. A run that never sampled a live visualizer mid-move proves nothing about the
	# sub-tick path either — so "no samples" is a FAIL, not a quiet pass.
	var subtick_sampled: bool = _subtick_samples > 0
	var subtick_responds: bool = subtick_sampled and _subtick_moved == _subtick_samples
	var render_timer_fails: Array = _render_timer_arms()
	var passed: bool = observed_movement and built_visualizers and interpolated \
		and subtick_responds and render_timer_fails.is_empty()

	print("\n=== %s ===" % get_test_name())
	print("[interp] seed %d, %d combat frames observed" % [MOVE_SEED, _frames])
	print("[interp] snapshot carries prev_move_pos + move_step_id: %s" % _hot_has_fields)
	print("[interp] frames with a live visualizer: %d  (units that got one: %d)" % [
		_frames_with_viz, _units_with_viz.size()])
	print("[interp] position deltas — interpolated (<%.2f): %d   snapped (>=%.2f): %d" % [
		SNAP_THRESHOLD, _lerp_deltas, SNAP_THRESHOLD, _snap_deltas])
	print("[interp] largest single-frame jump: %.3f" % _max_jump)
	print("[subtick] plain walks answered a FRACTIONAL timer differently: %d of %d samples"
		% [_subtick_moved, _subtick_samples]
		+ "  (%d cliff/pass-through samples skipped — plateaus are legal there)"
			% _subtick_plateau_shapes)
	print("[subtick] _render_timer arms: %d failure(s)" % render_timer_fails.size())
	# Diagnosis, not a gate — see `_count_zero_tick_frame`.
	if _zero_tick_moving > 0:
		print("[subtick] DIAGNOSIS ONLY — real zero-tick frames this run: %d; movers on them "
			% _zero_tick_frames + "redrew %d of %d (%.1f%%). Before #1206 this was 0%%."
			% [_zero_tick_redrew, _zero_tick_moving,
				100.0 * _zero_tick_redrew / _zero_tick_moving])
	else:
		print("[subtick] DIAGNOSIS ONLY — no zero-tick frame carried a mover this run "
			+ "(%d zero-tick frames). Unmeasured, not negative; the arms above are the guard."
			% _zero_tick_frames)

	if passed:
		print("[PASS] units interpolate between tiles: %d of %d position deltas were sub-tile" % [
			_lerp_deltas, _lerp_deltas + _snap_deltas])
	else:
		if not observed_movement:
			print("[FAIL] no unit moved at all — the fixture reached no movement, so it")
			print("       proves nothing about interpolation. Check the seed and CHECK_TICKS.")
		if not built_visualizers:
			print("[FAIL] no GPUMovementVisualizer was ever built: GPUMovementInterpreter")
			print("       .classify() never returned NEW_STEP. Its inputs are prev_move_pos")
			print("       and move_step_id — confirm both are in")
			print("       GPUCombatPacker.SNAPSHOT_HOT_UNION (carried: %s)." % _hot_has_fields)
		if not subtick_sampled:
			print("[FAIL] no plain adjacent walk was ever sampled mid-move (%d cliff/" % _subtick_plateau_shapes)
			print("       pass-through shapes were seen), so the #1206")
			print("       sub-tick arm asserted nothing. That is a broken fixture, not a")
			print("       pass — check CHECK_TICKS and the seed.")
		elif not subtick_responds:
			print("[FAIL] the visualizer returned the SAME position for two different points")
			print("       inside one tick (%d of %d samples moved). GPUMovementVisualizer" % [
				_subtick_moved, _subtick_samples])
			print("       .calculate_position is quantised to the integer tick again — the")
			print("       #1206 regression. Every rendered frame that banks less than a full")
			print("       tick will redraw walking units bit-identically (58%% of them at 144 Hz).")
		for f in render_timer_fails:
			print("[FAIL] GPUVisualBridge._render_timer: %s" % f)
			print("       See ADR-0292: it must be continuous across the tick boundary and")
			print("       must interpolate BEHIND, never extrapolate ahead of the sim.")
		if observed_movement and not interpolated:
			print("[FAIL] movement is dominated by whole-tile jumps (%d snapped vs %d" % [
				_snap_deltas, _lerp_deltas])
			print("       interpolated): the bridge is snapping to the GPU tile instead of")
			print("       following a visualizer.")

	DebugConfig.combat_seed = 0
	DebugConfig.combat_autostart = false
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
