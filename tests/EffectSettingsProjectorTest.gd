extends Node
## TDD guard (#271) for EffectSettingsProjector — the effect-level global-settings surface.
## Its first (and today only) section is "Timeline": the three phase-duration int rows
## (phase1_duration / spawn_delay / phase2_delay), each an editable cell addressing the
## `timeline_header` channel and seeded to the live value. sections() returns an ARRAY so
## #272 (flags) / #270 (time scale) append as pure additions later. Guards the row shape the
## manifest guard (shape:edit + channel) and the inspector's F1 int kit both consume.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectSettingsProjectorTest.tscn

const EffectSettingsProjector = preload("res://src/effects/studio/EffectSettingsProjector.gd")
const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_timeline_section_present_with_three_rows()
	_test_rows_are_editable_on_timeline_header_channel()
	_test_rows_seed_live_values_and_address_correct_fields()
	_test_spawn_delay_row_carries_multi_target_hint()
	_test_no_timeline_yields_no_section()
	_test_flags_section_present_with_bitflags_row()
	_test_flags_row_declares_four_engine_bits()
	_test_flags_row_seeds_raw_byte_so_ignored_bits_ride()
	_test_no_flags_yields_no_flags_section()
	_test_flags_section_appears_even_without_a_timeline()
	_test_script_section_swappable_is_a_choice_on_the_channel()
	_test_script_section_seeds_current_pattern_index()
	_test_script_section_readonly_for_code_format()
	_test_script_section_readonly_for_custom()
	_test_no_script_ops_yields_no_script_section()

	print("\n=== EffectSettingsProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSettingsProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSettingsProjectorTest")
		get_tree().quit(0)


func _effect():
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.new()
	ed.timeline.phase1_duration = 96
	ed.timeline.spawn_delay = 10
	ed.timeline.phase2_delay = 8
	ed.timeline.header = {"phase1_duration": 96, "spawn_delay": 10, "phase2_delay": 8}
	return ed


## E019-shaped flags fixture: raw byte 0x23 (bits 0,1 ignored + bit5 time_scale_pattern1).
func _effect_with_flags(flags_byte: int = 0x23):
	var ed = _effect()
	ed.flags = {
		"flags_byte": flags_byte,
		"terrain_height_adjust": (flags_byte & 0x08) != 0,
		"audio_fade": (flags_byte & 0x10) != 0,
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}
	return ed


func _op(offset: int, opcode: int, name: String, flags: int, size: int, arg1 = null, arg2 = null) -> Dictionary:
	var d := {"offset": offset, "opcode": opcode, "name": name, "flags": flags, "size": size}
	if arg1 != null:
		d["arg1"] = arg1
	if arg2 != null:
		d["arg2"] = arg2
	return d


# E001-shaped 3-phase root (texture_page 16, no callbacks), the canonical swappable case.
func _e001_root() -> Array:
	return [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 31, "branch_target_type", 0, 4, 34),
		_op(8, 30, "branch_anim_done_complex", 0, 4, 22),
		_op(12, 41, "process_timeline_frame", 0, 4, 36),
		_op(16, 37, "update_all_particles", 0, 2),
		_op(18, 0, "goto_yield", 0, 4, 8),
		_op(22, 37, "update_all_particles", 0, 2),
		_op(24, 22, "branch_count_eq", 0, 6, 0, 34),
		_op(30, 0, "goto_yield", 0, 4, 22),
		_op(34, 4, "end", 0, 2),
	]


func _effect_with_script(ops: Array, is_code: bool = false):
	var ed = _effect()
	ed.script_ops = ops
	ed.script_code_format = is_code
	return ed


func _sections(ed):
	return EffectSettingsProjector.sections(InspectionTarget.effect_settings(), ed, {})


func _script_section(ed):
	for sec in _sections(ed):
		if str(sec.get("title", "")) == "Script Pattern":
			return sec
	return {}


func _flags_section(ed):
	for sec in _sections(ed):
		if str(sec.get("title", "")) == "Flags":
			return sec
	return {}


func _timeline_section(ed):
	for sec in _sections(ed):
		if str(sec.get("title", "")) == "Timeline":
			return sec
	return {}


