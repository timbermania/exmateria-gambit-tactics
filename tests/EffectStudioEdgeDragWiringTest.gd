extends Node
## TDD guard for the Effect Studio CAMERA EDGE-DRAG host wiring (ADR-0086 boundary-drag
## amendment) — the page glue that turns a timeline edge-drag into a single, clamped,
## one-undo `end_frame` edit. When the author drags a camera sub-channel span's right edge,
## the page must:
##   (1) resolve the span's camera end_frame address off the live score (channel + phase +
##       camera_channel + ordinal), converting the ABSOLUTE cursor frame to PHASE-LOCAL via
##       the span's own start/authored_start offset,
##   (2) CLAMP it strictly between neighbours (min 1 frame): a boundary can't cross its own
##       start (keep THIS span >= 1) nor the next span's end (keep the NEIGHBOUR >= 1); the
##       tail (no successor) clamps only on the left,
##   (3) apply at most ONE edit per rendered frame (a _process drain, latest wins) so the
##       whole-section camera recompile is bounded to the frame rate, then reproject — the
##       neighbour moves for free because its start is derived from this end_frame,
##   (4) bracket the gesture as ONE undo: begin_coalesce on grab, end_coalesce on release
##       (flushing any pending edit first so the final frame isn't lost).
## The timeline reports the raw absolute frame; the host owns the bounds — mirroring fire-drag.
## Pure logic: the page is new()'d WITHOUT add_child; we inject a real timeline + camera data
## + a recording fake host that applies through a real EffectEditSession bound to that data.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioEdgeDragWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const PaletteDataClass = ExMateriaEffects.PaletteData
const ScreenDataClass = ExMateriaEffects.ScreenData
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

# Palette fixture: affected_units under for_each (offset 8) with three tv-2 tweens (16 frames
# each) → spans abs [8,24) [24,40) [40,56). PSID0's right edge is the boundary at abs 24.
const PSID0 := "palette:for_each:affected_units#0"
const PSID1 := "palette:for_each:affected_units#1"

# Palette MOVE fixture (structure-free drag): hold, SPAN, hold — the shape a colour Move needs
# on both sides. Indices 1 and 3 repeat the tint before them, so the real fold (nothing is
# stamped) calls both of them empty space and the drawn span at index 2 has frames to trade in
# either direction. tv 2/2/3/2/2 under for_each (offset 8) → the span sits at abs 40.
const PMSID1 := "palette:for_each:affected_units#1"
const PMSID2 := "palette:for_each:affected_units#2"
const PMSID3 := "palette:for_each:affected_units#3"
const PMS_HOME_START := 40

# Screen fixture: the same three tv-2 tweens under for_each (offset 8), 1-D address.
const SSID0 := "screen:for_each#0"
const SSID1 := "screen:for_each#1"

# Particle fixture: channel 0 under for_each (offset 8), keyframes [0,0][10,1][20,0][30,2] →
# drawn span #1 abs [8,18) (right edge at abs 18) followed by GAP [18,28), then drawn span #3
# abs [28,38). The address is the raw keyframe index (context + channel_index + event_index).
const PARTID1 := "particle:for_each:0#1"
const PARTID3 := "particle:for_each:0#3"

# Fixture: camera under `for_each` (offset = phase1_duration = 8). Angle ends 8 / 20
# phase-local → spans abs [8,16) and [16,28). sid0's right edge is the boundary at abs 16;
# sid1's is the lane tail at abs 28.
const SID0 := "camera:for_each:angle#0"
const SID1 := "camera:for_each:angle#1"
const OFFSET := 8

# HOLD fixture: the same lane with a third keyframe and #1 authored `MAP` + zero — a hidden
# SPACER (ADR-0086 dec. 15). Ends 8/20/32 local → spans abs [8,16) [16,28)
# [28,40). HSID1's right edge at abs 28 is what an author sees as HSID2's LEFT resize handle.
const HSID0 := "camera:for_each:angle#0"
const HSID1 := "camera:for_each:angle#1"
const HSID2 := "camera:for_each:angle#2"

# ORIGIN-MOVE fixture: a DRAWN angle event at the phase origin (local [0,10)) followed by a
# `MAP`+zero hold out to 40 — the lane shape the author's report starts from, and the one where
# a rightward Move has to MANUFACTURE the hold that owns the space it vacates. Its command word
# is packed CONSISTENTLY with its source_mode (0x08C1 = MAP | LINEAR | mask 1) because a Move
# RE-LOWERS the whole phase, rebuilding source_mode from the bits.
const OMSID0 := "camera:for_each:angle#0"

# MID-HOLD fixture: drawn(8) / `MAP`+zero hold(20) / drawn(32), all command words packed
# consistently — the GENERAL case of the same closure, away from the phase origin.
const MHSID1 := "camera:for_each:angle#1"
const MHSID2 := "camera:for_each:angle#2"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_edge_drag_boundary_trade_and_reprojects()
	_test_edge_drag_clamps_at_next_neighbour()
	_test_edge_drag_clamps_min_one_frame()
	_test_edge_drag_applies_once_per_frame()
	_test_edge_drag_brackets_one_undo_coalesce()
	_test_edge_drag_end_flushes_pending_then_closes()
	_test_edge_drag_tail_resize_grows_lane()
	_test_edge_drag_on_a_hold_selects_the_next_drawn_span()
	_test_move_right_then_drag_back_reaches_the_origin()
	_test_edge_drag_closes_a_mid_lane_hold_to_nothing()
	_test_an_emptied_hold_is_deleted_on_release_not_left_behind()
	_test_a_hold_with_room_left_survives_the_release()
	_test_edge_drag_on_a_tail_hold_touches_no_selection()
	_test_unknown_span_edge_is_inert()
	_test_palette_edge_drag_addresses_the_boundary_field()
	_test_palette_edge_drag_trades_and_reprojects()
	_test_screen_edge_drag_addresses_the_boundary_field()
	_test_screen_edge_drag_trades_and_reprojects()

	_test_particle_edge_drag_addresses_the_boundary_field()
	_test_particle_edge_drag_resizes_and_reprojects()
	_test_particle_span_grows_an_edge_grip()
	_test_particle_body_drag_slides_the_span()
	_test_particle_body_drag_brackets_one_move()
	_test_particle_edge_drag_defers_refold_to_release()
	_test_particle_body_drag_defers_refold_to_release()
	_test_typed_particle_edit_refolds_immediately()
	_test_particle_drag_reprojects_geometry_only_reusing_other_lanes()
	_test_colour_body_drag_touches_no_keyframe_until_release()
	_test_colour_body_drag_previews_the_planners_clamp_not_the_cursor()
	_test_a_colour_drag_back_onto_home_commits_nothing()
	_test_camera_body_drag_touches_no_keyframe_until_release()
	_test_screen_span_grows_an_edge_grip()
	_test_screen_structural_result_selects_by_raw_index()
	_test_ripple_toggle_defaults_off_and_flips()
	_test_ripple_injects_the_flag_on_colour_resizes()
	_test_ripple_rides_camera_end_frame_drags_and_typed_edits()
	_test_ripple_drag_shifts_downstream_in_the_score()
	_test_ripple_camera_drag_shifts_downstream_in_the_score()
	_test_ripple_swaps_the_camera_upper_clamp_to_tail_headroom()

	print("\n=== EffectStudioEdgeDragWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEdgeDragWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEdgeDragWiringTest")
		get_tree().quit(0)


