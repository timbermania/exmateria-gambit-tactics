extends Node
## TDD guard for the **drill-down chain** emitter → sequence → frameset → frame
## (ADR-0073 decs. 7-10). Closes the two hops that were dead-end integers:
##
##   1. emitter → sequence. The emitter's `Animation set` row keeps its editable
##      spinbox and grows a FOLLOW affordance (the `preload_action`-style wrap) whose
##      target is `InspectionTarget.animation(anim_index, anim_param)`. `anim_param`
##      ("Frameset group") is NOT a destination of its own — there is no group target
##      kind — so it rides the sequence target as the LENS its FRAME opcodes resolve
##      through, and one button (not two) carries the emitter's whole "what I play".
##   2. opcode → frameset. A FRAME opcode's `frameset` field is RELATIVE to the group,
##      so the absolute index is `frameset + EffectData.frameset_group_offset(group)`.
##      The group travels on the target's ref, so a target stays a self-contained
##      address (ADR-0073's core promise) instead of being read back off the nav stack.
##
## Also pins the single-source-of-truth for the group offset (`EffectData
## .frameset_group_offset`), which had FOUR independent copies before this change —
## the "documented truth with an unenumerated consumer" shape that produced the last
## two bugs on this branch.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioDrillDownTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const SequenceProjector = preload("res://src/effects/studio/SequenceProjector.gd")
const EffectDataClass = ExMateriaEffects.EffectData

## Pinned so a mid-test abort cannot report a clean [PASS] (the harness counts only
## assertions that RAN — see the branch's environment notes).
const EXPECTED_ASSERTIONS := 39   # 40 before `sequence_op` was deleted (2026-08-19)

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# The single derivation.
	_test_group_offset_is_one_derivation()
	# Hop 1 — emitter → sequence.
	_test_animation_set_row_stays_editable()
	_test_animation_set_row_follows_to_its_sequence()
	_test_follow_label_names_the_resolved_destination()
	_test_frameset_group_row_has_no_follow_of_its_own()
	_test_dangling_anim_index_is_dead_and_unfollowable()
	# The group is part of a target's identity.
	_test_group_is_part_of_the_animation_target_identity()
	# Hop 2 — opcode → frameset, resolved through the carried group.
	_test_frame_opcode_follows_to_the_absolute_frameset()
	_test_group_travels_from_the_sequence_to_its_opcodes()
	# (_test_opcode_back_link_preserves_the_group is gone with the `sequence_op` kind it
	#  addressed — deleted 2026-08-19. The lens it guarded still travels, and is still
	#  guarded: `_test_group_travels_from_the_sequence_to_its_opcodes` above asserts the
	#  thumb spec carries it, and EffectStudioUnifiedAnimationTest mutation-tests
	#  `SequenceProjector.absolute_frameset`, which is the one place it is now spent.)
	_test_dangling_frameset_is_unfollowable()
	_test_non_frame_opcode_has_no_follow()
	# The rendered affordance.
	_test_inspector_renders_follow_button_and_navigates()
	_test_disabled_follow_renders_no_button()

	var total := _passed + _failed
	if total != EXPECTED_ASSERTIONS:
		_failed += 1
		print("[FAIL] ran %d assertions, expected %d — a test aborted early"
			% [total, EXPECTED_ASSERTIONS])
	print("\n=== EffectStudioDrillDownTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioDrillDownTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioDrillDownTest")
		get_tree().quit(0)


# --- the single derivation -------------------------------------------------

## Before this change the emitter→group→frameset arithmetic existed in FOUR places
## (ActiveEmitter._get_group_offset, ParticleSubsystem's inline copy, EmitterSpriteColor's
## inline copy, and now the projectors). They all agreed on the same total function:
## in-range → the cumulative offset, anything else → 0. This pins that function once.
func _test_group_offset_is_one_derivation() -> void:
	var ed = EffectDataClass.new()
	ed.frameset_group_offsets = [0, 4, 7] as Array[int]
	_assert_eq(ed.frameset_group_offset(0), 0, "group 0 is always offset 0")
	_assert_eq(ed.frameset_group_offset(1), 4, "group 1 takes its cumulative offset")
	_assert_eq(ed.frameset_group_offset(2), 7, "group 2 takes its cumulative offset")
	_assert_eq(ed.frameset_group_offset(9), 0, "an out-of-range group degrades to 0")
	_assert_eq(ed.frameset_group_offset(-1), 0, "a negative group degrades to 0")


# --- hop 1: emitter → sequence ---------------------------------------------

## The follow affordance is ADDITIVE: the spinbox that authored anim_index before this
## change still authors it (ADR-0089 tier-1 capability is not traded for navigation).
func _test_animation_set_row_stays_editable() -> void:
	var row := _config_row(_effect(), 0, "Animation set")
	_assert_eq(row.get("shape", ""), "edit", "Animation set is still an edit row")
	_assert_eq(row.get("editor", ""), "int", "still the int spinbox")
	_assert_eq(str(row.get("field_ref", {}).get("field", "")), "anim_index",
		"still lowers through the anim_index field_ref")


