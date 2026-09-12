extends Node
## TDD guard for THE VERTICAL COLOUR COLUMN (ADR-0089's vertical-column amendment) — the
## colour ribbon rotated to run down the side of the film strip, one row per thumbnail and
## one column per life frame inside it.
##
## What is invisible here, and therefore worth asserting:
##
##   * THE TWO MAPPINGS ARE INVERSES. `frame_at` (pixel → age) and `rect_of_frame`
##     (age → pixel) are separate walks over the same rows. A drift between them means
##     clicking one colour and editing another — which draws perfectly and looks like
##     nothing at all.
##   * A SUB-PIXEL COLUMN IS STILL REACHABLE. A 128-frame hold in a 22px band gives each
##     age 0.17px. The hit test is FRAME-addressed, not pixel-radius, precisely so those
##     do not become unclickable.
##   * THE DEAD ZONE. Douglas-Peucker always keeps the terminal sample, so every colour
##     emitter carries a keyframe at frame 159 that this column does not address. It must
##     be neither drawn nor hit, and counted rather than silently dropped.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/ColourLifeColumnTest.tscn

const Column = preload("res://src/effects/studio/ColourLifeColumn.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

var _passed: int = 0
var _failed: int = 0
var _sel_emit: int = -99
var _add_emit: int = -99
var _rm_emit: int = -99


func _ready() -> void:
	_test_a_single_frame_row_is_one_full_width_column()
	_test_a_multi_frame_row_splits_into_that_many_columns()
	_test_the_two_mappings_are_inverses_over_every_age()
	_test_a_click_outside_the_column_addresses_nothing()
	_test_a_sub_pixel_column_is_still_addressable()
	_test_row_of_frame_is_the_strips_link()
	_test_the_dead_zone_is_not_addressed_and_is_counted()
	_test_clicking_an_empty_column_SELECTS_and_never_adds()
	_test_clicking_a_keyframe_selects_it_and_a_second_click_deselects()
	_test_a_second_click_deselects_an_INTERPOLATED_age_too()
	_test_selection_is_keyframe_separates_the_two_states()
	_test_right_click_removes_only_a_real_keyframe()
	_test_the_declared_height_is_one_row_per_thumbnail()
	_test_a_wide_row_asks_for_the_width_its_ages_need()
	_test_the_band_never_outgrows_what_the_host_offers()
	_test_the_widest_row_sets_the_width_for_the_whole_column()
	_test_the_ages_a_grown_band_makes_reachable()
	_test_the_keyframe_mark_stays_inside_the_age_it_marks()

	print("\n=== ColourLifeColumnTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourLifeColumnTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourLifeColumnTest")
		get_tree().quit(0)


## 81.8% of corpus rows. One life frame, one column, the full band width — which is what
## makes "one colour per frameset" nearly true and is why the author expected it.
func _test_a_single_frame_row_is_one_full_width_column() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 1}, {"cell": 1, "start": 1, "ticks": 1}]
	_assert_eq(Column.rect_of_frame(0, rows, 34.0, 22.0), Rect2(0, 0, 22, 34),
		"row 0's single frame fills the band")
	_assert_eq(Column.rect_of_frame(1, rows, 34.0, 22.0), Rect2(0, 34, 22, 34),
		"row 1 sits one row-pitch below it")


## The author's own statement of the rule: *"if i held a keyframe for 3 frames i would get
## 3 columns in the row"*.
func _test_a_multi_frame_row_splits_into_that_many_columns() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 3}]
	_assert_eq(Column.rect_of_frame(0, rows, 30.0, 30.0), Rect2(0, 0, 10, 30), "age 0 is column 1 of 3")
	_assert_eq(Column.rect_of_frame(1, rows, 30.0, 30.0), Rect2(10, 0, 10, 30), "age 1 is column 2")
	_assert_eq(Column.rect_of_frame(2, rows, 30.0, 30.0), Rect2(20, 0, 10, 30), "age 2 is column 3")
	_assert_eq(Column.rect_of_frame(3, rows, 30.0, 30.0), Rect2(), "age 3 is not in this row")


