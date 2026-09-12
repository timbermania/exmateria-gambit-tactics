extends Node
## TDD guard: the Effect Studio playhead value = the frame currently RENDERED (last-folded),
## NOT the `effect_frame` clock (which is one AHEAD — it counts frames elapsed / the next frame
## to process). Authoring intent: "park the playhead at the END of this span → pick a colour →
## SEE that colour." Before this fix, parking the displayed playhead at a span's end frame folded
## one frame short, so the authored colour only appeared one frame past the span (into the next
## event instruction) — see /tmp handoff + tools/probe_e317_gradient_timing.gd.
##
## The fix is contained to the studio HOST choke point (EffectViewerScene): studio_seek(D) folds
## the effect so its last-rendered frame == D (seek(D+1), with D<=0 preserved as the reset/Stop
## state seek(0)); studio_current_frame() reports the rendered frame (effect_frame - 1). The
## deterministic effect_frame clock (spawns, sound, ADR-0070 seek) is UNTOUCHED — only the studio
## display mapping changes. This test observes the REAL host against a LIVE effect (top_color is
## the folded backdrop the user sees), the same seam tools/probe_e317_gradient_timing exercised.
##
## Run: <GODOT> --path . --quit-after 340 res://tests/EffectStudioPlayheadDisplayTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const ScreenData = ExMateriaEffects.ScreenData

var _passed: int = 0
var _failed: int = 0
var _host = null
var _sc = null
var _phase := ""
var _idx := -1
var _span_start := 0
var _span_end := 0


func _ready() -> void:
	await _setup()
	if _host == null:
		_finish()
		return
	await _test_parking_playhead_at_span_end_shows_the_authored_colour()
	await _test_current_frame_round_trips_the_displayed_playhead()
	await _test_frame_zero_preserves_the_reset_state()

	_finish()


func _finish() -> void:
	print("\n=== EffectStudioPlayheadDisplayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioPlayheadDisplayTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioPlayheadDisplayTest")
		get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Spawn the real Effect Studio host on E317, take its screen:for_each kf#0 Gradient span,
## and author BOTH stops black — the shared fixture every slice parks against.
func _setup() -> void:
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	_host = scn
	await _frames(30)
	_host.studio_select_effect(317)
	await _frames(25)

	var eff = _host._current_effect
	if eff == null or not is_instance_valid(eff) or eff.screen_controller == null:
		_assert_true(false, "live E317 effect + screen_controller present")
		_host = null
		return
	_sc = eff.screen_controller

	var score := Model.build(eff.effect_data)
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "screen":
			continue
		for sp in lane.get("spans", []):
			if String(sp.get("phase", "")) == "for_each" and int(sp.get("keyframe_index", -1)) == 0:
				_phase = sp.get("phase", "")
				_idx = int(sp.get("keyframe_index", -1))
				_span_start = int(sp.get("start", 0))
				_span_end = int(sp.get("end", 0))
	if _idx < 0:
		_assert_true(false, "E317 has a screen:for_each kf#0 span")
		_host = null
		return
	_assert_eq(_span_end - _span_start, 8, "E317 screen:for_each kf#0 span is dur-8 (span=[%d,%d])" % [_span_start, _span_end])

	# Flip Kind -> Gradient and author BOTH stops black (the user's edit).
	_host.studio_apply_edit({"channel": "screen", "context": _phase, "event_index": _idx, "field": "kind"},
		ScreenData.ScreenMode.GRADIENT)
	await _frames(6)
	for which in ["start", "end"]:
		for chn in ["r", "g", "b"]:
			_host.studio_apply_edit({"channel": "screen", "context": _phase, "event_index": _idx, "field": which + "_" + chn}, 0)
	await _frames(6)


# --- Slice 1: displayed playhead at the span END renders the authored colour ----

## Parking the studio playhead at the span's END frame (16) must fold the backdrop to the
## authored black — the ramp settles at start+dur, and the displayed playhead now maps to the
## last-RENDERED frame, so what you park on is what you see.
func _test_parking_playhead_at_span_end_shows_the_authored_colour() -> void:
	_host.studio_seek(_span_end)
	_host.studio_set_playing(false)
	await _frames(4)
	var top: Color = _sc.top_color
	var lum := maxf(top.r, maxf(top.g, top.b))
	_assert_true(lum < 0.01,
		"playhead parked at span end %d shows the authored BLACK (top=%s lum=%.3f)" % [_span_end, _s(top), lum])


# --- Slice 2: studio_current_frame round-trips the displayed playhead -------

## After parking at displayed frame D, studio_current_frame() reports D (not the clock's D+1).
## This is what the page draws the playhead line at and mirrors during playback, so the readout
## and the line sit on the rendered frame. Checked at the span end and a mid-span frame.
func _test_current_frame_round_trips_the_displayed_playhead() -> void:
	for d in [_span_start, _span_start + 3, _span_end]:
		_host.studio_seek(d)
		_host.studio_set_playing(false)
		await _frames(4)
		_assert_eq(_host.studio_current_frame(), d,
			"studio_seek(%d) round-trips: studio_current_frame() == %d" % [d, d])


# --- Slice 3: frame 0 preserves the reset/Stop state ------------------------

## studio_seek(0) must leave the timeline clock at effect_frame==0 — the reset state the
## per-frame camera reconcile keys on to hand the camera back to the tile cursor (studio_stop).
## Mapping 0->seek(1) would break that. A frame > 0, by contrast, leaves effect_frame > 0
## (effect keeps the camera), one PAST the displayed frame.
func _test_frame_zero_preserves_the_reset_state() -> void:
	_host.studio_seek(0)
	_host.studio_set_playing(false)
	await _frames(4)
	_assert_eq(_host._current_effect.get_effect_frame(), 0,
		"studio_seek(0) keeps effect_frame==0 (reset/camera-handback state)")

	_host.studio_seek(_span_end)
	await _frames(4)
	_assert_eq(_host._current_effect.get_effect_frame(), _span_end + 1,
		"studio_seek(%d) leaves the clock one PAST the displayed frame (effect_frame==%d)" % [_span_end, _span_end + 1])


# --- helpers --------------------------------------------------------------

func _s(c: Color) -> String:
	return "(%.3f,%.3f,%.3f)" % [c.r, c.g, c.b]


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [ok] %s" % msg)
	else:
		_failed += 1
		print("  [XX] %s" % msg)


func _assert_eq(got, want, msg: String) -> void:
	_assert_true(got == want, "%s (got %s want %s)" % [msg, str(got), str(want)])
