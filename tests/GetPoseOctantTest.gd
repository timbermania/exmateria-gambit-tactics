extends Node
## get_pose_octant fixture test (ADR-0053). Asserts the structural invariants
## of the 4-bit pose_octant resolution that the idle dispatcher uses to index
## CinematicPoseLUT.SUB_A_FRAME_BASE. Camera-quad calibration to PSX's
## DAT_800a7786 is a separate verification step (handoff "Fail conditions" —
## the per-call chapel probe is the oracle).
##
## Pure GDScript, no scene / RenderingDevice / Unit.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController


func _ready() -> void:
	var failed := false
	# 1. Returns 0..15 for any facing_angle / psx_camera_angle combination.
	for fa in range(0, 0x1000, 0x80):
		for cam in range(0, 0x1000, 0x80):
			var po := AnimationStateController.get_pose_octant(fa, cam)
			if po < 0 or po > 15:
				print("[FAIL] pose_octant out of [0,15] at facing_angle=0x%x, psx_camera_angle=0x%x → %d" % [fa, cam, po])
				failed = true

	# 2. Stepping facing_angle by 0x100 increments pose_octant by 1 (mod 16) at
	#    fixed camera angle. This is the "byte step = octant step" property the
	#    chapel rotate cascade exposes (8 byte-steps = 8 octants = the 1,2,2,3,3,4,4,5
	#    tent walk that produces 5 distinct frame bases).
	for cam in [0x000, 0x400, 0x800, 0xC00]:
		for fa in range(0, 0xF00, 0x100):
			var po_a := AnimationStateController.get_pose_octant(fa, cam)
			var po_b := AnimationStateController.get_pose_octant(fa + 0x100, cam)
			if ((po_a + 1) % 16) != po_b:
				print("[FAIL] byte step does not increment pose_octant at facing_angle=0x%x → 0x%x, psx_camera_angle=0x%x (got %d → %d)" % [
					fa, fa + 0x100, cam, po_a, po_b])
				failed = true

	# 3. Sub-byte facing_angle increments below 0x100 do NOT change pose_octant
	#    (the 4-bit value uses bits 8..11 of the 12-bit angle).
	for fa_base in [0x000, 0x080, 0x100, 0x400, 0x800, 0xC00]:
		var po_lo := AnimationStateController.get_pose_octant(fa_base, 0x400)
		var po_hi := AnimationStateController.get_pose_octant(fa_base + 0x7F, 0x400)
		failed = _expect(po_lo == po_hi,
			"sub-byte increment 0x%x..0x%x keeps pose_octant stable (got %d → %d)" % [
				fa_base, fa_base + 0x7F, po_lo, po_hi], failed)

	# 4. Stepping psx_camera_angle by 0x400 (one cardinal, 90°) shifts
	#    pose_octant by exactly 4 — the "quarter-shift" invariant the old
	#    cardinal-quad path used to assert. With the continuous PSX-angle
	#    formula the sign is fixed (camera offset is +psx, not -psx).
	for fa in [0x000, 0x100, 0x400, 0xC00]:
		var po_c0 := AnimationStateController.get_pose_octant(fa, 0x000)
		var po_c1 := AnimationStateController.get_pose_octant(fa, 0x400)
		var delta := (po_c1 - po_c0 + 16) % 16
		failed = _expect(delta == 4,
			"psx_camera_angle 0x000 → 0x400 shifts pose_octant by +4 at facing_angle=0x%x (got %d → %d, delta=%d)" % [
				fa, po_c0, po_c1, delta], failed)

	# 5. pose_octant >> 2 cycles through 0..3 as facing_angle walks the full
	#    circle — the cardinal collapse the renderer's SEQ-range branch will use
	#    (cardinal_idx = pose_octant >> 2). Asserting the FULL set is hit (no
	#    cardinal lost) is the load-bearing property; the exact angle-to-cardinal
	#    mapping is a camera-calibration concern asserted at integration time.
	var cardinals_seen := {}
	for fa in range(0, 0x1000, 0x100):
		var po := AnimationStateController.get_pose_octant(fa, 0x400)
		cardinals_seen[po >> 2] = true
	failed = _expect(cardinals_seen.size() == 4, "all 4 cardinal_idx values reachable as facing_angle walks the circle (saw %s)" % str(cardinals_seen.keys()), failed)

	# 6. Continuity through a non-cardinal camera angle — old code snapped to
	#    cardinal quads, the new code tracks continuously. A 0x080 step in
	#    psx_camera_angle (≈11°, half a pose_octant) should not skip any octant
	#    when paired with a fixed facing_angle.
	for fa in [0x000, 0x600, 0xC00]:
		var prev := AnimationStateController.get_pose_octant(fa, 0)
		for cam in range(0x80, 0x1000, 0x80):
			var curr := AnimationStateController.get_pose_octant(fa, cam)
			var step := (curr - prev + 16) % 16
			# Stepping psx_camera_angle by 0x80 (half a pose_octant) flips
			# pose_octant by either 0 or 1; gap of >1 means we skipped.
			failed = _expect(step == 0 or step == 1,
				"continuous camera step at facing=0x%x, psx_camera_angle=0x%x: prev=%d curr=%d (delta=%d)" % [
					fa, cam, prev, curr, step], failed)
			prev = curr

	if failed:
		print("[FAIL] get_pose_octant fixture test")
	else:
		print("[PASS] get_pose_octant: range + byte-step + sub-byte stability + camera quad shift + cardinal cycle OK")
	get_tree().quit()


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	return failed_so_far