## Drag sid0's edge to abs 22 → phase-local 14. Exactly one end_frame edit reaches the host,
## and the reproject lands sid0's end AND sid1's derived start on abs 22 (the boundary trade).
func _test_edge_drag_boundary_trade_and_reprojects() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	var host = page._host

	page._on_edge_dragged(SID0, 22)
	page._process(0.0)   # drain the once-per-frame apply

	_assert_eq(host.applies.size(), 1, "one edge drag applies exactly one edit")
	if host.applies.is_empty():
		page.free()
		return
	var ref: Dictionary = host.applies[0]["field_ref"]
	_assert_eq(String(ref.get("channel", "")), "camera", "the edit addresses the camera channel")
	_assert_eq(String(ref.get("context", "")), "for_each", "…carrying the phase")
	_assert_eq(String(ref.get("camera_channel", "")), "angle", "…the sub-channel lane")
	_assert_eq(int(ref.get("ordinal", -1)), 0, "…the span's ordinal (stable address)")
	_assert_eq(String(ref.get("field", "")), "end_frame", "…and writes end_frame")
	_assert_eq(int(host.applies[0]["new_raw"]), 14, "the ABSOLUTE 22 lowered to PHASE-LOCAL 14")

	_assert_eq(_span_end(page, SID0), 22, "the dragged span's right edge moved to abs 22")
	_assert_eq(_span_start(page, SID1), 22, "the neighbour's start moved for free (boundary trade)")
	page.free()


## Drag past the next span's end: abs 100 → local 92 clamps to next_end(20) − 1 = 19, so the
## neighbour keeps at least one frame. The edit value is the clamped 19, not the raw target.
func _test_edge_drag_clamps_at_next_neighbour() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SID0, 100)
	page._process(0.0)
	_assert_eq(int(page._host.applies[0]["new_raw"]), 19,
		"dragging past the neighbour clamps to next_end − 1 (keeps the neighbour >= 1 frame)")
	page.free()


## Drag before its own start: abs 5 → local −3 clamps to authored_start(0) + 1 = 1, so THIS
## span keeps at least one frame (a drag never collapses a span — that's the delete verb).
func _test_edge_drag_clamps_min_one_frame() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SID0, 5)
	page._process(0.0)
	_assert_eq(int(page._host.applies[0]["new_raw"]), 1,
		"dragging below its own start clamps to prev_end + 1 (min 1 frame)")
	page.free()


## Two motions before one frame drain apply only ONCE (latest wins) — the whole-section
## camera recompile is bounded to the frame rate, not the raw motion-event rate.
func _test_edge_drag_applies_once_per_frame() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SID0, 22)   # local 14
	page._on_edge_dragged(SID0, 24)   # local 16 — supersedes
	page._process(0.0)
	_assert_eq(page._host.applies.size(), 1, "two motions in one frame apply once")
	_assert_eq(int(page._host.applies[0]["new_raw"]), 16, "the latest motion wins (local 16)")
	page.free()


## Grab brackets the gesture as ONE undo: started → studio_begin_coalesce with the span's
## end_frame field_ref; released → studio_end_coalesce. Grab also selects the span as the
## inspection root so the inspector tracks the drag.
func _test_edge_drag_brackets_one_undo_coalesce() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	var host = page._host

	page._on_edge_drag_started(SID0)
	_assert_eq(host.begin_count, 1, "grab opens exactly one coalesce bracket")
	_assert_eq(String(host.begin_field.get("field", "")), "end_frame", "…for the span's end_frame")
	_assert_eq(int(host.begin_field.get("ordinal", -1)), 0, "…addressed by the span's ordinal")
	_assert_eq(page._timeline.selected_span_id(), SID0, "grabbing selects the span on the timeline")
	_assert_true(not page._nav.is_empty() and page._nav.back() == Target.span(SID0),
		"…and makes it the inspection root")

	page._on_edge_drag_ended(SID0)
	_assert_eq(host.end_count, 1, "release closes the coalesce bracket")
	page.free()


## Release must FLUSH a pending edit (a motion since the last frame drain) before closing the
## bracket — else the final drag frame is lost. Drag then release with NO _process between.
func _test_edge_drag_end_flushes_pending_then_closes() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	var host = page._host

	page._on_edge_drag_started(SID0)
	page._on_edge_dragged(SID0, 22)   # pending local 14, not yet drained
	page._on_edge_drag_ended(SID0)    # must flush first

	_assert_eq(host.applies.size(), 1, "release flushes the pending edit")
	_assert_eq(int(host.applies[0]["new_raw"]), 14, "…with the last dragged value")
	_assert_eq(host.end_count, 1, "…then closes the bracket")
	page.free()


## The last span has no successor, so its right edge resizes the lane TAIL: abs 40 → local 32
## applies with no upper clamp (only the left min-1 bound), growing the final tween.
func _test_edge_drag_tail_resize_grows_lane() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SID1, 40)
	page._process(0.0)
	_assert_eq(int(page._host.applies[0]["new_raw"]), 32, "the tail edge grows to local 32 (no upper clamp)")
	_assert_eq(_span_end(page, SID1), 40, "the lane tail extended to abs 40")
	page.free()


func _test_unknown_span_edge_is_inert() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged("does:not:exist#9", 20)
	page._process(0.0)
	_assert_eq(page._host.applies.size(), 0, "an unknown span id applies no edit")
	page.free()


## A palette span shares the edge-drag seam (ADR-0087), but its address is the palette
## `boundary_end` pseudo-field (two-dim: phase + channel_name + keyframe index), and the value
## is the offset-corrected LOCAL frame (the PaletteChannel snaps + clamps, not the page).
func _test_palette_edge_drag_addresses_the_boundary_field() -> void:
	var page = _palette_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(PSID0, 32)   # abs 32 → local 24 (offset 8)
	page._process(0.0)

	_assert_eq(page._host.applies.size(), 1, "one palette edge drag applies exactly one edit")
	if page._host.applies.is_empty():
		page.free()
		return
	var ref: Dictionary = page._host.applies[0]["field_ref"]
	_assert_eq(String(ref.get("channel", "")), "palette", "the edit addresses the palette channel")
	_assert_eq(String(ref.get("context", "")), "for_each", "…carrying the phase")
	_assert_eq(String(ref.get("channel_name", "")), "affected_units", "…the tint channel (palette's 2nd address dim)")
	_assert_eq(int(ref.get("event_index", -1)), 0, "…the keyframe index")
	_assert_eq(String(ref.get("field", "")), "boundary_end", "…and writes the boundary pseudo-field")
	_assert_eq(int(page._host.applies[0]["new_raw"]), 24, "the ABSOLUTE 32 offset-corrected to LOCAL 24 (unclamped — channel snaps)")
	page.free()


## The applied palette boundary edit re-times the tween: dragging PSID0's edge to abs 32 grows
## it and shrinks the neighbour, and the reproject lands the moved boundary at abs 32.
func _test_palette_edge_drag_trades_and_reprojects() -> void:
	var page = _palette_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(PSID0, 32)
	page._process(0.0)

	_assert_eq(_span_end(page, PSID0), 32, "the dragged palette span's right edge moved to abs 32")
	_assert_eq(_span_start(page, PSID1), 32, "the neighbour's start followed for free (sum-preserving trade)")
	_assert_eq(_span_end(page, PSID1), 40, "downstream stays pinned (neighbour's end unchanged)")
	page.free()


## A screen span shares the edge-drag seam (ADR-0087), with the 1-D screen address (phase
## context + keyframe index — no channel_name), and the value is the offset-corrected LOCAL
## frame (the ScreenChannel snaps + clamps, not the page).
func _test_screen_edge_drag_addresses_the_boundary_field() -> void:
	var page = _screen_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SSID0, 32)   # abs 32 → local 24 (offset 8)
	page._process(0.0)

	_assert_eq(page._host.applies.size(), 1, "one screen edge drag applies exactly one edit")
	if page._host.applies.is_empty():
		page.free()
		return
	var ref: Dictionary = page._host.applies[0]["field_ref"]
	_assert_eq(String(ref.get("channel", "")), "screen", "the edit addresses the screen channel")
	_assert_eq(String(ref.get("context", "")), "for_each", "…carrying the phase")
	_assert_true(not ref.has("channel_name"), "…with NO channel_name (screen's address is 1-D)")
	_assert_eq(int(ref.get("event_index", -1)), 0, "…the keyframe index")
	_assert_eq(String(ref.get("field", "")), "boundary_end", "…and writes the boundary pseudo-field")
	_assert_eq(int(page._host.applies[0]["new_raw"]), 24, "the ABSOLUTE 32 offset-corrected to LOCAL 24 (unclamped — channel snaps)")
	page.free()


