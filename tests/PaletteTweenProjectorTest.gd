extends Node
## TDD guard for PaletteTweenProjector (ADR-0071 / ADR-0087) — the palette/field-tint
## tween's inspector projection. This guard covers the blend-mode selector's SHARED human
## labels (ADR-0087 slice 1): the value-carrying `enum` over the 11 codes reads its labels
## from the one ColorModeLabels map that screen also reads, so the two lanes cannot drift
## to different words for the same op. (The tint result-picker editor is guarded separately.)
##
## Run: <GODOT> --path . --quit-after 4 res://tests/PaletteTweenProjectorTest.tscn

const Projector = preload("res://src/effects/studio/PaletteTweenProjector.gd")
const Labels = preload("res://src/effects/studio/ColorModeLabels.gd")
const TintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_blend_mode_selector_uses_the_shared_human_labels()
	_test_tint_is_a_result_picker_not_a_gradient_color()
	_test_tint_seed_is_the_forward_fold_of_the_stored_bytes()
	_test_restore_modes_carry_no_tint_cell()
	_test_enabled_toggle_is_present_and_addresses_the_enabled_bit()
	_test_signed_delta_row_present_seeded_signed_absent_for_restores()
	_test_duration_row_is_an_editable_int()

	print("\n=== PaletteTweenProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PaletteTweenProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] PaletteTweenProjectorTest")
		get_tree().quit(0)


## The blend-mode enum selector carries all 11 codes as {value, label}, each label from the
## shared ColorModeLabels map — NOT a bare `str(code)`. Seeded to the keyframe's current mode.
func _test_blend_mode_selector_uses_the_shared_human_labels() -> void:
	var secs := Projector.sections(_palette_span(5))
	var row := _field(secs[0], "Blend mode")
	_assert_eq(row.get("editor", ""), "enum", "blend mode is a value-carrying enum")
	_assert_eq(int(row.get("value", -1)), 5, "seeded to the keyframe's current mode")
	var choices: Array = row.get("choices", [])
	_assert_eq(choices.size(), Labels.COUNT, "all 11 modes offered")
	for code in range(Labels.COUNT):
		_assert_eq(int(choices[code].get("value", -1)), code, "choice %d carries its code" % code)
		_assert_eq(str(choices[code].get("label", "")), Labels.label(code),
			"choice %d shows the shared human label, not a bare code" % code)


## The tint cell is now a WYSIWYG result-picker (`target_color`, ADR-0087), NOT the retired
## absolute-unsigned `gradient_color`. It carries three per-component write-side field_refs on
## the "palette" channel — the addresses the SOLVED bytes lower through the choke point.
func _test_tint_is_a_result_picker_not_a_gradient_color() -> void:
	var secs := Projector.sections(_palette_span(0))
	var tint := _field(secs[0], "Tint")
	_assert_eq(tint.get("shape", ""), "edit", "the Tint cell is editable")
	_assert_eq(tint.get("editor", ""), "target_color", "the Tint cell is a result-picker")
	_assert_true(tint.get("editor", "") != "gradient_color", "the absolute gradient_color reuse is retired")
	var refs: Dictionary = tint.get("field_refs", {})
	_assert_eq(refs.get("r", {}).get("channel", ""), "palette", "Tint.r writes the palette channel")
	_assert_eq(refs.get("r", {}).get("field", ""), "r", "Tint.r addresses the r byte")
	_assert_eq(refs.get("g", {}).get("field", ""), "g", "Tint.g addresses the g byte")
	_assert_eq(refs.get("b", {}).get("field", ""), "b", "Tint.b addresses the b byte")


## The picker opens on the colour the surface CURRENTLY reaches — the forward fold of the
## stored bytes over the mid-grey reference (not the raw/255 mislabel). Fixture bytes 240 =
## _sb −16, mode 0 → a darken of the reference.
func _test_tint_seed_is_the_forward_fold_of_the_stored_bytes() -> void:
	var span := _palette_span(0)
	span["fields"]["rgb"] = Vector3i(240, 240, 240)
	var tint := _field(Projector.sections(span)[0], "Tint")
	_assert_eq(tint.get("seed", Color.BLACK), TintSolver.result(0, 240, 240, 240),
		"the Tint seed is the forward fold of the stored bytes")


## Restores (modes 8/10) ignore the Δ, so the tint cell is ABSENT — a mode-shaped field set
## (a Variant), not a greyed control. The blend-mode selector and duration still show.
func _test_restore_modes_carry_no_tint_cell() -> void:
	for mode in [8, 10]:
		var names: Array = []
		for f in Projector.sections(_palette_span(mode))[0].get("fields", []):
			names.append(f.get("name", ""))
		_assert_true(not ("Tint" in names), "mode %d carries no Tint cell" % mode)
		_assert_true("Blend mode" in names, "mode %d still shows the blend-mode selector" % mode)


