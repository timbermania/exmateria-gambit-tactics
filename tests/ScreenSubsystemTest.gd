extends Node
## Tests for ScreenSubsystem — the effect SCREEN channel (background gradient), now on
## the unified ColorStack model (ADR-0067 slice 5b). It mirrors the PSX combat
## background-gradient applier FUN_80090258 @0x80090258, the SAME 11-mode engine as the
## CLUT applier in 8-bit framebuffer space: build_stream folds the map's TOP and BOTTOM
## baselines through one continuous op stream. These tests pin the byte-exact mode-5
## fold (baseline/2 + param, both endpoints), seam continuity (no pop), and the
## overlay's top/bottom corner composition. The 0-255 mode MATH itself lives in
## ColorRecipe (see ColorRecipeTest's 8-bit param_max cases).
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/ScreenSubsystemTest.tscn

const ScreenSubsystem = ExMateriaEffects.ScreenSubsystem
const ScreenData = ExMateriaEffects.ScreenData
const EffectPhase = ExMateriaEffects.EffectPhase
const ScreenEffectOverlayClass = preload("res://addons/exmateria_effects/overlay/ScreenEffectOverlay.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_fold_top_mode5_over_baseline()
	_test_fold_bottom_mode5_over_baseline()
	_test_folded_top_no_pop_across_seam()
	_test_overlay_composes_top_and_bottom_separately()
	_test_luma_screen_fold_is_8bit()
	_test_gradient_keyframe_advances_later_op_offset()
	_test_keyframe_at_max_keyframe_minus_1_dropped()
	_test_gradient_absolute_set_writes()
	_test_gradient_absolute_set_is_uniform_and_baseline_independent()
	_test_gradient_independent_top_bottom_endpoints()
	_test_gradient_ramps_linearly_over_time8()
	_test_gradient_time0_snaps()
	_test_e173_bound_drops_tail_gradient()
	_test_e173_in_window_gradient_blacks_bright_backdrop()
	_test_e173_screen_blend_param_doubled_matches_savestate9()
	_test_redeliver_refolds_a_live_edit_at_the_parked_frame()

	print("\n=== ScreenSubsystemTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScreenSubsystemTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScreenSubsystemTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenSubsystemTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_vec_approx(got: Vector3, want: Vector3, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _ch(v: float) -> int:
	return roundi(v * 255.0)


func _c3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Mark the ScreenEffectOverlay autoload initialized (so the no-camera delivery in a
## bare test scene is a clean no-op) AND clear its layers, so tests don't bleed phantom
## layers into each other via the singleton.
func _reset_overlay() -> void:
	ScreenEffectOverlay._initialized = true
	ScreenEffectOverlay.active_layers.clear()


# --- fixture -----------------------------------------------------------------

## A minimal two-phase screen fixture mirroring E005's authored arc:
##   phase1:   kf0 TINT mode5 param(0,0,0)     -> dims toward baseline/2
##   for_each: kf0 TINT mode5 param(26,31,36)  -> recovers (the "bump")
## (max_keyframe=2 so only kf0 applies in each; a disabled terminator follows.)
func _seam_screen_data() -> ScreenData:
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
		var term = ScreenData.Keyframe.new()  # disabled terminator (ctrl 0 / FADE)
		term.index = 1
		ch.keyframes.append(term)
		sd.channels_by_context[ctx] = ch
	return sd


# --- tests -------------------------------------------------------------------

## After advance(), the subsystem exposes a folded TOP gradient color reproducing PSX
## FUN_80090258 case 5 = baseline_top/2 + param*2 (the screen Blend stepper DOUBLES the
## signed param, `start << 1` — proven live on E173/savestate9). E005 for_each screen kf0 =
## mode5 (26,31,36); TOP (32,64,124) -> (16,32,62) + 2*(26,31,36) = (68,94,134).
func _test_fold_top_mode5_over_baseline() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_seam_screen_data(), Color8(32, 64, 124), Color8(108, 120, 112))
	for f in range(0, 20):  # pump so for_each starts at 0; frame 20 is settled (dur 8)
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(68, 94, 134) / 255.0,
		"top fold = base_top/2 + 2*param (68,94,134)")


## BOTTOM baseline folds the SAME op stream over its OWN baseline (FUN_80090258 runs
## the 2-iteration top/bottom loop with the shared DOUBLED param). BOTTOM (108,120,112)/2 +
## 2*(26,31,36) = (54,60,56) + (52,62,72) = (106,122,128).
func _test_fold_bottom_mode5_over_baseline() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_seam_screen_data(), Color8(32, 64, 124), Color8(108, 120, 112))
	for f in range(0, 20):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.bottom_color), Vector3(106, 122, 128) / 255.0,
		"bottom fold = base_bottom/2 + 2*param (106,122,128)")


