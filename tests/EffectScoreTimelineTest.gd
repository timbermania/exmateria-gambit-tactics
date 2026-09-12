extends Node
## TDD guard for EffectScoreTimeline's hit-test routing — the CONTEXT invariant
## "seek here vs inspect this must never fight over one click". Exercises the pure
## layout + hit_test seam (no paint) against a real projected score. See CONTEXT.md
## "Effect Studio" / "Playhead / scrub" / "Keyframe inspector".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectScoreTimelineTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_span_click_selects_not_seeks()
	_test_empty_lane_area_seeks()
	_test_gutter_is_inert()
	_test_seek_emits_and_moves_playhead()
	_test_drag_scrubs_playhead()
	_test_span_press_does_not_scrub()
	_test_motion_without_press_is_inert()
	_test_right_click_span_requests_context()
	_test_right_click_off_span_no_context()
	_test_right_click_marker_center_requests_span_context()
	_test_right_click_gap_requests_lane_context()
	_test_right_click_outside_lane_rows_requests_nothing()
	_test_right_click_particle_gap_requests_lane_context()
	_test_default_view_shows_first_70_frames()
	_test_pan_can_go_before_zero()
	_test_section_header_toggles_collapse()
	_test_compiled_markers_select_and_fan_stays_clickable()
	_test_coincident_markers_share_a_tie_at_true_frame_x()
	_test_reproject_preserves_selection_and_refreshes_geometry()
	_test_reproject_drops_selection_when_the_span_is_gone()
	_test_sound_trigger_instant_and_ghost_rect()
	_test_overlapping_sound_triggers_both_selectable()
	_test_overlapping_select_picks_nearest_fire()
	_test_loose_near_miss_selects_nearest_marker()
	_test_loose_pass_prefers_event_over_nearer_terminator()
	_test_loose_pass_is_lane_scoped()
	_test_sound_ghost_carries_energy_envelope()
	_test_sound_anchor_handle_rect_and_hit()
	_test_sound_anchor_drag_emits_offset()
	_test_set_anchor_offset_reprojects_without_reset()
	_test_sound_fire_handle_and_precedence()
	_test_sound_terminator_selectable_not_fire_draggable()
	_test_sound_fire_drag_emits_target_frame()
	_test_fire_drag_is_relative_no_grab_jump()
	_test_camera_edge_grip_and_drag_emits_frame()
	_test_a_short_span_keeps_a_body_to_grab()
	_test_a_wide_span_still_gives_its_right_edge_to_the_grip()
	_test_reproject_preserves_playhead()
	_test_reproject_preserves_selection_audibility_end_and_zoom()
	_test_reproject_drops_stale_selection_and_audibility()
	_test_gap_edit_reprojects_shifts_later_markers_preserving_transport()
	_test_spacer_label_wins_on_any_colour_lane()
	_test_spacer_hatch_segments_fill_the_rect()
	_test_selected_span_rect_tracks_the_selection()
	_test_pacing_strip_sits_below_the_phase_lanes()
	_test_pacing_band_click_selects_the_curve()
	_test_no_pacing_strip_without_a_time_scale()
	_test_pacing_outline_present_even_at_normal_speed()
	_test_pacing_outline_rises_for_slow_mo()
	_test_pacing_fill_survives_horizontal_scroll()
	_test_pacing_flat_band_has_no_fill()

	print("\n=== EffectScoreTimelineTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScoreTimelineTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScoreTimelineTest")
		get_tree().quit(0)


func _test_span_click_selects_not_seeks() -> void:
	var tl = _timeline()
	var span := _first_span(tl)
	_assert_true(not span.is_empty(), "the score has a span to click")
	# Midpoint of the span, in the lane band (below the ruler).
	var mid_frame := (float(span["start"]) + float(span["end"])) * 0.5
	var x: float = tl.axis.frame_to_x(mid_frame)
	# Find the span's row y from the rebuilt layout.
	var y := _span_row_y(tl, span["id"])
	var hit = tl.hit_test(Vector2(x, y))
	_assert_eq(hit["kind"], "select", "a click on a span selects, does not seek")
	_assert_eq(hit["span_id"], span["id"], "the clicked span is the selected one")


func _test_empty_lane_area_seeks() -> void:
	var tl = _timeline()
	# Far right of the lane band, past every span → empty area seeks.
	var y := _span_row_y(tl, _first_span(tl)["id"])
	var x: float = tl.axis.frame_to_x(float(tl._score["max_frame"]) + 50.0)
	var hit = tl.hit_test(Vector2(x, y))
	_assert_eq(hit["kind"], "seek", "empty lane area seeks (never selects nothing)")


func _test_gutter_is_inert() -> void:
	var tl = _timeline()
	# A point in the label gutter (x < GUTTER_W) on a lane row — the ruler that used
	# to sit at the top is gone (it's now the detached frames bar), so we probe a lane.
	var hit = tl.hit_test(Vector2(10.0, _empty_lane_y(tl)))
	_assert_eq(hit["kind"], "none", "the label gutter routes to no transport intent")


func _test_seek_emits_and_moves_playhead() -> void:
	# A press in an EMPTY lane row seeks (the timeline keeps the empty-area seek
	# surface; the ruler-band seek moved to the frames bar). See EffectFramesBarTest.
	var tl = _timeline()
	var seen := {"frame": -1}
	tl.seek_requested.connect(func(f): seen["frame"] = f)
	tl.select_span("")   # clear
	var y := _empty_lane_y(tl)
	var f := 9.0
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(tl.axis.frame_to_x(f), y)
	tl._gui_input(ev)
	_assert_eq(seen["frame"], 9, "an empty-lane press emits seek_requested with the frame")
	_assert_eq(tl.get_playhead(), 9, "and moves the playhead there")


func _test_drag_scrubs_playhead() -> void:
	# left-press in an empty lane, then hold+drag: every motion continuously seeks to
	# the frame under the cursor and the playhead follows (motion uses x only, so the
	# drag scrubs even across spans once armed).
	var tl = _timeline()
	var y := _empty_lane_y(tl)
	var seen := {"frame": -1, "count": 0}
	tl.seek_requested.connect(func(f):
		seen["frame"] = f
		seen["count"] += 1)
	_press(tl, 5.0, y)
	_assert_eq(seen["frame"], 5, "initial press seeks to the frame under it")
	# Drag across several increasing frames.
	for target in [10.0, 24.0, 41.0]:
		_move(tl, target, y)
		_assert_eq(seen["frame"], int(target), "drag seeks to frame %d under the cursor" % int(target))
		_assert_eq(tl.get_playhead(), int(target), "playhead follows the drag to %d" % int(target))
	# Backward drag scrubs too.
	_move(tl, 3.0, y)
	_assert_eq(tl.get_playhead(), 3, "backward drag scrubs the playhead left")
	# Release ends the scrub; later motion is inert.
	_release(tl, 3.0, y)
	var before: int = seen["count"]
	_move(tl, 50.0, y)
	_assert_eq(seen["count"], before, "motion after release does not seek")


func _test_span_press_does_not_scrub() -> void:
	# Pressing a span selects (inspect); dragging off it must NOT hijack into a scrub.
	var tl = _timeline()
	var span := _first_span(tl)
	var seek_seen := {"count": 0}
	var select_seen := {"id": ""}
	tl.seek_requested.connect(func(_f): seek_seen["count"] += 1)
	tl.span_selected.connect(func(id): select_seen["id"] = id)
	var mid_frame := (float(span["start"]) + float(span["end"])) * 0.5
	var y := _span_row_y(tl, span["id"])
	_press(tl, mid_frame, y)
	_assert_eq(select_seen["id"], span["id"], "pressing a span selects it")
	var ph = tl.get_playhead()
	_move(tl, mid_frame + 20.0, y)
	_assert_eq(seek_seen["count"], 0, "dragging after a span press does not scrub")
	_assert_eq(tl.get_playhead(), ph, "the playhead stays put after a span press+drag")


func _test_motion_without_press_is_inert() -> void:
	# Hover (motion with no prior press) must not move the playhead.
	var tl = _timeline()
	var seek_seen := {"count": 0}
	tl.seek_requested.connect(func(_f): seek_seen["count"] += 1)
	_move(tl, 15.0, _empty_lane_y(tl))
	_assert_eq(seek_seen["count"], 0, "bare hover does not seek")
	_assert_eq(tl.get_playhead(), 0, "bare hover leaves the playhead at 0")


func _test_right_click_span_requests_context() -> void:
	# Right-click a keyframe span → request its context menu AND select it (so the
	# inspector shows the keyframe being addressed).
	var tl = _timeline()
	var span := _first_span(tl)
	# The signal carries the span id AND the frame under the cursor (an Add-here cuts the
	# span AT that frame — ADR-0086 dec. 7).
	var seen := {"id": "", "count": 0, "frame": -1}
	tl.span_context_requested.connect(func(id, frame):
		seen["id"] = id
		seen["frame"] = frame
		seen["count"] += 1)
	var mid_frame := (float(span["start"]) + float(span["end"])) * 0.5
	var y := _span_row_y(tl, span["id"])
	_right_press(tl, mid_frame, y)
	_assert_eq(seen["id"], span["id"], "right-click a span requests its context menu")
	_assert_eq(seen["count"], 1, "one context request per right-click")
	_assert_true(abs(float(seen["frame"]) - mid_frame) <= 1.0,
		"the context request carries the frame under the cursor")
	_assert_eq(tl.selected_span_id(), span["id"], "right-click also selects the keyframe")


func _test_right_click_off_span_no_context() -> void:
	# Right-click an empty lane area → no keyframe menu (nothing to address).
	var tl = _timeline()
	var seen := {"count": 0}
	tl.span_context_requested.connect(func(_id, _frame): seen["count"] += 1)
	_right_press(tl, 9.0, _empty_lane_y(tl))
	_assert_eq(seen["count"], 0, "right-click off a span opens no keyframe menu")


