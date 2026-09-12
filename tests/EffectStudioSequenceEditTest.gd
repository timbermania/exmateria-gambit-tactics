extends Node
## TDD guard for Effect Studio SEQUENCE (Animation) editing (#275) — the animation
## sequence bytecode's opcode PARAMETERS made editable through the same #255 choke
## point, reusing the F1 shared kit (#264).
##
## An animation is a plain JSON-shaped Dictionary on `EffectData.animations[i]`
## (`parse_animations_section`'s output shape verbatim), holding an ordered
## `opcodes` array of `{type, ...params}` dicts. The encoder mutates the live dict
## in place. Unlike frames (read-live), sequences are BAKED ONCE by
## `ParticleAnimator._bake_animations` at subsystem setup, so a sequence edit is
## `invalidates_sim = true` — the host must re-fold for it to reach the preview.
##
## v1 SCOPE (locked with the user 2026-08-18, see #275): IN-PLACE PARAMETER EDITS
## ONLY — no insert/delete/reorder of opcodes, no changing an opcode's TYPE, no
## adding/removing sequences. Those are variable-size structural rewrites (a
## sequence's opcodes are 1/3/5 bytes) needing the section regenerator + offset
## table rewrite + header pointer fixups; deferred to a follow-on.
##
## Opcode completeness is settled: a section-bounded corpus audit (2026-08-18)
## walked all 2428 sequences across all 401 non-empty effects and found ZERO
## undocumented opcodes, zero opcodes straddling a sequence bound, and zero
## non-zero unconsumed tail bytes. Every sequence is exactly SET_OFFSET … LOOP,
## one of each, always first and last.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioSequenceEditTest.tscn

