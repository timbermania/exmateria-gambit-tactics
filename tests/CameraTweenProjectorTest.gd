extends Node
## TDD guard for the EDITABLE Camera projector (wayfinder #267). Flips the camera
## lane rows from read-only (shape:"const") to authorable (shape:"edit") using the
## F1 editor kit (`int` / `enum` / `bitflags`), each row carrying a write-side
## `field_ref` into the #255 choke point (channel "camera").
##
## A camera span is one (phase, sub-channel) slice of a keyframe. The projector
## emits TWO sections: an "Event" section of the keyframe-level fields shared by
## every sub-channel (End frame + the packed command word: Source / Interp /
## Channels / Param / Flags), then the sub-channel's own value section (angle →
## Pitch/Yaw/Roll, position → X/Y/Z, zoom → Zoom). field_refs address the span's
## phase + keyframe index.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CameraTweenProjectorTest.tscn

const Camera = preload("res://src/effects/studio/CameraTweenProjector.gd")
const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_angle_value_section_three_editable_ints()
	_test_position_value_section()
	_test_zoom_value_section_single_int()
	_test_event_section_command_word_editors()
	_test_end_frame_editable_int()
	_test_event_section_has_readonly_length_row()
	_test_every_edit_row_addresses_the_camera_channel_at_the_spans_keyframe()
	_test_value_rows_carry_their_authoring_unit()
	_test_value_row_labels_follow_source_mode()
	_test_shake_motion_scopes_profile_and_relabels_values()
	_test_zoom_offset_row_is_inert_and_undecorated()
	_test_param_flags_are_readonly_and_marked_nonfunctional()

	print("\n=== CameraTweenProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraTweenProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraTweenProjectorTest")
		get_tree().quit(0)


func _test_angle_value_section_three_editable_ints() -> void:
	var secs := Camera.sections(_span("angle", Vector3i(11, 22, 33)))
	var f_pitch := _field(secs, "Pitch")
	_assert_eq(f_pitch.get("shape", ""), "edit", "Pitch is an editable row")
	_assert_eq(f_pitch.get("editor", ""), "int", "Pitch uses the int editor")
	_assert_eq(f_pitch.get("type", ""), "s16", "angle components are signed 16-bit")
	_assert_eq(int(f_pitch.get("value", -1)), 11, "Pitch seeded from angle.x")
	_assert_eq(_ref_field(f_pitch), "angle_x", "Pitch fans angle_x")
	_assert_eq(int(_field(secs, "Yaw").get("value", -1)), 22, "Yaw seeded from angle.y")
	_assert_eq(_ref_field(_field(secs, "Roll")), "angle_z", "Roll fans angle_z")


func _test_position_value_section() -> void:
	var secs := Camera.sections(_span("position", Vector3i(4, 5, 6)))
	_assert_eq(int(_field(secs, "X").get("value", -1)), 4, "X seeded from position.x")
	_assert_eq(_ref_field(_field(secs, "Y")), "position_y", "Y fans position_y")
	_assert_eq(_ref_field(_field(secs, "Z")), "position_z", "Z fans position_z")


func _test_zoom_value_section_single_int() -> void:
	var secs := Camera.sections(_span("zoom", Vector3i(2048, 0, 0)))
	var f := _field(secs, "Zoom")
	_assert_eq(f.get("editor", ""), "int", "Zoom is an int editor")
	_assert_eq(int(f.get("value", -1)), 2048, "Zoom seeded from zoom slot 0")
	_assert_eq(_ref_field(f), "zoom", "Zoom fans the zoom field")


