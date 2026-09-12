extends Node
## Guard for the LOAD-UNDER-BLACK guarantee on a cross-group re-boot. When the walk
## crosses from one group's world into the next (e.g. the chapel → Orbonne battle), the
## navigator tears down the live world and boots a fresh one. The freshly-built world
## must NOT render at its default camera before the incoming member's {Reveal} fades it
## in — the real hardware loads the whole encounter under black. So `_boot_world_for`
## primes the fade fully BLACK before it teardowns/rebuilds, via `_prime_fade_black`.
##
## Without it, the prior group leaves the fade transparent (revealed), and the 2+ render
## frames inside `_boot_scenario_world` (map build + spawn) flash the never-shown default
## camera of the new world.
##
## No scene boot / render / sim: constructs a bare NavigatorMain and exercises the prime
## helper against a stub fade rect. It is the symmetric partner to `_reveal_for_combat`
## (see NavigatorCombatRevealTest). The boot-ordering itself (prime BEFORE change_map) is
## scene-bound and verified headful.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorRebootFadeTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_prime_blacks_a_revealed_fade()
	_test_prime_is_null_safe()

	print("\n=== NavigatorRebootFadeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorRebootFadeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorRebootFadeTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorRebootFadeTest")
		get_tree().quit(0)


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _new_nav() -> Node:
	# Bare construct — no tree add, so no @onready / scene boot fires.
	return load("res://src/scenarios/NavigatorMain.gd").new()


func _test_prime_blacks_a_revealed_fade() -> void:
	var nav := _new_nav()
	var fade := ColorRect.new()
	# The state the PRIOR group (the chapel) leaves behind: fully revealed / transparent.
	fade.color = Color(0, 0, 0, 0)
	nav._fade_rect = fade

	nav._prime_fade_black()

	# A cross-group re-boot must start under fully opaque black regardless of prior state,
	# so the new world builds/renders hidden until its member's {Reveal} fades it in.
	_true(fade.color.a >= 0.999, "re-boot primes the fade to opaque black")
	_true(fade.color.r == 0.0 and fade.color.g == 0.0 and fade.color.b == 0.0,
		"primed fade is black")

	fade.free()
	nav.free()


func _test_prime_is_null_safe() -> void:
	# A defensive path must not crash if the fade rect isn't wired yet.
	var nav := _new_nav()
	nav._fade_rect = null
	nav._prime_fade_black()  # must not throw
	_true(true, "prime is null-safe when the fade rect is not wired")
	nav.free()
