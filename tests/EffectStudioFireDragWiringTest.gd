extends Node
## TDD guard for the Effect Studio FIRE-DRAG host wiring (ADR-0085) — the page glue
## that turns a timeline marker-drag into a byte-faithful, stay-local trigger move.
## When the author drags a sound trigger's instant marker, the page must:
##   (1) resolve the trigger's THREE-dim keyframe address off the live score span
##       (phase + channel_index + keyframe_index) and read the channel's live gaps,
##   (2) turn the target fire frame into the stay-local gap edits (SoundGapMath:
##       dur[N-1] += K, dur[N] -= K) and lower them as ONE compound edit through the
##       host — so the two-gap write is a single undo,
##   (3) reproject the WHOLE score from the now-edited live gaps (ADR-0085 unified path),
##       landing the marker on the CLAMPED new fire, not the raw cursor target — the
##       timeline reports intent; the host owns the bounds. This is the SAME reproject a
##       typed Gap edit takes, so dragging and typing agree (no surgical set_fire_frame).
## The FIRST trigger is pinned (no prior gap) → the drag lowers nothing.
## Pure logic: the page is new()'d WITHOUT add_child (no _ready UI build); we inject a
## real timeline + effect data + a recording fake host. The host APPLIES the compound to
## the shared effect data (as the real host does) so the page's rebuild reflects the move.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioFireDragWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_fire_drag_lowers_stay_local_compound_and_reprojects()
	_test_fire_drag_reprojects_to_the_clamped_fire_not_the_raw_target()
	_test_first_trigger_is_pinned_lowers_nothing()
	_test_unknown_span_is_inert()
	_test_baseline_cumulative_reads_from_the_drag_start_snapshot()
	_test_drag_away_then_back_to_origin_restores_the_fire()
	_test_fire_drag_ended_clears_the_baseline()
	_test_fire_drag_selects_trigger_as_inspection_root()
	_test_fire_drag_live_updates_inspector_gap()
	_test_ripple_fire_drag_edits_only_the_prior_gap_and_shifts_later_fires()
	_test_ripple_fire_drag_first_trigger_stays_pinned()
	_test_ripple_fire_drag_bottoms_out_at_gap_zero()
	_test_ripple_fire_drag_is_baseline_cumulative_and_one_undo()
	_test_typed_gap_is_natively_ripple_no_flag_no_branch()

	print("\n=== EffectStudioFireDragWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFireDragWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFireDragWiringTest")
		get_tree().quit(0)


## Fixture gaps [4,10,6] at for_each offset 8 → fires 8,12(,22 terminator). Drag the
## SECOND trigger (fire 12) to frame 17 (K=+5): stay-local edits are dur[0]=4+5=9,
## dur[1]=10-5=5, lowered as ONE compound, and the marker reprojects to 17.
func _test_fire_drag_lowers_stay_local_compound_and_reprojects() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#1"

	page._on_fire_frame_changed(sid, 17)

	# (1)+(2): exactly one COMPOUND edit reached the host, with the two neighbouring
	# duration_frames gaps, each addressed by the trigger's three-dim sound address.
	_assert_eq(host.compounds.size(), 1, "the drag lowers exactly one compound edit (one undo)")
	if host.compounds.is_empty():
		page.free()
		return
	var edits: Array = host.compounds[0]
	_assert_eq(edits.size(), 2, "the compound trades the two neighbouring gaps")
	var m0: Dictionary = _member_for_event(edits, 0)
	var m1: Dictionary = _member_for_event(edits, 1)
	_assert_eq(m0.get("field_ref", {}).get("channel", ""), "sound", "gap edit addresses a sound channel")
	_assert_eq(m0.get("field_ref", {}).get("field", ""), "duration_frames", "gap edit writes duration_frames")
	_assert_eq(m0.get("field_ref", {}).get("phase", ""), "for_each", "address carries the phase")
	_assert_eq(int(m0.get("field_ref", {}).get("channel_index", -1)), 0, "address carries the channel_index")
	_assert_eq(int(m0.get("new_raw", -1)), 9, "dur[N-1] gains K (4+5)")
	_assert_eq(int(m1.get("new_raw", -1)), 5, "dur[N] loses K (10-5)")

	# (3): the marker reprojected to fire 17; the FIRST trigger did not move.
	_assert_eq(int(_span_start(tl, sid)), 17, "the dragged trigger's marker moves to the new fire")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#0")), 8, "the first trigger never moves")
	page.free()


