extends Node
## Pure-logic guard for the generalized battle COMPOSITION policy (wayfinder #234 A2):
## `EntdBattle.team_of(team_color)` (the named binary team policy — the single reopen
## hook for any future N-faction work) and `EntdBattle.compose_teams(deployed_owned,
## entd_slots)` which folds deployed player units into the ENTD partition:
##   team0 = deployed_owned  ∪  ENTD-blue
##   team1 = ENTD-non-blue
## Orbonne is the DEGENERATE case (deployed_owned empty → the baked ENTD-blue cast,
## unchanged). CombatLoop is hard 2-team, so this is the whole side split.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/EntdBattleComposeTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_team_of_is_binary_blue_vs_rest()
	_test_compose_folds_deployed_into_team0()
	_test_compose_orbonne_degenerate_empty_deployed()
	_test_compose_skips_empty_slots()

	print("\n=== EntdBattleComposeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] EntdBattleComposeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] EntdBattleComposeTest")
		get_tree().quit(1)
	else:
		print("[PASS] EntdBattleComposeTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _slot(uid: int, team_color: int) -> Dictionary:
	return {"unit_id": uid, "team_color": team_color}


# --- A2a: team_of collapses every non-Blue color to team1 (binary engine boundary) ---
func _test_team_of_is_binary_blue_vs_rest() -> void:
	_eq(EntdBattle.team_of(0), 0, "team_of(Blue)=team0")
	_eq(EntdBattle.team_of(1), 1, "team_of(Red)=team1")
	_eq(EntdBattle.team_of(2), 1, "team_of(Green)=team1 (collapsed)")
	_eq(EntdBattle.team_of(3), 1, "team_of(LightBlue)=team1 (collapsed)")


# --- A2b: deployed player units join team0, ahead of the ENTD-blue guests ---
func _test_compose_folds_deployed_into_team0() -> void:
	var deployed := ["ramza_unit", "g1_unit"]
	var blue := _slot(0x04, 0)          # Delita (guest)
	var red1 := _slot(0x80, 1)
	var red2 := _slot(0x81, 1)
	var out := EntdBattle.compose_teams(deployed, [blue, red1, red2])
	# team0 = deployed (first, in order) then the ENTD-blue slots.
	_eq(out["team0"], ["ramza_unit", "g1_unit", blue], "team0 = deployed ∪ ENTD-blue")
	_eq(out["team1"], [red1, red2], "team1 = ENTD-non-blue")


# --- A2c: Orbonne — empty deployed_owned yields the baked ENTD-blue cast, unchanged ---
func _test_compose_orbonne_degenerate_empty_deployed() -> void:
	var b1 := _slot(0x01, 0)
	var b2 := _slot(0x02, 0)
	var red := _slot(0x80, 1)
	var out := EntdBattle.compose_teams([], [b1, b2, red])
	_eq(out["team0"], [b1, b2], "empty deployed → team0 is the ENTD-blue cast")
	_eq(out["team1"], [red], "team1 unchanged")


# --- A2d: empty ENTD slots (0xFF) are dropped from both sides ---
func _test_compose_skips_empty_slots() -> void:
	var blue := _slot(0x04, 0)
	var empty := _slot(0xFF, 0)
	var red := _slot(0x80, 1)
	var out := EntdBattle.compose_teams([], [blue, empty, red])
	_eq(out["team0"], [blue], "empty slot not in team0")
	_eq(out["team1"], [red], "empty slot not in team1")
