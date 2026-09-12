extends Node
## Track A — the interactive colour-keyframe track drawn under the Colour ribbon (ADR-0089
## colour-keyframe amendment, "keyframe place/move/delete on the ribbon/sparkline scaffolding").
## The ribbon is a PURE read-out; this separate strip is the editor, sharing the ribbon's
## PARTICLE-AGE axis (0 → lifetime) — the domain a colour curve actually lives in (NOT the
## emitter/timeline playhead, which is ambiguous for over-life curves).
##
## This proves the pure axis maths + the click semantics:
##   • frame_at_x maps a pixel to an age frame on the same axis the ribbon draws;
##   • x_of_frame is its inverse (marker placement lines up under the ribbon bands);
##   • clicking near an existing keyframe SELECTS it; clicking empty axis ADDs one at that age.
##
## Run: godot --path . --quit-after 30 res://tests/ColourKeyframeTrackTest.tscn

const ColourKeyframeTrack = preload("res://src/effects/studio/ColourKeyframeTrack.gd")

var _passed: int = 0
var _failed: int = 0
var _selected_emit: int = -99
var _added_emit: int = -99
var _removed_emit: int = -99


func _ready() -> void:
	_test_frame_at_x_maps_age_axis()
	_test_x_of_frame_is_inverse()
	_test_nearest_keyframe_by_pixels()
	_test_click_near_marker_selects()
	_test_click_empty_axis_adds()
	_test_ghost_frame_targets_empty_age_else_none()
	_test_handles_ride_a_lane_above_the_band()
	_test_track_hosts_the_ribbon_in_the_band_region()
	_test_click_on_the_band_region_adds_by_x()
	_test_right_click_a_handle_requests_remove()
	_test_right_click_empty_requests_nothing()
	_test_a_frame_past_the_life_window_is_out_of_the_domain()
	_test_the_dead_zone_is_never_drawn_or_hit()
	_test_the_dead_zone_is_counted_rather_than_silently_dropped()
	_test_the_band_is_a_fixed_width_not_a_share_of_the_panel()
	_test_pixels_per_frame_is_the_width_over_the_frame_count()
	_test_clicking_the_selected_handle_again_deselects()
	_test_clicking_a_different_handle_selects_it_rather_than_toggling()

	print("\n=== ColourKeyframeTrackTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourKeyframeTrackTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourKeyframeTrackTest")
		get_tree().quit(0)


## Pixel → age frame, floored and clamped to [0, n-1] — the same axis the ribbon bands use.
## THE TRACK'S DOMAIN IS THE RIBBON'S WINDOW (2026-08-19). Keyframes are imported by a
## Douglas-Peucker fit over ALL 160 curve samples and DP always keeps the last point, so
## EVERY colour emitter in the corpus carries one at frame 159 — while the ribbon paints
## only `life_n` bands (median 16 across 2621 colour emitters). `x_of_frame` does not clamp
## and the track does not clip, so those handles used to paint OUTSIDE the control: measured
## on E317 emitter 3, frame 20 at x=540 and frame 26 at x=702 of a 432px track, with frame
## 159 at x=4293. All 27 colour emitters sampled did it; some are mostly dead zone (E241
## emitter 2 has a 2-frame window and 23 of its 24 keyframes beyond it).
##
## `life_n` is `life.max()`, the UPPER bound of what the renderer ever reads — so a handle
## past it edits samples the game never looks at. It is not drawn and not hit; the count is
## stated instead, because silently dropping data is the other way to be wrong here.
func _test_a_frame_past_the_life_window_is_out_of_the_domain() -> void:
	_assert_true(ColourKeyframeTrack.in_window(0, 16), "frame 0 is inside a 16-band window")
	_assert_true(ColourKeyframeTrack.in_window(15, 16), "and so is the last band")
	_assert_true(not ColourKeyframeTrack.in_window(16, 16),
		"but frame 16 is the first age the particle never reaches")
	_assert_true(not ColourKeyframeTrack.in_window(159, 16),
		"and 159 — the fit's terminal point, present on EVERY emitter — is far outside")
	_assert_true(not ColourKeyframeTrack.in_window(-1, 16), "a negative frame is outside too")