## A target past the next trigger clamps: dragging the second trigger (fire 12) to
## frame 100 clamps K to dur[1]=10, so the marker lands on 22 (coincident with the
## terminator), NOT the raw 100. Proves the host reprojects to the CLAMPED fire.
func _test_fire_drag_reprojects_to_the_clamped_fire_not_the_raw_target() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#1"

	page._on_fire_frame_changed(sid, 100)

	_assert_eq(int(_span_start(tl, sid)), 22, "the marker reprojects to the clamped fire, not the raw target")
	page.free()


## The first trigger's fire IS the phase offset — no prior gap to trade — so a drag on
## it lowers no edit and moves nothing.
func _test_first_trigger_is_pinned_lowers_nothing() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host

	page._on_fire_frame_changed("sound:for_each:0#0", 20)

	_assert_eq(host.compounds.size(), 0, "the pinned first trigger lowers no compound edit")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#0")), 8, "the first trigger stays put")
	page.free()


func _test_unknown_span_is_inert() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host

	page._on_fire_frame_changed("does:not:exist#9", 5)
	_assert_eq(host.compounds.size(), 0, "an unknown span id lowers no edit")
	page.free()


## Baseline-cumulative lifecycle (BUG #3 fix): on grab the page snapshots a DEEP COPY
## of the live gaps; every motion computes edits from that fixed drag-start baseline +
## a cumulative delta, never from the now-mutated live gaps. Skip-aware fixture: gaps
## [14,11,15,16,544,600], sids [0,2,0,3,0,0], for_each offset 0 → the audible trigger
## #3 fires at frame 40. After grab we MUTATE the live gaps (simulating a prior motion's
## applied write); dragging to fire 20 (cumulative -20) must still floor on the previous
## audible via the BASELINE gaps: dur[2] 15→0 (nearest), dur[1] 11→6 (spill), dur[3]
## 16→36. A live-read would clamp differently (proving it reads the snapshot).
func _test_baseline_cumulative_reads_from_the_drag_start_snapshot() -> void:
	var page = Page.new()
	var ed = _sound_effect_sid([14, 11, 15, 16, 544, 600], [0, 2, 0, 3, 0, 0], 6, 0)
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#3"

	page._on_fire_drag_started(sid)
	# A prior motion already mutated the LIVE gaps in place — the baseline must ignore this.
	var live: Array = ed.sound["for_each"][0]["keyframes"]
	live[2]["duration_frames"] = 0
	live[3]["duration_frames"] = 42

	page._on_fire_frame_changed(sid, 20)

	_assert_eq(host.compounds.size(), 1, "the drag lowers one compound from the baseline")
	var edits: Array = host.compounds[0] if not host.compounds.is_empty() else []
	_assert_eq(int(_member_for_event(edits, 3).get("new_raw", -1)), 36,
		"dur[3] is 16+20 from the BASELINE (36), not the mutated live 42")
	_assert_eq(int(_member_for_event(edits, 2).get("new_raw", -1)), 0,
		"the nearest skip gap collapses from baseline 15 → 0")
	_assert_eq(int(_member_for_event(edits, 1).get("new_raw", -1)), 6,
		"the farther audible gap keeps the spill from baseline 11 → 6")
	_assert_eq(int(_span_start(tl, sid)), 20, "reprojects to baseline_fire + applied_delta (40-20)")
	page.free()


## The reported bug, end-to-end: grab a trigger, drag it one frame EARLIER, then drag back
## to the ORIGINAL frame. The return (delta 0 from the baseline) must restore the trigger to
## its start fire — previously delta 0 lowered nothing, so the marker stuck one frame early and
## the origin was unreachable ("you can get one frame before the original, but not the original").
func _test_drag_away_then_back_to_origin_restores_the_fire() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])   # for_each offset 8 → trigger #1 fires at 12
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)
	page._on_fire_frame_changed(sid, 11)   # drag one frame earlier
	_assert_eq(int(_span_start(tl, sid)), 11, "the trigger moves one frame earlier")
	page._on_fire_frame_changed(sid, 12)   # drag back to the original frame
	_assert_eq(int(_span_start(tl, sid)), 12, "returning to the origin frame restores the trigger (the bug)")
	# The live gaps are restored byte-for-byte to the baseline, so the move truly reversed.
	var live: Array = ed.sound["for_each"][0]["keyframes"]
	_assert_eq(int(live[0]["duration_frames"]), 4, "dur[0] restored to baseline")
	_assert_eq(int(live[1]["duration_frames"]), 10, "dur[1] restored to baseline")
	page.free()


