extends Node
## The N LIVE REGIONS rule (ADR-0130 dec. 12), asserted against `FramesetCanvas`'s pure
## statics — no live node, no window, no compositor. That is deliberate: the sibling
## acceptance suite documents a ~1-in-3 false failure caused by aiming a simulated press at
## a canvas whose size had not settled, and every rule below is a function of its inputs
## alone, so none of it needs a window to be true.
##
## What is under test, in the ADR's own terms:
##   * GROUPING is ADR-0099 dec. 1+2 — normalised block, EXACT equality. Flips fold onto
##     their twin; partial overlap and containment do NOT fold.
##   * Every distinct region is its own editable box, and the ones that coincide exactly
##     have already become one box, which is what "moved together" means here.
##   * The ANCHOR is a SET, because a region's members can wind differently (419 of 19,518
##     corpus regions do) and picking one member's corner would contradict the rest.
##   * The GRAB PRIORITY is corner-over-body then smaller-over-larger, because 118 corpus
##     region pairs overlap within one frameset, 69 nested and 48 sharing a top-left
##     origin — so the handles genuinely stack and the inner box must stay reachable.
##
## Run: godot --path . --quit-after 4 res://tests/EffectStudioGroupHandlesTest.tscn
## Grep the SUMMARY COUNT, never `[FAIL]` — a coroutine error aborts a suite silently and
## still prints green ([[gdscript-coroutine-errors-abort-tests-silently]]).

const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_exact_equality_folds_into_one_region()
	_test_a_flip_folds_onto_its_twin()
	_test_overlap_and_containment_do_not_fold()
	_test_members_are_recorded_per_region()
	_test_anchor_is_the_set_of_member_windings()
	_test_handle_colour_precedence()
	_test_corner_beats_body_across_regions()
	_test_smaller_region_wins_a_nested_body()
	_test_stacked_corners_resolve_to_the_smaller_region()
	_test_a_miss_picks_nothing()
	_test_regions_are_ordered_largest_first()
	_test_commit_status_names_the_framesets_you_cannot_see()
	_test_a_click_pins_the_region_and_a_drag_still_commits()
	_test_a_pinned_region_is_the_only_one_that_takes_a_press()
	_test_the_pin_does_not_survive_a_rebind()

	print("\n=== EffectStudioGroupHandlesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioGroupHandlesTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioGroupHandlesTest")
		get_tree().quit(0)


static func _frame(x: int, y: int, w: int, h: int) -> Dictionary:
	return {"uv": {"x": x, "y": y, "width": w, "height": h}}


## A live canvas showing two non-overlapping 32x32 regions on a 128x128 sheet, at 1:1 with
## no pan, so a texel is a pixel and the event positions below are readable.
func _live_canvas() -> Control:
	var c = Canvas.new()
	c.size = Vector2(128, 128)
	add_child(c)
	c.bind_frame(_sheet(), {})
	c.bind_group([_frame(0, 0, 32, 32), _frame(64, 64, 32, 32)])
	c.group_live = true
	return c


func _sheet() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(128, 128, false, Image.FORMAT_RGBA8))


