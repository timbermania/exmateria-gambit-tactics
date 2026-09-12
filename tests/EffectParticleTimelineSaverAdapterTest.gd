extends Node
## TDD guard for EffectParticleTimelineSaver.to_timeline_json (ADR-0089 particle_timeline
## amendment, slice 5) — the game→json shape bridge that feeds the byte-exact Python writer.
## The parser reads FIXED 25-slot channels; the live model is a variable-length array with a
## max_keyframe watermark. The adapter must pad every channel to 25 slots, carry max_keyframe
## verbatim, and serialize emitter_id AS-IS — a disabled span (emitter_id 0) saves as a gap,
## its session-remembered id never written.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectParticleTimelineSaverAdapterTest.tscn

const Saver = preload("res://src/effects/studio/EffectParticleTimelineSaver.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_channels_pad_to_25_slots()
	_test_values_and_watermark_are_carried()
	_test_a_disabled_span_saves_as_a_gap()
	_test_all_15_channels_are_serialized()
	_test_null_timeline_is_refused()

	print("\n=== EffectParticleTimelineSaverAdapterTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectParticleTimelineSaverAdapterTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectParticleTimelineSaverAdapterTest")
		get_tree().quit(0)


## A channel with fewer than 25 live keyframes pads up to 25 (trailing slots zeroed) — the
## writer indexes keyframes[i] for every slot.
func _test_channels_pad_to_25_slots() -> void:
	var tl = _timeline([[[0, 0], [10, 1]]])
	var res: Dictionary = Saver.to_timeline_json(tl)
	_assert_true(res.get("ok", false), "the adapter succeeds")
	var ch: Dictionary = res["json"]["particle_channels"][0]
	_assert_eq(ch["keyframes"].size(), 25, "the channel is padded to 25 slots")
	_assert_eq(int(ch["keyframes"][24]["emitter_id"]), 0, "trailing slots are zeroed")
	_assert_eq(int(ch["keyframes"][24]["time"]), 0, "…time too")


## Live values (time / emitter_id / action_flags) and the max_keyframe watermark survive.
func _test_values_and_watermark_are_carried() -> void:
	var tl = _timeline([[[0, 0], [10, 1], [25, 2]]])
	var ch: Dictionary = Saver.to_timeline_json(tl)["json"]["particle_channels"][0]
	_assert_eq(int(ch["max_keyframe"]), 2, "max_keyframe is carried verbatim")
	_assert_eq(int(ch["keyframes"][1]["time"]), 10, "kf[1].time preserved")
	_assert_eq(int(ch["keyframes"][2]["emitter_id"]), 2, "kf[2].emitter_id preserved")
	_assert_eq(String(ch["context"]), "for_each", "the channel context rides along")
	_assert_eq(int(ch["channel_index"]), 0, "…and the lane index")


## A DISABLED span (emitter_id 0 + a session-remembered id) saves as an ordinary gap:
## emitter_id 0, no remembered id serialized (disable cannot persist).
func _test_a_disabled_span_saves_as_a_gap() -> void:
	var tl = _timeline([[[0, 0], [10, 1]]])
	var kf = tl.get_channels("for_each")[0].keyframes[1]
	kf.emitter_id = 0
	kf.remembered_emitter_id = 1   # session stash — must NOT be written
	var ch: Dictionary = Saver.to_timeline_json(tl)["json"]["particle_channels"][0]
	_assert_eq(int(ch["keyframes"][1]["emitter_id"]), 0, "a disabled span saves as emitter_id 0 (a gap)")
	_assert_true(not ch["keyframes"][1].has("remembered_emitter_id"),
		"the session-remembered id is never serialized")


## The adapter serializes every channel across for_each / phase1 / phase2 (15 total when full).
func _test_all_15_channels_are_serialized() -> void:
	var chans: Array = []
	for _c in range(5):
		chans.append([[0, 0], [10, 1]])
	var tl = _timeline_multi(chans, chans, chans)   # 5 + 5 + 5
	var res: Dictionary = Saver.to_timeline_json(tl)
	_assert_eq(res["json"]["particle_channels"].size(), 15, "all 15 channels serialize")


func _test_null_timeline_is_refused() -> void:
	var res: Dictionary = Saver.to_timeline_json(null)
	_assert_true(not res.get("ok", true), "a null timeline is a reported error, not a crash")


# --- fixtures -------------------------------------------------------------

## One-context timeline from a list of channels, each a list of [time, emitter_id] pairs.
func _timeline(for_each_channels: Array):
	return _timeline_multi(for_each_channels, [], [])


func _timeline_multi(for_each_channels: Array, phase1_channels: Array, phase2_channels: Array):
	var particle_channels: Array = []
	_append_channels(particle_channels, "for_each", for_each_channels)
	_append_channels(particle_channels, "phase1", phase1_channels)
	_append_channels(particle_channels, "phase2", phase2_channels)
	return TimelineDataClass.from_json({
		"header": {"phase1_duration": 0},
		"particle_channels": particle_channels,
	})


func _append_channels(out: Array, context: String, channels: Array) -> void:
	for i in range(channels.size()):
		var kf_dicts: Array = []
		for pair in channels[i]:
			kf_dicts.append({"time": int(pair[0]), "emitter_id": int(pair[1]), "action_flags": 0})
		out.append({"context": context, "channel_index": i,
			"max_keyframe": channels[i].size() - 1, "keyframes": kf_dicts})


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
