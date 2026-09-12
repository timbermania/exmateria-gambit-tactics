extends Node
## AbilityPickerMenu interface guard (formation ability "Set" flow port).
## Mirrors the equip picker's navigation seam (EquipPickerRowMechanismTest) but
## for the text-only ability list: row_count/selected_row/scroll, move_up/down
## with wrap + the ROM 5-row scroll window (ABILITY_PICKER.md §3: row stride 16,
## VISIBLE_ROWS 5 — identical to the equip picker), and confirm/cancel signals.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/AbilityPickerMenuTest.tscn

const AbilityPickerMenu = preload("res://src/ui3/detail/AbilityPickerMenu.gd")

var _passed := 0
var _failed := 0
var _chosen_row := -1
var _cancelled := false


func _ready() -> void:
	# Capacity constant matches the ROM window (5 rows, 16px pitch).
	_expect(AbilityPickerMenu.VISIBLE_ROWS == 5, "VISIBLE_ROWS != ROM capacity 5")

	var p = AbilityPickerMenu.new()
	p.entries = []
	for i in 7:
		p.entries.append({"id": 100 + i, "name": "Ability %d" % i})
	add_child(p)
	await get_tree().process_frame

	_expect(p.row_count() == 7, "row_count %d != 7" % p.row_count())
	_expect(p.selected_row() == 0 and p.scroll() == 0, "fresh picker not at row0/scroll0")

	# Walk to the bottom of the window: no scroll yet.
	for i in 4:
		p.move_down()
	_expect(p.selected_row() == 4 and p.scroll() == 0,
		"row 4 should not scroll (row %d scroll %d)" % [p.selected_row(), p.scroll()])
	# Row 5 enters -> window slides.
	p.move_down()
	_expect(p.selected_row() == 5 and p.scroll() == 1,
		"row 5 must scroll (row %d scroll %d)" % [p.selected_row(), p.scroll()])
	p.move_down()
	_expect(p.selected_row() == 6 and p.scroll() == 2,
		"row 6 scroll 2 (row %d scroll %d)" % [p.selected_row(), p.scroll()])
	# Wrap down to top rewinds the window.
	p.move_down()
	_expect(p.selected_row() == 0 and p.scroll() == 0,
		"wrap to top must rewind (row %d scroll %d)" % [p.selected_row(), p.scroll()])
	# Wrap up to the last row scrolls to the tail.
	p.move_up()
	_expect(p.selected_row() == 6 and p.scroll() == 2,
		"wrap to bottom must scroll to tail (row %d scroll %d)" % [p.selected_row(), p.scroll()])

	# confirm() emits chosen(row) with the current selection.
	p.chosen.connect(func(r): _chosen_row = r)
	p.cancelled.connect(func(): _cancelled = true)
	p.confirm()
	_expect(_chosen_row == 6, "confirm emitted chosen(%d), want 6" % _chosen_row)
	p.cancel()
	_expect(_cancelled, "cancel did not emit cancelled")

	p.queue_free()

	# --- Slice 4b: text-only row rendering (ABILITY_PICKER.md §5) ---
	# Each VISIBLE row renders its candidate name as FONT text; NO per-row type
	# glyph or icon (the RE correction vs the equip picker). Fresh picker, scroll 0.
	var p2 = AbilityPickerMenu.new()
	p2.entries = [{"id": 6, "name": "Item"}, {"id": 7, "name": "Battle"}]
	p2.autoplay_open = false
	add_child(p2)
	await get_tree().process_frame
	# The two visible rows render their names as text.
	_expect(p2.visible_row_names() == ["Item", "Battle"],
		"visible_row_names %s != [Item, Battle]" % [p2.visible_row_names()])
	# Text glyphs are actually mounted (one ShaderMaterial per non-space glyph).
	_expect(p2.row_text_materials().size() > 0, "no row text glyph materials mounted")
	# Text-only: the picker mounts NO per-row decoration (type glyph / icon) quads.
	_expect(p2.row_decoration_materials().is_empty(),
		"picker mounted %d decoration quads — rows must be text-only" % p2.row_decoration_materials().size())

	# --- Chrome: the cream "Ability" TITLE tab + the glove CURSOR ---
	# The title is the SAME baked RANGETILE panel-tab cell (window_tab_rect("Ability")),
	# mounted through the index→CLUT sprite mechanism — exactly ONE cell, not FONT glyphs.
	_expect(p2.header_cell_materials().size() == 1,
		"header must mount exactly the one 'Ability' tab cell (got %d)" % p2.header_cell_materials().size())
	# The glove cursor is present when the picker opens (lit + shadow materials).
	_expect(p2.cursor_materials().size() > 0, "no glove cursor materials mounted")
	# The cursor anchor rides the VISIBLE row: row 0 vs row 1 differ by the 16px pitch.
	var a0 := AbilityPickerMenu.cursor_anchor_for(0)
	var a1 := AbilityPickerMenu.cursor_anchor_for(1)
	_expect(a1.y - a0.y == 16.0, "cursor row pitch != 16 (%s → %s)" % [a0, a1])

	# Only the visible window renders: 7 entries, 5 rows show their names.
	var p3 = AbilityPickerMenu.new()
	p3.entries = []
	for i in 7:
		p3.entries.append({"id": 200 + i, "name": "A%d" % i})
	p3.autoplay_open = false
	add_child(p3)
	await get_tree().process_frame
	_expect(p3.visible_row_names() == ["A0", "A1", "A2", "A3", "A4"],
		"7-entry window names %s != first 5" % [p3.visible_row_names()])
	p2.queue_free()
	p3.queue_free()

	# --- Chrome: the cream "Ability" title tab must NOT clip at the window top ---
	# The header cell is authored at y132, above the window rect top (y137); the box-open
	# aperture the picker opens over must be padded to enclose it, else the title is
	# scissored (mirrors EquipPickerMenu's aperture_pad). Guard the MECHANISM, not pixels:
	# once the window settles open, its live aperture encloses the header cell's rect.
	var p4 = AbilityPickerMenu.new()
	p4.entries = [{"id": 1, "name": "One"}, {"id": 2, "name": "Two"}]
	add_child(p4)
	await get_tree().process_frame
	var steps := 0
	while not p4._window.is_settled() and steps < 40:
		UI3Registry.transition_engine_step()
		steps += 1
	_expect(p4._window.is_settled(), "picker window failed to settle open (steps %d)" % steps)
	var aperture := Rect2(p4._window.aperture())
	_expect(aperture.encloses(p4._header_elem.rect()),
		"the 'Ability' title cell %s must sit inside the settled window aperture %s (needs aperture_pad top)" \
			% [p4._header_elem.rect(), aperture])
	p4.queue_free()

	print("\n=== AbilityPickerMenuTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] AbilityPickerMenuTest")
		get_tree().quit(1)
	else:
		print("[PASS] AbilityPickerMenu: nav + wrap + 5-row scroll + confirm/cancel + text-only rows")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