## A right-click never starts a drag, so a right-click DEAD CENTER on a draggable
## instant marker (where the fire grab wins the hit-test) must still open the span's
## context menu — not silently do nothing because the hit kind was "fire".
func _test_right_click_marker_center_requests_span_context() -> void:
	var tl = _timeline_with_two_triggers()
	tl.axis.pixels_per_frame = 10.0
	tl.rebuild_layout()
	var sid1 := "sound:for_each:0#1"   # draggable — its fire grab owns the marker center
	var seen := {"id": "", "count": 0}
	tl.span_context_requested.connect(func(id, _frame):
		seen["id"] = id
		seen["count"] += 1)
	var y := _span_row_y(tl, sid1)
	_right_press(tl, 12.0, y)   # the fire frame — hit kind is "fire" here
	_assert_eq(seen["count"], 1, "right-click on the marker center opens the context menu")
	_assert_eq(seen["id"], sid1, "…for the marker's own trigger")
	_assert_eq(tl.selected_span_id(), sid1, "…and selects it (the inspector shows the address)")


## Sound "add here" targets a GAP, which on the timeline is EMPTY lane space — so a
## right-click on a lane row that hits no span emits lane_context_requested(lane_id,
## frame): the host offers the lane-level verbs (Add sound event here) at that frame.
func _test_right_click_gap_requests_lane_context() -> void:
	var tl = _timeline_with_two_triggers()
	tl.axis.pixels_per_frame = 10.0
	tl.rebuild_layout()
	var sid1 := "sound:for_each:0#1"
	var seen := {"lane": "", "frame": -1, "count": 0, "spans": 0}
	tl.lane_context_requested.connect(func(lane_id, frame):
		seen["lane"] = lane_id
		seen["frame"] = frame
		seen["count"] += 1)
	tl.span_context_requested.connect(func(_id, _frame): seen["spans"] += 1)
	# Frame 15: 30px right of the trigger at 12 — beyond the loose tolerance, inside
	# the gap before the terminator at 22. A LEFT click here seeks; a RIGHT click
	# addresses the gap.
	_right_press(tl, 15.0, _span_row_y(tl, sid1))
	_assert_eq(seen["count"], 1, "right-click in a lane gap requests the lane context menu")
	_assert_eq(seen["lane"], "sound:for_each:0", "…carrying the clicked lane's id")
	_assert_eq(seen["frame"], 15, "…and the frame under the cursor (where the event lands)")
	_assert_eq(seen["spans"], 0, "…and no span menu (nothing exact was hit)")


## Outside every lane row — the gutter, or below the last lane — a right-click
## addresses nothing: neither menu signal fires.
func _test_right_click_outside_lane_rows_requests_nothing() -> void:
	var tl = _timeline_with_two_triggers()
	tl.axis.pixels_per_frame = 10.0
	tl.rebuild_layout()
	var seen := {"count": 0}
	tl.lane_context_requested.connect(func(_l, _f): seen["count"] += 1)
	tl.span_context_requested.connect(func(_id, _frame): seen["count"] += 1)
	# Below the last lane row (past the content).
	_right_press(tl, 15.0, tl._content_h + 20.0)
	# The label gutter (x < GUTTER_W) on a lane row.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(10.0, _span_row_y(tl, "sound:for_each:0#1"))
	tl._gui_input(ev)
	_assert_eq(seen["count"], 0, "right-clicks outside the lane rows open no menu")


## ADR-0089 particle_timeline (Add in a gap): right-clicking the EMPTY stretch of a particle
## lane row is a "seek" hit — no span to address — so it emits the new lane_context_requested
## carrying the lane id (so the page resolves phase + channel) and the score-absolute cursor
## frame (so Add lands under the cursor). This is the entry point the drawn-span
## span_context_requested has no counterpart for on empty space.
func _test_right_click_particle_gap_requests_lane_context() -> void:
	var tl = _timeline()
	_assert_true(tl.has_signal("lane_context_requested"),
		"the timeline declares the lane_context_requested signal")
	if not tl.has_signal("lane_context_requested"):
		return
	var seen := {"lane_id": "", "frame": -1, "count": 0}
	tl.lane_context_requested.connect(func(lane_id, frame):
		seen["lane_id"] = lane_id
		seen["frame"] = frame
		seen["count"] += 1)
	# The empty particle channel (index 1) row — a gap at every x. Right-click at absolute frame 20.
	var empty_lane_id := _empty_lane_id(tl)
	_right_press(tl, 20.0, _empty_lane_y(tl))
	_assert_eq(seen["count"], 1, "right-click a particle gap requests one lane context")
	_assert_eq(seen["lane_id"], empty_lane_id, "…carrying the lane's id (phase + channel)")
	_assert_true(abs(float(seen["frame"]) - 20.0) <= 1.0,
		"…and the score-absolute frame under the cursor")


func _test_default_view_shows_first_70_frames() -> void:
	# On load the timeline zooms so frames 0..DEFAULT_VIEW_FRAMES fill the frame area
	# (frame 0 at the left edge), instead of fitting the whole padded span.
	var tl = _timeline()
	tl._resolve_default_view()
	_assert_true(is_equal_approx(tl.axis.frame_to_x(0.0), Timeline.GUTTER_W + Timeline.PAD_X),
		"frame 0 sits at the left edge of the frame area")
	_assert_true(absf(tl.axis.frame_to_x(Timeline.DEFAULT_VIEW_FRAMES) - (tl.size.x - Timeline.PAD_X)) < 2.0,
		"frame 70 lands at the right edge — the first 70 frames fill the view")


func _test_pan_can_go_before_zero() -> void:
	# Middle-drag rightward → scroll_x goes negative (frame 0 leaves the left edge);
	# the old scroll_x>=0 clamp that snapped 0 back to the left is gone.
	var tl = _timeline()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(500.0, 100.0)
	tl._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(620.0, 100.0)   # dragged right by 120px
	tl._gui_input(move)
	_assert_true(tl.axis.scroll_x < 0.0, "panning right pushes scroll_x negative (space before frame 0)")
	_assert_true(tl.axis.frame_to_x(0.0) > Timeline.GUTTER_W + Timeline.PAD_X,
		"frame 0 has moved right of the left edge — no snap-back to 0")


# --- capability probes -----------------------------------------------------

## Does `obj` declare `method` taking EXACTLY `n_args` arguments?
##
## `has_method` answers only "is there a name", so a capability guard built on it passes
## while the call it guards is impossible — the call then throws, and a GDScript runtime
## error ABORTS THE ENCLOSING FUNCTION, so the clean red the guard exists to produce comes
## out as a silent green with the rest of the test unrun. `get_method_list` carries `args`,
## which is the fact the guard actually needs. #465.
func _declares(obj: Object, method: String, n_args: int) -> bool:
	for m in obj.get_method_list():
		if String(m.get("name", "")) == method:
			return (m.get("args", []) as Array).size() == n_args
	return false


# --- input synthesis helpers ----------------------------------------------

