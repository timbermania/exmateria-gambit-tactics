extends Node
## TDD guard for Effect Studio PALETTE / field-tint authoring (Subsystem 1, #266) — the
## palette colour tracks (affected_units / caster / target x phases) made editable through
## the same #255 choke point the screen pilot established, reusing the F1 shared kit (#264).
## Palette RGB is an absolute UNSIGNED colour (colour = raw/255), so — unlike the signed
## screen Blend — it reuses the plain `gradient_color` picker (three direct byte writes); the
## blend mode is a value-carrying `enum`. Seams guarded here:
##
##   (1) PaletteTweenProjector.sections(span) emits an EDITABLE "Tint" cell (shape "edit",
##       editor "gradient_color") carrying per-component field_refs {channel:"palette",
##       context, channel_name, event_index, field:"r"|"g"|"b"} — palette's TWO-dimensional
##       address (phase context AND channel_name) — plus an editable "Blend mode" enum cell.
##   (2) EffectKeyframeInspector renders the Tint cell as ONE seeded RGB picker (three byte
##       writes on change) and the Blend mode as a value-carrying enum; seeding fires no edit.
##   (3) PaletteChannel (via EffectEditSession.apply_edit) writes the raw byte on the live
##       PaletteData.Keyframe, reports invalidates_sim=false (read-live → repaint in place),
##       preserves the ctrl enabled-bit on a blend-mode edit, and undo restores.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioPaletteEditTest.tscn