## The applied screen boundary edit re-times the tween: dragging SSID0's edge to abs 32 grows
## it and shrinks the neighbour, and the reproject lands the moved boundary at abs 32.
func _test_screen_edge_drag_trades_and_reprojects() -> void:
	var page = _screen_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(SSID0, 32)
	page._process(0.0)

	_assert_eq(_span_end(page, SSID0), 32, "the dragged screen span's right edge moved to abs 32")
	_assert_eq(_span_start(page, SSID1), 32, "the neighbour's start followed for free (sum-preserving trade)")
	_assert_eq(_span_end(page, SSID1), 40, "downstream stays pinned (neighbour's end unchanged)")
	page.free()


## The timeline's edge-grip gate includes screen spans (ADR-0087) — without the grip the
## boundary is undraggable no matter what the page can dispatch.
## THE acceptance for the structure-free colour Move, through the page's REAL handlers.
##
## Mid-drag nothing structural may happen: no keyframe written, no lane renumbered, no score
## reprojected. The span tracks the cursor purely as GEOMETRY (the timeline's move-preview
## offset), and the splice lands exactly once, on release.
##
## The score-IDENTITY assertion is the sharp one. `_reproject_dragged_kind` hands the timeline a
## freshly built Dictionary, so `is_same` going false is proof a reprojection ran — and the old
## shape ran one per motion, each re-folding the palette spacer oracle behind it (~95ms on
## E317, with the lane's grip count oscillating 16 ↔ 23 as padding appeared and vanished under
## the cursor).
func _test_colour_body_drag_touches_no_keyframe_until_release() -> void:
	var page = _palette_move_page()
	if not _capable(page) or not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var tl = page._timeline
	var ch = page._effect_data.palette.get_channel("for_each", "affected_units")
	_assert_true(_is_hold(tl, PMSID1) and _is_hold(tl, PMSID3),
		"fixture: the fold (unstamped) calls the span's two neighbours empty space")
	var pristine := _kf_fingerprint(ch)
	var score_at_grab = tl._score

	page._on_span_body_drag_started(PMSID2)
	for d in [3, 11, 8]:
		page._on_span_body_dragged(PMSID2, d)
		page._process(0.0)
		_assert_eq(_kf_fingerprint(ch), pristine,
			"motion %+d writes no keyframe — the channel is byte-identical to the grab" % d)
		_assert_true(is_same(tl._score, score_at_grab),
			"…and reprojects nothing: the timeline still holds the grab's own score object")
	_assert_eq(int(tl.move_preview_state().get("dx", 0)), 8,
		"the span is tracking the cursor as a geometry OFFSET, at the last motion's delta")

	page._on_span_body_drag_ended(PMSID2)
	_assert_true(_kf_fingerprint(ch) != pristine, "release commits the slide for real")
	_assert_true(not is_same(tl._score, score_at_grab),
		"…and reprojects ONCE, here, where the old shape reprojected once per motion")
	_assert_eq(String(tl.move_preview_state().get("id", "?")), "",
		"…dropping the geometry offset onto the committed lane")
	_assert_true(tl.selected_span_id().begins_with("palette:for_each:affected_units#"),
		"…and the selection follows the renumbered address")
	page.free()


## The offset drawn is the PLANNER'S, never the cursor's. Over-drag past the room the two hold
## runs can trade and the preview must pin at the clamp — a preview that drew the wish would
## promise a landing release refuses, which is the whole reason the motion still plans.
func _test_colour_body_drag_previews_the_planners_clamp_not_the_cursor() -> void:
	var page = _palette_move_page()
	if not _capable(page) or not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var tl = page._timeline
	page._on_span_body_drag_started(PMSID2)
	page._on_span_body_dragged(PMSID2, 999)
	page._process(0.0)
	var clamped: int = int(tl.move_preview_state().get("dx", -1))
	_assert_true(clamped > 0 and clamped < 999,
		"an over-drag previews the CLAMP (%d), not the cursor's 999" % clamped)
	page._on_span_body_drag_ended(PMSID2)
	_assert_eq(_span_start(page, tl.selected_span_id()) - PMS_HOME_START, clamped,
		"…and release lands exactly where the preview promised")
	page.free()


## Drag out, then back onto home. With the data untouched all gesture, the return trip is
## carried by the planner answering ZERO — so the offset must come back to 0 and release must
## commit nothing at all, leaving the lane (and the undo stack) as if it were a click.
func _test_a_colour_drag_back_onto_home_commits_nothing() -> void:
	var page = _palette_move_page()
	if not _capable(page) or not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var tl = page._timeline
	var ch = page._effect_data.palette.get_channel("for_each", "affected_units")
	var pristine := _kf_fingerprint(ch)

	page._on_span_body_drag_started(PMSID2)
	page._on_span_body_dragged(PMSID2, 8)
	page._process(0.0)
	_assert_eq(int(tl.move_preview_state().get("dx", 0)), 8, "the slide out previews +8")
	page._on_span_body_dragged(PMSID2, 0)
	page._process(0.0)
	_assert_eq(int(tl.move_preview_state().get("dx", -1)), 0,
		"…and dragging back onto home previews it away")
	page._on_span_body_drag_ended(PMSID2)
	_assert_eq(_kf_fingerprint(ch), pristine, "the cancelled gesture commits nothing")
	page.free()


## The camera arm of the structure-free drag, through the page's REAL handlers.
##
## Camera's per-motion apply was never slow the way colour's was — it is the CHURN that made it
## worth taking. The apply manufactures a lead hold, deletes an emptied one and renumbers the
## lane, so the ordinal the author grabbed named a different event one motion later and the
## page chased the selection across the lane underneath the cursor (`_follow_structural_move`,
## every motion). Measured on E317's for_each angle lane, the drag id went 0 -> 1 on the FIRST
## motion. Now it renumbers exactly once, on release.
func _test_camera_body_drag_touches_no_keyframe_until_release() -> void:
	var page = _origin_move_page()
	if not _capable(page) or not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var tl = page._timeline
	var pristine := _camera_fingerprint(page)
	var score_at_grab = tl._score

	page._on_span_body_drag_started(OMSID0)
	for d in [2, 5, 6]:
		page._on_span_body_dragged(OMSID0, d)
		page._process(0.0)
		_assert_eq(_camera_fingerprint(page), pristine,
			"motion %+d writes no camera keyframe — the table is byte-identical to the grab" % d)
		_assert_true(is_same(tl._score, score_at_grab),
			"…and reprojects nothing: the timeline still holds the grab's own score object")
	_assert_eq(int(tl.move_preview_state().get("dx", 0)), 6,
		"the span tracks the cursor as a geometry OFFSET, at the last motion's delta")
	_assert_eq(page._body_drag_id, OMSID0,
		"…and the gesture never renumbered under the cursor: the drag id is the one it grabbed")

	page._on_span_body_drag_ended(OMSID0)
	_assert_true(_camera_fingerprint(page) != pristine, "release commits the slide for real")
	_assert_eq(_authored_start(page, "camera:for_each:angle#1"), 6,
		"…landing exactly where the preview promised, on the renumbered address")
	_assert_eq(String(tl.move_preview_state().get("id", "?")), "",
		"…and drops the geometry offset onto the committed lane")
	page.free()


