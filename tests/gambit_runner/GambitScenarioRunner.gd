class_name GambitScenarioRunner
extends CombatHost

## Scenario registry + executor + reporter for the gambit scenario suite.
## See [code]docs/gambit-rules.md[/code] for the behavioral spec the suite
## encodes and [GambitAssertions] for the predicate vocabulary.
##
## Composes a [CombatLoop] (via the shared [CombatHost] base) one scenario at
## a time. Sorts scenarios by [code]map[/code] and calls
## [code]MapComposer.change_map[/code] at group boundaries only. For each
## scenario:
##   1. Spawn the configured units on the requested tiles.
##   2. Run each unit's gambits through [code]GambitEncoder.encode_gambits[/code]
##      (real domain objects, no flat-dict shortcuts).
##   3. Boot the loop on those units; wait for victory or [code]max_ticks[/code].
##   4. Hand the trace + expectations to [GambitAssertions], compute the
##      six-state verdict (PASS / FAIL / XFAIL / XPASS / ERROR / NORAN).
##   5. Tear the units + loop down; advance to the next scenario.
##
## Verdict aggregation: any FAIL or NORAN in the suite makes the overall test
## verdict FAIL; XFAIL / XPASS are loud-but-green by default (issue #57's
## `xpass_treatment: "soft"` knob).


# The four addon aliases this file used to carry (TerrainCell, UnitProgression,
# FacingDirection, ClockOwner) went with the spawn/spec bodies to
# [GambitScenarioBoot]. ADR-0211 dec. 4 makes a grep for a façade the census of
# host->addon coupling, so an alias kept past its last use site inflates that census.

# Six-state verdict taxonomy (issue #57). Values are strings so they print
# cleanly in the log without an enum-name lookup.
const VERDICT_PASS := "PASS"
const VERDICT_FAIL := "FAIL"
const VERDICT_XFAIL := "XFAIL"
const VERDICT_XPASS := "XPASS"
const VERDICT_ERROR := "ERROR"
const VERDICT_NORAN := "NORAN"

@export var test_time_scale: float = 4.0
@export var max_ticks_default: int = 200
@export var xpass_treatment: String = "soft"  # "soft" (default) or "hard"

@onready var map: Node3D = $ProceduralMap

# Scenario registry — built in _ready() from the per-rule script files.
var _scenarios: Array = []
# Internal NORAN fixture: a sentinel that intentionally doesn't run the sim
# and confirms the baseline check trips. Appended after real scenarios.
var _noran_fixture_appended: bool = false

# Aggregated counts for the summary block.
var _counts := {
	VERDICT_PASS: 0,
	VERDICT_FAIL: 0,
	VERDICT_XFAIL: 0,
	VERDICT_XPASS: 0,
	VERDICT_ERROR: 0,
	VERDICT_NORAN: 0,
}
var _scenario_results: Array = []  # array of {scenario, verdict, expectations}

# Per-scenario active state (cleared between scenarios).
var _active_trace: GambitTraceLogger = null
var _active_team_of: Dictionary = {}
var _active_done: bool = false
var _encoder_skip_count: int = 0

# Set by _load_scenarios when `--only=` trimmed the run list. Empty = full run.
var _scenario_filter: String = ""


func _ready() -> void:
	Engine.time_scale = test_time_scale
	_rlog = RegressionLogger.new("GambitScenarioRunner", true)
	print("\n=== Gambit Scenario Runner ===")

	# Wait for the map to build (MapComposer auto_build_on_ready).
	await get_tree().process_frame
	await get_tree().process_frame
	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	# ADR-0192 dec. 3's clean fetch, into a LOCAL annotated here (the field is
	# inherited from `CombatHost` and the register's inference is per file).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		push_error("[GambitScenarioRunner] No lattice after map build")
		get_tree().quit()
		return

	_scenarios = _load_scenarios()
	_sort_scenarios_by_map()
	_run_all()


# ============================================================================
# Scenario loading
# ============================================================================