func _press(tl, frame: float, y: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(tl.axis.frame_to_x(frame), y)
	tl._gui_input(ev)


func _release(tl, frame: float, y: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(tl.axis.frame_to_x(frame), y)
	tl._gui_input(ev)


func _move(tl, frame: float, y: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(tl.axis.frame_to_x(frame), y)
	tl._gui_input(ev)


## Pixel-addressed variants — press/move at an EXACT local x (not a frame), so a test can
## grab a handle OFF the marker's frame center or at a coarse zoom where whole frames fall
## between pixels (the fire-drag relative-grab guard).
func _press_px(tl, x: float, y: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(x, y)
	tl._gui_input(ev)


func _move_px(tl, x: float, y: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(x, y)
	tl._gui_input(ev)


func _release_px(tl, x: float, y: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(x, y)
	tl._gui_input(ev)


func _right_press(tl, frame: float, y: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(tl.axis.frame_to_x(frame), y)
	tl._gui_input(ev)


## A phase section header is clickable: a click on it routes to a "toggle" intent,
## and toggling collapses the section — its lanes/spans drop from layout while the
## header stays (so it can be re-expanded). This keeps the all-channels console
## navigable.
func _test_section_header_toggles_collapse() -> void:
	var tl = _timeline()
	_assert_true(tl._section_rows.size() >= 1, "the score has at least one phase section")
	var sec: Dictionary = tl._section_rows[0]
	var phase: String = sec["phase"]
	var hrect: Rect2 = sec["rect"]
	var header_center: Vector2 = hrect.position + hrect.size * 0.5
	var hit = tl.hit_test(header_center)
	_assert_eq(hit["kind"], "toggle", "clicking a section header routes to a collapse toggle")
	_assert_eq(hit["phase"], phase, "the toggle carries the section's phase")

	_assert_true(not tl.is_section_collapsed(phase), "sections start expanded")
	var lanes_before: int = tl._lane_rows.size()
	_assert_true(lanes_before > 0, "the expanded section shows its lanes")
	tl.toggle_section(phase)
	_assert_true(tl.is_section_collapsed(phase), "toggling collapses the section")
	_assert_eq(tl._lane_rows.size(), 0, "a collapsed section drops its lane rows")
	_assert_eq(tl._span_rects.size(), 0, "a collapsed section drops its span hit-rects")
	_assert_eq(tl._section_rows.size(), 1, "the header survives collapse (re-expandable)")
	tl.toggle_section(phase)
	_assert_eq(tl._lane_rows.size(), lanes_before, "re-expanding restores the lanes")


## Compiled camera keyframes render as POINT markers (not intervals). A click at a
## marker's center selects it; and two coincident split siblings (angle@10 + position@10)
## are FANNED apart so each has its own hit box and stays individually clickable — the
## split's whole payoff would be lost if the second sibling sat unreachable under the first.
func _test_compiled_markers_select_and_fan_stays_clickable() -> void:
	var tl = _timeline_with_camera_split()
	# Two markers on the compiled lane, coincident in frame but fanned in x.
	var markers: Array = []
	for m in tl._marker_rects:
		if str(m["span"].get("kind", "")) == "camera_compiled":
			markers.append(m)
	_assert_eq(markers.size(), 2, "the split shows two compiled point markers")
	var c0: Vector2 = markers[0]["center"]
	var c1: Vector2 = markers[1]["center"]
	_assert_true(absf(c0.x - c1.x) >= Timeline.MARKER_FAN - 0.01,
		"coincident siblings are fanned apart in x (both clickable)")
	var h0 = tl.hit_test(c0)
	var h1 = tl.hit_test(c1)
	_assert_eq(h0["kind"], "select", "clicking a marker selects (does not seek)")
	_assert_eq(h0["span_id"], markers[0]["span"]["id"], "the first marker selects its own keyframe")
	_assert_eq(h1["span_id"], markers[1]["span"]["id"], "the second, fanned marker is reachable too")
	_assert_true(h0["span_id"] != h1["span_id"], "the two siblings select DISTINCT keyframes")


## The fan keeps coincident siblings clickable but nudges them OFF the true frame x, so a
## split reads as several markers at nearby frames rather than one coincident group (#285).
## A coincidence TIE — one per fanned group, anchored at the TRUE frame x and bracketing the
## fanned centers — restores the "these all belong to frame N" read. A lone marker gets none.
func _test_coincident_markers_share_a_tie_at_true_frame_x() -> void:
	var tl = _timeline_with_camera_split()   # two markers coincident at frame 10

	_assert_eq(tl._marker_ties.size(), 1, "the coincident pair yields exactly one tie")
	var tie: Dictionary = tl._marker_ties[0]

	# The two siblings share one frame (start); the tie must sit at THAT frame's true x.
	var markers: Array = []
	for m in tl._marker_rects:
		if str(m["span"].get("kind", "")) == "camera_compiled":
			markers.append(m)
	var true_x: float = tl.axis.frame_to_x(float(markers[0]["span"]["start"]))
	_assert_true(absf(float(tie["center_x"]) - true_x) < 0.01,
		"the tie is anchored at the TRUE frame x, not a fanned center")
	var min_cx: float = minf(markers[0]["center"].x, markers[1]["center"].x)
	var max_cx: float = maxf(markers[0]["center"].x, markers[1]["center"].x)
	_assert_true(float(tie["left_x"]) <= min_cx + 0.01, "the tie reaches the left sibling")
	_assert_true(float(tie["right_x"]) >= max_cx - 0.01, "the tie reaches the right sibling")


## A non-structural timing edit (a camera keyframe's end_frame) changes lane GEOMETRY but
## not the field set, so the host asks the timeline to reproject the SAME document. Unlike
## load_score (which resets a fresh document), reproject_score must REFRESH the span geometry
## while PRESERVING the author's selection — else nudging end_frame would drop the inspector
## target on every tick. (The stale-timeline bug: end_frame edits never reached the timeline.)
func _test_reproject_preserves_selection_and_refreshes_geometry() -> void:
	var ed = _camera_effect_phase1()   # angle-only keyframe, end_frame 8
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()

	var span: Dictionary = _lane_first_span(tl, "camera:phase1:angle")
	tl.select_span(span["id"])
	var w_before: float = _span_width(tl, span["id"])

	# The author drags the keyframe's end_frame out; reproject the SAME document.
	ed.camera.get_table("phase1").get_keyframe(0).end_frame = 40
	tl.reproject_score(Model.build(ed))

	_assert_eq(tl.selected_span_id(), String(span["id"]),
		"selection survives a reproject (the span still exists)")
	_assert_true(_span_width(tl, span["id"]) > w_before + 0.01,
		"the span widened to the new end_frame (geometry refreshed)")


## If the edit makes the selected span disappear (end_frame collapses to a zero-width no-op),
## reproject drops the now-dangling selection rather than pointing at nothing.
func _test_reproject_drops_selection_when_the_span_is_gone() -> void:
	var ed = _camera_effect_phase1()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	tl.select_span("camera:phase1:angle#0")

	ed.camera.get_table("phase1").get_keyframe(0).end_frame = 0   # collapses the span away
	tl.reproject_score(Model.build(ed))

	_assert_eq(tl.selected_span_id(), "", "a selection whose span vanished is dropped")
# --- reproject_score: structural re-render preserves transport ------------

## A structural edit (e.g. a Blend↔Gradient kind flip) re-renders the SAME document via
## reproject_score, which — unlike load_score (fresh document) — must PRESERVE the parked
## playhead. Regression guard for "flipping Kind resets the play mode" (playhead → 0).
func _test_reproject_preserves_playhead() -> void:
	var tl = _timeline()
	tl.set_playhead(37)
	tl.reproject_score(tl._score)   # re-render the same score (structural refresh)
	_assert_eq(tl.get_playhead(), 37, "reproject_score preserves the parked playhead")


## reproject_score keeps the WHOLE authoring place: the selected span, per-lane solo/mute,
## the derived end-frame marker, and the zoom — none of which load_score keeps. This is the
## full preserve contract that separates the two verbs.
func _test_reproject_preserves_selection_audibility_end_and_zoom() -> void:
	var tl = _timeline()
	var span_id: String = _first_span(tl)["id"]
	var lane_id: String = tl._score["lanes"][0]["id"]
	tl.select_span(span_id)
	tl.toggle_mute(lane_id)
	tl.toggle_solo(lane_id)
	tl.set_end_frame(52)
	var ppf_before: float = 3.5
	tl.axis.pixels_per_frame = ppf_before   # a non-default zoom the author dialed in

	tl.reproject_score(tl._score)

	_assert_eq(tl.selected_span_id(), span_id, "reproject preserves the span selection")
	_assert_true(tl.is_lane_muted(lane_id), "reproject preserves mute")
	_assert_true(tl.is_lane_soloed(lane_id), "reproject preserves solo")
	_assert_eq(tl.get_end_frame(), 52, "reproject preserves the derived end-frame marker")
	_assert_eq(tl.axis.pixels_per_frame, ppf_before, "reproject preserves the zoom (no default-view re-fit)")


## Preservation is defensive: if the reshape DROPS the selected span or a soloed/muted lane
## (a future structural edit that removes a keyframe/lane), reproject clears the now-dangling
## selection + audibility keys rather than pointing the inspector/preview at ghosts.
func _test_reproject_drops_stale_selection_and_audibility() -> void:
	var tl = _timeline()
	var span_id: String = _first_span(tl)["id"]
	var lane_id: String = tl._score["lanes"][0]["id"]
	tl.select_span(span_id)
	tl.toggle_mute(lane_id)
	tl.toggle_solo(lane_id)
	# Re-render a document that no longer contains that span/lane.
	tl.reproject_score({"lanes": [], "phases": [], "max_frame": 0})
	_assert_eq(tl.selected_span_id(), "", "reproject drops a selection whose span vanished")
	_assert_true(not tl.is_lane_muted(lane_id), "reproject drops mute for a vanished lane")
	_assert_true(not tl.is_lane_soloed(lane_id), "reproject drops solo for a vanished lane")


# --- fixtures -------------------------------------------------------------

## Slice 1 (ADR-0086 dec. 11): a camera sub-channel span carries a
## right-EDGE grip. Pressing it arms an edge drag and emits edge_dragged(span_id, ABSOLUTE
## snapped frame) as you move — the timeline REPORTS intent only (no clamp, no mutate; the
## host clamps to (prev_end,next_end) and reprojects). Press brackets the gesture with
## edge_drag_started / edge_drag_ended, exactly like the sound fire-drag seam.
func _test_camera_edge_grip_and_drag_emits_frame() -> void:
	var tl = _camera_two_angle_timeline()   # angle spans [0,8) and [8,20)
	var sid0 := "camera:phase1:angle#0"     # its right edge is the boundary at frame 8
	_assert_true(tl.has_signal("edge_dragged") and tl.has_signal("edge_drag_started") \
		and tl.has_signal("edge_drag_ended"), "the timeline declares the edge-drag signals")
	# ARITY-AWARE (#465). `has_method` is blind to argument count, so the old guard passed
	# while the call below was impossible — the runtime error aborted this function and the
	# 201 assertions after it silently never ran under a green verdict. `get_method_list`
	# carries the declared args, so a signature drift now scores the clean red the guard
	# was written to produce.
	_assert_true(_declares(tl, "edge_rect_for", 1),
		"the timeline exposes edge_rect_for(span_id) — one argument")
	if not (_declares(tl, "edge_rect_for", 1) and tl.has_signal("edge_dragged") \
		and tl.has_signal("edge_drag_started") and tl.has_signal("edge_drag_ended")):
		return   # clean red: the capability isn't built yet

	# The grip sits on the span's RIGHT edge (frame 8 — its end_frame), a grabbable band.
	var edge0: Rect2 = tl.edge_rect_for(sid0)
	_assert_true(edge0.size.x > 0.0, "a camera span has a right-edge grip")
	_assert_true(absf(edge0.get_center().x - tl.axis.frame_to_x(8.0)) < 3.0,
		"the grip sits on the span's right edge (its end_frame)")
	# ONE GRIP PER SPAN, RIGHT EDGE ONLY. ADR-0095 briefly split this band in two and gave
	# every signal a `side`; it was SUPERSEDED on 2026-08-21 by ADR-0086 dec. 23
	# ("a hold's boundary grip speaks for its neighbour"), whose build is what shipped. The
	# two-sided assertions outlived their build by three days because the supersession removed
	# ADR-0095's three whole suites but not its edits to this one — and the `side` argument
	# threw, aborting this function under a green verdict (#465).
	# Precedence: a press on the edge band is an edge grab, not a whole-tile body select.
	var hit = tl.hit_test(edge0.get_center())
	_assert_eq(hit["kind"], "edge", "a click on the edge band is an edge grab, not select")
	_assert_eq(hit["span_id"], sid0, "…carrying the span id")

	var seen := {"id": "", "frame": -999, "count": 0, "started": "", "ended": ""}
	tl.edge_dragged.connect(func(id, f):
		seen["id"] = id
		seen["frame"] = f
		seen["count"] += 1)
	tl.edge_drag_started.connect(func(id): seen["started"] = id)
	tl.edge_drag_ended.connect(func(id): seen["ended"] = id)

	var y: float = edge0.get_center().y
	_press(tl, 8.0, y)
	_assert_eq(seen["started"], sid0, "pressing the edge arms an edge drag for its span")
	_assert_eq(seen["id"], sid0, "…and reports the frame at the press point")
	# Drag right — emits the ABSOLUTE snapped target frame (no clamp at the timeline).
	_move(tl, 14.0, y)
	_assert_eq(seen["frame"], 14, "dragging emits the absolute target frame (snapped)")
	# Release ends the drag; later motion is inert.
	_release(tl, 14.0, y)
	_assert_eq(seen["ended"], sid0, "releasing ends the edge drag")
	var before: int = seen["count"]
	_move(tl, 25.0, y)
	_assert_eq(seen["count"], before, "motion after release does not emit")


## THE STUCK CASE. The boundary grip is centred on the boundary, so it reaches EDGE_HANDLE_W/2
## into the span on EACH side — and a short span (a 1-frame event at anything but a deep zoom)
## is narrower than that. Both flanking grips then cover every pixel it has, and its MOVE stops
## being reachable at all: `plan_move` still says yes, but no press can ever start one. The
## author found it by shrinking an event to one frame with an edge drag and then being unable to
## move it, ever — with no visible reason and no way back except undo.
##
## Move is the verb that must win a contested span, because it is drag-ONLY: the boundary this
## grip writes is also typeable in the inspector (camera's `end_frame` row, the colour lanes'
## Duration row), so losing the grip at a coarse zoom costs a zoom-in, while losing the body
## costs the verb.
func _test_a_short_span_keeps_a_body_to_grab() -> void:
	var tl = _camera_sliver_timeline()
	var sid := "camera:for_each:angle#1"      # the ONE-frame drawn event, holds either side
	var hit_rect: Rect2 = _span_rect(tl, sid)["rect"]
	_assert_true(hit_rect.size.x < Timeline.EDGE_HANDLE_W,
		"fixture: the span (%.1fpx) is narrower than the grip band (%.1fpx)"
			% [hit_rect.size.x, Timeline.EDGE_HANDLE_W])

	# Walk every pixel of the span: at least one must be able to START a Move.
	var body := 0
	var x: float = hit_rect.position.x
	while x <= hit_rect.position.x + hit_rect.size.x:
		if String(tl.hit_test(Vector2(x, hit_rect.get_center().y))["kind"]) == "select":
			body += 1
		x += 1.0
	_assert_true(body > 0,
		"a span narrower than the grip still has a body to grab — Move never becomes unreachable")
	_assert_eq(String(tl.hit_test(hit_rect.get_center())["kind"]), "select",
		"…and its CENTRE is body, so aiming at the middle of the tile always starts the Move")

	# hit_test saying "select" is not the same as the press path ARMING a Move — assert the
	# gesture the author actually makes.
	var armed := {"id": ""}
	tl.span_body_drag_started.connect(func(id): armed["id"] = id)
	_press_px(tl, hit_rect.get_center().x, hit_rect.get_center().y)
	_assert_eq(armed["id"], sid, "pressing the middle of the sliver arms its body drag")
	_release_px(tl, hit_rect.get_center().x, hit_rect.get_center().y)


## The other half of the pair: yielding on a sliver must not cost a WIDE span its grip. At the
## same zoom the flanking holds are tens of pixels, and their right edges still resize.
func _test_a_wide_span_still_gives_its_right_edge_to_the_grip() -> void:
	var tl = _camera_sliver_timeline()
	var wide := "camera:for_each:angle#2"     # the hold [7,38) — 124px at this zoom
	var grip: Rect2 = tl.edge_rect_for(wide)
	_assert_true(grip.size.x > 0.0, "a wide span keeps its boundary grip")
	_assert_eq(String(tl.hit_test(grip.get_center())["kind"]), "edge",
		"…and a press on it still resizes rather than selecting the tile")


## The stuck state, laid out: a hold [0,6), a ONE-FRAME drawn event [6,7), a hold [7,38) —
## exactly what an edge drag leaves when it shrinks a moved event to its minimum. Pinned at
## 4 px/frame so the drawn span is 4px, comfortably inside the 9px grip band.
func _camera_sliver_timeline():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"for_each": {"max_keyframe": 2, "keyframes": [
			{"index": 0, "end_frame": 6,
				"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
				"command_raw": 0x08C1, "channel_mask": 1,
				"source_mode": "MAP", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
			{"index": 1, "end_frame": 7,
				"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
				"command_raw": 0x0841, "channel_mask": 1,
				"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
			{"index": 2, "end_frame": 38,
				"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
				"command_raw": 0x08C1, "channel_mask": 1,
				"source_mode": "MAP", "interpolation": "LINEAR", "param_index": 0, "flags": 0}]},
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.axis.pixels_per_frame = 4.0
	tl.rebuild_layout()
	return tl


## Two angle-only keyframes (ends 8 and 20) → angle spans [0,8) and [8,20). The boundary
## at 8 is span#0's right edge; the tail at 20 is span#1's right edge. Used by the
## boundary-drag slice (both an internal boundary and a lane tail to grab).
func _camera_two_angle_timeline():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 24, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"phase1": {"max_keyframe": 1, "keyframes": [
			{"index": 0, "end_frame": 8,
				"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
				"command_raw": 0x0841, "channel_mask": 1,
				"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
			{"index": 1, "end_frame": 20,
				"angle": [40, 50, 60], "position": [0, 0, 0], "zoom": [0, 0, 0],
				"command_raw": 0x0841, "channel_mask": 1,
				"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0}]},
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


## A phase1 (offset 0, in default view) camera effect with one angle-only keyframe.
func _camera_effect_phase1():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"phase1": {"max_keyframe": 0, "keyframes": [{
			"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0}]},
	})
	return ed


func _lane_first_span(tl, lane_id: String) -> Dictionary:
	for lane in tl._score["lanes"]:
		if String(lane.get("id", "")) == lane_id and not lane["spans"].is_empty():
			return lane["spans"][0]
	return {}


func _span_width(tl, span_id: String) -> float:
	for hit in tl._span_rects:
		if String(hit["span"]["id"]) == span_id:
			return hit["rect"].size.x
	return -1.0


## A timeline whose camera table has a split: two keyframes at the SAME end_frame (angle,
## position), so the compiled lane emits two coincident point markers.
func _timeline_with_camera_split():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"for_each": {"max_keyframe": 1, "keyframes": [
			{"index": 0, "end_frame": 10, "channel_mask": 1, "command_raw": 0x0141,
				"source_mode": "CASTER", "interpolation": "IMMEDIATE", "angle": [1, 2, 3]},
			{"index": 1, "end_frame": 10, "channel_mask": 2, "command_raw": 0x00C2,
				"source_mode": "MAP", "interpolation": "IMMEDIATE", "position": [4, 5, 6]}]},
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


## A sound trigger DRAWS as an instant marker but its whole visible footprint — the
## marker plus the ghost bar behind it — is one CLICK TARGET that selects the trigger
## (you edit its sound_id/duration; the ghost itself stays read-only, never dragged).
## The ghost is still a SEPARATE read-only visual rect. The hit target starts at the
## fire instant and covers the ghost length.
func _test_sound_trigger_instant_and_ghost_rect() -> void:
	var tl = _timeline_with_sound_ghost()
	var sid := "sound:for_each:0#0"
	var instant := _span_rect(tl, sid)
	_assert_true(not instant.is_empty(), "the sound trigger has a hit-rect")

	var ghost: Rect2 = tl.ghost_rect_for(sid)
	_assert_true(ghost.size.x > 3.0, "the ghost bar spans the projected length")
	_assert_true(absf(ghost.position.x - instant["rect"].position.x) < 0.5,
		"the ghost bar starts at the instant (playback begins at the fire)")
	# The ghost width matches the frame extent of ghost_frames (20) at this axis.
	var start_frame := float(tl._score["lanes"][0]["spans"][0]["start"])
	var expected_w: float = tl.axis.frame_to_x(start_frame + 20.0) - tl.axis.frame_to_x(start_frame)
	_assert_true(absf(ghost.size.x - expected_w) < 0.5, "ghost width == 20 frames on the axis")

	# ADR-0085 conformance: the INSTANT is primary. The select rect is the fixed
	# SOUND_HIT_MIN_W on the marker — decoupled from the ghost width (the ghost is a
	# read-only projection, never the click target).
	_assert_true(absf(instant["rect"].size.x - tl.SOUND_HIT_MIN_W) < 0.5,
		"the trigger's select rect is the fixed marker width, not the ghost width")
	_assert_true(instant["rect"].size.x < ghost.size.x - 0.5,
		"the ghost is wider than the select rect (the bar is not the click target)")
	var y: float = instant["rect"].position.y + instant["rect"].size.y * 0.5
	# The marker's select zone selects the trigger. (Its exact center is owned by the
	# anchor/fire drag handles — preserved precedence — so probe the select-only sliver
	# just past them, still inside the fixed marker rect.)
	var sel_x: float = instant["rect"].end.x - 1.0
	var on_marker = tl.hit_test(Vector2(sel_x, y))
	_assert_eq(on_marker["kind"], "select", "the marker's select zone selects the trigger")
	_assert_eq(on_marker["span_id"], sid, "…the trigger the marker belongs to")
	# Clicking deep in the ghost body (clear of the marker AND beyond the loose-select
	# tolerance) is a SEEK, not a select — the ghost is never a click target. Zoom in
	# first: at the coarse default view the whole ghost sits inside the loose tolerance
	# (where selecting the marker is exactly what loose selection is for).
	tl.axis.pixels_per_frame = 10.0
	tl.rebuild_layout()
	var ghost_z: Rect2 = tl.ghost_rect_for(sid)
	var y_z: float = _span_row_y(tl, sid)
	var mid_x := ghost_z.position.x + ghost_z.size.x * 0.5
	var hit = tl.hit_test(Vector2(mid_x, y_z))
	_assert_eq(hit["kind"], "seek", "a click in the read-only ghost body seeks, does not select")

	# A span with no ghost frames has no ghost rect.
	_assert_true(tl.ghost_rect_for("does:not:exist").size == Vector2.ZERO,
		"a span without a ghost has an empty ghost rect")


## ADR-0085 conformance (the selection drift fix): when one trigger's read-only ghost
## fully covers a NEARBY trigger's marker (E317: kf#1 fires 22 with a 90-frame ghost,
## kf#3 fires 48 with a 42-frame ghost — 48 sits inside [22,112]), BOTH must stay
## selectable. The regression was the select rect taking the ghost width, so kf#1's
## rect swallowed kf#3's marker at 48. With the select rect decoupled to the fixed
## marker width, each marker selects its own trigger.
func _test_overlapping_sound_triggers_both_selectable() -> void:
	var tl = _timeline_with_overlapping_triggers()
	var sid1 := "sound:for_each:0#1"   # fires at 22, ghost 90 → covers 48
	var sid3 := "sound:for_each:0#3"   # fires at 48, its marker sits under kf#1's ghost

	var r1 := _span_rect(tl, sid1)
	var r3 := _span_rect(tl, sid3)
	_assert_true(not r1.is_empty() and not r3.is_empty(), "both firing triggers have select rects")

	# kf#1's ghost really does cover kf#3's marker frame (48).
	var ghost1: Rect2 = tl.ghost_rect_for(sid1)
	var x48: float = tl.axis.frame_to_x(48.0)
	_assert_true(ghost1.position.x <= x48 and ghost1.end.x >= x48,
		"kf#1's ghost covers frame 48 (the overlap that caused the drift)")

	# The regression assertion: kf#1's SELECT rect must NOT reach frame 48.
	_assert_true(r1["rect"].end.x < x48,
		"kf#1's select rect no longer covers frame 48 (decoupled from the ghost)")

	# The anti-swallow core: hit_test AT each marker resolves to that marker's OWN
	# trigger — previously a click anywhere in [48,90] returned kf#1. (Kind is the
	# fire-grab here — the drag handle owns the marker center — but it carries the right
	# span; before the fix, kf#3's marker returned kf#1's id.)
	var at1 = tl.hit_test(r1["rect"].get_center())
	_assert_eq(at1["span_id"], sid1, "kf#1's marker resolves to kf#1")
	var at3 = tl.hit_test(r3["rect"].get_center())
	_assert_eq(at3["span_id"], sid3, "kf#3's marker resolves to kf#3, not the covering kf#1")

	# …and each is genuinely selectable via its marker's select zone.
	var sel3 = tl.hit_test(Vector2(r3["rect"].end.x - 1.0, r3["rect"].get_center().y))
	_assert_eq(sel3["kind"], "select", "kf#3's marker has a live select zone")
	_assert_eq(sel3["span_id"], sid3, "…that selects kf#3")


## ADR-0085 decision 3: when two triggers' select rects overlap (markers within the
## fixed marker width — e.g. one frame apart), a click in the overlap selects the
## trigger whose FIRE marker is NEAREST the click, not the first-in-order one. Fixture:
## kf#0 fires at 8 (pinned, no fire handle), kf#1 fires at 9 (both ghostless → no anchor
## handles), so the far-right sliver of the overlap escapes kf#1's fire handle and lands
## in the pure select layer. First-in-order would pick kf#0; nearest-fire picks kf#1.
func _test_overlapping_select_picks_nearest_fire() -> void:
	var tl = _timeline_with_adjacent_triggers()
	var sid0 := "sound:for_each:0#0"   # fires at 8
	var sid1 := "sound:for_each:0#1"   # fires at 9 — one frame right of kf#0
	var r0 := _span_rect(tl, sid0)
	var r1 := _span_rect(tl, sid1)
	var y: float = r0["rect"].get_center().y

	# Sanity: the two select rects really do overlap (markers are within SOUND_HIT_MIN_W).
	_assert_true(r1["rect"].position.x < r0["rect"].end.x,
		"the two markers' select rects overlap (the precedence case)")

	# A click in the far-right of the overlap is nearer to kf#1's fire than kf#0's, and
	# clear of kf#1's fire handle → it reaches the select layer.
	var px: float = r0["rect"].end.x - 0.5   # inside both select rects, right of kf#1's fire grab
	var hit = tl.hit_test(Vector2(px, y))
	_assert_eq(hit["kind"], "select", "the overlap sliver reaches the select layer")
	_assert_eq(hit["span_id"], sid1, "nearest-fire wins: the later, nearer marker selects (not first-in-order kf#0)")


## Loose selection ("difficult to select an event"): a click on a LANE ROW that misses
## every exact rect by a few pixels must select the NEAREST marker within tolerance —
## not scrub the playhead out from under the author. The loose hit is SELECT-ONLY:
## even when the nearest handle is a draggable fire marker, a sloppy press never arms
## a byte-moving fire drag (the exact fire grab still does). Beyond the tolerance the
## lane row still seeks — the "seek vs inspect never fight" invariant keeps its edge.
func _test_loose_near_miss_selects_nearest_marker() -> void:
	var tl = _timeline_with_two_triggers()
	tl.axis.pixels_per_frame = 10.0
	tl.rebuild_layout()
	var sid0 := "sound:for_each:0#0"   # fires at 8 (pinned)
	var sid1 := "sound:for_each:0#1"   # fires at 12 — draggable, ghost 20
	var y := _span_row_y(tl, sid1)
	var x0: float = tl.axis.frame_to_x(8.0)
	var x1: float = tl.axis.frame_to_x(12.0)

	# 8px LEFT of trigger #1's marker: outside its fire grab (±4.5), outside every select
	# rect — today this seeks. Loose pass: nearest marker within tolerance → select #1.
	var near = tl.hit_test(Vector2(x1 - 8.0, y))
	_assert_eq(near["kind"], "select", "a near-miss on a lane row selects, does not seek")
	_assert_eq(near.get("span_id", ""), sid1, "…the nearest marker's trigger")

	# The loose hit never arms a drag: the same near-miss is a SELECT even though the
	# nearest handle is fire-draggable (kind 'fire' only on the exact grab).
	_assert_true(near["kind"] != "fire", "a sloppy press never starts a fire drag")

	# Nearest-wins in the other direction too: 18px right of #0's marker is within
	# tolerance of #0's select rect (10px past its right edge) and out of #1's reach.
	var near0 = tl.hit_test(Vector2(x0 + 18.0, y))
	_assert_eq(near0["kind"], "select", "a near-miss right of a marker still selects")
	_assert_eq(near0.get("span_id", ""), sid0, "…picking the nearest (earlier) trigger")

	# 30px right of #1 (22px past its select rect) is beyond the tolerance → the lane
	# row keeps its seek surface (this point is deep in the read-only ghost body).
	var far = tl.hit_test(Vector2(x1 + 30.0, y))
	_assert_eq(far["kind"], "seek", "beyond the tolerance the lane row still seeks")


## The loose pass preserves the event-beats-terminator rule: when both a real EVENT and
## the inert terminator end-cap are within tolerance, the event wins even if the
## terminator is strictly nearer — the terminator must never steal a neighbouring
## event's near-miss (it stays reachable by an exact click on its own rect).
func _test_loose_pass_prefers_event_over_nearer_terminator() -> void:
	var tl = _timeline_with_adjacent_triggers()   # events at 8, 9; terminator at 15
	tl.axis.pixels_per_frame = 2.0
	tl.rebuild_layout()
	var sid1 := "sound:for_each:0#1"
	var y := _span_row_y(tl, sid1)
	# 1px left of the terminator's select rect: terminator dist 1, event #1 dist 3 —
	# both within tolerance, the terminator nearer. The event must win.
	var x: float = tl.axis.frame_to_x(15.0) - 1.0
	var hit = tl.hit_test(Vector2(x, y))
	_assert_eq(hit["kind"], "select", "the near-miss between event and terminator selects")
	_assert_eq(hit.get("span_id", ""), sid1, "the event beats the strictly-nearer terminator")


## The tolerance applies WITHIN the clicked lane row only: a click on an EMPTY lane
## aligned under another lane's marker seeks — it never selects across rows.
func _test_loose_pass_is_lane_scoped() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 0, "sound_id": 7}]},
			{"channel_index": 1, "max_keyframe": 0, "keyframes": [
				{"duration_frames": 0, "sound_id": 0}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	var sid0 := "sound:for_each:0#0"
	var x: float = tl.axis.frame_to_x(8.0)   # channel 0's marker x
	# Channel 1's (empty) row, one lane below channel 0's.
	var y1: float = _span_row_y(tl, sid0) + tl.LANE_H + tl.LANE_GAP
	var hit = tl.hit_test(Vector2(x, y1))
	_assert_eq(hit["kind"], "seek", "an empty neighbouring lane seeks even under another lane's marker")


## ADR-0085 climax cue: a firing trigger's 0..1 energy envelope rides on its ghost
## rect so the draw pass can paint the swell inside the bar. rebuild_layout carries
## the model span's `energy` onto the ghost, surfaced by `ghost_energy_for(span_id)`.
## A trigger with no envelope reports an empty one (nothing to paint).
func _test_sound_ghost_carries_energy_envelope() -> void:
	var env := PackedFloat32Array([0.0, 0.25, 1.0, 0.5, 0.1])
	var tl = _timeline_with_sound_energy(20, env)
	var sid := "sound:for_each:0#0"
	var got: PackedFloat32Array = tl.ghost_energy_for(sid)
	_assert_eq(got.size(), env.size(), "the ghost carries one energy sample per rendered frame")
	_assert_true(absf(got[2] - 1.0) < 1e-6, "the envelope's peak sample rides onto the ghost")
	# A ghost with no supplied envelope carries an empty one (no curve to draw).
	var bare = _timeline_with_sound_ghost()
	_assert_eq(bare.ghost_energy_for("sound:for_each:0#0").size(), 0,
		"a ghost with no envelope reports an empty energy array")
	_assert_true(tl.ghost_energy_for("does:not:exist").size() == 0,
		"a span without a ghost has no energy")


## A timeline whose one sound trigger carries BOTH a ghost length and an energy
## envelope through the model maps — the climax-cue draw path's layout fixture.
func _timeline_with_sound_energy(ghost: int, env: PackedFloat32Array):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 0, "sound_id": 7}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {5: ghost}, {5: env}))
	tl.rebuild_layout()
	return tl


## ADR-0085 anchor: a DRAGGABLE handle on the read-only ghost bar marks the audible
## HIT position (fire + anchor_offset). It sits ON the ghost, is hit-tested BEFORE the
## whole-footprint select (so grabbing it drags, not selects), and exists ONLY where
## there's a ghost bar to place it on (no ghost → no handle).
func _test_sound_anchor_handle_rect_and_hit() -> void:
	var tl = _timeline_with_sound_anchor(8, 20)
	var sid := "sound:for_each:0#0"
	var span: Dictionary = tl._score["lanes"][0]["spans"][0]
	var start := float(span["start"])

	var handle: Rect2 = tl.anchor_rect_for(sid)
	_assert_true(handle.size.x > 0.0, "a sound trigger with a ghost has an anchor handle")
	# The handle is centered on the HIT frame = fire + anchor_offset (start + 8).
	var expected_x: float = tl.axis.frame_to_x(start + 8.0)
	_assert_true(absf(handle.get_center().x - expected_x) < 2.0,
		"the handle sits at fire + anchor_offset on the ghost bar")
	# It lives ON the ghost bar (vertically inside it).
	var ghost: Rect2 = tl.ghost_rect_for(sid)
	_assert_true(handle.get_center().y >= ghost.position.y - 0.5 and handle.get_center().y <= ghost.end.y + 0.5,
		"the handle sits within the ghost band")

	# Grabbing the handle hit-tests as an anchor, BEFORE the footprint select.
	var hit = tl.hit_test(handle.get_center())
	_assert_eq(hit["kind"], "anchor", "a click on the handle is an anchor grab, not a select")
	_assert_eq(hit["span_id"], sid, "…carrying the trigger's span id")

	# No ghost → no handle (nothing to place it on; offset would clamp to 0 anyway).
	var tl0 = _timeline_with_sound_anchor(8, 0)
	_assert_true(tl0.anchor_rect_for(sid).size == Vector2.ZERO,
		"a trigger without a ghost has no anchor handle")
	_assert_true(tl.anchor_rect_for("does:not:exist").size == Vector2.ZERO,
		"an unknown span has no anchor handle")


## Dragging the handle emits anchor_offset_changed(span_id, offset) continuously, with
## the offset = (hit frame − fire) clamped into the ghost length. The fire marker and
## the on-disk bytes do NOT move — the timeline only reports intent; the host applies
## it. Release ends the drag.
func _test_sound_anchor_drag_emits_offset() -> void:
	var tl = _timeline_with_sound_anchor(8, 20)
	var sid := "sound:for_each:0#0"
	var span: Dictionary = tl._score["lanes"][0]["spans"][0]
	var start := float(span["start"])
	var y: float = tl.ghost_rect_for(sid).get_center().y

	var seen := {"id": "", "offset": -1, "count": 0}
	tl.anchor_offset_changed.connect(func(id, off):
		seen["id"] = id
		seen["offset"] = off
		seen["count"] += 1)

	# Grab the handle at its current position (frame start+8).
	_press(tl, start + 8.0, y)
	_assert_eq(seen["id"], sid, "pressing the handle arms an anchor drag for its span")
	# Drag right to frame start+13 → offset 13.
	_move(tl, start + 13.0, y)
	_assert_eq(seen["offset"], 13, "dragging the handle emits the new offset (hit − fire)")
	# Drag past the ghost end (frame start+50) → clamps to the ghost length 20.
	_move(tl, start + 50.0, y)
	_assert_eq(seen["offset"], 20, "dragging past the ghost end clamps the offset to the length")
	# Drag left of the fire marker → clamps to 0.
	_move(tl, start - 5.0, y)
	_assert_eq(seen["offset"], 0, "dragging before the onset clamps the offset to 0")
	# Release ends the drag; later motion is inert.
	_release(tl, start - 5.0, y)
	var before: int = seen["count"]
	_move(tl, start + 15.0, y)
	_assert_eq(seen["count"], before, "motion after release does not move the anchor")


## The host applies the anchor edit to the live keyframe, then asks the timeline to
## reproject just the handle. That reproject moves the handle to the new offset but
## must NOT reset transport (playhead) or selection the way a fresh load_score does —
## a live drag has to keep the parked frame and the current selection.
func _test_set_anchor_offset_reprojects_without_reset() -> void:
	var tl = _timeline_with_sound_anchor(8, 20)
	var sid := "sound:for_each:0#0"
	var span: Dictionary = tl._score["lanes"][0]["spans"][0]
	var start := float(span["start"])
	tl.set_playhead(5)
	tl.select_span(sid)

	tl.set_anchor_offset(sid, 15)

	var handle: Rect2 = tl.anchor_rect_for(sid)
	_assert_true(absf(handle.get_center().x - tl.axis.frame_to_x(start + 15.0)) < 2.0,
		"reproject moves the handle to the new offset (fire + 15)")
	_assert_eq(tl.get_playhead(), 5, "reproject preserves the playhead (no transport reset)")
	_assert_eq(tl._selected_id, sid, "reproject preserves the current selection")


## ADR-0085 fire-drag: the sound INSTANT marker is a draggable grab that MOVES the
## trigger (stay-local). Every trigger past the first gets a fire grab; the FIRST
## trigger is PINNED (its fire IS the phase offset — no prior gap to trade), so it has
## no fire grab. The grab is checked BEFORE the anchor and the footprint-select, so a
## trigger whose anchor sits at the default offset 0 (on top of the marker) fire-drags
## rather than moving its anchor.
func _test_sound_fire_handle_and_precedence() -> void:
	var tl = _timeline_with_two_triggers()
	var sid0 := "sound:for_each:0#0"   # first trigger — pinned
	var sid1 := "sound:for_each:0#1"   # second trigger — draggable, has a ghost
	var span1: Dictionary = _span_by_id(tl, sid1)
	var start1 := float(span1["start"])

	# The draggable trigger has a fire grab centered on its fire frame.
	var fire1: Rect2 = tl.fire_rect_for(sid1)
	_assert_true(fire1.size.x > 0.0, "a non-first trigger has a fire grab handle")
	_assert_true(absf(fire1.get_center().x - tl.axis.frame_to_x(start1)) < 2.0,
		"the fire grab sits on the fire frame (the instant marker)")

	# The first trigger is pinned — no fire grab.
	_assert_true(tl.fire_rect_for(sid0).size == Vector2.ZERO,
		"the first trigger is pinned (no fire grab)")
	_assert_true(tl.fire_rect_for("does:not:exist").size == Vector2.ZERO,
		"an unknown span has no fire grab")

	# Precedence: at the marker, fire-drag WINS over the anchor (offset 0, overlapping)
	# and over the footprint select.
	var hit = tl.hit_test(fire1.get_center())
	_assert_eq(hit["kind"], "fire", "a click on the marker is a fire grab, not anchor/select")
	_assert_eq(hit["span_id"], sid1, "…carrying the trigger's span id")


## ADR-0085 "every event is accessible via a timeline handle": the terminator end-cap
## (index == max_keyframe) is SELECT-to-inspect only — NOT fire-draggable (its byte, the
## last event's gap, is already owned by that event's Gap field; a second handle would be
## two-handles-one-byte). Fire-grab is gated on role=="event", NOT merely keyframe_index>0
## — the terminator's index IS > 0. An interior EVENT still gets its fire grab.
func _test_sound_terminator_selectable_not_fire_draggable() -> void:
	var tl = _timeline_with_overlapping_triggers()   # events #0..#3, terminator #4 at frame 64
	var term := "sound:for_each:0#4"
	var event1 := "sound:for_each:0#1"   # an interior event (fires 22) — draggable

	# The terminator has NO fire grab even though its index (4) is > 0.
	_assert_true(tl.fire_rect_for(term).size == Vector2.ZERO,
		"the terminator is not fire-draggable (gate is role==event, not index>0)")
	# An interior event still IS fire-draggable — the gate didn't over-reach.
	_assert_true(tl.fire_rect_for(event1).size.x > 0.0,
		"an interior event keeps its fire grab")

	# The terminator is still a selectable handle (select-to-inspect).
	var trect := _span_rect(tl, term)
	_assert_true(not trect.is_empty(), "the terminator has a select rect (it's inspectable)")
	var hit = tl.hit_test(trect["rect"].get_center())
	_assert_eq(hit["kind"], "select", "clicking the terminator selects it (never a fire grab)")
	_assert_eq(hit["span_id"], term, "…the terminator's own id")


## Dragging the marker emits fire_frame_changed(span_id, new_fire_frame) continuously —
## the ABSOLUTE target frame under the cursor (snapped). The timeline reports intent
## only: it does NOT clamp against the neighbours (SoundGapMath does, in the host) and
## does NOT itself move the marker (the host applies the edit and reprojects). Release
## ends the drag.
func _test_sound_fire_drag_emits_target_frame() -> void:
	var tl = _timeline_with_two_triggers()
	var sid1 := "sound:for_each:0#1"
	var start1 := float(_span_by_id(tl, sid1)["start"])
	var y: float = tl.fire_rect_for(sid1).get_center().y

	var seen := {"id": "", "frame": -999, "count": 0}
	tl.fire_frame_changed.connect(func(id, f):
		seen["id"] = id
		seen["frame"] = f
		seen["count"] += 1)

	_press(tl, start1, y)
	_assert_eq(seen["id"], sid1, "pressing the marker arms a fire drag for its span")
	_move(tl, start1 + 7.0, y)
	_assert_eq(seen["frame"], int(start1) + 7, "dragging emits the absolute target fire frame")
	# Leftward too — the timeline does not clamp (that's the host's stay-local math).
	_move(tl, start1 - 2.0, y)
	_assert_eq(seen["frame"], int(start1) - 2, "dragging left emits the earlier target frame (unclamped)")
	# Release ends the drag; later motion is inert.
	_release(tl, start1 - 2.0, y)
	var before: int = seen["count"]
	_move(tl, start1 + 15.0, y)
	_assert_eq(seen["count"], before, "motion after release does not move the fire")

	# The first trigger's marker press does NOT arm a fire drag (it's pinned).
	var sid0 := "sound:for_each:0#0"
	var start0 := float(_span_by_id(tl, sid0)["start"])
	var y0: float = _span_rect(tl, sid0)["rect"].get_center().y
	seen["count"] = 0
	_press(tl, start0, y0)
	_move(tl, start0 + 5.0, y0)
	_assert_eq(seen["count"], 0, "the pinned first trigger emits no fire change")


## Fire-drag is RELATIVE to the grab point, not the absolute frame under the cursor. The
## bug: emitting round(x_to_frame(x)) meant (1) grabbing the ~9px-wide handle a few px off the
## marker leapt the trigger to the cursor's rounded frame, and (2) when zoomed out (ppf < 1)
## whole frames fell between cursor pixels, so you couldn't land on some frames (e.g. get 30
## or 32 but never 31 — "goes 0→12, can't back up to 11"). Relative-grab: the press records the
## marker's frame + cursor x, and motion emits start + round(Δpx / ppf) — so the grab never
## jumps and dragging back to the grab point returns to the start frame (no hysteresis).
func _test_fire_drag_is_relative_no_grab_jump() -> void:
	var tl = _timeline_with_two_triggers()
	var sid1 := "sound:for_each:0#1"
	var start1 := int(_span_by_id(tl, sid1)["start"])
	# Zoom OUT so whole frames fall between cursor pixels (the repro condition).
	tl.axis.pixels_per_frame = 0.6
	tl.rebuild_layout()
	var y: float = tl.fire_rect_for(sid1).get_center().y
	var marker_x: float = tl.axis.frame_to_x(float(start1))
	# Press OFFSET from the marker's exact x — a few px right, still inside the ~9px handle.
	var press_x: float = marker_x + 3.0

	var seen := {"frame": -999}
	tl.fire_frame_changed.connect(func(_id, f): seen["frame"] = f)

	# Grabbing must NOT move the trigger, despite the off-center press at coarse zoom (an
	# absolute round() would have leapt several frames).
	_press_px(tl, press_x, y)
	_assert_eq(seen["frame"], start1, "grabbing the handle does not move the trigger (relative)")

	# Motion is relative to the grab point: one frame's worth of pixels advances one frame.
	_move_px(tl, press_x + tl.axis.pixels_per_frame, y)
	_assert_eq(seen["frame"], start1 + 1, "moving one frame's worth of pixels advances exactly one frame")
	_move_px(tl, press_x + 2.0 * tl.axis.pixels_per_frame, y)
	_assert_eq(seen["frame"], start1 + 2, "…and two frames' worth advances two — every frame reachable")
	# Dragging back to the grab point returns to the start frame — no hysteresis.
	_move_px(tl, press_x, y)
	_assert_eq(seen["frame"], start1, "dragging back to the grab point returns to the start frame")
	_release_px(tl, press_x, y)


## The Q3 headline (end-to-end at the timeline+model seam): editing a trigger's Gap
## (duration_frames) on the LIVE sound dict and reprojecting the rebuilt score shifts
## trigger i+1 and every later marker on that channel by the delta — WHILE the parked
## playhead and the current selection stay put (typing a Gap must not clear the inspector).
func _test_gap_edit_reprojects_shifts_later_markers_preserving_transport() -> void:
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	# Three firing triggers on one channel: gaps 4, 10 → cumulative locals 0, 4, 14.
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 3, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 10, "sound_id": 6},
				{"duration_frames": 6, "sound_id": 7}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()

	var sid0 := "sound:for_each:0#0"
	var sid1 := "sound:for_each:0#1"
	var sid2 := "sound:for_each:0#2"
	var start0_before := int(_span_by_id(tl, sid0)["start"])
	var start1_before := int(_span_by_id(tl, sid1)["start"])
	var start2_before := int(_span_by_id(tl, sid2)["start"])

	# Park the author: select the LATER trigger, move the playhead, dial a zoom.
	tl.select_span(sid1)
	tl.set_playhead(30)
	tl.axis.pixels_per_frame = 4.0

	# Edit trigger 0's Gap 4 → 14 (delta +10) on the live dict, then reproject the rebuild.
	ed.sound["for_each"][0]["keyframes"][0]["duration_frames"] = 14
	tl.reproject_score(Model.build(ed))

	_assert_eq(int(_span_by_id(tl, sid0)["start"]), start0_before,
		"the edited trigger's own fire frame does not move (its gap is to the NEXT)")
	_assert_eq(int(_span_by_id(tl, sid1)["start"]), start1_before + 10,
		"trigger i+1 shifts by the gap delta (+10)")
	_assert_eq(int(_span_by_id(tl, sid2)["start"]), start2_before + 10,
		"every later trigger on the channel shifts by the same delta")
	_assert_eq(tl.get_playhead(), 30, "the parked playhead survives the Gap-edit reproject")
	_assert_eq(tl.selected_span_id(), sid1, "the selection survives (the inspector stays open while typing)")
	_assert_eq(tl.axis.pixels_per_frame, 4.0, "the author's zoom survives the reproject")


## A timeline with TWO firing triggers on one for_each channel: sid 5 (no ghost) then
## sid 6 (20-frame ghost). Trigger 0 is pinned; trigger 1 is fire-draggable and carries
## an anchor at the default offset 0 (so it overlaps the marker → precedence matters).
func _timeline_with_two_triggers():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 10, "sound_id": 6},
				{"duration_frames": 6, "sound_id": 0}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {6: 20}))
	tl.rebuild_layout()
	return tl


## A timeline mirroring E317's `sound:for_each:0` overlap: kf#0/2/4 skip (sound_id 0),
## kf#1 fires (sid 2) at frame 22 with a 90-frame ghost, kf#3 fires (sid 3) at frame 48
## with a 42-frame ghost. kf#1's ghost [22,112] fully covers kf#3's marker at 48 — the
## fixture for the selection-drift guard. phase_offset = 8; 8+14=22, 8+14+11+15=48.
func _timeline_with_overlapping_triggers():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 4, "keyframes": [
				{"duration_frames": 14, "sound_id": 0},
				{"duration_frames": 11, "sound_id": 2},
				{"duration_frames": 15, "sound_id": 0},
				{"duration_frames": 16, "sound_id": 3},
				{"duration_frames": 544, "sound_id": 0}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {2: 90, 3: 42}))
	tl.rebuild_layout()
	return tl


## A timeline with two ADJACENT firing triggers (one frame apart) and NO ghosts: kf#0
## fires at 8 (pinned — no fire handle), kf#1 fires at 9. Their fixed-width select rects
## overlap; the nearest-fire precedence guard clicks into that overlap.
func _timeline_with_adjacent_triggers():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 1, "sound_id": 2},
				{"duration_frames": 6, "sound_id": 3},
				{"duration_frames": 4, "sound_id": 0}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))   # no ghost map → no ghosts, no anchor handles
	tl.rebuild_layout()
	return tl


func _span_by_id(tl, span_id: String) -> Dictionary:
	for lane in tl._score.get("lanes", []):
		for span in lane.get("spans", []):
			if span.get("id", "") == span_id:
				return span
	return {}


## A timeline with one sound trigger (sound_id 5) carrying `anchor_offset`, projected
## with a `ghost`-frame ghost bar (0 → no ghost, so no handle).
func _timeline_with_sound_anchor(offset: int, ghost: int):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5, "anchor_offset": offset},
				{"duration_frames": 0, "sound_id": 7}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {5: ghost}))
	tl.rebuild_layout()
	return tl


