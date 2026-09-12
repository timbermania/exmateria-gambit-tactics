extends Node
## Integration guard for the scenario-6 LATE-ADD visibility fix (sibling of
## ScenarioDoorwayRevealTest). scn6 units 0x01 @ (0,4) and 0x04 @ (0,3) are
## `always_present`=false and are introduced ONLY by a lone {45} Add Draw=0 at
## pc434 — next-scene setup, added with the camera panned away. They must NOT be
## drawn for the bulk of scenario 6.
##
## The bug: the frame-0 static scan revealed them at spawn (independent of the
## runtime Add), so parking anywhere before pc434 showed them ~434 instructions
## early. The fix gates render visibility on PRESENCE (allocated in the sprite
## list), so a not-yet-added unit stays hidden until its {45} Add dispatches.
##
## This boots the exact user route — path-mode to member 6 — parks at PC 382 (the
## user's repro park, well before the pc434 Add), and asserts units 0x01 + 0x04 are
## BOTH hidden. Depends on the gitignored per-scenario chunks; SKIPS (loud, green)
## if scenario 3/6 chunks aren't present locally.
##
## Run: "$GODOT" --path . res://tests/ScenarioLateAddVisibilityTest.tscn

const LATE_A := 0x01   # (0,4)
const LATE_B := 0x04   # (0,3)
const PARK_PC := 382   # the user's repro park; the {45} Add for these is at pc434
const SCN3 := "res://assets/scenarios/chunks/scenario_003_chunk.json"
const SCN6 := "res://assets/scenarios/chunks/scenario_006_chunk.json"

var _scene: Node
var _vm: Node = null
var _f := 0
var _done := false


func _ready() -> void:
	if not FileAccess.file_exists(SCN3) or not FileAccess.file_exists(SCN6):
		print("[skip] scenario 3/6 chunks not present (gitignored) — skipping")
		print("[PASS] ScenarioLateAddVisibilityTest (skipped)")
		get_tree().quit(0)
		return
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
		print("[FAIL] ScenarioLateAddVisibilityTest: never parked at PC %d (timeout)" % PARK_PC)
		_finish(1)
		return
	if _vm == null:
		if _scene and "_vm" in _scene and _scene._vm != null:
			_vm = _scene._vm
		return
	if _vm.get_pc() >= PARK_PC and not _vm._ff_active and _vm._paused and _f > 60:
		var a_on := _visible(LATE_A)
		var b_on := _visible(LATE_B)
		print("[late-add] PARKED @pc=%d: uid 0x01 visible=%s  uid 0x04 visible=%s"
			% [_vm.get_pc(), str(a_on), str(b_on)])
		var ok := (not a_on) and (not b_on)
		if ok:
			print("[PASS] ScenarioLateAddVisibilityTest")
			_finish(0)
		else:
			print("[FAIL] ScenarioLateAddVisibilityTest: late-add units drawn before their pc434 {45} Add ran")
			_finish(1)


func _finish(code: int) -> void:
	_done = true
	get_tree().quit(code)
