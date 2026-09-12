extends Node
## REGRESSION (headful, real E019 + E317, #278/#279): the frameset texture canvas is the
## RIGHT-HAND AREA of the inspector row — not a floating rect hand-computed against the
## page. Three shipped attempts sized it from page-relative arithmetic and each broke a
## different way; the last one overran the timeline section by 388px at the developer's
## 1261x688 dashboard while every existing guard stayed green, because none of them ever
## asserted a rect. This one does.
##
## Asserted on GLOBAL rects, so it holds regardless of which parent the panel hangs off:
##   [A] the panel never bleeds into the timeline section
##   [B] the panel never overlaps the frame-controls column — two areas of ONE row
##   [C] the panel never occludes a transport control (the #275 "Sequences:" regression)
##   [D] the panel comes out approximately square
##   [E] the column NEVER takes width the inspector's declared content needs — asserted
##       against `EffectStudioPage.column_width` directly, because the developer's
##       1261x688 dashboard is not a case where those two terms contend (the square is
##       218 against 556 of room), so a live measurement there cannot see the clamp
##
## MEASUREMENT GOTCHA: the Studio page lives inside DebugDashboard, a separate OS-level
## Window. A HIDDEN Window does not lay out to its full width, so a probe that skips
## `DebugOverlay.show_overlay()` measures a half-width page and reports nonsense (601px
## against a real 1241px). Show it, exactly as F3 does, before measuring anything.
##
## …and then WAIT FOR IT TO SETTLE. Showing the window is not the end of the story:
## its final size arrives from the compositor over an unpredictable number of frames,
## and `_relayout` runs off `_body.resized`. Waiting a fixed 30 frames failed roughly
## one run in three — the canvas measured 231x27 at x=10 (an `editor_h` of 27 means
## `_relayout` last ran at a 237px-tall dashboard), and [B] and [D] failed against a
## layout that was merely unfinished. `_settle` waits for the geometry to stop moving
## instead of guessing, and reports if it never does.
##
## Skips when the ROM-derived effect assets are absent (gitignored).
## Run: godot --path . --quit-after 400 res://tests/EffectStudioFramesetLayoutTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"

var _passed: int = 0
var _failed: int = 0


const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const _Target = preload("res://src/effects/studio/InspectionTarget.gd")


func _ready() -> void:
	_test_the_column_never_takes_the_inspectors_declared_width()
	_test_the_focus_block_takes_only_the_columns_slack()
	_test_the_row_with_a_column_ignores_its_content_height()
	await _run()
	print("\n=== EffectStudioFramesetLayoutTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFramesetLayoutTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFramesetLayoutTest")
		get_tree().quit(0)


## [E] The invariant that lost this column the first time it was attempted (`0306ae37c`:
## a 108px overlap). A Container cannot shrink below its minimum, so a column wider than
## the leftover does not narrow the inspector — it lands on top of it.
##
## Driven at sizes where the terms genuinely contend, which no live dashboard here does.
func _test_the_column_never_takes_the_inspectors_declared_width() -> void:
	# A tall row in a NARROW body: the square wants 620, the inspector declares 900, and
	# only 1000-900-8 = 92 is actually free. The square must lose.
	_assert_true(Page.column_width(1000.0, 700.0, 900.0) <= 92.0,
		"a contended row hands the column only the leftover (%.0f)"
			% Page.column_width(1000.0, 700.0, 900.0))
	# Declared content wider than the whole row: no column at all, never a negative one.
	_assert_true(Page.column_width(600.0, 700.0, 900.0) == 0.0,
		"content wider than the row leaves no column, not a negative one")
	# Roomy: the square wins, capped at half the row.
	_assert_true(is_equal_approx(Page.column_width(1241.0, 199.0, 677.0), 215.0),
		"with room to spare the column is the canvas's own height plus its padding (%.0f)"
			% Page.column_width(1241.0, 199.0, 677.0))
	_assert_true(Page.column_width(1241.0, 5000.0, 100.0) <= 1241.0 * 0.5,
		"and never more than half the row, however tall it gets")
	# Sweep: for every row width and declared content, the inspector always keeps what
	# it declared. This is the property, not the four points above.
	var violations: int = 0
	for row_w in [400.0, 700.0, 1000.0, 1241.0, 1920.0]:
		for content_w in [100.0, 300.0, 457.0, 677.0, 812.0, 1500.0]:
			for canvas_h in [0.0, 100.0, 400.0, 900.0]:
				var col: float = Page.column_width(row_w, canvas_h, content_w)
				if col > 0.0 and row_w - col - 8.0 < minf(content_w, row_w) - 0.001:
					violations += 1
	_assert_true(violations == 0,
		"across 120 row/content/height combinations the inspector always keeps its declared width (%d violations)"
			% violations)


