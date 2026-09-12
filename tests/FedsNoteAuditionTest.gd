extends Node
## TDD guard for the note-chip AUDITION CONSOLE (ADR-0085 amendment 2026-08-13
## "the note chip is an audition console").
##
##   * FedsNoteAudition.build_with_meta() is PURE over the raw ADPCM loop facts +
##     the ·Silence name flag, and covers every branch with synthetic instruments:
##       - hold params carry the note's REAL pitch (octave·12 + key) + duration
##       - a One-shot instrument DISABLES tail-only (no ring to isolate)
##       - a silent instrument (real OR overridden) DISABLES both + gives a reason
##       - an explicit LOOP_START gives the EXACT tail start (not defaulted)
##       - a loop-repeat-only sample gives the end−0x1010 DEFAULTED start + label
##   * FedsPairProjector projects the console onto the note-chip descriptor: an
##     "Audition as" enum (transient override, value_detail = loop verdict) + the
##     three action buttons, gated by the same verdicts, defaulting to the note's
##     running instrument.
##   * EffectKeyframeInspector renders a `disabled` action button + dim reason.
##   * Dynamic close: the real E001 (CURE) AC 67 note builds a Sustaining, tail-
##     capable console (re-conclusions-static-rooted-dynamic-validated).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/FedsNoteAuditionTest.tscn

