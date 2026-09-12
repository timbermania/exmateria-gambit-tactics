extends Node
## TDD guard for FedsInstrumentMeta.gd (ADR-0085 amendment: instrument-chip loop
## verdict). loop_summary_of() is PURE over the raw ADPCM loop facts and covers every
## branch with synthetic dicts; of()/describe() read the committed
## assets/feds_instrument_meta.json (id 67 Tubular Bells sustains, id 1 Empty/Silent).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/FedsInstrumentMetaTest.tscn

const Meta = preload("res://src/effects/studio/FedsInstrumentMeta.gd")
const Semantics = preload("res://src/effects/studio/FedsParamSemantics.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const FedsBankScript = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_explicit_loop_start_reads_exact_tail()
	_test_loop_repeat_only_reads_heuristic_tail()
	_test_loop_repeat_short_sample_loops_whole()
	_test_no_loop_is_one_shot()
	_test_null_and_empty_have_no_verdict()
	_test_committed_tubular_bells_sustains()
	_test_committed_empty_silent_reads_silent()
	_test_describe_leads_with_the_name()
	_test_instrument_descriptor_exposes_value_detail()
	_test_enum_cell_renders_value_detail_and_updates_on_selection()
	_test_e001_carries_a_sustaining_instrument_event()
	_finish()


func _test_explicit_loop_start_reads_exact_tail() -> void:
	var s := Meta.loop_summary_of({
		"sample_size": 2000, "has_explicit_loop_start": true,
		"loop_offset_bytes": 1600, "has_loop_repeat": true, "is_null": false})
	_assert_true(s.begins_with("Sustains"), "explicit loop → Sustains")
	_assert_true(s.contains("400"), "explicit loop tail = size − offset (2000−1600)")


func _test_loop_repeat_only_reads_heuristic_tail() -> void:
	# size > 0x1010 (4112): loops a ~4112-byte tail, flagged as a heuristic.
	var s := Meta.loop_summary_of({
		"sample_size": 6000, "has_explicit_loop_start": false,
		"loop_offset_bytes": -1, "has_loop_repeat": true, "is_null": false})
	_assert_true(s.begins_with("Sustains"), "loop-repeat → Sustains")
	_assert_true(s.to_lower().contains("heuristic"), "heuristic loop point is labeled honestly")


func _test_loop_repeat_short_sample_loops_whole() -> void:
	# size <= 0x1010: the heuristic loop point clamps to start → whole-sample loop.
	var s := Meta.loop_summary_of({
		"sample_size": 2288, "has_explicit_loop_start": false,
		"loop_offset_bytes": -1, "has_loop_repeat": true, "is_null": false})
	_assert_true(s.begins_with("Sustains"), "short loop-repeat → Sustains")
	_assert_true(s.to_lower().contains("whole"), "short sample loops the whole sample")


func _test_no_loop_is_one_shot() -> void:
	var s := Meta.loop_summary_of({
		"sample_size": 512, "has_explicit_loop_start": false,
		"loop_offset_bytes": -1, "has_loop_repeat": false, "is_null": false})
	_assert_true(s.begins_with("One-shot"), "no loop flags → One-shot")


func _test_null_and_empty_have_no_verdict() -> void:
	_assert_eq(Meta.loop_summary_of({}), "", "empty meta → no verdict")
	_assert_eq(Meta.loop_summary_of({"is_null": true, "sample_size": 0}), "",
		"null instrument → no verdict")


func _test_committed_tubular_bells_sustains() -> void:
	var m := Meta.of(67)
	_assert_false(m.is_empty(), "id 67 present in committed table")
	_assert_eq(int(m.get("sample_size", 0)), 2288, "id 67 sample_size (empirical)")
	_assert_true(Meta.loop_summary_of(m).begins_with("Sustains"), "id 67 sustains")


func _test_committed_empty_silent_reads_silent() -> void:
	# id 1 = "Empty/Silent · Silence": describe() leads with the silent tell, not a loop.
	var d := Meta.describe(1)
	_assert_true(d.to_lower().contains("silent"), "id 1 describe reads silent")


func _test_describe_leads_with_the_name() -> void:
	var d := Meta.describe(67)
	_assert_true(d.contains("Tubular Bells"), "describe names the instrument")
	_assert_true(d.contains("Sustains"), "describe carries the loop verdict")


func _test_instrument_descriptor_exposes_value_detail() -> void:
	# The 0xAC Instrument cell carries a per-value detail Callable the inspector shows
	# beside the dropdown; it resolves the SELECTED id, not the byte the descriptor was
	# built for (param_index).
	var d := Semantics.descriptor(0xAC, 0)
	var detail = d.get("value_detail")
	_assert_true(detail is Callable, "0xAC descriptor exposes a value_detail Callable")
	if detail is Callable:
		var text := String(detail.call(67))
		_assert_true(text.contains("Tubular Bells") and text.contains("Sustains"),
			"value_detail.call(67) describes the sustaining bell")
		_assert_true(String(detail.call(1)).to_lower().contains("silent"),
			"value_detail.call(1) reads silent")


func _test_enum_cell_renders_value_detail_and_updates_on_selection() -> void:
	# An enum cell carrying a `value_detail` Callable draws a dim detail Label beside
	# the dropdown, seeded to the current value and refreshed on selection. A plain
	# stand-in callable isolates the render wiring from FedsInstrumentMeta.
	var insp = Inspector.new()
	add_child(insp)
	var cell := {"name": "Instrument", "shape": "edit", "editor": "enum",
		"value": 67,
		"choices": [{"value": 67, "label": "67 — Tubular Bells"},
					{"value": 1, "label": "1 — Empty/Silent"}],
		"value_detail": func(v: int) -> String: return "V=%d" % v,
		"field_ref": {"channel": "sound_def", "kind": "byte", "offset": 5, "pair_idx": 0}}
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass,
		func(_refs, _col): return Color.BLACK)
	var hints: Array = insp.enum_detail_hints()
	_assert_eq(hints.size(), 1, "a value_detail enum cell renders one detail hint")
	if hints.is_empty():
		insp.free()
		return
	_assert_eq(str(hints[0].text), "V=67", "detail seeds to the current value")
	# Selecting the other id refreshes the detail in place.
	var enums: Array = insp.enum_widgets()
	enums[0].item_selected.emit(1)  # index 1 == value 1
	_assert_eq(str(hints[0].text), "V=1", "detail refreshes on selection")
	insp.free()