func _span_rect(tl, span_id: String) -> Dictionary:
	for hit in tl._span_rects:
		if hit["span"]["id"] == span_id:
			return hit
	return {}


## A timeline whose score has one sound trigger (sound_id 5) carrying a 20-frame
## ghost length supplied through the model's ghost map.
func _timeline_with_sound_ghost():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"duration_frames": 4, "sound_id": 5},
				{"duration_frames": 0, "sound_id": 7}]},
		],
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {5: 20}))
	tl.rebuild_layout()
	return tl



## A spacer span (ADR-0087 dec. 27) labels itself "Spacer" on EITHER colour
## lane — the flag wins over the lane's usual label ("tint" / the screen kind), so a
## wide-enough inert tile names itself. Real spans keep their labels.
func _test_spacer_label_wins_on_any_colour_lane() -> void:
	var tl = _timeline()
	_assert_eq(tl._span_label({"kind": "palette", "fields": {"spacer": true}}), "Spacer",
		"a palette spacer labels itself 'Spacer'")
	_assert_eq(tl._span_label({"kind": "screen", "fields": {"spacer": true, "screen_kind": "Blend"}}),
		"Spacer", "a screen spacer labels itself 'Spacer' (not its kind)")
	_assert_eq(tl._span_label({"kind": "palette", "fields": {"spacer": false}}), "tint",
		"a real palette tween keeps its 'tint' label")
	_assert_eq(tl._span_label({"kind": "screen", "fields": {"screen_kind": "Grad"}}), "Grad",
		"a real screen tween keeps its kind label")
	tl.free()


