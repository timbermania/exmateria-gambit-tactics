extends Node
## Integration guard for the scenario-6 doorway-facing regression fix: a hidden-
## but-PRESENT unit must still be a team-broadcast target.
##
## Ovelia (uid 0x0C) is turned by the pc-31 player-team broadcast `Rotate Unit
## [Units=1, Multi=1, Facing=8]`. The chunk-derived visibility fix made her spawn
## HIDDEN (revealed at Draw@104), and the broadcast roster used to filter on
## `.visible` — so she was dropped from the pc-31 rotate and walked out facing the
## wrong way. The fix keys the roster on `scenario_present` (allocated), not render
## visibility, so her always_present slot keeps her a broadcast target while held.
##
## Oracle: after the pc-25..31 setup rotates (all Facing=8 — Agrias 0x34 is rotated
## individually at pc27, Ovelia by the pc31 broadcast), Ovelia's facing_angle must
## equal Agrias's. Pre-fix Ovelia is stuck at her spawn seed (!= Agrias).
##
## Depends on the gitignored scn3/6 chunks; SKIPS (loud, green) if absent.
## Run: "$GODOT" --path . res://tests/ScenarioBroadcastRotateHeldTest.tscn

const OVELIA := 0x0C
const AGRIAS := 0x34
const PARK_PC := 60   # past the pc25-31 Facing=8 rotates, before the doorway blocks (80)
const SCN3 := "res://assets/scenarios/chunks/scenario_003_chunk.json"
const SCN6 := "res://assets/scenarios/chunks/scenario_006_chunk.json"

var _scene: Node
var _vm: Node = null
var _f := 0
var _done := false


func _ready() -> void:
	if not FileAccess.file_exists(SCN3) or not FileAccess.file_exists(SCN6):
		print("[skip] scenario 3/6 chunks not present (gitignored) — skipping")
		print("[PASS] ScenarioBroadcastRotateHeldTest (skipped)")
		get_tree().quit(0)
		return
	ScenarioDebugSession.path_target_scenario_id = 6
	ScenarioDebugSession.rewind_target_pc = PARK_PC
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _units() -> Dictionary:
	return _scene._units_by_id if _scene and "_units_by_id" in _scene else {}


func _facing(uid: int) -> int:
	var u = _units().get(uid, null)
	return -999 if u == null else int(u.facing_angle)


func _on_post_draw() -> void:
	_f += 1
	if _done:
		return
	if _f > 6000:
		print("[FAIL] ScenarioBroadcastRotateHeldTest: never parked at pc %d (timeout)" % PARK_PC)
		_finish(1)
		return
	if _vm == null:
		if _scene and "_vm" in _scene and _scene._vm != null:
			_vm = _scene._vm
		return
	if _vm.get_pc() >= PARK_PC and not _vm._ff_active and _vm._paused and _f > 60:
		var ov := _facing(OVELIA)
		var ag := _facing(AGRIAS)
		print("[rotate] PARKED @pc=%d: Ovelia(0x0C).facing_angle=0x%03X  Agrias(0x34).facing_angle=0x%03X"
			% [_vm.get_pc(), ov, ag])
		if ov == ag and ov != -999:
			print("[PASS] ScenarioBroadcastRotateHeldTest")
			_finish(0)
		else:
			print("[FAIL] ScenarioBroadcastRotateHeldTest: Ovelia not rotated with the player team (held unit dropped from broadcast)")
			_finish(1)


func _finish(code: int) -> void:
	_done = true
	get_tree().quit(code)
