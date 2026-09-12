extends Node
## The navigator scene owns its own navigation surface.
##
## [NavigatorMain] extends [ScenarioPlayerScene], so it inherits that scene's whole debug
## panel set — including [ScenarioPathDebugPanel], the scenario-player's "pick a root ->
## pick a scenario -> Walk here" launcher, registered at the head of the SAME "Scenario"
## masonry cell the navigator's own [NavigatorDebugPanel] lives in. Two rival "pick a
## scene" pickers side by side, and driving the wrong one drops you out of the story walk
## into plain single-group scenario playback.
##
## This pins the split. On a booted navigator scene:
##   - the SCENARIO cell holds the Navigator panel and NOT the scenario path panel;
##   - the parent's INSPECTION panels (VM disassembly, dialogue box, look tuners) are
##     still there — suppressing the launcher must not strip the tools you debug event
##     instructions with.
##
## [b]Both arms matter.[/b] An override that suppressed everything would pass a
## path-panel-absent assertion on its own; the inspection arm is what says the cut was
## the launcher and only the launcher.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 900 res://tests/NavigatorPanelOwnershipTest.tscn

const TIMEOUT_MS := 60000
const SEEK_ROOT := 7   # Military Academy — a linear group, the cheapest world to boot

var _passed := 0
var _failed := 0
var _nav: Node = null
var _start_ms := 0


func _ready() -> void:
	ScenarioDebugSession.navigator_start_root = SEEK_ROOT
	ScenarioDebugSession.navigator_stop_root = SEEK_ROOT
	ScenarioDebugSession.navigator_start_action = 0

	_start_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)

	# Panels register inside `_boot_scenario_world`, i.e. only once the walk's first
	# action has booted a world — so wait for the navigator's own panel to appear rather
	# than sampling an empty overlay and calling it a pass.
	while _find("NavigatorDebugPanel") == null \
			and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame

	_true("the navigator registered its own seek panel", _find("NavigatorDebugPanel") != null)
	if _find("NavigatorDebugPanel") == null:
		print("  (timed out after %d ms — nothing below could report)" % TIMEOUT_MS)
		_finish()
		return

	# ARM 1 — the scenario-player launcher is gone from this scene.
	_true("the scenario-player path panel is NOT registered on the navigator scene",
			_find("ScenarioPathDebugPanel") == null)

	# ARM 2 — and the inspection panels the parent registers are still here. Without this
	# arm, an override that suppressed the parent's whole registration would pass arm 1.
	for ident in ["ScenarioVMDebugPanel", "ScenarioDialogueBoxDebugPanel",
			"ScenarioViewDebugPanel", "ScenarioWeatherDebugPanel"]:
		_true("the parent's %s inspection panel survives the cut" % ident, _find(ident) != null)

	_finish()


## The registered panel of the named class, in ANY category — a category-scoped lookup
## would read "absent" for a panel that merely moved cells.
func _find(class_ident: String):
	for cat in DebugOverlay._panels.keys():
		for panel in DebugOverlay._panels[cat]:
			if is_instance_valid(panel) and panel.get_script() != null \
					and panel.get_script().get_global_name() == class_ident:
				return panel
	return null


func _true(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  [ok] %s" % label)
	else:
		_failed += 1
		print("  [XX] %s" % label)


func _finish() -> void:
	print("\n=== NavigatorPanelOwnershipTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorPanelOwnershipTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorPanelOwnershipTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorPanelOwnershipTest")
		get_tree().quit(0)