## The folded top is continuous across the phase1->for_each seam — phase1's settled dim
## layer holds while for_each kf0 fades in on top, so no pop to baseline. This is the
## same build_stream continuity as the palette; the PSX background gradient shows the
## same smooth dim->recover (living doc §11).
func _test_folded_top_no_pop_across_seam() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_seam_screen_data(), Color8(32, 64, 124), Color8(108, 120, 112))
	var t := {}
	for f in range(0, 16):
		ss.advance(f, EffectPhase.open_phases(f, 8, 124))
		t[f] = _ch(ss.top_color.b)
	_assert_true(t[7] < t[0], "folded top dims in phase1 (t7 %d < t0 %d)" % [t[7], t[0]])
	_assert_true(t[8] < 90, "folded top no seam pop (t8 %d not baseline 124)" % t[8])
	_assert_true(absi(t[8] - t[7]) <= 8, "folded top continuous at seam (|t8-t7| %d)" % absi(t[8] - t[7]))


## The overlay composites a gradient layer's TOP delta onto the top corners (tl,tr) and
## its BOTTOM delta onto the bottom corners (bl,br) — a pure function of default corners
## + layers, testable without a material. This is what makes the folded top/bottom
## reach the screen as a real vertical gradient.
func _test_overlay_composes_top_and_bottom_separately() -> void:
	var layers := [{"top_delta": Color(0.1, 0.0, 0.0), "bottom_delta": Color(0.0, 0.2, 0.0)}]
	var out: Array = ScreenEffectOverlayClass.compose_corners(
		Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3),  # tl, tr
		Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5),  # bl, br
		layers)
	_assert_vec_approx(_c3(out[0]), Vector3(0.4, 0.3, 0.3), "tl = def_tl + top_delta")
	_assert_vec_approx(_c3(out[1]), Vector3(0.4, 0.3, 0.3), "tr = def_tr + top_delta")
	_assert_vec_approx(_c3(out[2]), Vector3(0.5, 0.7, 0.5), "bl = def_bl + bottom_delta")
	_assert_vec_approx(_c3(out[3]), Vector3(0.5, 0.7, 0.5), "br = def_br + bottom_delta")


## Build a for_each channel with `n` enabled TINT keyframes (each dur 8, mode/param
## from `ops` = [[blend_mode,r,g,b], ...]) plus a trailing terminator. max_keyframe is set
## so all n apply (0..max-2 window). Optionally inject a bit-7-clear (Gradient) keyframe
## between ops via `fade_at` — a Gradient is a REAL absolute-set write (to black, its default
## (0,0,0)), NOT an inert spacer, though it still advances the cumulative op offset by its dur.
func _for_each_ops(ops: Array, fade_at: int = -1) -> ScreenData:
	var sd = ScreenData.new()
	var ch = ScreenData.Channel.new()
	ch.context = EffectPhase.PHASE_FOR_EACH
	var idx := 0
	for j in range(ops.size()):
		if j == fade_at:
			var fade = ScreenData.Keyframe.new()
			fade.index = idx; fade.mode = ScreenData.ScreenMode.GRADIENT; fade.duration_frames = 8
			ch.keyframes.append(fade); idx += 1
		var op = ops[j]
		var kf = ScreenData.Keyframe.new()
		kf.index = idx; kf.mode = ScreenData.ScreenMode.BLEND; kf.blend_mode = op[0]
		kf.start_r_raw = op[1]; kf.start_g_raw = op[2]; kf.start_b_raw = op[3]
		kf.duration_frames = 8
		ch.keyframes.append(kf); idx += 1
	var term = ScreenData.Keyframe.new()
	term.index = idx; term.mode = ScreenData.ScreenMode.GRADIENT
	ch.keyframes.append(term)
	ch.max_keyframe = idx + 1  # apply 0..idx-1 (all real ops + any interior FADE)
	sd.channels_by_context[EffectPhase.PHASE_FOR_EACH] = ch
	return sd