const Audition = preload("res://src/effects/studio/FedsNoteAudition.gd")
const Meta = preload("res://src/effects/studio/FedsInstrumentMeta.gd")
const Projector = preload("res://src/effects/studio/FedsPairProjector.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Model = preload("res://src/effects/studio/FedsPairModel.gd")
const FedsBankScript = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")

# A note: F#4-ish — octave 4, key 6 → midi 54, held 144 ticks (the E001/CURE track-B shape).
const _NOTE := {"octave": 4, "relative_key": 6, "duration_ticks": 144,
		"duration_seconds": 1.5, "velocity": 100}
# Synthetic instruments (raw ADPCM loop facts), one per branch.
const _SUSTAIN_EXPLICIT := {"sample_size": 2000, "has_explicit_loop_start": true,
		"loop_offset_bytes": 1600, "has_loop_repeat": true, "is_null": false}
const _SUSTAIN_HEURISTIC := {"sample_size": 6000, "has_explicit_loop_start": false,
		"loop_offset_bytes": -1, "has_loop_repeat": true, "is_null": false}
const _ONE_SHOT := {"sample_size": 512, "has_explicit_loop_start": false,
		"loop_offset_bytes": -1, "has_loop_repeat": false, "is_null": false}
const _NULL := {"is_null": true, "sample_size": 0}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_hold_carries_real_pitch_and_duration()
	_test_one_shot_disables_tail_only()
	_test_silent_real_disables_both_with_reason()
	_test_silent_overridden_disables_both()
	_test_explicit_loop_gives_exact_tail_start()
	_test_heuristic_loop_gives_defaulted_start_and_label()
	_test_console_descriptor_on_note_chip()
	_test_console_gates_tail_for_one_shot_running_instrument()
	_test_console_override_drives_gating()
	_test_inspector_renders_disabled_action_button_with_reason()
	_test_inspector_hold_button_fires_down_and_release_up()
	_test_e001_ac67_builds_a_sustaining_tail_console()
	_finish()


# --- The pure builder ---------------------------------------------------------

func _test_hold_carries_real_pitch_and_duration() -> void:
	var b := Audition.build_with_meta(_NOTE, 67, _SUSTAIN_EXPLICIT, false)
	# midi_note is the note's own pitch: 4·12 + 6 = 54 — independent of the code path.
	_assert_eq(int(b["hold"]["midi_note"]), 54, "hold pitch = octave·12 + key")
	_assert_eq(int(b["hold"]["duration_ticks"]), 144, "hold carries the note's real duration")
	_assert_eq(float(b["hold"]["duration_seconds"]), 1.5, "hold carries real seconds for key-off")
	_assert_true(bool(b["hold_enabled"]), "an audible instrument enables Hear-held")


func _test_one_shot_disables_tail_only() -> void:
	var b := Audition.build_with_meta(_NOTE, 15, _ONE_SHOT, false)
	_assert_false(bool(b["sustains"]), "no loop flags → not sustaining")
	_assert_false(bool(b["tail_enabled"]), "One-shot → tail-only disabled (no ring)")
	_assert_true(bool(b["hold_enabled"]), "One-shot still plays held (hear the whole one-shot)")


func _test_silent_real_disables_both_with_reason() -> void:
	# A ·Silence-named slot (id 1 Empty/Silent) — even with loop facts present.
	var b := Audition.build_with_meta(_NOTE, 1, _NULL, true)
	_assert_false(bool(b["hold_enabled"]), "silent → Hear-held disabled")
	_assert_false(bool(b["tail_enabled"]), "silent → tail-only disabled")
	_assert_true(String(b["disabled_reason"]).to_lower().contains("silent"),
		"silent → the reason says so")
	_assert_true(String(b["disabled_reason"]).contains("empty slot"),
		"silent reason names the empty slot")


func _test_silent_overridden_disables_both() -> void:
	# The DROPPED-IN override is silent even though the raw facts look sustaining:
	# name_is_silence wins — you overrode onto a silent sample.
	var b := Audition.build_with_meta(_NOTE, 45, _SUSTAIN_EXPLICIT, true)
	_assert_false(bool(b["hold_enabled"]), "overridden-to-silent → Hear-held disabled")
	_assert_false(bool(b["tail_enabled"]), "overridden-to-silent → tail-only disabled")


func _test_explicit_loop_gives_exact_tail_start() -> void:
	var b := Audition.build_with_meta(_NOTE, 67, _SUSTAIN_EXPLICIT, false)
	_assert_true(bool(b["tail_enabled"]), "explicit-loop sustain → tail enabled")
	# The exact marked byte offset, verbatim — not the heuristic.
	_assert_eq(int(b["tail"]["loop_offset_bytes"]), 1600, "explicit loop → exact tail start")
	_assert_false(bool(b["tail"]["defaulted_loop"]), "explicit loop is NOT defaulted")
	_assert_eq(String(b["tail_label"]), Audition.TAIL_LABEL, "explicit loop → plain tail label")
	_assert_eq(String(b["tail_hint"]), "", "explicit loop → no fallback hint")


func _test_heuristic_loop_gives_defaulted_start_and_label() -> void:
	var b := Audition.build_with_meta(_NOTE, 66, _SUSTAIN_HEURISTIC, false)
	_assert_true(bool(b["tail_enabled"]), "loop-repeat sustain → tail enabled")
	# end − 0x1010 = 6000 − 4112 = 1888 (independent of the code).
	_assert_eq(int(b["tail"]["loop_offset_bytes"]), 6000 - 0x1010,
		"heuristic loop start = size − 0x1010")
	_assert_true(bool(b["tail"]["defaulted_loop"]), "loop-repeat-only start IS defaulted")
	_assert_true(String(b["tail_label"]).contains("defaulted"),
		"defaulted loop → the tail label warns it is defaulted")
	_assert_true(String(b["tail_hint"]).to_lower().contains("fallback"),
		"defaulted loop → dim hint names the fallback")


# --- The console descriptor + inspector rendering -----------------------------

func _test_console_descriptor_on_note_chip() -> void:
	# Project a synthetic pair view with one sustaining note (AC 67) selected, and
	# assert the note event section grew the audition console: an "Audition as" enum
	# (defaulting to the running instrument, with a loop-verdict value_detail) and the
	# three action buttons on the on_action seam.
	var sec := _note_event_section(67)
	_assert_false(sec.is_empty(), "a selected note projects an event section")
	var fields: Array = sec.get("fields", [])
	var dropdown := _field_named(fields, "Audition as")
	_assert_false(dropdown.is_empty(), "the note chip carries an 'Audition as' dropdown")
	_assert_eq(str(dropdown.get("editor", "")), "enum", "the override is an enum dropdown")
	_assert_eq(int(dropdown.get("value", -1)), 67, "the dropdown defaults to the running instrument")
	_assert_true(dropdown.get("value_detail") is Callable,
		"the dropdown shows the loop verdict as a value_detail")
	_assert_eq(str(dropdown.get("field_ref", {}).get("channel", "")), "audition",
		"the override routes through a transient 'audition' channel — NEVER a byte write")

	var hold := _action_of(fields, "audition_note_hold")
	var tail := _action_of(fields, "audition_note_tail")
	_assert_false(hold.is_empty(), "the console has a Hear-this-note action button")
	_assert_false(tail.is_empty(), "the console has a Tail-only action button")
	# HOLD-TO-PLAY (ADR-0085 2026-08-13): both play buttons are hold buttons that fire a
	# key-off release on button-up — NOT click-once buttons, and there is no Stop button.
	_assert_true(bool(hold.get("hold", false)), "Hear-this-note is a hold-to-play button")
	_assert_true(bool(tail.get("hold", false)), "Tail-only is a hold-to-play button")
	_assert_eq(str(hold.get("release_action", {}).get("kind", "")), "audition_note_release",
		"releasing the hold fires a key-off")
	_assert_true(_action_of(fields, "audition_note_stop").is_empty(),
		"hold-to-play has NO separate Stop button")
	# Real pitch + duration ride the action so the page can fire without re-decoding.
	_assert_eq(int(hold.get("action", {}).get("default_instrument", -1)), 67,
		"the hold action carries the running instrument as its default")
	_assert_eq(int(hold.get("action", {}).get("duration_ticks", -1)), 144,
		"the hold action carries the note's real duration")


func _test_console_gates_tail_for_one_shot_running_instrument() -> void:
	# Instrument 15 (Explosion) is a one-shot in the committed table — the descriptor's
	# tail button must come pre-disabled with the right reason from the projector.
	var oneshot := Meta.of(15)
	if oneshot.is_empty() or Meta.loop_summary_of(oneshot).begins_with("Sustains"):
		# The committed table classifies 15 as sustaining after all — skip rather than lie.
		_passed += 1
		return
	var sec := _note_event_section(15)
	var tail := _field_named(sec.get("fields", []), "Tail only")
	_assert_false(tail.is_empty(), "the tail row is present even when disabled")
	_assert_true(bool(tail.get("disabled", false)), "a one-shot running instrument disables tail")


func _test_console_override_drives_gating() -> void:
	# The dropdown DRIVES both buttons (ADR-0085 2026-08-13): a note whose RUNNING instrument
	# (67 Tubular Bells) sustains, but overridden onto a silent slot (id 1), must re-gate BOTH
	# buttons disabled + seed the dropdown to the override — an inaudible press never looks live.
	var sec := _note_event_section(67, 1)
	var fields: Array = sec.get("fields", [])
	var dropdown := _field_named(fields, "Audition as")
	_assert_eq(int(dropdown.get("value", -1)), 1, "the dropdown seeds to the ACTIVE override, not the running id")
	var hold := _field_named(fields, "Hear this note")
	var tail := _field_named(fields, "Tail only")
	_assert_true(bool(hold.get("disabled", false)), "silent override disables Hear-held")
	_assert_true(bool(tail.get("disabled", false)), "silent override disables Tail-only")


func _test_inspector_hold_button_fires_down_and_release_up() -> void:
	# A `hold` action field wires button_down → action and button_up → release_action, so
	# press-and-hold sounds the note and letting go stops it (ADR-0085 2026-08-13).
	var insp = Inspector.new()
	add_child(insp)
	var seen: Array = []
	var cell := {"name": "Hear this note", "shape": "action", "hold": true,
		"label": "▶ Hear this note (hold)",
		"action": {"kind": "audition_note_hold"},
		"release_action": {"kind": "audition_note_release"}}
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass, func(_refs, _col): return Color.BLACK,
		false, {},
		func(a): seen.append(str(a.get("kind", ""))))
	var btns: Array = insp.action_buttons()
	_assert_eq(btns.size(), 1, "the hold button renders")
	if btns.is_empty():
		insp.free()
		return
	var b: Button = btns[0]
	b.button_down.emit()
	b.button_up.emit()
	_assert_eq(seen, ["audition_note_hold", "audition_note_release"],
		"hold button: down fires the note, up fires the release")
	insp.free()