## Release clears the baseline, so a later motion falls back to the LIVE gaps. Grab then
## release, then mutate dur[0] 4→9 and drag +2: reading live gives dur[0]=9+2=11; the
## stale baseline would have given 4+2=6. 11 proves the baseline was dropped on release.
func _test_fire_drag_ended_clears_the_baseline() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)
	page._on_fire_drag_ended(sid)
	ed.sound["for_each"][0]["keyframes"][0]["duration_frames"] = 9

	page._on_fire_frame_changed(sid, 14)

	_assert_eq(host.compounds.size(), 1, "the fallback path still lowers a compound")
	var edits: Array = host.compounds[0] if not host.compounds.is_empty() else []
	_assert_eq(int(_member_for_event(edits, 0).get("new_raw", -1)), 11,
		"after release the caller reads LIVE gaps (9+2), not the stale baseline (4+2)")
	page.free()


## Grabbing a trigger's marker makes it the inspection ROOT — it selects on the timeline
## AND becomes what the inspector shows — so its Gap can track the drag live. (A fire-grab
## used to select nothing, leaving the inspector on a stale trigger.)
func _test_fire_drag_selects_trigger_as_inspection_root() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)

	_assert_eq(tl.selected_span_id(), sid, "grabbing a trigger selects it on the timeline")
	_assert_true(not page._nav.is_empty() and page._nav.back() == Target.span(sid),
		"…and makes it the inspection root so the inspector shows it")
	page.free()


## Each drag MOVE re-derives the inspector, so the dragged trigger's Gap field tracks the
## drag live (dragging trigger 1 later by K shrinks its gap to the next: dur[1] 10 → 5 at
## K=5). Proven with a fake inspector that records the sections it was handed.
func _test_fire_drag_live_updates_inspector_gap() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	var insp := _FakeInspector.new()
	page._inspector = insp
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)
	_assert_eq(insp.target, Target.span(sid), "the grab renders the dragged trigger in the inspector")
	_assert_eq(_gap_value(insp.sections), 10, "the inspector first shows the trigger's current Gap (dur[1]=10)")
	var calls_before: int = insp.calls

	page._on_fire_frame_changed(sid, 17)   # drag trigger 1 later (K=+5)

	_assert_true(insp.calls > calls_before, "each drag move re-derives the inspector")
	_assert_eq(insp.target, Target.span(sid), "…still showing the dragged trigger")
	_assert_eq(_gap_value(insp.sections), 5, "the Gap tracks the drag live (dur[1] 10 → 5)")
	page.free()


## RIPPLE fire-drag (ADR-0087 decs. 15-16): with the toggle on, the drag skips the
## SoundGapMath stay-local trade — it edits ONLY the grabbed trigger's PRIOR gap as a plain
## scalar through the choke point, so every later fire shifts by the delta. Fixture gaps
## [4,10,6,8] / sids [5,6,6,0] at offset 8 → fires 8, 12, 22 (skip 30). Dragging trigger
## #1 to 17 (Δ = +5) writes dur[0] = 9 and NO compound; #2's fire rides to 27; #0 is still 8.
func _test_ripple_fire_drag_edits_only_the_prior_gap_and_shifts_later_fires() -> void:
	var page = Page.new()
	var ed = _sound_effect_sid([4, 10, 6, 8], [5, 6, 6, 0], 3, 8)
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	page._ripple = true
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)
	page._on_fire_frame_changed(sid, 17)

	_assert_eq(host.compounds.size(), 0, "ripple skips the stay-local compound trade")
	_assert_eq(host.applies.size(), 1, "…and lowers ONE plain scalar edit instead")
	if host.applies.is_empty():
		page.free()
		return
	var ref: Dictionary = host.applies[0]["field_ref"]
	_assert_eq(String(ref.get("channel", "")), "sound", "the edit addresses the sound channel")
	_assert_eq(String(ref.get("phase", "")), "for_each", "…carrying the phase")
	_assert_eq(int(ref.get("channel_index", -1)), 0, "…the channel_index")
	_assert_eq(int(ref.get("event_index", -1)), 0, "…the PRIOR keyframe (the grabbed trigger's prior gap)")
	_assert_eq(String(ref.get("field", "")), "duration_frames", "…and writes duration_frames")
	_assert_eq(int(host.applies[0]["new_raw"]), 9, "the prior gap gains the delta (4+5)")
	_assert_eq(int(_span_start(tl, sid)), 17, "the dragged trigger lands on its new fire")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#2")), 27, "every LATER fire shifts by the delta")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#0")), 8, "the first trigger never moves")
	page.free()


