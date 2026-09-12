extends Node
## THE COLOUR SURFACE IN THE PLAYER COLUMN (ADR-0089 colour-move amendment, 2026-08-20;
## ADR-0100 dec. 1's occupant list grows by one).
##
## Replaces `ColourAuthorEditorTest`, whose subject — the inspector-built inline picker in a
## collapsible fold — was deleted by this amendment. What survives from it is decision 2 of
## the 2026-08-13 editing-UX amendment (the track HOSTS the ribbon so the coloured band is the
## click target), which is asserted below and is now the page's to build.
##
## What this guards, and why each one is invisible on screen:
##
##   * THE AXIS. The ribbon spans the particle's LIFE, not the animation's display length.
##     Both are plausible integers and both draw a plausible bar; of 2622 colour-enabled
##     corpus emitters they disagree for 1204, so the wrong one relocates every keyframe and
##     looks completely normal doing it.
##   * THE RESERVED SLOTS. `_canvas_chrome_h` and `_canvas_floor_w` skip invisible children,
##     so anything in the player panel that hides itself re-sizes the canvas square on
##     navigation. The colour track DOES hide itself (a colourless emitter), so its slot has
##     to declare the height — and the picker, at 439px, had to leave the panel entirely.
##   * THE PROJECTION. A strip cell whose opcode the particle never reaches must refuse,
##     not clamp. 324 corpus emitters (12.4%) have such cells.
##
## Run: <GODOT> --path . --quit-after 900 res://tests/EffectStudioColourColumnTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Column = preload("res://src/effects/studio/ColourLifeColumn.gd")
const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const LifeMap = preload("res://src/effects/studio/SequenceLifeMap.gd")