## [F] ADR-0100 dec. 1, amended 2026-08-19 — "shift the right panel with the sequence
## animation to the right and then fit the frameset controls underneath it". The frameset
## block was the MIDDLE column and is now STACKED under the player, so the rule that bounds
## it turned ninety degrees: it takes the column's leftover HEIGHT, not the row's leftover
## WIDTH, and the width it used to hold goes back to the inspector.
##
## Driven directly for the same reason [E] and [G] are: at the dev dashboard the row is 268px
## against a 448px box, so the answer is always 0 and a live measurement sees nothing.
func _test_the_focus_block_takes_only_the_columns_slack() -> void:
	# The block is STACKED under the player now, not beside it, so its bound is the column's
	# leftover HEIGHT once the player's constant box is paid — `focus_stack_height`.
	#
	# The player's box is `_CANVAS_SIDE` (260) plus ~188 of measured chrome = 448. On a row
	# that can hold the box and the block's declared content, the block takes what it asked.
	_assert_true(is_equal_approx(Page.focus_stack_height(800.0, 448.0, 300.0), 300.0),
		"the block takes what it declares, not the whole slack (%.0f)"
			% Page.focus_stack_height(800.0, 448.0, 300.0))
	# …and the surplus is the COLUMN's, not the block's: a tall window must not stretch a
	# name/value grid down half a screen. Same clamp the width rule carried.
	_assert_true(Page.focus_stack_height(1400.0, 448.0, 300.0) <= 300.0,
		"a tall row does not stretch the block (%.0f)"
			% Page.focus_stack_height(1400.0, 448.0, 300.0))
	# When the column cannot afford what the block wants, the BLOCK shrinks — the player's
	# box is never touched, which is ADR-0100 dec. 2's "the box is a CONSTANT" in the one
	# direction this new rule could have broken it.
	_assert_true(is_equal_approx(Page.focus_stack_height(700.0, 448.0, 300.0), 244.0),
		"a short row shortens the block, not the player (%.0f)"
			% Page.focus_stack_height(700.0, 448.0, 300.0))
	# Under the collapse point there is no block at all — and never a negative one. THIS IS
	# THE CASE THE DEV DASHBOARD ACTUALLY HITS: a 268px row against a 268px clamped box has
	# no slack whatever, so the animation screen shows no frameset block until the window is
	# roughly 510px of ROW — about an 840px body once the bars and MIN_CHANNELS_H are paid.
	_assert_eq(Page.focus_stack_height(268.0, 268.0, 300.0), 0.0,
		"the dev-body row has no slack, so the block is dropped rather than letterboxed")
	_assert_eq(Page.focus_stack_height(500.0, 448.0, 300.0), 0.0,
		"…and under the collapse height it goes entirely, rather than showing one clipped row")
	_assert_eq(Page.focus_stack_height(100.0, 448.0, 300.0), 0.0,
		"…and a row shorter than the box yields 0, not a negative height")
	# THE PROPERTY, over the grid: the block never overruns the column, and the player's box
	# is never encroached on — box + gutter + block always fits the row.
	var violations: int = 0
	for row_h in [200.0, 268.0, 400.0, 507.0, 700.0, 1069.0, 1400.0]:
		for box_h in [180.0, 268.0, 374.0, 448.0]:
			for want_h in [0.0, 120.0, 300.0, 700.0]:
				var blk: float = Page.focus_stack_height(row_h, box_h, want_h)
				if blk < 0.0:
					violations += 1
				elif blk > 0.0 and box_h + blk + 8.0 > row_h + 0.001:
					violations += 1
	_assert_true(violations == 0,
		"across 112 row/box/want combinations the stack always fits (%d violations)" % violations)


