extends Node
## TDD guard for PaletteTintSolver (ADR-0087 slice 2) — the WYSIWYG "pick the tint" fix.
##
## The palette tint byte is a SIGNED Δ through a blend mode, not an absolute colour (the
## #266 mislabel: a picked "red" 255 stores as _sb(255) = -1, a near-invisible darken — the
## "seek-color renders wrong hue" bug). This solver back-solves the Δ the SAME way screen's
## BlendTargetSolver does: brute-force all 256 candidate raw bytes per channel through the
## REAL forward palette fold (ColorStack, param_max 31, quantize) over a FIXED mid-grey
## (15/31) reference, and keep the byte whose result lands closest to the picked target.
## Because both base AND colour-so-far are the fixed reference in the single-op fold, every
## mode's per-channel result is a pure function of one delta byte (ADR-0087 decision 3), so
## the per-channel scan is valid for the luma modes too — no 3-D search.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/PaletteTintSolverTest.tscn

const Solver = preload("res://src/effects/studio/PaletteTintSolver.gd")

# One 5-bit CLUT step — the achievable-target tolerance after quantization.
const STEP := 1.0 / 31.0

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_picking_red_reads_red_not_a_dark_shift()
	_test_picking_the_reference_solves_a_zero_delta()
	_test_result_is_the_forward_fold_of_the_stored_bytes()
	_test_reported_achieved_matches_the_forward_fold_of_the_solved_bytes()

	print("\n=== PaletteTintSolverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PaletteTintSolverTest")
		get_tree().quit(1)
	else:
		print("[PASS] PaletteTintSolverTest")
		get_tree().quit(0)


## THE FIX: an author who picks bright red under an additive (mode 0) tint gets a surface
## that reads bright red — NOT the #266 near-black darken. Reachable target → achieved within
## one 5-bit step of the pick per channel.
func _test_picking_red_reads_red_not_a_dark_shift() -> void:
	var res := Solver.solve(0, {"r": 0, "g": 0, "b": 0}, Vector3(1.0, 0.0, 0.0))
	var got: Color = res.get("achieved", Color.BLACK)
	_assert_near(got.r, 1.0, STEP, "picked red reads bright red (not the #266 dark shift)")
	_assert_near(got.g, 0.0, STEP, "green channel solves to black")
	_assert_near(got.b, 0.0, STEP, "blue channel solves to black")
	# And the honest tell: the solved RED byte is a POSITIVE delta (a lighten), not the raw 255
	# the old gradient picker fanned (which sign-extends to −1, a darken).
	_assert_true(_sb(int(res.get("r", 255))) > 0, "the solved red byte is a positive (lightening) delta")


## Picking the reference colour itself solves a ~zero delta (byte 0) — the identity: "grey
## stays grey" under an additive mode needs no tint.
func _test_picking_the_reference_solves_a_zero_delta() -> void:
	var ref := 15.0 / 31.0
	var res := Solver.solve(0, {"r": 128, "g": 128, "b": 128}, Vector3(ref, ref, ref))
	_assert_eq(int(res.get("r", -1)), 0, "reference red → zero delta")
	_assert_eq(int(res.get("g", -1)), 0, "reference green → zero delta")
	_assert_eq(int(res.get("b", -1)), 0, "reference blue → zero delta")


## The seed helper `result(mode, r, g, b)` IS the forward fold the preview uses — an additive
## mode folds mid-grey + Δ. A stored −16 (byte 240) delta darkens the reference by 16/31.
func _test_result_is_the_forward_fold_of_the_stored_bytes() -> void:
	var ref := 15.0 / 31.0
	var got: Color = Solver.result(0, 240, 240, 240)  # _sb(240) = −16
	var want := clampf(ref - 16.0 / 31.0, 0.0, 1.0)
	_assert_near(got.r, want, 0.001, "additive result folds reference + signed delta")


## The reported `achieved` colour equals the forward fold of the SOLVED bytes — so the widget's
## "actual" swatch never lies about what the surface reaches.
func _test_reported_achieved_matches_the_forward_fold_of_the_solved_bytes() -> void:
	var res := Solver.solve(1, {"r": 0, "g": 0, "b": 0}, Vector3(0.9, 0.1, 0.5))  # mode 1 = dim ½ + add
	var got: Color = res.get("achieved", Color.BLACK)
	var refold: Color = Solver.result(1, int(res.r), int(res.g), int(res.b))
	_assert_near(got.r, refold.r, 0.0001, "achieved.r == forward fold of solved bytes")
	_assert_near(got.g, refold.g, 0.0001, "achieved.g == forward fold of solved bytes")
	_assert_near(got.b, refold.b, 0.0001, "achieved.b == forward fold of solved bytes")


# --- helpers --------------------------------------------------------------

func _sb(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


func _assert_near(actual: float, expected: float, tol: float, label: String) -> void:
	if absf(actual - expected) <= tol:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%f (±%f), got %f" % [label, expected, tol, actual])


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
