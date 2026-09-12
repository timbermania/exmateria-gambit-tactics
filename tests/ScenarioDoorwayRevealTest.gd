extends Node
## Integration guard for the scenario-6 doorway visibility fix (the case the pure
## ScenarioUnitVisibilityTest could NOT catch): a PATH-MODE boot spawns the ENTD
## roster once against the group-ROOT chunk (scenario 3 Setup), then walks to
## member scenario 6. The root chunk has no visibility op for Ovelia, so without
## re-deriving visibility from the loaded MEMBER chunk she spawns visible and is
## wrongly on at the doorway. This boots that exact route, parks at PC 115 (the
## doorway "Wait For Instruction"), and asserts Ovelia(0x0C) + Delita(0x05) are
## BOTH hidden — their block Draws (@88/@104) haven't run yet at PC 115.
##
## Depends on the per-scenario chunks (chunks/ is gitignored, regen per-machine);
## SKIPS (loud, green) if scenario 3/6 chunks aren't present locally.
##
## Run: "$GODOT" --path . res://tests/ScenarioDoorwayRevealTest.tscn

## The doorway "Wait For Instruction" this test parks on, in the TARGET member's
## chunk. Used both to ask for the park and to RECOGNISE it — see `_on_post_draw`.
const PARK_PC := 115
const OVELIA := 0x0C
const DELITA := 0x05
const SCN3 := "res://assets/scenarios/chunks/scenario_003_chunk.json"
const SCN6 := "res://assets/scenarios/chunks/scenario_006_chunk.json"

var _scene: Node
var _vm: Node = null
var _f := 0
var _done := false


func _ready() -> void:
	if not FileAccess.file_exists(SCN3) or not FileAccess.file_exists(SCN6):
		print("[skip] scenario 3/6 chunks not present (gitignored) — skipping")
		print("[PASS] ScenarioDoorwayRevealTest (skipped)")
		get_tree().quit(0)
		return
	# Reproduce the user's exact route: path-mode boot to member 6, then the
	# double-click "run to PC 115" park.
	ScenarioDebugSession.path_target_scenario_id = 6
	ScenarioDebugSession.rewind_target_pc = PARK_PC
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _units() -> Dictionary:
	return _scene._units_by_id if _scene and "_units_by_id" in _scene else {}


func _visible(uid: int) -> bool:
	var u = _units().get(uid, null)
	return u != null and u.visible


func _on_post_draw() -> void:
	_f += 1
	if _done:
		return
	if _f > 6000:
		print("[FAIL] ScenarioDoorwayRevealTest: never parked at PC %d (timeout)" % PARK_PC)
		_finish(1)
		return
	if _vm == null:
		if _scene and "_vm" in _scene and _scene._vm != null:
			_vm = _scene._vm
		return
	# `== PARK_PC`, NOT `>= PARK_PC`, and the difference is the whole test.
	#
	# The route is a path walk 3 -> 4 -> 5 -> 6, and ScenarioPathApplier runs every
	# INTERMEDIATE member "to end-of-script", parking at pc == that chunk's size —
	# 140 for scenario_004, 73 for scenario_005. Only the FINAL member is rewound to
	# the requested PC. A `>=` gate therefore fires on scenario_004's end-of-script
	# park while the walk is still on step 1/3, and reads unit visibility out of a
	# scenario this test is only passing through.
	#
	# It passed before `1929f790d` only by accident: the context reaper deleted a
	# dead main, so `get_pc()` fell back to 0 between chunks and the `>=` gate could
	# not fire early. That commit stopped reaping index 0 — correctly; the "am I
	# main?" identity is load-bearing at 13 call sites — so a dead main now reports
	# its frozen end-of-script pc and the latent bug in this gate became visible.
	# The VM is right; this gate was always under-specified.
	if _vm.get_pc() == PARK_PC and not _vm._ff_active and _vm._paused and _f > 60:
		var ovelia_on := _visible(OVELIA)
		var delita_on := _visible(DELITA)
		print("[doorway] PARKED @pc=%d: Delita(5) visible=%s  Ovelia(12) visible=%s"
			% [_vm.get_pc(), str(delita_on), str(ovelia_on)])
		var ok := (not ovelia_on) and (not delita_on)
		if ok:
			print("[PASS] ScenarioDoorwayRevealTest")
			_finish(0)
		else:
			print("[FAIL] ScenarioDoorwayRevealTest: doorway units drawn before their Draw op ran")
			_finish(1)


func _finish(code: int) -> void:
	_done = true
	get_tree().quit(code)