func _test_timeline_section_present_with_three_rows() -> void:
	var sec = _timeline_section(_effect())
	_assert_true(not sec.is_empty(), "a Timeline section is projected")
	_assert_eq(sec.get("fields", []).size(), 3, "the Timeline section has the 3 duration rows")


func _test_rows_are_editable_on_timeline_header_channel() -> void:
	var sec = _timeline_section(_effect())
	for f in sec.get("fields", []):
		_assert_eq(f.get("shape", ""), "edit", "%s is an editable row" % f.get("name", "?"))
		_assert_eq(f.get("editor", ""), "int", "%s uses the int kit" % f.get("name", "?"))
		_assert_eq(f.get("field_ref", {}).get("channel", ""), "timeline_header",
			"%s addresses the timeline_header channel" % f.get("name", "?"))


func _test_rows_seed_live_values_and_address_correct_fields() -> void:
	var by_field := {}
	for f in _timeline_section(_effect()).get("fields", []):
		by_field[str(f.get("field_ref", {}).get("field", ""))] = f
	_assert_eq(by_field.get("phase1_duration", {}).get("value"), 96, "phase1 row seeds the live value")
	_assert_eq(by_field.get("spawn_delay", {}).get("value"), 10, "spawn_delay row seeds the live value")
	_assert_eq(by_field.get("phase2_delay", {}).get("value"), 8, "phase2_delay row seeds the live value")


## spawn_delay is runtime-target-dependent (not dead), so it gets an honest hint rather than
## relevance gating — the author must not mistake a no-visible-effect for a no-op byte.
func _test_spawn_delay_row_carries_multi_target_hint() -> void:
	for f in _timeline_section(_effect()).get("fields", []):
		if str(f.get("field_ref", {}).get("field", "")) == "spawn_delay":
			_assert_true(str(f.get("tooltip", "")).to_lower().contains("multiple target"),
				"spawn_delay row hints it applies with multiple targets")
			return
	_assert_true(false, "spawn_delay row exists")


func _test_no_timeline_yields_no_section() -> void:
	var ed = EffectDataClass.new()
	ed.timeline = null
	_assert_eq(_sections(ed).size(), 0, "no timeline → no settings sections")


func _test_flags_section_present_with_bitflags_row() -> void:
	var sec = _flags_section(_effect_with_flags())
	_assert_true(not sec.is_empty(), "a Flags section is projected")
	_assert_eq(sec.get("fields", []).size(), 1, "the Flags section has one bitflags row")
	var f = sec.get("fields", [])[0] if not sec.get("fields", []).is_empty() else {}
	_assert_eq(f.get("shape", ""), "edit", "the flags row is editable")
	_assert_eq(f.get("editor", ""), "bitflags", "the flags row uses the bitflags kit")
	_assert_eq(f.get("field_ref", {}).get("channel", ""), "effect_flags",
		"the flags row addresses the effect_flags channel")
	_assert_eq(f.get("field_ref", {}).get("field", ""), "flags_byte",
		"the flags row edits flags_byte")


## All four engine-read bits (bit3 terrain / bit4 audio-fade / bit5 3-phase / bit6 1-phase)
## are declared with their masks; the ignored bits (0-2, 7) get NO checkbox.
func _test_flags_row_declares_four_engine_bits() -> void:
	var sec = _flags_section(_effect_with_flags())
	if sec.get("fields", []).is_empty():
		_assert_true(false, "flags row exists")
		return
	var bits: Array = sec["fields"][0].get("bits", [])
	_assert_eq(bits.size(), 4, "exactly the four engine-read bits are surfaced")
	var masks := {}
	for b in bits:
		masks[int(b.get("mask", 0))] = str(b.get("label", ""))
	_assert_true(masks.has(0x08), "bit3 (0x08) terrain-adjust is a checkbox")
	_assert_true(masks.has(0x10), "bit4 (0x10) audio-fade is a checkbox")
	_assert_true(masks.has(0x20), "bit5 (0x20) time-scale 3-phase is a checkbox")
	_assert_true(masks.has(0x40), "bit6 (0x40) time-scale 1-phase is a checkbox")
	for mask in masks:
		_assert_true(str(masks[mask]) != "", "bit 0x%X carries a label" % mask)


