extends Node
## ADR-0051's world-map panel is a VIEW, and this is the first thing that checks it.
##
## The panel arrived on trunk with no test and this line then added a control to it, so
## `_build_ui` had never been executed by anything: `register_panel()` only appends to a
## list — the dashboard calls `setup()` later, and a bare capture run has no dashboard at
## all. A plain boot of `WorldMap.tscn` therefore prints zero errors whether this file
## builds or not, which is not a check.
##
## What it pins is the ADR's own claim, in both directions: `fixture`, `zoom` and
## `boot_menu` are PROPERTIES of [WorldMapScene] and the panel reads and writes them
## THERE ("toggles persist as scene-level vars, not autoload globals"). A control that
## edits its own copy would pass a smoke test and fail this.
##
## `boot_menu` is the one this line added, and the one the `--menu=` rig arg writes — the
## panel is where a contributor is supposed to DISCOVER that it exists ("the F3 debug panel
## becomes the canonical place to discover what's configurable in a scene").
##
## Bound to a bare Node, not a real WorldMapScene: the panel reaches its subject only
## through `get`/`set`/`has_method`, so a stand-in with the same three properties exercises
## every path without loading the map's disc-derived VRAM.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/WorldMapDebugPanelTest.tscn

const WorldMapPanel = preload("res://src/debug/WorldMapDebugPanel.gd")

var _passed: int = 0
var _failed: int = 0


## The three `@export`s the panel is a view onto, and nothing else.
class SceneStub extends Node:
	var fixture: String = "ss1"
	var zoom: int = 3
	var boot_menu: String = ""
	var captured_to: String = ""
	var captured_quit: bool = true

	func capture_to(path: String, quit_when_done: bool = true) -> void:
		captured_to = path
		captured_quit = quit_when_done


func _ready() -> void:
	var scene := SceneStub.new()
	add_child(scene)
	var panel := WorldMapPanel.new()
	add_child(panel)
	panel.bind(scene)
	panel.setup()

	var fixture_picker := _find_option(panel, WorldMapPanel.FIXTURES)
	var menu_picker := _find_option(panel, ["(none)", "1", "move"])

	_true(fixture_picker != null, "the Fixture picker exists")
	_true(menu_picker != null, "the 'Open with' picker exists (boot_menu)")

	# --- the panel WRITES the scene's properties, not its own copies ---
	if fixture_picker:
		fixture_picker.item_selected.emit(1)
		_true(scene.fixture == "ss2",
			"picking a fixture writes WorldMapScene.fixture (got %s)" % scene.fixture)
	if menu_picker:
		var i := WorldMapPanel.BOOT_MENUS.find("screenin")
		_true(i > 0, "BOOT_MENUS carries the contact-sheet arms")
		menu_picker.item_selected.emit(i)
		_true(scene.boot_menu == "screenin",
			"picking a boot menu writes WorldMapScene.boot_menu (got '%s')" % scene.boot_menu)

	var spin := _find_spinbox(panel)
	_true(spin != null, "the Zoom spinbox exists")
	if spin:
		spin.value_changed.emit(4.0)
		_true(scene.zoom == 4, "scrubbing zoom writes WorldMapScene.zoom (got %d)" % scene.zoom)

	# --- the panel READS them back, so re-opening it never shows a stale row ---
	scene.fixture = "ss1"
	scene.boot_menu = "town"
	scene.zoom = 2
	panel.on_shown()
	if fixture_picker:
		_true(fixture_picker.get_selected_id() == 0 or fixture_picker.selected == 0,
			"on_shown re-reads fixture from the scene")
	if menu_picker:
		_true(menu_picker.selected == WorldMapPanel.BOOT_MENUS.find("town"),
			"on_shown re-reads boot_menu from the scene")
	if spin:
		_true(int(spin.value) == 2, "on_shown re-reads zoom from the scene")

	# --- Capture must NOT quit: the ADR's named example is a button in a live session ---
	var shoot := _find_button(panel, "Capture viewport")
	_true(shoot != null, "the Capture viewport button exists")
	if shoot:
		shoot.pressed.emit()
		_true(scene.captured_to != "", "the button calls capture_to (got '%s')" % scene.captured_to)
		_true(scene.captured_quit == false,
			"the panel's capture must NOT quit the session (quit_when_done=%s)" % scene.captured_quit)

	_finish()


func _find_option(n: Node, wanted: Array) -> OptionButton:
	if n is OptionButton:
		var ob := n as OptionButton
		for i in ob.item_count:
			if String(wanted[0]) == ob.get_item_text(i):
				return ob
	for c in n.get_children():
		var hit := _find_option(c, wanted)
		if hit != null:
			return hit
	return null


func _find_spinbox(n: Node) -> SpinBox:
	if n is SpinBox:
		return n
	for c in n.get_children():
		var hit := _find_spinbox(c)
		if hit != null:
			return hit
	return null


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_passed = _passed
		_failed += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	if _failed > 0:
		print("[FAIL] WorldMapDebugPanelTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] WorldMapDebugPanelTest — %d/%d" % [_passed, _passed])
		get_tree().quit(0)
