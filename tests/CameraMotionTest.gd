extends Node
## TDD guard for CameraMotion — the tagged-union AUTHORING VIEW of the camera command
## word's interpolation field (bits 9-12, mask 0x1E00). One 4-bit ROM field encodes BOTH
## a motion KIND (a track either moves toward a target OR shakes — never both; same field)
## and a per-kind PROFILE (Move → an easing curve; Shake → a decay). This module is the ONE
## place that partitions the interp bits into that view; storage/writer/runtime keep the
## single field. Pure, no runtime deps (testable in isolation, no `class_name` per ADR-0004).
##
## Expected values are an INDEPENDENT source of truth — the ROM interp bit table mirrored in
## CameraChannel._INTERPOLATIONS / parse_effect.CAMERA_INTERPOLATIONS:
##   Move easings: 0x0200 IMMEDIATE, 0x0400 COSINE_A, 0x0600 COSINE_B, 0x0800 LINEAR,
##                 0x0A00 COSINE_C, 0x0C00 ADDITIVE, 0x0E00 ADDITIVE_B
##   Shake decays: 0x1000 SHAKE_DAMPED, 0x1200 SHAKE_DIRECT, 0x1400 SHAKE_DAMPED_B
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraMotionTest.tscn

const CameraMotion = preload("res://src/effects/studio/CameraMotion.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_kind_of_partitions_the_interp_bits()
	_test_profile_choices_are_scoped_to_the_kind()
	_test_kind_choices_and_representative_drive_the_binary()

	print("\n=== CameraMotionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraMotionTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraMotionTest")
		get_tree().quit(0)


## bits 9-12: 0x1000+ is a SHAKE (Shake kind); everything below is a move-to-target easing
## (Move kind). Unmapped/zero bits fall back to Move (the safe, non-reinterpreting default).
func _test_kind_of_partitions_the_interp_bits() -> void:
	_assert_eq(CameraMotion.kind_of(0x0800), CameraMotion.MOVE, "LINEAR is a Move")
	_assert_eq(CameraMotion.kind_of(0x0200), CameraMotion.MOVE, "IMMEDIATE is a Move")
	_assert_eq(CameraMotion.kind_of(0x0E00), CameraMotion.MOVE, "ADDITIVE_B is a Move")
	_assert_eq(CameraMotion.kind_of(0x1000), CameraMotion.SHAKE, "SHAKE_DAMPED is a Shake")
	_assert_eq(CameraMotion.kind_of(0x1200), CameraMotion.SHAKE, "SHAKE_DIRECT is a Shake")
	_assert_eq(CameraMotion.kind_of(0x1400), CameraMotion.SHAKE, "SHAKE_DAMPED_B is a Shake")
	_assert_eq(CameraMotion.kind_of(0x0000), CameraMotion.MOVE, "unmapped 0x0000 falls back to Move")


## Move lists the seven easings at their ROM bits; Shake lists the three decays with the
## "SHAKE_" prefix dropped (the Motion row already says "Shake"). Each choice's VALUE is the
## FULL positioned interp bits so the enum cell fans it straight to the interpolation field.
func _test_profile_choices_are_scoped_to_the_kind() -> void:
	var move := CameraMotion.profile_choices(CameraMotion.MOVE)
	_assert_eq(move.size(), 7, "Move has the seven easing profiles")
	_assert_true(_has(move, 0x0800, "LINEAR"), "Move profiles list LINEAR at 0x0800")
	_assert_true(_has(move, 0x0200, "IMMEDIATE"), "Move profiles list IMMEDIATE at 0x0200")
	_assert_true(_has(move, 0x0E00, "ADDITIVE_B"), "Move profiles list ADDITIVE_B at 0x0E00")

	var shake := CameraMotion.profile_choices(CameraMotion.SHAKE)
	_assert_eq(shake.size(), 3, "Shake has the three decay profiles")
	_assert_true(_has(shake, 0x1000, "Damped"), "Shake profiles list Damped at 0x1000")
	_assert_true(_has(shake, 0x1200, "Direct"), "Shake profiles list Direct at 0x1200")
	_assert_true(_has(shake, 0x1400, "Damped B"), "Shake profiles list Damped B at 0x1400")


## The Motion binary is a 2-item enum whose two choice VALUES are each kind's DEFAULT interp
## bits — so selecting one flips the field to that kind's default profile. representative(kind)
## returns that same default, which is what the Motion row SEEDS to, so the cell highlights the
## right kind for ANY current profile (COSINE_A still shows "Move"). Two invariants tie them
## together: representative(kind) is the KIND_CHOICES value for that kind, and it round-trips —
## kind_of(representative(kind)) == kind.
func _test_kind_choices_and_representative_drive_the_binary() -> void:
	_assert_eq(CameraMotion.KIND_CHOICES.size(), 2, "Motion is a binary — two choices")
	_assert_true(_has(CameraMotion.KIND_CHOICES, 0x0800, "Move (to target)"), "Move choice defaults to LINEAR bits")
	_assert_true(_has(CameraMotion.KIND_CHOICES, 0x1000, "Shake"), "Shake choice defaults to SHAKE_DAMPED bits")

	_assert_eq(CameraMotion.representative(CameraMotion.MOVE), 0x0800, "Move seeds to LINEAR")
	_assert_eq(CameraMotion.representative(CameraMotion.SHAKE), 0x1000, "Shake seeds to SHAKE_DAMPED")
	# Round-trip: a kind's representative classifies back to that kind (so seeding highlights it).
	_assert_eq(CameraMotion.kind_of(CameraMotion.representative(CameraMotion.MOVE)), CameraMotion.MOVE, "Move representative is a Move")
	_assert_eq(CameraMotion.kind_of(CameraMotion.representative(CameraMotion.SHAKE)), CameraMotion.SHAKE, "Shake representative is a Shake")


func _has(choices: Array, value: int, label: String) -> bool:
	for c in choices:
		if int(c.get("value", -999)) == value and str(c.get("label", "")) == label:
			return true
	return false


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