## Every byte of the camera table a Move can touch. Not just the end_frames: the slide
## manufactures holds and re-lowers the whole stream, so a stray per-motion write could
## preserve the boundaries while rewriting the commands under them.
func _camera_fingerprint(page) -> String:
	var out: Array = []
	for phase in ["phase1", "for_each", "phase2"]:
		var t = page._effect_data.camera.get_table(phase)
		if t == null:
			continue
		for kf in t.keyframes:
			out.append("%s:%d/%d/%d" % [phase, int(kf.end_frame), int(kf.command_raw),
				int(kf.channel_mask)])
	return ",".join(out)


func _test_screen_span_grows_an_edge_grip() -> void:
	var page = _screen_page()
	var gripped := false
	for e in page._timeline._edge_rects:
		if String(e.get("span_id", "")) == SSID0:
			gripped = true
	_assert_true(gripped, "a screen span's right edge carries a drag grip")
	page.free()


## After a structural screen verb the page lands the selection by the RAW keyframe index —
## the screen span id is lane_id#index with the 1-D lane id.
func _test_screen_structural_result_selects_by_raw_index() -> void:
	var page = _screen_page()
	var ref := {"channel": "screen", "context": "for_each", "frame": 8}
	var sid: String = page._structural_result_span_id(ref, {"structural": true, "event_index": 1})
	_assert_eq(sid, "screen:for_each#1", "the screen structural result addresses lane_id#index")
	_assert_eq(page._structural_result_span_id(ref, {"structural": true, "event_index": -1}), "",
		"a negative index (lane emptied) selects nothing")
	page.free()


## The Ripple toggle (ADR-0087 dec. 10) is SESSION-LOCAL page state: off by default,
## flipped by the toolbar button's callback, never persisted into the effect file.
func _test_ripple_toggle_defaults_off_and_flips() -> void:
	var page = _page()
	_assert_true(not page._ripple, "ripple defaults OFF")
	page._toggle_ripple()
	_assert_true(page._ripple, "the toolbar toggle flips ripple on")
	page._toggle_ripple()
	_assert_true(not page._ripple, "…and back off")
	page.free()


## With ripple on, a colour-lane resize (drag boundary_end AND typed duration) carries
## `ripple: true` on the field_ref into the choke point — the channel skips the trade. The
## two affordances ride the SAME flag, so they can never diverge.
func _test_ripple_injects_the_flag_on_colour_resizes() -> void:
	var page = _palette_page()
	if not _capable(page):
		page.free()
		return
	page._ripple = true
	page._on_edge_dragged(PSID0, 32)
	page._process(0.0)
	_assert_eq(page._host.applies.size(), 1, "the ripple drag applies one edit")
	if not page._host.applies.is_empty():
		_assert_true(bool(page._host.applies[0]["field_ref"].get("ripple", false)),
			"the drag's boundary field_ref carries ripple: true")
	page.free()

	var spage = _screen_page()
	spage._ripple = true
	spage._apply_edit({"channel": "screen", "context": "for_each",
		"event_index": 0, "field": "duration"}, 24)
	_assert_eq(spage._host.applies.size(), 1, "the typed duration applies one edit")
	if not spage._host.applies.is_empty():
		_assert_true(bool(spage._host.applies[0]["field_ref"].get("ripple", false)),
			"the typed Duration field_ref carries ripple: true — same flag as the drag")
	spage.free()


## Camera JOINS ripple (ADR-0087 decs. 15-16 — every lane): with the toggle on, a
## camera end_frame resize — the drag AND the typed End-frame cell, through the SAME
## widened injection gate — carries `ripple: true` into the choke point.
func _test_ripple_rides_camera_end_frame_drags_and_typed_edits() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._ripple = true
	page._on_edge_dragged(SID0, 22)
	page._process(0.0)
	_assert_eq(page._host.applies.size(), 1, "the ripple camera drag applies one edit")
	if not page._host.applies.is_empty():
		_assert_true(bool(page._host.applies[0]["field_ref"].get("ripple", false)),
			"the camera end_frame drag carries ripple: true (2nd amendment)")
	page.free()

	var tpage = _page()
	tpage._ripple = true
	tpage._apply_edit({"channel": "camera", "context": "for_each",
		"camera_channel": "angle", "ordinal": 0, "field": "end_frame"}, 14)
	_assert_eq(tpage._host.applies.size(), 1, "the typed End frame applies one edit")
	if not tpage._host.applies.is_empty():
		_assert_true(bool(tpage._host.applies[0]["field_ref"].get("ripple", false)),
			"the typed End-frame field_ref carries ripple: true — same gate as the drag")
	tpage.free()


## End-to-end through the score: with ripple on, dragging PSID0's edge to abs 32 grows it and
## SHIFTS the downstream spans (PSID1 keeps its 16-frame width, its end moves 40 → 48) —
## instead of pinning the far edge with a trade.
func _test_ripple_drag_shifts_downstream_in_the_score() -> void:
	var page = _palette_page()
	if not _capable(page):
		page.free()
		return
	page._ripple = true
	page._on_edge_dragged(PSID0, 32)
	page._process(0.0)
	_assert_eq(_span_end(page, PSID0), 32, "the dragged span's right edge moved to abs 32")
	_assert_eq(_span_start(page, PSID1), 32, "the neighbour's start shifted with it")
	_assert_eq(_span_end(page, PSID1), 48, "…and its end too (width kept — downstream shifts, no trade)")
	page.free()


## The camera mirror of the palette shift test: with ripple on, dragging SID0's edge to
## abs 22 (local 14, Δ = +6) grows it and SHIFTS the downstream span — SID1 keeps its
## 12-frame width, its end moves 28 → 34 — instead of pinning the far edge with a trade.
func _test_ripple_camera_drag_shifts_downstream_in_the_score() -> void:
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._ripple = true
	page._on_edge_dragged(SID0, 22)
	page._process(0.0)
	_assert_eq(_span_end(page, SID0), 22, "the dragged camera span's right edge moved to abs 22")
	_assert_eq(_span_start(page, SID1), 22, "the neighbour's derived start shifted with it")
	_assert_eq(_span_end(page, SID1), 34, "…and its end too (width kept — downstream shifts, no trade)")
	page.free()


## With ripple on, the upper drag clamp is no longer next_end − 1 (the neighbour bound
## ripple exists to drop) but TAIL HEADROOM: CAMERA_END_MAX − (lane_last_end − this_end),
## so a drag physically cannot push the lane tail past s16.
func _test_ripple_swaps_the_camera_upper_clamp_to_tail_headroom() -> void:
	# Roomy lane: the old neighbour clamp (19) must NOT bite — local 92 applies as-is.
	var page = _page()
	if not _capable(page):
		page.free()
		return
	page._ripple = true
	page._on_edge_dragged(SID0, 100)
	page._process(0.0)
	_assert_eq(int(page._host.applies[0]["new_raw"]), 92,
		"the neighbour bound is dropped — the drag passes next_end − 1 unclamped")
	page.free()

	# Near-cap lane (ends 8 / 32760 local): headroom = 32767 − (32760 − 8) = 15.
	var cpage = _near_cap_page()
	cpage._ripple = true
	cpage._on_edge_dragged(SID0, 100)
	cpage._process(0.0)
	_assert_eq(int(cpage._host.applies[0]["new_raw"]), 15,
		"the drag clamps to tail headroom — the lane tail lands exactly on s16, never past")
	cpage.free()


