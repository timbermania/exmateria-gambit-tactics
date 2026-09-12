extends Node
## Unit tests for ScenarioPath — the pure debug-navigation planner (no scene, no
## VM, no combat engine). A [Path] is the ordered route of [scenario group] members
## walked to reach a target scenario without a live battle: boot the group root
## once, then per step force the minimal [ForcedDirectorState] that advances the
## [ScenarioDirector] to the next member.
##
## The whole point of the pure planner is that it is headless-testable: we plan a
## route against the REAL committed BattleConditionals artifact
## (assets/scenarios/battle_conditionals.json) and assert both the synthesized
## forced states AND that they actually drive the director to each member — proving
## the guard-synthesizer inverts each opcode correctly and that first-match-wins is
## respected (the preemption case).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioPathTest.tscn

var _passed: int = 0
var _failed: int = 0

# Orbonne group, bc_id 1 (map 56 / entd 387): members 3(setup),4,5,6.
const ORBONNE_BC := 1
const ORBONNE_AGRIAS := 23    # 0x17
const ORBONNE_GAFGARION := 52 # 0x34


func _ready() -> void:
	_test_plan_orbonne_to_5_shape()
	_test_plan_step_forced_states_drive_director()
	_test_plan_step1_forced_state_contents()
	_test_plan_step2_forced_state_contents()
	_test_preemption_reported()
	_test_plan_to_setup_root_is_empty()
	_test_synthesizer_inverts_each_opcode()

	print("\n=== ScenarioPathTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioPathTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioPathTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioPathTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _ok(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# --- Canonical: plan(1, 5) → 2 steps [ (4, {Var509=1}), (5, {...}) ] ---

func _test_plan_orbonne_to_5_shape() -> void:
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 5)
	_eq(steps.size(), 2, "plan(1,5) has 2 steps")
	if steps.size() != 2:
		return
	_eq(int(steps[0]["member_scenario_id"]), 4, "step0 member = 4")
	_eq(int(steps[1]["member_scenario_id"]), 5, "step1 member = 5")
	_ok(steps[0]["forced_state"] is ScenarioDirectorState, "step0 forced_state is a DirectorState")
	_ok(steps[1]["forced_state"] is ScenarioDirectorState, "step1 forced_state is a DirectorState")


func _test_plan_step_forced_states_drive_director() -> void:
	# Applying each step's forced state to a fresh director must return that member.
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 5)
	if steps.size() != 2:
		_eq(false, true, "plan(1,5) shape prerequisite")
		return
	var d0 := ScenarioDirector.new(steps[0]["forced_state"])
	_eq(d0.next_scenario(ORBONNE_BC), 4, "step0 forced state → director returns 4")
	var d1 := ScenarioDirector.new(steps[1]["forced_state"])
	_eq(d1.next_scenario(ORBONNE_BC), 5, "step1 forced state → director returns 5")
	# The planner verifies each step itself; no preemption on the clean route.
	_ok(bool(steps[0]["verified"]), "step0 verified")
	_ok(bool(steps[1]["verified"]), "step1 verified")
	_eq(int(steps[0]["preempted_by"]), ScenarioDirector.NONE, "step0 no preemption")
	_eq(int(steps[1]["preempted_by"]), ScenarioDirector.NONE, "step1 no preemption")


func _test_plan_step1_forced_state_contents() -> void:
	# Step to member 4: cond0 is Variable ==(509, 1) → forced Var509 = 1, nothing else.
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 5)
	if steps.size() != 2:
		return
	var s: ScenarioDirectorState = steps[0]["forced_state"]
	_eq(s.get_variable(509), 1, "step0 Var509 = 1")


func _test_plan_step2_forced_state_contents() -> void:
	# Step to member 5: cond1 = Var127==0, Var128==0, Present(23), Present(52),
	# ActiveTurn(23), HP>=(23,1), HP>=(52,1).
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 5)
	if steps.size() != 2:
		return
	var s: ScenarioDirectorState = steps[1]["forced_state"]
	_eq(s.get_variable(127), 0, "step1 Var127 = 0")
	_eq(s.get_variable(128), 0, "step1 Var128 = 0")
	_ok(s.unit_present(ORBONNE_AGRIAS), "step1 Present(23)")
	_ok(s.unit_present(ORBONNE_GAFGARION), "step1 Present(52)")
	_ok(s.is_active_turn(ORBONNE_AGRIAS), "step1 ActiveTurn(23)")
	_ok(s.unit_hp(ORBONNE_AGRIAS) >= 1, "step1 HP(23) >= 1")
	_ok(s.unit_hp(ORBONNE_GAFGARION) >= 1, "step1 HP(52) >= 1")