func _press(c: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	c._gui_input(e)


func _release(c: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	c._gui_input(e)


func _motion(c: Control, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	c._gui_input(e)


## CLICK-TO-PIN — the gesture that makes every control reading the scope reachable.
##
## ADR-0130 dec. 12d has the scope control FOLLOW THE POINTER, which is the only way to
## state a blast radius before the gesture when N boxes are live. It also means the pointer
## travelling from a box to the facts overlay in the port's corner crosses the sheet and
## rebinds the panel it is travelling towards. A click pins; a drag still commits.
func _test_a_click_pins_the_region_and_a_drag_still_commits() -> void:
	var c := _live_canvas()
	var locked: Array = []
	c.group_region_locked.connect(func(m): locked.append(m))
	var committed: Array = []
	c.group_uv_changed.connect(func(m, uv): committed.append(uv))

	# A press and a release at the same point, with no motion between them.
	_press(c, Vector2(80, 80))
	_release(c, Vector2(80, 80))
	_assert_eq(c.locked_region(), 1, "a click on the second region pins it")
	_assert_eq(locked.size(), 1, "and announces the pin once")
	_assert_eq(committed.size(), 0, "a click is not an edit — nothing is committed")

	# THE SAME PRESS WITH MOTION IS STILL A DRAG. This is the half that must not regress:
	# a click used to BE a zero-length drag that travelled the whole commit path and wrote
	# nothing, so the two gestures were never distinguished at all.
	_press(c, Vector2(80, 80))
	_motion(c, Vector2(88, 88))
	_release(c, Vector2(88, 88))
	_assert_eq(committed.size(), 1, "a press, a move and a release still commit an edit")
	_assert_eq(c.locked_region(), 1, "…and leave the pin where it was")

	# A PRESS ON BARE SHEET RELEASES IT — no chrome, no keyboard.
	_press(c, Vector2(120, 8))
	_assert_eq(c.locked_region(), -1, "a press on empty sheet un-pins")
	c.queue_free()


## While pinned, the other boxes are inert — and inert IN THE PICTURE TOO. Drawing a box
## live while refusing its press is "present, visible, and not hittable", which is the
## defect this surface has now shipped three separate times.
func _test_a_pinned_region_is_the_only_one_that_takes_a_press() -> void:
	var c := _live_canvas()
	var committed: Array = []
	c.group_uv_changed.connect(func(m, uv): committed.append(uv))
	c.set_locked_region(0)

	# Region 1 lives at (64,64)-(96,96) and is NOT the pinned one.
	_press(c, Vector2(80, 80))
	_motion(c, Vector2(88, 88))
	_release(c, Vector2(88, 88))
	_assert_eq(committed.size(), 0, "a drag on an un-pinned region is refused, not silently applied")

	# The pinned one still drags.
	_press(c, Vector2(16, 16))
	_motion(c, Vector2(24, 24))
	_release(c, Vector2(24, 24))
	_assert_eq(committed.size(), 1, "the pinned region is still fully live")

	# AND THE HOVER STOPS SPEAKING, which is the whole point: the panel the author is
	# reaching for must not be replaced by the boxes they cross to reach it.
	var hovered: Array = []
	c.group_region_hovered.connect(func(m): hovered.append(m))
	_motion(c, Vector2(80, 80))
	_assert_eq(hovered.size(), 0, "crossing another box while pinned rebinds nothing")
	c.queue_free()


## The pin is an INDEX into `_group_blocks`, so it cannot outlive them: a stale one would
## pin box 3 of a frameset that now has two.
func _test_the_pin_does_not_survive_a_rebind() -> void:
	var c := _live_canvas()
	c.set_locked_region(1)
	_assert_eq(c.locked_region(), 1, "pinned")
	c.bind_group([_frame(0, 0, 32, 32)])
	_assert_eq(c.locked_region(), -1, "a rebind drops the pin rather than re-pointing it")
	c.queue_free()


## ADR-0099 dec. 2: two frames are one region IFF their normalised blocks are exactly equal.
func _test_exact_equality_folds_into_one_region() -> void:
	var regions: Array = Canvas.group_regions([
		_frame(8, 40, 32, 32), _frame(8, 40, 32, 32), _frame(80, 0, 16, 16)])
	_assert_eq(regions.size(), 2, "two identical blocks + one other = 2 regions")
	_assert_eq(regions[0]["members"].size(), 2, "the identical pair share one region")
	_assert_eq(regions[1]["members"], [2], "the odd one out keeps its own region")


## ADR-0099 dec. 1, the flip fold, with the ADR's own E005 example: `(39,40,-32,32)` and
## `(8,40,32,32)` address the identical block (39 - 32 + 1 = 8), one drawn mirrored.
func _test_a_flip_folds_onto_its_twin() -> void:
	var regions: Array = Canvas.group_regions([_frame(8, 40, 32, 32), _frame(39, 40, -32, 32)])
	_assert_eq(regions.size(), 1, "a mirrored frame folds onto its unmirrored twin")
	_assert_eq(regions[0]["block"], Rect2i(8, 40, 32, 32), "the folded block is the positive one")
	_assert_eq(regions[0]["members"].size(), 2, "both frames are members, so both move together")


## ADR-0099 dec. 2: "not overlapping, not containing, not near." The ADR's E173 case — five
## rects at one origin plus a sprite nested inside their footprint — must stay SIX boxes.
func _test_overlap_and_containment_do_not_fold() -> void:
	var regions: Array = Canvas.group_regions([
		_frame(56, 48, 40, 32), _frame(56, 48, 40, 56), _frame(56, 48, 40, 80),
		_frame(56, 48, 40, 104), _frame(56, 48, 40, 136), _frame(64, 48, 24, 16)])
	_assert_eq(regions.size(), 6, "five overlapping beam lengths + a nested sprite = 6 regions")
	# And a near-miss is not a fold either.
	var near: Array = Canvas.group_regions([_frame(8, 40, 32, 32), _frame(9, 40, 32, 32)])
	_assert_eq(near.size(), 2, "one texel apart is two regions, not one")


func _test_members_are_recorded_per_region() -> void:
	var regions: Array = Canvas.group_regions([
		_frame(0, 0, 8, 8), _frame(64, 64, 32, 32), _frame(0, 0, 8, 8), _frame(64, 64, 32, 32)])
	# Largest first, so the 32x32 region leads.
	_assert_eq(regions[0]["block"], Rect2i(64, 64, 32, 32), "largest region first")
	_assert_eq(regions[0]["members"], [1, 3], "members are frame indices, in order")
	_assert_eq(regions[1]["members"], [0, 2], "and so are the small region's")


## The 2.1% case. Members share the block by construction but not the winding, so the anchor
## is every corner that is SOME member's, never one member's picked out of the set.
func _test_anchor_is_the_set_of_member_windings() -> void:
	var agree: Array = Canvas.group_regions([_frame(8, 40, 32, 32), _frame(8, 40, 32, 32)])
	_assert_eq(agree[0]["anchors"], ["tl"], "members that agree yield exactly one anchor")

	# `(39,40,-32,32)` is the same block wound from the top-RIGHT.
	var split: Array = Canvas.group_regions([_frame(8, 40, 32, 32), _frame(39, 40, -32, 32)])
	_assert_eq(split[0]["anchors"].size(), 2, "members that disagree yield two anchors")
	_assert_true(split[0]["anchors"].has("tl") and split[0]["anchors"].has("tr"),
		"and they are the two corners the members actually wind from")


func _test_handle_colour_precedence() -> void:
	# Agreeing members: exactly one cyan corner, the picture unchanged from a single frame.
	_assert_eq(Canvas.group_handle_color("tl", ["tl"], ""), Canvas.ANCHOR_COLOR,
		"the anchor corner is cyan")
	_assert_eq(Canvas.group_handle_color("br", ["tl"], ""), Canvas.HANDLE_COLOR,
		"a non-anchor corner is yellow")
	# Disagreeing members: BOTH windings are cyan. Two cyan corners is the honest statement.
	_assert_eq(Canvas.group_handle_color("tr", ["tl", "tr"], ""), Canvas.ANCHOR_COLOR,
		"a split region colours every corner some member winds from")
	_assert_eq(Canvas.group_handle_color("bl", ["tl", "tr"], ""), Canvas.HANDLE_COLOR,
		"but not the corners no member winds from")
	# Dragged beats anchor.
	_assert_eq(Canvas.group_handle_color("tl", ["tl"], "tl"), Canvas.DRAGGING_COLOR,
		"the corner being dragged wins over the anchor colour")


## The nested pair: a handle of the inner rect sits inside the outer rect's body. Without
## corner-over-body ACROSS regions, resizing the inner one would move the outer one.
func _test_corner_beats_body_across_regions() -> void:
	var regions: Array = Canvas.group_regions([_frame(0, 0, 64, 64), _frame(16, 16, 16, 16)])
	var draw := Rect2(Vector2.ZERO, Vector2(128, 128))   # 1 texel = 1 px
	var pick: Dictionary = Canvas.pick_region(Vector2(16, 16), regions,
		Vector2(128, 128), draw, Canvas.HANDLE_GRAB)
	_assert_eq(int(pick["index"]), 1, "the inner region takes the press")
	_assert_eq(String(pick["mode"]), "tl", "and takes it by its corner, not the outer body")


func _test_smaller_region_wins_a_nested_body() -> void:
	var regions: Array = Canvas.group_regions([_frame(0, 0, 64, 64), _frame(16, 16, 16, 16)])
	var draw := Rect2(Vector2.ZERO, Vector2(128, 128))
	# Dead centre of the inner rect, far from every handle of both.
	var pick: Dictionary = Canvas.pick_region(Vector2(24, 24), regions,
		Vector2(128, 128), draw, Canvas.HANDLE_GRAB)
	_assert_eq(int(pick["index"]), 1, "a body press inside both takes the SMALLER region")
	_assert_eq(String(pick["mode"]), "body", "by its body")
	# The outer region stays reachable everywhere the inner one is not.
	var outer: Dictionary = Canvas.pick_region(Vector2(50, 50), regions,
		Vector2(128, 128), draw, Canvas.HANDLE_GRAB)
	_assert_eq(int(outer["index"]), 0, "and the larger region is still grabbable outside it")


## 48 corpus pairs share a top-left origin, so their `tl` handles are the same pixel.
func _test_stacked_corners_resolve_to_the_smaller_region() -> void:
	var regions: Array = Canvas.group_regions([_frame(56, 48, 40, 136), _frame(56, 48, 40, 32)])
	var draw := Rect2(Vector2.ZERO, Vector2(256, 256))
	var pick: Dictionary = Canvas.pick_region(Vector2(56, 48), regions,
		Vector2(256, 256), draw, Canvas.HANDLE_GRAB)
	_assert_eq(String(pick["mode"]), "tl", "the stacked corner is still a corner grab")
	_assert_eq(regions[int(pick["index"])]["block"], Rect2i(56, 48, 40, 32),
		"and it resolves to the smaller of the two stacked regions")


func _test_a_miss_picks_nothing() -> void:
	var regions: Array = Canvas.group_regions([_frame(0, 0, 16, 16)])
	var draw := Rect2(Vector2.ZERO, Vector2(128, 128))
	var pick: Dictionary = Canvas.pick_region(Vector2(100, 100), regions,
		Vector2(128, 128), draw, Canvas.HANDLE_GRAB)
	_assert_eq(int(pick["index"]), -1, "a press on empty sheet picks no region")
	_assert_eq(String(pick["mode"]), "", "and starts no drag")
	# An empty group is not a crash.
	var none: Dictionary = Canvas.pick_region(Vector2(10, 10), [],
		Vector2(128, 128), draw, Canvas.HANDLE_GRAB)
	_assert_eq(int(none["index"]), -1, "an empty group picks nothing")


## Drawing order must agree with the hit priority, or a nested sprite is painted UNDER the
## rect it sits inside while being the thing a press there grabs.
func _test_regions_are_ordered_largest_first() -> void:
	var regions: Array = Canvas.group_regions([
		_frame(0, 0, 8, 8), _frame(0, 0, 64, 64), _frame(0, 0, 24, 24)])
	var areas: Array = []
	for r in regions:
		areas.append(r["block"].get_area())
	_assert_eq(areas, [64 * 64, 24 * 24, 8 * 8], "regions are drawn largest-first")


## The author's E317 report: a drag on emitter 6 moved six frames and only one thumbnail
## visibly changed, because that emitter's sequence plays framesets 15, 16 and 22 while the
## region's other five members live in 17-21. The status line has to say so — 81.4% of
## corpus regions reach outside their own frameset, so this is the ordinary case.
func _test_commit_status_names_the_framesets_you_cannot_see() -> void:
	var Page = load("res://src/effects/studio/EffectStudioPage.gd")
	var members: Array = []
	for fs in [15, 17, 18, 19, 20, 21]:
		members.append({"frameset_index": fs, "frame_index": 0})
	var msg: String = Page._region_commit_status(members, 15, {})
	_assert_true(msg.begins_with("Moved 6 frames"), "it still leads with the count")
	_assert_true(msg.contains("5 in framesets 17, 18, 19, 20, 21"),
		"and names the five the view cannot show")
	_assert_true(msg.contains("does not show"), "in those words")

	# A region wholly inside the frameset on screen says nothing extra — no false alarm.
	var local: Array = [{"frameset_index": 15, "frame_index": 0},
		{"frameset_index": 15, "frame_index": 1}]
	_assert_eq(Page._region_commit_status(local, 15, {}), "Moved 2 frames",
		"a region confined to the shown frameset gets no clause")

	# Singular, and the merge clause still rides on the end.
	var one_other: Array = [{"frameset_index": 15, "frame_index": 0},
		{"frameset_index": 22, "frame_index": 0}]
	_assert_true(Page._region_commit_status(one_other, 15, {}).contains("1 in frameset 22"),
		"one elsewhere is singular")
	_assert_true(Page._region_commit_status(one_other, 15,
		{"merges": true, "message": "lands on region (8,40)"}).ends_with("lands on region (8,40)"),
		"the merge announcement still lands last")

	# No frameset in context — nothing to be outside of, so no clause.
	_assert_eq(Page._region_commit_status(members, -1, {}), "Moved 6 frames",
		"with no frameset in context there is no 'elsewhere' to name")


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
