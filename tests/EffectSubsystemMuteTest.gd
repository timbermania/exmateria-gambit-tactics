extends Node
## TDD guard for per-LANE mute of the folded subsystems (Effect Studio Solo/Mute).
## Muting a lane excludes ONLY that lane's events from the subsystem's on-the-fly
## recompile — no whole-subsystem gate — so a single M button works and a rescrub
## re-derives without it. Covers:
##   - SCREEN: set_muted({phase}) drops that phase's ops from build_stream, so the folded
##     backdrop returns toward the map baseline; muting the active phase ⇒ baseline.
##     set_muted re-folds the current frame immediately (parked preview updates in place).
## (Sound mute is per-channel at EffectInstance._on_sound_pair_triggered — an instance
## path, exercised by the wiring guard. Camera is display-only — no mute.)
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectSubsystemMuteTest.tscn

const ScreenSubsystem = ExMateriaEffects.ScreenSubsystem
const ScreenData = ExMateriaEffects.ScreenData
const EffectPhase = ExMateriaEffects.EffectPhase

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	ScreenEffectOverlay._initialized = true   # allow no-camera delivery in a bare tree
	_test_screen_mute_phase_returns_to_baseline()
	_test_screen_mute_re_folds_in_place()

	print("\n=== EffectSubsystemMuteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSubsystemMuteTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSubsystemMuteTest")
		get_tree().quit(0)


## One-channel-per-phase screen data (phase1 + for_each), for_each kf0 = mode5 tint.
func _screen_data() -> ScreenData:
	var sd = ScreenData.new()
	for ctx in [EffectPhase.PHASE1, EffectPhase.PHASE_FOR_EACH]:
		var ch = ScreenData.Channel.new()
		ch.context = ctx
		ch.max_keyframe = 2
		var kf = ScreenData.Keyframe.new()
		kf.index = 0
		kf.mode = ScreenData.ScreenMode.BLEND
		kf.blend_mode = 5
		kf.duration_frames = 8
		if ctx == EffectPhase.PHASE_FOR_EACH:
			kf.start_r_raw = 26; kf.start_g_raw = 31; kf.start_b_raw = 36
		ch.keyframes.append(kf)
		ch.keyframes.append(ScreenData.Keyframe.new())  # disabled terminator
		sd.channels_by_context[ctx] = ch
	return sd


func _settled_screen() -> Variant:
	var ss = ScreenSubsystem.new()
	ss.initialize(_screen_data(), Color8(32, 64, 124), Color8(108, 120, 112))
	for f in range(0, 20):   # for_each kf0 (dur 8) settles well before 20
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	return ss


## Muting the ACTIVE screen phase drops its ops from the fold, so the backdrop returns to
## the map baseline (default TOP), instead of the tinted (68,94,134) settled value.
func _test_screen_mute_phase_returns_to_baseline() -> void:
	var ss = _settled_screen()
	var tinted := _c3(ss.top_color)
	_assert_true(tinted.distance_to(Vector3(32, 64, 124) / 255.0) > 0.05,
		"precondition: the unmuted screen is tinted away from baseline")
	ss.set_muted({EffectPhase.PHASE_FOR_EACH: true})
	_assert_true(_c3(ss.top_color).distance_to(Vector3(32, 64, 124) / 255.0) < 0.01,
		"muting the active screen phase returns the backdrop to the map baseline")


## set_muted re-folds the CURRENT frame immediately (no next tick needed) — so a parked
## preview updates in place. Un-muting restores the tint on the spot.
func _test_screen_mute_re_folds_in_place() -> void:
	var ss = _settled_screen()
	var tinted := _c3(ss.top_color)
	ss.set_muted({EffectPhase.PHASE_FOR_EACH: true})
	var muted := _c3(ss.top_color)
	ss.set_muted({})   # un-mute
	_assert_true(_c3(ss.top_color).distance_to(tinted) < 0.001,
		"un-muting re-folds the tint immediately")
	_assert_true(muted.distance_to(tinted) > 0.05, "muting visibly changed the fold in place")


func _c3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