## THE INVARIANT. Two independent walks over the same rows; if they ever disagree the author
## clicks one colour and edits another, and every pixel still looks right.
func _test_the_two_mappings_are_inverses_over_every_age() -> void:
	var bad := 0
	var checked := 0
	for durations in [[4, 4, 4], [2, 2], [4, 0], [1, 1, 1, 1], [8, 8], [6, 2, 2, 12]]:
		for life in [1, 2, 3, 7, 16, 40]:
			var rows := LifeMap.life_rows(_trace(durations), life)
			for w in [12.0, 22.0, 47.0]:
				for f in range(life):
					var r := Column.rect_of_frame(f, rows, 34.0, w)
					if r.size.x <= 0.0:
						continue
					checked += 1
					# Sample the centre of the cell — the pixel a click on it produces.
					if Column.frame_at(r.position + r.size * 0.5, rows, 34.0, w) != f:
						bad += 1
	print("  inverses: %d (age, width) cells round-tripped" % checked)
	_assert_eq(bad, 0, "frame_at(centre of rect_of_frame(f)) == f, over %d cells" % checked)


func _test_a_click_outside_the_column_addresses_nothing() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 1}]
	_assert_eq(Column.frame_at(Vector2(-1, 5), rows, 34.0, 22.0), -1, "left of the band")
	_assert_eq(Column.frame_at(Vector2(23, 5), rows, 34.0, 22.0), -1, "right of the band")
	_assert_eq(Column.frame_at(Vector2(5, -1), rows, 34.0, 22.0), -1, "above the first row")
	_assert_eq(Column.frame_at(Vector2(5, 40), rows, 34.0, 22.0), -1, "below the last row")


## A 128-frame hold exists in the corpus. At 22px that is 0.17px per age — invisible, but
## it must still be EDITABLE, which is why the hit test resolves a frame rather than
## searching for a marker within a pixel radius.
func _test_a_sub_pixel_column_is_still_addressable() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 128}]
	var hits := {}
	for px in range(22):
		var f := Column.frame_at(Vector2(float(px) + 0.5, 10.0), rows, 34.0, 22.0)
		hits[f] = true
		_assert_true(f >= 0 and f < 128, "pixel %d resolves to a real age (%d)" % [px, f])
	_assert_true(hits.size() >= 20,
		"a 22px band over 128 ages still reaches %d distinct ones" % hits.size())


func _test_row_of_frame_is_the_strips_link() -> void:
	var rows := LifeMap.life_rows(_trace([4, 4]), 4)
	_assert_eq(Column.row_of_frame(0, rows), 0, "age 0 is in row 0")
	_assert_eq(Column.row_of_frame(2, rows), 1, "age 2 is in row 1")
	_assert_eq(Column.row_of_frame(9, rows), -1, "an age past the column has no row")


## Every colour emitter in the corpus carries a keyframe at frame 159 (DP keeps the terminal
## sample) and the column addresses a median 16 ages. Those must be neither drawn nor hit —
## `rect_of_frame` returns a zero rect, which the draw loop skips — and counted, because
## dropping them without saying so is the other way to be wrong.
func _test_the_dead_zone_is_not_addressed_and_is_counted() -> void:
	var rows := LifeMap.life_rows(_trace([4, 4]), 4)
	var kfs := [{"frame": 0}, {"frame": 2}, {"frame": 40}, {"frame": 159}]
	_assert_eq(Column.rect_of_frame(159, rows, 34.0, 22.0), Rect2(),
		"a dead-zone keyframe has no rect, so it cannot paint outside the control")
	_assert_eq(Column.beyond_count(kfs, rows), 2, "and both are counted, not dropped silently")
	_assert_eq(Column.keyframe_at_frame(kfs, 2), 1, "a live one resolves by FRAME, not by pixel")
	_assert_eq(Column.keyframe_at_frame(kfs, 3), -1, "an age with no keyframe answers -1")