func _load_scenarios() -> Array:
	"""Every fixture dict under [code]tests/gambit_scenarios/[/code]. The count is
	deliberately NOT written down here — it said 84 while the walk returned 92, because a
	number in a docstring rots silently every time a group grows. The walk lives in
	[GambitScenarioBoot] because the live arm
	replays the same corpus read-only (ADR-0275 dec. 17) and "the fixture set" must not mean
	two different things depending on which arm asked."""
	var all: Array = GambitScenarioBoot.load_scenarios()
	# Iteration affordance, opt-in and LOUD:
	#
	#     godot --path . res://tests/GambitScenarioRunnerTest.tscn -- --only=corpse
	#
	# runs only the scenarios whose `rule` or `name` contains the needle — 40 seconds
	# instead of 12 minutes while a kernel change is still being diagnosed. A CLI arg and
	# not an env var, because ADR-0051 bans env vars for scene configuration and the tree
	# already reads `OS.get_cmdline_user_args()` in 18 files (GambitLabScene's `--scenario=`
	# is the same verb). The walk itself is untouched — the live arm reads the SAME corpus
	# (ADR-0275 dec. 17) — and the filter applies to this arm's RUN LIST only, after it.
	#
	# 🔴 A FILTERED RUN CANNOT REPORT GREEN. `_print_summary` forces the tail line to
	# [FAIL] whenever the filter is set, so a filtered run can never be mistaken for the
	# suite's verdict — which is the only way an affordance like this turns into a lie.
	var filt := ""
	for a in OS.get_cmdline_user_args():
		var arg: String = a
		if arg.begins_with("--only="):
			filt = arg.substr("--only=".length()).strip_edges()
	if filt.is_empty():
		return all
	_scenario_filter = filt
	var kept: Array = []
	for sc in all:
		var rule := String(sc.get("rule", ""))
		var sname := String(sc.get("name", ""))
		if rule.contains(filt) or sname.contains(filt):
			kept.append(sc)
	print("\n🔴 --only=%s — running %d of %d scenarios. THIS IS NOT A SUITE VERDICT.\n"
			% [filt, kept.size(), all.size()])
	return kept


func _sort_scenarios_by_map() -> void:
	# Group by `map:` so MapComposer.change_map is called at group boundaries.
	_scenarios.sort_custom(func(a, b): return a.get("map", "") < b.get("map", ""))


# ============================================================================
# Scenario execution
# ============================================================================

func _run_all() -> void:
	var current_map := ""
	for scenario in _scenarios:
		var map_id: String = scenario.get("map", "MAP042")
		if map_id != current_map:
			print("\n[GambitScenarioRunner] changing to %s" % map_id)
			map.change_map(map_id)
			# `map.lattice` is the SAME object across a change_map — the composer
			# rebinds the port onto the new store rather than replacing it
			# (`Lattice._bind`), precisely so a handle taken at boot keeps answering
			# for the map on screen. Re-read anyway: it costs nothing and this line
			# is where a future change to that rule would have to be noticed.
			await get_tree().process_frame
			var lat2: Lattice = map.lattice
			lattice = lat2
			current_map = map_id
		await _run_one(scenario)

	# Internal NORAN fixture: simulate "sim never advanced" by stopping a
	# zero-tick scenario and confirm the baseline check trips. Demonstrates
	# the sentinel is reachable.
	await _run_noran_fixture()

	_print_summary()
	get_tree().quit()


