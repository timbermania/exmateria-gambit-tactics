extends Node

## SpriteSlideAnimator test — pure GDScript, no GPU.
##
## Guards the Formation "Item → Equip" sprite-slide (FORMATION_SCREEN.md §15.23,
## RE round 22). Unlike VitalsSlideAnimator/BoxOpenAnimator there is NO baked ROM
## keyframe table: the slide is EMERGENT per-frame (the OT/GPU packet buffer is
## rebuilt every frame — there is no persistent per-unit screen-X source variable;
## see tmp/equip_re/FINDINGS_corrected_model.md). So the port models it as an
## accelerating (ease-in) tween over the measured duration, driving each unit
## between caller-supplied endpoints:
##   - non-selected units → settle OFF the right edge (exit); one class enters
##     diagonally from off-screen top;
##   - the selected unit → settles at screen (166,173) (measured from oracle f29:
##     bright pixels x[157..174] y[153..193], center ≈(166,173) = bottom-right
##     quadrant, left side), barely moving.
## No scale: the animator yields only POSITION, never a size (unit quads are 24×40
## in all 30 oracle frames).

const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")


func _ready() -> void:
	var failed := false

	# 1. Pinned RE constants (independent source of truth = the oracle measurement,
	#    NOT recomputed from the code): the selected unit's settle point and the
	#    slide duration in logical frames (measured f6..f20).
	if SpriteSlideAnimator.SETTLE_PX != Vector2(166, 173):
		print("[FAIL] SETTLE_PX = %s, expected (166, 173)" % [SpriteSlideAnimator.SETTLE_PX])
		failed = true
	if SpriteSlideAnimator.SLIDE_DURATION != 16:
		print("[FAIL] SLIDE_DURATION = %d, expected 16" % SpriteSlideAnimator.SLIDE_DURATION)
		failed = true

	var start := Vector2(150.0, 173.0)
	var settle := Vector2(300.0, 173.0)   # a rightward exit endpoint
	var dur := SpriteSlideAnimator.SLIDE_DURATION

	# 2. Endpoints: frame 0 is exactly the start, frame == duration is exactly the settle.
	if SpriteSlideAnimator.position_at_frame(start, settle, 0, dur) != start:
		print("[FAIL] frame 0 != start (%s)" % [SpriteSlideAnimator.position_at_frame(start, settle, 0, dur)])
		failed = true
	if SpriteSlideAnimator.position_at_frame(start, settle, dur, dur) != settle:
		print("[FAIL] frame dur != settle (%s)" % [SpriteSlideAnimator.position_at_frame(start, settle, dur, dur)])
		failed = true

	# 3. Clamp: negative frame holds at start; past duration holds at settle (no overshoot).
	if SpriteSlideAnimator.position_at_frame(start, settle, -5, dur) != start:
		print("[FAIL] negative frame did not clamp to start")
		failed = true
	if SpriteSlideAnimator.position_at_frame(start, settle, dur + 9, dur) != settle:
		print("[FAIL] past-duration frame did not hold at settle")
		failed = true

	# 4. Ease-IN (accelerating, §15.23 measured Δ grows 1→8 px/f): at the midpoint the
	#    slide has covered STRICTLY LESS than half the distance. Linear would be exactly
	#    half; ease-out would be more than half — so this asserts the accelerating shape.
	var mid := SpriteSlideAnimator.position_at_frame(start, settle, dur / 2, dur)
	var covered := mid.x - start.x
	var total := settle.x - start.x
	if covered >= total * 0.5:
		print("[FAIL] not ease-in: midpoint covered %.1f of %.1f (>= half)" % [covered, total])
		failed = true
	if covered <= 0.0:
		print("[FAIL] midpoint made no progress")
		failed = true

	# 5. Monotonic: for a rightward slide, x is non-decreasing every frame (no jitter).
	var prev_x := start.x
	for n in range(0, dur + 1):
		var x := SpriteSlideAnimator.position_at_frame(start, settle, n, dur).x
		if x < prev_x - 0.001:
			print("[FAIL] non-monotonic at frame %d: %.2f < %.2f" % [n, x, prev_x])
			failed = true
			break
		prev_x = x

	# 6. No vertical drift when start.y == settle.y (the horizontal-exit class keeps y).
	if not is_equal_approx(SpriteSlideAnimator.position_at_frame(start, settle, dur / 2, dur).y, 173.0):
		print("[FAIL] y drifted for a same-y slide")
		failed = true

	# 7. settle_frame is the first fully-settled frame (== duration) and NOT one earlier.
	if SpriteSlideAnimator.settle_frame(dur) != dur:
		print("[FAIL] settle_frame(%d) = %d, expected %d" % [dur, SpriteSlideAnimator.settle_frame(dur), dur])
		failed = true
	if SpriteSlideAnimator.position_at_frame(start, settle, dur - 1, dur) == settle:
		print("[FAIL] settled one frame too early (frame %d already at settle)" % (dur - 1))
		failed = true

	if failed:
		print("[FAIL] SpriteSlideAnimator test")
	else:
		print("[PASS] SpriteSlideAnimator: §15.23 ease-in slide, endpoints/clamp/settle + (166,173)")
	get_tree().quit()
