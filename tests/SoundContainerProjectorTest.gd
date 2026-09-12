extends Node
## TDD guard for SoundContainerProjector (ADR-0073 / ADR-0085 TIER-2) — the "container"
## target-kind projector, laid out as an AUTHORING workflow (#289 redesign): the whole
## 5-mode space as one always-visible radio list (each row previewing the sequence it
## WOULD play off the current ids), the three shared Sound A/B/C slots as bank-entry
## pickers with a ▶ one-shot preview each, and one Audition action for the selected
## mode. The header still carries the "used by N" back-links to referencing triggers.
##
## The projector is a THIN reader over the pre-projected view the studio threads into the
## SCORE (score["sound_containers"][index]) — mirrors how EmitterTargetProjector reads
## emitter_view. So this test hand-builds a score with a known view and asserts the
## formatting, independent of SoundContainerModel.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundContainerProjectorTest.tscn

const Projector = preload("res://src/effects/studio/SoundContainerProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_header_shows_index_mode_and_provenance_links()
	_test_missing_view_is_inert()
	_test_pick_mode_is_a_radio_list_with_sequence_previews()
	_test_ids_are_bank_entry_pickers_with_slot_preview()
	_test_out_of_bank_id_keeps_an_honest_raw_choice()
	_test_unused_slots_are_flagged_for_the_mode()
	_test_honest_second_fire_truth_is_present()
	_test_audition_action_targets_the_container()
	_test_step_truth_is_hover_only_and_pair_link_is_author_facing()

	print("\n=== SoundContainerProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundContainerProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundContainerProjectorTest")
		get_tree().quit(0)


# A score carrying one pre-projected container view (index 0), TRIPLE_CYCLE, ids 5/9/13
# over a 12-entry bank (id 13 → pair 12 is OUT of range), used by two triggers. The raw
# resolver inputs (mode + id_a/id_b/id_c), the mode radio choices (each with its what-if
# sequence off the CURRENT ids), and the bank extent all ride the view.
func _score() -> Dictionary:
	return {"sound_containers": [{
		"index": 0, "mode": 4, "mode_name": "TRIPLE_CYCLE",
		"mode_author_label": "Cycle 1 → 2 → 3",
		"used_slots": ["a", "b", "c"],
		"fire_sequence": [5, 9, 13, 5, 9, 13],
		"id_a": 5, "id_b": 9, "id_c": 13,
		"emitted_ids": [5, 9, 13],
		"pairs": [
			{"id": 5, "pair_idx": 4, "valid": true},
			{"id": 9, "pair_idx": 8, "valid": true},
			{"id": 13, "pair_idx": 12, "valid": false}],
		"mode_choices": [
			{"value": 0, "label": "Always Sound 1", "seq": [5, 5, 5, 5, 5, 5], "pattern": [1, 1, 1, 1, 1, 1]},
			{"value": 1, "label": "Alternate 1 / 2", "seq": [5, 9, 5, 9, 5, 9], "pattern": [1, 2, 1, 2, 1, 2]},
			{"value": 2, "label": "Sound 1 once, then 2", "seq": [5, 9, 9, 9, 9, 9], "pattern": [1, 2, 2, 2, 2, 2]},
			{"value": 3, "label": "1 once, then alternate 3 / 2", "seq": [5, 13, 9, 13, 9, 13], "pattern": [1, 3, 2, 3, 2, 3]},
			{"value": 4, "label": "Cycle 1 → 2 → 3", "seq": [5, 9, 13, 5, 9, 13], "pattern": [1, 2, 3, 1, 2, 3]}],
		"bank_size": 12,
		"used_by": 2,
		"provenance": [
			{"label": "Used by", "link": {"label": "sound for_each ch0 kf0",
				"target": Target.span("sound:for_each:0#0")}},
			{"label": "Used by", "link": {"label": "sound for_each ch1 kf0",
				"target": Target.span("sound:for_each:1#0")}}],
	}]}


# A DIRECT_A (mode 0) view — the 92%-common real shape. Only id_a is read; id_b/id_c are
# dead bytes for this mode. Author label "Always Sound A", used_slots ["a"].
func _score_direct_a() -> Dictionary:
	return {"sound_containers": [{
		"index": 0, "mode": 0, "mode_name": "DIRECT_A",
		"mode_author_label": "Always Sound 1",
		"used_slots": ["a"],
		"fire_sequence": [7, 7, 7, 7, 7, 7],
		"id_a": 7, "id_b": 9, "id_c": 13,
		"emitted_ids": [7],
		"pairs": [{"id": 7, "pair_idx": 6, "valid": true}],
		"mode_choices": [
			{"value": 0, "label": "Always Sound 1", "seq": [7, 7, 7, 7, 7, 7], "pattern": [1, 1, 1, 1, 1, 1]},
			{"value": 1, "label": "Alternate 1 / 2", "seq": [7, 9, 7, 9, 7, 9], "pattern": [1, 2, 1, 2, 1, 2]},
			{"value": 2, "label": "Sound 1 once, then 2", "seq": [7, 9, 9, 9, 9, 9], "pattern": [1, 2, 2, 2, 2, 2]},
			{"value": 3, "label": "1 once, then alternate 3 / 2", "seq": [7, 13, 9, 13, 9, 13], "pattern": [1, 3, 2, 3, 2, 3]},
			{"value": 4, "label": "Cycle 1 → 2 → 3", "seq": [7, 9, 13, 7, 9, 13], "pattern": [1, 2, 3, 1, 2, 3]}],
		"bank_size": 16,
		"used_by": 1, "provenance": [],
	}]}


func _fields_of(sections: Array, title: String) -> Array:
	for s in sections:
		if s.get("title", "") == title:
			return s.get("fields", [])
	return []


func _field(fields: Array, name: String) -> Dictionary:
	for f in fields:
		if f.get("name", "") == name:
			return f
	return {}


## The header identifies the container (index + mode) and carries the "used by" reverse
## links to every trigger that references it — the shared-object blast radius.
func _test_header_shows_index_mode_and_provenance_links() -> void:
	var header := Projector.header(Target.container(0), null, _score())
	_assert_true(not header.is_empty(), "the header is non-empty")
	var first_val := str(header[0].get("value", ""))
	_assert_true(first_val.findn("Cycle 1 → 2 → 3") != -1 and first_val.find("0") != -1,
		"the header names the container index and the author-facing pattern")
	var link_rows := 0
	for row in header:
		if row.has("link"):
			link_rows += 1
	_assert_eq(link_rows, 2, "both referencing triggers appear as clickable back-links")


## A target for a container index the score has no view for renders nothing rather than
## crashing (mirrors the registry's inert-unbuilt contract).
func _test_missing_view_is_inert() -> void:
	_assert_eq(Projector.sections(Target.container(9), null, _score()), [],
		"an index with no view yields empty sections")
	_assert_eq(Projector.header(Target.container(9), null, _score()), [],
		"an index with no view yields empty header")
	_assert_eq(Projector.sections(Target.container(0), null, {}), [],
		"no sound_containers in the score yields empty sections")


## "Play pattern" is a `radio` editor: EVERY mode visible at once, each choice carrying
## its author label AND a `detail` showing its slot-number step pattern ("1  2  1  2 …")
## — so the whole pattern space is scannable without auditioning each. Seeded to the raw
## mode, with a sound_container-channel field_ref addressing this container by index.
func _test_pick_mode_is_a_radio_list_with_sequence_previews() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	_assert_true(not fields.is_empty(), "there is a 'Sound selection' section")
	var cell := _field(fields, "Play pattern")
	_assert_eq(str(cell.get("shape", "")), "edit", "Play pattern is an editable cell")
	_assert_eq(str(cell.get("editor", "")), "radio", "Play pattern uses the radio editor")
	_assert_eq(int(cell.get("value", -1)), 4, "seeded to the container's raw mode (TRIPLE_CYCLE)")
	var ref: Dictionary = cell.get("field_ref", {})
	_assert_eq(str(ref.get("channel", "")), "sound_container", "field_ref targets the sound_container channel")
	_assert_eq(int(ref.get("index", -1)), 0, "field_ref addresses container 0")
	_assert_eq(str(ref.get("field", "")), "mode", "field_ref names the mode field")
	var choices: Array = cell.get("choices", [])
	_assert_eq(choices.size(), 5, "all 5 patterns are visible at once")
	var labels: Array = []
	for c in choices:
		labels.append(str(c.get("label", "")))
	_assert_true(labels.has("Cycle 1 → 2 → 3") and labels.has("Always Sound 1"),
		"the pattern choices read as numbered sequences, not RE names")
	# Every row shows its slot-number step pattern; steps name SLOTS (stable under id
	# edits), so the alternating mode reads "1  2  1  2".
	for c in choices:
		_assert_true(str(c.get("detail", "")) != "",
			"mode %d carries a step-pattern read-out" % int(c.get("value", -1)))
	var alt: Dictionary = choices[1]
	_assert_true(str(alt.get("detail", "")).find("1  2  1  2") != -1,
		"Alternate 1 / 2 shows its steps in slot numbers")
	# Sounds come FIRST (the pickers), the pattern list follows — the approved layout.
	_assert_eq(str(fields[0].get("name", "")), "Sound 1", "Sound 1 is the first field")
	_assert_eq(str(fields[3].get("name", "")), "Play pattern", "the pattern list follows the sounds")


## Each container slot (id_a/id_b/id_c) is a bank-entry `enum` picker — choosing a sound
## is a click over the effect's Sound bank entries (pair_idx = id-1), not a raw-byte
## guess — seeded to the raw value, with a ▶ preview_action so the author can hear the
## selected entry alone.
func _test_ids_are_bank_entry_pickers_with_slot_preview() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	for pair in [["id_a", 5], ["id_b", 9]]:
		var field_name: String = pair[0]
		var seed: int = pair[1]
		var cell := _field_by_ref_field(fields, field_name)
		_assert_true(not cell.is_empty(), "there is an editable cell for %s" % field_name)
		_assert_eq(str(cell.get("shape", "")), "edit", "%s is editable" % field_name)
		_assert_eq(str(cell.get("editor", "")), "enum", "%s uses the enum (bank picker) editor" % field_name)
		_assert_eq(int(cell.get("value", -1)), seed, "%s seeded to its raw value" % field_name)
		var ref: Dictionary = cell.get("field_ref", {})
		_assert_eq(str(ref.get("channel", "")), "sound_container", "%s field_ref channel" % field_name)
		_assert_eq(int(ref.get("index", -1)), 0, "%s field_ref index" % field_name)
		_assert_eq(str(ref.get("field", "")), field_name, "%s field_ref field" % field_name)
		var choices: Array = cell.get("choices", [])
		_assert_eq(choices.size(), 12, "%s enumerates the whole 12-entry bank" % field_name)
		var found := ""
		for c in choices:
			if int(c.get("value", -1)) == seed:
				found = str(c.get("label", ""))
		_assert_eq(found, "Sound bank entry %d" % (seed - 1),
			"%s's current value reads as its bank entry" % field_name)
		var prev: Dictionary = cell.get("preview_action", {})
		_assert_eq(str(prev.get("kind", "")), "audition_sound", "%s carries a ▶ slot preview" % field_name)
		_assert_eq(int(prev.get("id", -1)), seed, "%s's preview plays the selected id" % field_name)


## A raw byte outside the bank (id 13 over a 12-entry bank) stays REPRESENTABLE: the
## picker gains an honest extra choice naming the raw id, so projecting never silently
## rewrites a byte.
func _test_out_of_bank_id_keeps_an_honest_raw_choice() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	var cell := _field_by_ref_field(fields, "id_c")
	var choices: Array = cell.get("choices", [])
	_assert_eq(choices.size(), 13, "the out-of-bank value adds one honest extra choice")
	_assert_true(str(choices[0].get("label", "")).findn("no bank entry") != -1,
		"the extra choice is flagged as having no bank entry")
	_assert_eq(int(choices[0].get("value", -1)), 13, "the extra choice carries the raw byte")


## An id slot the current mode never reads is a DEAD byte — the cell is flagged (label or
## tooltip carries "unused"/"not played") so an author does not edit a no-op, but stays
## EDITABLE (all parameters selectable). DIRECT_A reads only id_a.
func _test_unused_slots_are_flagged_for_the_mode() -> void:
	var secs := Projector.sections(Target.container(0), null, _score_direct_a())
	var fields := _fields_of(secs, "Sound selection")
	var a := _field_by_ref_field(fields, "id_a")
	var b := _field_by_ref_field(fields, "id_b")
	var c := _field_by_ref_field(fields, "id_c")
	var a_txt := (str(a.get("name", "")) + str(a.get("tooltip", ""))).to_lower()
	var b_txt := (str(b.get("name", "")) + str(b.get("tooltip", ""))).to_lower()
	var c_txt := (str(c.get("name", "")) + str(c.get("tooltip", ""))).to_lower()
	_assert_true(a_txt.find("unused") == -1, "id_a is read by DIRECT_A — not flagged unused")
	_assert_true(b_txt.find("unused") != -1, "id_b is dead for DIRECT_A — flagged unused")
	_assert_true(c_txt.find("unused") != -1, "id_c is dead for DIRECT_A — flagged unused")
	_assert_eq(str(b.get("shape", "")), "edit", "a dead slot is dimmed, NOT locked — still editable")


## The MOST important honesty note (user-identified): the pattern advances one step per
## sound EVENT, so hearing step 2 inside the effect requires ADDING a 2nd sound event
## that plays this container. Present as an actionable note, not buried mechanism.
func _test_honest_second_fire_truth_is_present() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	var joined := ""
	for f in fields:
		joined += str(f.get("name", "")) + str(f.get("value", "")) + str(f.get("tooltip", ""))
	joined = joined.to_lower()
	_assert_true(joined.find("add a 2nd sound event") != -1,
		"the note says HOW to reach step 2: add a 2nd sound event")
	_assert_true(joined.find("one step") != -1,
		"the note explains the pattern advances one step per sound event")


## The Audition action lets the author HEAR the selected mode's repeat pattern (silent on
## a single studio play). An `action` field naming the container by index — the host wires
## this to fire the container repeatedly through the SFX engine.
func _test_audition_action_targets_the_container() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	var act := _field(fields, "Audition")
	_assert_eq(str(act.get("shape", "")), "action", "there is an action field")
	var ref: Dictionary = act.get("action", {})
	_assert_eq(str(ref.get("kind", "")), "audition_container", "the action auditions a container")
	_assert_eq(int(ref.get("index", -1)), 0, "the action names container 0")


## Layout honesty (user feedback 2026-08-11): the step-truth note is HOVER-ONLY —
## a long unwrapped const row inflates the inspector's shared value column and
## pushes the second column-pair (Sound 2 / pattern / the pair link) off-window.
## The note text rides the pattern radio + Audition tooltips instead. And the
## TIER-3 drill-in link is author-facing ("edit Sound bank entry N"), matching
## the slot pickers' vocabulary — not RE pair-speak.
func _test_step_truth_is_hover_only_and_pair_link_is_author_facing() -> void:
	var secs := Projector.sections(Target.container(0), null, _score())
	var fields := _fields_of(secs, "Sound selection")
	for f in fields:
		if str(f.get("shape", "")) == "const":
			_assert_true(str(f.get("value", "")).length() <= 60,
				"no const row long enough to inflate the value column (got '%s')" % str(f.get("value", "")))
	var radio := _field(fields, "Play pattern")
	_assert_true("one step" in str(radio.get("tooltip", "")).to_lower(),
		"the step truth hovers on the pattern radio")
	var act := _field(fields, "Audition")
	_assert_true("2nd sound event" in str(act.get("tooltip", "")).to_lower(),
		"the how-to-hear-step-2 truth hovers on the Audition button")
	var link := _field(fields, "Sound content")
	_assert_eq(str(link.get("shape", "")), "link", "the drill-in link exists under 'Sound content'")
	_assert_true(str(link.get("label", "")).begins_with("→ edit Sound bank entry "),
		"the link speaks the slot pickers' vocabulary")
	_assert_eq(str(link.get("target", {}).get("kind", "")), "pair",
		"the link drills into the pair editor")


## Find an editable cell by the field its field_ref writes (the display name may differ).
func _field_by_ref_field(fields: Array, ref_field: String) -> Dictionary:
	for f in fields:
		if str(f.get("field_ref", {}).get("field", "")) == ref_field:
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