## The first trigger has no prior gap — with ripple on it stays pinned: no scalar, no
## compound, no motion (same pin as the stay-local path).
func _test_ripple_fire_drag_first_trigger_stays_pinned() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	page._ripple = true

	page._on_fire_frame_changed("sound:for_each:0#0", 20)

	_assert_eq(host.applies.size(), 0, "the pinned first trigger lowers no scalar edit")
	_assert_eq(host.compounds.size(), 0, "…and no compound either")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#0")), 8, "the first trigger stays put")
	page.free()


## Dragging left bottoms out at gap 0 (fires coincide — same as typing Gap = 0): trigger #1
## (fire 12, prior gap 4) dragged to 5 clamps the prior gap at 0, landing the fire on 8.
## A skip-aware ripple that consumes EARLIER gaps is rejected by design.
func _test_ripple_fire_drag_bottoms_out_at_gap_zero() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	page._ripple = true
	var sid := "sound:for_each:0#1"

	page._on_fire_frame_changed(sid, 5)

	_assert_eq(host.applies.size(), 1, "the leftward drag lowers one scalar edit")
	if not host.applies.is_empty():
		_assert_eq(int(host.applies[0]["new_raw"]), 0, "the prior gap bottoms out at 0 — never negative")
	_assert_eq(int(_span_start(tl, sid)), 8, "the fire coincides with the previous trigger")
	page.free()


## The real UI path: grab snapshots the baseline and opens a ONE-UNDO coalesce bracket on
## the prior-gap field. Motions compute from the BASELINE + cumulative delta (a live-gap
## read would double-apply), coalescing to a single undo entry — one undo restores the
## pristine pre-drag gap.
func _test_ripple_fire_drag_is_baseline_cumulative_and_one_undo() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	page._ripple = true
	var sid := "sound:for_each:0#1"

	page._on_fire_drag_started(sid)
	_assert_eq(host.begin_count, 1, "grab opens the one-undo coalesce bracket")
	_assert_eq(int(host.begin_field.get("event_index", -1)), 0, "…on the PRIOR gap's address")
	_assert_eq(String(host.begin_field.get("field", "")), "duration_frames", "…duration_frames")

	page._on_fire_frame_changed(sid, 17)   # Δ = +5 from the baseline fire 12 → dur[0] 9
	page._on_fire_frame_changed(sid, 14)   # Δ = +2 CUMULATIVE from baseline → dur[0] 6, not 9+2
	_assert_eq(host.applies.size(), 2, "each motion applies a scalar edit")
	if host.applies.size() == 2:
		_assert_eq(int(host.applies[1]["new_raw"]), 6,
			"the second motion is baseline-cumulative (4+2), not live-relative (9+2)")

	page._on_fire_drag_ended(sid)
	_assert_eq(host.end_count, 1, "release closes the bracket")

	_assert_true(host.undo(), "the whole drag is one undo")
	_assert_eq(int(ed.sound["for_each"][0]["keyframes"][0]["duration_frames"]), 4,
		"…restoring the pristine pre-drag gap")
	_assert_true(not host.undo(), "nothing further to undo — one drag, one entry")
	page.free()


## The typed Gap is ripple BY NATURE — the gap IS the offset to the next trigger, so a
## duration_frames edit already shifts every later fire, toggle or no toggle. The injection
## gate must NOT touch sound: no `ripple` flag rides the field_ref, no channel branch
## exists to "fix". Guard so nobody adds one.
func _test_typed_gap_is_natively_ripple_no_flag_no_branch() -> void:
	var page = Page.new()
	var ed = _sound_effect([4, 10, 6])
	var tl = _timeline_for(ed)
	page._timeline = tl
	page._effect_data = ed
	var host := _FakeHost.new()
	host.bind(ed)
	page._host = host
	page._ripple = true

	page._apply_edit({"channel": "sound", "phase": "for_each", "channel_index": 0,
		"event_index": 0, "field": "duration_frames"}, 9)

	_assert_eq(host.applies.size(), 1, "the typed Gap applies one edit")
	if not host.applies.is_empty():
		_assert_true(not host.applies[0]["field_ref"].has("ripple"),
			"no ripple flag on a sound Gap — it is natively ripple, the gate leaves it alone")
	_assert_eq(int(_span_start(tl, "sound:for_each:0#1")), 17,
		"the typed Gap shifted the later fire (8+9) with the toggle irrelevant")
	page.free()