func _test_animation_set_row_follows_to_its_sequence() -> void:
	# anim_index 1, anim_param 1 → sequence 1 seen through frameset group 1.
	var row := _config_row(_effect(1, 1), 0, "Animation set")
	var follow: Dictionary = row.get("follow", {})
	_assert_true(not follow.is_empty(), "the Animation set row carries a follow affordance")
	_assert_true(Target.equals(follow.get("target", {}), Target.animation(1, 1)),
		"it follows to animation(anim_index, anim_param) — the group rides the target")


## The button reads the RESOLVED destination, so editing "Frameset group" visibly
## re-aims it. This is why one button suffices for two fields.
func _test_follow_label_names_the_resolved_destination() -> void:
	var one := _config_row(_effect(1, 1), 0, "Animation set")
	_assert_true("sequence 1" in str(one.get("follow", {}).get("label", "")),
		"the follow label names the sequence")
	_assert_true("group 1" in str(one.get("follow", {}).get("label", "")),
		"the follow label names the group it resolves through")
	var zero := _config_row(_effect(1, 0), 0, "Animation set")
	_assert_true("group 0" in str(zero.get("follow", {}).get("label", "")),
		"a different group relabels the same button")


## `anim_param` names a LENS, not a place — there is no group target kind, so this row
## stays a plain editor. (The correction that collapsed two buttons into one.)
func _test_frameset_group_row_has_no_follow_of_its_own() -> void:
	var row := _config_row(_effect(1, 1), 0, "Frameset group")
	_assert_eq(row.get("shape", ""), "edit", "Frameset group is an edit row")
	_assert_true(not row.has("follow"),
		"Frameset group has NO follow of its own — it is a lens, not a destination")


## anim_index/anim_param are u8s with no validity guarantee. A dangling one wears the
## ADR-0089 relevance `dead` marker and its follow is disabled — the editor stays live
## so the author can fix the index in place.
func _test_dangling_anim_index_is_dead_and_unfollowable() -> void:
	var ed = _effect(12, 0)  # only 2 sequences exist
	var row := _config_row(ed, 0, "Animation set")
	_assert_eq(row.get("shape", ""), "edit", "a dangling row is still editable")
	_assert_true(bool(row.get("follow", {}).get("disabled", false)),
		"a dangling anim_index disables the follow")
	_assert_eq(str(row.get("relevance", {}).get("state", "")), "dead",
		"and the row wears the relevance 'dead' state")
	_assert_true("12" in str(row.get("relevance", {}).get("why", "")),
		"the why names the offending index")


## Two emitters playing the same sequence through different groups reach DIFFERENT
## framesets, so they are different targets — the nav stack must not dedupe them.
## (E241 anim 0 and E408 anim 4 are the only two real instances in all 481 effects.)
func _test_group_is_part_of_the_animation_target_identity() -> void:
	_assert_true(not Target.equals(Target.animation(4, 0), Target.animation(4, 1)),
		"same sequence, different group → different targets")
	_assert_true(Target.equals(Target.animation(4, 1), Target.animation(4, 1)),
		"same sequence, same group → equal targets")
	_assert_eq(int(Target.ref(Target.animation(4)).get("group", -1)), 0,
		"the group defaults to 0 for a browser-entered sequence")


# --- hop 2: opcode → frameset ----------------------------------------------

## The FRAME opcode's `frameset` is RELATIVE; the link resolves it against the group
## carried on the target — the same derivation the sim does.
func _test_frame_opcode_follows_to_the_absolute_frameset() -> void:
	var ed = _effect()
	# Sequence 1 opcode 0 is FRAME fs=2; group 1's offset is 4 → absolute frameset 6.
	var row := _opcode_row(ed, Target.animation(1, 1), 0, "Frameset")
	_assert_eq(row.get("shape", ""), "edit", "the opcode Frameset row is still editable")
	_assert_eq(int(row.get("value", -1)), 2, "the editor still shows the RELATIVE value")
	_assert_true(Target.equals(row.get("follow", {}).get("target", {}), Target.frameset(6)),
		"but the follow resolves to the ABSOLUTE frameset (2 + offset 4)")
	# Same opcode, group 0 → no shift.
	var g0 := _opcode_row(ed, Target.animation(1, 0), 0, "Frameset")
	_assert_true(Target.equals(g0.get("follow", {}).get("target", {}), Target.frameset(2)),
		"through group 0 the same opcode reaches frameset 2 — the ambiguity this fixes")


