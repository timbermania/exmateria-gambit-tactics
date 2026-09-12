extends Node
## #555 — the map's two F3 panels are mounted from the HOST side, not by `MapComposer`.
##
## `MapComposer` used to construct and register `SkirtDebugPanel` + `MapRenderDebugPanel`
## in its own `_setup_debug_panels()`. That is an ADR-0068 R1 violation (the production
## owner of the tunables also instantiated their view) and it was the ENTIRE `DebugOverlay`
## autoload residue inside `Battlefield`. `MapDebugPanels.register_map_panels()` owns the
## mount now, and `Battlefield -> Debug` fell 42 -> 38.
##
## THREE ARMS, because the first two alone cannot report the event:
##   1. the mount lands both panels in their categories, wired to the composer passed in;
##   2. a SECOND call does not stack a duplicate AND re-points the surviving panel at the
##      new composer — `MapComposer._render_setup_done` was a PER-INSTANCE guard that
##      could not see a panel outliving its scene, so a reload used to stack a copy, and
##      a bare `return` guard would leave the button calling into a freed node;
##   3. the map source names neither `DebugOverlay` nor either panel class IN CODE. Arms 1-2
##      pass just as well with the old registration still in place beside the new one, so
##      only arm 3 reports the removal. It reads the source with comments STRIPPED — the
##      prose in `MapComposer.gd` explaining the inversion names `DebugOverlay`, and a
##      raw text match would fail on the very comment that documents the fix.
##
## 🔴 ARM 3's SUBJECT IS A DIRECTORY, so it MOVES. It read `res://src/map/` until
## extraction #3's loop pass 6 (ADR-0184) emptied that directory into
## `addons/exmateria_battlefield/`, and `scanned > 0` is the only reason that
## surfaced as a failure rather than as a silent pass over zero files — which is
## the ADR-0148 shape, and the reason that assertion is here at all.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/MapDebugPanelMountTest.tscn

const MAP_DIR := "res://addons/exmateria_battlefield/"
const BANNED := ["DebugOverlay", "SkirtDebugPanel", "MapRenderDebugPanel"]

var _passed := 0
var _failed := 0


## Stand-in for MapComposer: `SkirtDebugPanel` only ever asks its owner for `rebuild_map`.
class FakeComposer extends Node:
	var rebuilds := 0
	func rebuild_map() -> void:
		rebuilds += 1


func _ready() -> void:
	_test_mount()
	_test_second_call_rebinds()
	_test_map_names_no_debug_symbols()

	print("\n=== MapDebugPanelMountTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] MapDebugPanelMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapDebugPanelMountTest")
		get_tree().quit(0)


# --- arm 1 -------------------------------------------------------------------

func _test_mount() -> void:
	_assert_true(_panels_of(DebugOverlay.Category.SKIRTS, "SkirtDebugPanel").is_empty(),
		"no Skirts panel is mounted before the host asks for one")

	var composer := FakeComposer.new()
	add_child(composer)
	MapDebugPanels.register_map_panels(composer)

	var skirts := _panels_of(DebugOverlay.Category.SKIRTS, "SkirtDebugPanel")
	_assert_eq(skirts.size(), 1, "the mount registers exactly one SkirtDebugPanel under SKIRTS")
	var renders := _panels_of(DebugOverlay.Category.SHADERS, "MapRenderDebugPanel")
	_assert_eq(renders.size(), 1, "the mount registers exactly one MapRenderDebugPanel under SHADERS")

	if skirts.is_empty():
		return
	_assert_true(_press_rebuild(skirts[0]), "the Skirts panel carries a Rebuild Mesh button")
	_assert_eq(composer.rebuilds, 1, "Rebuild Mesh reaches the composer the host passed in")


# --- arm 2 -------------------------------------------------------------------

func _test_second_call_rebinds() -> void:
	var first := _panels_of(DebugOverlay.Category.SKIRTS, "SkirtDebugPanel")
	if first.is_empty():
		_fail("arm 2 needs arm 1's panel")
		return

	var second_composer := FakeComposer.new()
	add_child(second_composer)
	MapDebugPanels.register_map_panels(second_composer)

	_assert_eq(_panels_of(DebugOverlay.Category.SKIRTS, "SkirtDebugPanel").size(), 1,
		"a second mount does not stack a second SkirtDebugPanel")
	_assert_eq(_panels_of(DebugOverlay.Category.SHADERS, "MapRenderDebugPanel").size(), 1,
		"a second mount does not stack a second MapRenderDebugPanel")

	var survivor: Node = _panels_of(DebugOverlay.Category.SKIRTS, "SkirtDebugPanel")[0]
	_assert_true(survivor == first[0], "the surviving panel is the SAME instance (UI state kept)")
	_assert_true(_press_rebuild(survivor), "the surviving panel still carries its button")
	_assert_eq(second_composer.rebuilds, 1,
		"Rebuild Mesh now reaches the NEW composer — the panel was rebound, not merely kept")


# --- arm 3 -------------------------------------------------------------------

func _test_map_names_no_debug_symbols() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for rel in _gd_files_under(MAP_DIR):
		var text := FileAccess.get_file_as_string(rel)
		if text.is_empty():
			continue
		scanned += 1
		var lineno := 0
		for raw in _strip_comments(text).split("\n"):
			lineno += 1
			for sym in BANNED:
				if raw.contains(sym):
					offenders.append("%s:%d names %s" % [rel, lineno, sym])
	_assert_true(scanned > 0, "arm 3 actually opened files under %s" % MAP_DIR)
	_assert_true(offenders.is_empty(),
		"no file under %s names a Debug panel symbol in code (%s)" % [MAP_DIR, ", ".join(offenders)])


## Blank out `#` comments (docstrings included) so a line of PROSE about the inversion
## cannot fail the rule it describes. Naive by design: `#` inside a string literal would
## truncate the line, which can only ever HIDE text from the scan on a line that has
## already been stripped — never invent an offender.
func _strip_comments(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var hash_at := line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)


func _gd_files_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# --- helpers -----------------------------------------------------------------

func _panels_of(category: int, class_ident: String) -> Array:
	var out: Array = []
	for panel in DebugOverlay._panels.get(category, []):
		if is_instance_valid(panel) and panel.get_script() != null \
				and panel.get_script().get_global_name() == class_ident:
			out.append(panel)
	return out


func _press_rebuild(node: Node) -> bool:
	var btn := _find_button(node, "Rebuild Mesh")
	if btn == null:
		return false
	btn.pressed.emit()
	return true


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == text:
			return child
		var found := _find_button(child, text)
		if found:
			return found
	return null


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, want %d)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _fail(label: String) -> void:
	_failed += 1
	print("[FAIL] %s" % label)
