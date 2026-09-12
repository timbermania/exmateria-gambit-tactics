extends Node
# test-kind: gpu
# seeded-break: revert `NavigatorMain._go_live` to arm `_pending_gambits` unchanged (ARM A reds), or drop the `_gambits_dirty` write in `_set_combat_live` (ARM C reds).
## Does a gambit edit made on the NAVIGATOR host ever reach the kernel?
##
## The user's report: on the navigator's Gariland battle they set a row to
## `ThrowStone / Nearest Foe / Always` and the unit "ran up and attacked anyway" —
## which is exactly ADR-0048's injected safety net, i.e. the unit fell through every
## authored slot to the net.
##
## This reads the GAMBIT SSBO (`snapshot_battle()["gambits"]`), not the Character that
## was just written, because the whole question is whether the two agree.
##
## Run: godot --path . res://tests/NavigatorGambitEditCrossingTest.tscn

const SKIP_SLUG := "navigator.skip_pre_battle"
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"
## The walk's budget to reach the Deployment park, in FRAMES and not milliseconds
## (charter clauses 6 and 14: a verdict may not be a function of how busy the box was).
## MEASURED: the park lands at frame 32 on an idle box at `SIM_TIME_SCALE`, so this is ~37x
## headroom. A frame budget is stable under load in a way the 180 s one it replaces was not,
## and it is stable in the FORGIVING direction: `Engine.time_scale` scales the sim by the
## frame's delta, so a loaded box takes a LONGER step each frame and reaches the park in
## FEWER frames, not more. Exhausting it prints a TIMEOUT verdict, which is a result — the
## runner passes no `--quit-after`, so the alternative is a 360 s kill scored HUNG.
const PARK_FRAME_BUDGET := 1200
const SIM_TIME_SCALE := 40.0

## ThrowStone — the ability the user authored. id 148, mp_cost 0, range 4.
const THROW_STONE := 148

const GambitClass = ExMateriaAlmanac.Gambit

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _frames: int = 0
var _done: bool = false


func _ready() -> void:
	var action_index := _gariland_opener_index()
	if action_index < 0:
		print("  [FAIL] could not locate Gariland opener action in the plan")
		_failed += 1
		_finish()
		return
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = action_index

	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, false)
	Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(STOP_ON_TURN_SLUG, false)

	Engine.time_scale = SIM_TIME_SCALE

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)

	var parked := await AwaitUntil.frames(self,
		func(): _frames += 1; return _nav != null and bool(_nav._pre_battle_active),
		PARK_FRAME_BUDGET)
	if not parked:
		print("  [TIMEOUT] the walk did not park in Deployment within %d frames"
			% PARK_FRAME_BUDGET)
		_failed += 1
		_finish()
		return
	print("  [note] the walk parked in Deployment at frame %d of %d"
		% [_frames, PARK_FRAME_BUDGET])
	_run()


func _run() -> void:
	var loop = _nav._combat_loop
	if loop == null:
		_true(false, "a CombatLoop exists at the Deployment park")
		_finish()
		return

	var deployed: Array = _nav._deployed_owned
	if deployed.is_empty() or not is_instance_valid(deployed[0]):
		_true(false, "at least one owned unit was deployed")
		_finish()
		return
	var unit = deployed[0]
	var idx: int = loop.units.find(unit)
	_true(idx >= 0, "the edited unit is in the loop's unit array (idx=%d)" % idx)
	if idx < 0:
		_finish()
		return

	# THE EDIT — exactly what `GambitSurface`'s ability row writes (`src/ui3/detail/
	# GambitSurface.gd:648`): `action_kind = ABILITY`, `ability_id = <aid>`, on the row
	# object already in the list. Nothing else; if that is not sufficient, that IS the bug.
	var character = FormationMapHost.character_for_unit(unit)
	_true(character != null, "the deployed unit carries a Character")
	if character == null or character.gambits == null:
		_finish()
		return
	var row = character.gambits.get_at(0)
	_true(row != null, "the Character has a slot 0 to author")
	if row == null:
		_finish()
		return
	row.action_kind = GambitClass.ActionKind.ABILITY
	row.ability_id = THROW_STONE

	# Same object? (the handoff eliminated this, but a zero with no control is not a zero)
	_true(unit.gambit_list == character.gambits,
		"the Unit's gambit_list IS the Character's list (the edit is visible to the encoder)")
	_true(not row.is_empty(), "the authored row is non-empty, so the encoder will not skip it")

	# Go live — the navigator's only gambit->GPU push (`_go_live` -> `arm_combat_gambits`).
	_nav._start_battle()
	call_deferred("_assert_after_go_live", idx, unit)


func _assert_after_go_live(idx: int, unit) -> void:
	var loop = _nav._combat_loop
	var waited := 0
	while waited < 240:
		loop = _nav._combat_loop
		if loop != null and bool(loop.combat_active) and bool(_nav._combat_active):
			break
		await get_tree().process_frame
		waited += 1
	_true(loop != null and bool(loop.combat_active), "the battle went live")
	# The 40x clock existed to reach the Deployment park quickly. ARM C needs a battle that is
	# still RUNNING several frames from now, and at 40x Gariland resolves and tears the loop down
	# inside the pump below — which is not a failure of the crossing, it is the probe outliving
	# its subject.
	Engine.time_scale = 1.0

	# ARM A — THE BUG. The edit is on the Character; is it on the GPU?
	var found_a := _rows_carry_ability(idx)
	_true(found_a, "ARM A: after go-live the unit's GPU gambit rows carry ThrowStone (id %d)"
		% THROW_STONE)

	# ARM B — THE POSITIVE CONTROL. Push the same edit through the pusher the arena host
	# uses, and re-read with the SAME instrument. If this is also absent the probe is blind
	# and ARM A's zero means nothing.
	loop.gpu_simulator.set_unit_gambits(0, idx, GambitEncoder.encode_for_unit(unit))
	var found_b := _rows_carry_ability(idx)
	_true(found_b, "ARM B (control): after an explicit set_unit_gambits the SAME read finds it")

	await _assert_mid_battle_edit()
	_finish()


