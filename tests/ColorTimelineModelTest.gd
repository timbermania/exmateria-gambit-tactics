extends Node
## TDD guard for ColorTimelineModel — the PURE projection that turns an effect's
## COLOR keyframes (screen background + palette tints) into colored timeline lanes,
## the color-family sibling of EffectTimelineModel. It mirrors the block layout the
## runtime actually plays (PaletteSubsystem._each_keyframe / ScreenSubsystem.
## _push_phase_ops): keyframes laid back-to-back by duration_frames from the phase
## offset, only the "active" ones drawn.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ColorTimelineModelTest.tscn

const Model = preload("res://src/debug/ColorTimelineModel.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const ScreenDataClass = ExMateriaEffects.ScreenData
const EffectPhaseClass = ExMateriaEffects.EffectPhase

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_palette_spans_cumulative_with_gaps_and_offset()
	_test_screen_spans_include_last_keyframe_and_skip_fade()
	_test_lane_order_and_silent_channels_excluded()

	print("\n=== ColorTimelineModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColorTimelineModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorTimelineModelTest")
		get_tree().quit(0)


## A palette channel's blocks are its ENABLED keyframes, each spanning its own
## duration_frames, laid end-to-end from the phase offset. Disabled keyframes are
## timing-only gaps, and the last two keyframes are terminators (the PSX stepper's
## 0..max_keyframe-2 window), so they never draw.
func _test_palette_spans_cumulative_with_gaps_and_offset() -> void:
	var palette = _palette({
		EffectPhaseClass.PHASE_FOR_EACH: {
			"affected_units": _pchannel(4, [
				# [dur, enabled, r, g, b]
				[10, true, 255, 0, 0],    # idx0 -> [offset+0, +10) red
				[5, false, 9, 9, 9],      # idx1 -> gap, advances 5
				[8, true, 0, 0, 255],     # idx2 -> [offset+15, +23) blue
				[3, true, 1, 1, 1],       # idx3 -> terminator (max_keyframe-1), dropped
				[3, true, 2, 2, 2],       # idx4 -> terminator (max_keyframe), dropped
			]),
		},
	})
	var model := Model.build(null, palette, 100, 200)  # for_each offset = phase1_duration = 100
	var lane := _lane(model, EffectPhaseClass.PHASE_FOR_EACH, "affected_units")
	_assert_eq(lane["spans"].size(), 2, "two enabled, non-terminator keyframes -> two blocks")
	_assert_span(lane["spans"][0], 100, 110, Color(1, 0, 0), "idx0 red at offset 100 for 10 frames")
	_assert_span(lane["spans"][1], 115, 123, Color(0, 0, 1), "idx2 blue after the 5-frame gap")


## The screen channel draws its TINT keyframes over the WIDER 0..max_keyframe
## window (inclusive — no terminator pair, unlike palette); FADE keyframes are
## timing-only gaps. Block color is the keyframe's start_color.
func _test_screen_spans_include_last_keyframe_and_skip_fade() -> void:
	var screen = _screen({
		EffectPhaseClass.PHASE_FOR_EACH: _schannel(2, [
			# [dur, mode, r, g, b]
			[6, "TINT", 255, 128, 0],   # idx0 -> [offset+0, +6) orange
			[4, "FADE", 9, 9, 9],       # idx1 -> gap, advances 4
			[5, "TINT", 0, 255, 0],     # idx2 == max_keyframe -> still drawn (green)
		]),
	})
	var model := Model.build(screen, null, 50, 100)  # for_each offset = 50
	var lane := _lane(model, EffectPhaseClass.PHASE_FOR_EACH, "screen")
	_assert_eq(lane["spans"].size(), 2, "two TINT keyframes -> two blocks (last kf included)")
	_assert_span(lane["spans"][0], 50, 56, Color(1.0, 128.0 / 255.0, 0.0), "idx0 orange at offset 50")
	_assert_span(lane["spans"][1], 60, 65, Color(0, 1, 0), "idx2 green drawn at the max_keyframe edge")


## Lanes are ordered phase-first (phase1 -> for_each -> phase2), and within a
## phase screen comes before the palette channels (affected_units, caster,
## target). A channel with no visible block contributes no lane.
func _test_lane_order_and_silent_channels_excluded() -> void:
	var screen = _screen({
		EffectPhaseClass.PHASE1: _schannel(1, [[5, "TINT", 10, 20, 30], [1, "FADE", 0, 0, 0]]),
	})
	var palette = _palette({
		EffectPhaseClass.PHASE1: {
			"caster": _pchannel(3, [[5, true, 1, 2, 3], [1, false, 0, 0, 0], [1, false, 0, 0, 0]]),
			"target": _pchannel(3, [[5, false, 0, 0, 0], [1, false, 0, 0, 0], [1, false, 0, 0, 0]]),  # silent
		},
		EffectPhaseClass.PHASE_FOR_EACH: {
			"affected_units": _pchannel(3, [[5, true, 4, 5, 6], [1, false, 0, 0, 0], [1, false, 0, 0, 0]]),
		},
	})
	var model := Model.build(screen, palette, 10, 20)
	var order: Array = []
	for lane in model["lanes"]:
		order.append([lane["context"], lane["channel"]])
	_assert_eq(order, [
		[EffectPhaseClass.PHASE1, "screen"],
		[EffectPhaseClass.PHASE1, "caster"],
		[EffectPhaseClass.PHASE_FOR_EACH, "affected_units"],
	], "phase order, screen before palette, silent 'target' channel dropped")


# --- Builders -------------------------------------------------------------

func _palette(by_context_channel: Dictionary):
	var data := {}
	for ctx in by_context_channel:
		data[ctx] = {}
		for chan in by_context_channel[ctx]:
			var spec: Dictionary = by_context_channel[ctx][chan]
			spec["context"] = ctx
			spec["channel_name"] = chan
			data[ctx][chan] = spec
	return PaletteDataClass.from_json(data)


func _screen(by_context: Dictionary):
	var data := {}
	for ctx in by_context:
		var spec: Dictionary = by_context[ctx]
		spec["context"] = ctx
		data[ctx] = spec
	return ScreenDataClass.from_json(data)


func _schannel(max_keyframe: int, rows: Array) -> Dictionary:
	var kfs: Array = []
	for i in rows.size():
		var r: Array = rows[i]
		kfs.append({
			"index": i, "time_value": 0, "duration_frames": r[0], "mode": r[1],
			"start_r": r[2], "start_g": r[3], "start_b": r[4],
			"end_r": 128, "end_g": 128, "end_b": 128, "blend_mode": 0, "ctrl": 0,
		})
	return {"max_keyframe": max_keyframe, "keyframes": kfs}


func _pchannel(max_keyframe: int, rows: Array) -> Dictionary:
	var kfs: Array = []
	for i in rows.size():
		var r: Array = rows[i]
		kfs.append({
			"index": i, "time_value": 0, "duration_frames": r[0],
			"enabled": r[1], "rgb": [r[2], r[3], r[4]], "blend_mode": 0, "ctrl": 0,
		})
	return {"max_keyframe": max_keyframe, "keyframes": kfs}


# --- Assertions -----------------------------------------------------------

func _lane(model: Dictionary, context: String, channel: String) -> Dictionary:
	for lane in model["lanes"]:
		if lane["context"] == context and lane["channel"] == channel:
			return lane
	return {"spans": []}


func _assert_span(span: Dictionary, start: int, end: int, color: Color, label: String) -> void:
	var col: Color = span.get("color", Color.BLACK)
	var ok: bool = span.get("start") == start and span.get("end") == end \
		and is_equal_approx(col.r, color.r) and is_equal_approx(col.g, color.g) \
		and is_equal_approx(col.b, color.b)
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected [%d,%d) %s, got [%s,%s) %s" % [
			label, start, end, str(color), str(span.get("start")), str(span.get("end")), str(col)])


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