func _test_the_dead_zone_is_never_drawn_or_hit() -> void:
	# The regression, in the numbers it was reported with: a 432px track, a 16-band window,
	# and a keyframe at frame 20 whose marker would land at x=540 — 108px past the right edge.
	var kfs := [{"frame": 4, "color": Color.RED}, {"frame": 20, "color": Color.BLUE}]
	_assert_approx(ColourKeyframeTrack.x_of_frame(20, 432.0, 16), 540.0,
		"unclamped, frame 20 maps 108px outside a 432px track")
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 540.0, 432.0, 16, 6.0), -1,
		"a click at its phantom position selects nothing")
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 430.0, 432.0, 16, 6.0), -1,
		"and neither does one at the track's own right edge")
	# The in-window keyframe beside it still works — the filter must not eat the live ones.
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 108.0, 432.0, 16, 6.0), 0,
		"the in-window keyframe is still selectable at its real position")
	# And the returned index is an index into the ORIGINAL array, not a compacted one —
	# the page maps it straight back to `_colour_keyframes` for delete/recolour.
	var kfs2 := [{"frame": 99, "color": Color.RED}, {"frame": 4, "color": Color.BLUE}]
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs2, 108.0, 432.0, 16, 6.0), 1,
		"index 1 comes back as 1 even though index 0 was skipped")


func _test_the_dead_zone_is_counted_rather_than_silently_dropped() -> void:
	var kfs := [{"frame": 0, "color": Color.RED}, {"frame": 4, "color": Color.RED},
		{"frame": 20, "color": Color.RED}, {"frame": 26, "color": Color.RED},
		{"frame": 159, "color": Color.RED}]
	_assert_eq(ColourKeyframeTrack.beyond_count(kfs, 16), 3,
		"E317 emitter 3's three dead-zone keyframes are counted, not forgotten")
	_assert_eq(ColourKeyframeTrack.beyond_count(kfs, 160), 0,
		"an unresolved life window (the 0.2% that paint all 160) has no dead zone at all")
	_assert_eq(ColourKeyframeTrack.beyond_count([], 16), 0, "no keyframes, nothing beyond")


func _test_the_band_is_a_fixed_width_not_a_share_of_the_panel() -> void:
	# It used to take half the section body via EXPAND_FILL, so it grew and shrank with the
	# window and with whatever else was in the row — 432px on a 903px inspector, 567 on an
	# 1187px one. Fixed, so two emitters are comparable and the panel's width is not a term.
	var t := ColourKeyframeTrack.new()
	add_child(t)
	_assert_approx(t.custom_minimum_size.x, ColourKeyframeTrack.band_width,
		"the track declares the fixed band width as its minimum")
	_assert_eq(t.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"and does not expand — a container hands it exactly that width")
	t.queue_free()


func _test_pixels_per_frame_is_the_width_over_the_frame_count() -> void:
	# The author's rule, verbatim: "the distance between frames is a function of total
	# frames". The band spans the same pixels whatever the window, so a 2-frame life gets
	# fat bands and a 40-frame life gets thin ones.
	for n in [2, 8, 16, 32, 40, 160]:
		var w: float = ColourKeyframeTrack.band_width
		var step: float = ColourKeyframeTrack.x_of_frame(1, w, n) \
			- ColourKeyframeTrack.x_of_frame(0, w, n)
		_assert_approx(step, w / float(n),
			"at n=%d one frame is width/n = %.2f px" % [n, w / float(n)])
		_assert_approx(ColourKeyframeTrack.x_of_frame(n, w, n), w,
			"and frame n lands exactly on the band's right edge at n=%d" % n)
	# The corpus number the width was chosen against: a median window of 16 bands over 2621
	# colour emitters, which must stay wider than a handle or the strip reads as one blob.
	_assert_true(ColourKeyframeTrack.band_width / 16.0 > ColourKeyframeTrack.HANDLE_W,
		"at the corpus median (16 bands) a frame is wider than a handle (%.1f > %.1f)"
			% [ColourKeyframeTrack.band_width / 16.0, ColourKeyframeTrack.HANDLE_W])


func _test_frame_at_x_maps_age_axis() -> void:
	_assert_eq(ColourKeyframeTrack.frame_at_x(0.0, 100.0, 10), 0, "x=0 → frame 0")
	_assert_eq(ColourKeyframeTrack.frame_at_x(55.0, 100.0, 10), 5, "x=55 → frame 5")
	_assert_eq(ColourKeyframeTrack.frame_at_x(99.0, 100.0, 10), 9, "x=99 → frame 9")
	_assert_eq(ColourKeyframeTrack.frame_at_x(100.0, 100.0, 10), 9, "x=width clamps to n-1")
	_assert_eq(ColourKeyframeTrack.frame_at_x(-5.0, 100.0, 10), 0, "x<0 clamps to 0")