## A particle span shares the edge-drag seam (ADR-0089 particle_timeline), with the flat
## raw-index address (phase context + channel_index + keyframe index — no sub-channel), and
## the value is the offset-corrected LOCAL frame (the ParticleTimelineChannel clamps, not the
## page).
func _test_particle_edge_drag_addresses_the_boundary_field() -> void:
	var page = _particle_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(PARTID1, 25)   # abs 25 → local 17 (offset 8)
	page._process(0.0)

	_assert_eq(page._host.applies.size(), 1, "one particle edge drag applies exactly one edit")
	if page._host.applies.is_empty():
		page.free()
		return
	var ref: Dictionary = page._host.applies[0]["field_ref"]
	_assert_eq(String(ref.get("channel", "")), "particle", "the edit addresses the particle channel")
	_assert_eq(String(ref.get("context", "")), "for_each", "…carrying the phase")
	_assert_eq(int(ref.get("channel_index", -1)), 0, "…the lane index (particle's 2nd address dim)")
	_assert_eq(int(ref.get("event_index", -1)), 1, "…the raw keyframe index")
	_assert_eq(String(ref.get("field", "")), "boundary_end", "…and writes the boundary pseudo-field")
	_assert_eq(int(page._host.applies[0]["new_raw"]), 17, "the ABSOLUTE 25 offset-corrected to LOCAL 17 (unclamped — channel clamps)")
	page.free()


## The applied particle boundary edit re-times the span: dragging PARTID1's edge to abs 25
## grows it into the adjacent gap, and the downstream drawn span #3 keeps its extent.
func _test_particle_edge_drag_resizes_and_reprojects() -> void:
	var page = _particle_page()
	if not _capable(page):
		page.free()
		return
	page._on_edge_dragged(PARTID1, 25)
	page._process(0.0)

	_assert_eq(_span_end(page, PARTID1), 25, "the dragged particle span's right edge moved to abs 25")
	_assert_eq(_span_start(page, PARTID3), 28, "the downstream drawn span's start is untouched (gap absorbed the grow)")
	_assert_eq(_span_end(page, PARTID3), 38, "…and its far edge stays pinned")
	page.free()


## The timeline's edge-grip gate includes particle spans (ADR-0089) — without the grip the
## boundary is undraggable no matter what the page can dispatch.
func _test_particle_span_grows_an_edge_grip() -> void:
	var page = _particle_page()
	var gripped := false
	for e in page._timeline._edge_rects:
		if String(e.get("span_id", "")) == PARTID1:
			gripped = true
	_assert_true(gripped, "a particle span's right edge carries a drag grip")
	page.free()


## A particle span BODY drag (ADR-0089 Move) slides the whole span through its surrounding
## gaps. PARTID3 (drawn, tail) has a gap on its left, so dragging it +5 shifts BOTH its
## boundaries by 5 (offset 8 → abs [33,43)).
func _test_particle_body_drag_slides_the_span() -> void:
	var page = _particle_page()
	if not page.has_method("_on_span_body_dragged"):
		_assert_true(false, "the page exposes the body-drag handlers")
		page.free()
		return
	page._on_span_body_drag_started(PARTID3)
	page._on_span_body_dragged(PARTID3, 5)
	page._process(0.0)

	_assert_eq(page._host.move_begins, 1, "one grab opens one Move")
	_assert_eq(_span_start(page, PARTID3), 33, "the span slid +5 (abs 28 → 33)")
	_assert_eq(_span_end(page, PARTID3), 43, "…both boundaries, width preserved")
	page.free()


## Grab → release brackets the whole drag as ONE Move (begin + end), and the first span (its
## left edge is the pinned origin) is refused by plan_move — the wiring is inert there.
func _test_particle_body_drag_brackets_one_move() -> void:
	var page = _particle_page()
	if not page.has_method("_on_span_body_drag_ended"):
		page.free()
		return
	page._on_span_body_drag_started(PARTID3)
	page._on_span_body_dragged(PARTID3, 5)
	page._process(0.0)
	page._on_span_body_drag_ended(PARTID3)
	_assert_eq(page._host.move_begins, 1, "one begin")
	_assert_eq(page._host.move_ends, 1, "one end — the gesture is one undo bracket")

	# The first span (PARTID1) is pinned to the origin: the preview is refused, nothing slides.
	page._on_span_body_drag_started(PARTID1)
	page._on_span_body_dragged(PARTID1, 4)
	page._process(0.0)
	_assert_eq(_span_start(page, PARTID1), 8, "the first span stays pinned (Move refused)")
	page.free()


## Deferred-refold drag preview (ADR-0089 Drag preview): a live particle EDGE drag reprojects
## the sim-free geometry per motion but DEFERS the expensive sim rescrub to release. Across a
## whole drag — grab, several motions each drained by a _process frame, release — the sim must
## refold exactly ONCE (on release), never per motion. The FakeHost mirrors the host's refold
## accounting: a sim-invalidating edit refolds unless the page asks it to defer; commit_refold
## folds the one deferred edit.
func _test_particle_edge_drag_defers_refold_to_release() -> void:
	var page = _particle_page()
	if not _capable(page):
		page.free()
		return
	var host = page._host
	page._on_edge_drag_started(PARTID1)
	page._on_edge_dragged(PARTID1, 24)
	page._process(0.0)                       # motion 1 drained
	page._on_edge_dragged(PARTID1, 25)
	page._process(0.0)                       # motion 2 drained
	_assert_true(host.applies.size() >= 2, "each motion applied its geometry edit")
	_assert_eq(host.refolds, 0, "no sim refold happens mid-drag (geometry-only preview)")

	page._on_edge_drag_ended(PARTID1)
	_assert_eq(host.commit_calls, 1, "release commits the deferred refold exactly once")
	_assert_eq(host.refolds, 1, "the whole drag costs ONE refold, not one per motion")
	page.free()


## The body-drag (Move) mirror of the deferred-refold contract: several motions, one refold on
## release.
func _test_particle_body_drag_defers_refold_to_release() -> void:
	var page = _particle_page()
	if not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var host = page._host
	page._on_span_body_drag_started(PARTID3)
	page._on_span_body_dragged(PARTID3, 3)
	page._process(0.0)
	page._on_span_body_dragged(PARTID3, 5)
	page._process(0.0)
	_assert_eq(host.refolds, 0, "no sim refold happens mid-Move (geometry-only preview)")

	page._on_span_body_drag_ended(PARTID3)
	_assert_eq(host.commit_calls, 1, "release commits the deferred refold exactly once")
	_assert_eq(host.refolds, 1, "the whole Move costs ONE refold, not one per motion")
	page.free()


## A TYPED (non-drag) particle boundary edit is NOT part of a drag gesture, so it refolds
## immediately — the deferral is a drag-only optimization, never applied to a discrete edit.
func _test_typed_particle_edit_refolds_immediately() -> void:
	var page = _particle_page()
	if not _capable(page):
		page.free()
		return
	var host = page._host
	page._apply_edit({"channel": "particle", "context": "for_each", "channel_index": 0,
		"event_index": 1, "field": "boundary_end"}, 17)
	_assert_eq(host.refolds, 1, "a typed particle edit refolds at once (no drag to defer to)")
	_assert_eq(host.commit_calls, 0, "…and never routes through the drag-release commit")
	page.free()


## ADR-0089 Drag preview (the perf fix): a live particle drag must reproject ONLY the particle
## lane geometry and REUSE every other kind's lanes — a full Model.build re-runs the ~400ms
## palette/screen spacer oracle every motion. We tag the live palette lane object; if the drag
## rebuilt palette, the fresh dict loses the tag. The tag surviving proves the geometry-only path.
func _test_particle_drag_reprojects_geometry_only_reusing_other_lanes() -> void:
	var page = _particle_and_palette_page()
	var pal := _score_lane(page, "palette:for_each:affected_units")
	_assert_true(not pal.is_empty(), "the fixture carries a palette lane alongside the particle lane")
	if pal.is_empty():
		page.free()
		return
	pal["_sentinel"] = 777   # tag the LIVE palette lane object

	page._on_span_body_drag_started(PARTID3)
	page._on_span_body_dragged(PARTID3, 5)
	page._process(0.0)       # one drag motion drained

	var pal2 := _score_lane(page, "palette:for_each:affected_units")
	_assert_eq(int(pal2.get("_sentinel", -1)), 777,
		"the palette lane is REUSED across a particle drag motion (geometry-only reproject — the 400ms rebuild skipped)")
	_assert_eq(_span_start(page, PARTID3), 33, "…and the dragged particle span still slid +5 (abs 28 → 33)")
	page._on_span_body_drag_ended(PARTID3)
	page.free()