## A luma screen op (mode 2 = luma(current)/6 + param) folds in 8-bit space, NOT the
## palette 5-bit CLUT space — regression guard for the fold_packed param_max loss. base
## (255,0,0) -> luma (2*255)/6 = 85 -> (85,85,85). (5-bit would give ~82.)
func _test_luma_screen_fold_is_8bit() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_for_each_ops([[2, 0, 0, 0]]), Color8(255, 0, 0), Color8(255, 0, 0))
	for f in range(0, 20):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(85, 85, 85) / 255.0,
		"luma mode2 folds 8-bit ((2*255)/6=85), not 5-bit")


## A Gradient keyframe between two enabled Blend ops advances the cumulative op offset by
## its FULL duration, so build_stream places the later op EXACTLY dur frames later — AND is
## a real write (blacks the backdrop) while it holds. op1 is mode5 (base-source: base/2 +
## param), so once it rises it reads the ORIGINAL baseline, not the Gradient's black. This
## catches an off-by-N in the `start_frame += dur` Gradient advance, not just total loss.
func _test_gradient_keyframe_advances_later_op_offset() -> void:
	_reset_overlay()
	# op0 mode5 param(0,0,0) [-> base/2 = 100], GRADIENT->black(dur8), op1 mode5 param(40,40,40) [-> 140].
	# no_grad: op1 starts frame 8; with_grad: op1 starts frame 16 (Gradient holds 8-15).
	var with_grad = ScreenSubsystem.new()
	with_grad.initialize(_for_each_ops([[5, 0, 0, 0], [5, 40, 40, 40]], 1), Color8(200, 200, 200), Color8(200, 200, 200))
	var no_grad = ScreenSubsystem.new()
	no_grad.initialize(_for_each_ops([[5, 0, 0, 0], [5, 40, 40, 40]]), Color8(200, 200, 200), Color8(200, 200, 200))
	var wg := {}
	var ng := {}
	for f in range(0, 28):
		with_grad.advance(f, [EffectPhase.PHASE_FOR_EACH])
		no_grad.advance(f, [EffectPhase.PHASE_FOR_EACH])
		wg[f] = _ch(with_grad.top_color.r)
		ng[f] = _ch(no_grad.top_color.r)
	# Frame 16: op1 (start 16) is at elapsed 0 = progress 0, so the backdrop is the Gradient's
	# settled black. Any Gradient advance < 8 would have op1 already rising above black here.
	_assert_true(wg[16] < 5, "Gradient advances the FULL dur: op1 not yet risen at frame 16, backdrop is Gradient black (r=%d)" % wg[16])
	# no_grad's op1 (start 8) is settled by frame 16 (base/2 + 40 = 140).
	_assert_true(ng[16] > 130, "no_grad op1 (start 8) settled by frame 16 (r=%d)" % ng[16])
	# Frame 24: with_grad's op1 (start 16) has settled — it DID start, exactly 8 frames later.
	_assert_true(wg[24] > 130, "with_grad op1 settles by frame 24, proving it started at 16 (r=%d)" % wg[24])


