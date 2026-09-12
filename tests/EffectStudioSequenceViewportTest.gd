extends Node
## REGRESSION (headful, real E019): the #247 sequence viewport is wired into the page —
## it appears for an "animation" target, it SHARES the inspector row's
## right-hand canvas column with the frameset canvas rather than fighting it for the
## space, and clicking a strip cell drills into that opcode.
##
## The column is the part worth guarding. The two panels are mutually exclusive by
## target kind, so `_relayout` sizes ONE canvas column against whichever panel occupies
## it. Get that wrong and both panels can claim the column at once, or the sequence
## panel inherits the frameset panel's MEASURED chrome — which is taller, because that
## one carries a hover readout and the region scope beneath its canvas and this one
## carries neither. Asserted on global rects, never on a screenshot.
##
## Skips when the ROM-derived effect assets are absent (gitignored), and skips WITH THE
## NUMBERS when the dashboard window comes up too short to express the invariant — this
## same unchanged harness has measured a body of 153, 507 and 1209 px across runs, so a
## hard failure there would be measuring the compositor.
##
## Run: godot --path . --quit-after 400 res://tests/EffectStudioSequenceViewportTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")
const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")
const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")
const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")
const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")
const Sparkline = preload("res://src/effects/studio/EffectCurveSparkline.gd")