# --- fixtures -------------------------------------------------------------

## A page over an effect with BOTH a particle lane (the drag target) and a palette lane (the
## bystander whose reuse we assert). Same particle fixture as _particle_page, plus three
## affected_units tweens so palette:for_each:affected_units exists.
func _particle_and_palette_page():
	var page = Page.new()
	var ed = _particle_effect()
	var kfs: Array = []
	for i in range(3):
		kfs.append({"index": i, "time_value": 2, "duration_frames": 16,
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	ed.palette = PaletteDataClass.from_json({"for_each": {"affected_units": {
		"context": "for_each", "channel_name": "affected_units", "max_keyframe": 4, "keyframes": kfs,
	}}})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


func _score_lane(page, lane_id: String) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("id", "")) == lane_id:
			return lane
	return {}


func _particle_page():
	var page = Page.new()
	var ed = _particle_effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


## Particle under for_each (offset 8): channel 0 with a drawn burst, a gap, then a drawn burst.
func _particle_effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [{
			"context": "for_each", "channel_index": 0, "max_keyframe": 3,
			"keyframes": [
				{"time": 0, "emitter_id": 0, "action_flags": 0},
				{"time": 10, "emitter_id": 1, "action_flags": 0},
				{"time": 20, "emitter_id": 0, "action_flags": 0},
				{"time": 30, "emitter_id": 2, "action_flags": 0}],
		}],
	})
	return ed


## THE REPORTED BUG (left-handle resize). HSID1 is a hidden hold, so the boundary at its
## right edge is HSID2's visible LEFT edge — the "left resize handle" the author reaches for.
## The drag must write the HOLD's end_frame (it is the boundary's one stored number) while
## selecting and inspecting HSID2. Selecting the hold instead un-hides it — a selected span is
## never a hidden spacer — and the drag read as "it created a spacer and selected it".
func _test_edge_drag_on_a_hold_selects_the_next_drawn_span() -> void:
	var page = _hold_page()
	if not _capable(page):
		page.free()
		return
	var host = page._host
	var tl = page._timeline
	_assert_true(Timeline.is_hidden_spacer(Model.find_span(tl._score, HSID1), ""),
		"fixture: span #1 is a hidden hold")

	page._on_edge_drag_started(HSID1)

	# The WRITE is unmoved: the hold's own ordinal, its own end_frame.
	_assert_eq(host.begin_count, 1, "grabbing a hold's boundary still opens one coalesce")
	_assert_eq(String(host.begin_field.get("field", "")), "end_frame", "…on end_frame")
	_assert_eq(int(host.begin_field.get("ordinal", -1)), 1,
		"…addressed to the HOLD — its end_frame IS the boundary")
	# The SELECTION follows the grip's on-screen owner instead.
	_assert_eq(tl.selected_span_id(), HSID2,
		"…but the next DRAWN span is selected, not the hold")
	_assert_true(not page._nav.is_empty() and page._nav.back() == Target.span(HSID2),
		"…and it is the inspection root, so ITS Length tracks the drag")
	_assert_true(Timeline.is_hidden_spacer(Model.find_span(tl._score, HSID1), tl.selected_span_id()),
		"the hold stays HIDDEN — no phantom spacer appears mid-drag")

	# And the whole gesture still lands on the hold's boundary.
	page._on_edge_dragged(HSID1, 24)   # abs 24 → phase-local 16
	page._process(0.0)
	_assert_eq(host.applies.size(), 1, "the drag applies one edit")
	_assert_eq(int(host.applies[0]["field_ref"].get("ordinal", -1)), 1,
		"…still addressed to the hold's ordinal")
	_assert_eq(int(host.applies[0]["new_raw"]), 16, "…moving the boundary to local 16")
	page._on_edge_drag_ended(HSID1)
	page.free()


## THE REPORTED BUG (the camera Move round trip). Drag the leftmost for_each camera event
## RIGHT, then drag it back: it stops ONE FRAME short of the origin, for good, however far it
## was dragged.
##
## The two verbs meet here. A rightward Move of the first event MANUFACTURES a hold to own the
## space it vacated (CameraChannel.move_span) — and by the grip-identity rule above, that
## hidden hold's RIGHT edge is the moved span's visible LEFT edge. So "drag it back" is an EDGE
## drag on the manufactured hold, not a Move, and it met `lo = authored_start + 1`. That floor
## is right for a DRAWN span and wrong for a hold: a hold owns empty space, and closing the
## space in front of the first event to NOTHING is exactly what Move itself writes. The residue
## was a constant 1 frame — independent of the drag distance, which is why it read as an
## off-by-one rather than a clamp.
func _test_move_right_then_drag_back_reaches_the_origin() -> void:
	var page = _origin_move_page()
	if not _capable(page) or not page.has_method("_on_span_body_dragged"):
		page.free()
		return
	var tl = page._timeline
	_assert_eq(_authored_start(page, OMSID0), 0, "fixture: the event starts at the phase origin")

	# 1. Slide it right by 6. The manufactured hold takes ordinal 0; the event lands on 1.
	page._on_span_body_drag_started(OMSID0)
	page._on_span_body_dragged(OMSID0, 6)
	page._process(0.0)
	page._on_span_body_drag_ended(OMSID0)
	_assert_eq(_authored_start(page, "camera:for_each:angle#1"), 6,
		"the Move slid the event right by 6")
	_assert_eq(_authored_end(page, "camera:for_each:angle#1"), 16, "…width preserved")
	_assert_true(Timeline.is_hidden_spacer(Model.find_span(tl._score, "camera:for_each:angle#0"), ""),
		"…and manufactured a HIDDEN hold to own the space it left at the origin")

	# 2. Reach for the event's left edge — which IS that hold's grip — and drag to the origin
	#    (abs 8 → phase-local 0), then keep going. It must close to nothing, not to one frame.
	page._on_edge_drag_started("camera:for_each:angle#0")
	page._on_edge_dragged("camera:for_each:angle#0", 8)
	page._process(0.0)
	_assert_eq(int(page._host.applies.back()["new_raw"]), 0,
		"a HOLD may close to zero width — the same number Move itself writes")
	page._on_edge_dragged("camera:for_each:angle#0", 2)   # past the origin: still 0, never −6
	page._process(0.0)
	_assert_eq(int(page._host.applies.back()["new_raw"]), 0,
		"…and never inverts past its own start")
	page._on_edge_drag_ended("camera:for_each:angle#0")

	# 3. The gap is gone: the drawn event owns the phase origin again.
	var back := _drawn_camera_span(page)
	_assert_eq(int(back.get("authored_start", -1)), 0,
		"the event reaches the origin again — no residual 1-frame gap")
	page.free()


## The GENERAL case, away from the origin: a hold BETWEEN two drawn events closes to nothing
## too, handing its whole span to the drawn event after it while the one before it stays put.
## (The reported case coincides with `authored_start == 0`; a guard aimed only at it would ship
## a fix that still refused every other hold.) A DRAWN span still keeps its minimum frame —
## `_test_edge_drag_clamps_min_one_frame` is the other half of this pair.
func _test_edge_drag_closes_a_mid_lane_hold_to_nothing() -> void:
	var page = _mid_hold_page()
	if not _capable(page):
		page.free()
		return
	var tl = page._timeline
	_assert_true(Timeline.is_hidden_spacer(Model.find_span(tl._score, MHSID1), ""),
		"fixture: span #1 is a hidden hold, [8,20) phase-local")

	page._on_edge_drag_started(MHSID1)
	page._on_edge_dragged(MHSID1, 16)     # abs 16 → phase-local 8 == its own start
	page._process(0.0)
	_assert_eq(int(page._host.applies.back()["new_raw"]), 8,
		"the mid-lane hold closes to zero width at its own start")
	page._on_edge_drag_ended(MHSID1)

	# Release DELETES the emptied hold (ADR-0101 dec. 7 — see the next test), so the drawn event
	# that followed it renumbers from #2 down to #1. Address it by where it now sits.
	_assert_eq(_authored_start(page, MHSID1), 8,
		"…so the drawn event after it starts where the hold began")
	_assert_eq(_authored_end(page, MHSID1), 32, "…keeping its own end")
	_assert_eq(_authored_end(page, "camera:for_each:angle#0"), 8,
		"…and the drawn event before it never moved")
	page.free()