## The screen keyframe window is 0..max_keyframe-2 (dynamically CONFIRMED live on E173:
## SCREEN_KEYFRAME_BLEND_GRADIENT_E173_NIGHTSWORD.md §5/§2.1 — the same guard as the
## palette stepper `index < max_keyframe-1`), NOT the inclusive window the retired screen
## stepper was believed to use. A channel with max_keyframe=1 has an EMPTY apply window
## (0..-1), so an enabled TINT at index 0 is DROPPED and top stays at baseline (200).
## This reverses the earlier wide-bound belief (commit 7ea9ebb33): PSX drops the tail
## Blend too. Fails if the bound reverts to the inclusive mini(size, max_keyframe+1).
func _test_keyframe_at_max_keyframe_minus_1_dropped() -> void:
	_reset_overlay()
	var sd = ScreenData.new()
	var ch = ScreenData.Channel.new()
	ch.context = EffectPhase.PHASE_FOR_EACH
	ch.max_keyframe = 1
	var kf = ScreenData.Keyframe.new()
	kf.index = 0; kf.mode = ScreenData.ScreenMode.BLEND; kf.blend_mode = 5; kf.duration_frames = 8
	kf.start_r_raw = 50; kf.start_g_raw = 50; kf.start_b_raw = 50
	ch.keyframes.append(kf)
	var term = ScreenData.Keyframe.new()
	term.index = 1; term.mode = ScreenData.ScreenMode.GRADIENT
	ch.keyframes.append(term)
	sd.channels_by_context[EffectPhase.PHASE_FOR_EACH] = ch
	var ss = ScreenSubsystem.new()
	ss.initialize(sd, Color8(200, 200, 200), Color8(200, 200, 200))
	for f in range(0, 20):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(200, 200, 200) / 255.0,
		"TINT at max_keyframe-1 is DROPPED (empty 0..-1 window; top stays baseline 200; wide bound would give 150)")


## A for_each channel with a single in-window Gradient (bit-7-clear) keyframe absolute-set
## to (r,g,b) over `dur` frames (time_value = dur/8), plus a terminator. max_keyframe=2 so
## the 0..max-2 window applies exactly the Gradient at index 0.
func _gradient_fixture(r: int, g: int, b: int, dur: int) -> ScreenData:
	var sd = ScreenData.new()
	var ch = ScreenData.Channel.new()
	ch.context = EffectPhase.PHASE_FOR_EACH
	ch.max_keyframe = 2
	var kf = ScreenData.Keyframe.new()
	kf.index = 0; kf.mode = ScreenData.ScreenMode.GRADIENT  # ctrl bit-7 clear = Gradient
	kf.start_r_raw = r; kf.start_g_raw = g; kf.start_b_raw = b
	kf.time_value = int(dur / 8); kf.duration_frames = dur
	ch.keyframes.append(kf)
	var term = ScreenData.Keyframe.new()
	term.index = 1; term.mode = ScreenData.ScreenMode.GRADIENT
	ch.keyframes.append(term)
	sd.channels_by_context[EffectPhase.PHASE_FOR_EACH] = ch
	return sd


## A Gradient (ctrl bit-7 clear) keyframe is a REAL absolute-set write, not a timing-only
## no-op (the refuted "FADE" belief; SCREEN_KEYFRAME_BLEND_GRADIENT_E173_NIGHTSWORD.md §0/§4).
## Gradient -> black over a white baseline drives the backdrop to black (E164 phase1 is the
## shipped case where a Gradient blacks the screen by itself, with no preceding Blend).
func _test_gradient_absolute_set_writes() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_gradient_fixture(0, 0, 0, 8), Color8(255, 255, 255), Color8(255, 255, 255))
	for f in range(0, 12):  # dur 8 -> settled by frame 8
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(0, 0, 0),
		"Gradient (bit-7 clear) is a REAL absolute-set write: top -> black (not dropped)")


## The Gradient is an ABSOLUTE, baseline-INDEPENDENT set: it discards each vertex's own
## baseline (scale 0) and lands BOTH top and bottom on the same target, so a top=white /
## bottom=black gradient collapses to a flat target. This is the uniform (top==bottom) set
## faithful to 100% of shipped in-window Gradients (§1). base_top(255)/base_bottom(0) both
## -> gray(128) = 0.5.
func _test_gradient_absolute_set_is_uniform_and_baseline_independent() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_gradient_fixture(128, 128, 128, 8), Color8(255, 255, 255), Color8(0, 0, 0))
	for f in range(0, 12):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(128, 128, 128) / 255.0,
		"Gradient top set to absolute 128 regardless of white baseline")
	_assert_vec_approx(_c3(ss.bottom_color), Vector3(128, 128, 128) / 255.0,
		"Gradient bottom set to the SAME absolute 128 regardless of black baseline (uniform)")


