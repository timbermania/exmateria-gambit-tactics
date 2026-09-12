extends Node
## Render-cardinal converter golden (issue #138, ADR-0057 -> Render class).
##
## The orientation direction (raw 12-bit facing angle) is the SINGLE source of
## truth; the FacingDirection world enum and the raw cardinal bucket / sprite-
## LUT cardinal are DERIVED VIEWS, reached only through the named converters in
## the AnimationStateController seam. This test golden-locks all three at the
## four cardinals AND the between-cardinal cases, so a future "harmonization"
## cannot silently flip a direction (the E/S-swap category error).
##
## Converters under test (all pure, all in the one module):
##   angle_12bit_to_facing(angle)          -> FacingDirection world enum
##   angle_12bit_to_cardinal_bucket(angle) -> raw truncate bucket 0=E,1=S,2=W,3=N
##   pose_octant_to_atlas_cardinal(octant) -> sprite-LUT cardinal from octant
##
## Run headful; reads stdout; auto-quits.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const Facing = ExMateriaSchema.Facing.Direction
# The PSX truncate is byte-boundary aligned: [0x000,0x400)->E, [0x400,0x800)->S,
# [0x800,0xC00)->W, [0xC00,0x1000)->N. The cardinal bucket IS that truncate; the
# world enum is a second numbering of it. This table is the golden.
const BUCKET_E := 0
const BUCKET_S := 1
const BUCKET_W := 2
const BUCKET_N := 3

var _fail := false


func _ready() -> void:
	# --- angle -> cardinal bucket + world enum, at cardinals AND between them -----
	# Cardinal anchors, exact byte boundaries, and mid-sector between-cardinals.
	var cases := [
		# [angle, expected_bucket, expected_facing]
		[0x000, BUCKET_E, Facing.EAST],   # cardinal E
		[0x200, BUCKET_E, Facing.EAST],   # between E and S -> still E (truncate)
		[0x3FF, BUCKET_E, Facing.EAST],   # last tick before the S boundary
		[0x400, BUCKET_S, Facing.SOUTH],  # cardinal S (boundary flips)
		[0x600, BUCKET_S, Facing.SOUTH],  # between S and W
		[0x800, BUCKET_W, Facing.WEST],   # cardinal W
		[0xA00, BUCKET_W, Facing.WEST],   # between W and N
		[0xC00, BUCKET_N, Facing.NORTH],  # cardinal N
		[0xE00, BUCKET_N, Facing.NORTH],  # between N and E
		[0xFFF, BUCKET_N, Facing.NORTH],  # last tick before wrap
		# wrap-around / negative inputs must normalise identically
		[0x1000, BUCKET_E, Facing.EAST],   # 0x1000 wraps to 0x000
		[-0x400, BUCKET_N, Facing.NORTH],  # -0x400 wraps to 0xC00 -> N
	]
	for c in cases:
		var angle: int = c[0]
		_expect_bucket(angle, c[1])
		_expect_facing(angle, c[2])

	# The two derived views MUST agree on the same truncate bucket: the cardinal
	# bucket and the world enum are two numberings of ONE angle. Crossing them is
	# the retired E/S-swap bug — assert the mapping is consistent everywhere.
	var bucket_to_facing := [Facing.EAST, Facing.SOUTH, Facing.WEST, Facing.NORTH]
	for angle in range(0, 0x1000, 0x40):
		var bucket: int = AnimationStateController.angle_12bit_to_cardinal_bucket(angle)
		var facing: int = AnimationStateController.angle_12bit_to_facing(angle)
		if bucket_to_facing[bucket] != facing:
			_fail = true
			print("  MISMATCH: angle 0x%03X bucket=%d -> %d but facing=%d"
				% [angle, bucket, bucket_to_facing[bucket], facing])

	# --- pose octant -> sprite-LUT cardinal, all 16 octants -----------------------
	# (octant >> 2): octants 0-3->E, 4-7->S, 8-11->W, 12-15->N.
	for octant in range(16):
		var expected: int = (octant >> 2) & 0x3
		var got: int = AnimationStateController.pose_octant_to_atlas_cardinal(octant)
		if got != expected:
			_fail = true
			print("  MISMATCH: octant %d lut_cardinal=%d expected=%d"
				% [octant, got, expected])

	# Grep-clean guard: this test is the ONLY place the raw truncate/`>>2`
	# constants are written out; production code must route through the module.
	if _fail:
		print("[FAIL] render-cardinal converter golden: a derived view drifted "
			+ "from the single-truth angle (ADR-0057 Render).")
	else:
		print("[PASS] render-cardinal converters locked (cardinals + between, "
			+ "bucket<->facing consistent, 16 octants).")
	get_tree().quit()


func _expect_bucket(angle: int, expected: int) -> void:
	var got: int = AnimationStateController.angle_12bit_to_cardinal_bucket(angle)
	if got != expected:
		_fail = true
		print("  MISMATCH: cardinal_bucket(0x%03X)=%d expected=%d" % [angle, got, expected])


func _expect_facing(angle: int, expected: int) -> void:
	var got: int = AnimationStateController.angle_12bit_to_facing(angle)
	if got != expected:
		_fail = true
		print("  MISMATCH: angle_12bit_to_facing(0x%03X)=%d expected=%d"
			% [angle, got, expected])