## ADR-0101 decision 7, the half the boundary drag owes: a hold pulled back onto its own start
## owns NOTHING, and an owner of nothing is deleted — not parked at zero width. Parked, it is
## invisible in the lane (the score only emits a span for `end > prev_end`) but still a real
## opcode: a native SoA slot, a marker on the compiled lane, and +1 to every later ordinal. So
## dragging a hold shut and re-opening it used to cost a keyframe each time.
##
## The drop happens on RELEASE, because the drag re-resolves its address from the score every
## motion and a mid-gesture delete would renumber the lane under the cursor.
func _test_an_emptied_hold_is_deleted_on_release_not_left_behind() -> void:
	var page = _mid_hold_page()
	if not _capable(page):
		page.free()
		return
	var host = page._host
	var before: int = _kf_count(page)

	page._on_edge_drag_started(MHSID1)
	page._on_edge_dragged(MHSID1, 16)          # abs 16 → phase-local 8 == the hold's own start
	page._process(0.0)
	_assert_eq(host.deletes.size(), 0, "nothing is deleted mid-gesture — the address must hold")
	page._on_edge_drag_ended(MHSID1)

	_assert_eq(host.deletes.size(), 1, "releasing drops the hold that now owns nothing")
	_assert_eq(int(host.deletes[0].get("ordinal", -1)), 1, "…the one the drag was writing")
	_assert_eq(_kf_count(page), before - 1, "…freeing its keyframe")
	_assert_eq(_lane_ends(page), [8, 32],
		"the lane is two drawn events butted together — no zero-width orphan between them")
	page.free()


## A hold with room left is NOT dropped — the release check must fire on `owns nothing`, never
## on `is a hold`, or an ordinary resize would delete the thing being resized.
func _test_a_hold_with_room_left_survives_the_release() -> void:
	var page = _mid_hold_page()
	if not _capable(page):
		page.free()
		return
	var before: int = _kf_count(page)
	page._on_edge_drag_started(MHSID1)
	page._on_edge_dragged(MHSID1, 20)          # local 12 — the hold keeps [8,12)
	page._process(0.0)
	page._on_edge_drag_ended(MHSID1)
	_assert_eq(page._host.deletes.size(), 0, "a hold that still owns frames is left alone")
	_assert_eq(_kf_count(page), before, "…and keeps its keyframe")
	page.free()


## Live keyframes in the fixture's for_each table.
func _kf_count(page) -> int:
	var t = page._effect_data.camera.get_table("for_each")
	return mini(t.keyframes.size(), t.max_keyframe + 1)


## The for_each angle lane's authored ends, in order.
func _lane_ends(page) -> Array:
	var out: Array = []
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("id", "")) == "camera:for_each:angle":
			for sp in lane.get("spans", []):
				out.append(int(sp.get("authored_end", -1)))
	return out


## A hold at the LANE TAIL speaks for no span — ADR-0086 gives that grip the score end marker
## as its moving party, not a sibling. So the drag opens its bracket and writes as usual, and
## leaves the selection exactly where the author left it.
func _test_edge_drag_on_a_tail_hold_touches_no_selection() -> void:
	var page = _hold_page(true)
	if not _capable(page):
		page.free()
		return
	var host = page._host
	var tl = page._timeline
	tl.select_span(HSID0)
	page._set_root(Target.span(HSID0))

	page._on_edge_drag_started(HSID1)

	_assert_eq(host.begin_count, 1, "a tail hold still opens its coalesce bracket")
	_assert_eq(tl.selected_span_id(), HSID0, "…and moves no selection")
	_assert_true(not page._nav.is_empty() and page._nav.back() == Target.span(HSID0),
		"…leaving the inspection root where the author put it")
	page._on_edge_drag_ended(HSID1)
	page.free()


## A page over a camera lane carrying a hidden HOLD. Default: ends 8/20/32 with #1 authored
## `MAP` + zero (drawn, HOLD, drawn). `tail_hold` drops the third keyframe so the hold is the
## lane tail (drawn, HOLD) — the case with no successor to hand its grip to.
func _hold_page(tail_hold: bool = false):
	var page = Page.new()
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = [
		{"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 20,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "MAP", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
	]
	if not tail_hold:
		kfs.append({"index": 2, "end_frame": 32,
			"angle": [40, 50, 60], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0})
	ed.camera = CameraData.from_json({"for_each": {
		"max_keyframe": kfs.size() - 1, "keyframes": kfs}})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


func _capable(page) -> bool:
	var ok: bool = page.has_method("_on_edge_dragged") and page.has_method("_on_edge_drag_started") \
		and page.has_method("_on_edge_drag_ended")
	_assert_true(ok, "the page exposes the edge-drag handlers")
	return ok


## ADR-0095's three two-sided-grip tests lived here and were REMOVED with the design.
## ADR-0095 ("grabbable from either side") was superseded on 2026-08-21 by ADR-0086's
## reversal amendment — one grip per span, on the right edge, carrying two identities
## (its write owner and who it speaks for). That supersession deleted ADR-0095's three
## whole suites and its `side` parameter from `EffectStudioPage._on_edge_drag*`, but not
## its edits to THIS file, so three tests kept passing a third argument production no
## longer declares. Each call threw and aborted the enclosing function, under a green
## verdict. #465.


func _page():
	var page = Page.new()
	var ed = _camera_effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


## Camera under for_each (offset 8): two solo-angle keyframes at ends 8 and 20.
func _camera_effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 20,
			"angle": [40, 50, 60], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0}]}})
	return ed


## A page over a NEAR-CAP camera lane: two solo-angle keyframes at local ends 8 and 32760,
## so the ripple headroom above ordinal 0 is only 32767 − (32760 − 8) = 15.
func _near_cap_page():
	var page = Page.new()
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 32760,
			"angle": [40, 50, 60], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0}]}})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


func _palette_page():
	var page = Page.new()
	var ed = _palette_effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