## A Gradient fixture with INDEPENDENT top (start_r/g/b) and bottom (end_r/g/b) stops set to
## distinct absolute colours, Time = dur/8, plus a terminator (0..max-2 window applies index 0).
func _gradient_fixture_stops(sr: int, sg: int, sb: int, er: int, eg: int, eb: int, dur: int) -> ScreenData:
	var sd = ScreenData.new()
	var ch = ScreenData.Channel.new()
	ch.context = EffectPhase.PHASE_FOR_EACH
	ch.max_keyframe = 2
	var kf = ScreenData.Keyframe.new()
	kf.index = 0; kf.mode = ScreenData.ScreenMode.GRADIENT
	kf.start_r_raw = sr; kf.start_g_raw = sg; kf.start_b_raw = sb
	kf.end_r_raw = er; kf.end_g_raw = eg; kf.end_b_raw = eb
	kf.time_value = int(dur / 8); kf.duration_frames = dur
	ch.keyframes.append(kf)
	var term = ScreenData.Keyframe.new()
	term.index = 1; term.mode = ScreenData.ScreenMode.GRADIENT
	ch.keyframes.append(term)
	sd.channels_by_context[EffectPhase.PHASE_FOR_EACH] = ch
	return sd


## Authoring scope (B): a Gradient with top != bottom sets the two backdrop stops to their OWN
## explicit colours — top folds `start_r/g/b`, bottom folds `end_r/g/b`, INDEPENDENTLY. This is
## the net-new runtime endpoint-split path the studio's two-picker Gradient editor needs; no
## shipped effect uses it (all 32,510 shipped FADEs have start==end), so it is proven only here.
## Snap (Time=0): top -> (200,0,0), bottom -> (0,0,200), regardless of either baseline.
func _test_gradient_independent_top_bottom_endpoints() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_gradient_fixture_stops(200, 0, 0, 0, 0, 200, 1), Color8(255, 255, 255), Color8(64, 64, 64))
	for f in range(0, 4):  # Time=0 snaps by frame 1
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(200, 0, 0) / 255.0,
		"Gradient top folds start_r/g/b independently (200,0,0)")
	_assert_vec_approx(_c3(ss.bottom_color), Vector3(0, 0, 200) / 255.0,
		"Gradient bottom folds end_r/g/b independently (0,0,200), NOT the uniform start")


## The Gradient ramps LINEARLY over Time*8 frames — constant per-frame delta, no easing
## (§3 fact 1: the DDA adds a constant delta each vblank). Gradient white->black, Time=2
## (dur 16): top = 1 - progress, so quarter/half/three-quarter points land proportionally.
func _test_gradient_ramps_linearly_over_time8() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_gradient_fixture(0, 0, 0, 16), Color8(255, 255, 255), Color8(255, 255, 255))
	var t := {}
	for f in range(0, 18):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
		t[f] = ss.top_color.r
	_assert_true(absf(t[4] - 0.75) < 0.01, "linear ramp @ 1/4: top=%.3f want 0.75" % t[4])
	_assert_true(absf(t[8] - 0.50) < 0.01, "linear ramp @ 1/2: top=%.3f want 0.50" % t[8])
	_assert_true(absf(t[12] - 0.25) < 0.01, "linear ramp @ 3/4: top=%.3f want 0.25" % t[12])
	_assert_true(absf(t[16] - 0.00) < 0.01, "linear ramp settled: top=%.3f want 0.00" % t[16])


## A Time=0 Gradient snaps (degenerate 1-frame ramp, the shared maxi(1,dur) convention the
## Blend path also uses): settled by frame 1, not gradually. Gradient white->(64,64,64), Time=0.
func _test_gradient_time0_snaps() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_gradient_fixture(64, 64, 64, 1), Color8(255, 255, 255), Color8(255, 255, 255))
	for f in range(0, 3):
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_vec_approx(_c3(ss.top_color), Vector3(64, 64, 64) / 255.0,
		"Time=0 Gradient snapped to absolute 64 by frame 1")