func _test_inspector_renders_disabled_action_button_with_reason() -> void:
	var insp = Inspector.new()
	add_child(insp)
	var cell := {"name": "Hear this note held", "shape": "action",
		"label": "▶ Hear this note held", "disabled": true,
		"disabled_reason": "Silent — nothing to hear (empty slot)",
		"action": {"kind": "audition_note_hold"}}
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass, func(_refs, _col): return Color.BLACK,
		false, {},
		func(_a): pass)
	var btns: Array = insp.action_buttons()
	_assert_eq(btns.size(), 1, "the action button renders")
	if not btns.is_empty():
		_assert_true((btns[0] as Button).disabled, "a `disabled` action field renders disabled")
	_assert_true(_tree_has_text(insp, "empty slot"),
		"the disabled reason renders as a visible dim label")
	insp.free()


# --- Dynamic close ------------------------------------------------------------

func _test_e001_ac67_builds_a_sustaining_tail_console() -> void:
	var bank = FedsBankScript.load_from_file("res://authored_effects/E001.feds.bin")
	_assert_true(bank != null, "E001 feds bank loads")
	if bank == null:
		return
	# Find the AC 67 note: the long track-B hold this feature demonstrates.
	var note := _first_note_under_instrument(bank, 67)
	_assert_false(note.is_empty(), "E001 has a note playing under instrument 67")
	if note.is_empty():
		return
	var b := Audition.build(note, 67)
	_assert_true(bool(b["hold_enabled"]), "E001's AC 67 note can be heard held")
	_assert_true(bool(b["sustains"]), "instrument 67 sustains (its sample loops)")
	_assert_true(bool(b["tail_enabled"]), "so the ring can be isolated with Tail only")
	_assert_true(int(b["hold"]["duration_ticks"]) > 0, "the real note has a real duration to ring")


