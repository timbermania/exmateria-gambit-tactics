extends Node
## TDD guard for the Effect Studio ANCHOR host wiring (ADR-0085 Slice 1b, Seam 6) —
## the page glue that turns a timeline anchor-drag into a byte-faithful authoring edit.
## When the author drags a sound trigger's anchor handle, the page must:
##   (1) resolve the trigger's THREE-dim keyframe address off the live score span
##       (phase + channel_index + event_index) and address the `anchor_offset` FIELD,
##   (2) lower it through the host's studio_apply_edit choke point (the same path
##       sound_id/duration use) — NOT sound_id/duration, so the fire + bytes stay put,
##   (3) reproject just the handle (set_anchor_offset) so it tracks the cursor without
##       the transport/selection reset a full rebuild causes.
## Pure logic: the page is new()'d WITHOUT add_child (no _ready UI build); we inject a
## real timeline + a recording fake host and call the drag callback directly.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioAnchorWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_anchor_drag_routes_to_choke_point_and_reprojects()
	_test_unknown_span_is_inert()
	_test_rebuild_score_threads_energy_map()

	print("\n=== EffectStudioAnchorWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioAnchorWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioAnchorWiringTest")
		get_tree().quit(0)


func _test_anchor_drag_routes_to_choke_point_and_reprojects() -> void:
	var page = Page.new()
	var tl = _timeline_with_sound_anchor(8, 20)
	page._timeline = tl
	var host := _FakeHost.new()
	page._host = host
	var sid := "sound:for_each:0#0"
	var span: Dictionary = tl._score["lanes"][0]["spans"][0]
	var start := float(span["start"])

	page._on_anchor_offset_changed(sid, 13)

	# (1)+(2): exactly one edit reached the choke point, addressing anchor_offset via the
	# trigger's three-dim address — NOT sound_id/duration.
	_assert_eq(host.calls.size(), 1, "the drag lowers exactly one edit through the host choke point")
	if host.calls.is_empty():
		page.free()
		return
	var ref: Dictionary = host.calls[0][0]
	_assert_eq(ref.get("channel", ""), "sound", "the edit addresses a sound channel")
	_assert_eq(ref.get("field", ""), "anchor_offset", "the edit writes anchor_offset, not sound_id/duration (fire + bytes stay)")
	_assert_eq(ref.get("phase", ""), "for_each", "the address carries the trigger's phase")
	_assert_eq(int(ref.get("channel_index", -1)), 0, "the address carries the channel_index")
	_assert_eq(int(ref.get("event_index", -1)), 0, "the address carries the event_index")
	_assert_eq(int(host.calls[0][1]), 13, "the clamped offset value is lowered verbatim")

	# (3): the handle reprojected to fire + 13, and the fire frame did NOT move.
	_assert_eq(int(tl._score["lanes"][0]["spans"][0]["start"]), 8, "the fire frame never moves")
	var handle: Rect2 = tl.anchor_rect_for(sid)
	_assert_true(absf(handle.get_center().x - tl.axis.frame_to_x(start + 13.0)) < 2.0,
		"the handle reprojects to fire + offset after the drag")
	page.free()


func _test_unknown_span_is_inert() -> void:
	var page = Page.new()
	var tl = _timeline_with_sound_anchor(8, 20)
	page._timeline = tl
	var host := _FakeHost.new()
	page._host = host

	page._on_anchor_offset_changed("does:not:exist#9", 5)
	_assert_eq(host.calls.size(), 0, "an unknown span id lowers no edit")
	page.free()


## ADR-0085 climax cue wiring: the page holds the rendered {sound_id → energy} map
## next to the ghost map, and `_rebuild_score()` (the single build site the load and
## every re-project funnel through) must thread BOTH into EffectScoreModel.build so a
## trigger's ghost bar carries its energy envelope. Guards the threading without the
## SPU — the render itself is proven in SoundEnvelopeCaptureTest.
func _test_rebuild_score_threads_energy_map() -> void:
	var page = Page.new()
	var ed = EffectDataClass.new()
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
	page._timeline = tl
	page._effect_data = ed
	page._ghost_by_sound_id = {5: 20}
	page._energy_by_sound_id = {5: PackedFloat32Array([0.0, 1.0, 0.5])}

	page._rebuild_score()

	var span: Dictionary = tl._score["lanes"][0]["spans"][0]
	_assert_eq(int(span.get("ghost_frames", 0)), 20, "_rebuild_score threads the ghost map")
	_assert_eq(span["energy"].size(), 3, "_rebuild_score threads the energy map onto the span")
	_assert_true(absf(span["energy"][1] - 1.0) < 1e-6, "the envelope's peak reaches the span")
	page.free()


func _timeline_with_sound_anchor(offset: int, ghost: int):
	var ed = EffectDataClass.new()
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


## A host stub recording every studio_apply_edit; has_method("studio_apply_edit") is
## true (Object builtin), so the page's guard routes to it.
class _FakeHost extends RefCounted:
	var calls: Array = []
	func studio_apply_edit(ref: Dictionary, raw, defer_refold = false) -> Dictionary:
		calls.append([ref, raw])
		return {"invalidates_sim": false, "faithful": {"ok": true}}


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
