extends Node
## Fast bare-construct guard for NavigatorMain's COMMAND MODE toggle (ADR-0082). Command mode is
## the frozen-but-navigable battle state (`combat_active = false` + live cursor + free camera); its
## two instances (Deployment before the fight, Paused mid-fight) are the LITERAL same flag state.
## TAB is the ONE toggle that drives every transition: Deployment → Live ("start battle"),
## Live → STOPPED, Paused → Live ("continue"). Enter is reserved for a future cursor-select and must
## NOT drive the phase toggle.
##
## These guards bare-construct a NavigatorMain (no scene/GPU boot; mirrors NavigatorPreBattleTest)
## and exercise the toggle STATE MACHINE plus the go-live gambit swap directly:
##   - Deployment → Live: the toggle fires resume_pre_battle (clears the park, advances the runner).
##   - Live → Paused: the toggle freezes a live loop (combat_active → false) without leaving the loop.
##   - Paused → Live: the toggle re-arms a frozen loop (combat_active → true).
##   - go-live swaps IDLE gambits → the pending COMBAT gambits (arm_combat_gambits), the freeze model.
## The real frozen-loop build + cursor-seeded-on-leader are proven headful (NavigatorCommandModeProofTest).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorCommandModeTest.tscn

var _passed: int = 0
var _failed: int = 0


## A runner that only records the pre-battle → combat advance (mirrors NavigatorPreBattleTest.FakeRunner).
class FakeRunner:
	extends NavigatorRunner
	var pre_finished: int = 0
	func _init() -> void: super([], null)
	func on_pre_battle_finished() -> void: pre_finished += 1


## A CombatLoop that records arm_combat_gambits so the idle→combat swap is observable without GPU.
## Extends the real CombatLoop (so the typed `_combat_loop` accepts it) — its combat_active setter is
## tree-null-safe (the visuals-freeze refresh early-returns off-tree), so flipping it costs nothing here.
class RecordingLoop:
	extends CombatLoop
	var armed_with = null
	var arm_calls: int = 0
	func arm_combat_gambits(p_gambits: Array) -> void:
		armed_with = p_gambits
		arm_calls += 1


func _ready() -> void:
	_test_deployment_toggle_goes_live()
	_test_live_toggle_pauses()
	_test_paused_toggle_resumes()
	_test_go_live_arms_combat_gambits()

	print("\n=== NavigatorCommandModeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorCommandModeTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] NavigatorCommandModeTest"); get_tree().quit(1)
	else:
		print("[PASS] NavigatorCommandModeTest"); get_tree().quit(0)


func _new_nav() -> Node:
	return load("res://src/scenarios/NavigatorMain.gd").new()


## Deployment → Live: from the pre-battle park, Tab (the command-mode toggle) advances to combat —
## exactly what Enter used to do, now moved onto Tab so Enter is free for selection.
func _test_deployment_toggle_goes_live() -> void:
	var nav := _new_nav()
	var runner := FakeRunner.new()
	nav._nav_runner = runner
	nav._pre_battle_active = true

	nav._start_battle()
	_true(not nav._pre_battle_active, "Deployment→Live: Space clears the pre-battle park")
	_eq(runner.pre_finished, 1, "Deployment→Live: Space advances the runner (start battle)")
	nav.free()


## Live → STOPPED: with a live loop, Tab freezes the sim (combat_active → false) without tearing it down.
func _test_live_toggle_pauses() -> void:
	var nav := _new_nav()
	nav._nav_runner = FakeRunner.new()
	var loop := RecordingLoop.new()
	add_child(loop)  # in-tree so the loop's combat_active setter (visuals-freeze refresh) is quiet
	nav._combat_loop = loop
	loop.combat_active = true
	nav._combat_active = true

	nav._toggle_tactical_stop()
	_true(not loop.combat_active, "Live→Paused: Esc freezes the loop (combat_active false)")
	_true(not nav._combat_active, "Live→Paused: Esc clears the pump flag")
	_true(nav._combat_loop == loop, "Live→Paused: loop is retained, not torn down")
	loop.free()
	nav.free()


## STOPPED → Live: with a frozen (paused) loop, Tab re-arms the sim (combat_active → true).
func _test_paused_toggle_resumes() -> void:
	var nav := _new_nav()
	nav._nav_runner = FakeRunner.new()
	var loop := RecordingLoop.new()
	add_child(loop)  # in-tree so the loop's combat_active setter (visuals-freeze refresh) is quiet
	nav._combat_loop = loop
	loop.combat_active = false
	nav._combat_active = false

	nav._toggle_tactical_stop()
	_true(loop.combat_active, "Paused→Live: Esc re-arms the loop (combat_active true)")
	_true(nav._combat_active, "Paused→Live: Esc sets the pump flag")
	loop.free()
	nav.free()


## go-live (the Deployment→Live half of the freeze model): a FROZEN loop was booted with IDLE
## (empty) gambits; going live must SWAP in the pending COMBAT gambits (arm_combat_gambits) and set
## the loop live. This is what makes "one command mode" true in code — the loop already exists; Tab
## only arms it.
func _test_go_live_arms_combat_gambits() -> void:
	var nav := _new_nav()
	nav._nav_runner = FakeRunner.new()
	var loop := RecordingLoop.new()
	add_child(loop)
	nav._combat_loop = loop
	var combat_gambits := [[1], [2]]   # sentinel encoded gambits (the "combat" set)
	nav._pending_gambits = combat_gambits
	loop.combat_active = false
	nav._combat_active = false

	nav._go_live()
	_eq(loop.arm_calls, 1, "go-live: arms the pending combat gambits exactly once")
	_true(loop.armed_with == combat_gambits, "go-live: swaps idle→the pending combat gambits")
	_true(loop.combat_active, "go-live: sets the loop live")
	_true(nav._combat_active, "go-live: sets the pump flag")
	loop.free()
	nav.free()


func _eq(got, want, name: String) -> void:
	if got == want: _passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])

func _true(c: bool, name: String) -> void: _eq(c, true, name)