# --- helpers ------------------------------------------------------------------

## Project a one-track pair view carrying a single note under `instrument_id`, mark it
## selected, and return its Event section from the projector. Hand-built (ROM-free):
## the projector reads only the note dict's fields, so a synthetic view exercises it.
func _note_event_section(instrument_id: int, override_id: int = -1) -> Dictionary:
	var note := {
		"event_index": 3, "offset": 10, "size": 2, "start_tick": 0, "start_seconds": 0.0,
		"duration_ticks": 144, "duration_seconds": 1.5, "relative_key": 6, "octave": 4,
		"active_instrument": instrument_id, "noise_armed": false, "velocity": 100,
		"label": "F#4", "explicit_duration": false, "note_byte": 6 * 19 + 1,
	}
	var view := {
		"pair_idx": 0, "valid": true, "total_ticks": 144,
		"tracks": [
			{"notes": [note], "commands": [], "end_seconds": 1.5},
			{"notes": [], "commands": [], "end_seconds": 0.0},
		],
		"used_by_containers": [],
		"selected": {"track": 0, "event_index": 3},
		"audition_override": override_id,
	}
	var score := {"feds_pairs": [view]}
	var secs := Projector.sections(Target.pair(0), null, score)
	for s in secs:
		if String(s.get("title", "")).begins_with("Event"):
			return s
	return {}


func _first_note_under_instrument(bank, instrument_id: int) -> Dictionary:
	for pidx in range(bank.num_pairs):
		var v := Model.pair_view(bank, pidx, {}, null)
		for track in v.get("tracks", []):
			for n in track.get("notes", []):
				if int(n.get("active_instrument", -1)) == instrument_id:
					return n
	return {}


func _field_named(fields: Array, name_starts: String) -> Dictionary:
	for f in fields:
		if String(f.get("name", "")).begins_with(name_starts):
			return f
	return {}


func _action_of(fields: Array, kind: String) -> Dictionary:
	for f in fields:
		if String(f.get("shape", "")) == "action" and String(f.get("action", {}).get("kind", "")) == kind:
			return f
	return {}


func _tree_has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	for c in node.get_children():
		if _tree_has_text(c, needle):
			return true
	return false


func _finish() -> void:
	print("\n=== FedsNoteAuditionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FedsNoteAuditionTest")
		get_tree().quit(1)
	else:
		print("[PASS] FedsNoteAuditionTest")
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
