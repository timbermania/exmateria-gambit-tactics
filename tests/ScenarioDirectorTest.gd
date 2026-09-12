extends Node
## Unit tests for ScenarioDirector — the BattleConditionals interpreter (FFT's battle
## "director"). Exercises the evaluator against the REAL committed artifact
## (assets/scenarios/battle_conditionals.json) with a hand-set stub state, proving the
## story-branch logic: Orbonne's deploy/chat/victory chain, and Mandalia's menu-choice
## and Algus-alive-vs-KO'd victory branches. No VM, no scene, no combat engine.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioDirectorTest.tscn

var _passed: int = 0
var _failed: int = 0

# ENTD unit ids referenced by the guards under test.
const ORBONNE_AGRIAS := 23   # 0x17
const ORBONNE_GAFGARION := 52 # 0x34
const MANDALIA_ALGUS := 7     # unit 7


## Stub state: everything false/zero unless explicitly set. Mirrors the "empty world"
## base, with setters so a test can pin exactly the guards it means to exercise.
class StubState extends ScenarioDirectorState:
	var vars: Dictionary = {}
	var present: Dictionary = {}
	var hp: Dictionary = {}
	var active: Dictionary = {}
	var victory: bool = false
	var cur_date: Array = [0, 0]
	var locations: Dictionary = {}

	func get_variable(id: int) -> int:
		return int(vars.get(id, 0))

	func unit_present(unit_id: int) -> bool:
		return bool(present.get(unit_id, false))

	func unit_hp(unit_id: int) -> int:
		return int(hp.get(unit_id, 0))

	func is_active_turn(unit_id: int) -> bool:
		return bool(active.get(unit_id, false))

	func is_victory() -> bool:
		return victory

	func date() -> Array:
		return cur_date

	func unit_location(unit_id: int) -> Array:
		return locations.get(unit_id, [])


