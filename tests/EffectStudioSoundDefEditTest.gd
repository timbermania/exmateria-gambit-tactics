extends Node
## TDD guard for TIER-3 FEDS **bounded parameter editing** (ADR-0085 amendment
## 2026-08-11, slice 2): the SoundDefChannel encoder patches param bytes IN PLACE
## at their decode-annotated blob offsets through the EffectEditSession choke
## point — the stream is never restructured (every write is same-size). Seams:
##
##   (1) SoundDefChannel.apply_raw via EffectEditSession.apply_edit: "byte" kind
##       (opcode params / velocity / explicit durations / toggle substitutions),
##       plus the note data-byte's writable sub-field "note_key" ("note_delta_idx" is
##       refused: it is the parked length verb, ADR-0085 2026-08-19 §6)
##       (key*19 + delta_idx share one byte; delta_idx 0 = explicit-form flip =
##       structural = REJECTED). Declares invalidates_feds (never sim).
##   (2) Scalar undo replays the pre-edit value through the same dispatch.
##   (3) EffectData carries the FedsBank OBJECT (single source: page env,
##       playback, ghosts and the encoder all mutate/read the same raw bytes).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioSoundDefEditTest.tscn

const FedsBankScript = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_byte_edit_patches_bank_raw_and_undoes()
	_test_pitchbend16_word_writes_both_bytes_as_one_undo()
	_test_note_key_writes_and_keeps_the_duration_index()
	_test_note_duration_writes_are_refused()
	_test_out_of_range_writes_are_rejected()
	_test_page_feds_edit_evicts_only_resolving_ghosts()

	print("\n=== EffectStudioSoundDefEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSoundDefEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSoundDefEditTest")
		get_tree().quit(0)


# Same synthetic bank as FedsPairEditorTest: track A at 28 =
# AC 05 | 94 04 | E0 40 | 60 0C | 98 03 | 81 06 | 99 | 90, track B at 42 = D2 08.
func _make_data():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([44, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 42, 0])
	blob.append_array([0xAC, 0x05, 0x94, 0x04, 0xE0, 0x40, 0x60, 0x0C,
			0x98, 0x03, 0x81, 0x06, 0x99, 0x90])
	blob.append_array([0xD2, 0x08])
	var ed = EffectDataClass.new()
	ed.feds_bank = FedsBankScript.parse(blob)
	return ed


func _ref(kind: String, offset: int) -> Dictionary:
	return {"channel": "sound_def", "kind": kind, "offset": offset, "pair_idx": 0}


## Instrument param byte (blob offset 29, value 5) — the ring-1 archetype.
func _test_byte_edit_patches_bank_raw_and_undoes() -> void:
	var ed = _make_data()
	var session = Session.new(ed)
	var res: Dictionary = session.apply_edit(_ref("byte", 29), 12)
	_assert_eq(int(res.get("before_raw", -1)), 5, "before_raw is the pre-edit byte")
	_assert_eq(int(ed.feds_bank.raw[29]), 12, "the bank byte is patched in place")
	_assert_eq(bool(res.get("invalidates_sim", true)), false, "no framebuffer impact")
	_assert_eq(bool(res.get("invalidates_feds", false)), true,
			"declares the FEDS fan-out (ghosts + views re-derive)")
	_assert_eq(bool(res.get("faithful", {}).get("ok", false)), true, "in-range byte is faithful")
	_assert_true(session.undo(), "undo pops the edit")
	_assert_eq(int(ed.feds_bank.raw[29]), 5, "undo restores the byte")


# Track A at 28 = D3 FF FE 90 (PitchBend_Add_16bit −2, EndBar); track B at 32 = D2 08.
func _make_d3_data():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([34, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 32, 0])
	blob.append_array([0xD3, 0xFF, 0xFE, 0x90])
	blob.append_array([0xD2, 0x08])
	var ed = EffectDataClass.new()
	ed.feds_bank = FedsBankScript.parse(blob)
	return ed


