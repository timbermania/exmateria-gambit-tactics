extends Node
## TDD guard for SpacerVerdicts (ADR-0087 decs. 17-22): the spacer verdict is
## DISABLE-EQUIVALENCE, not intrinsic bytes — fold the channel's authored stream WITH
## the event vs WITHOUT it (timing kept, exactly the runtime's disabled semantics) and
## compare as colour TRANSFORMS: equal for every probe base, at every ramp breakpoint.
## Never "equal on the currently-previewed colour" — a hatch must survive a map change.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SpacerVerdictsTest.tscn

const Verdicts = preload("res://src/effects/studio/SpacerVerdicts.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const ScreenDataClass = ExMateriaEffects.ScreenData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_intrinsic_class_stays_spacer()
	_test_e317_shaped_lane_lead_flash_fade_hold()
	_test_over_base_delta0_is_contextual()
	_test_half_dim_and_luma_are_never_spacers()
	_test_restore_over_nothing_vs_after_tint()
	_test_gradient_transform_equality()
	_test_overlapping_equal_gradient_differs_mid_ramp_only()
	_test_palette_wrapper_folds_cross_phase()
	_test_screen_wrapper_ands_both_endpoints()

	print("\n=== SpacerVerdictsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpacerVerdictsTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpacerVerdictsTest")
		get_tree().quit(0)


## The new predicate SUBSUMES the third amendment's intrinsic one: a disabled
## keyframe and an enabled mode-0 Δ0 satisfy disable-equivalence trivially, so
## nothing hatched today un-hatches. A non-zero Δ in a current-source mode is real.
func _test_intrinsic_class_stays_spacer() -> void:
	var v: Array = Verdicts.verdicts([_op(4, [25, 23, 8], 0, 1, false)], Verdicts.PALETTE_PROFILE)
	_assert_true(bool(v[0]), "a disabled op is a spacer (no push either way — timing only)")
	v = Verdicts.verdicts([_op(0, [0, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
	_assert_true(bool(v[0]), "enabled mode-0 Δ0 is a spacer (current + 0 in any context)")
	v = Verdicts.verdicts([_op(0, [1, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
	_assert_true(not bool(v[0]), "mode-0 Δ(1,0,0) is real (one 5-bit quantum shows)")


## The E317 caster shape (the amendment's motivating pins): the SAME m4 Δ0 bytes are
## a spacer as a lead-in (nothing tinted beneath — base + 0 over a clean stack) and as
## a post-fade hold, but REAL as the flash's fade-out ramp (they're what runs the tint
## back down). Byte-identical events, opposite roles — only context tells them apart.
func _test_e317_shaped_lane_lead_flash_fade_hold() -> void:
	var ops: Array = [
		_op(4, [0, 0, 0], 0),      # lead-in: base+0 over a clean stack
		_op(4, [25, 23, 8], 8),    # the flash (real tint)
		_op(4, [0, 0, 0], 16),     # fade-out ramp: runs current back to base
		_op(4, [0, 0, 0], 24),     # post-fade hold: base again, already at base
	]
	var v: Array = Verdicts.verdicts(ops, Verdicts.PALETTE_PROFILE)
	_assert_true(bool(v[0]), "the m4 Δ0 lead-in is a spacer (nothing beneath to mask)")
	_assert_true(not bool(v[1]), "the flash is real")
	_assert_true(not bool(v[2]), "the m4 Δ0 FADE-OUT is real — same bytes as the lead-in, opposite role")
	_assert_true(bool(v[3]), "the post-fade m4 Δ0 hold is a spacer (already at base)")


## Mode-4/9 Δ0 (base + 0) is CONTEXTUAL: alone it is a spacer, but over a live
## current-source tint it masks everything below — disabling it would let the tint
## show, so it is real. (The third amendment excluded these wholesale; the fourth
## amendment's fold decides per context.)
func _test_over_base_delta0_is_contextual() -> void:
	var v: Array = Verdicts.verdicts([_op(9, [0, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
	_assert_true(bool(v[0]), "m9 Δ0 alone is a spacer (base + 0 over a clean stack)")
	v = Verdicts.verdicts([
		_op(0, [10, 0, 0], 0),    # a live current-source tint
		_op(4, [0, 0, 0], 8),     # base+0 on top: masks the tint below
	], Verdicts.PALETTE_PROFILE)
	_assert_true(not bool(v[1]), "m4 Δ0 over a live tint is REAL (a reset-to-base that masks below)")


## Modes 1/5 at Δ0 are NEVER spacers — `(current|base >> 1) + 0` is a half-dim
## (on E317/E015 those events ARE the darkening). Luma modes recolour even at Δ0.
func _test_half_dim_and_luma_are_never_spacers() -> void:
	for mode in [1, 5]:
		var v: Array = Verdicts.verdicts([_op(mode, [0, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
		_assert_true(not bool(v[0]), "mode-%d Δ0 is real (half-dim, never a spacer)" % mode)
	for mode in [2, 3, 6, 7]:
		var v: Array = Verdicts.verdicts([_op(mode, [0, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
		_assert_true(not bool(v[0]), "luma mode-%d Δ0 is real (recolours even at Δ0)" % mode)


## A mode-8 restore is contextual: over nothing (or after everything already
## restored) it is a spacer; after a live tint it is the cleanup — real.
func _test_restore_over_nothing_vs_after_tint() -> void:
	var v: Array = Verdicts.verdicts([_op(8, [0, 0, 0], 0)], Verdicts.PALETTE_PROFILE)
	_assert_true(bool(v[0]), "m8 over nothing is a spacer")
	v = Verdicts.verdicts([
		_op(4, [25, 23, 8], 0),
		_op(8, [0, 0, 0], 8),
	], Verdicts.PALETTE_PROFILE)
	_assert_true(not bool(v[1]), "m8 after a live tint is real (the cleanup)")
	v = Verdicts.verdicts([
		_op(4, [25, 23, 8], 0),
		_op(8, [0, 0, 0], 8),
		_op(8, [0, 0, 0], 32),
	], Verdicts.PALETTE_PROFILE)
	_assert_true(not bool(v[1]), "the first m8 stays real")
	_assert_true(bool(v[2]), "a second m8 after everything expired is a spacer")


## Transform equality keeps a LEADING Gradient real forever — an absolute set and a
## map-dependent passthrough differ as functions even when they coincide on one
## previewed sky — while a Gradient after an EQUAL settled Gradient is a redundant
## re-set (a spacer). A different target stays real.
func _test_gradient_transform_equality() -> void:
	var v: Array = Verdicts.verdicts([_grad([32, 64, 124], 0, 8)], Verdicts.SCREEN_PROFILE)
	_assert_true(not bool(v[0]), "a leading Gradient is real (absolute set ≠ passthrough as transforms)")
	v = Verdicts.verdicts([
		_grad([32, 64, 124], 0, 8),
		_grad([32, 64, 124], 16, 8),
	], Verdicts.SCREEN_PROFILE)
	_assert_true(bool(v[1]), "a Gradient after an EQUAL settled Gradient is a spacer (redundant re-set)")
	_assert_true(not bool(v[0]), "…the first one stays real")
	v = Verdicts.verdicts([
		_grad([32, 64, 124], 0, 8),
		_grad([200, 10, 10], 16, 8),
	], Verdicts.SCREEN_PROFILE)
	_assert_true(not bool(v[1]), "a Gradient to a DIFFERENT target is real")


## An equal-target Gradient that overlaps a longer ramp to the same target IS real:
## it accelerates the trajectory. The two folds agree at every breakpoint (start,
## both ramp ends) and differ only strictly BETWEEN them — the midpoint samples are
## what catch it (transform equality is checked between breakpoints too).
func _test_overlapping_equal_gradient_differs_mid_ramp_only() -> void:
	var v: Array = Verdicts.verdicts([
		_grad([255, 255, 255], 0, 32),
		_grad([255, 255, 255], 8, 32),
	], Verdicts.SCREEN_PROFILE)
	_assert_true(not bool(v[1]),
		"an equal-target Gradient overlapping a longer ramp is real (differs mid-interval only)")


## The palette wrapper folds ONE continuous stream across phases at the given absolute
## offsets (the PSX has no phase concept), so cross-phase context is real context:
## a phase2 m8 after a LIVE for_each tint is real cleanup; once the for_each lane
## already restored everything, the same phase2 m8 is a spacer (the E015 pin's shape).
func _test_palette_wrapper_folds_cross_phase() -> void:
	var offsets := {"for_each": 8, "phase2": 72}
	var live = PaletteDataClass.from_json({
		"for_each": {"caster": {"context": "for_each", "channel_name": "caster",
			"max_keyframe": 2,
			"keyframes": [{"enabled": true, "blend_mode": 4, "rgb": [25, 23, 8],
				"time_value": 1, "duration_frames": 8}]}},
		"phase2": {"caster": {"context": "phase2", "channel_name": "caster",
			"max_keyframe": 2,
			"keyframes": [{"enabled": true, "blend_mode": 8, "rgb": [0, 0, 0],
				"time_value": 1, "duration_frames": 8}]}},
	})
	var v: Dictionary = Verdicts.palette_verdicts(live, "caster", offsets)
	_assert_true(not bool(v["phase2"][0]),
		"a phase2 m8 after a live for_each tint is REAL cleanup (cross-phase context)")
	var restored = PaletteDataClass.from_json({
		"for_each": {"caster": {"context": "for_each", "channel_name": "caster",
			"max_keyframe": 3,
			"keyframes": [
				{"enabled": true, "blend_mode": 4, "rgb": [25, 23, 8],
					"time_value": 1, "duration_frames": 8},
				{"enabled": true, "blend_mode": 8, "rgb": [0, 0, 0],
					"time_value": 1, "duration_frames": 8}]}},
		"phase2": {"caster": {"context": "phase2", "channel_name": "caster",
			"max_keyframe": 2,
			"keyframes": [{"enabled": true, "blend_mode": 8, "rgb": [0, 0, 0],
				"time_value": 1, "duration_frames": 8}]}},
	})
	v = Verdicts.palette_verdicts(restored, "caster", offsets)
	_assert_true(not bool(v["for_each"][1]), "the for_each m8 is the real cleanup")
	_assert_true(bool(v["phase2"][0]),
		"the phase2 m8 opening after everything was already restored is a spacer")
	# A disabled keyframe still ADVANCES timing (enabled=false op in the stream), and
	# verdict keys line up with the played keyframe indices the score projects.
	_assert_true(v["for_each"].has(0) and v["for_each"].has(1) and v["phase2"].has(0),
		"verdicts are keyed by (phase, played keyframe index)")


## The screen wrapper folds one stream PER endpoint (top = start bytes, bottom = end
## bytes) and a spacer must be disable-equivalent on BOTH: a re-set Gradient whose TOP
## repeats but whose BOTTOM differs is real. The identity no-op Blend (screen's
## disable byte-swap) is a spacer by equivalence — no special-casing.
func _test_screen_wrapper_ands_both_endpoints() -> void:
	var ed = ScreenDataClass.from_json({
		"for_each": {"context": "for_each", "max_keyframe": 5, "keyframes": [
			{"index": 0, "duration_frames": 8, "mode": "FADE", "time_value": 1,
				"start_r": 10, "start_g": 20, "start_b": 30,
				"end_r": 40, "end_g": 50, "end_b": 60},
			{"index": 1, "duration_frames": 8, "mode": "FADE", "time_value": 1,
				"start_r": 10, "start_g": 20, "start_b": 30,
				"end_r": 99, "end_g": 50, "end_b": 60},
			{"index": 2, "duration_frames": 8, "mode": "FADE", "time_value": 1,
				"start_r": 10, "start_g": 20, "start_b": 30,
				"end_r": 99, "end_g": 50, "end_b": 60},
			{"index": 3, "duration_frames": 12, "mode": "TINT", "blend_mode": 0,
				"time_value": 1, "start_r": 0, "start_g": 0, "start_b": 0},
		]},
	})
	var v: Dictionary = Verdicts.screen_verdicts(ed, {"for_each": 8})
	_assert_true(not bool(v["for_each"][1]),
		"a Gradient repeating TOP but changing BOTTOM is real (endpoint AND)")
	_assert_true(bool(v["for_each"][2]),
		"a Gradient repeating BOTH settled endpoints is a spacer")
	_assert_true(bool(v["for_each"][3]),
		"the identity no-op Blend (the disable byte-swap) is a spacer by equivalence")


# --- fixtures ---------------------------------------------------------------

## One screen Gradient op: an absolute set of this endpoint to `rgb` bytes, ramping
## linearly over `dur` frames from `at`.
func _grad(rgb: Array, at: int, dur: int) -> Dictionary:
	return {"gradient": true, "at": at, "dur": dur, "r": rgb[0], "g": rgb[1], "b": rgb[2]}

## One palette-profile op tuple: mode + raw Δ bytes at an absolute frame. `time` is
## the raw Time byte (palette ramps over the fast/slow DDA tables); default 1 → 8 frames.
func _op(mode: int, rgb: Array, at: int, time: int = 1, enabled: bool = true) -> Dictionary:
	return {"enabled": enabled, "at": at, "mode": mode,
		"r": rgb[0], "g": rgb[1], "b": rgb[2], "time": time}


# --- asserts ----------------------------------------------------------------

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
