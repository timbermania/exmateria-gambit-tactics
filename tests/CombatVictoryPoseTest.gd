extends Node
## Guard for the post-battle "return to normal" decoupling (ADR-0026 follow-up).
##
## The GPU reports a battle-won SETTLED state (LOGICAL_ACTIVITY_CELEBRATING) that
## `stage_victory.glsl` keys on to declare the winner — that handshake is
## untouched. What the settled unit RENDERS is now a CPU-side choice owned by
## `CombatLoop.settled_victory_activity`:
##
##   - celebrate ON  → the made-up victory dance (CELEBRATING), the arena's fun
##     behaviour and the thing the ADR-0026 combat-suite invariant guards.
##   - celebrate OFF (default, "faithful") → the unit returns to its normal,
##     HP-appropriate pose: a KO'd unit is LEFT as its corpse (DEAD), and a
##     living unit settles to IDLE — where the resolver then auto-picks
##     IDLE_LOW_HEALTH (kneel) for a critical unit or plain IDLE (walk-in-place
##     wait) for a healthy one.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CombatVictoryPoseTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationResolutionMap = ExMateriaSpriteRig.AnimationResolutionMap
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_settled_decision()
	_test_faithful_idle_autopicks_low_health()

	print("\n=== CombatVictoryPoseTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CombatVictoryPoseTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CombatVictoryPoseTest")
		get_tree().quit(1)
	else:
		print("[PASS] CombatVictoryPoseTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_ne(got, other, name: String) -> void:
	if got != other:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s should differ from %s" % [name, str(got), str(other)])


# The pure decision: (celebrate, is_dead) → activity to apply, or LEAVE_ACTIVITY.
func _test_settled_decision() -> void:
	var A := DisplayActivity.Activity

	# Celebrate ON: dance regardless of HP (preserves the ADR-0026 arena behaviour;
	# a KO'd carrier that reached the settled state still routes as before).
	_assert_eq(CombatLoop.settled_victory_activity(true, false), A.CELEBRATING,
		"celebrate + alive → CELEBRATING")
	_assert_eq(CombatLoop.settled_victory_activity(true, true), A.CELEBRATING,
		"celebrate + dead → CELEBRATING")

	# Celebrate OFF (faithful): living unit settles to IDLE; dead unit is LEFT as
	# its corpse (sentinel = don't touch, so DEAD holds its final frame).
	_assert_eq(CombatLoop.settled_victory_activity(false, false), A.IDLE,
		"faithful + alive → IDLE")
	_assert_eq(CombatLoop.settled_victory_activity(false, true), CombatLoop.LEAVE_ACTIVITY,
		"faithful + dead → LEAVE (stay DEAD)")

	# The sentinel must not collide with a real activity value.
	_assert_ne(CombatLoop.LEAVE_ACTIVITY, A.IDLE, "LEAVE sentinel != IDLE")
	_assert_ne(CombatLoop.LEAVE_ACTIVITY, A.DEAD, "LEAVE sentinel != DEAD")
	_assert_ne(CombatLoop.LEAVE_ACTIVITY, A.CELEBRATING, "LEAVE sentinel != CELEBRATING")


# Faithful mode hands the unit the base IDLE activity; the resolver's own
# auto-pick then produces the kneel for a critical unit and the neutral wait for
# a healthy one — so "return to normal" needs no HP branch of its own.
func _test_faithful_idle_autopicks_low_health() -> void:
	var A := DisplayActivity.Activity
	var t := "TYPE1"  # authored humanoid; has both IDLE and IDLE_LOW_HEALTH rows

	var idle := AnimationResolutionMap.resolve_for_activity(A.IDLE, t, false, false)
	var kneel := AnimationResolutionMap.resolve_for_activity(A.IDLE, t, false, true)
	var kneel_explicit := AnimationResolutionMap.resolve_idle_low_health(t, false)

	# Base IDLE + low_health flag routes to the same slot as the explicit
	# IDLE_LOW_HEALTH resolver (the auto-pick wiring), and differs from neutral IDLE.
	_assert_eq(kneel.body_slot, kneel_explicit.body_slot,
		"IDLE(low_health=true) auto-picks IDLE_LOW_HEALTH slot")
	_assert_ne(kneel.body_slot, idle.body_slot,
		"kneel slot differs from neutral idle slot")