func _test_event_section_command_word_editors() -> void:
	# command_raw 0x0841: source=0x040(DIRECT), interp=0x0800(LINEAR), mask=1, param=0.
	var secs := Camera.sections(_span("angle", Vector3i.ZERO))
	var src := _field(secs, "Source")
	_assert_eq(src.get("editor", ""), "enum", "Source is an enum editor")
	_assert_eq(int(src.get("value", -1)), 0x040, "Source seeded to the current source bits")
	_assert_true(_enum_has(src, 0x140, "CASTER"), "Source lists CASTER at its bit value 0x140")
	_assert_eq(_ref_field(src), "source_mode", "Source fans source_mode")

	# The interpolation field is split into a Motion binary (Move/Shake) + a kind-scoped
	# Profile enum, BOTH writing "interpolation". The fixture's interp = 0x0800 (LINEAR) is a
	# Move: Motion seeds to the Move representative, Profile lists the easings.
	var motion := _field(secs, "Motion")
	_assert_eq(motion.get("editor", ""), "enum", "Motion is an enum editor")
	_assert_eq(int(motion.get("value", -1)), 0x0800, "Motion seeded to the Move representative bits")
	_assert_true(_enum_has(motion, 0x0800, "Move (to target)"), "Motion lists Move at the LINEAR default")
	_assert_true(_enum_has(motion, 0x1000, "Shake"), "Motion lists Shake at the SHAKE_DAMPED default")
	_assert_eq(_ref_field(motion), "interpolation", "Motion fans the interpolation field")

	var profile := _field(secs, "Profile")
	_assert_eq(profile.get("editor", ""), "enum", "Profile is an enum editor")
	_assert_eq(int(profile.get("value", -1)), 0x0800, "Profile seeded to the current interp bits (LINEAR)")
	_assert_true(_enum_has(profile, 0x0200, "IMMEDIATE"), "Move Profile lists IMMEDIATE at 0x0200")
	_assert_true(_field(secs, "Profile").get("choices", []).size() == 7, "Move Profile lists the seven easings")
	_assert_eq(_ref_field(profile), "interpolation", "Profile fans the interpolation field")

	# The flat "Interp" row is GONE — replaced by the Motion/Profile pair.
	_assert_true(_field(secs, "Interp").is_empty(), "no flat Interp row (it is now Motion + Profile)")

	# channel_mask is a LOWERING artifact (ADR-0086), never an authored field — the
	# Channels bitflags that produced the orphan bug is GONE from the author vocabulary.
	_assert_true(_field(secs, "Channels").is_empty(), "no editable Channels row (channel_mask is not authored)")

	# Param / Flags are NOT editable command-word knobs — RE proved they are dead bits
	# (see _test_param_flags_are_readonly_and_marked_nonfunctional). They must not appear
	# as editable rows anywhere.
	_assert_true(not _has_edit_row(secs, "Param"), "Param is never an editable row")
	_assert_true(not _has_edit_row(secs, "Flags"), "Flags is never an editable row")


func _test_end_frame_editable_int() -> void:
	var secs := Camera.sections(_span("angle", Vector3i.ZERO))
	var f := _field(secs, "End frame")
	_assert_eq(f.get("editor", ""), "int", "End frame is an int editor")
	_assert_eq(int(f.get("value", -1)), 8, "End frame seeded from the keyframe")
	_assert_eq(_ref_field(f), "end_frame", "End frame fans end_frame")


## The Event section carries a read-only `const` "Length" row (authored_end -
## authored_start) so the author sees the span's extent WITHOUT it being editable —
## end_frame stays the only editable knob (moving end_frame is how you change length,
## which the packed schedule can then coalesce/split; a direct Length edit would be a
## second, conflicting way to say the same thing).
func _test_event_section_has_readonly_length_row() -> void:
	var secs := Camera.sections(_span("angle", Vector3i.ZERO))
	var length := _field(secs, "Length")
	_assert_eq(length.get("shape", ""), "const", "Length is a read-only const row")
	_assert_true(not length.has("field_ref"), "Length carries no write-side field_ref")
	_assert_eq(str(length.get("value", "")), "5", "Length = authored_end - authored_start (8-3)")
	# end_frame remains the ONE editable length knob.
	_assert_eq(_field(secs, "End frame").get("shape", ""), "edit", "End frame stays editable")


func _test_every_edit_row_addresses_the_camera_channel_at_the_spans_keyframe() -> void:
	var secs := Camera.sections(_span("angle", Vector3i.ZERO))
	var edits := 0
	for sec in secs:
		for f in sec.get("fields", []):
			if f.get("shape", "") != "edit":
				continue
			edits += 1
			var ref: Dictionary = f.get("field_ref", {})
			_assert_eq(str(ref.get("channel", "")), "camera", "%s fans the camera channel" % f.get("name"))
			_assert_eq(str(ref.get("context", "")), "phase1", "%s addresses the span's phase" % f.get("name"))
			_assert_eq(int(ref.get("ordinal", -1)), 2, "%s addresses the span's sub-channel ordinal" % f.get("name"))
			_assert_eq(str(ref.get("camera_channel", "")), "angle",
				"%s carries the sub-channel so a shared-field edit splits the right lane" % f.get("name"))
	_assert_true(edits >= 7, "the projector emits the full editable field set sans Channels (got %d)" % edits)


# --- fixtures --------------------------------------------------------------

