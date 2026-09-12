extends "res://src/scenes/GPUArena.gd"

## GPU snapshot-union coverage test — the runtime half of W1's defence.
##
## The per-frame combat path takes GPUBatchSimulator.get_battle_unit_states_hot(),
## which builds 39 of the record's 101 fields instead of all of them
## (GPUCombatPacker.SNAPSHOT_HOT_UNION). That trade's failure mode is SILENT: a
## consumer reading a field the union omits gets `state.get("x", default)` — the
## default, quietly, no error, no crash, just a battle that behaves slightly wrong
## forever.
##
## This makes that failure LOUD. With `debug_poison_non_union` set, the per-frame
## snapshot carries all 101 keys, but every key OUTSIDE the union holds
## POISON_VALUE (-999,777,333) instead of its real value. Union reads are
## untouched, so a battle that reads nothing else is unaffected — and a battle
## that reads anything else gets an absurd number where a plausible one used to
## be, and diverges.
##
## PASS: 1800 ticks of a real battle with every non-union field poisoned, and no
##       poisoned value ever reaches a Unit's CPU-mirrored stats or a visual
##       position — the two observable outputs of the per-frame consumers.
## FAIL: a poisoned value lands in either — i.e. some per-frame consumer read a
##       field the union omits. That is not hypothetical: this test is how the
##       five STAT_FIELDS reads were found, after both a hand census and the
##       static guard had passed the union as complete (R22/F25).
##
## ⚠ WHAT THIS DOES AND DOES NOT PROVE. It exercises the union through the REAL
## consumers, which is what the static guard cannot do. It only covers the code
## paths this seed actually reaches — an ability, reaction or cinematic that never
## fires here is never checked. MEASURED on this seed: movement, melee, damage,
## casting, stat reads and visual updates all run; NO unit dies inside 1800 ticks
## (HP falls from 40 to 15-31 and holds), so `_apply_death` and `_handle_revives`
## are covered by the static guard ALONE. A seed that resolves would be a strictly
## better fixture — if you find one, take it. tools/check_snapshot_union.py is the
## arm that covers the code rather than the run; neither is sufficient alone.
##
## Run headful (never --headless):
##   godot --path . tests/GPUSnapshotUnionTest.tscn

# Same seed as GPUTeleportTest — a battle already known to run a full engagement
# with movement, melee and projectiles. It does NOT reach a death inside
# CHECK_TICKS; see the coverage note above.
const UNION_SEED: int = 3601067600983631927
const CHECK_TICKS: int = 1800

# No hardcoded golden outcome on purpose. `_check_state_changes()` runs once per
# FRAME against the newest snapshot, so how many ticks elapse between two of its
# runs depends on frame pacing — which makes an exact per-tick event trace or a
# final-HP literal flaky by construction, on a suite that already reds under load.
# The pass criterion below is pacing-independent instead: a poisoned value is nine
# digits of nonsense, so it cannot reach a Unit's stats without being read.
var _test_done: bool = false
var _poison_armed: bool = false
var _poison_reached_stats: Array = []
var _poison_reached_visuals: Array = []


func _ready():
	DebugConfig.combat_seed = UNION_SEED
	DebugConfig.combat_autostart = true
	regression_logging = false
	max_ticks = CHECK_TICKS

	super._ready()
	# The simulator is NOT up yet here — CombatHost._sync_loop_refs() adopts it from
	# the loop later, so `gpu_simulator` is still null at this point. Poisoning is
	# armed lazily in _process, on the first frame the reference exists.


func get_test_name() -> String:
	return "GPU Snapshot Union Test"