## [G] ADR-0100 dec. 2's amendment: "the animation box is changing in size all the time as
## clicking through keyframes. It should have fixed dimensions." The box is now a CONSTANT
## square (`_CANVAS_SIDE`) and this is the rule that has to leave it alone — the row is
## floored at the box and otherwise still fits its content.
##
## Both halves are load-bearing and each replaced a real failure. Reading `content_height()`
## for the row (and squaring the box off it) made the box a function of the open target and
## of its FOLD state, since a container minimum skips invisible children. Handing the row
## the whole budget instead — the first fix — made it a function of the WINDOW, and on a
## tall one the box grew until there was no width left for the focus column beside it.
##
## Driven directly, because no dashboard here can express it: at the dev body the budget is
## 268 against 1723 of content, so every variant agrees and a live measurement sees nothing.
func _test_the_row_with_a_column_ignores_its_content_height() -> void:
	# The box is a CONSTANT, so the row only has to be tall enough to hold it — 348 is
	# `_CANVAS_SIDE` (260) plus the sequence panel's measured chrome (88).
	_assert_eq(Page.inspector_row_height(40.0, 661.0, 0.0, 348.0), 348.0,
		"a row with a column is never shorter than the box it holds")
	_assert_eq(Page.inspector_row_height(500.0, 661.0, 0.0, 348.0), 500.0,
		"…and never taller than its own content just because it holds one")
	_assert_eq(Page.inspector_row_height(2452.0, 661.0, 0.0, 348.0), 661.0,
		"…capped by the budget, which reserves the lanes' minimum")
	# The failure this replaced: a column-bearing row taking the WHOLE budget made the box
	# a function of the window, and on a tall one it grew until the focus column beside it
	# had no width left at all. A 661px budget must not produce a 661px row for 500px of
	# content — that difference is the timeline's.
	_assert_true(Page.inspector_row_height(500.0, 661.0, 0.0, 348.0) < 661.0,
		"a tall window hands the surplus back to the lanes, not to the box")
	# WITHOUT a column the floor is 0 and the rule is unchanged.
	_assert_eq(Page.inspector_row_height(300.0, 661.0, 0.0, 0.0), 300.0,
		"without a column the row fits its content")
	# The FEDS pair band comes off the same budget, and the row may never take what the
	# band has already claimed.
	_assert_eq(Page.inspector_row_height(2452.0, 661.0, 200.0, 348.0), 461.0,
		"a pair band takes its share off the row first")
	_assert_eq(Page.inspector_row_height(2452.0, 661.0, 900.0, 348.0), 0.0,
		"…and a band wider than the budget leaves 0, never a negative row")