## The hatch geometry is a PURE helper (the painter stays a dumb renderer): faint
## diagonal stripes clipped to the span rect. Every segment lies inside the rect,
## runs at 45° (readable at widths too narrow for a label), and the stripes cover
## the whole width — no bare stretch that would read as a real fill.
func _test_spacer_hatch_segments_fill_the_rect() -> void:
	var tl = _timeline()
	var rect := Rect2(100.0, 40.0, 37.0, 14.0)
	var segs: Array = tl._hatch_segments(rect)
	_assert_true(segs.size() >= 4, "a labelled-width span gets several stripes")
	var eps := 0.01
	var all_inside := true
	var all_diagonal := true
	var min_x := INF
	var max_x := -INF
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		for p in [a, b]:
			if p.x < rect.position.x - eps or p.x > rect.end.x + eps \
					or p.y < rect.position.y - eps or p.y > rect.end.y + eps:
				all_inside = false
		if absf(absf(b.x - a.x) - absf(b.y - a.y)) > eps:
			all_diagonal = false
		min_x = minf(min_x, minf(a.x, b.x))
		max_x = maxf(max_x, maxf(a.x, b.x))
	_assert_true(all_inside, "every stripe is clipped inside the span rect")
	_assert_true(all_diagonal, "stripes run at 45° (|dx| == |dy|)")
	_assert_true(min_x - rect.position.x < 8.0, "stripes start at the left edge")
	_assert_true(rect.end.x - max_x < 8.0, "stripes reach the right edge")
	# A sliver narrower than a label still hatches — the inert read survives zoom-out.
	var sliver: Array = tl._hatch_segments(Rect2(0.0, 0.0, 6.0, 12.0))
	_assert_true(sliver.size() >= 1, "a narrow sliver still carries at least one stripe")
	tl.free()


