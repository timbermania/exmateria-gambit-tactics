extends Node
## ACCEPTANCE (headful, real E317 — many lanes, enough to scroll): the two UX features end to
## end through the live studio.
##   (A) Selecting an event scrolls it into view — clicking the TOP span grows the inspector over
##       the top lanes (_relayout bottom-anchors them, pushing the clicked span above the window);
##       after the deferred relayout settles the selection must be back inside the visible window.
##   (B) Esc deselects — reaches the Deselected (empty inspection) state: nav emptied, inspector
##       collapsed, no timeline highlight.
##   (C) Two-stage Esc — with a value cell focused, the first Esc drops that FIELD (keeps the
##       selection); only the next Esc deselects. Empirically confirms a focused edit control does
##       not itself swallow Esc in this build (so _unhandled_key_input still fires).
## E317 is chosen over E019 to avoid the concurrent directional-Y session's entanglement, and it
## has the lane count needed to actually scroll. Skips when E317 assets are absent. A screenshot is
## written for the eyeball check.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioDeselectScrollAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const SHOT := "user://deselect_scroll_e317.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioDeselectScrollAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioDeselectScrollAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioDeselectScrollAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E317")):
		print("[SKIP] E317 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	_assert_true(dir != "", "E317 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	# The geometrically TOPMOST span (smallest content-y) — the one _relayout pushes above the
	# visible window when the inspector grows over it, so selecting it genuinely exercises the
	# into-view nudge (a low span would stay visible via the bottom-anchor and no-op the scroll).
	var top_id := _topmost_span_id(page._timeline)
	_assert_true(top_id != "", "E317 has a top span to click")
	if top_id == "":
		return

	# --- (A) Selecting the top span scrolls it into view -----------------------------------
	page._on_span_selected(top_id)
	await _frames(20)   # let the deferred relayout re-scroll AND the into-view nudge settle

	_assert_true(page._inspector.row_count() > 0, "the click opened the inspector (it grew over the lanes)")
	var rect: Rect2 = page._timeline.selected_span_rect()
	var sv: float = float(page._scroll.scroll_vertical)
	var vh: float = page._scroll.size.y
	_assert_true(rect.size.y > 0.0, "the selected span has a drawn rect")
	# The core guarantee: the just-clicked span is inside the visible window, not hidden behind
	# the editor. (Without the fix, _relayout leaves scroll_vertical ≈ editor height, so a top
	# span at y≈2 sits far above the window.)
	# THE NUDGE MUST HAVE RUN, AND MUST HAVE RUN LAST (#453). Without these two the check
	# below is vacuous: measured 2026-08-23, the channel scroll has no range on an idle box
	# (max == page == 442), so `scroll` is pinned at 0, a top span at y=22 is trivially
	# inside the window, and the assertion goes green having never exercised Feature 2 at
	# all. It was green that way for every run on record while `_scroll_selected_into_view`
	# returned -1 ("already visible") EVERY time — reading a `scroll_vertical` that
	# `_relayout`'s deferred write had not yet moved. `saw_pending_settle` is exactly that
	# defect, and it is true on the pre-fix page.
	# GUARDED, and the guard is the point. Called bare, a page without the seam raises
	# `Invalid call. Nonexistent function` — and a GDScript runtime error ABORTS THE
	# ENCLOSING FUNCTION and returns, so `_run()` stops here, the remaining assertions
	# silently never run, and the test prints `[PASS]` off 4 green assertions instead of 15
	# (#462, measured on this very file against the pre-fix page). A missing seam has to be
	# a FAILURE, not an abort that reads as success.
	_assert_true(page.has_method("into_view_debug"),
		"the page exposes the into-view ordering seam (into_view_debug)")
	var dbg: Dictionary = page.into_view_debug() if page.has_method("into_view_debug") else {}
	_assert_true(int(dbg.get("runs", 0)) > 0,
		"the into-view nudge actually ran for this selection (runs=%d)" % int(dbg.get("runs", 0)))
	_assert_true(not bool(dbg.get("saw_pending_settle", true)),
		"the nudge ran AFTER _relayout's scroll write landed, not before it — "
			+ "a nudge that decides against a scroll_vertical about to be overwritten "
			+ "decides against nothing (saw_pending_settle=%s)"
			% str(dbg.get("saw_pending_settle", true)))
	# The scrollbar's own range goes in the message because the two failure modes are only
	# distinguishable by it: `page < max` means the channel list really can scroll and the
	# into-view nudge did not bring the span back, while `page >= max` means there was no
	# scroll range at all and a non-zero `scroll` is impossible — a different bug entirely.
	var vb: VScrollBar = page._scroll.get_v_scroll_bar()
	_assert_true(rect.position.y >= sv - 1.5,
		"the selected span's top is at/below the window top (not hidden behind the editor): "
			+ "rect.y=%.1f scroll=%.1f max=%.1f page=%.1f" % [
				rect.position.y, sv, vb.max_value, vb.page])
	_assert_true(rect.end.y <= sv + vh + 1.5,
		"the selected span's bottom is within the window: rect.end=%.1f window_bottom=%.1f"
			% [rect.end.y, sv + vh])

	# --- (C) Two-stage Esc: a focused value cell eats the first Esc (field cancel), not the sel --
	# The studio page lives in the DebugDashboard Window — its own viewport — so the cell must be
	# a child of the page (that viewport) and focus is read through page.get_viewport().
	var vp = page.get_viewport()
	var cell := LineEdit.new()
	page.add_child(cell)
	cell.grab_focus()
	_assert_true(vp.gui_get_focus_owner() == cell, "a value cell holds focus")
	page._unhandled_key_input(_esc())
	await _frames(2)
	_assert_true(vp.gui_get_focus_owner() == null, "the first Esc drops the focused field")
	_assert_true(not page._nav.is_empty(), "…and keeps the selection (two-stage: field first)")
	cell.queue_free()

	# --- (B) The next Esc (nothing focused) deselects to empty inspection --------------------
	page._unhandled_key_input(_esc())
	await _frames(10)
	_assert_true(page._nav.is_empty(), "Esc empties the nav path (deselected to nothing)")
	_assert_eq(page._timeline.selected_span_id(), "", "Esc clears the timeline highlight")
	_assert_eq(page._inspector.row_count(), 0, "Esc collapses the inspector (empty inspection)")

	# Visual record for the eyeball (field dumps don't count) — the studio's OWN viewport (the
	# DebugDashboard Window), not the root game scene.
	page._on_span_selected(top_id)   # re-select so the shot shows the into-view result
	await _frames(20)
	var img = page.get_viewport().get_texture().get_image()
	var err = img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


# --- helpers ---------------------------------------------------------------

## The id of the span with the smallest content-y (the visually topmost selectable span). Top
## timeline lanes are camera MARKERS, not spans, so this walks the rebuilt hit-rects rather than
## the score's lane order (whose first `spans` entry can sit far down the content).
func _topmost_span_id(tl) -> String:
	tl.rebuild_layout()
	var best_y := INF
	var best_id := ""
	for hit in tl._span_rects:
		var y: float = hit["rect"].position.y
		if y < best_y:
			best_y = y
			best_id = String(hit["span"]["id"])
	return best_id


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	e.echo = false
	return e


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