func _assert_eq(actual, expected, what: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s\n        expected: %s\n        actual:   %s" % [what, expected, actual])


func _assert_true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Await until `node`'s global rect stops changing (8 consecutive identical frames),
## or give up after `max_frames` and say so rather than measuring a moving target.
func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Rect2()
	var stable := 0
	for i in range(max_frames):
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


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — layout regression skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	_assert_true(page != null, "the studio page exists")
	if page == null:
		return
	# See MEASUREMENT GOTCHA above — without this every rect below is half-width.
	DebugOverlay.show_overlay()
	await _frames(30)
	# `_relayout` reads `_body`, so THAT is the rect that has to have stopped moving
	# before any effect is loaded — not the panel, which is still invisible here.
	await _settle(page._body, "the dashboard body")

	for eff in ["E317", "E019"]:
		await _check(page, eff)


## Drive one real effect to a frame target and assert the four layout invariants.
## E317 (128x128) and E019 (128x256) are deliberately different texture aspects: the
## panel's rect must depend on the LAYOUT BAND, never on the bound texture's shape.
func _check(page, eff_name: String) -> void:
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(eff_name):
			dir = d
	if dir == "":
		print("[SKIP] %s not in the catalogue" % eff_name)
		return
	page._load_effect(dir)
	await _frames(40)
	await _settle(page._body, "the dashboard body after loading %s" % eff_name)
	var data = page._effect_data
	if data == null or data.texture == null:
		print("[SKIP] %s has no texture" % eff_name)
		return

	# A **texture** target, not a frame one. ADR-0130 dec. 10 took the frame screen's
	# right column away from this canvas and gave it to the sequence player: the Texture
	# tab already draws the sheet in the LEFT column with the same handles and the same
	# scope control, so a frame target was paying for one picture twice. `texture` is now
	# the only kind that parks this panel, so that is where its layout is asserted.
	#
	# Everything below is unchanged and still the point of this file — the rect rules that
	# three shipped attempts each broke a different way.
	page._set_root(_Target.texture())
	await _frames(12)
	await _settle(page._frameset_panel, "%s's canvas panel" % eff_name)
	_assert_true(page._frameset_panel.visible, "%s: the canvas is visible for a texture target" % eff_name)
	if not page._frameset_panel.visible:
		return

	var panel: Rect2 = page._frameset_panel.get_global_rect()
	var controls: Rect2 = page._inspector.get_global_rect()
	var timeline: Rect2 = page._scroll.get_global_rect()   # the VISIBLE timeline band
	var bar: Rect2 = (page._frameset_picker.get_parent().get_parent() as Control).get_global_rect()

	# The DebugDashboard window's height is whatever the compositor hands it, and it is
	# not stable across runs: this same unchanged test has measured a body of 153, 507 and
	# 1209 px. Below a certain height the band above the timeline is simply smaller than
	# the panel's irreducible minimum (its chrome plus a canvas floor), and NO layout can
	# satisfy [A] — at body 153 there are 30px of band for an 85px minimum. Asserting
	# through that measures the compositor, not the code, so it is skipped WITH the
	# numbers rather than failed.
	var band_above_timeline: float = timeline.position.y - panel.position.y
	var panel_floor_h: float = page._frameset_panel.get_combined_minimum_size().y
	if band_above_timeline < panel_floor_h:
		print("[SKIP] %s: the dashboard came up too short to express the layout — %.0fpx of band above the timeline for a %.0fpx panel minimum (body %.0fpx)"
			% [eff_name, band_above_timeline, panel_floor_h, page._body.size.y])
		return

	# [A] the reported symptom: it "extends into the timelines section".
	_assert_true(panel.position.y + panel.size.y <= timeline.position.y + 0.5,
		"%s: canvas bottom (%.0f) stays above the timeline top (%.0f)"
			% [eff_name, panel.position.y + panel.size.y, timeline.position.y])

	# [B] two areas of one row: adjacent, never stacked on top of each other.
	_assert_true(not panel.intersects(controls),
		"%s: canvas does not overlap the frame-controls column (controls right=%.0f, canvas left=%.0f)"
			% [eff_name, controls.position.x + controls.size.x, panel.position.x])
	# The row's top edge is shared by the canvas and the LEFT COLUMN'S STACK, which since
	# ADR-0130 begins with the tab strip rather than with the inspector. Asserted as two
	# facts instead of one, which is strictly stronger than the single top-edge equality
	# this replaced: the strip must start exactly where the canvas does (no dead space at
	# the row's top, the drift this check exists to catch), AND the inspector must abut
	# the strip exactly (no gap opened by a stale constant, no overlap).
	var strip: Rect2 = page._tab_strip.get_global_rect()
	_assert_true(absf(panel.position.y - strip.position.y) <= 1.0,
		"%s: canvas and the left column's tab strip share the row's top edge (%.0f vs %.0f)"
			% [eff_name, panel.position.y, strip.position.y])
	_assert_true(absf((strip.position.y + strip.size.y) - controls.position.y) <= 1.0,
		"%s: the inspector abuts the tab strip exactly (strip bottom %.0f, inspector top %.0f)"
			% [eff_name, strip.position.y + strip.size.y, controls.position.y])

	# [C] the #275 regression: a fourth transport browser must never end up underneath.
	_assert_true(not panel.intersects(bar),
		"%s: canvas does not occlude the transport bar (bar bottom=%.0f, canvas top=%.0f)"
			% [eff_name, bar.position.y + bar.size.y, panel.position.y])

	# [D] the row's height is the binding dimension, so an equal width is the largest
	# the canvas can be — a wildly non-square panel means the bound came from elsewhere.
	#
	# Only assertable when the dashboard is tall enough to EXPRESS it. The window is
	# sized by the compositor, and its height varies run to run (measured: 507 usually,
	# but 154 and 1209 both occur). `_relayout`'s band is `h - MIN_CHANNELS_H - BAR_H`,
	# so at h=154 there is no band at all and the panel correctly falls back to its own
	# minimum (231x27) — a squashed canvas there is the layout working, not failing.
	# Asserting through that produced a ~1-in-3 false failure.
	#
	# The chrome term is MEASURED, not a constant. `_CANVAS_CHROME_H := 40.0` was deleted
	# on purpose — it "silently became wrong the moment ADR-0099's scope control was added
	# below the canvas" — and replaced by `_canvas_chrome_h()`, which walks the canvas's
	# containers. Reading the dead constant threw, and a GDScript runtime error aborts the
	# enclosing function, so [D] — the assertion this entire skip guard exists to protect —
	# never ran once, under a green verdict. #465.
	var band: float = page._body.size.y - page.MIN_CHANNELS_H - page._frames_bar.size.y
	if band < page._CANVAS_MIN_SIDE + page._canvas_chrome_h():
		print("[SKIP] %s: dashboard came up %.0f px tall — no room for a square canvas"
			% [eff_name, page._body.size.y])
		return
	var aspect: float = panel.size.x / maxf(panel.size.y, 1.0)
	_assert_true(aspect >= 0.75 and aspect <= 1.33,
		"%s: canvas is approximately square (%.0fx%.0f, aspect %.2f)"
			% [eff_name, panel.size.x, panel.size.y, aspect])