func _test_e001_carries_a_sustaining_instrument_event() -> void:
	# Dynamic close (ADR-0085 re-conclusions-static-rooted-dynamic-validated): the real
	# E001 (CURE) FEDS stream contains the AC 67 Tubular Bells instrument event whose
	# sustaining sample this feature explains. Decode it and confirm the verdict lands.
	var bank = FedsBankScript.load_from_file("res://authored_effects/E001.feds.bin")
	_assert_true(bank != null, "E001 feds bank loads")
	if bank == null:
		return
	var found_67 := false
	for track_idx in range(4):
		for evt in SMD.decode_track(bank.get_track_bytes(track_idx)):
			if evt is SMD.OpcodeEvent and evt.opcode == 0xAC \
					and evt.params.size() > 0 and evt.params[0] == 67:
				found_67 = true
	_assert_true(found_67, "E001 selects instrument 67 (Tubular Bells) somewhere in its pair")
	var d := Meta.describe(67)
	_assert_true(d.contains("Tubular Bells") and d.contains("Sustains"),
		"E001's instrument-67 chip would read 'Sustains'")


func _finish() -> void:
	print("\n=== FedsInstrumentMetaTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FedsInstrumentMetaTest")
		get_tree().quit(1)
	else:
		print("[PASS] FedsInstrumentMetaTest")
		get_tree().quit(0)


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


func _assert_false(cond: bool, label: String) -> void:
	if not cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected false" % label)