## 0xD3 PitchBend_Add_16bit is a genuine 16-bit value (high<<8|low) — the "s16" kind
## writes BOTH bytes in one apply_raw call, so it is ONE field_ref, ONE undo entry,
## one honest number (ADR-0085 §3). The high byte is addressed at blob offset 29.
func _test_pitchbend16_word_writes_both_bytes_as_one_undo() -> void:
	var ed = _make_d3_data()
	var session = Session.new(ed)
	# Seed is −2 (0xFF 0xFE). Edit to +300 (0x012C): high 0x01, low 0x2C.
	var res: Dictionary = session.apply_edit(_ref("s16", 29), 300)
	_assert_eq(int(res.get("before_raw", 0)), -2, "before_raw is the pre-edit signed word")
	_assert_eq(int(res.get("after_raw", 0)), 300, "after_raw is the new signed word")
	_assert_eq(int(ed.feds_bank.raw[29]), 0x01, "high byte written")
	_assert_eq(int(ed.feds_bank.raw[30]), 0x2C, "low byte written in the SAME call")
	_assert_eq(bool(res.get("invalidates_feds", false)), true, "declares the FEDS fan-out")
	# One atomic edit → ONE undo that restores BOTH bytes.
	_assert_true(session.undo(), "one undo pops the whole word")
	_assert_eq(int(ed.feds_bank.raw[29]), 0xFF, "undo restores high byte")
	_assert_eq(int(ed.feds_bank.raw[30]), 0xFE, "undo restores low byte")
	_assert_true(not session.undo(), "the word was a SINGLE undo entry, now empty")
	# A negative word round-trips through two's-complement (−759 = 0xFD09).
	session.apply_edit(_ref("s16", 29), -759)
	_assert_eq(int(ed.feds_bank.raw[29]), 0xFD, "negative high byte")
	_assert_eq(int(ed.feds_bank.raw[30]), 0x09, "negative low byte")
	# Out-of-range 16-bit is rejected; the contract stays a signed 16-bit word.
	_assert_eq(session.apply_edit(_ref("s16", 29), 40000), {}, "value past s16 rejected")
	_assert_eq(int(ed.feds_bank.raw[29]), 0xFD, "high byte untouched on rejection")


## The note data byte (offset 35 = 0x0C: key 0, delta_idx 12) holds two fields, and only
## ONE of them is writable: the key. Editing it keeps the duration index untouched.
func _test_note_key_writes_and_keeps_the_duration_index() -> void:
	var ed = _make_data()
	var session = Session.new(ed)
	var res: Dictionary = session.apply_edit(_ref("note_key", 35), 2)   # C → D
	_assert_eq(int(ed.feds_bank.raw[35]), 2 * 19 + 12, "key edit keeps delta_idx")
	_assert_eq(bool(res.get("invalidates_feds", false)), true, "note edit fans out")
	_assert_true(session.undo(), "undo key")
	_assert_eq(int(ed.feds_bank.raw[35]), 0x0C, "byte fully restored")


## The duration half is REFUSED whatever the value (ADR-0085 2026-08-19 §6): a same-size
## write that is not same-TIME re-times the span and slides everything after it, which is
## the length verb 18c §7 parks. Index 0 was already refused as a form flip (±1 byte);
## now every index is, for the reason that always applied to all of them.
func _test_note_duration_writes_are_refused() -> void:
	var ed = _make_data()
	var session = Session.new(ed)
	for idx in [0, 1, 4, 18, 19]:
		_assert_eq(session.apply_edit(_ref("note_delta_idx", 35), idx), {},
				"delta_idx %d is the parked length verb, not a parameter" % idx)
	_assert_eq(int(ed.feds_bank.raw[35]), 0x0C, "byte untouched")
	_assert_true(not session.undo(), "nothing recorded to undo")