## The page scrolls the selected span back into view after the inspector grows over it
## (Feature 2). It must read the selected span's hit-rect WITHOUT reaching into the private
## _span_rects — so the timeline exposes selected_span_rect() (mirrors ghost_rect_for). It
## tracks _selected_id: the current selection's drawn rect, or an empty Rect2 when nothing is
## selected or the selection has no drawn rect.
func _test_selected_span_rect_tracks_the_selection() -> void:
	var tl = _timeline()
	_assert_true(tl.selected_span_rect() == Rect2(), "no selection → an empty rect")
	var span := _first_span(tl)
	tl.select_span(span["id"])
	tl.rebuild_layout()
	# Independent truth: the same span looked up by id in the layout's hit-rects.
	var expected: Rect2 = _span_rect(tl, span["id"])["rect"]
	_assert_true(tl.selected_span_rect() == expected,
		"selected_span_rect returns the selected span's own hit-rect")
	_assert_true(tl.selected_span_rect().size.y > 0.0, "the selected rect has a real height")
	tl.select_span("does:not:exist")
	tl.rebuild_layout()
	_assert_true(tl.selected_span_rect() == Rect2(), "a selection with no drawn rect → an empty rect")
	tl.free()


func _timeline():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 40, "emitter_id": 2}]},
			# An empty channel (no keyframes) → a KEPT lane with zero spans; the
			# seek/scrub tests press along it (empty at every x). See _empty_lane_y.
			{"context": "for_each", "channel_index": 1, "max_keyframe": 0, "keyframes": []},
		],
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