## SELECT IS NOT ADD (author, 2026-08-20: *"selecting frames is good but adding them by
## clicking them is not. there needs be a second step to lock it into being a keyframe
## instead of just a frame."*). The first build minted a keyframe on every click into an
## empty column, so browsing the colour of an age you were curious about permanently altered
## the curve. This control emits a SELECTION and nothing else; the ⬥ button on the picker is
## the only thing that mints.
func _test_clicking_an_empty_column_SELECTS_and_never_adds() -> void:
	var c = _column([{"cell": 0, "start": 0, "ticks": 3}], 3)
	c.frame_selected.connect(func(f): _sel_emit = f)
	_sel_emit = -99
	# w=22 over 3 columns is 7.33px each, so the MIDDLE one spans x 7.33..14.67.
	c._gui_input(_click(Vector2(11.0, 10.0), MOUSE_BUTTON_LEFT))
	_assert_eq(_sel_emit, 1, "clicking the middle column SELECTS age 1")
	_assert_eq(c.selected_frame(), 1, "…and the column holds it as the selected AGE")
	_assert_true(not c.selection_is_keyframe(),
		"…which is NOT a keyframe — nothing was minted by looking at it")
	c.queue_free()


func _test_clicking_a_keyframe_selects_it_and_a_second_click_deselects() -> void:
	var c = _column([{"cell": 0, "start": 0, "ticks": 3}], 3)
	c.set_keyframes([{"frame": 1, "color": Color.RED}])
	c.frame_selected.connect(func(f): _sel_emit = f)
	_sel_emit = -99
	c._gui_input(_click(Vector2(11.0, 10.0), MOUSE_BUTTON_LEFT))
	_assert_eq(_sel_emit, 1, "clicking a column that HAS a keyframe selects that AGE")
	_assert_true(c.selection_is_keyframe(), "…and it reports as a real keyframe")
	c._gui_input(_click(Vector2(11.0, 10.0), MOUSE_BUTTON_LEFT))
	_assert_eq(_sel_emit, -1, "and a second click deselects — the picker's close gesture")
	_assert_eq(c.selected_frame(), -1, "which the column reflects in its own highlight")
	c.queue_free()


## The deselect toggle works on ANY cell now. It used to fire only on keyframes, because a
## click into an empty column was spoken for by the add — losing that gesture is what buys
## this one, and an interpolated selection needs a way out as much as a keyframe does (it is
## what the picker's visibility is bound to).
func _test_a_second_click_deselects_an_INTERPOLATED_age_too() -> void:
	var c = _column([{"cell": 0, "start": 0, "ticks": 3}], 3)
	c.frame_selected.connect(func(f): _sel_emit = f)
	_sel_emit = -99
	c._gui_input(_click(Vector2(11.0, 10.0), MOUSE_BUTTON_LEFT))
	_assert_eq(_sel_emit, 1, "an interpolated age selects")
	c._gui_input(_click(Vector2(11.0, 10.0), MOUSE_BUTTON_LEFT))
	_assert_eq(_sel_emit, -1, "…and a second click on it deselects")
	c.queue_free()


## The two states the picker branches on — its title, its ⬥ button's enabled-ness, and
## whether a pick authors anything at all. They were the same question while only keyframes
## could be selected.
func _test_selection_is_keyframe_separates_the_two_states() -> void:
	var c = _column([{"cell": 0, "start": 0, "ticks": 3}], 3)
	c.set_keyframes([{"frame": 2, "color": Color.RED}])
	c.set_selected_frame(2)
	_assert_true(c.selection_is_keyframe(), "age 2 carries a keyframe")
	c.set_selected_frame(1)
	_assert_true(not c.selection_is_keyframe(), "age 1 does not")
	c.set_selected_frame(-1)
	_assert_true(not c.selection_is_keyframe(), "and nothing selected is not one either")
	c.queue_free()


func _test_right_click_removes_only_a_real_keyframe() -> void:
	var c = _column([{"cell": 0, "start": 0, "ticks": 3}], 3)
	c.set_keyframes([{"frame": 2, "color": Color.RED}])
	c.keyframe_remove_requested.connect(func(i): _rm_emit = i)
	_rm_emit = -99
	c._gui_input(_click(Vector2(3.0, 10.0), MOUSE_BUTTON_RIGHT))   # column 1, no keyframe
	_assert_eq(_rm_emit, -99, "right-clicking an empty column asks for nothing")
	c._gui_input(_click(Vector2(20.0, 10.0), MOUSE_BUTTON_RIGHT))  # column 3, has one
	_assert_eq(_rm_emit, 0, "right-clicking a real keyframe requests its removal")
	c.queue_free()


