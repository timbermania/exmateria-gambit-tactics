extends Node
## TDD guard (#271): the effect-level "Effect Settings" inspection target + its registry
## routing (ADR-0073). Unlike span/emitter/container, an effect_settings target is GLOBAL —
## exactly one per effect, degenerate ref {} — so the whole small-byte cluster (timeline
## durations #271, effect flags #272, time scale #270) finally has somewhere to be edited.
## This guard pins the target shape, the title, and that the registry routes the kind to a
## real (built) projector so the inspector renders it instead of erroring.
##
## Run: <GODOT> --path . --quit-after 2 res://tests/EffectSettingsTargetTest.tscn

const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")
const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_target_shape()
	_test_title_and_label()
	_test_registry_recognizes_and_builds_kind()

	print("\n=== EffectSettingsTargetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSettingsTargetTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSettingsTargetTest")
		get_tree().quit(0)


## The target is `{kind:"effect_settings", ref:{}}` — a degenerate ref (one effect only),
## so the back-stack dedup and the projector both read an empty payload.
func _test_target_shape() -> void:
	var t := InspectionTarget.effect_settings()
	_assert_eq(InspectionTarget.kind(t), "effect_settings", "kind is effect_settings")
	_assert_eq(InspectionTarget.ref(t), {}, "ref is the degenerate empty payload")
	_assert_true(InspectionTarget.equals(t, InspectionTarget.effect_settings()),
		"two effect_settings targets are equal (back-stack dedups)")


## Title reads "Effect Settings"; the nav-trail token is a short "effect settings".
func _test_title_and_label() -> void:
	var t := InspectionTarget.effect_settings()
	_assert_eq(InspectionTarget.title(t), "Effect Settings", "title is Effect Settings")
	_assert_eq(InspectionTarget.label(t), "effect settings", "breadcrumb token")


## The registry RECOGNIZES the kind and reports it BUILT (a real projector, not a seam) so
## the inspector renders header/sections rather than the empty-seam fallback.
func _test_registry_recognizes_and_builds_kind() -> void:
	_assert_true(Registry.has_kind("effect_settings"), "registry recognizes the kind")
	_assert_true(Registry.is_built("effect_settings"), "registry reports it built")
	_assert_true(Registry.projector_for("effect_settings") != null,
		"registry resolves a real projector for the kind")


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
