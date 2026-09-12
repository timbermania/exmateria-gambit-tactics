extends Node
## TDD guard for CameraValueSemantics — issue #281. A camera keyframe value is stored the
## same way regardless of mode, but what it MEANS depends on source_mode × interpolation:
## an absolute heading, an offset from a unit's facing / a saved slot, a delta on the current
## camera, or a shake amplitude. The inspector must LABEL it honestly so "Yaw 15.8°" doesn't
## read as a world heading when the engine treats it as an offset.
##
## Expected labels are an INDEPENDENT source of truth — read off CameraSubsystem's
## _execute_{angle,position,zoom}_command match statements (the runtime), NOT the classifier's
## own table:
##   angle TARGET  → pitch = current+kf (Δ), yaw = facing+kf (offset), roll = current+kf (Δ)
##   angle OFFSET  → pitch = kf (absolute),   yaw = current+kf (Δ),      roll = current+kf (Δ)
##   angle DIRECT  → all = kf (absolute)
##   angle MAP     → all = current+kf (Δ)
##   angle SLOT_COPY → all = saved+kf (offset)
##   angle ORIGIN  → pitch = saved+kf (offset), yaw/roll = current+kf (Δ)
##   position: anchor-modes = offset, DIRECT = absolute, MAP = Δ, SLOT_COPY/ORIGIN = offset
##   zoom: MAP = Δ, SLOT_COPY = offset, OFFSET/CURSOR = INERT (runtime no-ops), else absolute
##   any SHAKE_* interpolation ⇒ amplitude (overrides the source role) — EXCEPT an inert
##     zoom mode, where the runtime early-returns before the shake branch, so inert wins
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraValueSemanticsTest.tscn

