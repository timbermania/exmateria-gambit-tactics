extends Node
## Guard for [BattleDeployment] — the control-flag gate that decides, at a battle, whether
## the cast is PREDETERMINED (fixed, no deployment) or the player deploys from the
## formation (GAME_STATE_TRANSITIONS.md §2.6). Verified against the real ENTD records:
## Orbonne 387 (control=3 → predetermined) is the game's singular fixed-cast battle;
## Gariland 388 (control=0 → deploy) is the first roster-fed fight.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/BattleDeploymentTest.tscn

const BattleDeployment = preload("res://src/scenarios/BattleDeployment.gd")
const ENTD_JSON := "res://assets/scenarios/entd.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_orbonne_is_predetermined()
	_test_gariland_needs_deployment()
	_test_empty_record_is_not_predetermined()

	print("\n=== BattleDeploymentTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] BattleDeploymentTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] BattleDeploymentTest"); get_tree().quit(1)
	else:
		print("[PASS] BattleDeploymentTest"); get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want: _passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])

func _true(c: bool, name: String) -> void: _eq(c, true, name)


func _record(idx: int):
	var f := FileAccess.open(ENTD_JSON, FileAccess.READ)
	if f == null: return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed.get("records", {}).get(str(idx), null)


func _test_orbonne_is_predetermined() -> void:
	var rec = _record(387)
	_true(rec != null, "loaded Orbonne ENTD 387")
	if rec == null: return
	_eq(BattleDeployment.control_count(rec), 3, "Orbonne has 3 control units")
	_true(BattleDeployment.is_predetermined(rec), "Orbonne is predetermined (no deployment)")


func _test_gariland_needs_deployment() -> void:
	var rec = _record(388)
	_true(rec != null, "loaded Gariland ENTD 388")
	if rec == null: return
	_eq(BattleDeployment.control_count(rec), 0, "Gariland has 0 control units")
	_true(not BattleDeployment.is_predetermined(rec), "Gariland needs deployment (roster-fed)")


func _test_empty_record_is_not_predetermined() -> void:
	_true(not BattleDeployment.is_predetermined(null), "null record → not predetermined (safe)")
	_eq(BattleDeployment.control_count({"slots": []}), 0, "no slots → 0 control")