## The inspector exposes an editable Enabled toggle (ADR-0087 byte coverage) — the ctrl bit-7
## the model always carried but never presented. A `choice` Disabled/Enabled seeded to the
## keyframe's state, addressing the "enabled" field. Present for ALL modes (enable is
## independent of the blend mode), including the restores.
func _test_enabled_toggle_is_present_and_addresses_the_enabled_bit() -> void:
	for mode in [0, 8]:
		var span := _palette_span(mode)
		span["fields"]["enabled"] = true
		var en := _field(Projector.sections(span)[0], "Enabled")
		_assert_eq(en.get("shape", ""), "edit", "mode %d exposes an editable Enabled control" % mode)
		_assert_eq(en.get("editor", ""), "choice", "Enabled is a choice toggle")
		_assert_eq(int(en.get("value", -1)), 1, "seeded to the keyframe's enabled state (on)")
		_assert_true(en.get("choices", []) == ["Disabled", "Enabled"], "choices are Disabled/Enabled")
		var ref: Dictionary = en.get("field_ref", {})
		_assert_eq(ref.get("channel", ""), "palette", "the toggle lowers through the palette channel")
		_assert_eq(ref.get("field", ""), "enabled", "…addressing the enabled bit")


## The precise signed-Δ row (ADR-0087 byte coverage) sits beside the WYSIWYG picker: a
## `signed_rgb` editor exposing the raw delta as three SIGNED bytes so "0, 0, 0" reads
## unambiguously as no-change (the no-op the mid-grey picker can't show). It carries the raw rgb
## seed + the r/g/b write-side field_refs, and — like the picker — is ABSENT for the restores.
func _test_signed_delta_row_present_seeded_signed_absent_for_restores() -> void:
	var span := _palette_span(0)
	span["fields"]["rgb"] = Vector3i(225, 0, 7)   # −31, 0, +7 signed
	var d := _field(Projector.sections(span)[0], "Tint Δ")
	_assert_eq(d.get("shape", ""), "edit", "the signed-Δ cell is editable")
	_assert_eq(d.get("editor", ""), "signed_rgb", "…a signed_rgb editor")
	_assert_eq(d.get("seed", Vector3i.ZERO), Vector3i(225, 0, 7), "seeded with the raw rgb bytes (widget shows signed)")
	var refs: Dictionary = d.get("field_refs", {})
	_assert_eq(refs.get("r", {}).get("channel", ""), "palette", "Δ.r writes the palette channel")
	_assert_eq(refs.get("r", {}).get("field", ""), "r", "Δ.r addresses the r byte")
	_assert_eq(refs.get("g", {}).get("field", ""), "g", "Δ.g addresses the g byte")
	_assert_eq(refs.get("b", {}).get("field", ""), "b", "Δ.b addresses the b byte")

	for mode in [8, 10]:
		var names: Array = []
		for f in Projector.sections(_palette_span(mode))[0].get("fields", []):
			names.append(f.get("name", ""))
		_assert_true(not ("Tint Δ" in names), "mode %d (restore) carries no signed-Δ row" % mode)


## The Duration row is EDITABLE (ADR-0087 dec. 9) — an `int` cell whose typed value IS
## the boundary edit (the `duration` pseudo-field the channel routes to the sum-preserving
## trade). Seeded to the keyframe's duration, min 1, addressed with palette's 2-D address.
func _test_duration_row_is_an_editable_int() -> void:
	var d := _field(Projector.sections(_palette_span(0))[0], "Duration")
	_assert_eq(d.get("shape", ""), "edit", "the Duration cell is editable")
	_assert_eq(d.get("editor", ""), "int", "Duration is an int cell")
	_assert_eq(int(d.get("value", -1)), 8, "Duration seeds to the keyframe's duration_frames")
	_assert_eq(int(d.get("min", -1)), 1, "Duration floors at 1 frame")
	var ref: Dictionary = d.get("field_ref", {})
	_assert_eq(ref.get("channel", ""), "palette", "Duration lowers through the palette channel")
	_assert_eq(ref.get("field", ""), "duration", "…addressing the duration pseudo-field")
	_assert_eq(ref.get("channel_name", ""), "affected_units", "…with palette's channel_name dimension")
	_assert_eq(int(ref.get("event_index", -2)), 0, "…at the span's keyframe index")


# --- fixtures -------------------------------------------------------------

func _palette_span(mode: int) -> Dictionary:
	return {
		"phase": "phase1",
		"keyframe_index": 0,
		"fields": {
			"channel": "affected_units",
			"rgb": Vector3i(-31, -31, -31),
			"blend_mode": mode,
			"duration_frames": 8,
		},
	}


func _field(section: Dictionary, name: String) -> Dictionary:
	for f in section.get("fields", []):
		if f.get("name", "") == name:
			return f
	return {}


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