func _ready() -> void:
	_test_orbonne_deploy()
	_test_orbonne_midbattle_chat()
	_test_orbonne_victory()
	_test_mandalia_menu_choice()
	_test_mandalia_victory_algus_alive()
	_test_mandalia_victory_algus_koed()
	_test_no_condition_matches_empty_state()
	_test_unknown_set_returns_none()
	_test_edges_view()
	_test_date_polarity_follows_the_rom()
	_test_unit_location_layer_is_a_bit()

	print("\n=== ScenarioDirectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioDirectorTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioDirectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioDirectorTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- Orbonne (bc_id 1): deploy(4) → mid-battle chat(5) → victory abduction(6) ---

func _test_orbonne_deploy() -> void:
	# cond0 requires var 509 (deploy done) == 1 → Run Scenario 4.
	var s := StubState.new()
	s.vars[509] = 1
	var d := ScenarioDirector.new(s)
	_eq(d.next_scenario(1), 4, "orbonne deploy → 4")


func _test_orbonne_midbattle_chat() -> void:
	# cond0 must fail (var 509 != 1) so cond1 can win: both leads present, alive,
	# Agrias's active turn, latches clear.
	var s := StubState.new()
	s.vars[509] = 0
	s.vars[127] = 0
	s.vars[128] = 0
	s.present[ORBONNE_AGRIAS] = true
	s.present[ORBONNE_GAFGARION] = true
	s.active[ORBONNE_AGRIAS] = true
	s.hp[ORBONNE_AGRIAS] = 100
	s.hp[ORBONNE_GAFGARION] = 100
	var d := ScenarioDirector.new(s)
	_eq(d.next_scenario(1), 5, "orbonne mid-battle chat → 5")


func _test_orbonne_victory() -> void:
	# cond2 = var 128 == 0 AND Victory → Run Scenario 6. cond0/cond1 fail.
	var s := StubState.new()
	s.vars[128] = 0
	s.victory = true
	var d := ScenarioDirector.new(s)
	_eq(d.next_scenario(1), 6, "orbonne victory abduction → 6")


# --- Mandalia (bc_id 5): the menu-choice + Algus-HP branches ---

func _test_mandalia_menu_choice() -> void:
	# Options phase (var 125 == 0). Menu choice lives in var 150: 0 = Destroy Corps
	# (→17), 1 = Save Algus (→18). Deploy latch var 509 = 0 so cond0 (→16) is skipped.
	var destroy := StubState.new()
	destroy.vars[509] = 0
	destroy.vars[125] = 0
	destroy.vars[150] = 0
	_eq(ScenarioDirector.new(destroy).next_scenario(5), 17, "mandalia destroy chosen → 17")

	var save := StubState.new()
	save.vars[509] = 0
	save.vars[125] = 0
	save.vars[150] = 1
	_eq(ScenarioDirector.new(save).next_scenario(5), 18, "mandalia save chosen → 18")


func _test_mandalia_victory_algus_alive() -> void:
	# Battle active (var 125 == 1), victory reached, Algus present and alive → cond7
	# (Run 23). The mid-battle KO conds fail because Algus HP >= 1.
	var s := StubState.new()
	s.vars[125] = 1
	s.vars[128] = 0
	s.victory = true
	s.present[MANDALIA_ALGUS] = true
	s.hp[MANDALIA_ALGUS] = 42
	var d := ScenarioDirector.new(s)
	_eq(d.next_scenario(5), 23, "mandalia victory, Algus alive → 23")


func _test_mandalia_victory_algus_koed() -> void:
	# Algus KO'd at victory. The mid-battle KO cutscenes (cond3/4/5, Run 19/20/21) are
	# one-shot: their latches (var 126/127/150 guards) are consumed, so evaluation
	# falls through to cond6 (Run 22, "Victory, Algus KO'd").
	var s := StubState.new()
	s.vars[125] = 1
	s.vars[126] = 1   # cond3 active-turn cutscene consumed
	s.vars[127] = 1   # cond4 (Destroy KO cutscene) consumed
	s.vars[128] = 0
	s.vars[150] = 0   # Destroy was chosen; cond5 (Save) needs 150 == 1
	s.victory = true
	s.present[MANDALIA_ALGUS] = true
	s.hp[MANDALIA_ALGUS] = 0
	var d := ScenarioDirector.new(s)
	_eq(d.next_scenario(5), 22, "mandalia victory, Algus KO'd → 22")


# --- Evaluator contract ---

func _test_no_condition_matches_empty_state() -> void:
	# Orbonne (bc 1) fires only on the deploy latch (var 509), live leads, OR victory —
	# none true in an empty world, so nothing advances. (Note bc 5 is NOT a valid
	# no-match probe: its var==0 menu guards ARE satisfied by all-zero defaults, which
	# is faithful — FFT variables init to 0 and are set by the scenario scripts.)
	var d := ScenarioDirector.new(StubState.new())
	_eq(d.next_scenario(1), ScenarioDirector.NONE, "orbonne empty state → NONE")


func _test_unknown_set_returns_none() -> void:
	var d := ScenarioDirector.new(StubState.new())
	_eq(d.next_scenario(99999), ScenarioDirector.NONE, "unknown bc_id → NONE")
	_eq(d.next_scenario(0), ScenarioDirector.NONE, "stub set bc_id 0 → NONE")


func _test_edges_view() -> void:
	# Static graph view: Mandalia has 8 outgoing edges; describe_guard is non-empty.
	var d := ScenarioDirector.new(StubState.new())
	var edges := d.edges(5)
	_eq(edges.size(), 8, "mandalia edge count = 8")
	var targets: Array = []
	for e in edges:
		targets.append(e["target"])
	_eq(targets, [16, 17, 18, 19, 20, 21, 22, 23], "mandalia edge targets in order")
	_eq(
		ScenarioDirector.describe_guard([]),
		"(unconditional)",
		"empty guard string",
	)


# --- ROM-grounded opcode semantics (WITHIN_GROUP_MEMBER_TRANSITION.md §7.5) ---
#
# 0x0010 / 0x0011 and 0x0018's Z operand are driven through _requirement_holds
# directly rather than through a real set, because NEITHER date opcode appears
# anywhere in the 146 shipped BattleConditionals sets and every 0x0018 use has Z = 0.
# There is no data to drive them with, and "no data" is exactly how a swapped
# comparison survives unnoticed.

func _req(opcode: int, values: Array) -> Dictionary:
	var params: Array = []
	for v in values:
		params.append({"value": int(v)})
	return {"opcode": opcode, "params": params}


func _test_date_polarity_follows_the_rom() -> void:
	# bc_predicate 0x0010 (BATTLE.BIN 0x8014295C) returns TRUE the moment
	# var 0x2E < Month -- i.e. the CURRENT date is at or before (Month, Day).
	# The catalog names it "Date >=", which is backwards; the director follows the ROM.
	var s := StubState.new()
	var d := ScenarioDirector.new(s)
	var early := _req(BattleConditionalOpcode.DATE_GE, [5, 10, 0])   # 0x0010
	var late := _req(BattleConditionalOpcode.DATE_LE, [5, 10, 0])    # 0x0011

	s.cur_date = [3, 1]                                             # before (5, 10)
	_eq(d._requirement_holds(early), true, "0x0010 true when current date is earlier")
	_eq(d._requirement_holds(late), false, "0x0011 false when current date is earlier")

	s.cur_date = [9, 1]                                             # after (5, 10)
	_eq(d._requirement_holds(early), false, "0x0010 false when current date is later")
	_eq(d._requirement_holds(late), true, "0x0011 true when current date is later")

	s.cur_date = [5, 10]                                            # exactly equal
	_eq(d._requirement_holds(early), true, "0x0010 true on the exact date")
	_eq(d._requirement_holds(late), true, "0x0011 true on the exact date")

	# The day half only decides when the months tie -- the ROM compares lexicographically.
	s.cur_date = [5, 20]
	_eq(d._requirement_holds(early), false, "0x0010 false when same month, later day")
	_eq(d._requirement_holds(late), true, "0x0011 true when same month, later day")


func _test_unit_location_layer_is_a_bit() -> void:
	# 0x0018's third operand is bit 15 of the halfword at unit+0x48, an upper/lower
	# tile flag -- not a height. The state contract is [x, y, layer] with layer in 0/1.
	var s := StubState.new()
	var d := ScenarioDirector.new(s)
	s.locations[7] = [4, 9, 0]
	_eq(d._requirement_holds(_req(BattleConditionalOpcode.UNIT_LOCATION, [7, 4, 9, 0])),
		true, "0x0018 matches x/y/layer")
	_eq(d._requirement_holds(_req(BattleConditionalOpcode.UNIT_LOCATION, [7, 4, 9, 1])),
		false, "0x0018 rejects the other layer")
