extends Node
## Guard for ADR-0068: the F3 Scenario picker's selection persists across app
## restarts, not just scene reloads. `DebugConfig.active_scenario_id` is backed by
## the `scenario.active_id` Tune slug at persistence class AUTOSAVE — so assigning it
## (what ScenarioDebugPanel does on select) commits to the staging file in the same
## gesture, with no Pin. The picker widget itself stays a raw dynamic dropdown
## (tune-exempt), but its VALUE is Tune-backed and sticky.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioActiveIdAutosaveTest.tscn

const SLUG := "scenario.active_id"
const TMP := "user://test_scenario_active_id_autosave.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Tune.reset()

	# Reading the property registers the slug — and it must register as AUTOSAVE, so
	# the panel field shows green (sticks on edit) rather than cyan (Pin-to-keep).
	var _boot: int = DebugConfig.active_scenario_id
	_check(Tune.persist_of(SLUG) == Tune.Persist.AUTOSAVE, "scenario.active_id is AUTOSAVE")
	_check(_boot == -1, "default is -1 (use scene default) when nothing committed")

	# An explicit PICK (what the F3 picker does) routes through Tune AND commits it.
	DebugConfig.set_active_scenario_id(8, TMP)
	_check(DebugConfig.active_scenario_id == 8, "getter reflects an explicit pick")
	_check(int(Tune.bind(SLUG, -1)) == 8, "explicit pick routed through Tune")
	_check(not Tune.is_dirty(SLUG), "explicit pick commits in the same gesture (AUTOSAVE)")

	# Disk round-trip: a fresh boot (clean registry) that loads the staging file
	# restores the picked scenario — proving it survives an app restart, not just Ctrl+R.
	Tune.reset()
	Tune.load_overrides(TMP)
	_check(DebugConfig.active_scenario_id == 8, "explicit pick survives a reload from disk")

	# A BOOT DEFAULT (a bare property assignment, as GPUArena does) is session-only: it
	# updates the live value but MUST NOT pin the default into the git-tracked overrides.
	DebugConfig.active_scenario_id = 5
	_check(DebugConfig.active_scenario_id == 5, "boot-default seed updates the live value")
	_check(_disk_value(TMP) == 8, "boot-default seed does NOT commit (staging file unchanged)")

	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	print("\n=== ScenarioActiveIdAutosaveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScenarioActiveIdAutosaveTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioActiveIdAutosaveTest")
		get_tree().quit(0)


# The committed value for SLUG in the staging file at `path` (-999 if absent), read
# straight off disk so a test can prove a write did (or did not) reach the file.
func _disk_value(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -999
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has(SLUG):
		return int(parsed[SLUG])
	return -999


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