## The lens has to reach each opcode, or its picture would be drawn through group 0 and
## silently show the wrong sprite. It used to travel on the header's per-opcode LINK;
## those rows are gone (ADR-0100) and the same number now rides the section's `thumb`
## request, which is what the host resolves the sprite through.
func _test_group_travels_from_the_sequence_to_its_opcodes() -> void:
	var ed = _effect()
	var sections := SequenceProjector.sections(Target.animation(1, 1), ed, {})
	_assert_true(not sections.is_empty(), "the sequence view sections its opcodes")
	if sections.is_empty():
		return
	var spec: Dictionary = sections[0].get("thumb", {})
	_assert_eq(int(spec.get("animation_index", -1)), 1, "opcode 0's picture is of sequence 1")
	_assert_eq(int(spec.get("opcode_index", -1)), 0, "and of opcode 0")
	_assert_eq(int(spec.get("group", -1)), 1, "and carries the sequence's group")
	# The header itself must produce no per-opcode edge — nothing in the UI drills into one
	# instruction, and a stray link here would re-introduce the width that blocked the column.
	for r in SequenceProjector.header(Target.animation(1, 1), ed, {}):
		_assert_true(not r.has("link"), "the sequence header carries no opcode links")


func _test_dangling_frameset_is_unfollowable() -> void:
	var ed = _effect()
	# Sequence 1 opcode 2 is FRAME fs=99 — off the end of the flat framesets array.
	var row := _opcode_row(ed, Target.animation(1, 0), 2, "Frameset")
	_assert_true(bool(row.get("follow", {}).get("disabled", false)),
		"a frameset index that resolves off the end disables the follow")
	_assert_eq(row.get("shape", ""), "edit", "the editor stays live so it can be fixed")


func _test_non_frame_opcode_has_no_follow() -> void:
	# Sequence 1 opcode 1 is SET_OFFSET — nothing to drill into.
	var row := _opcode_row(_effect(), Target.animation(1, 0), 1, "Offset X")
	_assert_true(not row.has("follow"), "a SET_OFFSET parameter carries no follow")


# --- the rendered affordance -----------------------------------------------

## The follow button is a real link: it registers on the inspector's link_buttons()
## seam and fires the navigate callback with its target, exactly like a `link` row.
func _test_inspector_renders_follow_button_and_navigates() -> void:
	var ed = _effect(1, 1)
	var insp = Inspector.new()
	add_child(insp)
	var got := {"target": {}}
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}),
		Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass, func(t): got["target"] = t)
	var found := false
	for b in insp.link_buttons():
		if "sequence 1" in b.text:
			b.pressed.emit()
			found = true
			break
	_assert_true(found, "the Animation set row renders a follow button")
	_assert_true(Target.equals(got["target"], Target.animation(1, 1)),
		"pressing it navigates to the sequence, group and all")
	insp.queue_free()


func _test_disabled_follow_renders_no_button() -> void:
	var ed = _effect(12, 0)  # dangling
	var insp = Inspector.new()
	add_child(insp)
	var target := Target.emitter(0)
	insp.show_target(target, Model.inspector_header(target, ed, {}),
		Model.inspector_sections(target, ed, {}),
		func(_i): return [], func(_a, _b): pass, func(_t): pass)
	var any := false
	for b in insp.link_buttons():
		if "sequence" in b.text:
			any = true
	_assert_true(not any, "a dangling reference renders no pressable follow button")
	insp.queue_free()


# --- fixtures --------------------------------------------------------------

## Two sequences and two frameset groups (offsets [0, 4]) over 8 flat framesets, so a
## relative frameset resolves DIFFERENTLY through group 0 and group 1 — the shape that
## makes an opcode's frameset field ambiguous without its lens.
func _effect(anim_index: int = 0, anim_param: int = 0):
	var ed = EffectDataClass.new()
	ed.frameset_group_offsets = [0, 4] as Array[int]
	ed.framesets = []
	for i in range(8):
		ed.framesets.append({"header_flags": 0, "frames": [{"uv": {}, "vertices": {}}]})
	ed.animations = [
		{"opcodes": [{"type": "FRAME", "frameset": 0, "duration": 4, "depth_mode": 0},
			{"type": "LOOP"}]},
		{"opcodes": [
			{"type": "FRAME", "frameset": 2, "duration": 8, "depth_mode": 0},
			{"type": "SET_OFFSET", "x": 3, "y": -1},
			{"type": "FRAME", "frameset": 99, "duration": 2, "depth_mode": 0},
			{"type": "LOOP"}]},
	]
	var em = EffectEmitter.new()
	em.anim_index = anim_index
	em.anim_param = anim_param
	ed.emitters.append(em)
	return ed


func _config_row(ed, emitter_index: int, name: String) -> Dictionary:
	for group in Model.emitter_view(ed, emitter_index):
		if group.get("title", "") == "Config":
			for f in group.get("params", []):
				if f.get("name", "") == name:
					return f
	return {}


## A named field out of the opcode section the sequence view renders for `op_idx`.
func _opcode_row(ed, anim_target: Dictionary, op_idx: int, name: String) -> Dictionary:
	for section in SequenceProjector.sections(anim_target, ed, {}):
		if not str(section.get("title", "")).begins_with("%d:" % op_idx):
			continue
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
