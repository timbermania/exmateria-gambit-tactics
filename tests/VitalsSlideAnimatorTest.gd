extends Node

## VitalsSlideAnimator test — pure GDScript, no GPU.
##
## Guards the Formation → Status(detail) ○-press SLIDE animation
## (FORMATION_SCREEN.md §15.1, §15.5, §15.9): the vitals-bar + nameplate group
## rises bottom→top 144 px by replaying a BAKED keyframe table (NOT a float tween).
## Pins the byte-exact keyframe table (RAM 0x8018ABD6 / WORLD.BIN file 0xAABD6,
## descending half {144,139,67,31,13,4,0}) and the one-index-per-frame walk +
## settle, exactly as BoxOpenAnimator guards the box-open curve.

const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")


func _ready() -> void:
	var failed := false

	# 1. The keyframe table is the byte-exact descending half of the WORLD bell
	#    (0x8018ABD6, indices 10-16): the source-Y OFFSET above the settled top.
	var expect_curve := [144, 139, 67, 31, 13, 4, 0]
	if Array(VitalsSlideAnimator.SLIDE_CURVE) != expect_curve:
		print("[FAIL] SLIDE_CURVE = %s, expected %s" % [VitalsSlideAnimator.SLIDE_CURVE, expect_curve])
		failed = true

	# 2. offset_at_frame walks the table one index per frame and clamps to 0 (settled)
	#    forever past the last index — the discrete, table-driven replay (§15.9).
	var got: Array[int] = []
	for n in 10:
		got.append(VitalsSlideAnimator.offset_at_frame(n))
	var expect_walk := [144, 139, 67, 31, 13, 4, 0, 0, 0, 0]
	if got != expect_walk:
		print("[FAIL] offset walk = %s, expected %s" % [str(got), str(expect_walk)])
		failed = true

	# 3. Frame 0 is the full 144 px offset (docked at the formation bottom).
	if VitalsSlideAnimator.offset_at_frame(0) != 144:
		print("[FAIL] frame 0 offset = %d, expected 144 (docked)" % VitalsSlideAnimator.offset_at_frame(0))
		failed = true

	# 4. Negative frames clamp to the docked start (144), not out of bounds.
	if VitalsSlideAnimator.offset_at_frame(-3) != 144:
		print("[FAIL] negative frame did not clamp to 144")
		failed = true

	# 5. Settle: offset first reaches 0 at settle_frame(), and NOT one frame earlier.
	var sf := VitalsSlideAnimator.settle_frame()
	if VitalsSlideAnimator.offset_at_frame(sf) != 0:
		print("[FAIL] settle_frame %d offset != 0" % sf)
		failed = true
	if VitalsSlideAnimator.offset_at_frame(sf - 1) == 0:
		print("[FAIL] settled one frame too early (frame %d already 0)" % (sf - 1))
		failed = true

	if failed:
		print("[FAIL] VitalsSlideAnimator test")
	else:
		print("[PASS] VitalsSlideAnimator: §15.1 keyframe table {144..0} + settle")
	get_tree().quit()