## The global "Time scale" lane (#270, ADR-0093) is a bottom strip below the phase lanes,
## carrying the two pacing bands over their frame ranges. It is laid out during rebuild_layout
## and exposed for hit-testing + the pop-up open.
func _test_pacing_strip_sits_below_the_phase_lanes() -> void:
	var tl = _timeline_with_pacing()
	var strip: Rect2 = tl.pacing_lane_rect()
	_assert_true(strip.size.y > 0.0, "the pacing strip has a real height when a time_scale is present")
	# It sits at or below the last phase-lane row's bottom (a first non-phase lane at the bottom).
	var last_bottom := 0.0
	for row in tl._lane_rows:
		last_bottom = maxf(last_bottom, row["rect"].end.y)
	_assert_true(strip.position.y >= last_bottom - 0.5,
		"the pacing strip is pinned below the phase lanes")
	var bands: Array = tl.pacing_band_rects()
	_assert_eq(bands.size(), 2, "the strip lays out both pacing bands")
	var b1: Dictionary = _pacing_band_by_id(bands, "time_scale#outer_phases")
	_assert_true(not b1.is_empty(), "the Phase-1 band is laid out")
	# The band's X-range maps its [start,end) through the shared axis (lined up against the ruler).
	_assert_true(abs(b1["rect"].position.x - tl.axis.frame_to_x(0.0)) < 1.5,
		"the Phase-1 band starts at frame 0 on the axis")


