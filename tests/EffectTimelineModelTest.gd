extends Node
## TDD guard for EffectTimelineModel — the PURE projection that turns a
## TimelineData (parsed E###.BIN particle channels) into the "score" the
## embedded EffectViewer timeline strip draws: per-context channel lanes, each
## lane a list of absolute-frame emitter spans. No scene, no drawing: the model
## is the testable core, EffectTimelineView is thin glue over it (mirrors the
## TuneDashboardModel / TuneDashboardPanel split).
##
## Keyframe semantics come straight from PhaseBlock: kf[0] is skipped, and
## kf[N].emitter_id spawns emitter (id-1) DURING frames [kf[N-1].time, kf[N].time);
## emitter_id 0 is a gap. Each context is offset onto the absolute timeline:
## phase1 at 0, for_each at phase1_duration, phase2 at phase2_start.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectTimelineModelTest.tscn

const Model = preload("res://src/debug/EffectTimelineModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const EffectPhaseClass = ExMateriaEffects.EffectPhase

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_spans_from_keyframes()
	_test_gap_keyframes_produce_no_span()
	_test_context_offsets_onto_absolute_timeline()
	_test_silent_channels_excluded()
	_test_max_frame_spans_score_and_phase2()
	_test_lane_order_is_phase_then_channel()

	print("\n=== EffectTimelineModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectTimelineModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectTimelineModelTest")
		get_tree().quit(0)


## A channel's spans come from consecutive keyframe pairs: keyframe N spans
## [kf[N-1].time, kf[N].time) and spawns emitter (kf[N].emitter_id - 1). The
## kf[0] anchor (time 0) is never itself a span, only a left edge.
func _test_spans_from_keyframes() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE1: [
			_channel(0, [[0, 0], [10, 3], [30, 6]]),  # e3 over 0..10, e6 over 10..30
		],
	})
	var model := Model.build(tl, 0, 0)
	var lane := _lane_for(model, EffectPhaseClass.PHASE1, 0)
	_assert_eq(lane["spans"].size(), 2, "two active keyframes -> two spans")
	_assert_span(lane["spans"][0], 2, 0, 10, "kf1 spawns emitter 2 (id 3) over [0,10)")
	_assert_span(lane["spans"][1], 5, 10, 30, "kf2 spawns emitter 5 (id 6) over [10,30)")


## A keyframe with emitter_id 0 is a silence window, not a block — it advances
## the left edge for the next span but draws nothing itself.
func _test_gap_keyframes_produce_no_span() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE1: [
			_channel(0, [[0, 0], [10, 2], [20, 0], [30, 5]]),  # e2, gap, e5
		],
	})
	var model := Model.build(tl, 0, 0)
	var spans: Array = _lane_for(model, EffectPhaseClass.PHASE1, 0)["spans"]
	_assert_eq(spans.size(), 2, "the id-0 keyframe is a gap, not a span")
	_assert_span(spans[0], 1, 0, 10, "first span before the gap")
	_assert_span(spans[1], 4, 20, 30, "second span picks up after the gap at frame 20")


## for_each keyframe times are phase-local; the model offsets them by
## phase1_duration (first spawn), and phase2 by phase2_start — so every span is
## in the same absolute frame space as the live playhead.
func _test_context_offsets_onto_absolute_timeline() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE_FOR_EACH: [_channel(0, [[0, 0], [5, 1]])],  # e1 over local [0,5)
		EffectPhaseClass.PHASE2: [_channel(0, [[0, 0], [8, 3]])],          # e3 over local [0,8)
	})
	var model := Model.build(tl, 15, 40)
	var fe := _lane_for(model, EffectPhaseClass.PHASE_FOR_EACH, 0)
	_assert_span(fe["spans"][0], 0, 15, 20, "for_each offset by phase1_duration=15")
	var p2 := _lane_for(model, EffectPhaseClass.PHASE2, 0)
	_assert_span(p2["spans"][0], 2, 40, 48, "phase2 offset by phase2_start=40")