const Channel = preload("res://src/effects/studio/SequenceChannel.gd")
const Projector = preload("res://src/effects/studio/SequenceProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_encoder_writes_frame_duration_and_records_undo()
	_test_encoder_writes_frameset_and_depth_mode()
	_test_encoder_writes_set_offset_and_add_offset_params()
	_test_encoder_refuses_a_param_the_opcode_type_does_not_own()
	_test_encoder_reports_unfaithful_frameset_that_would_change_the_opcode_type()
	_test_encoder_reports_unfaithful_out_of_range_add_offset_delta()
	_test_animation_header_is_a_summary_with_no_per_opcode_rows()
	_test_every_section_is_titled_like_the_lua_instruction_list()
	_test_every_section_requests_its_own_picture()
	_test_sections_start_collapsed_under_a_value_stable_key()
	_test_animation_sections_emit_one_editable_group_per_opcode()
	_test_loop_opcode_has_no_editable_params()
	_test_depth_mode_row_offers_the_named_modes()
	_test_session_dispatches_sequence_channel_and_undoes()

	print("\n=== EffectStudioSequenceEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceEditTest")
		get_tree().quit(0)


func _test_encoder_writes_frame_duration_and_records_undo() -> void:
	var data := _fake_data()
	var op: Dictionary = data.animations[0]["opcodes"][1]
	var ref := {"channel": "sequence", "animation_index": 0, "opcode_index": 1, "field": "duration"}

	var res: Dictionary = Channel.apply_raw(data, ref, 12)

	_assert_eq(res.get("before_raw", -1), 8, "records the pre-edit duration")
	_assert_eq(res.get("after_raw", -1), 12, "records the written duration")
	_assert_eq(res.get("invalidates_sim", false), true,
		"a sequence edit re-bakes (ParticleAnimator bakes once at setup)")
	_assert_true(res.get("faithful", {}).get("ok", false), "an in-range duration is faithfully encodable")
	_assert_eq(op["duration"], 12, "the encoder writes the raw value onto the live opcode dict")


func _test_encoder_writes_frameset_and_depth_mode() -> void:
	var data := _fake_data()
	var op: Dictionary = data.animations[0]["opcodes"][1]

	Channel.apply_raw(data, _ref(0, 1, "frameset"), 9)
	Channel.apply_raw(data, _ref(0, 1, "depth_mode"), 4)

	_assert_eq(op["frameset"], 9, "frameset is written onto the live opcode dict")
	_assert_eq(op["depth_mode"], 4, "depth_mode is written onto the live opcode dict")


func _test_encoder_writes_set_offset_and_add_offset_params() -> void:
	var data := _fake_data()
	var set_off: Dictionary = data.animations[0]["opcodes"][0]
	var add_off: Dictionary = data.animations[0]["opcodes"][2]

	var res_x: Dictionary = Channel.apply_raw(data, _ref(0, 0, "x"), -40)
	Channel.apply_raw(data, _ref(0, 0, "y"), 7)
	Channel.apply_raw(data, _ref(0, 2, "dx"), -3)
	Channel.apply_raw(data, _ref(0, 2, "dy"), 5)

	_assert_eq(res_x.get("before_raw", 999), 0, "records the pre-edit SET_OFFSET x")
	_assert_eq(set_off["x"], -40, "SET_OFFSET x accepts the full signed 16-bit range")
	_assert_eq(set_off["y"], 7, "SET_OFFSET y is written")
	_assert_eq(add_off["dx"], -3, "ADD_OFFSET dx is written")
	_assert_eq(add_off["dy"], 5, "ADD_OFFSET dy is written")


## A field only exists on the opcode type that encodes it. Addressing a FRAME
## param at a LOOP (which has no parameters at all) must be refused, not
## silently invent a "duration" key the writer would never emit.
func _test_encoder_refuses_a_param_the_opcode_type_does_not_own() -> void:
	var data := _fake_data()
	var loop_op: Dictionary = data.animations[0]["opcodes"][4]

	var res: Dictionary = Channel.apply_raw(data, _ref(0, 4, "duration"), 5)

	_assert_true(res.is_empty(), "writing a FRAME param at a LOOP opcode is refused")
	_assert_true(not loop_op.has("duration"), "the refused write leaves the LOOP opcode untouched")

	var res_dx: Dictionary = Channel.apply_raw(data, _ref(0, 1, "dx"), 5)
	_assert_true(res_dx.is_empty(), "writing an ADD_OFFSET param at a FRAME opcode is refused")


## The FRAME opcode byte IS the frameset index, so a frameset >= 0x80 would
## re-encode the opcode as LOOP/SET_OFFSET/ADD_OFFSET — a TYPE change, which v1
## excludes. Free still accepts it; the advisory is what warns.
func _test_encoder_reports_unfaithful_frameset_that_would_change_the_opcode_type() -> void:
	var data := _fake_data()

	var ok: Dictionary = Channel.apply_raw(data, _ref(0, 1, "frameset"), 127)
	var bad: Dictionary = Channel.apply_raw(data, _ref(0, 1, "frameset"), 129)

	_assert_true(ok.get("faithful", {}).get("ok", false), "frameset 127 is the largest faithful index")
	_assert_true(not bad.get("faithful", {}).get("ok", true),
		"frameset 129 would collide with the SET_OFFSET opcode byte")
	_assert_eq(data.animations[0]["opcodes"][1]["frameset"], 129,
		"Free still accepts the write — the verdict is advisory, not a veto")


func _test_encoder_reports_unfaithful_out_of_range_add_offset_delta() -> void:
	var data := _fake_data()

	var ok: Dictionary = Channel.apply_raw(data, _ref(0, 2, "dx"), -128)
	var bad: Dictionary = Channel.apply_raw(data, _ref(0, 2, "dy"), 200)

	_assert_true(ok.get("faithful", {}).get("ok", false), "-128 fits ADD_OFFSET's signed byte")
	_assert_true(not bad.get("faithful", {}).get("ok", true), "200 overflows ADD_OFFSET's signed byte")


## The header is a SUMMARY, and only a summary (ADR-0100). The per-opcode link rows
## that used to live here were a second, read-only copy of the section list below, and
## they alone held the inspector's minimum width at 1068px of a 1241px body — which is
## why the player could not dock beside it. The labels they carried did not vanish:
## they are the section titles now (see the test below).
func _test_animation_header_is_a_summary_with_no_per_opcode_rows() -> void:
	var data := _fake_data()

	var rows: Array = Projector.header(Target.animation(0), data, {})

	var links: Array = []
	for row in rows:
		if row.has("link"):
			links.append(str(row["link"].get("label", "")))
	_assert_eq(links, [], "the header carries no opcode link rows at all")
	_assert_eq(rows.size(), 2, "just the two summary rows")
	_assert_eq(rows[0].get("value", ""), "sequence 0 (5 opcodes)",
		"the header identifies the sequence and its opcode count")


## Nothing the deleted link rows showed is lost: the section title IS the Lua
## sequences tab's instruction label, verbatim in form.
func _test_every_section_is_titled_like_the_lua_instruction_list() -> void:
	var data := _fake_data()

	var sections: Array = Projector.sections(Target.animation(0), data, {})

	var titles: Array = []
	for section in sections:
		titles.append(str(section.get("title", "")))
	_assert_eq(titles, [
		"0: SET_OFFSET x=0 y=-12",
		"1: FRAME fs=3 dur=8 depth=1",
		"2: ADD_OFFSET dx=2 dy=-1",
		"3: FRAME fs=4 dur=0 depth=1",
		"4: LOOP",
	], "every opcode section is labelled like the Lua sequences tab")


## Each section asks the host for its own opcode's picture, carrying the group the
## sequence is being read through — a FRAME's sprite is group-relative.
func _test_every_section_requests_its_own_picture() -> void:
	var sections: Array = Projector.sections(Target.animation(0, 1), _fake_data(), {})

	for i in range(sections.size()):
		var spec: Dictionary = sections[i].get("thumb", {})
		_assert_eq(int(spec.get("opcode_index", -1)), i,
			"section %d asks for opcode %d's picture" % [i, i])
		_assert_eq(int(spec.get("animation_index", -1)), 0, "of sequence 0")
		_assert_eq(int(spec.get("group", -1)), 1, "through the group it is being read at")


## The sections open SHUT, and each carries a fold identity that does NOT move when its
## own values are edited — a key made from the title would shut the section being typed
## into the moment `duration` changed.
func _test_sections_start_collapsed_under_a_value_stable_key() -> void:
	var sections: Array = Projector.sections(Target.animation(0), _fake_data(), {})

	_assert_true(bool(sections[1].get("collapsed", false)), "an opcode section starts collapsed")
	_assert_eq(str(sections[1].get("fold_id", "")), "seq:0:1", "keyed by sequence and opcode index")


func _test_animation_sections_emit_one_editable_group_per_opcode() -> void:
	var data := _fake_data()

	var sections: Array = Projector.sections(Target.animation(0), data, {})

	_assert_eq(sections.size(), 5, "one section per opcode")
	_assert_eq(str(sections[1].get("title", "")), "1: FRAME fs=3 dur=8 depth=1",
		"a section is titled by the full instruction label")
	var names: Array = []
	var refs: Array = []
	for f in sections[1]["fields"]:
		names.append(str(f.get("name", "")))
		refs.append(f.get("field_ref", {}))
	_assert_eq(names, ["Frameset", "Duration", "Depth mode"], "a FRAME exposes its three parameters")
	_assert_eq(refs[1], {"channel": "sequence", "animation_index": 0, "opcode_index": 1,
		"field": "duration"}, "each row carries the field_ref the choke point routes")
	_assert_eq(sections[1]["fields"][1].get("value", -1), 8, "the row shows the live value")
	_assert_eq(str(sections[1]["fields"][0].get("shape", "")), "edit", "parameters are editable")


func _test_loop_opcode_has_no_editable_params() -> void:
	var data := _fake_data()

	var sections: Array = Projector.sections(Target.animation(0), data, {})

	_assert_eq(str(sections[4].get("title", "")), "4: LOOP", "the terminator is still listed")
	_assert_eq(sections[4]["fields"].size(), 1, "LOOP shows one explanatory row")
	_assert_eq(str(sections[4]["fields"][0].get("shape", "")), "const",
		"LOOP carries no parameters, so nothing is editable")


func _test_depth_mode_row_offers_the_named_modes() -> void:
	var data := _fake_data()

	var sections: Array = Projector.sections(Target.animation(0), data, {})
	var depth_row: Dictionary = sections[1]["fields"][2]

	_assert_eq(str(depth_row.get("editor", "")), "choice", "depth mode is a named choice, not a bare int")
	_assert_eq(depth_row.get("choices", []).size(), 6, "the six RE-documented depth modes")
	_assert_eq(str(depth_row.get("choices", [])[0]), "0: Standard (Z>>2)",
		"mode names match the Lua sequences tab's DEPTH_MODE_OPTIONS")
	_assert_eq(depth_row.get("value", -1), 1, "the row shows the live depth mode")


## Seam 5: the #255 choke point routes the new channel, and its default undo
## path replays the scalar back — sequence edits need no bespoke snapshot verb.
func _test_session_dispatches_sequence_channel_and_undoes() -> void:
	var data := _fake_data()
	var op: Dictionary = data.animations[0]["opcodes"][1]
	var session = Session.new(data)

	var res: Dictionary = session.apply_edit(_ref(0, 1, "duration"), 40)
	_assert_eq(op["duration"], 40, "the choke point routes a sequence edit to the encoder")
	_assert_eq(res.get("invalidates_sim", false), true, "and reports that the host must re-fold")

	_assert_true(session.undo(), "the edit is undoable")
	_assert_eq(op["duration"], 8, "undo restores the pre-edit duration byte-exactly")


# --- fixtures -------------------------------------------------------------

func _ref(anim_idx: int, op_idx: int, field: String) -> Dictionary:
	return {"channel": "sequence", "animation_index": anim_idx,
		"opcode_index": op_idx, "field": field}



## One sequence in the corpus-universal shape the audit confirmed: SET_OFFSET
## first, LOOP last, FRAME/ADD_OFFSET in between.
func _fake_data() -> RefCounted:
	var data := _FakeData.new()
	data.animations = [
		{
			"index": 0,
			"opcodes": [
				{"type": "SET_OFFSET", "x": 0, "y": -12},
				{"type": "FRAME", "frameset": 3, "duration": 8, "depth_mode": 1},
				{"type": "ADD_OFFSET", "dx": 2, "dy": -1},
				{"type": "FRAME", "frameset": 4, "duration": 0, "depth_mode": 1},
				{"type": "LOOP"},
			],
		},
	]
	# Production reads `framesets` and calls `frameset_group_offset` off this object
	# (SequenceProjector.absolute_frameset / _attach_frameset_follow). The double used to
	# carry only `animations`, so BOTH threw — and an aborted production call leaves the
	# double in its pre-call state, which is what made the assertions after it describe a
	# world where the call never happened. Six framesets covers the two the opcodes above
	# name (3 and 4) with room to spare. #466.
	data.framesets = [{}, {}, {}, {}, {}, {}]
	return data


class _FakeData extends RefCounted:
	var animations: Array = []
	var framesets: Array = []

	## The ONE derivation production delegates to (EffectData.frameset_group_offset).
	## This fixture has a single frameset group, so every group applies no shift — the
	## same answer the real one gives for group 0, and for an out-of-range group.
	func frameset_group_offset(_group: int) -> int:
		return 0


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