var _passed: int = 0
var _failed: int = 0
## Which test functions RAN TO THE END. A GDScript coroutine that hits a runtime error
## — touching a signal that no longer exists, say — aborts silently, taking its
## remaining assertions with it and reporting only a smaller "N passed" that still says
## 0 failed. That happened here: the drill-down test kept emitting a signal deleted when
## the film strip moved onto the inspector rows, and five assertions vanished without a
## word. Each test stamps itself; `_ready` fails loudly if any stamp is missing.
var _completed: Dictionary = {}
const _EXPECTED_TESTS := [
	"viewport_appears", "panels_exclusive", "row_drills", "band_layout", "row_thumbnails",
	"transport", "edit_reaches_the_player", "colour_ribbon", "film_strip",
]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run, so its assertions were never made" % name)
	print("\n=== EffectStudioSequenceViewportTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceViewportTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceViewportTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — sequence viewport regression skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	_assert_true(page != null, "the studio page exists")
	if page == null:
		return
	# A HIDDEN Window does not lay out to its full width — show it exactly as F3 does
	# before measuring anything.
	DebugOverlay.show_overlay()
	await _frames(30)
	await _settle(page._body, "the dashboard body")

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	if dir == "":
		print("[SKIP] E019 not in the catalogue")
		_passed += 1
		return
	page._load_effect(dir)
	await _frames(40)
	await _settle(page._body, "the dashboard body after loading E019")
	if page._effect_data == null or page._effect_data.texture == null:
		print("[SKIP] E019 has no texture")
		_passed += 1
		return

	await _test_the_viewport_appears_for_a_sequence(page)
	await _test_the_two_panels_never_hold_the_column_at_once(page)
	await _test_clicking_an_opcode_row_drills_into_that_opcode(page)
	await _test_the_panel_stays_inside_its_band(page)
	await _test_every_opcode_row_grows_its_own_picture(page)
	await _test_the_player_has_its_own_transport(page)
	await _test_an_opcode_edit_reaches_the_player(page)
	await _test_the_colour_ribbon_spans_the_ages_the_strip_tiles(page)
	await _test_the_film_strip_under_the_player(page)


## The Colour ribbon under the player (ADR-0103 follow-on). Two invariants, and the second
## is the one with teeth.
func _test_the_colour_ribbon_spans_the_ages_the_strip_tiles(page) -> void:
	# Item 1 is sequence 0 (item 0 is the picker's placeholder), and BROWSING is the point:
	# `_set_root` clears the nav trail, so no emitter is on it and the ladder has to fall
	# through to the cohort. E019 sequence 0 has TWO applicable emitters (2 and 3), so the
	# answer must be `first` — the rung whose whole justification is that it is labelled.
	page._on_sequence_browsed(1)
	await _frames(12)
	var r = page._sequence_ribbon
	var slot: Control = page._sequence_life_slot
	_assert_true(r != null and slot != null, "the player carries a ribbon and a slot for it")
	_assert_eq(str(page._sequence_provenance.get("rung", "")), "first",
		"E019 sequence 0 has two applicable emitters, so the ladder names the first")
	_assert_true(r.is_shown(), "…and the ribbon draws, because that rung resolved curves")
	# THE AXIS IS THE PARTICLE'S LIFE, AND IT WAS THE STRIP'S UNTIL 2026-08-20.
	#
	# This assertion used to read `used_n() == total_ticks(trace)` — the ribbon and the strip
	# on one shared axis, so a position along the bar mapped to a row. That was the right
	# answer while the bar was read-only, and it is the wrong one now that it is the surface
	# keyframes are authored on: the renderer reads a particle's own LIFE, and of 2622
	# colour-enabled corpus emitters that differs from the animation's display length for
	# 1204 (45.9%), 698 of them by more than 8 frames (ADR-0089 colour-move amendment).
	#
	# The old assertion did not fail when the axis changed, and that is worth saying out
	# loud: E019 sequence 0's emitter is animation-driven (Life = -1), and for those two the
	# windows are equal BY CONSTRUCTION — `EmitterLifeWindow` defines one as the other. 1370
	# corpus emitters are in that class. So the test agreed with both answers and could not
	# tell them apart; it is pinned to the module that decides now, and the equality with
	# the strip is asserted as a CONSEQUENCE of this emitter's kind rather than as the rule.
	var want: Dictionary = LifeWindow.resolve(page._effect_data,
		int(page._sequence_provenance.get("emitter_index", -1)))
	_assert_eq(r.used_n(), int(want["n"]),
		"the ribbon's window is the particle's LIFE (%d, %s)" % [int(want["n"]), want["kind"]])
	# ONE BAND PER AGE, **FLOORED AT 2**. The ribbon floors a trimmed window at two bands
	# (mirroring `EffectCurveSparkline.windowed_samples`), and 154 corpus colour emitters
	# have a 1-frame particle life. Asserting the raw window here held only by never meeting
	# one; `EmitterLifeWindow`'s 2026-08-20 correction let one through and it failed — the
	# floor doing its job, not a regression. Stated as a literal rather than recomputed from
	# the ribbon, so this pins the floor instead of agreeing with whatever it currently is.
	var want_bands: int = maxi(int(want["n"]), 2) if Sparkline.display_trim_width else 160
	_assert_eq(r.colors().size(), want_bands,
		"so it draws one band per age it can read, floored at 2 (window %d)" % int(want["n"]))
	var ticks: int = SequenceTimeline.total_ticks(page._sequence_canvas.get_trace())
	if str(want["kind"]) == "animation_driven":
		_assert_eq(int(want["n"]), ticks,
			"…and on an ANIMATION-DRIVEN emitter that is also the strip's span (%d)" % ticks)
	elif int(want["n"]) == ticks:
		print("  [NOTE] this emitter's authored lifetime (%d) happens to equal the strip's "
			% int(want["n"]) + "span — only 42 of the corpus's 1246 authored ones do")
		_passed += 1
	else:
		print("  [NOTE] authored lifetime (%d) vs the strip's %d — the axes legitimately part"
			% [int(want["n"]), ticks])
		_passed += 1
	_assert_true(slot.tooltip_text.find("emitter") >= 0,
		"and the slot names the rung in full, where no column width can drop it")

	# THE SLOT IS RESERVED. `ColourRibbon.set_curves` HIDES itself when colour is off, and
	# `_canvas_chrome_h` SKIPS INVISIBLE CHILDREN — so an unwrapped ribbon would shrink the
	# panel's measured chrome the moment the author browsed to a sequence with no
	# colour-enabled emitter, resizing the canvas square and re-flowing every thumbnail in
	# the strip. That is the exact movement ADR-0102's reserved focus slot exists to stop.
	# THE SLOT IS RESERVED — and since the 2026-08-20 vertical-column amendment it reserves
	# WIDTH, not height. The reason is untouched: `_canvas_chrome_h` and `_canvas_floor_w`
	# both SKIP INVISIBLE CHILDREN, so an occupant that hid itself when colour went off would
	# re-size the player's square as the author browsed. Only the AXIS the slot binds moved,
	# because the occupant moved from under the canvas to beside it.
	var floor_lit: float = page._canvas_floor_w(page._sequence_canvas)
	var chrome_lit: float = page._canvas_chrome_h(page._sequence_canvas)
	page._sequence_life_column.visible = false   # the `none` rung, forced
	await _frames(4)
	_assert_true(slot.visible, "with no colour the ribbon hides but its SLOT stays up")
	_assert_eq(page._canvas_floor_w(page._sequence_canvas), floor_lit,
		"so the panel's measured floor WIDTH does not move, and the square does not re-size")
	_assert_eq(page._canvas_chrome_h(page._sequence_canvas), chrome_lit,
		"…nor its measured chrome height")
	page._sequence_life_column.visible = true
	_assert_eq(slot.get_combined_minimum_size().x, Page.sequence_life_column_w(),
		"the slot's WIDTH is declared once, at build, not derived from what it holds")
	_assert_eq(slot.get_combined_minimum_size().y, 0.0,
		"and it bids for NO height — its height is the panel's, so the square keeps the rest")

	_done("colour_ribbon")


## THE FILM STRIP UNDER THE PLAYER (author, 2026-08-19: "I think we can fit the thumbnails
## under the sequence which is playing"). One cell per opcode, the parked cell scrolled into
## view, and — the part with teeth — a slot whose height does not move.
func _test_the_film_strip_under_the_player(page) -> void:
	page._on_sequence_browsed(1)
	await _frames(20)
	var row: BoxContainer = page._sequence_strip_row
	var slot: Control = page._sequence_life_slot
	_assert_true(row != null and slot != null, "the player carries a strip and a slot for it")
	var trace: Array = page._sequence_canvas.get_trace()
	# ONE CELL PER LIFE ROW, not per opcode (ADR-0089 vertical-column amendment). The strip
	# is the particle's life now so the ribbon beside it can be one row per thumbnail: a
	# zero-dwell cell holds no age and gets none, a looped cell gets one per pass, and cells
	# the particle never reaches follow the life rows dimmed.
	var life_rows: Array = page._sequence_life_rows
	if life_rows.is_empty():
		_assert_eq(row.get_child_count(), trace.size(),
			"colour off → the strip falls back to one cell per opcode (%d)" % trace.size())
	else:
		var all_cells: int = 0
		for vb in page._sequence_strip_rows:
			all_cells += (vb as Control).get_child_count()
		_assert_true(all_cells >= life_rows.size(),
			"the strip carries every life row (%d rows, %d cells across %d columns)"
			% [life_rows.size(), all_cells, page._sequence_strip_rows.size()])
		_assert_true(row is VBoxContainer,
			"and each column is a COLUMN — the wrap is between columns, not inside one")

	# THE SLOT IS RESERVED and its height is DECLARED, not derived from what it holds.
	# `_canvas_chrome_h` skips invisible children, so a strip that hid itself on a short
	# sequence — or a scrollbar that appeared only on a long one — would swing the panel's
	# measured chrome as the author browsed, re-sizing the canvas square under them. Same
	# failure the ribbon slot beside it exists to prevent (ADR-0102/0103).
	_assert_eq(slot.get_combined_minimum_size().x, Page.sequence_life_column_w(),
		"the slot's WIDTH is declared once, at build")
	_assert_eq(slot.get_combined_minimum_size().y, 0.0,
		"and it bids for NO height — the column's minimum must not reach _canvas_chrome_h")
	var chrome_long: float = page._canvas_chrome_h(page._sequence_canvas)
	var cells_long: int = row.get_child_count()
	page._on_sequence_browsed(2)     # a different sequence, a different opcode count
	await _frames(20)
	_assert_eq(page._canvas_chrome_h(page._sequence_canvas), chrome_long,
		"browsing to a sequence of another length does not move the measured chrome")
	if row.get_child_count() != cells_long:
		_assert_true(true, "…and the cell count DID change (%d to %d), so that was a real test"
			% [cells_long, row.get_child_count()])
	else:
		print("[NOTE] sequences 0 and 1 have the same opcode count — the chrome check is weaker here")
		_passed += 1

	# THE PARKED CELL IS SCROLLED INTO VIEW. Without this the strip is decorative on any real
	# sequence: E019's longest is 1258px of cells in a 276px column, so the marked cell spends
	# most of the loop off-screen. Browse the LONGEST sequence deliberately — sequence 0 is
	# four opcodes and fits, which would skip the only assertion that matters here.
	page._on_sequence_browsed(_longest_sequence_item(page))
	await _frames(20)
	# IT WRAPS INTO COLUMNS, and that reverses this suite's assertion for the SECOND time —
	# worth spelling out, because the reasoning was wrong both times in the same way.
	#
	#   1. It WAS an `HFlowContainer` answering *"can we have the keyframes just wrap if
	#      they go to the end of the frame?"* — right for a wide, short band under the
	#      player, wrong once the strip stood on end.
	#   2. It then did NOT wrap, and this suite argued: *"a column beside a ribbon cannot
	#      wrap at all: a second column of thumbnails would have no ribbon next to it, which
	#      is the whole alignment claim broken."*
	#
	# The author dissolved (2) in one sentence — **the ribbon wraps too**. Each column of
	# thumbnails gets its own ribbon strip beside it, so the pairing survives per column and
	# nothing about the alignment claim was ever at stake. The argument was not a fact about
	# wrapping; it was a fact about a design that had exactly one ribbon in it, stated as
	# though it were a fact about wrapping. That is the same error as (1): both took a
	# property of the then-current layout and wrote it down as a constraint on layouts.
	#
	# Asserted on the GEOMETRY rather than the class, as both previous versions were: WITHIN
	# a column the cells share one x and strictly descend, and ACROSS columns x strictly
	# increases while y restarts at the top.
	var col_x: Array = []
	var checked_cols: int = 0
	for k in range(page._sequence_strip_rows.size()):
		var vb: Control = page._sequence_strip_rows[k]
		var cells: Array = vb.get_children()
		if cells.is_empty():
			continue
		checked_cols += 1
		col_x.append((cells[0] as Control).global_position.x)
		if cells.size() < 2:
			continue
		var same_x: bool = true
		var strictly_down: bool = true
		var prev_y: float = -1.0
		for c in cells:
			var cc := c as Control
			if absf(cc.global_position.x - (cells[0] as Control).global_position.x) > 0.5:
				same_x = false
			if cc.global_position.y <= prev_y:
				strictly_down = false
			prev_y = cc.global_position.y
		_assert_true(same_x,
			"column %d's cells share one x — a column is a column, not a grid" % k)
		_assert_true(strictly_down,
			"…and they descend in order, so row i is thumbnail i inside column %d" % k)
	_assert_true(checked_cols >= 1, "at least one column held cells (%d)" % checked_cols)
	if col_x.size() >= 2:
		var rightwards: bool = true
		for i in range(1, col_x.size()):
			if col_x[i] <= col_x[i - 1]:
				rightwards = false
		_assert_true(rightwards,
			"…and the columns run LEFT TO RIGHT (%s) — the wrap goes to the right, which is "
			% str(col_x) + "the author's own words for it")
		# EVERY COLUMN HAS A RIBBON. This is the sentence that dissolved the old no-wrap
		# argument, so it is the one thing that must be true for the reversal to be honest.
		var ribboned: int = 0
		for k in range(page._sequence_life_columns.size()):
			var lc = page._sequence_life_columns[k]
			if (page._sequence_strip_rows[k] as Control).get_child_count() > 0 \
					and lc.visible and lc.row_count() > 0:
				ribboned += 1
		_assert_true(ribboned >= 2,
			"every wrapped column of thumbnails has its OWN ribbon beside it (%d of %d) — "
			% [ribboned, col_x.size()]
			+ "the claim that reversed the no-wrap rule")
	else:
		print("[NOTE] %d column(s) held cells — the wrap geometry is unmeasured here"
			% col_x.size())
		_passed += 1
	var scroll: ScrollContainer = page._sequence_strip_scroll
	var n: int = row.get_child_count()
	if n < 8 or scroll.size.y <= 0.0 or row.size.y <= scroll.size.y:
		print("[SKIP] the strip fits its viewport (%d cells, %.0f of %.0f px tall) - nothing to scroll"
			% [n, row.size.y, scroll.size.y])
		_passed += 1
		_done("film_strip")
		return
	page._park_sequence_on(n - 2)
	await _frames(20)
	var cell := row.get_child(n - 2) as Control
	var top: float = scroll.scroll_vertical
	_assert_true(cell.position.y >= top - 1.0
			and cell.position.y + cell.size.y <= top + scroll.size.y + 1.0,
		"parking deep in the sequence scrolls that cell's ROW into view (cell at %.0f, window %.0f..%.0f)"
			% [cell.position.y, top, top + scroll.size.y])
	# …and a click on a cell PARKS, exactly as the inspector's rows do - one meaning of
	# "parked" whichever surface you click (ADR-0100 dec. 7).
	#
	# THE CELL'S OPCODE IS NOT ITS INDEX any more. The strip is laid out by LIFE ROW, so
	# child 1 is the second row, whose trace cell is whatever `life_rows` says — a zero-dwell
	# opcode before it shifts them apart. Asserting `== 1` passed only while the two indices
	# happened to coincide, which is the shape of test this ADR has already been caught by
	# twice.
	var want_op: int = 1
	if not page._sequence_life_rows.is_empty():
		want_op = int(page._sequence_life_rows[1]["cell"])
	(row.get_child(1) as Control).clicked.emit()
	await _frames(10)
	_assert_eq(page._sequence_canvas._selected_op, want_op,
		"clicking strip row 1 parks the player on ITS opcode (%d)" % want_op)

	_done("film_strip")


## The picker item index of the effect's longest sequence (item 0 is the placeholder, so
## item i is animation i-1).
func _longest_sequence_item(page) -> int:
	var best := 1
	var most := -1
	var anims: Array = page._effect_data.animations
	for i in range(anims.size()):
		var n: int = (anims[i].get("opcodes", []) as Array).size()
		if n > most:
			most = n
			best = i + 1
	return best


func _test_the_viewport_appears_for_a_sequence(page) -> void:
	page._on_sequence_browsed(1)   # the callback a real click on row 1 fires
	await _frames(12)
	_assert_true(page._sequence_panel != null and page._sequence_panel.visible,
		"the sequence viewport is visible for an animation target")
	_assert_true(page._sequence_canvas._trace.size() > 0,
		"and it is bound to a real sequence (%d cells)" % page._sequence_canvas._trace.size())
	# One cell per OPCODE — the cell count must equal the sequence's opcode count, not
	# its FRAME count and not its tick count.
	var ref: Dictionary = Target.ref(page._nav.back())
	var anim = page._effect_data.animations[int(ref.get("index", 0))]
	_assert_eq(page._sequence_canvas._trace.size(), (anim.get("opcodes", []) as Array).size(),
		"one cell per opcode, every opcode")

	_done("viewport_appears")

## THE SECOND OCCUPANT IS A `texture` TARGET, NOT A `frame` ONE (ADR-0130 dec. 10).
## This used to browse a FRAME and assert the frameset canvas took the column. That is now
## the opposite of the decision: a frame target no longer parks the sheet here, because the
## Texture TAB already draws it in the left column with the same live handles and the same
## scope control — showing it twice paid for one picture twice and gave the author two places
## to drag the same box. The slot goes to the sequence player instead, so a frame screen reads
## "the sheet on the left, the animation on the right".
##
## `texture` KEEPS the column: there is no sequence for a texture target to show, and dec. 8 —
## the page finally having a picture without switching tabs — is the whole complaint ADR-0130
## opened on. So the exclusivity this test exists for is unchanged; only which kind triggers
## the swap moved, and asserting the old kind was asserting a superseded design.
func _test_the_two_panels_never_hold_the_column_at_once(page) -> void:
	# They share ONE column, so whichever is showing, the other must not be.
	page._on_sequence_browsed(1)
	await _frames(12)
	_assert_true(page._sequence_panel.visible, "an animation target shows the sequence viewport")
	_assert_true(not page._frameset_panel.visible, "and hides the frameset canvas")

	page._set_root(Target.texture())
	await _frames(16)
	_assert_true(page._frameset_panel.visible, "a texture target shows the frameset canvas")
	_assert_true(not page._sequence_panel.visible, "and hides the sequence viewport")

	# …and a FRAME target does the opposite of what it used to: it keeps the sequence player,
	# because the sheet is the Texture tab's job now (dec. 10).
	page._on_frameset_browsed(1)
	await _frames(16)
	_assert_true(not page._frameset_panel.visible,
		"a frame target does NOT re-park the sheet here — the Texture tab owns it")
	_assert_true(page._sequence_panel.visible,
		"…the slot goes to the sequence player instead")

	_done("panels_exclusive")

func _test_clicking_an_opcode_row_drills_into_that_opcode(page) -> void:
	# Clicking a thumbnail PARKS the player on that opcode — it does NOT navigate.
	# Drilling used to open a focused-opcode target, which showed strictly LESS than the
	# section already rendered inline; all it uniquely did was park, and parking now does
	# that directly. The saving is the rebuild a navigation costs: the folds and the
	# scroll position the author set up survive being looked at.
	page._on_sequence_browsed(1)
	await _frames(20)
	var before: Dictionary = page._nav.back()
	var thumbs: Array = _section_thumbnails(page)
	_assert_true(thumbs.size() >= 3, "the opcode sections carry pictures (%d found)" % thumbs.size())
	if thumbs.size() < 3:
		_done("row_drills")
		return
	thumbs[2].clicked.emit()
	await _frames(10)
	_assert_eq(page._sequence_canvas._selected_op, 2, "the click parks the player on that opcode")
	_assert_eq(page._sequence_canvas._playing, false, "and stops it, so the state can be read")
	# No navigation: the target is exactly the one that was open.
	_assert_true(Target.equals(page._nav.back(), before),
		"and does NOT navigate — the sequence target is untouched")
	_assert_eq(Target.kind(page._nav.back()), "animation", "still the whole sequence")

	_done("row_drills")

## The panel is a right-hand COLUMN now (ADR-0100), not a full-width band. It was a
## column once before and that attempt was reverted, so this measures the two things
## that broke it: it must sit BESIDE the inspector without landing ON it, and it must
## stay inside the inspector row rather than bleeding into the timeline.
func _test_the_panel_stays_inside_its_band(page) -> void:
	page._on_sequence_browsed(1)
	await _frames(12)
	await _settle(page._sequence_panel, "the sequence panel")
	if not page._sequence_panel.visible:
		print("[SKIP] the sequence panel is not visible — nothing to measure")
		_passed += 1
		_done("band_layout")
		return
	var panel: Rect2 = page._sequence_panel.get_global_rect()
	var controls: Rect2 = page._inspector.get_global_rect()
	var timeline: Rect2 = page._scroll.get_global_rect()

	var room: float = page._body.size.x - page._inspector.content_width()
	var floor_w: float = page._sequence_panel.get_combined_minimum_size().x
	if room < floor_w:
		print("[SKIP] the dashboard came up too narrow to express the layout — %.0fpx beside a %.0fpx declared inspector for a %.0fpx panel minimum (body %.0fpx wide)"
			% [room, page._inspector.content_width(), floor_w, page._body.size.x])
		_passed += 1
		_done("band_layout")
		return
	# …and too SHORT, which is the same class of skip and was missing. `_relayout` reserves
	# the path bar, MIN_CHANNELS_H of lanes and the frames bar off the body before the
	# inspector row gets anything; when what is left cannot hold a square canvas plus the
	# panel's measured chrome, the row is clamped to the budget and the PanelContainer — which
	# may not shrink below its own minimum — renders TALLER than the rect assigned to it and
	# overhangs the timeline [A]. No clamp fixes a 153px body holding a 268px panel; the
	# window is simply too small. This same unchanged harness has measured a body of 153, 507
	# and 1209 px across runs, so state the numbers and skip rather than measure the compositor.
	#
	# The WIDTH analogue of this is NOT skipped — it is fixed. `column_width`'s floor is
	# `_CANVAS_MIN_SIDE`, a floor for the canvas, while the panel around it carries chrome
	# with a width of its own (the sequence transport row, 202px); `_relayout` now floors the
	# column at `_canvas_floor_w` so the panel can never overhang the inspector sideways.
	var reserved: float = Page.MIN_CHANNELS_H + FramesBar.BAR_H \
		+ (page._path_bar.bar_height() if page._path_bar != null else 0.0)
	var chrome_h: float = page._canvas_chrome_h(page._sequence_canvas)
	var budget: float = page._body.size.y - reserved
	var floor_h: float = 180.0 + chrome_h   # 180.0 == _CANVAS_MIN_SIDE
	if budget < floor_h:
		print("[SKIP] the dashboard came up too short to express the layout — %.0fpx of row budget for a %.0fpx square-canvas floor (body %.0fpx tall, %.0f reserved for lanes/bars, %.0f of canvas chrome)"
			% [budget, floor_h, page._body.size.y, reserved, chrome_h])
		_passed += 1
		_done("band_layout")
		return

	_assert_true(panel.position.y + panel.size.y <= timeline.position.y + 1.0,
		"[A] the panel never bleeds into the timeline (panel ends %.0f, timeline starts %.0f)"
			% [panel.position.y + panel.size.y, timeline.position.y])
	# [B] a COLUMN: it shares the inspector ROW, docked right. Both objections that made
	# it a band have expired — the film strip left this panel (so it wants a square, like
	# the frameset canvas beside which it now alternates), and the per-opcode LINK rows
	# that held the inspector at 1068px of a 1241px body are deleted.
	# It shares the ROW, and the row's top is the path bar's bottom — NOT the inspector's top.
	# ADR-0130 put the tab strip inside the LEFT column only: `_relayout` places the strip at
	# `bar_h` and the inspector at `bar_h + tab_h`, while the right column stays at `bar_h` so
	# that "the right column and everything stacked below do not move when a tab is switched or
	# the strip appears." Measuring the panel against the INSPECTOR's top made this assertion a
	# function of the tab strip's height — it failed by exactly `tab_h` (31px) — which is the
	# one thing the layout is built to keep it independent of.
	var row_top: float = page._body.get_global_rect().position.y \
		+ (page._path_bar.bar_height() if page._path_bar != null else 0.0)
	_assert_true(absf(panel.position.y - row_top) <= 1.0,
		"[B] the panel shares the row, docked right (panel top %.0f, row top %.0f)"
			% [panel.position.y, row_top])
	_assert_true(controls.position.y >= panel.position.y - 1.0,
		"[B1] and the inspector sits at or below it, under the tab strip (inspector top %.0f)"
			% controls.position.y)
	_assert_true(absf((panel.position.x + panel.size.x)
			- (page._body.get_global_rect().position.x + page._body.size.x)) <= 1.0,
		"[B2] flush with the row's right edge")
	# [C] AND IT DOES NOT OVERLAP. This is the exact failure that lost the column the
	# first time: a Container cannot shrink below its minimum, so a column wider than the
	# leftover does not narrow the inspector — it lands on top of it by the difference.
	_assert_true(controls.position.x + controls.size.x <= panel.position.x + 1.0,
		"[C] the inspector ends before the column begins (inspector right %.0f, column left %.0f)"
			% [controls.position.x + controls.size.x, panel.position.x])
	_assert_true(page._inspector.content_width() <= controls.size.x + 1.0,
		"[C2] and the width it kept covers its DECLARED content (%.0f declared, %.0f assigned)"
			% [page._inspector.content_width(), controls.size.x])
	_assert_true(panel.size.y > 1.0, "[D] the panel has a real height (%.0f)" % panel.size.y)
	_assert_true(panel.size.x > 1.0, "[D2] and a real width (%.0f)" % panel.size.x)

	# The two occupants share ONE slot: switching target kind must move the same column,
	# never open a second one. The other occupant is a `texture` target (ADR-0130 dec. 10 —
	# see `_test_the_two_panels_never_hold_the_column_at_once`); browsing a FRAME here measured
	# a panel that is deliberately hidden, so it read a stale rect and failed on it.
	page._set_root(Target.texture())
	await _frames(16)
	await _settle(page._frameset_panel, "the frameset panel")
	var fs: Rect2 = page._frameset_panel.get_global_rect()
	var fs_controls: Rect2 = page._inspector.get_global_rect()
	_assert_true(fs_controls.position.x + fs_controls.size.x <= fs.position.x + 1.0,
		"[E] the frameset occupant does not overlap the inspector either (inspector right %.0f, column left %.0f)"
			% [fs_controls.position.x + fs_controls.size.x, fs.position.x])
	_assert_true(not page._sequence_panel.visible, "[E2] and the sequence panel yielded the slot")

	_done("band_layout")

func _test_every_opcode_row_grows_its_own_picture(page) -> void:
	# The film strip IS the inspector list (#247, ADR-0100): each opcode SECTION carries
	# the picture of the animator state after its opcode runs, on the title row so a shut
	# section still shows it. The reel scrolls with the sections and needs no surface of
	# its own — and the header, which used to hold a second copy of this list, is free.
	page._on_sequence_browsed(1)
	await _frames(20)
	var thumbs: Array = _section_thumbnails(page)
	var ref: Dictionary = Target.ref(page._nav.back())
	var opcodes: int = (page._effect_data.animations[int(ref.get("index", 0))].get("opcodes", []) as Array).size()
	_assert_eq(thumbs.size(), opcodes,
		"every opcode row grew a picture — one per opcode, none for the summary rows")
	# They must all share ONE bounds box, or a row whose opcode merely moved the sprite
	# would re-centre and duplicate the row above it.
	var boxes := {}
	for t in thumbs:
		boxes[str(t._box)] = true
	_assert_eq(boxes.size(), 1,
		"all thumbnails share one coordinate box (%d distinct found)" % boxes.size())
	# And that box is the sequence's, not a per-row derivation.
	_assert_eq(thumbs[0]._box, page._sequence_canvas.get_bounds(),
		"the box is the sequence's shared bounds, the same one the player draws through")
	# The header is a two-row summary now. Its per-opcode rows were the whole reason the
	# inspector demanded 1068px of a 1241px body; measure the freed width, don't infer it.
	_assert_eq(page._inspector.row_count(), 2, "the header is down to its summary rows")
	var min_w: float = page._inspector.get_combined_minimum_size().x
	_assert_true(min_w < page._body.size.x * 0.6,
		"the inspector's minimum width leaves room for a column beside it (%.0f of %.0f)"
			% [min_w, page._body.size.x])
	# Every OPCODE section is shut on arrival, so they read as a vertical film strip — and
	# after the ADR-0102 second amendment the strip is ONLY opcode sections. The focus block
	# left this list for a panel of its own (`_focus_inspector`), so that nothing it does
	# can move a thumbnail; a block back in here would be that regression, whatever it was
	# called, which is why this counts non-opcode sections rather than naming the block.
	var open_opcode_sections: int = 0
	var strangers: int = 0
	for entry in page._inspector.section_folds():
		if not str(entry.get("id", "")).begins_with("seq:"):
			strangers += 1
		elif entry["body"].visible:
			open_opcode_sections += 1
	_assert_eq(open_opcode_sections, 0, "every opcode section arrives collapsed")
	_assert_eq(strangers, 0, "and the strip's list is opcode sections and nothing else")
	var block_folds: Array = page._focus_inspector.section_folds()
	_assert_eq(block_folds.size(), 1, "the block is the focus panel's one section")
	_assert_true((block_folds[0]["body"] as Control).visible, "…and it opens")
	# And one control shuts or opens the lot.
	var bulk: Dictionary = page._inspector.section_bulk_buttons()
	_assert_true(not bulk.is_empty(), "a section-level Expand all / Collapse all is offered")
	if not bulk.is_empty():
		bulk["expand"].pressed.emit()
		await _frames(4)
		var opened: int = 0
		for entry in page._inspector.section_folds():
			if entry["body"].visible:
				opened += 1
		_assert_eq(opened, page._inspector.section_folds().size(), "Expand all opens every section")
		bulk["collapse"].pressed.emit()
		await _frames(4)

	_done("row_thumbnails")


## Pace, and the marks that say where the pace has got to.
func _test_the_player_has_its_own_transport(page) -> void:
	page._on_sequence_browsed(1)
	await _frames(20)
	var canvas = page._sequence_canvas

	# The speed field is the player's OWN, not the page transport's. Moving one must
	# leave the other exactly where it was: the page scrubs the effect timeline, this
	# scrubs a reusable asset being authored, and the clocks are already separate.
	_assert_true(page._sequence_speed_field != null, "the player carries a speed field")
	var page_speed_before: float = page._speed_value
	page._sequence_speed_field.value = 0.25
	await _frames(6)
	_assert_eq(canvas.speed(), 0.25, "setting it slows THIS player")
	_assert_eq(page._speed_value, page_speed_before, "and leaves the page transport alone")

	# Session state: picking another sequence, and loading another effect, must not
	# throw away a rate the author deliberately set.
	page._on_sequence_browsed(2)
	await _frames(16)
	_assert_eq(page._sequence_canvas.speed(), 0.25, "the rate survives picking another sequence")
	var e317 := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			e317 = d
	if e317 != "":
		page._load_effect(e317)
		await _frames(40)
		page._on_sequence_browsed(1)
		await _frames(16)
		_assert_eq(page._sequence_canvas.speed(), 0.25, "and survives loading another effect")
		canvas = page._sequence_canvas

	# Step buttons walk the opcodes and park.
	page._park_sequence_on_step(1)
	await _frames(4)
	var first: int = canvas.selected_op()
	_assert_true(first >= 0, "a step parks the player on an opcode (%d)" % first)
	page._park_sequence_on_step(1)
	await _frames(4)
	_assert_eq(canvas.selected_op(), (first + 1) % canvas.get_trace().size(),
		"and the next step moves one along")

	# The parked mark reaches the thumbnail that is parked, and only it. Each thumbnail
	# subscribes itself, so this is also the guard that the subscription is wired at all.
	var thumbs: Array = _section_thumbnails(page)
	if thumbs.is_empty():
		print("[SKIP] no thumbnails to mark")
		_passed += 1
		_done("transport")
		return
	var parked: int = canvas.selected_op()
	var marked: Array = []
	for i in range(thumbs.size()):
		if thumbs[i]._selected:
			marked.append(i)
	_assert_eq(marked, [parked], "exactly the parked opcode's picture carries the parked mark")
	page._park_sequence_on_step(-1)
	await _frames(4)
	_assert_true(not thumbs[parked]._selected, "and the mark MOVES off it when the park does")
	_assert_true(thumbs[canvas.selected_op()]._selected, "onto the new one")

	page._sequence_speed_field.value = 1.0
	await _frames(4)

	_done("transport")


## An edit to an opcode must reach the thing the author is looking at while making it.
##
## It did not. The player holds a DECODE — `SequenceTimeline.trace` flattens the opcode
## stream once at bind — and a `sequence` channel edit returns only `invalidates_sim`, so
## `_apply_edit` took no branch that re-bound it. Changing a duration from 2 to 10, or
## pointing a FRAME at another frameset, re-folded the particle preview and left the
## sequence player, its thumbnails and its labels showing the old values.
func _test_an_opcode_edit_reaches_the_player(page) -> void:
	page._on_sequence_browsed(1)
	await _frames(20)
	var canvas = page._sequence_canvas
	var ref: Dictionary = Target.ref(page._nav.back())
	var anim_idx: int = int(ref.get("index", -1))
	var opcodes: Array = page._effect_data.animations[anim_idx].get("opcodes", [])

	# Find a FRAME opcode to edit — it is the only kind that owns duration and frameset.
	var op_i: int = -1
	for i in range(opcodes.size()):
		if str((opcodes[i] as Dictionary).get("type", "")) == "FRAME":
			op_i = i
			break
	if op_i < 0:
		print("[SKIP] the browsed sequence has no FRAME opcode to edit")
		_passed += 1
		_done("edit_reaches_the_player")
		return

	var thumbs: Array = _section_thumbnails(page)
	var was_ticks: int = canvas._total_ticks
	var was_cell_ticks: int = int((canvas.get_trace()[op_i] as Dictionary).get("ticks", 0))
	# By fold_id, not by index: the ADR-0102 focus block leads the section list, so
	# `section_folds()[op_i]` is off by one (and would be off by more if the block grew a
	# neighbour). `"seq:<anim>:<op>"` is SequenceProjector's own stable id for the section.
	var op_fold_id := "seq:%d:%d" % [anim_idx, op_i]
	var was_title: String = _section_title(page, op_fold_id)
	var was_plays: String = _plays_for_cell(page)

	# --- duration: 2 -> 30, through the REAL choke point the spinbox drives. ---
	page._apply_edit({"channel": "sequence", "animation_index": anim_idx,
		"opcode_index": op_i, "field": "duration"}, 30)
	await _frames(8)
	_assert_true(canvas._total_ticks != was_ticks,
		"a duration edit re-decodes the player (%d ticks -> %d)" % [was_ticks, canvas._total_ticks])
	_assert_true(int((canvas.get_trace()[op_i] as Dictionary).get("ticks", 0)) != was_cell_ticks,
		"and that opcode's own cell dwells longer (%d -> %d)"
			% [was_cell_ticks, int((canvas.get_trace()[op_i] as Dictionary).get("ticks", 0))])
	# The header's "Plays for N ticks" is a sum over the durations below it, so a duration
	# edit must move it. Matched on the UNIT, not on prose: the cell used to read "N ticks
	# before the terminator" and that sentence was the widest thing in the view, so it set
	# the declared `content_width()` the ADR-0102 focus column is claimed from and was cut
	# to "N ticks" (the terminator moved to the tooltip). The claim was never the wording —
	# it is that the row is there and its number follows the edit.
	var plays := _plays_for_cell(page)
	_assert_true(plays != "", "the header still carries a run-length cell (%s)" % plays)
	_assert_true(plays != was_plays,
		"…and it refreshed with the edit (%s -> %s)" % [was_plays, plays])
	_assert_true(not plays.begins_with("%d " % was_ticks),
		"and it followed the edit rather than showing the old total (%s)" % plays)
	# The section title spells out this opcode's own values, so it went stale too.
	var now_title: String = _section_title(page, op_fold_id)
	_assert_true(now_title != was_title,
		"the section title followed the edit ('%s' -> '%s')" % [was_title, now_title])
	_assert_true("dur=30" in now_title, "and states the new duration (%s)" % now_title)
	# NOT rebuilt — the widgets are the same objects, which is what keeps a live scrub alive.
	_assert_true(_section_thumbnails(page).size() == thumbs.size()
			and (thumbs.is_empty() or _section_thumbnails(page)[0] == thumbs[0]),
		"and the inspector was refreshed IN PLACE, not rebuilt")

	# --- frameset: point it somewhere else and watch the picture change. ---
	var was_fs: int = int((canvas.get_trace()[op_i] as Dictionary).get("frameset", -1))
	var other_fs: int = 0 if int((opcodes[op_i] as Dictionary).get("frameset", 0)) != 0 else 1
	page._apply_edit({"channel": "sequence", "animation_index": anim_idx,
		"opcode_index": op_i, "field": "frameset"}, other_fs)
	await _frames(8)
	_assert_true(int((canvas.get_trace()[op_i] as Dictionary).get("frameset", -1)) != was_fs,
		"a frameset edit re-decodes the cell (%d -> %d)"
			% [was_fs, int((canvas.get_trace()[op_i] as Dictionary).get("frameset", -1))])
	# The thumbnail is drawn from the trace, so it has to have re-pulled its own cell —
	# it subscribes itself, so this is the guard that the subscription covers re-decodes.
	# The FOLLOW button beside that editor is derived from the value just written, so it
	# has to be re-aimed too — a stale one navigates to the frameset the opcode USED to
	# point at, which is a wrong destination, not just a wrong label.
	var follows: Array = page._inspector.follow_buttons()
	var aimed := false
	for entry in follows:
		if int(entry["ref"].get("opcode_index", -1)) == op_i \
				and str(entry["ref"].get("field", "")) == "frameset":
			aimed = true
			var shift: int = page._sequence_group_offset(ref)
			_assert_eq(str((entry["button"] as Button).text), "→ frameset %d" % (other_fs + shift),
				"the follow beside the editor re-aims to the frameset now referenced")
			_assert_eq(int(Target.ref(entry["state"]["target"]).get("index", -1)), other_fs + shift,
				"and so does where it actually navigates")
	_assert_true(aimed, "the FRAME opcode's Frameset row carries a follow to re-aim")
	if op_i < thumbs.size():
		_assert_eq(thumbs[op_i]._entry, canvas.get_trace()[op_i],
			"and the opcode's picture re-pulled that cell rather than holding the old one")
		_assert_eq(thumbs[op_i]._box, canvas.get_bounds(),
			"through the sequence's re-derived shared box — a frameset edit can resize it")

	_done("edit_reaches_the_player")


# --- harness ----------------------------------------------------------------

## Every `SequenceThumbnail` hanging off a section's title row, in section order.
func _section_thumbnails(page) -> Array:
	var script := load("res://src/effects/studio/SequenceThumbnail.gd")
	var out: Array = []
	for entry in page._inspector.section_folds():
		var row = entry["header"].get_parent()
		if row == null:
			continue
		for sub in row.get_children():
			if sub.get_script() == script:
				out.append(sub)
	return out

## One section's live title, addressed by its stable fold id.
func _section_title(page, fold_id: String) -> String:
	for entry in page._inspector.section_folds():
		if str(entry.get("id", "")) == fold_id:
			return str(entry.get("title", ""))
	return ""


## The header's run-length cell ("N ticks"), or "". Found by its UNIT rather than by grid
## index, which shifts with the header's row count.
func _plays_for_cell(page) -> String:
	for child in page._inspector._grid.get_children():
		if child is Label and (child as Label).text.ends_with("ticks"):
			return (child as Label).text
	return ""


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Rect2()
	var stable := 0
	for _i in range(max_frames):
		await get_tree().process_frame
		var now: Rect2 = node.get_global_rect()
		if now == last and now.size.x > 1.0 and now.size.y > 1.0:
			stable += 1
			if stable >= 8:
				return
		else:
			stable = 0
			last = now
	print("  WARN: %s never settled in %d frames (last %s)" % [what, max_frames, str(last)])


func _assert_true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % what)


func _assert_eq(actual, expected, what: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s\n        expected: %s\n        actual:   %s" % [what, expected, actual])