func _run_one(scenario: Dictionary) -> void:
	var name: String = scenario.get("name", "<unnamed>")
	var rule: String = scenario.get("rule", "??")
	var max_ticks: int = scenario.get("max_ticks", max_ticks_default)
	print("\n[%s/%s] starting (max_ticks=%d)" % [rule, name, max_ticks])

	# Per-scenario state reset.
	_active_trace = GambitTraceLogger.new(name, _rlog)
	_active_team_of.clear()
	_encoder_skip_count = 0
	_active_done = false

	# Spawn units; build team0/team1 from scenario.units.
	var unit_names: Array = []
	team0_units = []
	team1_units = []
	units = []
	for cfg in scenario.get("units", []):
		var spawned := await GambitScenarioBoot.spawn_unit(self, map, cfg, units.size())
		if spawned == null:
			_record_verdict(scenario, VERDICT_ERROR, [{
				"ok": false, "name": "spawn", "detail": "failed to spawn %s" % cfg.get("name", "?")
			}])
			return
		var unit_name: String = cfg.get("name", "Unit%d" % units.size())
		unit_names.append(unit_name)
		_active_team_of[units.size()] = cfg.get("team", 0)
		if cfg.get("team", 0) == 0:
			team0_units.append(spawned)
		else:
			team1_units.append(spawned)
		units.append(spawned)
	_active_trace.bind_units(unit_names)

	# Encode gambits (real domain objects → GPU configs). Count skips for
	# expect_encoder_skips bookkeeping. Shared with the live arm (ADR-0275 dec. 17):
	# a fixture the lab replays must be the fixture this suite runs, down to the
	# encoder's own skip set.
	var encoded_all := GambitScenarioBoot.encode_units(scenario)
	var gambits_array: Array = encoded_all["gambits"]
	_encoder_skip_count = int(encoded_all["skips"])

	# Boot the loop; subscribe trace logger to its signals; run.
	combat_loop = CombatLoopClass.new()
	combat_loop.name = "CombatLoop"
	combat_loop.battle_name = name
	combat_loop._rlog = _rlog
	combat_loop.max_ticks = max_ticks
	combat_loop.lattice = lattice
	add_child(combat_loop)
	_connect_trace_signals(combat_loop)

	var spec := GambitScenarioBoot.build_battle_spec(scenario, lattice)
	combat_loop.start_battle(team0_units, team1_units, gambits_array,
			lattice, map, scenario.get("seed", 42), spec)
	_sync_loop_refs()
	combat_active = true

	# Block until victory or max_ticks (CombatLoop emits victory/timed_out).
	while not _active_done and current_tick < max_ticks:
		await get_tree().process_frame
	combat_active = false

	# Verdict.
	var verdict_data := _verdict_for(scenario)
	_record_verdict(scenario, verdict_data["verdict"], verdict_data["expectations"])

	_teardown_battle()


# ============================================================================
# Signal routing — feed the trace logger off the existing CombatLoop surface
# ============================================================================

func _connect_trace_signals(loop) -> void:
	loop.state_changed.connect(_on_loop_state_changed)
	loop.cast_began.connect(_on_loop_cast_began)
	loop.action_committed.connect(_on_loop_action_committed)
	loop.projectile_fired.connect(_on_loop_projectile_fired)
	loop.unit_died.connect(_on_loop_unit_died)
	loop.hp_changed.connect(_on_loop_hp_changed)
	loop.victory.connect(_on_loop_victory)
	loop.timed_out.connect(_on_loop_timed_out)


func _read_current_gambit(unit_idx: int) -> int:
	"""`current_gambit` off the FULL snapshot, not off `_all_states`.

	`_all_states` is the production per-frame snapshot and since W1 it carries only
	GPUCombatPacker.SNAPSHOT_HOT_UNION — the 39 fields the game itself reads. This
	trace is a diagnostic observer, and `current_gambit` is not one of them, so
	reading it off `_all_states` returned the `.get()` DEFAULT of -1 and every
	`gambit_fired_at_slot` assertion in the corpus reported `slot -1 (expected 0)`.
	62 of 82 fixtures went red on exactly that.

	A consumer that wants field-heavy state asks for it — the same move production
	makes via CombatLoop.refresh_all_states_now() for the cinematic edge. The full
	build is served off the simulator's per-version cache, so this costs one rebuild
	per frame in which a trace signal actually fires, and nothing in the game.
	"""
	if unit_idx < 0 or gpu_state_reader == null:
		return -1
	var full: Array = gpu_state_reader.get_all_unit_states()
	if unit_idx >= full.size():
		return -1
	return int(full[unit_idx].get("current_gambit", -1))