## Frame → left-edge pixel, matching ColourRibbon's band placement (width·f/n).
func _test_x_of_frame_is_inverse() -> void:
	_assert_approx(ColourKeyframeTrack.x_of_frame(5, 100.0, 10), 50.0, "frame 5 → x=50")
	_assert_approx(ColourKeyframeTrack.x_of_frame(0, 100.0, 10), 0.0, "frame 0 → x=0")


## Nearest keyframe within the hit radius (in pixels), or -1.
func _test_nearest_keyframe_by_pixels() -> void:
	var kfs := [{"frame": 0, "color": Color.RED}, {"frame": 50, "color": Color.BLUE}]
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 52.0, 100.0, 100, 6.0), 1, "x=52 hits kf@50")
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 3.0, 100.0, 100, 6.0), 0, "x=3 hits kf@0")
	_assert_eq(ColourKeyframeTrack.nearest_keyframe(kfs, 25.0, 100.0, 100, 6.0), -1, "x=25 hits nothing")


## Clicking near an existing keyframe emits keyframe_selected(index).
func _test_click_near_marker_selects() -> void:
	var t := _make_track()
	t.keyframe_selected.connect(func(i): _selected_emit = i)
	_selected_emit = -99
	t._gui_input(_click(50.0))
	_assert_eq(_selected_emit, 1, "click @x=50 selects kf index 1")
	t.queue_free()


## Clicking empty axis emits frame_added(frame) at that age.
func _test_click_empty_axis_adds() -> void:
	var t := _make_track()
	t.frame_added.connect(func(f): _added_emit = f)
	_added_emit = -99
	t._gui_input(_click(20.0))
	_assert_eq(_added_emit, 20, "click @x=20 adds a keyframe at age 20")
	t.queue_free()


## A SECOND CLICK ON THE SELECTED HANDLE DESELECTS IT (emits -1). This is the picker's only
## close gesture on this control: clicking empty space is already spoken for (it ADDS), so
## "click off to deselect" was never available here. Without it the picker — whose visibility
## is bound to "a keyframe is selected" — had no way out at all ("how do I close the color
## picker?").
func _test_clicking_the_selected_handle_again_deselects() -> void:
	var t := _make_track()
	t.set_keyframes([{"frame": 0, "color": Color.RED}, {"frame": 50, "color": Color.BLUE}], 1)
	t.keyframe_selected.connect(func(i): _selected_emit = i)
	_selected_emit = -99
	t._gui_input(_click(50.0))
	_assert_eq(_selected_emit, -1, "a second click on the selected handle emits -1 (deselect)")
	_assert_eq(t.selected_index(), -1, "…and the track drops its own highlight with it")
	t.queue_free()


## …but only the SELECTED one toggles. Clicking a different handle is an ordinary select —
## a toggle that fired on any handle would make moving between keyframes a two-click gesture.
func _test_clicking_a_different_handle_selects_it_rather_than_toggling() -> void:
	var t := _make_track()
	t.set_keyframes([{"frame": 0, "color": Color.RED}, {"frame": 50, "color": Color.BLUE}], 0)
	t.keyframe_selected.connect(func(i): _selected_emit = i)
	_selected_emit = -99
	t._gui_input(_click(50.0))
	_assert_eq(_selected_emit, 1, "clicking the OTHER handle selects it")
	_assert_eq(t.selected_index(), 1, "…and it becomes the track's selection")
	t.queue_free()


## ADR-0089 editing-UX amendment (decision 3): a ghost handle telegraphs "click adds here" —
## so `ghost_frame` returns the age a click would ADD at when hovering an EMPTY spot, and -1 over
## a real handle (there a click would SELECT, so no ghost, no accidental add).
func _test_ghost_frame_targets_empty_age_else_none() -> void:
	var t := _make_track()   # real keyframes at frame 0 and 50, n=100, width=100
	_assert_eq(t.ghost_frame(20.0), 20, "hovering an empty age → ghost add-frame at that age")
	_assert_eq(t.ghost_frame(50.0), -1, "hovering a real handle → no ghost (a click there selects)")
	t.queue_free()