## A channel that never spawns (all id 0, or no valid keyframes) contributes no
## lane — the strip shows only channels that actually do something.
func _test_silent_channels_excluded() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE1: [
			_channel(0, [[0, 0], [10, 4]]),  # active
			_channel(1, [[0, 0], [10, 0]]),  # all gaps -> excluded
			_channel(2, []),                 # no keyframes -> excluded
		],
	})
	var model := Model.build(tl, 0, 0)
	_assert_eq(model["lanes"].size(), 1, "only the channel that spawns gets a lane")
	_assert_eq(model["lanes"][0]["channel_index"], 0, "the surviving lane is channel 0")


## max_frame is the axis length: the largest span end, but never shorter than
## phase2_start (so an empty-but-late phase2 still shows its region).
func _test_max_frame_spans_score_and_phase2() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE1: [_channel(0, [[0, 0], [12, 1]])],
	})
	_assert_eq(Model.build(tl, 0, 0)["max_frame"], 12, "max_frame is the last span end")
	_assert_eq(Model.build(tl, 5, 40)["max_frame"], 40, "max_frame never shorter than phase2_start")


## Lanes are ordered by phase (phase1 -> for_each -> phase2) then channel_index,
## so the strip reads top-to-bottom in execution order.
func _test_lane_order_is_phase_then_channel() -> void:
	var tl = _timeline({
		EffectPhaseClass.PHASE2: [_channel(0, [[0, 0], [5, 1]])],
		EffectPhaseClass.PHASE1: [
			_channel(2, [[0, 0], [5, 1]]),
			_channel(0, [[0, 0], [5, 1]]),
		],
		EffectPhaseClass.PHASE_FOR_EACH: [_channel(0, [[0, 0], [5, 1]])],
	})
	var model := Model.build(tl, 5, 10)
	var order: Array = []
	for lane in model["lanes"]:
		order.append([lane["context"], lane["channel_index"]])
	_assert_eq(order, [
		[EffectPhaseClass.PHASE1, 0],
		[EffectPhaseClass.PHASE1, 2],
		[EffectPhaseClass.PHASE_FOR_EACH, 0],
		[EffectPhaseClass.PHASE2, 0],
	], "lanes sort by phase order then channel_index")


# --- Builders -------------------------------------------------------------

## Build a TimelineData from {context -> Array[channel-dict]}.
func _timeline(channels_by_context: Dictionary):
	var particle_channels: Array = []
	for ctx in channels_by_context:
		for ch in channels_by_context[ctx]:
			ch["context"] = ctx
			particle_channels.append(ch)
	return TimelineDataClass.from_json({
		"header": {"phase1_duration": 0, "spawn_delay": 0, "phase2_delay": 0},
		"particle_channels": particle_channels,
	})


## A channel dict from (channel_index, [[time, emitter_id], ...]).
func _channel(channel_index: int, keyframes: Array) -> Dictionary:
	var kfs: Array = []
	for kf in keyframes:
		kfs.append({"time": kf[0], "emitter_id": kf[1], "action_flags": 0})
	return {
		"channel_index": channel_index,
		"max_keyframe": maxi(0, keyframes.size() - 1),
		"keyframes": kfs,
	}


# --- Assertions -----------------------------------------------------------

func _lane_for(model: Dictionary, context: String, channel_index: int) -> Dictionary:
	for lane in model["lanes"]:
		if lane["context"] == context and lane["channel_index"] == channel_index:
			return lane
	return {"spans": []}


func _assert_span(span: Dictionary, emitter_index: int, start: int, end: int, label: String) -> void:
	var ok: bool = span.get("emitter_index") == emitter_index \
		and span.get("start") == start and span.get("end") == end
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected em=%d [%d,%d), got em=%s [%s,%s)" % [
			label, emitter_index, start, end,
			str(span.get("emitter_index")), str(span.get("start")), str(span.get("end"))])


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
