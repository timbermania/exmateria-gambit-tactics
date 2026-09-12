extends Node

## BoxOpenAnimator test — pure GDScript, no GPU.
##
## Guards the unit-detail/Status-screen box-open animation (FORMATION_SCREEN.md
## §15.17): the shared FFT world-menu center-out scale. Pins the byte-exact easing
## table and the ROM-integer scale math against the two live-confirmed snapshots
## (settled p=100 and the mid-open p=60 grab from ss3).

const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")

# The live-measured full container rect (display space, §15.17).
const FULL := Rect2i(4, 126, 250, 108)


func _ready() -> void:
	var failed := false

	# 1. The easing table is the byte-exact WORLD 0x801533b8 curve.
	var expect_curve := [10, 10, 60, 60, 90, 90, 95, 95, 100, 100, 100, 100]
	if Array(BoxOpenAnimator.OPEN_CURVE) != expect_curve:
		print("[FAIL] OPEN_CURVE = %s, expected %s" % [BoxOpenAnimator.OPEN_CURVE, expect_curve])
		failed = true

	# 2. Normal-speed progression walks the curve one index per frame and clamps
	#    to 100 forever past index 11.
	var got_normal: Array[int] = []
	for n in 14:
		got_normal.append(BoxOpenAnimator.progress_percent(n, false))
	var expect_normal := [10, 10, 60, 60, 90, 90, 95, 95, 100, 100, 100, 100, 100, 100]
	if got_normal != expect_normal:
		print("[FAIL] normal progression = %s" % str(got_normal))
		failed = true

	# 3. Fast progression (DAT_8015326c==2) doubles the step: 10,60,90,95,100.
	var got_fast: Array[int] = []
	for n in 6:
		got_fast.append(BoxOpenAnimator.progress_percent(n, true))
	if got_fast != [10, 60, 90, 95, 100, 100]:
		print("[FAIL] fast progression = %s, expected [10,60,90,95,100,100]" % str(got_fast))
		failed = true

	# 4. Settle: p first reaches 100 at frame 8 (normal) / 4 (fast).
	if BoxOpenAnimator.progress_percent(BoxOpenAnimator.settle_frame(false), false) != 100:
		print("[FAIL] normal settle frame is not 100%%")
		failed = true
	if BoxOpenAnimator.progress_percent(BoxOpenAnimator.settle_frame(false) - 1, false) == 100:
		print("[FAIL] normal settled one frame too early")
		failed = true
	if BoxOpenAnimator.progress_percent(BoxOpenAnimator.settle_frame(true), true) != 100:
		print("[FAIL] fast settle frame is not 100%%")
		failed = true

	# 5. p=100 => the full rect, unchanged (settled ss4 output).
	if BoxOpenAnimator.scaled_rect(FULL, 100) != FULL:
		print("[FAIL] p=100 rect = %s, expected %s" % [BoxOpenAnimator.scaled_rect(FULL, 100), FULL])
		failed = true

	# 6. p=60 => the LIVE-CONFIRMED mid-open prim {54,148,150,64} (ss3, §15.17):
	#    center-out on both axes, ROM-integer.
	var mid := BoxOpenAnimator.scaled_rect(FULL, 60)
	if mid != Rect2i(54, 148, 150, 64):
		print("[FAIL] p=60 rect = %s, expected (54,148,150,64) — the ss3 live grab" % str(mid))
		failed = true
	# 6b. and it's reachable from the curve: 60 == OPEN_CURVE[2].
	if BoxOpenAnimator.rect_at_frame(FULL, 2, false) != Rect2i(54, 148, 150, 64):
		print("[FAIL] frame-2 rect != p=60 rect")
		failed = true

	# 7. p=0 => a zero-size point at the container centre (129,180).
	var pt := BoxOpenAnimator.scaled_rect(FULL, 0)
	if pt.size != Vector2i.ZERO or pt.position != Vector2i(129, 180):
		print("[FAIL] p=0 rect = %s, expected zero-size at (129,180)" % str(pt))
		failed = true

	if failed:
		print("[FAIL] BoxOpenAnimator test")
	else:
		print("[PASS] BoxOpenAnimator: §15.17 curve + center-out scale (p=60 -> {54,148,150,64})")
	get_tree().quit()