## Handles ride a high-contrast lane ABOVE the band (decision 2), not on the coloured band where
## they were hard to see. The lane occupies the top of the track; the band sits below it.
func _test_handles_ride_a_lane_above_the_band() -> void:
	_assert_true(ColourKeyframeTrack.LANE_H > 0.0, "there is a handle lane with real height")
	var t := _make_track_with_band()
	_assert_approx(t.band_top(), ColourKeyframeTrack.LANE_H, "the band starts just below the lane")
	_assert_true(t.handle_y() < t.band_top(), "handles sit in the lane, above the band")
	t.queue_free()


## The track HOSTS the ribbon (a transparent overlay owning clicks over the pure band, decision 2):
## the ribbon is parented into the band region and the track grows to lane + band height.
func _test_track_hosts_the_ribbon_in_the_band_region() -> void:
	var t := ColourKeyframeTrack.new()
	add_child(t)
	t.configure(100)
	var ribbon = load("res://src/effects/studio/ColourRibbon.gd").new()
	t.set_ribbon(ribbon, 22.0)
	_assert_true(ribbon.get_parent() == t, "the track hosts the ribbon (overlay owns the clicks)")
	_assert_approx(t.custom_minimum_size.y, ColourKeyframeTrack.LANE_H + 22.0, "track height = lane + band")
	t.queue_free()


## The BAND is the click target: a click in the band region (below the lane) adds/selects by its
## x exactly like a lane click — the whole coloured strip feels clickable.
func _test_click_on_the_band_region_adds_by_x() -> void:
	var t := _make_track_with_band()
	t.frame_added.connect(func(f): _added_emit = f)
	_added_emit = -99
	t._gui_input(_click_xy(20.0, ColourKeyframeTrack.LANE_H + 4.0))  # y inside the band
	_assert_eq(_added_emit, 20, "a click on the coloured band adds a keyframe at that age")
	t.queue_free()


## ADR-0089 editing-UX amendment (decision 4): right-clicking a real handle requests its removal
## (the curve interps across the gap). Sparse authoring is by delete.
func _test_right_click_a_handle_requests_remove() -> void:
	var t := _make_track()   # real keyframes at frame 0 and 50
	_removed_emit = -99
	t.keyframe_remove_requested.connect(func(i): _removed_emit = i)
	t._gui_input(_right_click(50.0))
	_assert_eq(_removed_emit, 1, "right-click on the kf@50 handle requests removing index 1")
	t.queue_free()


## Right-clicking empty axis removes nothing (there is no keyframe to delete there).
func _test_right_click_empty_requests_nothing() -> void:
	var t := _make_track()
	_removed_emit = -99
	t.keyframe_remove_requested.connect(func(i): _removed_emit = i)
	t._gui_input(_right_click(25.0))
	_assert_eq(_removed_emit, -99, "right-click on empty axis requests no removal")
	t.queue_free()


func _right_click(x: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(x, 6.0)
	return ev


func _make_track_with_band() -> ColourKeyframeTrack:
	var t := ColourKeyframeTrack.new()
	add_child(t)
	# The axis cases below are about the MATHS at a round 100px, not about the band's real
	# width — and a Control cannot be sized under its own minimum, which is now the fixed
	# `band_width`. Drop the floor so `size` means what these tests say it means.
	t.custom_minimum_size.x = 0.0
	t.configure(100)
	var ribbon = load("res://src/effects/studio/ColourRibbon.gd").new()
	t.set_ribbon(ribbon, 22.0)
	t.size = Vector2(100, ColourKeyframeTrack.LANE_H + 22.0)
	t.set_keyframes([{"frame": 0, "color": Color.RED}, {"frame": 50, "color": Color.BLUE}], -1)
	return t


func _click_xy(x: float, y: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(x, y)
	return ev


func _make_track() -> ColourKeyframeTrack:
	var t := ColourKeyframeTrack.new()
	add_child(t)
	t.custom_minimum_size.x = 0.0   # see _make_track_with_band
	t.size = Vector2(100, 12)
	t.configure(100)
	t.set_keyframes([{"frame": 0, "color": Color.RED}, {"frame": 50, "color": Color.BLUE}], -1)
	return t


func _click(x: float) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(x, 6.0)
	return ev


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)


func _assert_eq(got: int, expected: int, label: String) -> void:
	if got == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %d, expected %d)" % [label, got, expected])


func _assert_approx(got: float, expected: float, label: String) -> void:
	if absf(got - expected) < 0.0006:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %f, expected %f)" % [label, got, expected])