func _test_pacing_band_click_selects_the_curve() -> void:
	var tl = _timeline_with_pacing()
	var bands: Array = tl.pacing_band_rects()
	var b2: Dictionary = _pacing_band_by_id(bands, "time_scale#for_each")
	_assert_true(not b2.is_empty(), "the For-each band is laid out")
	var center: Vector2 = b2["rect"].get_center()
	var hit = tl.hit_test(center)
	_assert_eq(hit["kind"], "select", "clicking a pacing band selects (opens the pop-up), never seeks")
	_assert_eq(hit["span_id"], "time_scale#for_each", "the clicked band reports its curve id")
	# And a real press emits span_selected with the band id (the pop-up open signal).
	var seen := {"id": "", "count": 0}
	tl.span_selected.connect(func(id):
		seen["id"] = id
		seen["count"] += 1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = center
	tl._gui_input(ev)
	_assert_eq(seen["id"], "time_scale#for_each", "pressing the band emits span_selected(band_id)")
	_assert_eq(seen["count"], 1, "one select per press")


func _test_no_pacing_strip_without_a_time_scale() -> void:
	var tl = _timeline()  # the default fixture has no time_scale section
	_assert_true(tl.pacing_lane_rect().size == Vector2.ZERO,
		"no pacing strip when the effect carries no time_scale")
	_assert_eq(tl.pacing_band_rects().size(), 0, "no pacing bands laid out")


## The pacing band's stepped-top outline (ADR-0093 revision, "Outline + fill"): a band of pure
## normal-speed 2s must STILL yield a full-width polyline sitting on the baseline — that outline is
## what makes the band "show something everywhere" (the old zero-height fill collapsed and vanished).
func _test_pacing_outline_present_even_at_normal_speed() -> void:
	var tl = Timeline.new()
	var band := Rect2(200.0, 100.0, 360.0, 30.0)  # right of the gutter
	var base_y := band.end.y - 1.0
	var pts: PackedVector2Array = tl.pacing_top_points([2, 2, 2, 2, 2, 2], band)
	_assert_true(pts.size() >= 2, "a normal-speed (all-2) band still yields an outline polyline")
	var min_x := INF
	var max_x := -INF
	var off_baseline := false
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		if abs(p.y - base_y) > 0.5:
			off_baseline = true
	_assert_true(abs(min_x - band.position.x) < 1.5, "the outline starts at the band's left edge")
	_assert_true(abs(max_x - band.end.x) < 1.5, "the outline runs to the band's right edge")
	_assert_true(not off_baseline, "every normal-speed sample sits on the baseline (flat, but drawn)")
	tl.free()


## Slow-mo samples (>2) lift the outline above the baseline, monotone with slowness, and value 10
## reaches the top of the lane — the swell still stands out over the always-present baseline.
func _test_pacing_outline_rises_for_slow_mo() -> void:
	var tl = Timeline.new()
	var band := Rect2(200.0, 100.0, 360.0, 30.0)
	var base_y := band.end.y - 1.0
	var top_y := band.position.y + 1.0
	var pts: PackedVector2Array = tl.pacing_top_points([2, 6, 10], band)
	_assert_eq(pts.size(), 6, "two points per sample (a stepped stair)")
	_assert_true(abs(pts[0].y - base_y) < 0.5, "the leading normal-speed sample stays on the baseline")
	_assert_true(pts[3].y < base_y - 1.0, "a value-6 sample rises above the baseline")
	_assert_true(pts[5].y < pts[3].y, "a value-10 sample rises above the value-6 sample")
	_assert_true(pts[5].y <= top_y + 0.5, "a value-10 sample reaches the top of the lane")
	tl.free()


## The fill must survive horizontal scroll. A single closed fill polygon self-touches at the gutter
## when the band is scrolled partly off-screen (all off-screen points clamp to GUTTER_W) and fails
## to triangulate — dropping the WHOLE fill while the outline stays. Per-column rects clip cleanly:
## every rect stays at/right of the gutter with positive area, and the swell still paints.
func _test_pacing_fill_survives_horizontal_scroll() -> void:
	var tl = Timeline.new()
	var gw: float = Timeline.GUTTER_W
	var band := Rect2(gw - 100.0, 100.0, 600.0, 30.0)  # left edge scrolled LEFT of the gutter
	var rects: Array = tl.pacing_fill_rects([2, 2, 10, 10, 2, 2], band)
	_assert_true(rects.size() >= 1, "a scrolled-off-left band still yields fill rects for its swell")
	for r in rects:
		_assert_true(r.position.x >= gw - 0.01, "every fill rect is clipped to the gutter (x >= GUTTER_W)")
		_assert_true(r.size.x > 0.0, "every fill rect has positive width")
		_assert_true(r.size.y > 0.0 and r.position.y >= band.position.y - 0.01,
			"fill rects sit within the band, above the baseline")
	tl.free()


## A flat normal-speed band paints NO fill — only the always-present baseline outline carries it
## (no zero-area polygon, no triangulation failure).
func _test_pacing_flat_band_has_no_fill() -> void:
	var tl = Timeline.new()
	_assert_eq(tl.pacing_fill_rects([2, 2, 2, 2], Rect2(200.0, 100.0, 360.0, 30.0)).size(), 0,
		"a flat normal-speed band paints no fill (only the baseline outline)")
	tl.free()


func _timeline_with_pacing():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 40, "emitter_id": 2}]},
		],
	})
	var outer: Array = []
	var foreach: Array = []
	for i in range(600):
		outer.append(2 + (i % 9))
		foreach.append(2 + ((i + 3) % 9))
	ed.time_scale = {
		"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
		"outer_phases": outer, "for_each": foreach,
	}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


func _pacing_band_by_id(bands: Array, id: String) -> Dictionary:
	for b in bands:
		if String(b.get("id", "")) == id:
			return b
	return {}


func _first_span(tl) -> Dictionary:
	for lane in tl._score["lanes"]:
		if not lane["spans"].is_empty():
			return lane["spans"][0]
	return {}


func _span_row_y(tl, span_id: String) -> float:
	for hit in tl._span_rects:
		if hit["span"]["id"] == span_id:
			return hit["rect"].position.y + hit["rect"].size.y * 0.5
	return -1.0


## Y-center of an EMPTY lane row (no spans) — a press anywhere along it seeks
## regardless of x, so it's the clean surface for the timeline's seek/scrub tests
## now that the ruler band lives on the frames bar. Falls back to the first lane.
func _empty_lane_y(tl) -> float:
	for row in tl._lane_rows:
		if row["lane"]["spans"].is_empty():
			return row["rect"].position.y + row["rect"].size.y * 0.5
	var r: Rect2 = tl._lane_rows[0]["rect"]
	return r.position.y + r.size.y * 0.5


## The lane id of the first empty (span-less) lane row — the surface the gap-context test
## right-clicks (see _empty_lane_y). Falls back to the first lane.
func _empty_lane_id(tl) -> String:
	for row in tl._lane_rows:
		if row["lane"]["spans"].is_empty():
			return String(row["lane"]["id"])
	return String(tl._lane_rows[0]["lane"]["id"])


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
