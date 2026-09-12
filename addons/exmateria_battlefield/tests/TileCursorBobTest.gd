extends Node

## CursorBob phase-machine test — pure GDScript, no rendering.
##
## Guards the ROM-faithful tile-cursor bob step machine (ADR-0046). The knife
## bob is two parallel 8-entry tables — OFFSET {0,1,2,3,5,3,2,1} and HOLD
## {16,8,2,2,6,4,4,10} — read from BATTLE.BIN (FUN_8007e304) into
## tile_knife.json. A frame counter advancing at VBLANK_HZ/vblanks_per_tick
## selects the phase; the offset is one-sided from rest (16-frame dwell at 0,
## single excursion to 5). One full cycle = 52 frames (sum of holds).
##
## Asserts: the exact 52-frame sequence, wrap at 52, and hold-count boundary
## edges (a frame on a boundary belongs to the LATER step).

const TileCursorBobScript = preload("res://addons/exmateria_battlefield/cursor/TileCursorBob.gd")

# The ground-truth tables (also what tile_knife.json must carry).
const OFFSETS := [0, 1, 2, 3, 5, 3, 2, 1]
const HOLDS := [16, 8, 2, 2, 6, 4, 4, 10]

# COUNTERS, not a bare bool — gained in the move commit, the ADR-0194 dec. 12 arm 2
# convention already applied to DepthModeTest, TileCursorCompositorTest and the overlay
# pair. A `[PASS]` printed off `not failed` is equally true of a run that asserted
# NOTHING, and a GDScript runtime error aborts only its ENCLOSING function while `_ready`
# carries on — so the verdict below pins the TOTAL, not just the absence of failures.
var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		print("[FAIL] %s" % msg)
		_failed += 1


func _ready() -> void:

	# Build the expected per-frame offset for one cycle: 16×0, 8×1, 2×2, 2×3,
	# 6×5, 4×3, 4×2, 10×1 = 52 frames.
	var expected: Array[int] = []
	for i in OFFSETS.size():
		for _h in range(HOLDS[i]):
			expected.append(OFFSETS[i])

	# 1. Cycle length is the sum of holds (52).
	var cycle := TileCursorBobScript.cycle_length(HOLDS)
	_check(cycle == 52, "cycle_length = %d, expected 52" % cycle)
	_check(expected.size() == 52, "expected sequence is %d frames, should be 52" % expected.size())

	# 2. Every frame in the first cycle maps to the right offset.
	for f in expected.size():
		var got := TileCursorBobScript.offset_for_frame(OFFSETS, HOLDS, f)
		_check(got == expected[f], "frame %d -> offset %d, expected %d" % [f, got, expected[f]])

	# 3. Wrap: frame 52..103 repeats the cycle; frame 52 returns to offset 0.
	for f in range(52, 104):
		var got := TileCursorBobScript.offset_for_frame(OFFSETS, HOLDS, f)
		_check(got == expected[f % 52],
			"wrapped frame %d -> offset %d, expected %d" % [f, got, expected[f % 52]])

	# 4. Exact hold-count boundary edges. A frame ON a boundary is the LATER step.
	#    Cumulative ends: 16, 24, 26, 28, 34, 38, 42, 52.
	var edge_cases := {
		15: 0,   # last frame of the 16-frame dwell at offset 0
		16: 1,   # first frame of step 1 (offset 1)
		23: 1,   # last frame of step 1
		24: 2,   # boundary -> step 2
		27: 3,   # last frame of step 3 (the 2-frame dwell at offset 3)
		28: 5,   # excursion to the peak offset 5
		33: 5,   # last peak frame
		34: 3,   # descend
		41: 2,   # last frame of step 6
		42: 1,   # final 10-frame dwell at offset 1
		51: 1,   # last frame of the cycle
	}
	for f in edge_cases:
		var got := TileCursorBobScript.offset_for_frame(OFFSETS, HOLDS, f)
		_check(got == edge_cases[f], "edge frame %d -> offset %d, expected %d" % [f, got, edge_cases[f]])

	# 5. phase_for_frame indexes the table directly: boundary 24 -> phase 2.
	_check(TileCursorBobScript.phase_for_frame(HOLDS, 24) == 2,
		"phase_for_frame(24) = %d, expected 2" % TileCursorBobScript.phase_for_frame(HOLDS, 24))

	# 6. Negative frames wrap correctly (-1 -> last frame of cycle, offset 1).
	_check(TileCursorBobScript.offset_for_frame(OFFSETS, HOLDS, -1) == 1,
		"frame -1 -> %d, expected 1" % TileCursorBobScript.offset_for_frame(OFFSETS, HOLDS, -1))

	# 7. The committed tile_knife.json carries the same tables (parser parity).
	var table: Dictionary = TileCursorBobScript.load_step_table("tile_knife")
	_check(table.get("offsets", []) == OFFSETS,
		"tile_knife.json offsets = %s, expected %s" % [table.get("offsets"), OFFSETS])
	_check(table.get("holds", []) == HOLDS,
		"tile_knife.json holds = %s, expected %s" % [table.get("holds"), HOLDS])
	_check(int(table.get("tile_unit", 0)) == 28,
		"tile_knife.json tile_unit = %s, expected 28" % table.get("tile_unit"))

	print("\n=== TileCursorBobTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] TileCursorBobTest: ran zero assertions")
	elif _failed:
		print("[FAIL] CursorBob phase-machine test")
	else:
		print("[PASS] TileCursorBob: 52-frame sequence 16×0,8×1,2×2,2×3,6×5,4×3,4×2,10×1, wrap, edges, JSON parity")
	get_tree().quit()