func _on_loop_state_changed(unit_idx: int, prev_state: int, new_state: int) -> void:
	if _active_trace == null:
		return
	var cg: int = _read_current_gambit(unit_idx)
	_active_trace.on_state_changed(unit_idx, prev_state, new_state, current_tick, cg)


func _on_loop_cast_began(unit_idx: int, ability_id: int, target: int) -> void:
	if _active_trace == null:
		return
	var cg: int = _read_current_gambit(unit_idx)
	# Diagnose-only sample of the GPU's cooldown_ready_at slot at the moment
	# CAST_BEGAN fires. Lets the cooldown_respected predicate distinguish a
	# real GPU floor violation from a host-frame trace-tick drift (where the
	# GPU correctly respected the 60-tick floor but the cast event was emitted
	# at the end of a multi-tick host frame). Read is per-cast (one SSBO
	# fetch per CAST_BEGAN), so the cost is negligible.
	var cooldown_ready_at: int = -1
	if gpu_simulator and ability_id >= 0:
		cooldown_ready_at = gpu_simulator.get_cooldown_ready_at(0, unit_idx, ability_id)
	_active_trace.on_cast_began(unit_idx, ability_id, target, current_tick, cg, cooldown_ready_at)


func _on_loop_action_committed(unit_idx: int, ability_id: int, target: int) -> void:
	if _active_trace == null:
		return
	var cg: int = _read_current_gambit(unit_idx)
	_active_trace.on_action_committed(unit_idx, ability_id, target, current_tick, cg)


func _on_loop_projectile_fired(unit_idx: int) -> void:
	if _active_trace == null:
		return
	var cg: int = _read_current_gambit(unit_idx)
	_active_trace.on_projectile_fired(unit_idx, current_tick, cg)


func _on_loop_unit_died(unit_idx: int) -> void:
	if _active_trace == null:
		return
	_active_trace.on_unit_died(unit_idx, current_tick)


func _on_loop_hp_changed(unit_idx: int, prev_hp: int, new_hp: int, delta: int) -> void:
	if _active_trace == null:
		return
	_active_trace.on_hp_changed(unit_idx, prev_hp, new_hp, delta, current_tick)


func _on_loop_victory(winner: int, _team0_alive: int, _team1_alive: int) -> void:
	if _active_trace != null:
		_active_trace.on_victory(winner, current_tick)
	_active_done = true


func _on_loop_timed_out(tick: int) -> void:
	if _active_trace != null:
		_active_trace.on_timed_out(tick)
	_active_done = true


# Pump override: the CombatHost base ticks the loop in _process; we also
# snapshot the per-tick gambit/state samples into the trace logger.
func _process(delta: float) -> void:
	super._process(delta)
	if _active_trace != null and combat_loop != null and gpu_state_reader != null:
		# The FULL snapshot, deliberately, not `_all_states`. Since W1 the host's
		# `_all_states` carries only SNAPSHOT_HOT_UNION — the 39 fields the game
		# reads — and snapshot_tick records `current_gambit`, `status_flags_lo`
		# and `status_flags_hi`, none of which are in it. Off `_all_states` those
		# three silently record `.get()` defaults forever. Served off the
		# simulator's per-version cache, so this is one build per host frame.
		# The J-group cinematic_caster_idx field is derived inside snapshot_tick
		# from per-unit U_CINEMATIC_TIMER now (issue #118 retired the battle-
		# header pair), so forwarding _battle_state is just for forwards
		# compatibility if another scalar gets added.
		_active_trace.snapshot_tick(
			current_tick, gpu_state_reader.get_all_unit_states(), combat_loop._battle_state)


# ============================================================================
# Verdict computation
# ============================================================================

