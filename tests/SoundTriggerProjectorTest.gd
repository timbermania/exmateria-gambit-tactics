extends Node
## TDD guard for SoundTriggerProjector — the SFX-lane inspector view. Beyond the existing
## editable Sound-id / Gap cells, ADR-0085 TIER-2 adds a FOLLOW-THE-REFERENCE link: a
## trigger's sound_id is a container index (container_idx = sound_id - 2), so the Sound
## section carries a "Plays" link that drills into the shared SoundContainer target
## (ADR-0073), the same way a particle span links to its emitter.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundTriggerProjectorTest.tscn

const Projector = preload("res://src/effects/studio/SoundTriggerProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_still_has_editable_sound_id_and_gap()
	_test_plays_link_follows_to_the_container_target()
	_test_identity_cell_is_labelled_track_with_tooltip()
	_test_sound_id_cell_explains_container_mapping()
	_test_gap_cell_explains_next_trigger()
	_test_terminator_projects_inert_end_of_track_section()

	print("\n=== SoundTriggerProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundTriggerProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundTriggerProjectorTest")
		get_tree().quit(0)


# A firing trigger span: sound_id 4 → container index 2. `fields` mirrors _sound_kf_fields.
func _span() -> Dictionary:
	return {
		"phase": "for_each", "channel_index": 0, "keyframe_index": 1,
		"fields": {"channel": 0, "sound_id": 4, "duration_frames": 11},
	}


func _field(fields: Array, name: String) -> Dictionary:
	for f in fields:
		if f.get("name", "") == name:
			return f
	return {}


func _sound_fields() -> Array:
	for s in Projector.sections(_span()):
		if s.get("title", "") == "Sound":
			return s.get("fields", [])
	return []


## The pre-existing editable cells stay: Sound id (u8 int) and Gap (s16 int).
func _test_still_has_editable_sound_id_and_gap() -> void:
	var fields := _sound_fields()
	_assert_eq(_field(fields, "Sound").get("value", -1), 4, "Sound id cell seeds the raw")
	_assert_eq(_field(fields, "Gap").get("value", -1), 11, "Gap cell seeds duration_frames")


## The new link: a trigger's sound_id resolves THROUGH SoundContainer[sound_id-2]. The
## Sound section carries a `link` field whose target is that container (index 2 for id 4),
## so the inspector renders a navigate button (ADR-0073).
func _test_plays_link_follows_to_the_container_target() -> void:
	var fields := _sound_fields()
	var link := _field(fields, "Plays")
	_assert_eq(link.get("shape", ""), "link", "the Plays cell is a link field")
	_assert_eq(link.get("target", {}), Target.container(2),
		"the link follows to SoundContainer[sound_id-2] = container 2")
	_assert_true(str(link.get("label", "")).find("2") != -1,
		"the link label names the container index")


# --- legibility pass (Q1/Q2/Q5), byte-faithful, no seam change -------------

## Q1: the lane-identity cell reads "Track" (not the ambiguous "Channel", which authors
## misread as an off-by-one index). It stays a const cell (identity, not an authored
## value) and carries a tooltip naming what it is. `channel_index` is a plain 0-based
## sub-track number — NOT off-by-1 (the emitter's E<i>→i+1 has no analog here).
func _test_identity_cell_is_labelled_track_with_tooltip() -> void:
	var fields := _sound_fields()
	var track := _field(fields, "Track")
	_assert_eq(track.get("shape", ""), "const", "the identity cell stays const (lane identity)")
	_assert_eq(str(track.get("value", "")), "0", "the Track cell shows the 0-based sub-track number")
	_assert_true(str(track.get("tooltip", "")).to_lower().find("track") != -1,
		"the Track cell has a tooltip naming the sub-track")
	_assert_true(_field(fields, "Channel").is_empty(),
		"the old ambiguous 'Channel' label is gone")


## Q2: the Sound id cell explains the container mapping (sound_id N≥2 → SoundContainer[N−2])
## via a tooltip, so the raw byte reads self-describingly next to the "Plays → container N"
## link. sound_id 4 → container 2.
func _test_sound_id_cell_explains_container_mapping() -> void:
	var fields := _sound_fields()   # _span() has sound_id 4
	var sid := _field(fields, "Sound")
	var tip := str(sid.get("tooltip", ""))
	_assert_true(tip.find("2") != -1 and tip.to_lower().find("container") != -1,
		"the Sound id tooltip explains the → container 2 mapping (sound_id 4 − 2)")

	# 0 / 1 are the SKIP sentinels — they resolve to no container, so no mapping is claimed.
	var skip_fields := _fields_for_sound_id(1)
	var skip_tip := str(_field(skip_fields, "Sound").get("tooltip", "")).to_lower()
	_assert_true(skip_tip.find("container") == -1, "a skip id (0/1) claims no container mapping")


## Q5: the Gap cell's tooltip states it is the space to the NEXT trigger on this track
## (now that a Gap edit actually shifts the later markers — Q3), so the number reads right.
func _test_gap_cell_explains_next_trigger() -> void:
	var fields := _sound_fields()
	var tip := str(_field(fields, "Gap").get("tooltip", "")).to_lower()
	_assert_true(tip.find("next trigger") != -1,
		"the Gap tooltip says 'frames until the next trigger on this track'")


## ADR-0085 "every event is accessible via a timeline handle": the TERMINATOR end-cap
## (role "terminator", index == max_keyframe) is SELECT-to-inspect only. Its inspector is
## INERT — a single read-only "end of track" section, NO editable Gap or Sound id and NO
## Plays link — because its byte (the last event's gap) is already owned by that event's Gap
## field; a second editor would be two-handles-one-byte. Its slot's sound_id (here 6, which
## LOOKS audible) must NOT surface a container link — the runtime never fires it.
func _test_terminator_projects_inert_end_of_track_section() -> void:
	var term := {
		"role": "terminator", "phase": "for_each", "channel_index": 0, "keyframe_index": 5,
		"fields": {"channel": 0, "sound_id": 6, "duration_frames": 0},
	}
	var sections := Projector.sections(term)
	_assert_eq(sections.size(), 1, "the terminator projects exactly one section")
	var fields: Array = sections[0].get("fields", []) if not sections.is_empty() else []
	# No editable / navigable cells.
	_assert_true(_field(fields, "Sound").is_empty(), "the terminator has NO editable Sound id")
	_assert_true(_field(fields, "Gap").is_empty(), "the terminator has NO editable Gap (its byte is the last event's)")
	_assert_true(_field(fields, "Plays").is_empty(), "the terminator has NO container link even with an audible-looking slot sid")
	# Every cell it DOES have is read-only (const), and something names it "end of track".
	var all_const := not fields.is_empty()
	var names_end := false
	for f in fields:
		if str(f.get("shape", "")) != "const":
			all_const = false
		var blob := (str(f.get("label", "")) + " " + str(f.get("value", "")) + " " + str(f.get("tooltip", ""))).to_lower()
		if blob.find("end of track") != -1 or blob.find("terminator") != -1:
			names_end = true
	_assert_true(all_const, "every terminator cell is read-only (const)")
	_assert_true(names_end, "the terminator section reads as the end-of-track end-cap")


func _fields_for_sound_id(sid: int) -> Array:
	var span := {
		"phase": "for_each", "channel_index": 0, "keyframe_index": 1,
		"fields": {"channel": 0, "sound_id": sid, "duration_frames": 11},
	}
	for s in Projector.sections(span):
		if s.get("title", "") == "Sound":
			return s.get("fields", [])
	return []


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
