extends Node
# test-kind: logic
# seeded-break: no-oped BOTH _update_vitals_for_selection() calls on the _try_scroll path (rebuild_cells's tail rebind — ADR-0180 — and _try_scroll's own explicit call, which is redundant today because rebuild_cells already rebinds) — the pre-fix stale-panel shape; the 'vitals panel REFRESHED to the unit now under the cursor (not the stale one)' assert reds (panel keeps the pre-scroll unit), the panel-shows-the-pre-scroll-unit (set_selected_cell still refreshes), _try_scroll-scrolls / offset-advanced / genuinely-new-unit-windowed and vitals-window-built asserts stay green

## TDD guard for the SCROLL-REFRESH bug in the all-templates view (ADR-0081 follow-up).
##
## At the bottom row, pressing ↓ scrolls the ROW window: a NEW unit slides under the
## STATIONARY cursor. The cell index does not change, so set_selected_cell early-returns
## and the side panels used to keep showing the OLD unit. The fix routes _try_scroll
## through _update_vitals_for_selection() after rebuild_cells(), so the vitals panel +
## RIGHT info panel + portrait follow the unit now under the cursor.
##
## This pins the invariant AS STATE: after _try_scroll, the vitals window's current view
## reflects units[selected_cell] (the freshly-windowed unit), NOT the pre-scroll unit.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/FormationScrollSelectionTest.tscn

const FormationSceneClass = preload("res://src/ui3/formation/FormationScene.gd")
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== FormationScrollSelectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationScrollSelectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationScrollSelectionTest")
		get_tree().quit(0)


func _run() -> void:
	CharacterCatalog.reset_to_new_game()
	AllTemplatesSeeder.seed()
	var owned: Array = CharacterCatalog.owned_units()
	_assert_true(owned.size() > FormationSceneClass.ROWS * FormationSceneClass.COLS,
		"seeded roster overflows the grid so a scroll is real (%d units)" % owned.size())

	var form: FormationSceneClass = FormationSceneClass.new()
	form.name = "Formation"
	form.set_owned_characters(owned)
	add_child(form)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(form._vitals_window != null, "vitals window is built (not debug_bodies_only)")

	# Park the cursor on the BOTTOM row so a further ↓ scrolls instead of moving it.
	var cols: int = FormationSceneClass.COLS
	var bottom := Vector2i(0, FormationSceneClass.ROWS - 1)
	form.set_selected_cell(bottom)
	await get_tree().process_frame
	var idx: int = bottom.y * cols + bottom.x

	var before_unit = form._roster_characters()[idx]
	_assert_eq(form._vitals_window._current.get("name", ""), before_unit.display_name,
		"panel shows the pre-scroll unit under the cursor")

	# ↓ at the bottom row: the window scrolls, a NEW unit slides under the stationary cursor.
	var scrolled: bool = form._try_scroll(1)
	_assert_true(scrolled, "_try_scroll(1) scrolls at the bottom row")
	_assert_eq(form.scroll_offset, 1, "scroll offset advanced by one row")
	await get_tree().process_frame

	var after_unit = form._roster_characters()[idx]
	_assert_true(after_unit != before_unit,
		"a genuinely new unit is windowed under the cursor after the scroll")
	# THE REGRESSION: the panel must now show the NEW unit, not the stale pre-scroll one.
	_assert_eq(form._vitals_window._current.get("name", ""), after_unit.display_name,
		"vitals panel REFRESHED to the unit now under the cursor (not the stale one)")

	form.queue_free()


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