func _verdict_for(scenario: Dictionary) -> Dictionary:
	var expectations := GambitAssertions.evaluate(
			scenario.get("expect", {}), _active_trace, _active_team_of)

	# NORAN baseline: current_tick > 0, sim observably ran (a gambit eval
	# committed into an active state OR the per-tick snapshot ring captured
	# frames). A B6 case where slot 0 perpetually fails its cast-position
	# search keeps the unit IDLE forever, so [code]gambit_eval_events[/code]
	# stays zero even though the sim ticked every TICKS_GAMBIT_REEVAL —
	# falling back to [code]per_tick_snapshots[/code] keeps that from being
	# misclassified as "sim never ran." Encoder skips count only where opted
	# in.
	var allow_skips: bool = scenario.get("expect_encoder_skips", false)
	var noran_reasons: Array = []
	if current_tick <= 0:
		noran_reasons.append("current_tick=0")
	if _active_trace.gambit_eval_events <= 0 and _active_trace.per_tick_snapshots.size() <= 0:
		noran_reasons.append("no gambit eval recorded and no per-tick snapshot")
	if _encoder_skip_count > 0 and not allow_skips:
		noran_reasons.append("encoder skipped %d slot(s) without expect_encoder_skips" % _encoder_skip_count)
	# E1-style scenarios opt in: we further confirm the skip happened.
	if allow_skips and _encoder_skip_count == 0:
		expectations.append({
			"ok": false,
			"name": "encoder.skipped_at_least_one",
			"detail": "expect_encoder_skips set but no skip observed"
		})
	if not noran_reasons.is_empty():
		return {"verdict": VERDICT_NORAN, "expectations": expectations + [{
			"ok": false, "name": "baseline.no_ran",
			"detail": ", ".join(noran_reasons)
		}]}

	# XFAIL bookkeeping: matched names in scenario.xfail are expected to fail.
	var xfail_names: Array = scenario.get("xfail", [])
	var any_unxfailed_fail := false
	var any_xfailed_passed := false
	var any_xfailed_failed := false
	for e in expectations:
		var xfailed := xfail_names.has(e["name"])
		if xfailed:
			if e["ok"]:
				any_xfailed_passed = true
			else:
				any_xfailed_failed = true
		else:
			if not e["ok"]:
				any_unxfailed_fail = true

	if any_unxfailed_fail:
		return {"verdict": VERDICT_FAIL, "expectations": expectations}
	if any_xfailed_passed and xpass_treatment == "hard":
		return {"verdict": VERDICT_XPASS, "expectations": expectations}
	if any_xfailed_passed:
		return {"verdict": VERDICT_XPASS, "expectations": expectations}
	if any_xfailed_failed:
		return {"verdict": VERDICT_XFAIL, "expectations": expectations}
	return {"verdict": VERDICT_PASS, "expectations": expectations}


# ============================================================================
# NORAN fixture (internal self-test)
# ============================================================================

func _run_noran_fixture() -> void:
	# Synthetic scenario that never advances: we build a trace with
	# current_tick == 0 and no gambit_eval_events, then evaluate. Verdict
	# must be NORAN. This proves the sentinel is reachable; it is NOT a
	# real scenario in the registry.
	print("\n[fixture/noran_sentinel] starting")
	var name := "noran_sentinel"
	_active_trace = GambitTraceLogger.new(name, _rlog)
	_active_team_of.clear()
	_encoder_skip_count = 0
	# Don't run the sim at all — leave current_tick at 0.
	var fake_scenario := {
		"rule": "fixture",
		"name": name,
		"expect": {"outcome": {"winner": 0}},
	}
	# We need current_tick == 0 — but the host's current_tick forwards to the
	# loop. With no loop, the getter returns 0, so we're already there.
	combat_loop = null
	var verdict_data := _verdict_for(fake_scenario)
	# The fixture passes if-and-only-if the verdict was NORAN.
	var ok: bool = verdict_data["verdict"] == VERDICT_NORAN
	var fixture_verdict := VERDICT_PASS if ok else VERDICT_FAIL
	_scenario_results.append({
		"scenario": fake_scenario,
		"verdict": fixture_verdict,
		"expectations": verdict_data["expectations"] + [{
			"ok": ok, "name": "fixture.noran_sentinel_fired",
			"detail": "got %s (expected NORAN)" % verdict_data["verdict"]
		}],
	})
	_counts[fixture_verdict] = _counts.get(fixture_verdict, 0) + 1
	print("[fixture/noran_sentinel] verdict=%s (raw_verdict_under_test=%s)" % [
		fixture_verdict, verdict_data["verdict"]])