## Load the SHIPPED E173/screen.json for_each channel — the worked specimen from the
## living doc (max_keyframe=12; idx1/idx2 in-window Gradients, idx11/idx12 out of window).
func _load_e173() -> ScreenData:
	var f := FileAccess.open("res://assets/effects/E173/screen.json", FileAccess.READ)
	return ScreenData.from_json(JSON.parse_string(f.get_as_text()))


## THE strong, discriminating real-data guard for the window bound (§2.1/§5). E173 idx12 is a
## Gradient -> absolute gray (128,128,128); if it were in-window it would OVERRIDE the whole
## backdrop to uniform 0.502 (scale-0 absolute set). Under the real max_keyframe=12 the 0..max-2
## window DROPS idx12 (and idx11), so the settled backdrop is the idx0..10 composition, NOT gray.
## A "wide" copy (max_keyframe bumped to 14) forces idx12 in-window and DOES go gray — proving
## both the drop and that the dropped op is a real (Gradient) write. Uses the seek-friendly fold
## (advance 0 then 6000) since idx12 settles at frame 5395.
func _test_e173_bound_drops_tail_gradient() -> void:
	_reset_overlay()
	var narrow = ScreenSubsystem.new()
	narrow.initialize(_load_e173(), Color8(32, 64, 124), Color8(108, 120, 112))
	narrow.advance(0, [EffectPhase.PHASE_FOR_EACH])
	narrow.advance(6000, [EffectPhase.PHASE_FOR_EACH])

	var wide_sd = _load_e173()
	wide_sd.get_channel(EffectPhase.PHASE_FOR_EACH).max_keyframe = 14
	var wide = ScreenSubsystem.new()
	wide.initialize(wide_sd, Color8(32, 64, 124), Color8(108, 120, 112))
	wide.advance(0, [EffectPhase.PHASE_FOR_EACH])
	wide.advance(6000, [EffectPhase.PHASE_FOR_EACH])

	# Wide: idx12 in-window -> Gradient overrides the backdrop to uniform gray 128/255.
	_assert_vec_approx(_c3(wide.top_color), Vector3(128, 128, 128) / 255.0,
		"wide bound applies idx12 Gradient -> top gray 0.502")
	_assert_vec_approx(_c3(wide.bottom_color), Vector3(128, 128, 128) / 255.0,
		"wide bound applies idx12 Gradient -> bottom gray 0.502 (uniform)")
	# Narrow (real): idx12 DROPPED -> the settled backdrop is NOT that uniform gray.
	var gray := Vector3(128, 128, 128) / 255.0
	_assert_true(_c3(narrow.top_color).distance_to(gray) > 0.1,
		"real max=12 DROPS idx12 Gradient: top %s not gray %s" % [str(narrow.top_color), str(gray)])


## The IN-WINDOW E173 idx1/idx2 Gradients (-> absolute black) are applied as real writes on
## shipped data. Over a BRIGHT baseline (where idx0's mode5 Blend alone only dims to ~0.25,
## not black), by frame 24 the settled idx1 Gradient has forced the backdrop to black — so
## the black is the GRADIENT's doing, not idx0's. If the Gradient were dropped, top would
## sit at idx0's ~0.25. (On PSX idx0's doubled param blacks it too and the Gradients sustain
## it — §3 fact 3; this bright-baseline lens is what makes the write observable in Godot.)
func _test_e173_in_window_gradient_blacks_bright_backdrop() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	ss.initialize(_load_e173(), Color8(255, 255, 255), Color8(255, 255, 255))
	for f in range(0, 25):  # idx1 Gradient (start 8, dur 16) settled by frame 24
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	_assert_true(ss.top_color.r < 0.05 and ss.top_color.g < 0.05 and ss.top_color.b < 0.05,
		"E173 in-window idx1 Gradient blacks the bright backdrop by frame 24 (top=%s)" % str(ss.top_color))