## The row is seeded with the WHOLE raw byte (0x23), not just the four bools — so the
## bitflags editor recomputes over it and the ignored bits 0,1 survive a toggle (ADR-0092).
func _test_flags_row_seeds_raw_byte_so_ignored_bits_ride() -> void:
	var sec = _flags_section(_effect_with_flags(0x23))
	if sec.get("fields", []).is_empty():
		_assert_true(false, "flags row exists")
		return
	_assert_eq(int(sec["fields"][0].get("value", -1)), 0x23,
		"the flags row seeds the raw byte 0x23 (ignored bits 0,1 included)")


func _test_no_flags_yields_no_flags_section() -> void:
	# _effect() has an empty flags dict → no Flags section (but the Timeline one still shows).
	_assert_true(_flags_section(_effect()).is_empty(), "no flags block → no Flags section")


func _test_flags_section_appears_even_without_a_timeline() -> void:
	var ed = _effect_with_flags()
	ed.timeline = null  # a flags-only effect still shows the Flags section
	_assert_true(not _flags_section(ed).is_empty(),
		"Flags section is independent of the Timeline section")


## A swappable (DATA + canonical) script gets a "Script Pattern" section: a `choice`
## edit row on the script_pattern channel, choices ["3-phase", "1-phase"].
func _test_script_section_swappable_is_a_choice_on_the_channel() -> void:
	var sec = _script_section(_effect_with_script(_e001_root(), false))
	_assert_true(not sec.is_empty(), "a Script Pattern section is projected for a swappable script")
	if sec.get("fields", []).is_empty():
		_assert_true(false, "script section has a field")
		return
	var f = sec["fields"][0]
	_assert_eq(f.get("shape", ""), "edit", "the pattern row is editable")
	_assert_eq(f.get("editor", ""), "choice", "the pattern row is a choice selector")
	_assert_eq(f.get("field_ref", {}).get("channel", ""), "script_pattern",
		"the pattern row addresses the script_pattern channel")
	var choices: Array = f.get("choices", [])
	_assert_eq(choices.size(), 2, "two pattern choices")
	_assert_eq(str(choices[0]), "3-phase", "choice 0 is 3-phase")
	_assert_eq(str(choices[1]), "1-phase", "choice 1 is 1-phase")


func _test_script_section_seeds_current_pattern_index() -> void:
	var sec = _script_section(_effect_with_script(_e001_root(), false))
	if sec.get("fields", []).is_empty():
		_assert_true(false, "script section has a field")
		return
	# E001 is 3-phase -> choice index 0 is pre-selected.
	_assert_eq(int(sec["fields"][0].get("value", -1)), 0, "the choice seeds the current pattern (3-phase = 0)")


## A CODE-format effect shows the mode READ-ONLY (a const row) with a reason — not a choice.
func _test_script_section_readonly_for_code_format() -> void:
	var sec = _script_section(_effect_with_script(_e001_root(), true))
	_assert_true(not sec.is_empty(), "a Script Pattern section still shows for CODE-format (read-only)")
	if sec.get("fields", []).is_empty():
		_assert_true(false, "script section has a field")
		return
	var f = sec["fields"][0]
	_assert_true(f.get("shape", "") != "edit", "the CODE-format pattern row is NOT editable")
	_assert_eq(str(f.get("value", "")), "3-phase", "it shows the detected mode")
	_assert_true(str(f.get("tooltip", "")).contains("CODE"), "the read-only reason mentions CODE")


func _test_script_section_readonly_for_custom() -> void:
	# E306-shaped Custom: op41 but no op31 -> not swappable, read-only.
	var custom := [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 30, "branch_anim_done_complex", 0, 4, 18),
		_op(8, 41, "process_timeline_frame", 0, 4, 32),
		_op(12, 4, "end", 0, 2),
	]
	var sec = _script_section(_effect_with_script(custom, false))
	if sec.get("fields", []).is_empty():
		_assert_true(false, "custom script still shows a read-only section")
		return
	_assert_true(sec["fields"][0].get("shape", "") != "edit", "a Custom pattern is read-only")
	_assert_eq(str(sec["fields"][0].get("value", "")), "Custom", "shows Custom")


func _test_no_script_ops_yields_no_script_section() -> void:
	# _effect() has no script_ops -> no Script Pattern section (Timeline still shows).
	_assert_true(_script_section(_effect()).is_empty(), "no script_ops → no Script Pattern section")


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
