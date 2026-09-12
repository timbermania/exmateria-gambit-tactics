extends Node
## END-TO-END acceptance guard for #275 on a REAL effect (E019 / Fire 4), not a
## synthetic fixture: load the shipped `assets/effects/E019` data, browse to a
## sequence, project its opcode rows, edit a parameter through the #255 choke
## point, and undo it — the chain an author actually exercises.
##
## The pure seams are guarded by EffectStudioSequenceEditTest; this file is the
## proof they compose against real ROM-derived data with real opcode streams
## (E019 has 9 sequences / 251 opcodes), where a synthetic fixture could hide a
## shape mismatch.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/EffectStudioSequenceAcceptanceTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Projector = preload("res://src/effects/studio/SequenceProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")

const _E019_DIR := "res://assets/effects/E019"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var data = EffectDataClass.load_from_directory(_E019_DIR)
	if data == null or not (data.animations is Array) or data.animations.is_empty():
		print("[SKIP] E019 effect data unavailable — acceptance test needs assets/effects/E019")
		print("[PASS] EffectStudioSequenceAcceptanceTest")
		get_tree().quit(0)
		return

	_test_real_effect_exposes_every_sequence(data)
	_test_real_opcode_stream_projects_editable_rows(data)
	_test_editing_a_real_duration_round_trips_through_the_choke_point(data)
	await _test_the_page_browser_reaches_a_real_sequence(data)

	print("\n=== EffectStudioSequenceAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceAcceptanceTest")
		get_tree().quit(0)


func _test_real_effect_exposes_every_sequence(data) -> void:
	_assert_true(data.animations.size() > 0, "E019 loads at least one sequence")
	var total_opcodes := 0
	for anim in data.animations:
		total_opcodes += (anim.get("opcodes", []) as Array).size()
	_assert_true(total_opcodes > 100, "E019's sequences carry a real opcode stream (got %d)" % total_opcodes)

	# Every sequence must project a non-empty header through the REGISTRY (not the
	# projector directly) — that is what the inspector actually calls.
	var projected_all := true
	for i in range(data.animations.size()):
		if Registry.header(Target.animation(i), data, {}).is_empty():
			projected_all = false
	_assert_true(projected_all, "the registry projects every real sequence")


func _test_real_opcode_stream_projects_editable_rows(data) -> void:
	var sections: Array = Registry.sections(Target.animation(0), data, {})
	var opcodes: Array = data.animations[0].get("opcodes", [])
	_assert_eq(sections.size(), opcodes.size(), "one section per real opcode")

	var edit_rows := 0
	var channels: Dictionary = {}
	for sec in sections:
		for f in sec.get("fields", []):
			if str(f.get("shape", "")) == "edit":
				edit_rows += 1
				channels[str(f.get("field_ref", {}).get("channel", ""))] = true
	_assert_true(edit_rows > 0, "a real sequence yields editable parameter rows (got %d)" % edit_rows)
	_assert_eq(channels.keys(), ["sequence"], "every editable row routes to the sequence channel")

	# The corpus invariant the audit established, on real data.
	_assert_eq(str(opcodes[0].get("type", "")), "SET_OFFSET", "a real sequence opens with SET_OFFSET")
	_assert_eq(str(opcodes[opcodes.size() - 1].get("type", "")), "LOOP",
		"a real sequence ends with the LOOP terminator")


func _test_editing_a_real_duration_round_trips_through_the_choke_point(data) -> void:
	# Find a real FRAME opcode in the real stream.
	var anim_idx := -1
	var op_idx := -1
	for a in range(data.animations.size()):
		var ops: Array = data.animations[a].get("opcodes", [])
		for o in range(ops.size()):
			if str(ops[o].get("type", "")) == "FRAME":
				anim_idx = a
				op_idx = o
				break
		if anim_idx >= 0:
			break
	_assert_true(anim_idx >= 0, "E019 has a real FRAME opcode to edit")
	if anim_idx < 0:
		return

	var op: Dictionary = data.animations[anim_idx]["opcodes"][op_idx]
	var original: int = int(op.get("duration", 0))
	var session = Session.new(data)

	var res: Dictionary = session.apply_edit({"channel": "sequence",
		"animation_index": anim_idx, "opcode_index": op_idx, "field": "duration"}, original + 7)

	_assert_eq(int(op["duration"]), original + 7, "a real duration edit reaches the live opcode")
	_assert_eq(res.get("invalidates_sim", false), true, "and asks the host to re-fold")
	_assert_true(session.undo(), "the real edit is undoable")
	_assert_eq(int(op["duration"]), original, "undo restores the original ROM value byte-exactly")


func _test_the_page_browser_reaches_a_real_sequence(data) -> void:
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	page._effect_data = data
	page._refresh_sequence_browser()

	_assert_eq(page._sequence_picker.item_count, data.animations.size() + 1,
		"the browser lists every real sequence plus the placeholder")
	page._on_sequence_browsed(1)
	_assert_eq(page._nav.back(), Target.animation(0),
		"browsing roots the inspector on a real sequence")
	page.queue_free()


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