func _test_out_of_range_writes_are_rejected() -> void:
	var ed = _make_data()
	var session = Session.new(ed)
	_assert_eq(session.apply_edit(_ref("byte", 29), 300), {}, "non-byte value rejected")
	_assert_eq(int(ed.feds_bank.raw[29]), 5, "byte untouched on rejection")
	_assert_eq(session.apply_edit(_ref("byte", 4000), 1), {}, "offset past blob rejected")
	_assert_eq(session.apply_edit(_ref("note_key", 35), 14), {}, "key > 11 rejected")
	# 12 (tie) and 13 (note-form rest) are DECODER readings, not forms FFT authors
	# (ADR-0085 18c §1: zero occurrences in music or effects). The studio reads them
	# where they already exist and refuses to write new ones — it has one rest, `0x80`.
	_assert_eq(session.apply_edit(_ref("note_key", 35), 12), {}, "the tie form is not writable")
	_assert_eq(session.apply_edit(_ref("note_key", 35), 13), {}, "nor is the note-form rest")
	_assert_eq(int(ed.feds_bank.raw[35]), 0x0C, "…and neither refusal touched the byte")
	var no_bank = EffectDataClass.new()
	_assert_eq(Session.new(no_bank).apply_edit(_ref("byte", 29), 1), {},
			"no FEDS bank → inert error, not a crash")


## The page's invalidates_feds fan-out (mirror of the container branch): a FEDS
## byte edit re-derives the pair views and drops the ghost/energy of EVERY
## sound_id resolving into the edited pair — and ONLY those (an unrelated
## container's cached ghost survives; no blanket SPU re-render).
func _test_page_feds_edit_evicts_only_resolving_ghosts() -> void:
	var ed = _make_data()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	# sid 2 → container 0 → id 1 → PAIR 0 (the edited pair); sid 3 → container 1 → id 9
	# (resolves elsewhere / out of bank) — its ghost must be untouched.
	ed.sound_containers = {"containers": [
		{"mode": 0, "id_a": 1, "id_b": 0, "id_c": 0, "index": 0},
		{"mode": 0, "id_a": 9, "id_b": 0, "id_c": 0, "index": 1}]}
	ed.sound = {"for_each": [{"channel_index": 0, "max_keyframe": 2, "keyframes": [
		{"duration_frames": 10, "sound_id": 2},
		{"duration_frames": 5, "sound_id": 3}]}]}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	var page = Page.new()
	page._effect_data = ed
	page._timeline = tl
	var host := _FakeEditHost.new()
	host.bind(ed)
	page._host = host
	page._sound_env = {"feds_bank": ed.feds_bank, "sound_containers": ed.sound_containers}
	# 999 is an impossible render length — a sentinel that can't collide with the
	# fresh offline render the eviction triggers.
	page._ghost_by_sound_id = {2: 999, 3: 44}
	page._pair_views = []   # stale — the fan-out must recompute

	page._apply_edit({"channel": "sound_def", "kind": "byte", "offset": 29, "pair_idx": 0}, 12)

	_assert_true(int(page._ghost_by_sound_id.get(2, -1)) != 999,
			"the resolving trigger's stale ghost is dropped + re-projected")
	_assert_eq(int(page._ghost_by_sound_id.get(3, -1)), 44,
			"an unrelated container's cached ghost survives")
	_assert_eq(page._pair_views.size(), 1, "pair views recomputed after the byte patch")
	if page._pair_views.size() == 1:
		var cmds: Array = (page._pair_views[0].get("tracks", [])[0] as Dictionary).get("commands", [])
		var instr_param := -1
		for c in cmds:
			if str(c.get("label", "")) == "Instrument":
				instr_param = int((c.get("params", []) as Array)[0])
		_assert_eq(instr_param, 12, "the recomputed view reads the patched byte")
	page.free()
	tl.free()


## A host double that applies the edit through the REAL EffectEditSession, so the
## live bank gets the patch and the page's fan-out reads the real res flags.
class _FakeEditHost extends RefCounted:
	var _session = null
	func bind(ed) -> void:
		_session = load("res://src/effects/studio/EffectEditSession.gd").new(ed)
	func studio_apply_edit(ref: Dictionary, raw, defer_refold = false) -> Dictionary:
		return _session.apply_edit(ref, raw) if _session != null else {}


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