## The declared height is what keeps row i beside thumbnail i. A column that measured
## itself by life frames instead of rows would drift out of step with the strip the moment
## any cell held more than one frame — and still draw a plausible bar.
func _test_the_declared_height_is_one_row_per_thumbnail() -> void:
	var rows := LifeMap.life_rows(_trace([4, 0]), 40)   # 2 rows, the second holds 38 frames
	var c = _column(rows, 40)
	_assert_eq(c.row_count(), 2, "two rows")
	_assert_eq(c.frame_count(), 40, "…addressing all 40 ages between them")
	_assert_eq(c.custom_minimum_size.y, 68.0, "and the height is 2 x the strip's 34px pitch")
	c.queue_free()


## THE MINIMUM AGE WIDTH (author, 2026-08-21: *"sometimes for sprites which are just one
## frame and held things get crazy on the keyframes — can we maybe do a minimum width
## keyframes?"*).
##
## A row splits the band into one sub-column per life frame, so a row owning `t` ages draws
## each at `band / t`. E088 em1 is ONE row of 128 ages: **0.17px an age** at the fixed 22px
## band, where the keyframe mark alone is 5px of footprint. The band asks for
## `min_col_w * widest` now, bounded by what the host says there is room for.
func _test_a_wide_row_asks_for_the_width_its_ages_need() -> void:
	var one := [{"cell": 0, "start": 0, "ticks": 1}]
	_assert_eq(Column.wanted_band(one, 150.0), Column.band_width,
		"a single-age row wants nothing but the floor — 81.8%% of corpus rows are this")

	var six := [{"cell": 0, "start": 0, "ticks": 6}]
	_assert_eq(Column.wanted_band(six, 150.0), 6.0 * Column.min_col_w,
		"a 6-age row asks for 6 x the minimum")
	_assert_true(Column.wanted_band(six, 150.0) > Column.band_width,
		"…which is more than the floor, so the growth is what makes it legible")


## THE HOST'S CEILING IS A HARD BOUND, and that is the whole reason this is safe. The page's
## life slot is declared ONCE at build — a per-emitter bid would move the inspector's right
## edge, the complaint already answered twice — so a column that could widen past what it
## was offered would overflow a `ScrollContainer` with horizontal scrolling DISABLED and be
## clipped without saying so.
func _test_the_band_never_outgrows_what_the_host_offers() -> void:
	var huge := [{"cell": 0, "start": 0, "ticks": 128}]
	_assert_eq(Column.wanted_band(huge, 60.0), 60.0,
		"128 ages want 640px and take the 60 they are offered")
	_assert_eq(Column.wanted_band(huge, 1.0), Column.band_width,
		"a ceiling under the floor is not a floor — the band never goes below band_width")
	_assert_eq(Column.wanted_band(huge, 10000.0), Column.band_max,
		"and never past band_max, however much room there is")
	_assert_eq(Column.wanted_band([], 150.0), Column.band_width,
		"no rows is the floor, not a division by zero")

	# The default is the pre-amendment behaviour EXACTLY, which is what every caller with no
	# slot to ask still gets.
	var c = _column(huge, 128)
	_assert_eq(c.band(), Column.band_width,
		"configure without a ceiling is the fixed 22px band it always was")
	c.queue_free()


