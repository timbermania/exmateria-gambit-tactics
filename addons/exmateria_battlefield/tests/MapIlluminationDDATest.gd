extends Node
## Tests for MapIlluminationDDA — the 8-bit ADDITIVE map-illumination applier
## (FUN_80090dec @0x80090DEC), the THIRD colour sink Godot was missing (Holy/E015).
## Distinct from the 5-bit CLUT ColorStack: a single global RGB in 8-bit space,
## additive with neutral 0, ramped over map_ramp(time) = Time×8 (fast, NOT the CLUT's
## fixed-8) / 32·(Time»2) (slow). Root cause of the "clicking" the map showed in Godot.
## Oracle = the RE-captured curve (living doc MAP_ILLUMINATION_APPLIER_HOLY_E015.md §2/§4/§5).
##
## Run: bash tests/stranger/exmateria_battlefield/run.sh   (ADR-0194 — this test
## is addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . --quit-after 5 res://addons/exmateria_battlefield/tests/MapIlluminationDDATest.tscn)

const DDA = preload("res://addons/exmateria_battlefield/texturing/MapIlluminationDDA.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_mode4_folds_base_plus_param_times8()
	_test_empty_is_neutral_zero()
	_test_mode5_idle_settles_0_8_8()
	_test_negative_dim_clamps_to_zero()
	_test_map_ramp_differs_from_clut_at_time2()
	_test_ramp_is_linear_over_time_times8()
	_test_time0_snaps_instantly()
	_test_mode0_reads_running_current()
	_test_mode8_restore_ramps_back_to_base()
	_test_mode10_holds_current()
	_test_luma_mode6_reads_base()
	_test_e015_channel_reproduces_captured_curve()

	print("\n=== MapIlluminationDDATest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] MapIlluminationDDATest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] MapIlluminationDDATest")
		get_tree().quit(1)
	else:
		print("[PASS] MapIlluminationDDATest")
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


## An 8-bit output colour (0..255) normalized to the [0,1] uniform space.
func _c8(r: float, g: float, b: float) -> Vector3:
	return Vector3(r, g, b) / 255.0


# --- tests -------------------------------------------------------------------

## Tracer bullet: one mode-4 op (base + param) with the near-white flood params
## (31,31,31). The map applier rescales the 5-bit param ×8 (R<<3 at the call site),
## so 31→248, over the additive base 0 ⇒ the settled colour is 248,248,248 — the
## captured white flood peak (§5), NOT 255 and NOT the 5-bit-quantized 31/31.
func _test_mode4_folds_base_plus_param_times8() -> void:
	var dda = DDA.new()
	dda.push_op(4, 31, 31, 31, 4, 0)  # mode4, δ31, Time4 (32-frame ramp), @frame 0
	_assert_vec_approx(dda.evaluate(32), _c8(248, 248, 248), "mode4 δ31 settles at 248 (param×8, base 0)")


## Neutral: an empty DDA (no effect) outputs 0 — a true additive no-op so non-effect
## maps are untouched (the idle/no-op guard).
func _test_empty_is_neutral_zero() -> void:
	var dda = DDA.new()
	_assert_vec_approx(dda.evaluate(0), Vector3.ZERO, "empty DDA is neutral 0")
	_assert_vec_approx(dda.evaluate(999), Vector3.ZERO, "empty DDA stays neutral 0")


## E015 idle/settled: mode 5 (base/2 + param) with δ(0,1,1) over base 0 ⇒ (0,8,8) —
## the normally-lit-green idle value the live capture holds between beats (§5 f147).
func _test_mode5_idle_settles_0_8_8() -> void:
	var dda = DDA.new()
	dda.push_op(5, 0, 1, 1, 4, 0)  # mode5, δ(0,1,1), Time4
	_assert_vec_approx(dda.evaluate(32), _c8(0, 8, 8), "mode5 δ(0,1,1) settles at (0,8,8) idle")


## A dim (negative param) over the additive base 0 clamps to 0, never wraps — idx0 of
## E015 (mode5, δ(-4,-4,-4)) renders the map at 0, not a huge positive value.
func _test_negative_dim_clamps_to_zero() -> void:
	var dda = DDA.new()
	dda.push_op(5, 252, 252, 252, 2, 0)  # δ = -4 (signed byte 252), base/2 - 32 -> clamp 0
	_assert_vec_approx(dda.evaluate(16), Vector3.ZERO, "negative dim clamps to 0")


## map_ramp is DISTINCT from the CLUT's ramp_frames_for_time at Time 2/3: the CLUT
## fast ramp is a fixed 8, but the map ramps Time×8 = 16 frames for Time 2. This is a
## concrete "clicking" contributor (Godot reused the CLUT clock). At frame 8 (the CLUT
## would be settled) the map is only HALF-way to its target.
func _test_map_ramp_differs_from_clut_at_time2() -> void:
	_assert_true(DDA.map_ramp(2) == 16, "map_ramp(2)==16 (Time×8), not the CLUT fixed-8")
	_assert_true(DDA.map_ramp(1) == 8, "map_ramp(1)==8")
	_assert_true(DDA.map_ramp(0) == 0, "map_ramp(0)==0 (snap)")
	_assert_true(DDA.map_ramp(4) == 32, "map_ramp(4)==32 (slow, matches CLUT here)")
	# Half-way through a Time-2 ramp the value is half the target — proves 16-frame span.
	var dda = DDA.new()
	dda.push_op(4, 10, 10, 10, 2, 0)  # target (80,80,80) over 16 frames
	_assert_vec_approx(dda.evaluate(8), _c8(40, 40, 40), "Time2 map ramp is 16 frames (half at frame 8)")


## The ramp is arithmetic-LINEAR (constant per-frame step), filling the whole hold —
## no curve table. A Time-4 mode-4 op ramps base→target over 32 frames: 0 at start,
## quarter at 8, half at 16, full at 32 — each step equal.
func _test_ramp_is_linear_over_time_times8() -> void:
	var dda = DDA.new()
	dda.push_op(4, 31, 31, 31, 4, 0)  # (0,0,0) -> (248,248,248) over 32 frames
	_assert_vec_approx(dda.evaluate(0), Vector3.ZERO, "ramp: 0 at start")
	_assert_vec_approx(dda.evaluate(8), _c8(62, 62, 62), "ramp: quarter at frame 8")
	_assert_vec_approx(dda.evaluate(16), _c8(124, 124, 124), "ramp: half at frame 16")
	_assert_vec_approx(dda.evaluate(32), _c8(248, 248, 248), "ramp: full at frame 32")


## Time=0 is an instant snap (0-frame ramp): the target is reached at its start_frame,
## not before. This is the idx8-17 "flicker" — faithful discrete jumps (§5).
func _test_time0_snaps_instantly() -> void:
	var dda = DDA.new()
	dda.push_op(4, 15, 20, 20, 0, 10)  # snap to (120,160,160) at frame 10
	_assert_vec_approx(dda.evaluate(9), Vector3.ZERO, "snap inactive before its start_frame")
	_assert_vec_approx(dda.evaluate(10), _c8(120, 160, 160), "snap reaches target exactly at start_frame")


## Mode 0 reads the RUNNING current (not base), so a second mode-0 op adds onto the
## first's settled value — the chaining the DDA carries between ops. +40R then +40R
## folds to +80R.
func _test_mode0_reads_running_current() -> void:
	var dda = DDA.new()
	dda.push_op(0, 5, 0, 0, 0, 0)   # current 0 + 40 -> 40 (snap @0)
	dda.push_op(0, 5, 0, 0, 0, 1)   # current 40 + 40 -> 80 (snap @1)
	_assert_vec_approx(dda.evaluate(1), _c8(80, 0, 0), "mode0 chains onto running current")


## Mode 8 (restore) ramps the running current back to the additive base (0) over
## map_ramp(time) — the timed release at the end of the effect (idx21), not an instant
## snap. Full value at the restore start, base by the end.
func _test_mode8_restore_ramps_back_to_base() -> void:
	var dda = DDA.new()
	dda.push_op(4, 31, 31, 31, 0, 0)   # snap to 248 at frame 0
	dda.push_op(8, 0, 0, 0, 4, 2)      # restore to base 0 over 32 frames from frame 2
	_assert_vec_approx(dda.evaluate(2), _c8(248, 248, 248), "restore starts from the held value")
	_assert_vec_approx(dda.evaluate(18), _c8(124, 124, 124), "restore half-way back to base")
	_assert_vec_approx(dda.evaluate(34), Vector3.ZERO, "restore fully released to base 0")


## Mode 10 (stop) freezes the current value — the stepper deactivates, holding
## wherever it was; a later op can re-arm from there.
func _test_mode10_holds_current() -> void:
	var dda = DDA.new()
	dda.push_op(4, 10, 10, 10, 0, 0)   # snap to 80 at frame 0
	dda.push_op(10, 0, 0, 0, 0, 1)     # stop at frame 1
	_assert_vec_approx(dda.evaluate(5), _c8(80, 80, 80), "mode10 holds the current value")


## Luma mode 6 reads the BASE luminance (not current). Over base 0 the luma of 0 is 0,
## plus the ×8 delta — a sanity check the luma path is wired in 8-bit space (param_max
## 255), reusing ColorRecipe.luma_out. δ(2,1,0)×8 = (16,8,0) added to L(base=0)=0.
func _test_luma_mode6_reads_base() -> void:
	var dda = DDA.new()
	dda.push_op(6, 2, 1, 0, 0, 0)  # luma from base 0, +(16,8,0)
	_assert_vec_approx(dda.evaluate(0), _c8(16, 8, 0), "luma mode6 over base 0 = delta×8")


## Integration oracle: the E015 authored map channel (§4) reproduces the captured
## curve (§5) — the near-white flood peak 248, the idle 0,8,8, and a clean linear
## brighten to the peak. Built with the §4 keyframes (mode/δ/Time/hold) at their
## cumulative start frames; asserts the SHAPE (peak, idle, monotone brighten to flood),
## which is offset-invariant to the capture's absolute frame numbering.
func _test_e015_channel_reproduces_captured_curve() -> void:
	# §4 rows 0..7 (the brighten arc up to the flood + hold + decay start).
	# {mode, r, g, b, time, hold}
	var rows := [
		[5, 252, 252, 252, 2, 16],   # idx0 dim -> 0
		[5, 0, 1, 1, 4, 32],         # idx1 -> 0,8,8
		[5, 3, 4, 4, 2, 16],         # idx2 -> 24,32,32
		[4, 5, 6, 6, 2, 16],         # idx3 -> 40,48,48
		[4, 31, 31, 31, 4, 32],      # idx4 -> 248 (flood, 32-frame linear)
		[4, 31, 31, 31, 1, 8],       # idx5 hold 248
		[4, 10, 10, 10, 1, 8],       # idx6 -> 80
		[5, 0, 1, 1, 1, 8],          # idx7 -> 0,8,8
	]
	var dda = DDA.new()
	var start := 0
	var starts := []
	for row in rows:
		starts.append(start)
		dda.push_op(row[0], row[1], row[2], row[3], row[4], start)
		start += row[5]
	# idx1 settles at (0,8,8) idle (evaluate at its hold end = idx2 start).
	_assert_vec_approx(dda.evaluate(starts[2]), _c8(0, 8, 8), "curve: idx1 idle settles (0,8,8)")
	# idx4 flood settles at the peak 248,248,248 (evaluate at idx5 start).
	_assert_vec_approx(dda.evaluate(starts[5]), _c8(248, 248, 248), "curve: idx4 flood peak 248")
	# idx5 holds the peak through its whole span.
	_assert_vec_approx(dda.evaluate(starts[6]), _c8(248, 248, 248), "curve: idx5 holds 248")
	# The idx4 brighten is monotone non-decreasing frame to frame (no click/dip).
	var prev := dda.evaluate(starts[4])
	var monotone := true
	for f in range(starts[4], starts[5] + 1):
		var cur: Vector3 = dda.evaluate(f)
		if cur.y < prev.y - 0.0005:
			monotone = false
		prev = cur
	_assert_true(monotone, "curve: idx4 flood brighten is monotone (no clicking)")
	# idx7 settles back to idle (0,8,8).
	_assert_vec_approx(dda.evaluate(start), _c8(0, 8, 8), "curve: idx7 returns to idle (0,8,8)")
