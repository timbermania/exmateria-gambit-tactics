extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #278): the "Frames browser → pick a frame →
## texture canvas shows the frame's UV box over the real texture" path, end to end through
## the live studio.
##   1. E019's frame browser (page._frameset_picker) is populated with every (frameset,
##      frame) pair from the real parsed effect.
##   2. Picking one (the same _on_frameset_browsed callback a real click fires) sets it as
##      the inspection root — the SAME nav path every other browser (emitter/container) uses.
##   3. The frameset canvas panel becomes visible, bound to the effect's real texture and
##      that frame's real UV rect (not a placeholder/empty state).
##   4. The inspector ALSO shows the frame's editable fields (palette_id/UV/vertices) —
##      canvas and numeric editors are both live for the same frame simultaneously.
## MEASUREMENT GOTCHA: the studio page lives in DebugDashboard, which extends Window —
## a separate OS-level window. A hidden one does not lay out, and even after
## `show_overlay()` its final size arrives from the compositor over an unpredictable
## number of frames (measured across runs: a 507px-tall body usually, but 154 and 1209
## both occur). This test reads `canvas.size` to aim a simulated press, so a window that
## has not settled aims it at a canvas that no longer exists by the time the press lands
## — at a degenerate size the whole 23x23 UV box is smaller than a corner handle and the
## press meant for its body hits `tl`. That was a ~1-in-3 false failure.
##
## Skips when E019 assets are absent (gitignored/ROM-derived). A screenshot is written.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioFramesetCanvasAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const SHOT := "user://effect_frameset_canvas_e019.png"
const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioFramesetCanvasAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFramesetCanvasAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFramesetCanvasAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	# Show the dashboard exactly as F3 does, then wait for it to STOP resizing — see the
	# measurement gotcha above. Everything below measures real rects.
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

	var data = page._effect_data
	_assert_true(data != null and data.texture != null, "E019 loaded a real texture")
	_assert_true(data != null and data.framesets is Array and not data.framesets.is_empty(),
		"E019 has at least one frameset")
	if data == null or data.texture == null or data.framesets.is_empty():
		return

	# --- (1) The frame browser is populated. ---
	_assert_true(page._frameset_picker != null, "the frame browser exists")
	_assert_true(page._frameset_picker.item_count > 1,
		"the frame browser lists at least one real (frameset, frame) pair")

	# --- (2) Picking item 1 (the first real frame) sets it as the inspection root. ---
	var nav_before: int = page._nav.size()
	page._on_frameset_browsed(1)
	await _frames(6)
	_assert_true(page._nav.size() >= 1, "picking a frame pushes/sets an inspection root")
	var target: Dictionary = page._nav.back()
	_assert_eq(str(target.get("kind", "")), "frame", "the new root is a 'frame' target")

	# --- (3) The canvas is visible, bound to the real texture + this frame's real UV. ---
	#
	# THE TEXTURE TAB'S canvas, not the right column's. ADR-0130 dec. 10 took the frame
	# screen's right column away from the frameset canvas and gave it to the sequence
	# player, because the tab already drew the same sheet with the same live handles and
	# the same scope control — two places to drag one box. So the region drag this file
	# exists to prove now happens HERE, and proving it here is strictly more than this
	# file proved before: the tab's commit path (`_on_texture_tab_uv_changed`) had no
	# end-to-end guard at all.
	page._set_active_tab("texture")
	await _frames(8)
	_assert_true(page._texture_panel.visible, "the texture tab is showing for a frame target")
	var tab_canvas = page._texture_panel.canvas()
	_assert_true(tab_canvas._texture == data.texture,
		"the canvas is bound to the effect's real texture")
	var ref: Dictionary = target.get("ref", {})
	var fs = data.framesets[int(ref.get("frameset_index", -1))]
	var expected_frame: Dictionary = fs["frames"][int(ref.get("frame_index", -1))]
	_assert_eq(tab_canvas._frame, expected_frame,
		"the canvas is bound to the SAME frame dict the browser selected")

	# --- (4) The inspector ALSO shows this frame's editable fields (canvas + numerics both live). ---
	var score: Dictionary = page._timeline._score if page._timeline else {}
	var sections: Array = page.Model.inspector_sections(target, data, score)
	var found_palette := false
	for sec in sections:
		for f in sec.get("fields", []):
			if str(f.get("name", "")) == "Palette ID" and str(f.get("shape", "")) == "edit":
				found_palette = true
	_assert_true(found_palette, "the SAME target also projects an editable Palette ID row")

	# --- (5) A real simulated drag on the canvas body MOVES the box, end to end (#279):
	# _gui_input -> uv_rect_changed signal -> page's compound commit -> live frame data. ---
	# The canvas panel is now sized dynamically (max-available layout, #279 follow-up) —
	# settle a couple more frames before reading `canvas.size` for the test's OWN expected-
	# value math, or it can read a stale in-between size the real drag (dispatched slightly
	# later) won't match.
	await _frames(4)
	var canvas = page._texture_panel.canvas()
	await _settle(canvas, "the texture tab's canvas")
	var texture_size := Vector2(data.texture.get_width(), data.texture.get_height())
	# The canvas's OWN draw rect, not a re-derived fit. ADR-0098's amendment opened the
	# viewport at 100% rather than fit, so `texture_rect` is no longer where the sheet is
	# drawn — and aiming a simulated press at a rect the canvas does not use tests the
	# test's arithmetic, not the drag. `current_draw_rect` is what `_gui_input` hit-tests
	# against, and it is what a user aims at because it is what they can see.
	var draw_rect: Rect2 = canvas.current_draw_rect()
	var uv_before: Dictionary = (expected_frame.get("uv", {}) as Dictionary).duplicate()
	var body_center: Vector2 = Canvas.uv_to_canvas_rect(uv_before, texture_size, draw_rect).get_center()
	var motion_pos: Vector2 = body_center + Vector2(20, 15)
	# A press can only mean "body" while the box is bigger than the handles that sit on
	# its corners. At a degenerate dashboard height it is not, and the interaction under
	# test is simply unrepresentable — say so rather than assert through it.
	var box: Rect2 = Canvas.uv_to_canvas_rect(uv_before, texture_size, draw_rect)
	if minf(box.size.x, box.size.y) <= Canvas.HANDLE_SIZE * 2.0:
		print("[SKIP] the dashboard came up too small to drag: the UV box is %.0fx%.0f px"
			% [box.size.x, box.size.y])
		return

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = body_center
	canvas._gui_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = motion_pos
	canvas._gui_input(motion)
	await _frames(2)
	_assert_eq(str(canvas._drag_mode), "body", "the press-on-body + motion enters 'body' (move) drag mode")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion_pos
	canvas._gui_input(release)
	await _frames(6)

	var uv_after: Dictionary = expected_frame.get("uv", {})
	var expected_delta: Vector2 = Canvas.canvas_point_to_texture_pixel(motion_pos, texture_size, draw_rect) \
		- Canvas.canvas_point_to_texture_pixel(body_center, texture_size, draw_rect)
	_assert_eq(int(uv_after.get("x", -1)), int(uv_before.get("x", 0)) + roundi(expected_delta.x),
		"the real drag moved uv.x by the mouse delta, mapped through the SAME texture-pixel math")
	_assert_eq(int(uv_after.get("y", -1)), int(uv_before.get("y", 0)) + roundi(expected_delta.y),
		"the real drag moved uv.y by the mouse delta")
	_assert_eq(int(uv_after.get("width", -1)), int(uv_before.get("width", 0)), "width is unchanged by a move")

	# --- (6) THE REGION MOVED, not just the dragged frame (ADR-0099 dec. 5, end to end). ---
	# Item 1 is E019 frameset 0 / frame 0, whose UV rect (104,176,23x23) is that sheet's
	# BIGGEST region: 30 frames across 15 framesets, one fireball replicated at ten
	# different quad sizes. Before ADR-0099 this drag moved exactly one of them and left
	# the other 29 pointing at the old art with no diagnostic — which is the entire reason
	# the region is the unit of edit. Asserting only the dragged frame (5, above) cannot
	# tell the two behaviours apart, so it is asserted here.
	var block_before: Rect2i = Canvas.normalised_block(uv_before)
	var block_after: Rect2i = Canvas.normalised_block(uv_after)
	var moved_members: Array = Canvas.region_members(data.framesets, block_after)
	var stragglers: Array = Canvas.region_members(data.framesets, block_before)
	_assert_true(moved_members.size() > 1,
		"the dragged frame's rect is genuinely shared (%d members)" % moved_members.size())
	_assert_eq(stragglers.size(), 0,
		"no member was left behind on the old block — %d straggler(s)" % stragglers.size())
	_assert_eq(moved_members.size(), 30,
		"all 30 frames of E019's largest region moved together")
	var framesets_touched := {}
	for m in moved_members:
		framesets_touched[m["frameset_index"]] = true
	_assert_eq(framesets_touched.size(), 15, "spanning all 15 of its framesets")
	# dec. 3: the region owns the rect and NOTHING else. The members deliberately draw at
	# ten different sizes, and a region move must not have quietly flattened them.
	var sizes := {}
	for m in moved_members:
		sizes[m["quad_size"]] = true
	_assert_true(sizes.size() > 1,
		"and they still draw at %d different quad sizes — vertices untouched" % sizes.size())

	# --- Screenshot --- the studio page lives in the DebugDashboard's OWN Window, not the
	# main game viewport this test node sits in — capture page.get_viewport(), not get_viewport().
	await _frames(4)
	var img: Image = page.get_viewport().get_texture().get_image()
	var err: int = img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


# --- helpers ---------------------------------------------------------------
## Await until `node`'s global rect stops changing, or give up and say so rather than
## measuring a moving target.
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
