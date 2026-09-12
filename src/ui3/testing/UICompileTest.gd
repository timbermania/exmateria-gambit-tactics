extends SceneTree
## Compile and instantiation test for ui3 components.
##
## Run via: godot --headless --script res://src/ui3/testing/UICompileTest.gd
##
## This script verifies that all ui3 components can be loaded and instantiated.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("[UICompileTest] Starting ui3 component tests...")
	print("")

	_test_component("UIRosterBar", "res://src/ui3/UIRosterBar.gd")
	_test_component("UICombatManager", "res://src/ui3/UICombatManager.gd")
	_test_component("UIListModalWindow", "res://src/ui3/UIListModalWindow.gd")
	_test_component("UIEquipmentPopup", "res://src/ui3/UIEquipmentPopup.gd")
	_test_component("UIJobPopup", "res://src/ui3/UIJobPopup.gd")
	_test_component("UIPassiveAbilityPopup", "res://src/ui3/UIPassiveAbilityPopup.gd")
	_test_component("UIActionAbilityPopup", "res://src/ui3/UIActionAbilityPopup.gd")
	_test_component("UILearnPanel", "res://src/ui3/UILearnPanel.gd")
	_test_component("UIGambitEditor3", "res://src/ui3/UIGambitEditor.gd")

	print("")
	_test_testing_utilities()

	print("")
	_print_summary()
	quit(_failed == 0)


func _test_component(name: String, path: String) -> void:
	print("Testing %s..." % name)

	# Check file exists
	if not FileAccess.file_exists(path):
		_record_failure(name, "File not found: %s" % path)
		return

	# Try to load script
	var script = load(path)
	if script == null:
		_record_failure(name, "Failed to load script")
		return

	# Try to instantiate
	var instance = script.new()
	if instance == null:
		_record_failure(name, "Failed to instantiate")
		return

	# Clean up
	if instance is Node:
		instance.queue_free()

	_record_pass(name)


func _test_testing_utilities() -> void:
	pass


func _record_pass(name: String) -> void:
	_passed += 1
	print("  PASS: %s" % name)


func _record_failure(name: String, message: String) -> void:
	_failed += 1
	print("  FAIL: %s - %s" % [name, message])


func _print_summary() -> void:
	print("=" .repeat(60))
	print("[UICompileTest] Summary: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("[UICompileTest] All tests passed!")
	else:
		print("[UICompileTest] Some tests failed.")
	print("=" .repeat(60))