## A representative camera span: phase1, sub-channel ordinal 2. The score model
## enriches `fields` with the raw values the projector seeds from. The projector
## addresses by ordinal (ADR-0086 dec. 5, #286), not the raw keyframe index.
## Each value row carries the authoring unit its inspector cell renders in — degrees for
## angle, tiles for position, × for zoom — so the SpinBox shows human numbers, not raw s16.
func _test_value_rows_carry_their_authoring_unit() -> void:
	var ang := Camera.sections(_span("angle", Vector3i(11, 22, 33)))
	_assert_true(_field(ang, "Pitch").get("unit", {}) == CameraUnits.ANGLE_DEG, "angle rows author in degrees")
	var pos := Camera.sections(_span("position", Vector3i(4, 5, 6)))
	_assert_true(_field(pos, "X").get("unit", {}) == CameraUnits.POS_TILES, "position rows author in tiles")
	var zm := Camera.sections(_span("zoom", Vector3i(2048, 0, 0)))
	_assert_true(_field(zm, "Zoom").get("unit", {}) == CameraUnits.ZOOM_X, "zoom row authors in ×")
	# A non-shake (move) row is a target/offset, not a symmetric amplitude — no ± decoration.
	_assert_eq(str(_field(ang, "Pitch").get("prefix", "")), "", "a move row carries no ± prefix")


## The value-row LABEL is honest about what the mode does with the value (#281): in a
## facing-anchored mode the yaw is an OFFSET, not an absolute heading.
func _test_value_row_labels_follow_source_mode() -> void:
	var secs := Camera.sections(_span_mode("angle", Vector3i(11, 22, 33), "TARGET", "LINEAR"))
	_assert_eq(_field(secs, "Yaw offset").get("editor", ""), "int", "TARGET yaw relabels to 'Yaw offset'")
	_assert_true(_field(secs, "Yaw").is_empty(), "the bare 'Yaw' label is gone in TARGET mode")
	# The field_ref still addresses angle_y — only the display label changed.
	_assert_eq(_ref_field(_field(secs, "Yaw offset")), "angle_y", "relabeled row still fans angle_y")


## When the command word carries shake interp bits (0x1000+), Motion seeds to Shake, Profile
## scopes to the three decays, and — composing with #281 CameraValueSemantics — the value rows
## relabel to "amplitude". A shake on the position track: command_raw has SHAKE_DAMPED bits and
## the decoded interpolation string agrees.
func _test_shake_motion_scopes_profile_and_relabels_values() -> void:
	var secs := Camera.sections(_span_shake("position", Vector3i(120, 0, 40)))
	var motion := _field(secs, "Motion")
	_assert_eq(int(motion.get("value", -1)), 0x1000, "Motion seeds to the Shake representative")
	var profile := _field(secs, "Profile")
	_assert_eq(int(profile.get("value", -1)), 0x1000, "Profile seeded to the current shake bits (Damped)")
	_assert_true(_enum_has(profile, 0x1200, "Direct"), "Shake Profile lists Direct (constant amplitude)")
	_assert_eq(profile.get("choices", []).size(), 3, "Shake Profile lists the three decays")
	# #281 composition: a SHAKE_* interp makes the value rows AMPLITUDE, not a target.
	_assert_eq(_field(secs, "X amplitude").get("editor", ""), "int", "shake relabels X to 'X amplitude'")
	_assert_true(_field(secs, "X").is_empty(), "the bare 'X' label is gone under shake")
	_assert_eq(_ref_field(_field(secs, "X amplitude")), "position_x", "amplitude row still fans position_x")
	# The value renders as a symmetric ± peak (a shake is random_in_range(-amp, +amp)).
	_assert_eq(str(_field(secs, "X amplitude").get("prefix", "")), "±", "shake value shows a ± prefix")
	_assert_true(_field(secs, "X amplitude").get("unit", {}) == CameraUnits.POS_TILES, "shake amplitude keeps the track's unit (tiles)")


## Param (bits 3-4) and Flags (bits 13-15) of the camera command word are DEAD BITS: static RE
## proved the PSX engine never reads them, and the data shows Flags is only ever set on a single
## misparsed table (research/working_documents/CAMERA_COMMAND_PARAM_FLAGS_ARE_INERT.md). So the
## projector must SHOW them (an author can see a non-zero value on a real effect) but DEMOTE them
## to read-only const rows in an "Advanced (raw)" section whose note marks them non-functional —
## never a working authoring knob, and never carrying a write-side field_ref.
func _test_param_flags_are_readonly_and_marked_nonfunctional() -> void:
	var secs := Camera.sections(_span_pf("angle", Vector3i.ZERO, 2, 5))
	var adv := _section(secs, "Advanced (raw)")
	_assert_true(not adv.is_empty(), "there is an 'Advanced (raw)' section")
	_assert_true(str(adv.get("note", "")).to_lower().contains("ignore"),
		"the section note marks the fields as ignored by the engine")
	# Shut on arrival, under a stable fold id: dead bits are the last thing the ~268px
	# inspector row should spend its height on, and without an id the hint would win on
	# every rebuild and the author would re-open the section forever.
	_assert_true(bool(adv.get("collapsed", false)), "and it opens collapsed")
	_assert_eq(str(adv.get("fold_id", "")), "camera-advanced",
		"…under a stable fold id, so a toggle outlives the rebuild")

	var param := _field(secs, "Param")
	_assert_eq(param.get("shape", ""), "const", "Param is a read-only const row")
	_assert_true(not param.has("field_ref"), "Param carries no write-side field_ref")
	_assert_eq(str(param.get("value", "")), "2", "Param shows its raw value")

	var flags := _field(secs, "Flags")
	_assert_eq(flags.get("shape", ""), "const", "Flags is a read-only const row")
	_assert_true(not flags.has("field_ref"), "Flags carries no write-side field_ref")
	_assert_eq(str(flags.get("value", "")), "5", "Flags shows its raw value")