var _passed: int = 0
var _failed: int = 0
## Which tests RAN TO THE END — a GDScript coroutine that hits a runtime error aborts
## silently, taking its remaining assertions with it and still reporting `0 failed`.
var _completed: Dictionary = {}
const _EXPECTED_TESTS := ["track_hosts_ribbon", "axis_is_life", "slots_declared",
	"picker_is_its_own_panel", "picker_two_states", "picker_closes", "strip_projects",
	"select_or_add", "key_button_reachable", "wrap_arithmetic"]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run" % name)
	print("\n=== EffectStudioColourColumnTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioColourColumnTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioColourColumnTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E009")):
		print("[SKIP] E009 assets not available — colour column guard skipped")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	_assert_true(page != null, "the studio page exists")
	if page == null:
		return
	DebugOverlay.show_overlay()
	await _frames(30)
	# The dashboard's own UI Scale, the one lever the tiling WM does not refuse (`Window.size`
	# is). Without it this harness lays out a ~237px inspector row, which has no slack under
	# the player at all — so the picker could never claim a height and the conditional-panel
	# assertions below would pass vacuously on a panel that is hidden for the wrong reason.
	var dash = page._body.get_viewport()
	if dash is Window:
		(dash as Window).content_scale_factor = 0.55
	await _frames(30)
	await _settle(page._body, "the dashboard body")

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E009"):
			dir = d
	if dir == "":
		print("[SKIP] E009 not in the catalogue")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return
	# E009, not E019: the reserved-slot assertion needs BOTH a colour-enabled emitter and a
	# colourless one on the same effect, so the navigation between them can be watched for a
	# canvas that moves. E009 is 1 lit of 11; 205 of the 401 corpus effects carry both.
	page._load_effect(dir)
	await _frames(40)
	await _settle(page._body, "the dashboard body after loading E009")

	var data = page._effect_data
	# Find a colour-ENABLED emitter and, separately, a colourless one — the pair is what
	# makes the reserved-slot assertions mean anything.
	var lit := -1
	var dark := -1
	for i in range(data.emitters.size()):
		page._set_root(Target.emitter(i))
		await _frames(12)
		if page._sequence_life_column != null and page._sequence_life_column.visible:
			if lit < 0:
				lit = i
		elif dark < 0:
			dark = i
		if lit >= 0 and dark >= 0:
			break
	if lit < 0:
		print("[SKIP] no colour-enabled emitter in E009 (checked %d)" % data.emitters.size())
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	page._set_root(Target.emitter(lit))
	await _frames(24)
	await _settle(page._body, "the body on the colour emitter")

	# --- THE RIBBON IS A COLUMN BESIDE THE PLAYER, not a band under it -------------
	# ADR-0089's vertical-column amendment. The claim this suite exists to hold is that row
	# i of the ribbon IS thumbnail i — an alignment that is either exact or invisible, since
	# a mis-stepped column still draws a perfectly plausible ramp.
	var col = page._sequence_life_column
	var ribbon = page._sequence_ribbon
	_assert_true(col != null and ribbon != null, "the page built the life column and a resolver")
	if col == null or ribbon == null:
		return
	_assert_true(page._sequence_life_slot.get_parent() == page._sequence_body,
		"the column's slot is a HORIZONTAL sibling of the canvas, not a row under it")
	_assert_true(page._sequence_canvas.get_parent() == page._sequence_body,
		"…and the canvas is in that same row")
	_assert_true(not ribbon.visible,
		"the old horizontal band is headless now — it resolves colours, it does not draw")
	_assert_true(absf(col.size.x - Column.band_width) <= 0.5,
		"the ribbon is its DECLARED width (%.0f, wanted %.0f)" % [col.size.x, Column.band_width])
	_done("track_hosts_ribbon")

	# --- ROW i IS THUMBNAIL i, in pixels ------------------------------------------
	# Not "the counts match" — two lists of the same length can still be one row out of
	# step, and that is exactly the failure this whole placement was chosen to make
	# impossible. Compare the actual y of each row's rect against the actual y of the
	# thumbnail beside it.
	var rows: Array = page._sequence_life_rows
	_assert_true(rows.size() > 0, "the emitter resolved a life column (%d rows)" % rows.size())
	# ACROSS EVERY COLUMN, since the wrap (2026-08-20). The old form asked column 0 whether it
	# carried every row, which the wrap makes false BY DESIGN — so it is asked of the columns
	# TOGETHER, which is the same claim and survives the layout change. Asserting the sum is
	# also what catches the failure the wrap actually introduces: a slice arithmetic that
	# drops or duplicates a row would still leave every individual column looking sane.
	var carried: int = 0
	for lc in page._sequence_life_columns:
		carried += (lc as Object).row_count()
	_assert_eq(carried, rows.size(),
		"the columns together carry every row exactly once (%d of %d, in %d columns)"
		% [carried, rows.size(), int(page._strip_split.get("cols", 0))])
	# …AND IN PIXELS. Not "the counts match" — two lists of the same length can still be one
	# row out of step, and that is exactly the failure this whole placement was chosen to make
	# impossible. GLOBAL y, not local: a wrapped cell's local y is relative to its own column,
	# so row 20 in column 2 and row 8 in column 1 share a local y and a local comparison would
	# pass while the picture was wrong. Global also catches a column whose ribbon and strip
	# have drifted apart from EACH OTHER, which local never could.
	var drift: int = 0
	var compared: int = 0
	for k in range(page._sequence_life_columns.size()):
		var lc = page._sequence_life_columns[k]
		var vb: Control = page._sequence_strip_rows[k]
		var slice: Array = lc._rows
		for i in range(mini(slice.size(), vb.get_child_count())):
			var thumb := vb.get_child(i) as Control
			if thumb == null:
				continue
			var r: Rect2 = Column.rect_of_frame(int(slice[i]["start"]), slice,
				SequenceThumbnail.SIDE, lc.size.x)
			compared += 1
			if absf((lc.global_position.y + r.position.y) - thumb.global_position.y) > 1.0:
				drift += 1
	_assert_true(compared > 0, "there were rows to compare (%d)" % compared)
	_assert_eq(compared, rows.size(),
		"…and EVERY row was compared, not just column 0's share (%d of %d)"
		% [compared, rows.size()])
	_assert_eq(drift, 0, "every ribbon row sits at its thumbnail's y (%d compared, %d columns)"
		% [compared, int(page._strip_split.get("cols", 0))])
	_done("axis_is_life")

	# --- the column IS the life: no zero-dwell cells, and every age addressed ------
	var trace: Array = page._sequence_canvas.get_trace()
	var want: Dictionary = LifeWindow.resolve(data, lit)
	_assert_true(int(page._sequence_colour_window.get("n", -1)) == int(want["n"]),
		"the column stamped the LIFE window (%d)" % int(want["n"]))
	_assert_true(page._sequence_colour_emitter == lit,
		"…against the emitter it is actually about (%d)" % lit)
	var frames_carried: int = 0
	for lc in page._sequence_life_columns:
		frames_carried += (lc as Object).frame_count()
	_assert_eq(frames_carried, int(want["n"]),
		"the rows partition the whole life — every age has exactly one column, and the wrap "
		+ "did not lose or double one (%d of %d across %d columns)"
		% [frames_carried, int(want["n"]), int(page._strip_split.get("cols", 0))])
	var zero_dwell: int = 0
	for c in trace:
		if int(c.get("ticks", 0)) <= 0:
			zero_dwell += 1
	if zero_dwell > 0:
		_assert_true(rows.size() <= trace.size() - zero_dwell,
			"the %d zero-dwell cells hold no age, so they get no row (%d rows, %d cells)"
			% [zero_dwell, rows.size(), trace.size()])
	else:
		print("  [NOTE] this sequence has no zero-dwell cells — that arm is unexercised")
		_passed += 1

	# --- THE SLOT IS RESERVED, and it declares WIDTH now --------------------------
	# The dimension changed with the placement; the reason did not. `_canvas_chrome_h` and
	# `_canvas_floor_w` both skip invisible children, so an occupant that hid itself would
	# re-size the player's square the moment the author browsed to a colourless sequence.
	var square_before: Vector2 = page._sequence_canvas.size
	var slot_before: Vector2 = page._sequence_life_slot.custom_minimum_size
	_assert_true(slot_before.x > 0.0 and slot_before.y == 0.0,
		"the slot declares a WIDTH (%.0f) and lets its height be the panel's" % slot_before.x)
	if dark >= 0:
		page._set_root(Target.emitter(dark))
		await _frames(24)
		await _settle(page._body, "the body on the colourless emitter")
		_assert_true(not page._sequence_life_column.visible,
			"a colourless emitter hides the ribbon (there is nothing to author)")
		_assert_true(page._sequence_life_slot.custom_minimum_size == slot_before,
			"…but its SLOT keeps its declared width — chrome measurement skips invisible "
			+ "children, so a bare column would re-size the square on navigation")
		_assert_true(page._sequence_canvas.size == square_before,
			"…and the canvas square is unmoved (%s)" % str(page._sequence_canvas.size))
		_assert_true(page._sequence_strip_cells.size() > 0,
			"…and the film strip is still there: it is the sequence's picture first and the "
			+ "colour surface's ruler second")
		page._set_root(Target.emitter(lit))
		await _frames(24)
		await _settle(page._body, "the body back on the colour emitter")
	else:
		print("[NOTE] every E009 emitter has colour — the colourless half is unexercised")
		_passed += 1
	_done("slots_declared")

	# --- the picker is its OWN panel, not a row inside the player's ---
	_assert_true(page._colour_picker_panel != null, "the picker panel is built")
	_assert_true(page._colour_picker_panel.get_parent() == page._body,
		"…as a SIBLING of the player panel: inside it, `_canvas_chrome_h` would measure its "
		+ "439px and swing the square by that much on every selection")
	_assert_true(page._colour_picker.get_combined_minimum_size().x <= Page.picker_panel_w,
		"the declared width covers what Godot's ColorPicker actually insists on (%.0f)"
		% page._colour_picker.get_combined_minimum_size().x)
	_done("picker_is_its_own_panel")

	# --- ⬥ IS REACHABLE, which is not the same as ⬥ existing ------------------------
	# Author, 2026-08-20: *"I don't see where I toggle key frame on and off. You said there
	# was a button - but I don't see it."* It WAS on screen and it WAS inside the panel and
	# every assertion in this suite passed — the defect was that it was the LAST child under
	# a 439px wall of colour, at y=1019 of a 1069px body. So "the button exists and is
	# enabled" is a guard that agrees with both answers; these are about WHERE it is.
	#
	# Three separate failures are covered, and each one alone loses the gesture:
	#   1. ORDER. Below the grid, the button rides on the panel's ~61px of content overflow
	#      and lands off the bottom of the display.
	#   2. THE HEADER FLOOR. `picker_head_h` is what the panel degrades to; if the real
	#      title+button minimum exceeds it, the "degraded" panel silently overflows again
	#      and we are back to case 1 with extra steps.
	#   3. THE VISIBILITY RULE. `picker_h > 0` off a raw slack hid the panel outright on a
	#      short row. Since ADR-0089 dec. 5 retired click-to-add, that is the whole gesture
	#      gone, decided by the window's height. Swept as a pure function because a live
	#      layout test cannot reach a negative slack.
	var pv_kids: Array = page._colour_key_button.get_parent().get_children()
	_assert_true(pv_kids.find(page._colour_key_button) < pv_kids.find(page._colour_picker),
		"⬥ is ABOVE the colour grid in the panel's VBox (button at %d, grid at %d)"
		% [pv_kids.find(page._colour_key_button), pv_kids.find(page._colour_picker)])
	# SETTLE, DON'T SLEEP. A container recomputes its minimum on a deferred pass, so a fixed
	# `await _frames(4)` here read the panel's FULL minimum (~500) on a loaded machine and
	# reported the header floor as broken — a flake that fails the two assertions below and
	# says nothing true about either. Poll until the hide has actually landed, and say so
	# separately if it never does, so a settle failure cannot be read as a floor failure.
	var pv: Control = page._colour_key_button.get_parent()
	var was_grid: bool = page._colour_picker.visible
	page._colour_picker.visible = false
	var head_min: float = pv.get_combined_minimum_size().y
	for _i in range(120):
		await get_tree().process_frame
		head_min = pv.get_combined_minimum_size().y
		if head_min < Page.picker_panel_h:
			break
	page._colour_picker.visible = was_grid
	_assert_true(head_min < Page.picker_panel_h,
		"hiding the grid shrinks the panel's minimum at all — the degraded panel is a real "
		+ "state and not a repaint of the full one (got %.0f)" % head_min)
	_assert_true(head_min <= Page.picker_head_h,
		"the declared header floor covers the real title+⬥ minimum (%.0f <= %.0f)"
		% [head_min, Page.picker_head_h])
	# The sweep. Every slack from far-negative to far-past the grid must yield a height that
	# can still draw the header — there is no slack at which the gesture is unavailable.
	var never_zero: bool = true
	var flipped_once: bool = false
	var prev_fits: bool = Page.colour_picker_grid_fits(-400.0)
	for slack_i in range(-400, 1200, 8):
		var h: float = Page.colour_picker_height(float(slack_i))
		if h < head_min:
			never_zero = false
		var fits: bool = Page.colour_picker_grid_fits(float(slack_i))
		if fits != prev_fits:
			flipped_once = true
			prev_fits = fits
	_assert_true(never_zero,
		"across 200 slacks from -400 to 1200 the panel never falls below the header — the "
		+ "keyframe gesture is not a function of the window's height")
	_assert_true(flipped_once and Page.colour_picker_grid_fits(Page.picker_panel_h)
		and not Page.colour_picker_grid_fits(Page.picker_panel_h - 1.0),
		"…and the grid still drops exactly at the height it declares (%.0f)"
		% Page.picker_panel_h)
	# The keyboard half. K is the ⬥ button's peer and is gated on the same fact, so a
	# selection that offers the button offers K and one that does not offers neither.
	_assert_true(Page._is_colour_key_shortcut(_key(KEY_K)),
		"a bare K is the colour-key shortcut")
	_assert_true(not Page._is_colour_key_shortcut(_key(KEY_K, true)),
		"…and Ctrl+K is NOT — modifiers are excluded, not ignored")
	_assert_true(not Page._is_colour_key_shortcut(_key(KEY_J)),
		"…and J is not either")
	_done("key_button_reachable")

	# --- THE WRAP'S ARITHMETIC, swept ------------------------------------------------
	# Author, 2026-08-20: *"I don't want to have to scroll to see all the thumb nails. I just
	# want them to form another row on the right."* Pure and static, so the whole space is
	# reachable — including the shapes a live page cannot be made to produce on demand (a
	# 75-row emitter, a zero-height slot, a window narrower than one column).
	#
	# THE HEADLINE IS THAT WRAPPING DOES NOT REMOVE SCROLLING, and the author priced that
	# before choosing it. Corpus rows are median 9, p90 22, p99 35, max 75; three columns of
	# ~12 cover the 99th percentile and the tail scrolls. Asserted so the trade stays visible
	# rather than becoming a surprise the next time someone reads "it wraps".
	var cap: int = 12
	var lim: int = 3
	_assert_eq(Page.strip_columns(9, cap, lim), {"cols": 1, "per": 9},
		"the MEDIAN emitter (9 rows) still fits one column — the common case is unchanged")
	_assert_eq(Page.strip_columns(22, cap, lim), {"cols": 2, "per": 11},
		"p90 (22 rows) takes two BALANCED columns, not one full and one nearly empty")
	_assert_eq(Page.strip_columns(35, cap, lim), {"cols": 3, "per": 12},
		"p99 (35 rows) takes all three and still does not scroll")
	var tail: Dictionary = Page.strip_columns(75, cap, lim)
	_assert_eq(int(tail["cols"]), 3, "the MAX emitter (75 rows) is capped at three columns")
	_assert_true(int(tail["per"]) > cap,
		"…and therefore SCROLLS (%d rows in a column that shows %d) — wrapping does not "
		% [int(tail["per"]), cap] + "remove scrolling, it removes it for the first 99%")
	_assert_eq(Page.strip_columns(0, cap, lim), {"cols": 1, "per": 0},
		"an empty strip is one empty column, never a division by zero")
	# A sweep across every shape, for the two properties that must never break: no cell is
	# lost, and the column count never exceeds the limit. `cols * per >= count` is what says
	# the last column reaches the end.
	var lost: int = 0
	var over: int = 0
	for count in range(0, 120):
		for c2 in [1, 3, 12, 40]:
			for l2 in [1, 2, 3]:
				var sp: Dictionary = Page.strip_columns(count, c2, l2)
				if int(sp["cols"]) * int(sp["per"]) < count:
					lost += 1
				if int(sp["cols"]) > l2 or int(sp["cols"]) < 1:
					over += 1
	_assert_eq(lost, 0, "across 1440 shapes the columns always reach the last cell")
	_assert_eq(over, 0, "…and never exceed the limit the width affords, or fall below one")
	# THE WIDTH SIDE. The slot's declared minimum stays ONE column — raising it is how the
	# player panel stops being able to shrink and lands on the inspector, which is the exact
	# failure ADR-0100 dec. 2's clamp exists to make unrepresentable.
	_assert_eq(page._sequence_life_slot.custom_minimum_size.x, Page.sequence_life_column_w(),
		"the slot still declares ONE column as its minimum, whatever the wrap wants")
	_assert_true(Page.sequence_life_slot_w(3) < Page.sequence_life_column_w() * 3.0,
		"three columns cost LESS than three times one (%.0f vs %.0f) — the scrollbar is paid "
		% [Page.sequence_life_slot_w(3), Page.sequence_life_column_w() * 3.0]
		+ "once for the whole scroller, not once per column")
	_assert_eq(Page.life_columns_affordable(Page.sequence_life_slot_w(3)), 3,
		"a slot sized for three shows three")
	_assert_eq(Page.life_columns_affordable(Page.sequence_life_slot_w(1)), 1,
		"…and a slot sized for one shows one, rather than clipping a second")
	_assert_eq(Page.life_columns_affordable(0.0), 1,
		"a zero-width slot still reports one — never zero, which would be ceil(n/0) columns")
	var mono: bool = true
	var prev_n: int = 0
	for wpx in range(0, 400, 2):
		var got: int = Page.life_columns_affordable(float(wpx))
		if got < prev_n:
			mono = false
		prev_n = got
	_assert_true(mono, "columns afforded never DECREASE as the slot widens")

	# --- THE BAND'S CEILING (2026-08-21) -----------------------------------------------
	# `life_band_ceiling` is `sequence_life_slot_w` solved for the band instead of for the
	# slot, and the two ends of that one formula are what makes the growth affordable: THREE
	# pairs afford exactly `band_width`, so the constant it replaces is this function's own
	# answer at the crowded end. A band that grew past the ceiling would overflow a
	# ScrollContainer with horizontal scrolling DISABLED and clip without saying so.
	_assert_eq(Page.life_band_ceiling(Page.sequence_life_slot_w(3), 3), Column.band_width,
		"three pairs in the slot they were sized for afford exactly the floor — 22px")
	_assert_eq(Page.life_band_ceiling(Page.sequence_life_slot_w(1), 1), Column.band_width,
		"…and so does one pair in a slot sized for one")
	_assert_true(Page.life_band_ceiling(Page.sequence_life_slot_w(3), 1) > Column.band_width * 5.0,
		"but ONE pair inside the THREE-pair slot affords %.0fpx — the width a wrap that "
			% Page.life_band_ceiling(Page.sequence_life_slot_w(3), 1)
		+ "did not happen leaves on the floor, and the whole reason the band can grow at all")
	_assert_eq(Page.life_band_ceiling(0.0, 1), Column.band_width,
		"a zero-width slot still offers the floor, never a negative ceiling")
	# The arithmetic that makes it land: a row is WIDE exactly when there are FEW rows,
	# because rows x ticks ~= life_n. Few rows is few pairs is a bigger ceiling.
	var prev_ceiling: float = 1e9
	var ceilings_fall: bool = true
	for c in [1, 2, 3]:
		var got: float = Page.life_band_ceiling(Page.sequence_life_slot_w(3), c)
		if got > prev_ceiling:
			ceilings_fall = false
		prev_ceiling = got
	_assert_true(ceilings_fall,
		"the more pairs a strip uses, the less each may take — one slot, shared")

	# --- AND THE LIVE WRAP, in pixels ------------------------------------------------
	# EVERY KEYFRAME LANDS IN EXACTLY ONE COLUMN. The selection and the keyframe list are
	# BROADCAST to all three columns — they are facts about an AGE, not about a column — and
	# the only thing making that safe is that `rect_of_frame` returns an empty rect for an
	# age outside a column's slice. If a slice were ever wrong in the overlapping direction,
	# the same keyframe would be marked in two columns and the picture would look busy rather
	# than broken. Ages past the particle's life resolve in NO column, which is correct and
	# is what the slot's "%d past this particle's life" tooltip is about.
	var doubled: int = 0
	var placed: int = 0
	for kf in page._colour_keyframes:
		var f: int = int(kf.get("frame", -1))
		var hits: int = 0
		for lc2 in page._sequence_life_columns:
			if (lc2 as Object).rect_of_frame(f, lc2._rows, SequenceThumbnail.SIDE,
					lc2.size.x).size.x > 0.0:
				hits += 1
		if hits > 1:
			doubled += 1
		if hits == 1:
			placed += 1
	_assert_eq(doubled, 0,
		"no keyframe is marked in two columns at once (%d keyframes, %d placed, %d beyond "
		% [page._colour_keyframes.size(), placed, page._colour_keyframes.size() - placed]
		+ "the particle's life)")
	# THE COLUMNS DO NOT LAND ON THE PLAYER'S SQUARE. The strip lives to the RIGHT of the box
	# (ADR-0089 dec. 4), and the wrap grows it rightwards into width the bid asked for — so
	# the failure to watch for is the columns growing LEFTWARDS over the render instead,
	# which a screenshot of a dark thumbnail on a dark canvas would not obviously show.
	var sq: Rect2 = page._sequence_canvas.get_global_rect()
	var on_square: int = 0
	if sq.size.x > 0.0:
		for pr in page._sequence_life_pairs:
			var prc := pr as Control
			if prc.visible and prc.get_global_rect().size.x > 0.0 \
					and prc.global_position.x < sq.end.x - 1.0:
				on_square += 1
		_assert_eq(on_square, 0,
			"no column overlaps the player's square (square ends at %.0f)" % sq.end.x)
	else:
		print("  [SKIP] the square has no width at this window — the overlap check is "
			+ "unmeasured")
		_passed += 1
	_done("wrap_arithmetic")

	# --- the picker APPEARS ON A SELECTION, and the square does not hear about it ---
	#
	# This is the author's ask verbatim ("the color picker should only appear when a keyframe
	# is selected") and it is only affordable because the picker is a sibling panel. The
	# first build kept it up permanently on the theory that a hiding picker would swing
	# `_canvas_chrome_h` — true INSIDE the player panel, false for a sibling — and the cost
	# was the ADR-0102 frameset block, which stopped appearing at all: at a 1069px body the
	# column's slack under the player is 327 and a permanent 439px picker left the block
	# 16px, under its 64px collapse floor. Reported as "when I click on a thumbnail I don't
	# see the frameset controls now".
	page._colour_selected_frame = -1
	page._update_colour_picker_panel()
	await _frames(20)
	var square_idle: Vector2 = page._sequence_canvas.size
	var focus_idle: bool = page._focus_panel != null and page._focus_panel.visible
	_assert_true(not page._colour_picker_panel.visible,
		"no selection → the picker panel is not up, and its height is back in the column")
	# A CLICK IS A (row, column) NOW, so the fixture resolves the age's rect through the
	# column's own geometry and clicks its centre — the same pixel the author's mouse lands
	# on. Picking an x from a linear axis, as this suite used to, would address a different
	# age on any row that holds more than one frame.
	var n: int = col.frame_count()
	var age: int = clampi(int(n * 0.5), 1, maxi(1, n - 1))
	var cell: Rect2 = Column.rect_of_frame(age, rows, SequenceThumbnail.SIDE, col.size.x)
	_assert_true(cell.size.x > 0.0, "age %d has a cell on the column" % age)
	var kf_before: int = page._colour_keyframes.size()
	col._gui_input(_click_at(cell.position + cell.size * 0.5))
	await _frames(24)
	_assert_true(page._colour_selected_frame == age,
		"clicking the column selected age %d (got %d)" % [age, page._colour_selected_frame])

	# --- SELECT IS NOT ADD, and the ⬥ button is the second step ---------------------
	# Author, 2026-08-20: *"selecting frames is good but adding them by clicking them is not.
	# there needs be a second step to lock it into being a keyframe instead of just a frame."*
	# The whole point is a state that could not exist before — an age that is SELECTED and is
	# NOT a keyframe — so every assertion here is about that state existing and being safe.
	_assert_eq(page._colour_keyframes.size(), kf_before,
		"the click minted NOTHING — browsing an age must not alter the curve")
	_assert_true(page._colour_picker_wanted(),
		"…but the picker is wanted, because an age IS selected")
	if page._colour_index_of_frame(age) < 0:
		_assert_true(not col.selection_is_keyframe(), "the selected age is interpolated")
		_assert_true(page._colour_key_button != null and not page._colour_key_button.disabled,
			"⬥ Set keyframe is OFFERED on an interpolated age")
		_assert_true(str(page._colour_picker_title.text).ends_with("interpolated"),
			"…and the title says which state this is (got '%s')" % page._colour_picker_title.text)
		# A PICK IS A PREVIEW HERE. The author was shown that this means dragging the picker
		# changes nothing on screen and chose it anyway: *nothing keys implicitly*.
		page._on_colour_authored(Color(0.25, 0.5, 0.75, 1.0))
		await _frames(12)
		_assert_eq(page._colour_keyframes.size(), kf_before,
			"picking a colour on an interpolated age authors nothing until ⬥ is pressed")
		# …and now the second step.
		page._colour_key_button.pressed.emit()
		await _frames(30)
		_assert_true(page._colour_keyframes.size() == kf_before + 1,
			"⬥ locks it in (%d → %d keyframes)" % [kf_before, page._colour_keyframes.size()])
		_assert_true(page._colour_index_of_frame(age) >= 0,
			"…as a real keyframe at the age that was selected (%d)" % age)
		_assert_true(page._colour_key_button.disabled,
			"…and the button goes to its state form — there is nothing left to set")
	else:
		print("  [NOTE] age %d already carried a keyframe — the two-step arm is unexercised" % age)
		_passed += 1

	# --- THE PICKER HAS THREE WAYS OUT (2026-08-20; "how do I close the color picker?") ---
	# Asserted HERE, before the slack-dependent skip below, because none of these three
	# depend on the column having room for the panel — they are about the SELECTION, which
	# is what the panel's visibility is bound to. Put after that skip they would go
	# unmeasured on exactly the short windows where the harness usually runs.
	var kf_at: Vector2 = cell.position + cell.size * 0.5
	col._gui_input(_click_at(kf_at))
	await _frames(12)
	_assert_true(page._colour_selected_frame == -1,
		"1/3 a second click on the selected column deselects (got %d)" % page._colour_selected_frame)
	_assert_true(not page._colour_picker_wanted(), "…and the picker is no longer wanted")

	col._gui_input(_click_at(kf_at))
	await _frames(12)
	_assert_true(page._colour_selected_frame == age, "re-selected for the Esc arm")
	_assert_true(page._clear_colour_selection(),
		"2/3 Esc's colour stage reports it cleared a real selection")
	await _frames(12)
	_assert_true(page._colour_selected_frame == -1, "…and the selection is gone")
	_assert_true(col.selected_frame() == -1,
		"…and the COLUMN dropped its highlight too (a half-closed picker is the same bug)")
	_assert_true(not page._clear_colour_selection(),
		"…a second Esc finds nothing to clear, so it falls through to deselect")

	col._gui_input(_click_at(kf_at))
	await _frames(12)
	_assert_true(page._colour_selected_frame == age, "re-selected for the deselect arm")
	page._deselect()
	await _frames(12)
	_assert_true(page._colour_selected_frame == -1,
		"3/3 dropping the whole target drops its colour sub-selection with it")
	_done("picker_closes")

	# Restore the selection the conditional-panel assertions below are about.
	page._set_root(Target.emitter(lit))
	await _frames(24)
	col = page._sequence_life_column
	rows = page._sequence_life_rows
	n = col.frame_count()
	age = clampi(int(n * 0.5), 1, maxi(1, n - 1))
	cell = Column.rect_of_frame(age, rows, SequenceThumbnail.SIDE, col.size.x)
	col._gui_input(_click_at(cell.position + cell.size * 0.5))
	await _frames(24)

	if not page._colour_picker_panel.visible:
		# Skip WITH THE NUMBERS (the house rule for this harness): a row this short has no
		# slack under the player for the picker to claim, so its absence says nothing.
		print("  [SKIP] no column slack at this window (row %.0f, player box %.0f) — the "
			% [page._inspector.size.y, page._sequence_panel.size.y]
			+ "conditional-panel assertions are unmeasured")
		_passed += 1
		_done("picker_two_states")
		return
	# THE PANEL HAS TWO LEGAL SHAPES and both are asserted, because the short one is the one
	# this harness's window actually produces — an arm that only ran on a tall window would
	# be an arm that never ran. NOTE THE FALL-THROUGH: an early `return` here skipped every
	# assertion in the rest of the suite and reported `0 failed` doing it. The completion
	# flags caught it; nothing else would have.
	if page._colour_picker.visible:
		# THE INVARIANT THE WHOLE PLACEMENT EXISTS FOR. A conditional panel is only safe
		# here because `_canvas_chrome_h` measures the player panel's own children and this
		# is not one; if the picker ever moves back inside that panel, this fails.
		#
		# Gated on `square_idle` having been a real measurement: this harness's window is
		# not stable run to run, and a `square_idle` of (260, 0) means the canvas had not
		# laid out when it was taken, not that the square moved. Comparing against it
		# reported a drift that was never there.
		if square_idle.y > 0.0:
			_assert_true(page._sequence_canvas.size == square_idle,
				"…and the canvas square is UNMOVED across the appear (%s vs %s)"
				% [str(page._sequence_canvas.size), str(square_idle)])
		else:
			print("  [SKIP] the square had not laid out when the idle reading was taken — "
				+ "the unmoved-across-the-appear assertion is unmeasured at this window")
			_passed += 1
	else:
		# THE DEGRADED PANEL, asserted rather than skipped. A window too short for the 439px
		# grid is exactly the case that used to hide the whole panel and take the only
		# keyframe-minting gesture with it, so what has to hold here is that ⬥ survived.
		_assert_true(page._colour_key_button.visible
			and page._colour_key_button.get_global_rect().size.y > 0.0,
			"the grid does not fit at this window and ⬥ is STILL on screen — the header "
			+ "floor is the whole point of the three-way height")
		_assert_true(page._colour_picker_panel.size.y <= Page.picker_head_h + 4.0,
			"…and the panel collapsed to its header (%.0f) instead of overflowing the column"
			% page._colour_picker_panel.size.y)
	if focus_idle:
		print("  [NOTE] the frameset block was up with no selection and yields to the "
			+ "picker while authoring — the column's slack cannot hold both")
		_passed += 1
	else:
		print("  [NOTE] this window is too short for the frameset block either way "
			+ "(row %.0f) — the yield is unmeasured here" % page._inspector.size.y)
		_passed += 1
	_done("picker_two_states")

	# --- THE STRIP IS THE LIFE, THEN THE CELLS THAT NEVER PLAY ---------------------
	# The old assertion here was `life_frames.size() == strip.get_child_count()`, one
	# projection per opcode. That is no longer the layout and, more to the point, it could
	# not express what the strip now says: the first `rows.size()` children ARE the life, in
	# order, and any cell the particle never reaches follows them dimmed (author's call,
	# "show both, marked"). 374 corpus emitters (14.3%) have such cells.
	trace = page._sequence_canvas.get_trace()
	rows = page._sequence_life_rows
	var reached: Dictionary = {}
	for r in rows:
		reached[int(r["cell"])] = true
	var want_dead: int = 0
	for i in range(trace.size()):
		if not reached.has(i) and int(trace[i].get("ticks", 0)) > 0:
			want_dead += 1
	_assert_eq(page._sequence_strip_cells.size(), rows.size() + want_dead,
		"the strip is %d life rows plus %d cells the particle never reaches"
		% [rows.size(), want_dead])
	# EVERY CELL IS PARENTED TO EXACTLY ONE COLUMN. The wrap moves cells between VBoxes, and
	# a slice arithmetic that skipped an index would leave a thumbnail built, alive, holding
	# its subscriptions — and simply not on screen. Nothing about the picture would look
	# wrong; there would just be one fewer frame than the sequence has.
	var parented: int = 0
	for vb in page._sequence_strip_rows:
		parented += (vb as Control).get_child_count()
	_assert_eq(parented, page._sequence_strip_cells.size(),
		"…and every one of them is in a column (%d parented of %d built)"
		% [parented, page._sequence_strip_cells.size()])
	var lit_bright: int = 0
	for i in range(rows.size()):
		var live_cell := page._sequence_strip_cells[i] as Control
		if live_cell != null and live_cell.modulate.a >= 0.9:
			lit_bright += 1
	_assert_eq(lit_bright, rows.size(), "every life row's thumbnail is drawn at full strength")
	var dimmed: int = 0
	for i in range(rows.size(), page._sequence_strip_row.get_child_count()):
		var dead_cell := page._sequence_strip_row.get_child(i) as Control
		if dead_cell != null and dead_cell.modulate.a < 0.9:
			dimmed += 1
	if want_dead > 0:
		_assert_eq(dimmed, want_dead,
			"…and every unreachable cell after them is dimmed (%d)" % want_dead)
	else:
		print("  [NOTE] this particle reaches every opcode — the dimmed arm is unexercised")
		_passed += 1
	var frames: Array = LifeMap.life_frames(trace, int(want["n"]))
	_done("strip_projects")

	# --- right-click a strip_cell: SELECT the keyframe there, or ADD one; never duplicate ---
	var reachable: int = -1
	for i in range(frames.size()):
		if int(frames[i]) >= 0:
			reachable = i
			break
	if reachable < 0:
		print("[NOTE] no reachable strip cell on this emitter — the entry point is unexercised")
		_passed += 1
	else:
		var f: int = int(frames[reachable])
		var before: int = page._colour_keyframes.size()
		page._on_strip_colour_requested(reachable, f)
		await _frames(24)
		_assert_true(page._colour_selected_frame == f,
			"right-clicking cell %d selected life frame %d (got %d)"
			% [reachable, f, page._colour_selected_frame])
		# SELECT ONLY — the strip's right-click used to be select-or-ADD, and that fell with
		# the click-to-add rule on 2026-08-20: a right-click meant to look at a cell's colour
		# permanently altered the curve.
		_assert_eq(page._colour_keyframes.size(), before,
			"…and minted nothing (%d keyframes before and after)" % before)
		# AND THE RIBBON HEARD ABOUT IT. This route reaches the page WITHOUT going through
		# the column, so the column never sets its own `_selected_frame` — the page has to
		# push it back. It did not, and the fault was invisible to every number in this file:
		# the page state and the picker were both correct and only the ribbon showed nothing
		# selected. Caught by a cropped screenshot, asserted here so it stays caught.
		_assert_eq(col.selected_frame(), f,
			"the COLUMN shows the selection a strip right-click made")
		# Doing it AGAIN must select, never duplicate — there is no way to tell two marks
		# stacked at the same age apart.
		page._on_strip_colour_requested(reachable, f)
		await _frames(24)
		_assert_eq(page._colour_keyframes.size(), before,
			"…and a second right-click on the same cell still mints nothing")
	_done("select_or_add")


# --- helpers ---

## A key-down event for the pure shortcut recognizers. `echo` stays false: an auto-repeat
## echo is exactly what those recognizers exist to reject, and a fixture that produced one
## by default would assert the opposite of what it reads.
func _key(code: Key, ctrl: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e


## A left-click at a POINT. The horizontal track took an x and derived the y from its lane
## height; the vertical column needs both, because an age is a (row, column) cell.
func _click_at(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Vector2.ZERO
	var stable := 0
	for i in range(max_frames):
		await get_tree().process_frame
		if node == null:
			return
		if node.size == last:
			stable += 1
			if stable >= 8:
				return
		else:
			stable = 0
			last = node.size
	print("[NOTE] %s never settled in %d frames (last %s)" % [what, max_frames, last])


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
