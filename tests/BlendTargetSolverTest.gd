extends Node
## TDD guard for BlendTargetSolver — the pure search behind the WYSIWYG "target colour"
## screen-Blend authoring widget (#255). The mode-5 screen Blend param is a SIGNED byte
## applied doubled, so ±128 is not a colour chart; instead the author picks the colour the
## backdrop TOP should BECOME at the parked frame, and the solver brute-forces all 256
## candidate raw bytes per channel through the REAL forward blend (supplied as an evaluator
## callback so this stays pure) and returns the raw bytes whose fold lands closest to the
## target. Reusing the exact forward op means the chosen param is provably the best achievable
## and the parked preview always matches. Seams:
##
##   (1) solve(eval, orig, target) inverts a reachable evaluator EXACTLY — it returns the raw
##       bytes whose fold equals the target (argmin, error 0), scanning each channel
##       independently while holding the others at `orig`.
##   (2) An UNREACHABLE target (a weak evaluator that can't span the colour) resolves to the
##       NEAREST raw byte (min |result − target|), both above and below the reachable range —
##       never a wild value, so the honest "nearest match" caveat holds.
##   (3) The returned bytes are ints in [0, 255].
##
## Expected values are independent hand-worked literals from the synthetic evaluators here,
## NOT recomputed the way solve() searches. Pure, no scene.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/BlendTargetSolverTest.tscn

const Solver = preload("res://src/effects/studio/BlendTargetSolver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_reachable_target_is_inverted_exactly()
	_test_unreachable_target_snaps_to_nearest_byte()
	_test_returned_bytes_are_in_byte_range()

	print("\n=== BlendTargetSolverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] BlendTargetSolverTest")
		get_tree().quit(1)
	else:
		print("[PASS] BlendTargetSolverTest")
		get_tree().quit(0)


## A signed byte in [-128, +127] (two's complement of a 0-255 byte).
func _signed(byte: int) -> int:
	return byte - 256 if byte >= 128 else byte


## Synthetic FULL-RANGE additive evaluator: result_ch = clamp(base_ch + 2·signed(byte)/255).
## Mirrors the doubled signed additive Blend (mode 0/4) over a mid baseline — injective within
## the non-saturating band, so a reachable target has a UNIQUE argmin byte. `base` is 0-1.
func _additive_eval(base: Vector3) -> Callable:
	return func(r: int, g: int, b: int) -> Vector3:
		return Vector3(
			clampf(base.x + 2.0 * _signed(r) / 255.0, 0.0, 1.0),
			clampf(base.y + 2.0 * _signed(g) / 255.0, 0.0, 1.0),
			clampf(base.z + 2.0 * _signed(b) / 255.0, 0.0, 1.0))


## Synthetic WEAK evaluator: delta only ±0.1 (result_ch = clamp(base + 0.1·signed(byte)/128)).
## Its reachable band is [base−0.1, base+0.1], so a target outside that band is UNREACHABLE and
## must resolve to the extreme byte (+127 above, −128 i.e. 128 below). `base` is 0-1.
func _weak_eval(base: Vector3) -> Callable:
	return func(r: int, g: int, b: int) -> Vector3:
		return Vector3(
			clampf(base.x + 0.1 * _signed(r) / 128.0, 0.0, 1.0),
			clampf(base.y + 0.1 * _signed(g) / 128.0, 0.0, 1.0),
			clampf(base.z + 0.1 * _signed(b) / 128.0, 0.0, 1.0))


# --- Seam 1: a reachable target is inverted exactly -----------------------

## With the full-range additive evaluator, pick target = eval(known bytes) inside the
## non-saturating band (so the mapping is injective). solve must return those exact bytes —
## it finds the argmin, scanning each channel independently with the others held at `orig`.
func _test_reachable_target_is_inverted_exactly() -> void:
	var base := Vector3(0.25, 0.5, 0.0)
	var eval := _additive_eval(base)

	# Known bytes, chosen to stay off the 0/1 clamp (injective):
	#   r=20  → signed +20  → +40/255  = 0.15686 → 0.40686
	#   g=200 → signed −56  → −112/255 = −0.43922 → 0.06078
	#   b=10  → signed +10  → +20/255  = 0.07843 → 0.07843
	var target := Vector3(0.40686, 0.06078, 0.07843)
	var orig := {"r": 128, "g": 128, "b": 128}   # deliberately far from the answer

	var best: Dictionary = Solver.solve(eval, orig, target)
	_assert_eq(int(best.get("r", -1)), 20, "R is inverted to its exact byte (independent of orig)")
	_assert_eq(int(best.get("g", -1)), 200, "G is inverted to its exact byte")
	_assert_eq(int(best.get("b", -1)), 10, "B is inverted to its exact byte")


# --- Seam 2: an unreachable target snaps to the nearest byte ---------------

## The weak evaluator can only move each channel ±0.1. A target far ABOVE the reachable band
## resolves to the max-add byte (+127); far BELOW to the max-subtract byte (128 = signed −128).
## Never a wild value — the honest "nearest match" behaviour.
func _test_unreachable_target_snaps_to_nearest_byte() -> void:
	var base := Vector3(0.5, 0.5, 0.5)
	var eval := _weak_eval(base)

	# R target 0.95 (band tops out at 0.6) → nearest is the max-add byte 127.
	# B target 0.0  (band bottoms at 0.4)  → nearest is the max-subtract byte 128.
	# G target 0.5  (exactly the neutral)  → byte 0 (signed 0, zero delta).
	var target := Vector3(0.95, 0.5, 0.0)
	var orig := {"r": 0, "g": 0, "b": 0}

	var best: Dictionary = Solver.solve(eval, orig, target)
	_assert_eq(int(best.get("r", -1)), 127, "an above-range target snaps to the max-add byte (+127)")
	_assert_eq(int(best.get("g", -1)), 0, "a neutral target resolves to zero delta (byte 0)")
	_assert_eq(int(best.get("b", -1)), 128, "a below-range target snaps to the max-subtract byte (−128 = 128)")


# --- Seam 3: byte-range invariant -----------------------------------------

func _test_returned_bytes_are_in_byte_range() -> void:
	var best: Dictionary = Solver.solve(_additive_eval(Vector3(0.3, 0.6, 0.9)),
		{"r": 128, "g": 64, "b": 32}, Vector3(1.0, 0.0, 0.5))
	for ch in ["r", "g", "b"]:
		var v: int = int(best.get(ch, -1))
		_assert_true(v >= 0 and v <= 255, "%s byte is in [0,255] (got %d)" % [ch, v])


# --- asserts --------------------------------------------------------------

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