## ARM C — THE USER'S ACTUAL ROUTE. Mid-battle, on a SECOND unit, through the two edges the
## formation screen really drives: it freezes the sim while it is up (`_set_screen_pause(true)`)
## and restores it on close (`_set_screen_pause(false)`).
##
## A second unit and not the one ARM A edited, so a pass here cannot be ARM A's write still
## sitting in the buffer — and the NEGATIVE control below (absent while the screen is still up)
## is what says the crossing is the CLOSE and not something that happened earlier.
func _assert_mid_battle_edit() -> void:
	var loop = _nav._combat_loop
	var deployed: Array = _nav._deployed_owned
	if deployed.size() < 2 or not is_instance_valid(deployed[1]):
		_true(false, "ARM C: a second owned unit was deployed to edit mid-battle")
		return
	var unit2 = deployed[1]
	var idx2: int = loop.units.find(unit2)
	_true(idx2 >= 0, "ARM C: the second unit is in the loop's unit array (idx=%d)" % idx2)
	if idx2 < 0:
		return

	# Let the live battle actually run first — an edit that crosses only because nothing had
	# started yet would be ARM A again under another name.
	for _i in range(10):
		await get_tree().process_frame
	if _nav._combat_loop == null or not is_instance_valid(_nav._combat_loop) \
			or not bool(_nav._combat_loop.combat_active):
		_true(false, "ARM C: the battle is still live after a short pump (nothing to edit into)")
		return

	# The screen opens: the host freezes the sim under it.
	_nav._set_screen_pause(true)
	var character2 = FormationMapHost.character_for_unit(unit2)
	if character2 == null or character2.gambits == null:
		_true(false, "ARM C: the second unit carries a Character with a gambit list")
		return
	var row2 = character2.gambits.get_at(0)
	row2.action_kind = GambitClass.ActionKind.ABILITY
	row2.ability_id = THROW_STONE

	# The real screen is up for many frames before it closes, so let some pass. (The host must
	# not DEPEND on that — see `NavigatorMain._gambits_dirty` — but the faithful route does.)
	for _i in range(3):
		await get_tree().process_frame

	# NEGATIVE CONTROL — with the screen still up, the edit is on the Character and must NOT
	# yet be in the kernel. If this is already true the arm below proves nothing.
	_true(not _rows_carry_ability(idx2),
		"ARM C (control): with the screen still open the edit has NOT crossed yet")

	# The screen closes: the host un-freezes, which is the edge that re-arms.
	_nav._set_screen_pause(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_true(_rows_carry_ability(idx2),
		"ARM C: a MID-BATTLE edit crosses to the kernel when the screen closes")


## Does the unit's slice of the gambit SSBO carry an ABILITY row for ThrowStone?
func _rows_carry_ability(idx: int) -> bool:
	# A torn-down loop reads exactly like "the row is absent", and that is how ARM C's negative
	# control passed for the wrong reason on the first run. Count it as a probe failure instead.
	var loop = _nav._combat_loop
	if loop == null or not is_instance_valid(loop) or loop.gpu_simulator == null:
		_true(false, "  [probe] the CombatLoop is gone — this read means NOTHING")
		return false
	var snap: Dictionary = loop.gpu_simulator.snapshot_battle(0)
	var slice: PackedInt32Array = snap.get("gambits", PackedInt32Array())
	if slice.is_empty():
		print("  [note] the gambit slice came back EMPTY — the instrument may be blind")
		return false
	var rows: PackedInt32Array = RolloutCandidates.unit_rows(slice, idx)
	var report: Array = []
	for r in range(GPUConstants.MAX_GAMBITS):
		var base := r * GPUConstants.GAMBIT_SIZE
		var enabled := rows[base + GPUCombatPacker.GambitField.ENABLED]
		var atype := rows[base + GPUCombatPacker.GambitField.ACTION_TYPE]
		var aid := rows[base + GPUCombatPacker.GambitField.ACTION_ID]
		report.append("slot%d(en=%d type=%d id=%d)" % [r, enabled, atype, aid])
	print("  [rows] unit %d: %s" % [idx, " ".join(report)])
	for r in range(GPUConstants.MAX_GAMBITS):
		var base := r * GPUConstants.GAMBIT_SIZE
		if rows[base + GPUCombatPacker.GambitField.ACTION_TYPE] == GPUConstants.ACTION_SPELL \
				and rows[base + GPUCombatPacker.GambitField.ACTION_ID] == THROW_STONE:
			return true
	return false


func _gariland_opener_index() -> int:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "opener" and int(a.get("beat", {}).get("scenario_id", -1)) == 10:
			return i
	return -1


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	Tune.clear(SKIP_SLUG)
	print("\n=== NavigatorGambitEditCrossingTest: %d passed, %d failed (%d frames to the park) ==="
		% [_passed, _failed, _frames])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorGambitEditCrossingTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorGambitEditCrossingTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorGambitEditCrossingTest")
		get_tree().quit(0)