## Palette under for_each (offset 8): three enabled tv-2 (16-frame) affected_units tweens.
func _palette_effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	for i in range(3):
		kfs.append({"index": i, "time_value": 2, "duration_frames": 16,
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	ed.palette = PaletteDataClass.from_json({"for_each": {"affected_units": {
		"context": "for_each", "channel_name": "affected_units", "max_keyframe": 4, "keyframes": kfs,
	}}})
	return ed


func _screen_page():
	var page = Page.new()
	var ed = _screen_effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


## Screen under for_each (offset 8): three tv-2 (16-frame) tweens, alternating Blend/Gradient.
func _screen_effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	for i in range(3):
		var blend: bool = (i % 2) == 0
		kfs.append({"index": i, "time_value": 2, "duration_frames": 16,
			"start_r": 10, "start_g": 20, "start_b": 30,
			"end_r": 10, "end_g": 20, "end_b": 30,
			"ctrl": (0x85 if blend else 0x00), "mode": ("TINT" if blend else "FADE"),
			"blend_mode": (5 if blend else 0)})
	ed.screen = ScreenDataClass.from_json({"for_each": {
		"context": "for_each", "max_keyframe": 4, "keyframes": kfs,
	}})
	return ed


func _span_end(page, span_id: String) -> int:
	var span: Dictionary = Model.find_span(page._timeline._score, span_id)
	return int(span.get("end", -1)) if not span.is_empty() else -1


## A page over the palette MOVE fixture — the structure-free drag's lane.
func _palette_move_page():
	var page = Page.new()
	var ed = _palette_move_effect()
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


## Hold, SPAN, hold, under for_each (offset 8). NOTHING is stamped: indices 1 and 3 are
## idempotent repeats of the tints before them, which is the fold's own reason to call a tile
## empty space — so the hold vector the planner trades against is the one the painter hides.
func _palette_move_effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	var spec := [[2, [200, 40, 40]], [2, [200, 40, 40]], [3, [40, 40, 200]],
		[2, [40, 40, 200]], [2, [40, 200, 40]]]
	var kfs: Array = []
	for i in range(spec.size()):
		kfs.append({"index": i, "time_value": int(spec[i][0]),
			"duration_frames": 8 * int(spec[i][0]), "rgb": spec[i][1],
			"ctrl": 0x85, "enabled": true, "blend_mode": 5})
	ed.palette = PaletteDataClass.from_json({"for_each": {"affected_units": {
		"context": "for_each", "channel_name": "affected_units", "max_keyframe": 6,
		"keyframes": kfs,
	}}})
	return ed


## Every byte a Move can touch, per keyframe, in index order. Deliberately not just the
## durations: the splice mints pads and copies holds, so a stray per-motion write could
## preserve the lengths while changing the tints or the ctrl bits under them.
func _kf_fingerprint(ch) -> String:
	var out: Array = []
	for kf in ch.keyframes:
		out.append("%d/%d/%d,%d,%d/%d/%d" % [kf.time_value, kf.duration_frames, kf.rgb.x,
			kf.rgb.y, kf.rgb.z, kf.ctrl, 1 if kf.enabled else 0])
	return "max=%d|%s" % [int(ch.max_keyframe), ",".join(out)]


## Does the FOLD call this span empty space? Read off the projected score, blind to selection —
## the fixture asserts its own premise rather than trusting the tint spec to imply it.
func _is_hold(tl, span_id: String) -> bool:
	return Timeline.is_hidden_spacer(Model.find_span(tl._score, span_id), "")


func _span_start(page, span_id: String) -> int:
	var span: Dictionary = Model.find_span(page._timeline._score, span_id)
	return int(span.get("start", -1)) if not span.is_empty() else -1


## A host stub recording every studio_apply_edit + coalesce call AND applying through a real
## EffectEditSession bound to the shared camera data — exactly what the production host does.
## A page over the lane the author's report starts from: a DRAWN angle event owning the phase
## origin ([0,10) local) and a `MAP`+zero hold out to 40 giving the Move somewhere to slide.
func _origin_move_page():
	return _camera_hold_page([
		_kf(0, 10, "DIRECT", 0x0841, [10, 20, 30]),
		_kf(1, 40, "MAP", 0x08C1, [0, 0, 0]),
	])


## A page over drawn(8) / `MAP`+zero hold(20) / drawn(32) — a hold with a drawn event on BOTH
## sides, so closing it is a pure hand-over rather than a phase-origin special case.
func _mid_hold_page():
	return _camera_hold_page([
		_kf(0, 8, "DIRECT", 0x0841, [10, 20, 30]),
		_kf(1, 20, "MAP", 0x08C1, [0, 0, 0]),
		_kf(2, 32, "DIRECT", 0x0841, [40, 50, 60]),
	])


## One angle-only camera keyframe. `command_raw` carries the SAME source mode as `source_mode`
## (the Move re-lowers the phase and rebuilds the field from the bits, so a fixture that packs
## only one of the two silently changes shape after the first edit).
func _kf(index: int, end_frame: int, source_mode: String, command_raw: int, angle: Array) -> Dictionary:
	return {
		"index": index, "end_frame": end_frame, "channel_mask": 1,
		"angle": angle, "position": [0, 0, 0], "zoom": [0, 0, 0],
		"command_raw": command_raw, "source_mode": source_mode,
		"interpolation": "LINEAR", "param_index": 0, "flags": 0,
	}


func _camera_hold_page(kfs: Array):
	var page = Page.new()
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": OFFSET, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = CameraData.from_json({"for_each": {
		"max_keyframe": kfs.size() - 1, "keyframes": kfs}})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	var host = _FakeHost.new()
	host.bind(ed)
	page._host = host
	return page


func _authored_start(page, span_id: String) -> int:
	return int(Model.find_span(page._timeline._score, span_id).get("authored_start", -1))


func _authored_end(page, span_id: String) -> int:
	return int(Model.find_span(page._timeline._score, span_id).get("authored_end", -1))


## The one DRAWN span in the for_each angle lane — addressed by content, not by ordinal, so a
## structural Move that renumbers the lane cannot make the assertion look at a hold instead.
func _drawn_camera_span(page) -> Dictionary:
	for lane in page._timeline._score.get("lanes", []):
		if String(lane.get("id", "")) != "camera:for_each:angle":
			continue
		for s in lane.get("spans", []):
			if not bool(s.get("fields", {}).get("spacer", false)):
				return s
	return {}


class _FakeHost extends RefCounted:
	const _Session = preload("res://src/effects/studio/EffectEditSession.gd")
	var applies: Array = []          # [{field_ref, new_raw}]
	var begin_field: Dictionary = {}
	var begin_count: int = 0
	var end_count: int = 0
	var _session = null
	func bind(ed) -> void:
		_session = _Session.new(ed)
	# Deferred-refold accounting (ADR-0089 Drag preview): mirror the real host so the wiring
	# test can assert ONE refold per drag. A sim-invalidating edit refolds unless the page asks
	# to defer; commit_refold folds the single deferred edit on release.
	var refolds: int = 0
	var commit_calls: int = 0
	var _deferred_pending: bool = false
	func studio_apply_edit(field_ref: Dictionary, new_raw, defer_refold: bool = false) -> Dictionary:
		applies.append({"field_ref": field_ref, "new_raw": new_raw})
		var res: Dictionary = _session.apply_edit(field_ref, new_raw) if _session != null else {}
		if res.get("invalidates_sim", false):
			if defer_refold:
				_deferred_pending = true
			else:
				refolds += 1
		return res
	func studio_commit_refold() -> void:
		commit_calls += 1
		if _deferred_pending:
			refolds += 1
		_deferred_pending = false
	func studio_begin_coalesce(field_ref: Dictionary) -> void:
		begin_field = field_ref
		begin_count += 1
		if _session != null and _session.has_method("begin_coalesce"):
			_session.begin_coalesce(field_ref)
	func studio_end_coalesce() -> void:
		end_count += 1
		if _session != null and _session.has_method("end_coalesce"):
			_session.end_coalesce()
	func studio_seek(_f: int) -> void:
		pass
	# Move body-drag (ADR-0089): delegate to the real session, recording the calls.
	var move_begins: int = 0
	var move_ends: int = 0
	var move_previews: Array = []      # [{field_ref, delta}]
	func studio_begin_move(field_ref: Dictionary) -> void:
		move_begins += 1
		if _session != null:
			_session.begin_move(field_ref)
	func studio_move_preview(field_ref: Dictionary, delta: int, defer_refold: bool = false) -> Dictionary:
		move_previews.append({"field_ref": field_ref, "delta": delta})
		var res: Dictionary = _session.move_preview(field_ref, delta) if _session != null else {}
		if not res.is_empty():
			if defer_refold:
				_deferred_pending = true
			else:
				refolds += 1
		return res
	func studio_end_move() -> Dictionary:
		move_ends += 1
		return _session.end_move() if _session != null else {}
	# Structural delete (ADR-0101 dec. 7): the release-time drop of a hold the drag emptied.
	var deletes: Array = []
	func studio_delete_event(field_ref: Dictionary) -> Dictionary:
		deletes.append(field_ref)
		return _session.delete_event(field_ref) if _session != null else {}


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