# --- Preemption: forcing step-2's guard but ALSO leaving Var509=1 → director
#     returns 4 (earlier edge wins), and ScenarioPath reports the preemption
#     rather than claiming 5. Validates first-match-wins. ---

func _test_preemption_reported() -> void:
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 5)
	if steps.size() != 2:
		return
	var forced: ForcedDirectorState = steps[1]["forced_state"]
	forced.set_variable(509, 1)  # pollute with an earlier edge's guard
	# Directly: first-match-wins returns 4, not the intended 5.
	_eq(ScenarioDirector.new(forced).next_scenario(ORBONNE_BC), 4, "polluted state → director returns 4")
	# ScenarioPath's verifier must report the preemption, not lie about reaching 5.
	var report := ScenarioPath.isolates(ORBONNE_BC, forced, 5)
	_ok(not bool(report["isolated"]), "isolates(): intended 5 is NOT isolated")
	_eq(int(report["actual"]), 4, "isolates(): actual = 4")
	_eq(int(report["preempted_by"]), 4, "isolates(): preempted_by = 4")


func _test_plan_to_setup_root_is_empty() -> void:
	# The setup root (scenario 3) is booted once, not a director target → 0 steps.
	var steps := ScenarioPath.new().plan(ORBONNE_BC, 3)
	_eq(steps.size(), 0, "plan(1,3) [setup root] has 0 steps")


# --- Guard synthesizer: each opcode inverts to the minimal forced read ---

func _test_synthesizer_inverts_each_opcode() -> void:
	# Build a synthetic requirement list covering the common opcodes and confirm
	# the synthesized ForcedDirectorState answers each guard true.
	var reqs := [
		_req(BattleConditionalOpcode.VARIABLE_EQ, [{"value": 200}, {"value": 7}]),
		_req(BattleConditionalOpcode.VARIABLE_GE, [{"value": 201}, {"value": 3}]),
		_req(BattleConditionalOpcode.VARIABLE_LE, [{"value": 202}, {"value": 9}]),
		_req(BattleConditionalOpcode.UNIT_PRESENT, [{"value": 11}]),
		_req(BattleConditionalOpcode.HP_GE, [{"value": 12}, {"value": 1}]),
		_req(BattleConditionalOpcode.HP_LE, [{"value": 13}, {"value": 0}]),
		_req(BattleConditionalOpcode.MP_GE, [{"value": 14}, {"value": 5}]),
		_req(BattleConditionalOpcode.ACTIVE_TURN, [{"value": 15}]),
		_req(BattleConditionalOpcode.VICTORY, []),
	]
	var s := ForcedDirectorState.synthesize(reqs)
	_eq(s.get_variable(200), 7, "synth Variable ==(200,7)")
	_ok(s.get_variable(201) >= 3, "synth Variable >=(201,3)")
	_ok(s.get_variable(202) <= 9, "synth Variable <=(202,9)")
	_ok(s.unit_present(11), "synth Present(11)")
	_ok(s.unit_hp(12) >= 1, "synth HP >=(12,1)")
	_ok(s.unit_hp(13) <= 0, "synth HP <=(13,0)")
	_ok(s.unit_mp(14) >= 5, "synth MP >=(14,5)")
	_ok(s.is_active_turn(15), "synth ActiveTurn(15)")
	_ok(s.is_victory(), "synth Victory()")

	# And a director built on it must accept every one of those requirements.
	var d := ScenarioDirector.new(s)
	for r in reqs:
		_ok(d._requirement_holds(r), "director accepts synth req op 0x%02x" % int(r["opcode"]))


func _req(opcode: int, params: Array) -> Dictionary:
	return {"opcode": opcode, "params": params}