const Sem = preload("res://src/effects/studio/CameraValueSemantics.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_angle_target_is_per_component()
	_test_angle_direct_is_absolute()
	_test_angle_offset_pitch_absolute_yaw_delta()
	_test_angle_map_and_slotcopy_and_origin()
	_test_position_modes()
	_test_zoom_modes()
	_test_zoom_offset_cursor_is_inert()
	_test_shake_overrides_to_amplitude()
	_test_is_amplitude_flags_the_shake_interps()
	_test_is_inert_flags_zoom_offset_and_cursor()

	print("\n=== CameraValueSemanticsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraValueSemanticsTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraValueSemanticsTest")
		get_tree().quit(0)


func _lbl(base, chan, comp, src, interp) -> String:
	return Sem.label(base, chan, comp, src, interp)


func _test_angle_target_is_per_component() -> void:
	_assert_eq(_lbl("Pitch", "angle", 0, "TARGET", "LINEAR"), "Pitch Δ", "TARGET pitch = current+kf → Δ")
	_assert_eq(_lbl("Yaw", "angle", 1, "TARGET", "LINEAR"), "Yaw offset", "TARGET yaw = facing+kf → offset")
	_assert_eq(_lbl("Roll", "angle", 2, "TARGET", "LINEAR"), "Roll Δ", "TARGET roll = current+kf → Δ")
	# CASTER/CURSOR/EFFECT_CTR/ALL_TARGETS share TARGET's shape.
	_assert_eq(_lbl("Yaw", "angle", 1, "CASTER", "LINEAR"), "Yaw offset", "CASTER yaw = facing+kf → offset")


func _test_angle_direct_is_absolute() -> void:
	_assert_eq(_lbl("Yaw", "angle", 1, "DIRECT", "LINEAR"), "Yaw", "DIRECT yaw = kf → absolute (no suffix)")
	_assert_eq(_lbl("Pitch", "angle", 0, "DIRECT", "LINEAR"), "Pitch", "DIRECT pitch = kf → absolute")


func _test_angle_offset_pitch_absolute_yaw_delta() -> void:
	_assert_eq(_lbl("Pitch", "angle", 0, "OFFSET", "LINEAR"), "Pitch", "OFFSET pitch = kf → absolute")
	_assert_eq(_lbl("Yaw", "angle", 1, "OFFSET", "LINEAR"), "Yaw Δ", "OFFSET yaw = current+kf → Δ")


func _test_angle_map_and_slotcopy_and_origin() -> void:
	_assert_eq(_lbl("Yaw", "angle", 1, "MAP", "LINEAR"), "Yaw Δ", "MAP yaw = current+kf → Δ")
	_assert_eq(_lbl("Yaw", "angle", 1, "SLOT_COPY", "LINEAR"), "Yaw offset", "SLOT_COPY yaw = saved+kf → offset")
	_assert_eq(_lbl("Pitch", "angle", 0, "ORIGIN", "LINEAR"), "Pitch offset", "ORIGIN pitch = saved+kf → offset")
	_assert_eq(_lbl("Yaw", "angle", 1, "ORIGIN", "LINEAR"), "Yaw Δ", "ORIGIN yaw = current+kf → Δ")


func _test_position_modes() -> void:
	_assert_eq(_lbl("X", "position", 0, "TARGET", "LINEAR"), "X offset", "position TARGET = anchor+kf → offset")
	_assert_eq(_lbl("X", "position", 0, "DIRECT", "LINEAR"), "X", "position DIRECT = kf → absolute")
	_assert_eq(_lbl("X", "position", 0, "MAP", "LINEAR"), "X Δ", "position MAP = current+kf → Δ")
	_assert_eq(_lbl("Y", "position", 1, "SLOT_COPY", "LINEAR"), "Y offset", "position SLOT_COPY = saved+kf → offset")


func _test_zoom_modes() -> void:
	_assert_eq(_lbl("Zoom", "zoom", 0, "MAP", "LINEAR"), "Zoom Δ", "zoom MAP = current+kf → Δ")
	_assert_eq(_lbl("Zoom", "zoom", 0, "SLOT_COPY", "LINEAR"), "Zoom offset", "zoom SLOT_COPY = saved+kf → offset")
	_assert_eq(_lbl("Zoom", "zoom", 0, "DIRECT", "LINEAR"), "Zoom", "zoom DIRECT = kf → absolute")


## zoom under OFFSET / CURSOR is a NO-OP: CameraSubsystem._execute_zoom_command early-returns
## for those modes (0x801… camera path; verified at CameraSubsystem.gd:493-495) before setting
## up any tween, so the stored value never moves the camera. Labelled inert (#281) — not an
## absolute zoom the author can trust.
func _test_zoom_offset_cursor_is_inert() -> void:
	_assert_eq(_lbl("Zoom", "zoom", 0, "OFFSET", "LINEAR"), "Zoom (inert)", "zoom OFFSET = no-op → inert")
	_assert_eq(_lbl("Zoom", "zoom", 0, "CURSOR", "LINEAR"), "Zoom (inert)", "zoom CURSOR = no-op → inert")
	# Inert wins over amplitude: the runtime returns BEFORE the shake branch for these modes.
	_assert_eq(_lbl("Zoom", "zoom", 0, "OFFSET", "SHAKE_DAMPED"), "Zoom (inert)",
		"zoom OFFSET+SHAKE still no-ops → inert, not amplitude")
	# Non-inert zoom modes are unaffected (angle/position never inert).
	_assert_eq(_lbl("Zoom", "zoom", 0, "TARGET", "LINEAR"), "Zoom", "zoom TARGET = kf → absolute (not inert)")


func _test_shake_overrides_to_amplitude() -> void:
	# SHAKE_* stores an amplitude, not an angle-to — overrides whatever the source role was.
	_assert_eq(_lbl("Yaw", "angle", 1, "DIRECT", "SHAKE_DAMPED"), "Yaw amplitude", "SHAKE overrides absolute")
	_assert_eq(_lbl("Yaw", "angle", 1, "TARGET", "SHAKE_DIRECT"), "Yaw amplitude", "SHAKE overrides offset")
	_assert_eq(_lbl("Zoom", "zoom", 0, "MAP", "SHAKE_DAMPED_B"), "Zoom amplitude", "SHAKE overrides zoom Δ (MAP not inert)")


## The SAME predicate that drives the "amplitude" suffix — exposed so the projector can
## decorate a shake row's value with "±" (a symmetric peak) without re-listing the SHAKE set.
func _test_is_amplitude_flags_the_shake_interps() -> void:
	_assert_true(Sem.is_amplitude("SHAKE_DAMPED"), "SHAKE_DAMPED is an amplitude")
	_assert_true(Sem.is_amplitude("SHAKE_DIRECT"), "SHAKE_DIRECT is an amplitude")
	_assert_true(Sem.is_amplitude("SHAKE_DAMPED_B"), "SHAKE_DAMPED_B is an amplitude")
	_assert_true(not Sem.is_amplitude("LINEAR"), "LINEAR is not an amplitude")
	_assert_true(not Sem.is_amplitude("COSINE_A"), "COSINE_A is not an amplitude")


## The predicate that drives the inert label — exposed so the projector can suppress the "±"
## amplitude decoration on an inert zoom row (a no-op is neither a target nor a shake peak).
func _test_is_inert_flags_zoom_offset_and_cursor() -> void:
	_assert_true(Sem.is_inert("zoom", "OFFSET"), "zoom OFFSET is inert")
	_assert_true(Sem.is_inert("zoom", "CURSOR"), "zoom CURSOR is inert")
	_assert_true(not Sem.is_inert("zoom", "MAP"), "zoom MAP is not inert")
	_assert_true(not Sem.is_inert("zoom", "DIRECT"), "zoom DIRECT is not inert")
	# Only zoom has an inert mode set; angle/position OFFSET are meaningful, never inert.
	_assert_true(not Sem.is_inert("angle", "OFFSET"), "angle OFFSET is not inert")
	_assert_true(not Sem.is_inert("position", "CURSOR"), "position CURSOR is not inert")


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