func _gap_value(sections: Array) -> int:
	for sec in sections:
		for f in sec.get("fields", []):
			if f.get("name", "") == "Gap":
				return int(f.get("value", -1))
	return -1


## A recording inspector stub: captures the target + sections handed to show_target so a
## drag-move re-render is observable without a live UI. show_target's 13-param signature
## mirrors EffectStudioPage._render_current's call.
class _FakeInspector extends RefCounted:
	# The page writes this on every re-derive (EffectStudioPage.gd:4445). Without it the
	# assignment throws and takes the whole re-derive down with it, so the inspector
	# renders {} and the Gap reads -1 — all five of this file's reds were that one gap.
	var name_column_width: float = 0.0
	var target: Dictionary = {}
	var sections: Array = []
	var calls: int = 0
	func show_target(t, _header, secs, _a, _b, _c, _d, _e, _f, _g, _h = null,
			hide_inert = false, marker = {}, on_action = null) -> void:
		target = t
		sections = secs
		calls += 1
	func update_marker(_marker) -> void:
		pass


func _sound_effect(durations: Array):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	var sids := [5, 6, 0]
	for i in range(durations.size()):
		kfs.append({"duration_frames": int(durations[i]), "sound_id": sids[i] if i < sids.size() else 0})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": kfs},
		],
	}
	return ed


## Like _sound_effect but with explicit sids / max_keyframe / for_each offset — for the
## skip-aware baseline fixture. A firing sid (>=2) gets a ghost so its span projects.
func _sound_effect_sid(durations: Array, sids: Array, max_keyframe: int, offset: int):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": offset, "phase2_delay": 64},
		"particle_channels": [],
	})
	var kfs: Array = []
	for i in range(durations.size()):
		kfs.append({"duration_frames": int(durations[i]), "sound_id": int(sids[i])})
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": max_keyframe, "keyframes": kfs},
		],
	}
	return ed


func _timeline_for(ed):
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {6: 20}))
	tl.rebuild_layout()
	return tl


func _span_start(tl, span_id: String) -> int:
	for lane in tl._score.get("lanes", []):
		for span in lane.get("spans", []):
			if span.get("id", "") == span_id:
				return int(span.get("start", -1))
	return -1


func _member_for_event(edits: Array, event_index: int) -> Dictionary:
	for e in edits:
		if int(e.get("field_ref", {}).get("event_index", -1)) == event_index:
			return e
	return {}


## A host stub recording every studio_apply_compound AND applying it to the shared effect
## data through the real EffectEditSession — exactly what the production host does. The
## page then rebuilds the score from that now-edited data, so the reprojected marker lands
## on its new fire. has_method(...) is true (Object builtin), so the page routes to it.
class _FakeHost extends RefCounted:
	const _Session = preload("res://src/effects/studio/EffectEditSession.gd")
	var compounds: Array = []
	var applies: Array = []          # [{field_ref, new_raw}] — the ripple scalar path
	var begin_field: Dictionary = {}
	var begin_count: int = 0
	var end_count: int = 0
	var _session = null
	## Bind the session to the SAME effect data the page holds, so applied gap edits are
	## visible to the page's rebuild. Call after wiring page._effect_data.
	func bind(ed) -> void:
		_session = _Session.new(ed)
	func studio_apply_compound(edits: Array) -> Dictionary:
		compounds.append(edits)
		if _session != null:
			return _session.apply_compound(edits)
		return {"invalidates_sim": false, "results": []}
	func studio_apply_edit(field_ref: Dictionary, new_raw, defer_refold = false) -> Dictionary:
		applies.append({"field_ref": field_ref, "new_raw": new_raw})
		if _session != null:
			return _session.apply_edit(field_ref, new_raw)
		return {}
	func studio_begin_coalesce(field_ref: Dictionary) -> void:
		begin_field = field_ref
		begin_count += 1
		if _session != null:
			_session.begin_coalesce(field_ref)
	func studio_end_coalesce() -> void:
		end_count += 1
		if _session != null:
			_session.end_coalesce()
	func undo() -> bool:
		return _session.undo() if _session != null else false


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