const Projector = preload("res://src/effects/studio/PaletteTweenProjector.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const TintSolver = preload("res://src/effects/studio/PaletteTintSolver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_projector_emits_editable_tint_and_blend_cells()
	_test_inspector_renders_seeded_picker_and_enum()
	_test_encoder_writes_rgb_read_live_and_undoes()
	_test_blend_mode_edit_preserves_enabled_bit()
	_test_enabled_toggle_is_a_ctrl_bit7_rmw()
	_test_signed_delta_row_seeds_signed_writes_raw_and_resets_to_noop()
	_test_a_tint_edit_materializes_into_the_delta_row()

	print("\n=== EffectStudioPaletteEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioPaletteEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioPaletteEditTest")
		get_tree().quit(0)


# --- Seam 1: projector emits the editable palette cells --------------------

func _test_projector_emits_editable_tint_and_blend_cells() -> void:
	var span := _span("phase1", "caster", 3, Vector3i(10, 20, 30), 5)
	var secs := Projector.sections(span)

	var tint := _field(secs[0], "Tint")
	_assert_eq(tint.get("shape", ""), "edit", "the Tint cell is editable")
	# ADR-0087: the tint byte is a signed Δ, so Tint is a WYSIWYG result-picker, not the
	# retired absolute-unsigned gradient_color.
	_assert_eq(tint.get("editor", ""), "target_color", "Tint is a result-picker (target_color) editor")
	var refs: Dictionary = tint.get("field_refs", {})
	_assert_true(refs.get("r", {}) == {"channel": "palette", "context": "phase1", "channel_name": "caster", "event_index": 3, "field": "r"},
		"the R field_ref carries palette's two-dim address (phase + channel_name) and field r")
	_assert_eq(refs.get("g", {}).get("field", ""), "g", "the G field_ref addresses field g")
	_assert_eq(refs.get("b", {}).get("field", ""), "b", "the B field_ref addresses field b")
	# The seed is the colour the surface CURRENTLY reaches — the forward fold of the stored
	# bytes over the mid-grey reference (NOT raw/255), for mode 5 (dim ½ + add over base).
	_assert_eq(tint.get("seed", Color.BLACK), TintSolver.result(5, 10, 20, 30),
		"the Tint picker seed is the forward fold of the stored bytes")

	var blend := _field(secs[0], "Blend mode")
	_assert_eq(blend.get("shape", ""), "edit", "the Blend mode cell is editable")
	_assert_eq(blend.get("editor", ""), "enum", "Blend mode is a value-carrying enum")
	_assert_eq(int(blend.get("value", -1)), 5, "the enum is seeded to the keyframe's blend mode")
	_assert_eq(blend.get("choices", []).size(), 11, "the enum offers the 11 palette blend modes (0-10)")
	_assert_eq(blend.get("field_ref", {}).get("channel", ""), "palette", "the enum lowers through the palette channel")
	_assert_eq(blend.get("field_ref", {}).get("field", ""), "blend_mode", "the enum addresses the blend_mode field")


# --- Seam 2: inspector renders the palette editors -------------------------

func _test_inspector_renders_seeded_picker_and_enum() -> void:
	var span := _span("for_each", "affected_units", 0, Vector3i(40, 80, 120), 2)
	var secs := Projector.sections(span)
	var insp = Inspector.new()
	add_child(insp)

	var mutations: Array = []
	var picks: Array = []
	insp.show_target(Target.span("palette:for_each:affected_units#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): mutations.append([ref, raw]),
		func(refs, col): picks.append([refs, col]); return Color(0.5, 0.5, 0.5))

	# ADR-0087: the Tint is a result-picker (pick_widgets), NOT a direct-byte gradient_color.
	var pickers: Array = insp.pick_widgets()
	_assert_eq(pickers.size(), 1, "the Tint cell renders ONE result-picker")
	_assert_eq(insp.gradient_pickers().size(), 0, "the retired gradient_color path renders nothing")
	var enums: Array = insp.enum_widgets()
	_assert_eq(enums.size(), 1, "the Blend mode cell renders ONE enum dropdown")
	if pickers.is_empty() or enums.is_empty():
		return
	_assert_true(pickers[0].color.is_equal_approx(TintSolver.result(2, 40, 80, 120)),
		"the picker is seeded to the forward fold (mode 2) of the stored bytes")
	_assert_eq(pickers[0].edit_alpha, false, "the tint picker edits RGB only")
	_assert_eq(mutations.size(), 0, "seeding fires NO spurious write")
	_assert_eq(picks.size(), 0, "seeding fires NO spurious pick")

	# Pick a target colour → the host back-solves + writes (not the inspector); the inspector
	# routes ONE pick call carrying the field_refs + the picked colour, and repaints "actual".
	var picked := Color(0.8, 0.4, 0.2)
	pickers[0].color = picked
	pickers[0].color_changed.emit(picked)
	_assert_eq(mutations.size(), 0, "a tint pick does NOT fan direct byte writes (the host solves)")
	_assert_eq(picks.size(), 1, "one tint pick routes exactly one solve request")
	if not picks.is_empty():
		_assert_eq(picks[0][0].get("r", {}).get("field", ""), "r", "the pick carries the r field_ref")
		_assert_true((picks[0][1] as Color).is_equal_approx(picked), "the pick carries the picked target colour")

	# Change the blend mode enum → one mutate carrying the selected code (its VALUE, not index).
	mutations.clear()
	var ob = enums[0]
	var idx7: int = ob.get_item_index(7)
	ob.selected = idx7
	ob.item_selected.emit(idx7)
	_assert_eq(mutations.size(), 1, "a blend-mode change fans exactly one write")
	if not mutations.is_empty():
		_assert_eq(mutations[0][0].get("field", ""), "blend_mode", "the write addresses blend_mode")
		_assert_eq(mutations[0][1], 7, "the enum fans the selected CODE (7), not the item index")

	# The Enabled toggle is a RENDERED, WIRED choice widget — toggling it Disabled fans a real
	# `enabled`=0 edit through the same mutate path (not just a projector field on paper).
	var choices: Array = insp.choice_widgets()
	_assert_eq(choices.size(), 1, "the Enabled toggle renders ONE choice dropdown")
	if not choices.is_empty():
		_assert_eq(int(choices[0].selected), 1, "seeded to the keyframe's Enabled state (on)")
		mutations.clear()
		choices[0].selected = 0
		choices[0].item_selected.emit(0)
		_assert_eq(mutations.size(), 1, "toggling Enabled fans exactly one write")
		if not mutations.is_empty():
			_assert_eq(mutations[0][0].get("field", ""), "enabled", "…addressing the enabled bit")
			_assert_eq(int(mutations[0][1]), 0, "…with the Disabled index (0)")


# --- Seam 3: encoder writes the raw byte, read-live, and undoes -------------

func _test_encoder_writes_rgb_read_live_and_undoes() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = data.palette.get_channel("for_each", "affected_units").get_keyframe(0)
	var before: int = kf.rgb.x

	var ref := {"channel": "palette", "context": "for_each", "channel_name": "affected_units", "event_index": 0, "field": "r"}
	var res: Dictionary = session.apply_edit(ref, 200)

	_assert_eq(res.get("invalidates_sim", true), false, "a palette colour edit is read-live (no re-seek)")
	_assert_true(res.get("faithful", {}).get("ok", false), "an in-range byte is faithfully encodable")
	_assert_eq(kf.rgb.x, 200, "the encoder writes the raw R byte onto the live keyframe")
	_assert_eq(res.get("before_raw", -1), before, "the snapshot records the pre-edit byte")

	_assert_true(session.undo(), "the edit is undoable")
	_assert_eq(kf.rgb.x, before, "undo restores the original R byte through the same dispatch path")


# --- Seam 4: blend-mode edit is a ctrl read-modify-write -------------------

func _test_blend_mode_edit_preserves_enabled_bit() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = data.palette.get_channel("for_each", "affected_units").get_keyframe(0)
	# Seed: enabled (bit 7) + blend mode 5 → ctrl 0x85.
	kf.ctrl = 0x85
	kf.enabled = true
	kf.blend_mode = 5

	var ref := {"channel": "palette", "context": "for_each", "channel_name": "affected_units", "event_index": 0, "field": "blend_mode"}
	session.apply_edit(ref, 3)

	_assert_eq(kf.blend_mode, 3, "the blend mode is rewritten")
	_assert_eq(kf.ctrl, 0x83, "ctrl is a read-modify-write: enabled bit-7 preserved, bits 0-6 = 3")
	_assert_true(kf.enabled, "the enabled flag survives a blend-mode edit")


# --- Seam 5: the enabled toggle is a ctrl bit-7 read-modify-write ----------

func _test_enabled_toggle_is_a_ctrl_bit7_rmw() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = data.palette.get_channel("for_each", "affected_units").get_keyframe(0)
	kf.ctrl = 0x85  # enabled + blend mode 5
	kf.enabled = true
	kf.blend_mode = 5

	var ref := {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": 0, "field": "enabled"}
	var res: Dictionary = session.apply_edit(ref, 0)   # DISABLE

	_assert_eq(kf.ctrl, 0x05, "disabling clears bit-7, preserving blend mode 5 (0x85 → 0x05)")
	_assert_true(not kf.enabled, "the cached enabled flag is cleared")
	_assert_eq(kf.blend_mode, 5, "the blend mode survives an enable toggle")
	_assert_eq(res.get("invalidates_sim", true), false, "the toggle is read-live (no re-seek)")
	_assert_true(res.get("invalidates_layout", false), "…but reprojects the lane (the span restyles)")

	session.apply_edit(ref, 1)   # RE-ENABLE
	_assert_eq(kf.ctrl, 0x85, "re-enabling restores bit-7 (0x05 → 0x85)")
	_assert_true(kf.enabled, "the cached enabled flag is set")

	_assert_true(session.undo(), "the toggle is undoable")
	_assert_eq(kf.ctrl, 0x05, "undo restores the disabled ctrl")


# --- Seam 6: the signed-Δ row seeds signed, writes raw, and resets to no-op ---

func _test_signed_delta_row_seeds_signed_writes_raw_and_resets_to_noop() -> void:
	var span := _span("for_each", "affected_units", 0, Vector3i(225, 0, 7), 0)  # −31, 0, +7 signed
	var secs := Projector.sections(span)
	var insp = Inspector.new()
	add_child(insp)

	var mutations: Array = []
	insp.show_target(Target.span("palette:for_each:affected_units#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): mutations.append([ref, raw]),
		func(_refs, _col): return Color.BLACK)

	var boxes: Array = insp.signed_rgb_widgets()
	_assert_eq(boxes.size(), 3, "the signed-Δ row renders three spinboxes (R/G/B)")
	if boxes.size() < 3:
		return
	# Seeded to the SIGNED interpretation of the raw bytes (225 → −31).
	_assert_eq(int(boxes[0].value), -31, "R spinbox shows the signed delta (225 → −31)")
	_assert_eq(int(boxes[1].value), 0, "G spinbox shows 0")
	_assert_eq(int(boxes[2].value), 7, "B spinbox shows +7")
	_assert_eq(mutations.size(), 0, "seeding fires no spurious write")

	# Typing a signed value fans the RAW byte (−16 → 240) to the r field. (SpinBox .value=
	# emits value_changed on its own — no explicit emit, else it double-fires.)
	boxes[0].value = -16
	_assert_eq(mutations.size(), 1, "a signed-Δ edit fans exactly one write")
	_assert_eq(mutations[0][0].get("field", ""), "r", "…addressing the r byte")
	_assert_eq(int(mutations[0][1]), 240, "…as the raw byte (−16 & 0xFF = 240)")

	# The "No tint" reset zeros all three channels — the unambiguous no-op (Δ = 0,0,0).
	mutations.clear()
	var btn: Button = insp.signed_rgb_reset_button()
	_assert_true(btn != null, "the row exposes a No-tint reset")
	if btn == null:
		return
	btn.pressed.emit()
	_assert_eq(mutations.size(), 3, "the reset fans three writes (one per channel)")
	var by_field := {}
	for m in mutations:
		by_field[m[0].get("field", "")] = int(m[1])
	_assert_eq(by_field.get("r", -1), 0, "reset writes r = 0")
	_assert_eq(by_field.get("g", -1), 0, "reset writes g = 0")
	_assert_eq(by_field.get("b", -1), 0, "reset writes b = 0")


# --- Seam 7: the +/- deltas are the source of truth — any edit MATERIALIZES into them ---

## The signed-Δ row is the single source of truth: whatever sets the bytes (the picker, or the
## No-tint reset) refreshes IN PLACE so the boxes always show the current delta and the picker's
## swatch shows the current result. refresh_palette_tint pushes new bytes to the widgets without
## re-rendering (so a live picker/spinbox isn't destroyed). update_picker gates whether the
## picker colour is also moved (true when the picker is NOT the source, e.g. after a +/- / reset).
func _test_a_tint_edit_materializes_into_the_delta_row() -> void:
	var span := _span("for_each", "affected_units", 0, Vector3i(0, 0, 0), 0)
	var insp = Inspector.new()
	add_child(insp)
	insp.show_target(Target.span("palette:for_each:affected_units#0"),
		[], Projector.sections(span),
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass, func(_refs, _col): return Color.BLACK)

	var boxes: Array = insp.signed_rgb_widgets()
	var pickers: Array = insp.pick_widgets()
	_assert_eq(boxes.size(), 3, "the delta row is present")
	_assert_eq(pickers.size(), 1, "the picker is present")
	if boxes.size() < 3 or pickers.is_empty():
		return

	# A pick materialized as Δ = (240, 0, 16) → the boxes show the SIGNED delta, in place.
	insp.refresh_palette_tint(Vector3i(240, 0, 16), Color(0.2, 0.3, 0.4), false)
	_assert_eq(int(boxes[0].value), -16, "the pick materializes into the R delta box (240 → −16)")
	_assert_eq(int(boxes[1].value), 0, "…G box")
	_assert_eq(int(boxes[2].value), 16, "…B box")
	_assert_eq(insp.actual_swatch().color, Color(0.2, 0.3, 0.4), "the actual swatch shows the folded result")
	_assert_true(not pickers[0].color.is_equal_approx(Color(0.2, 0.3, 0.4)),
		"update_picker=false leaves the picker (its own value) alone — it was the source")

	# A No-tint / +/- edit (picker is NOT the source) also moves the picker colour to the result.
	insp.refresh_palette_tint(Vector3i(0, 0, 0), Color(0.48, 0.48, 0.48), true)
	_assert_eq(int(boxes[0].value), 0, "No tint zeroes the R box")
	_assert_true(pickers[0].color.is_equal_approx(Color(0.48, 0.48, 0.48)),
		"update_picker=true moves the picker colour to 'whatever no tint is'")


# --- fixtures -------------------------------------------------------------

func _span(phase: String, channel_name: String, kf_index: int, rgb: Vector3i, blend_mode: int) -> Dictionary:
	return {
		"phase": phase,
		"keyframe_index": kf_index,
		"color": Color(rgb.x / 255.0, rgb.y / 255.0, rgb.z / 255.0),
		"fields": {
			"channel": channel_name,
			"rgb": rgb,
			"blend_mode": blend_mode,
			"enabled": true,
			"duration_frames": 8,
		},
	}


func _fake_data() -> RefCounted:
	var pd = PaletteDataClass.from_json({
		"for_each": {
			"affected_units": {
				"context": "for_each", "channel_name": "affected_units", "max_keyframe": 2,
				"keyframes": [
					{"index": 0, "time_value": 1, "duration_frames": 8, "rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 5},
					{"index": 1, "time_value": 0, "duration_frames": 1, "rgb": [0, 0, 0], "ctrl": 0, "enabled": false, "blend_mode": 0},
				],
			},
		},
	})
	var data := _FakeData.new()
	data.palette = pd
	return data


class _FakeData extends RefCounted:
	var screen = null
	var palette = null


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