## ONE BAND PER COLUMN, SET BY ITS WIDEST ROW — never per row. Rows are drawn at a single
## width by construction (`_draw` divides `size.x`), so a per-row width would be a number the
## picture cannot express, and the alignment claim (row i IS thumbnail i) is about the
## vertical axis only.
func _test_the_widest_row_sets_the_width_for_the_whole_column() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 1},
		{"cell": 1, "start": 1, "ticks": 9},
		{"cell": 2, "start": 10, "ticks": 3}]
	_assert_eq(Column.wanted_band(rows, 150.0), 9.0 * Column.min_col_w,
		"the 9-age row sets it, not the 1-age one and not the average")

	var c = _column(rows, 13)
	c.configure(rows, [], 34.0, 150.0)
	_assert_eq(c.band(), 9.0 * Column.min_col_w, "and the column declares that width")
	_assert_eq(c.custom_minimum_size.x, 9.0 * Column.min_col_w,
		"…as its minimum, so the layout actually gives it to it")
	_assert_eq(c.custom_minimum_size.y, 34.0 * 3.0,
		"while the height is still one row per thumbnail — the two axes are independent")
	c.queue_free()


## WHAT THE WIDTH BUYS, in the only unit that matters: an age is selectable only if some
## INTEGER pixel floors to it, and `⬥` acts on the selection, so an unreachable age cannot be
## keyframed at all. Censused over 3,214 colour emitters, 3.8% have at least one such age and
## E088 em1 has 106 of its 128.
func _test_the_ages_a_grown_band_makes_reachable() -> void:
	var rows := [{"cell": 0, "start": 0, "ticks": 128}]
	var before := _reachable(rows, Column.band_width)
	var after := _reachable(rows, Column.wanted_band(rows, 187.0))
	_assert_eq(before, 22, "a 22px band over 128 ages reaches 22 of them, one per pixel")
	_assert_eq(after, 128, "the grown band reaches every one")
	_assert_true(after > before * 5, "%d -> %d ages" % [before, after])


## THE OTHER HALF OF THE SAME REPORT, and it is not fixed by width. The mark was a flat 3px
## bar with a 1px keyline grown around it — 5px of footprint — drawn at the left edge of a
## cell that can be a fraction of a pixel. Three adjacent keyframes on a 128-age row painted
## one 15px white block over 11 ages of colour, which is what "crazy" looked like.
func _test_the_keyframe_mark_stays_inside_the_age_it_marks() -> void:
	for cw in [0.17, 1.0, 1.4, 2.9, 3.0, 4.4, 22.0]:
		var cell := Rect2(Vector2(10.0, 0.0), Vector2(cw, 34.0))
		var mark: Rect2 = Column.mark_rect(cell)
		_assert_true(mark.size.x <= maxf(cell.size.x, 1.0) + 0.001,
			"a %.2fpx age draws a %.2fpx mark — never wider than itself" % [cw, mark.size.x])
		_assert_eq(mark.position, cell.position, "…anchored to the age's own left edge")
	_assert_eq(Column.mark_rect(Rect2(Vector2.ZERO, Vector2(22.0, 34.0))).size.x, 3.0,
		"where there IS room it is the full bar, unchanged")
	_assert_eq(Column.mark_rect(Rect2(Vector2.ZERO, Vector2(0.17, 34.0))).size.x, 1.0,
		"and a sub-pixel age still draws SOMETHING — invisible is not the fix")


func _reachable(rows: Array, width: float) -> int:
	var hit := {}
	for px in range(int(ceil(width))):
		var f := Column.frame_at(Vector2(float(px) + 0.5, 10.0), rows, 34.0, width)
		if f >= 0:
			hit[f] = true
	return hit.size()


# --- fixtures ---

func _trace(durations: Array) -> Array:
	var ops: Array = []
	for d in durations:
		ops.append({"type": "FRAME", "frameset": 0, "duration": int(d), "depth_mode": 0})
	return SequenceTimeline.trace({"opcodes": ops})


func _column(rows: Array, n_frames: int):
	var c = Column.new()
	add_child(c)
	var colors: Array = []
	for i in range(n_frames):
		colors.append(Color(float(i) / maxf(1.0, float(n_frames)), 0.5, 0.5, 1.0))
	c.configure(rows, colors, 34.0)
	c.size = Vector2(22.0, 34.0 * float(rows.size()))
	return c


func _click(pos: Vector2, button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = pos
	return ev


# --- harness ---

func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s\n        expected: %s\n        actual:   %s" % [msg, b, a])