func _process(delta):
	super._process(delta)

	if _test_done:
		return

	# Arm through the LOOP, not the host: CombatHost.gpu_simulator is adopted by
	# _sync_loop_refs() only once start_battle runs, i.e. after the whole strategy
	# march. combat_loop.gpu_simulator exists as soon as setup_gpu_simulator() has
	# run, so this poisons the very first snapshot any consumer sees.
	if not _poison_armed and combat_loop and combat_loop.gpu_simulator:
		combat_loop.gpu_simulator.debug_poison_non_union = true
		_poison_armed = true
		print("[union] armed at tick %d — every non-union field now reads %d" % [
			current_tick, GPUBatchSimulator.POISON_VALUE])

	# A poisoned value reaching a Unit's CPU-mirrored stats is the loudest
	# possible symptom: it means an _apply_* handler read outside the union.
	if combat_active:
		_check_stats_uncontaminated()
		_check_visuals_uncontaminated()

	if victory_achieved or current_tick >= CHECK_TICKS:
		_finish_test()


func _check_stats_uncontaminated() -> void:
	for i in range(units.size()):
		var u = units[i]
		if not is_instance_valid(u) or u.unit_stats == null:
			continue
		var hp: int = u.unit_stats.current_hp
		var mp: int = u.unit_stats.current_mp
		if hp < -1000 or mp < -1000:
			var name_i: String = u.name
			if not _poison_reached_stats.any(func(e): return e["unit"] == name_i):
				_poison_reached_stats.append({
					"unit": name_i, "tick": current_tick, "hp": hp, "mp": mp,
				})


func _check_visuals_uncontaminated() -> void:
	"""The visual bridge is the other big per-frame consumer, and it never touches
	unit stats — a poisoned field reaching it shows up as a unit standing a hundred
	million tiles away, not as bad HP. The map is ~40 tiles across; anything past
	10 000 is a poisoned number that got as far as a position."""
	if _visual_bridge == null:
		return
	for i in _visual_bridge.visual_positions:
		var p: Vector3 = _visual_bridge.visual_positions[i]
		if absf(p.x) < 10000.0 and absf(p.y) < 10000.0 and absf(p.z) < 10000.0:
			continue
		var name_i: String = units[i].name if i < units.size() else "Unit%d" % i
		if not _poison_reached_visuals.any(func(e): return e["unit"] == name_i):
			_poison_reached_visuals.append({
				"unit": name_i, "tick": current_tick, "pos": p,
			})


func _finish_test():
	_test_done = true

	var dead: Array = []
	var final_hp: Array = []
	for i in range(units.size()):
		var u = units[i]
		if is_instance_valid(u) and u.unit_stats != null:
			dead.append(u.unit_stats.current_hp <= 0)
			final_hp.append(u.unit_stats.current_hp)

	# A run that never armed proves nothing — do not let it print PASS.
	var passed: bool = _poison_armed \
		and _poison_reached_stats.is_empty() \
		and _poison_reached_visuals.is_empty()
	if not _poison_armed:
		print("[FAIL] poisoning was never armed — gpu_simulator stayed null, so this")
		print("       run exercised nothing. The test is broken, not the union.")

	print("\n=== %s ===" % get_test_name())
	print("[union] seed %d, %d ticks, %d units" % [UNION_SEED, current_tick, units.size()])
	print("[union] final hp: %s" % str(final_hp))
	print("[union] dead:     %s" % str(dead))

	if passed:
		print("[PASS] %d ticks with every non-union field poisoned: no poisoned value reached any unit's stats or visual position" % current_tick)
	else:
		print("[FAIL] a poisoned (non-union) field was read on the per-frame path:")
		for e in _poison_reached_stats:
			print("  T%d: %s reached unit stats — hp=%d mp=%d" % [e["tick"], e["unit"], e["hp"], e["mp"]])
		for e in _poison_reached_visuals:
			print("  T%d: %s reached a visual position — %s" % [e["tick"], e["unit"], str(e["pos"])])
		print("  Add the field to GPUCombatPacker.SNAPSHOT_HOT_UNION, or move the read")
		print("  off the per-frame path onto the full get_all_unit_states().")

	if combat_loop and combat_loop.gpu_simulator:
		combat_loop.gpu_simulator.debug_poison_non_union = false
	DebugConfig.combat_seed = 0
	DebugConfig.combat_autostart = false

	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
