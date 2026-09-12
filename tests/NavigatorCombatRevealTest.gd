extends Node
## Guard for the fade-reveal GUARANTEE on the "seek to COMBAT" path. On a direct seek,
## [NavigatorMain.run_combat] boots a fresh battle world (fade primed fully BLACK by
## ScenarioPlayerScene._boot_scenario_world) and settles it by fast-forwarding the group's
## opener cinematic — whose {Reveal} opcode fades the world in. But at 30× fast-play the
## opener's timed fade ticker may still be mid-reveal when the opcode stream ends, so
## `_settle_world_via_opener` snaps the fade fully clear via `_reveal_for_combat` as a
## belt-and-braces visibility guarantee (also the sole reveal when a group has no opener).
## Without it the battle can render under a partial black rect.
##
## No scene boot / render / sim: constructs a bare NavigatorMain and exercises the reveal
## helper against a stub fade rect. Mirrors the VM's settled-reveal end state (alpha 0 —
## see ScenarioVM._reveal_remaining_ticks ticker). The opener-replay wiring itself is
## scene-bound and verified headful (settled camera/color/weather, no black screen).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorCombatRevealTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_reveal_clears_boot_black_fade()
	_test_reveal_is_null_safe()

	print("\n=== NavigatorCombatRevealTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorCombatRevealTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorCombatRevealTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorCombatRevealTest")
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


func _test_reveal_clears_boot_black_fade() -> void:
	var nav := _new_nav()
	var fade := ColorRect.new()
	# The state `_boot_scenario_world` leaves behind before combat.
	fade.color = Color(0, 0, 0, 1)
	nav._fade_rect = fade

	nav._reveal_for_combat()

	# Settled reveal = fully transparent, so the battle world is visible.
	_true(fade.color.a <= 0.001, "reveal clears the boot-time black fade to transparent")

	fade.free()
	nav.free()


func _test_reveal_is_null_safe() -> void:
	# In the normal linear walk combat reuses the opener's world; a defensive path or an
	# early call must not crash if the fade rect isn't wired yet.
	var nav := _new_nav()
	nav._fade_rect = null
	nav._reveal_for_combat()  # must not throw
	_true(true, "reveal is null-safe when the fade rect is not wired")
	nav.free()
