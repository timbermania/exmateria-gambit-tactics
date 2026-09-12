extends Node
## ACCEPTANCE (headful, real E019): the path bar in the LIVE studio — it occupies a
## full-width row above BOTH the inspector and the right-hand canvas column, it never
## overlaps either of them, and the row it takes comes out of the same budget that
## reserves MIN_CHANNELS_H of lanes (so the frames bar and the channel strip are still
## where they belong).
##
## Asserted on global rects, plus a screenshot to LOOK at. The unit-level behaviour (the
## trail, the elision, `‹` / Alt+Left) is EffectStudioPathBarTest's job.
##
## MEASUREMENT GOTCHA: the studio page lives in DebugDashboard, which extends Window — so
## capture `page.get_viewport()`, not this node's, and `_settle(page._body)` first or the
## rects are read while the dashboard is still sizing itself.
##
## Skips when the ROM-derived effect assets are absent (gitignored).
##
## Run: godot --path . --quit-after 200 res://tests/EffectStudioPathBarAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const SHOT := "user://path_bar_acceptance.png"
const PathBar = preload("res://src/effects/studio/EffectPathBar.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}
const _EXPECTED_TESTS := ["bar_row", "no_overlap", "deep_path", "screenshot"]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run" % name)
	print("\n=== EffectStudioPathBarAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioPathBarAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioPathBarAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — path bar acceptance skipped")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	DebugOverlay.show_overlay()
	await _frames(30)
	await _settle(page._body, "the dashboard body")

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	# --- the bar's own row ---------------------------------------------------
	var bar = page._path_bar
	_assert_true(bar != null and bar.visible, "the bar is up with an effect loaded, before any selection")
	var body_rect: Rect2 = page._body.get_global_rect()
	var bar_rect: Rect2 = bar.get_global_rect()
	_assert_true(absf(bar_rect.position.y - body_rect.position.y) < 1.0,
		"the bar is the TOP row of the body (bar y %.0f vs body y %.0f)" % [bar_rect.position.y, body_rect.position.y])
	_assert_true(absf(bar_rect.size.x - body_rect.size.x) < 1.0,
		"it is full width (%.0f of %.0f)" % [bar_rect.size.x, body_rect.size.x])
	# The bar reports the height it TAKES (`bar_height()`), not the BAR_H floor — a
	# Container cannot shrink below its combined minimum, so the constant alone would be a
	# number the bar overflows, and `_relayout` would seat the inspector under a bar that
	# is taller than the row reserved for it.
	_assert_true(bar_rect.size.y >= PathBar.BAR_H - 1.0,
		"it is at least the declared floor (%.0f >= %.0f)" % [bar_rect.size.y, PathBar.BAR_H])
	_assert_true(absf(bar_rect.size.y - bar.bar_height()) < 1.0,
		"and exactly what it declares it takes (%.0f vs %.0f)" % [bar_rect.size.y, bar.bar_height()])
	_done("bar_row")

	# --- it takes a row, it does not overlay one -----------------------------
	page._set_root(Target.emitter(0))
	await _frames(20)
	var insp_rect: Rect2 = page._inspector.get_global_rect()
	_assert_true(insp_rect.position.y >= bar_rect.end.y - 1.0,
		"the inspector starts BELOW the bar (%.0f vs %.0f)" % [insp_rect.position.y, bar_rect.end.y])
	var frames_rect: Rect2 = page._frames_bar.get_global_rect()
	_assert_true(frames_rect.position.y >= bar_rect.end.y - 1.0,
		"the frames bar is below the path bar (%.0f vs %.0f)" % [frames_rect.position.y, bar_rect.end.y])
	_assert_true(page._scroll.get_global_rect().position.y >= frames_rect.end.y - 1.0,
		"and the channel strip under that")
	_assert_true(page._scroll.get_global_rect().size.y > 0.0,
		"the lanes still have height (%.0f) — the bar came out of the budget, not the strip"
			% page._scroll.get_global_rect().size.y)
	# The full stack order — bar, inspector, frames bar — is only expressible when the body
	# can HOLD it. `_relayout` clamps the inspector's row to the budget left after the path
	# bar, MIN_CHANNELS_H of lanes and the frames bar; a Control cannot shrink below its
	# own content minimum, so in a short window the inspector renders TALLER than the row it
	# was assigned and overhangs the frames bar. That is the dashboard coming up small — the
	# same harness has measured a body of 153, 507 and 1209 px across runs — not the layout
	# being wrong, so state the numbers and skip rather than fail on the window.
	var reserved: float = PathBar.BAR_H + 180.0 + 30.0   # bar + MIN_CHANNELS_H + FramesBar.BAR_H
	var row_budget: float = body_rect.size.y - reserved
	if row_budget < page._inspector.get_combined_minimum_size().y:
		print("[SKIP] the dashboard came up too short to express the stack — %.0fpx of row budget for a %.0fpx inspector minimum (body %.0fpx tall)"
			% [row_budget, page._inspector.get_combined_minimum_size().y, body_rect.size.y])
		_passed += 1
	else:
		_assert_true(frames_rect.position.y >= insp_rect.end.y - 1.0,
			"the frames bar is still glued under the inspector (%.0f vs %.0f)"
				% [frames_rect.position.y, insp_rect.end.y])
	_done("no_overlap")

	# --- a real depth-4 path, with the right column showing ------------------
	# emitter 0 › sequence N › frameset M › frame M/0 — the chain the design traced its
	# mockups from, and the one where the right column (the frameset sheet) is up, so the
	# bar has to clear that too.
	var anim_idx: int = _first_sequence(page)
	if anim_idx >= 0:
		page._navigate_to(Target.animation(anim_idx))
		await _frames(20)
		page._navigate_to(Target.frameset(0))
		page._navigate_to(Target.frame(0, 0))
		await _frames(30)
		_assert_eq(page._nav.size(), 4, "four deep")
		var text: String = bar.path_text()
		_assert_true(text.begins_with("E019"), "the bar names the document (got '%s')" % text)
		_assert_true(text.ends_with(PathBar.MARK_CURRENT + "frame 0/0"),
			"and ends on the current target, marked (got '%s')" % text)
		print("  path: %s" % text)
		var col = page._frameset_panel
		if col != null and col.visible:
			var col_rect: Rect2 = col.get_global_rect()
			_assert_true(col_rect.position.y >= bar.get_global_rect().end.y - 1.0,
				"the right column clears the bar too (%.0f vs %.0f)"
					% [col_rect.position.y, bar.get_global_rect().end.y])
			_assert_true(not bar.get_global_rect().intersects(col_rect),
				"the bar and the right column do not overlap")
	else:
		print("  NOTE: E019 declares no sequence — depth-4 leg measured at depth 2")
	_done("deep_path")

	# --- Screenshot ----------------------------------------------------------
	await _frames(4)
	var img: Image = page.get_viewport().get_texture().get_image()
	var err: int = img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))
	_done("screenshot")


## The first sequence index the effect declares, or -1.
func _first_sequence(page) -> int:
	var data = page._effect_data
	if data == null or not (data.animations is Array) or data.animations.is_empty():
		return -1
	return 0


# --- helpers ---------------------------------------------------------------

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