## BYTE-EXACT live oracle — E173 in savestate9 (PSX effect editor), captured 2026-07-14.
## The screen Blend applier DOUBLES the signed start byte (`r = (i8)start << 1`), dynamically
## PROVEN: for_each idx8 `start_r=192` (=-64) fires the setter with param -128 = -64*2
## (SCREEN_KEYFRAME_BLEND_GRADIENT_E173_NIGHTSWORD.md §2). Folding E173's for_each over the
## live PSX background base gradient (read from the gradient block's packed base @0x800a1b48:
## top=(48,56,48), bottom=(48,56,96)) reproduces the captured working block
## (DAT_800a1b18/1b30): at the idx7 ramp (frame 53) TOP=(167,96,~) BOT=(167,96,116). R and G
## match byte-exact and the BOTTOM matches byte-exact; the subtle blue top/bottom split
## (bottom bluer) comes entirely from the base (the shared param is channel-equal). WITHOUT
## the doubling the fold peaks at R=111 (=48+63, half strength) — the "flat/dim red" bug.
func _test_e173_screen_blend_param_doubled_matches_savestate9() -> void:
	_reset_overlay()
	var ss = ScreenSubsystem.new()
	# PSX map background base gradient (packed-byte base the applier reads, live @0x800a1b48).
	ss.initialize(_load_e173(), Color8(48, 56, 48), Color8(48, 56, 96))
	for f in range(0, 54):  # for_each idx7 (frames 51..58); frame 53 == the capture instant
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	# R and G are byte-exact vs the live block; the bottom is byte-exact end to end.
	_assert_true(_ch(ss.top_color.r) == 167 and _ch(ss.top_color.g) == 96,
		"E173 f53 TOP R,G byte-exact vs PSX (167,96): got (%d,%d) [undoubled bug gives R=108..111]"
			% [_ch(ss.top_color.r), _ch(ss.top_color.g)])
	_assert_vec_approx(_c3(ss.bottom_color), Vector3(167, 96, 116) / 255.0,
		"E173 f53 BOTTOM byte-exact vs PSX savestate9 block (167,96,116)")
	# The gradient shape: bottom is bluer than top (the base's blue split, preserved through Blend).
	_assert_true(ss.bottom_color.b > ss.top_color.b + 0.1,
		"E173 background is a real vertical gradient: bottom bluer than top (bot.b=%.2f top.b=%.2f)"
			% [ss.bottom_color.b, ss.top_color.b])


## Authoring re-fold (#255 slice 6): screen colour is read-live, but the once-per-frame
## guard HOLDS the folded output between ticks, so a live-keyframe edit while the preview
## is PARKED won't reach the overlay on a same-frame advance. `redeliver()` re-folds in
## place from the current (mutated) keyframes at the parked frame — the read-live repaint
## with NO reset + re-pump (ADR-0070). Proven end-to-end headful in tools/verify_screen_color_edit.gd.
func _test_redeliver_refolds_a_live_edit_at_the_parked_frame() -> void:
	_reset_overlay()
	var sd := _seam_screen_data()
	var ss = ScreenSubsystem.new()
	ss.initialize(sd, Color8(32, 64, 124), Color8(108, 120, 112))
	for f in range(0, 20):  # settle at frame 19 (for_each kf0 done, dur 8)
		ss.advance(f, [EffectPhase.PHASE_FOR_EACH])
	var before: Color = ss.top_color

	# Mutate the live for_each kf0 param exactly as the choke point does — no clock advance.
	var kf = sd.get_channel(EffectPhase.PHASE_FOR_EACH).get_keyframe(0)
	kf.start_r_raw = 255; kf.start_g_raw = 0; kf.start_b_raw = 0

	ss.advance(19, [EffectPhase.PHASE_FOR_EACH])   # same-frame advance = once-per-frame no-op
	_assert_true(ss.top_color.is_equal_approx(before),
		"the once-per-frame guard holds the folded output on a same-frame advance")

	ss.redeliver()
	_assert_true(not ss.top_color.is_equal_approx(before),
		"redeliver re-folds the live edit at the parked frame (read-live, no re-pump)")