## Zoom under OFFSET/CURSOR is a runtime NO-OP (CameraSubsystem._execute_zoom_command early-
## returns before any tween). The projector must relabel the row "(inert)" (#281 honesty) and,
## since a no-op is neither a target nor a shake peak, drop the ± amplitude decoration even when
## the interp is SHAKE_* — the label alone tells the truth.
func _test_zoom_offset_row_is_inert_and_undecorated() -> void:
	var secs := Camera.sections(_span_mode("zoom", Vector3i(2048, 0, 0), "OFFSET", "LINEAR"))
	_assert_eq(_field(secs, "Zoom (inert)").get("editor", ""), "int", "OFFSET zoom relabels to 'Zoom (inert)'")
	_assert_true(_field(secs, "Zoom").is_empty(), "the bare 'Zoom' label is gone under OFFSET")
	_assert_eq(str(_field(secs, "Zoom (inert)").get("prefix", "")), "", "an inert row carries no ± prefix")
	# Even a SHAKE interp stays inert (the runtime returns before the shake branch).
	var shk := Camera.sections(_span_mode("zoom", Vector3i(2048, 0, 0), "CURSOR", "SHAKE_DAMPED"))
	_assert_eq(_field(shk, "Zoom (inert)").get("editor", ""), "int", "CURSOR+SHAKE zoom is still inert, not amplitude")
	_assert_eq(str(_field(shk, "Zoom (inert)").get("prefix", "")), "", "inert+shake still carries no ± prefix")


## A span carrying an explicit non-zero param_index / flags so the read-only rows have
## something to display (the real ROM footprint an author would encounter, e.g. param=3 on
## a CASTER keyframe).
func _span_pf(channel: String, vec: Vector3i, param: int, flags: int) -> Dictionary:
	var span := _span(channel, vec)
	span["fields"]["param_index"] = param
	span["fields"]["flags"] = flags
	return span


## A span whose command word carries SHAKE_DAMPED bits, with the decoded interpolation string
## kept consistent so the #281 label classifier sees a shake too. source=DIRECT(0x040), mask=2.
func _span_shake(channel: String, vec: Vector3i) -> Dictionary:
	var span := _span(channel, vec)
	span["fields"]["command_raw"] = 0x1000 | 0x040 | 0x02
	span["fields"]["interpolation"] = "SHAKE_DAMPED"
	return span


func _span_mode(channel: String, vec: Vector3i, source_mode: String, interp: String) -> Dictionary:
	var span := _span(channel, vec)
	span["fields"]["source_mode"] = source_mode
	span["fields"]["interpolation"] = interp
	return span


func _span(channel: String, vec: Vector3i) -> Dictionary:
	var fields := {
		"camera_channel": channel,
		"angle": Vector3i.ZERO, "position": Vector3i.ZERO, "zoom": Vector3i.ZERO,
		"end_frame": 8, "command_raw": 0x0841,
		"channel_mask": 1, "param_index": 0, "flags": 0,
	}
	fields[channel] = vec
	# authored_start/end are the span's extent on the axis; Length reads them (8-3=5).
	return {"kind": "camera", "phase": "phase1", "keyframe_index": 2, "ordinal": 2,
		"authored_start": 3, "authored_end": 8, "fields": fields}


func _field(secs: Array, name: String) -> Dictionary:
	for sec in secs:
		for f in sec.get("fields", []):
			if f.get("name", "") == name:
				return f
	return {}


func _section(secs: Array, title: String) -> Dictionary:
	for sec in secs:
		if str(sec.get("title", "")) == title:
			return sec
	return {}


## True when a row of this name exists anywhere with shape "edit" (an editable widget).
func _has_edit_row(secs: Array, name: String) -> bool:
	for sec in secs:
		for f in sec.get("fields", []):
			if str(f.get("name", "")) == name and str(f.get("shape", "")) == "edit":
				return true
	return false


func _ref_field(f: Dictionary) -> String:
	return str(f.get("field_ref", {}).get("field", "<none>"))


func _enum_has(f: Dictionary, value: int, label: String) -> bool:
	for c in f.get("choices", []):
		if int(c.get("value", -999)) == value and str(c.get("label", "")) == label:
			return true
	return false


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
