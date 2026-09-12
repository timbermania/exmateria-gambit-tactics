extends Node
## TDD guard for the Effect Studio's PAGE-DRIVEN bounce transport (ADR-0090). The page
## owns the clock: each tick it steps LoopTransport and seeks the host — the host is
## parked, never free-running. Drives the page's transport seam against a FAKE host that
## records (frame, silent) seeks. Asserts:
##   - playback bounces within the effective loop span (region, else whole score),
##   - the ping-pong REVERSE leg routes through the SILENT seek path (skips sound re-arm),
##   - a Forward-mode wrap (end→start) is NOT silent (a new pass re-arms sound),
##   - Off mode plays once to the stop frame and halts,
##   - Play seeks to the region start when the playhead is outside it.
## Golden seek sequences are hand-computed (independent source of truth).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioTransportTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Transport = preload("res://src/effects/studio/LoopTransport.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


class FakeHost:
	var seeks: Array = []       # [{frame, silent}]
	func studio_seek(frame: int) -> void:
		seeks.append({"frame": frame, "silent": false})
	func studio_seek_silent(frame: int) -> void:
		seeks.append({"frame": frame, "silent": true})
	func studio_set_playing(_playing: bool) -> void:
		pass


func _ready() -> void:
	_test_forward_region_wraps_within_span()
	_test_forward_wrap_is_not_silent()
	_test_pingpong_reverse_leg_is_silent()
	_test_off_mode_plays_once_then_stops()
	_test_play_seeks_to_start_when_outside_region()

	print("\n=== EffectStudioTransportTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTransportTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTransportTest")
		get_tree().quit(0)


func _test_forward_region_wraps_within_span() -> void:
	var p = _page(Transport.MODE_FORWARD, {"start": 10, "end": 14}, 10)
	var frames := _run(p, 7)
	# 10 -> 11,12,13,14 -> wrap to 10 -> 11,12
	_assert_seq(frames, [11, 12, 13, 14, 10, 11, 12], "forward region wraps within [10,14]")


func _test_forward_wrap_is_not_silent() -> void:
	var p = _page(Transport.MODE_FORWARD, {"start": 10, "end": 12}, 10)
	_run(p, 3)
	var seeks = p._host.seeks
	# The wrap (3rd seek, back to start 10) must NOT be silent — a new forward pass re-arms sound.
	_assert_eq(seeks[2]["frame"], 10, "3rd step wraps to start")
	_assert_eq(seeks[2]["silent"], false, "forward wrap re-arms sound (not silent)")
	_assert_eq(seeks[0]["silent"], false, "forward step not silent")


func _test_pingpong_reverse_leg_is_silent() -> void:
	var p = _page(Transport.MODE_PINGPONG, {"start": 10, "end": 13}, 10)
	_run(p, 6)
	var got: Array = []
	for s in p._host.seeks:
		got.append([s["frame"], s["silent"]])
	# forward legs normal, reverse legs silent — each endpoint shown once per pass.
	_assert_seq(got, [[11, false], [12, false], [13, false], [12, true], [11, true], [10, true]],
		"ping-pong: reverse leg silent, forward leg normal")


func _test_off_mode_plays_once_then_stops() -> void:
	# No region → whole score 0..stop_frame (end_frame = 40 here). Off plays forward once.
	var p = _page(Transport.MODE_OFF, {}, 38)
	# Step past the end; transport should halt at 40 and clear _playing.
	_run(p, 5)
	_assert_eq(p._timeline.get_playhead(), 40, "off mode parks at the stop frame")
	_assert_true(not p._playing, "off mode halts at end (not looping)")


func _test_play_seeks_to_start_when_outside_region() -> void:
	var p = _page(Transport.MODE_FORWARD, {"start": 10, "end": 14}, 50)
	p._playing = false
	p._arm_transport()
	_assert_eq(p._timeline.get_playhead(), 10, "Play seeks to region start when outside")
	_assert_eq(p._loop_dir, Transport.DIR_FWD, "Play resets direction to forward")


# --- harness -------------------------------------------------------------

func _page(mode: int, region: Dictionary, playhead: int):
	var p = Page.new()
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	tl.set_playhead(playhead)
	p._timeline = tl
	p._end_frame = 40
	p._host = FakeHost.new()
	p._loop_mode = mode
	p._loop_region = region
	p._loop_dir = Transport.DIR_FWD
	p._playing = true
	return p


## Run `n` transport steps, returning the playhead landed on after each.
func _run(p, n: int) -> Array:
	var frames: Array = []
	for _i in range(n):
		if not p._playing:
			break
		p._transport_step()
		frames.append(p._timeline.get_playhead())
	return frames


func _assert_seq(got: Array, want: Array, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_eq(got, want, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