# ============================================================================
# Recording + reporting
# ============================================================================

func _record_verdict(scenario: Dictionary, verdict: String, expectations: Array) -> void:
	_counts[verdict] = _counts.get(verdict, 0) + 1
	_scenario_results.append({
		"scenario": scenario,
		"verdict": verdict,
		"expectations": expectations,
	})
	var rule: String = scenario.get("rule", "??")
	var name: String = scenario.get("name", "<unnamed>")
	print("[%s/%s] verdict=%s" % [rule, name, verdict])
	for e in expectations:
		var mark: String = "ok" if e["ok"] else "FAIL"
		print("  - [%s] %s — %s" % [mark, e["name"], e.get("detail", "")])
	if verdict == VERDICT_XFAIL or verdict == VERDICT_XPASS:
		print("  xfail_reason: %s" % scenario.get("xfail_reason", ""))


func _teardown_battle() -> void:
	if combat_loop:
		combat_loop.queue_free()
		combat_loop = null
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units = []
	team0_units = []
	team1_units = []
	_active_trace = null


func _print_summary() -> void:
	print("\n======================================")
	print("  GambitScenarioRunner SUMMARY")
	print("======================================")
	for r in _scenario_results:
		var s: Dictionary = r["scenario"]
		print("  [%s] %s/%s" % [r["verdict"], s.get("rule", "??"), s.get("name", "?")])
	print("--------------------------------------")
	print("  PASS:  %d" % _counts[VERDICT_PASS])
	print("  FAIL:  %d" % _counts[VERDICT_FAIL])
	print("  XFAIL: %d" % _counts[VERDICT_XFAIL])
	print("  XPASS: %d" % _counts[VERDICT_XPASS])
	print("  ERROR: %d" % _counts[VERDICT_ERROR])
	print("  NORAN: %d" % _counts[VERDICT_NORAN])
	print("======================================")
	# Aggregate verdict for run_all_tests.sh — any FAIL/NORAN/ERROR is red.
	var aggregate_red: int = int(_counts[VERDICT_FAIL]) + int(_counts[VERDICT_NORAN]) + int(_counts[VERDICT_ERROR])
	var aggregate_green: int = int(_counts[VERDICT_PASS]) + int(_counts[VERDICT_XFAIL]) + int(_counts[VERDICT_XPASS])
	if aggregate_red > 0:
		print("[FAIL] GambitScenarioRunner: %d red verdict(s)" % aggregate_red)
	else:
		if not _scenario_filter.is_empty():
			print("[FAIL] GambitScenarioRunner: FILTERED RUN (--only=%s) — %d green, NOT a verdict"
					% [_scenario_filter, aggregate_green])
		else:
			print("[PASS] GambitScenarioRunner: %d scenarios green (XFAIL/XPASS soft)" % aggregate_green)
	# ...and say it on the channel the runner actually reads (#451). The line
	# above was NEVER heard: an XFAIL scenario prints `  - [FAIL] ...` for each
	# quarantined expectation, and the runner's marker rule found those and
	# scored this test FAIL in all five full runs on record — 82 scenarios green,
	# reported red. `[VERDICT]` outranks the markers; see tests/lib/verdict.sh.
	print("[VERDICT] %s" % ("FAIL" if aggregate_red > 0 else "PASS"))

