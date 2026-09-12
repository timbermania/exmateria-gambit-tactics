extends Node
## TDD guard for Effect Studio SOUND TIMELINE authoring (Subsystem 3, #268) — the
## SFX-trigger tracks (for_each / phase1 / phase2 x channel 0-2) made editable through
## the same #255 choke point, reusing the F1 shared `int` editor (#264). A trigger's
## `sound_id` (u8) and `duration_frames` (s16 timing) are plain int editors; the write
## is `invalidates_sim = false` (sound has no framebuffer impact). Seams guarded here:
##
##   (1) SoundTriggerProjector.sections(span) emits EDITABLE "Sound" + "Gap"
##       cells (shape "edit", editor "int") carrying the THREE-dimensional field_ref
##       {channel:"sound", phase, channel_index, event_index, field}; "Channel" stays a
##       const_field (lane identity).
##   (2) EffectKeyframeInspector renders each as a seeded SpinBox; seeding fires no edit;
##       a value change fans exactly one write with the raw value.
##   (3) SoundChannel (via EffectEditSession.apply_edit) writes the raw field on the live
##       sound-dict keyframe (a reference type the score model reads), reports
##       invalidates_sim=false, and undo restores.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioSoundEditTest.tscn

const Projector = preload("res://src/effects/studio/SoundTriggerProjector.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_projector_emits_editable_int_cells()
	_test_inspector_renders_seeded_spinboxes()
	_test_encoder_writes_sound_id_and_undoes()
	_test_encoder_writes_duration_s16()
	_test_encoder_writes_anchor_offset_authoring_only()
	_test_duration_edit_invalidates_layout_not_sound_id()
	_test_compound_or_accumulates_invalidates_layout()
	_test_sound_id_edit_rederives_the_container_link_live()
	_test_reproject_renders_a_new_sound_id_from_the_cached_bank()
	_test_schedule_ghost_reproject_skips_when_nothing_to_render()
	_test_container_edit_keeps_cached_ghost_when_first_fire_unchanged()

	print("\n=== EffectStudioSoundEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSoundEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSoundEditTest")
		get_tree().quit(0)


# --- Seam 1: projector emits the editable sound cells ----------------------

func _test_projector_emits_editable_int_cells() -> void:
	var span := _span("phase1", 1, 3, 4, 5)
	var secs := Projector.sections(span)

	# Q1 legibility: the lane-identity cell reads "Track" (not the ambiguous "Channel").
	var channel := _field(secs[0], "Track")
	_assert_eq(channel.get("shape", ""), "const", "the Track cell stays const (lane identity)")

	var sid := _field(secs[0], "Sound")
	_assert_eq(sid.get("shape", ""), "edit", "the Sound id cell is editable")
	_assert_eq(sid.get("editor", ""), "int", "Sound id is an int editor")
	_assert_eq(sid.get("type", ""), "u8", "Sound id is a u8 (0-255)")
	_assert_eq(int(sid.get("value", -1)), 4, "the Sound id is seeded to the keyframe raw")
	_assert_true(sid.get("field_ref", {}) == {"channel": "sound", "phase": "phase1", "channel_index": 1, "event_index": 3, "field": "sound_id"},
		"the Sound id field_ref carries the three-dim address (phase + channel_index + event_index)")

	# ADR-0085 conformance: the timing field surfaces as `Gap` (space to the next
	# trigger), not `Duration` — a trigger is an instant, so this is a gap, not a length.
	var dur := _field(secs[0], "Gap")
	_assert_eq(dur.get("shape", ""), "edit", "the Gap cell is editable")
	_assert_eq(dur.get("editor", ""), "int", "Gap is an int editor")
	_assert_eq(dur.get("type", ""), "s16", "Gap is an s16 timing value")
	_assert_eq(int(dur.get("value", -1)), 5, "the Gap is seeded to the keyframe raw")
	_assert_eq(dur.get("field_ref", {}).get("field", ""), "duration_frames", "the Gap field_ref addresses duration_frames")
	_assert_eq(dur.get("field_ref", {}).get("channel_index", -1), 1, "the Gap field_ref carries the int channel_index")


# --- Seam 2: inspector renders seeded SpinBoxes ----------------------------

func _test_inspector_renders_seeded_spinboxes() -> void:
	var span := _span("for_each", 2, 0, 7, 12)
	var secs := Projector.sections(span)
	var insp = Inspector.new()
	add_child(insp)

	var mutations: Array = []
	insp.show_target(Target.span("sound:for_each:2#0"),
		[], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): mutations.append([ref, raw]),
		func(_refs, _col): return Color.BLACK)

	var ints: Array = insp.int_widgets()
	_assert_eq(ints.size(), 2, "the two editable cells render two SpinBoxes")
	if ints.size() < 2:
		return
	_assert_eq(int(ints[0].value), 7, "the Sound id SpinBox is seeded to the raw")
	_assert_eq(int(ints[1].value), 12, "the Gap SpinBox is seeded to the raw")
	_assert_eq(int(ints[0].max_value), 255, "the Sound id SpinBox is a u8 range")
	_assert_eq(mutations.size(), 0, "seeding fires NO spurious write")

	# Legibility (Q2/Q5): the projector-declared tooltips render onto the live widgets so
	# hovering the field explains it — not dead metadata.
	_assert_true(str(ints[1].tooltip_text).to_lower().find("next trigger") != -1,
		"the Gap SpinBox renders the 'next trigger' tooltip")
	_assert_true(str(ints[0].tooltip_text).to_lower().find("container") != -1,
		"the Sound id SpinBox renders the container-mapping tooltip")

	# Change the sound_id → one write carrying the raw value.
	ints[0].value = 9
	_assert_eq(mutations.size(), 1, "one Sound id change fans exactly one write")
	if not mutations.is_empty():
		_assert_eq(mutations[0][0].get("field", ""), "sound_id", "the write addresses sound_id")
		_assert_eq(mutations[0][1], 9, "the SpinBox fans the raw value 9")


# --- Seam 3: encoder writes sound_id on the live dict and undoes ------------

func _test_encoder_writes_sound_id_and_undoes() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf: Dictionary = data.sound["phase1"][0]["keyframes"][1]
	var before: int = int(kf["sound_id"])

	var ref := {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 1, "field": "sound_id"}
	var res: Dictionary = session.apply_edit(ref, 42)

	_assert_eq(res.get("invalidates_sim", true), false, "a sound edit has no framebuffer impact (no re-seek)")
	_assert_true(res.get("faithful", {}).get("ok", false), "an in-range byte is faithfully encodable")
	_assert_eq(int(kf["sound_id"]), 42, "the encoder writes the raw sound_id onto the live keyframe dict")
	_assert_eq(res.get("before_raw", -1), before, "the snapshot records the pre-edit value")

	_assert_true(session.undo(), "the edit is undoable")
	_assert_eq(int(kf["sound_id"]), before, "undo restores the original sound_id through the same dispatch path")


# --- Seam 4: duration_frames is an s16 write -------------------------------

func _test_encoder_writes_duration_s16() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf: Dictionary = data.sound["for_each"][2]["keyframes"][0]

	var ref := {"channel": "sound", "phase": "for_each", "channel_index": 2, "event_index": 0, "field": "duration_frames"}
	var res: Dictionary = session.apply_edit(ref, -300)

	_assert_eq(int(kf["duration_frames"]), -300, "the encoder writes a signed duration onto the live keyframe")
	_assert_true(res.get("faithful", {}).get("ok", false), "an in-range s16 is faithfully encodable")

	# Out-of-s16-range → non-destructive Faithful advisory says not encodable.
	var res2: Dictionary = session.apply_edit(ref, 40000)
	_assert_true(not res2.get("faithful", {}).get("ok", true), "a value past the s16 range is flagged not faithfully encodable")


# --- Seam 5: anchor_offset is an authoring-only write (ADR-0085) -----------

## The anchor lives as an extra key on the live sound keyframe (the authored JSON is
## already the sidecar). It writes through the SAME choke point, has no framebuffer
## impact (invalidates_sim=false), and — because it is NEVER lowered to E###.BIN — is
## ALWAYS faithful, even for a value a byte/s16 field would reject. Undo restores it.
func _test_encoder_writes_anchor_offset_authoring_only() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf: Dictionary = data.sound["phase1"][0]["keyframes"][1]

	var ref := {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 1, "field": "anchor_offset"}
	var res: Dictionary = session.apply_edit(ref, 18)

	_assert_eq(res.get("invalidates_sim", true), false, "an anchor edit has no framebuffer impact (no re-seek)")
	_assert_true(res.get("faithful", {}).get("ok", false), "the authoring-only anchor is always faithful")
	_assert_eq(int(kf["anchor_offset"]), 18, "the encoder writes anchor_offset onto the live keyframe dict")
	_assert_eq(int(res.get("before_raw", -1)), 0, "the snapshot records the pre-edit anchor (default 0)")

	# A large value a lowered byte/s16 field would reject is STILL faithful — the
	# anchor never reaches the ROM bytes.
	var res2: Dictionary = session.apply_edit(ref, 99999)
	_assert_true(res2.get("faithful", {}).get("ok", false), "anchor stays faithful for any value (never lowered)")

	_assert_true(session.undo(), "the anchor edit is undoable")
	_assert_true(session.undo(), "the first anchor edit is undoable too")
	_assert_eq(int(kf.get("anchor_offset", -1)), 0, "undo restores the original (absent) anchor to 0")


# --- Seam 6: the invalidates_layout axis (Q3 fix) --------------------------

## A Gap (duration_frames) edit shifts trigger i+1 and every later marker on the channel
## (EffectScoreModel runs `local += dur`), so it must declare the THIRD response axis —
## invalidates_layout — distinct from invalidates_sim (framebuffer). The page reprojects
## the timeline on it while PRESERVING transport. A sound_id / anchor_offset edit does NOT
## move any marker, so it stays layout-false (its ghost-length reproject is deferred).
func _test_duration_edit_invalidates_layout_not_sound_id() -> void:
	var data := _fake_data()
	var session = Session.new(data)

	var dur_ref := {"channel": "sound", "phase": "for_each", "channel_index": 2, "event_index": 0, "field": "duration_frames"}
	var dur_res: Dictionary = session.apply_edit(dur_ref, 20)
	_assert_true(dur_res.get("invalidates_layout", false), "a Gap edit invalidates the timeline marker layout")
	_assert_eq(dur_res.get("invalidates_sim", true), false, "a Gap edit does NOT invalidate the framebuffer (orthogonal axis)")

	var sid_ref := {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 1, "field": "sound_id"}
	var sid_res: Dictionary = session.apply_edit(sid_ref, 9)
	_assert_true(not sid_res.get("invalidates_layout", false), "a sound_id edit does NOT move a marker (layout-false; ghost reproject deferred)")

	var anc_ref := {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 1, "field": "anchor_offset"}
	var anc_res: Dictionary = session.apply_edit(anc_ref, 3)
	_assert_true(not anc_res.get("invalidates_layout", false), "an anchor edit does NOT move the fire marker (layout-false)")


## apply_compound OR-accumulates invalidates_layout the same way it does invalidates_sim,
## so a future multi-field inspector gesture that touches a Gap reprojects the ruler. A
## compound of only sound_id edits leaves layout untouched.
func _test_compound_or_accumulates_invalidates_layout() -> void:
	var data := _fake_data()
	var session = Session.new(data)

	var gap_compound := [
		{"field_ref": {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 0, "field": "sound_id"}, "new_raw": 4},
		{"field_ref": {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 1, "field": "duration_frames"}, "new_raw": 12},
	]
	var res: Dictionary = session.apply_compound(gap_compound)
	_assert_true(res.get("invalidates_layout", false), "a compound touching a Gap invalidates layout (OR over members)")

	var id_only := [
		{"field_ref": {"channel": "sound", "phase": "phase1", "channel_index": 0, "event_index": 0, "field": "sound_id"}, "new_raw": 6},
	]
	var res2: Dictionary = session.apply_compound(id_only)
	_assert_true(not res2.get("invalidates_layout", false), "a sound_id-only compound leaves layout untouched")


# --- fixtures -------------------------------------------------------------

## Seam 4 (the reported bug): the container "Plays" link + Sound-id tooltip are DERIVED from
## sound_id, so a sound_id edit must re-derive the inspector — otherwise the link only shows
## after clicking off and re-selecting the trigger. Editing a SILENT event (no link) up to an
## audible id must surface the "Plays → container N" link LIVE, in place, without a re-select.
func _test_sound_id_edit_rederives_the_container_link_live() -> void:
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	ed.sound = {"for_each": [{"channel_index": 0, "max_keyframe": 2, "keyframes": [
		{"duration_frames": 10, "sound_id": 0},   # kf0 SILENT → no container link
		{"duration_frames": 5, "sound_id": 6},
		{"duration_frames": 0, "sound_id": 0}]}]}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))

	var page = Page.new()
	page._effect_data = ed
	page._timeline = tl
	var host := _FakeEditHost.new()
	host.bind(ed)
	page._host = host
	var insp := _FakeInspector.new()
	page._inspector = insp
	page._nav = [Target.span("sound:for_each:0#0")]
	# The ghost LENGTH for sound 5 (as an offline SPU render would produce). _sound_env stays
	# empty in the test, so the page's re-projection keeps this injected map instead of clobbering
	# it — letting us assert the ghost tail follows the edit without driving the real SPU.
	page._ghost_by_sound_id = {5: 30}

	# Baseline: a silent event carries no container link AND no ghost tail.
	page._render_current()
	_assert_true(not _section_has_field(insp.last_sections, "Plays"),
		"a silent event shows no container link")
	_assert_eq(_span_ghost(tl, "sound:for_each:0#0"), 0, "a silent event has no ghost tail")
	var renders_before: int = insp.renders

	# Edit sound_id 0 → 5 (audible) through the choke point. The link AND the ghost tail must
	# both refresh in place.
	var ref := {"channel": "sound", "phase": "for_each", "channel_index": 0,
		"event_index": 0, "field": "sound_id"}
	page._apply_edit(ref, 5)

	_assert_true(insp.renders > renders_before,
		"a sound_id edit re-derives the inspector (no re-select needed)")
	_assert_true(_section_has_field(insp.last_sections, "Plays"),
		"the container 'Plays' link now appears live after the sound_id edit")
	_assert_eq(_span_ghost(tl, "sound:for_each:0#0"), 30,
		"the ghost tail updates live to the newly-selected sound's length (no re-select)")
	page.free()
	tl.free()


## A span's projected ghost length (frames) off the timeline's live score, or -1 if absent.
func _span_ghost(tl, span_id: String) -> int:
	for lane in tl._score.get("lanes", []):
		for span in lane.get("spans", []):
			if span.get("id", "") == span_id:
				return int(span.get("ghost_frames", -1))
	return -1


## Headful (real SPU + real E317 FEDS bank): the incremental re-projection renders a NEW
## sound_id offline from the CACHED bank and merges its ghost length into the map — the
## expensive path a brand-new selection takes (an already-known id no-ops and shows instantly).
## SKIPs when the SFX engine or E317 assets aren't present. NOT --headless.
func _test_reproject_renders_a_new_sound_id_from_the_cached_bank() -> void:
	var dir := "res://assets/effects/E317"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E317 assets absent")
		return
	if not (ExMateriaEffectSfx and ExMateriaEffectSfx.ready_ok):
		print("[SKIP] SFX engine not ready")
		return
	var JSONLoader = load("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
	var le = JSONLoader.load_dir(dir)
	if le == null or le.feds_bank == null:
		print("[SKIP] E317 has no FEDS bank")
		return

	var page = Page.new()
	page._effect_data = EffectDataClass.load_from_directory(dir)
	page._sound_env = {"feds_bank": le.feds_bank, "sound_containers": le.sound_containers}
	page._ghost_by_sound_id = {}   # empty → sound 2 is a NEW id that must be rendered
	page._energy_by_sound_id = {}

	page._reproject_sound_id(2)   # E317 fires sound 2 → a real pair with a rendered length

	_assert_true(page._ghost_by_sound_id.has(2),
		"a new sound_id is rendered into the ghost map from the cached bank")
	_assert_true(int(page._ghost_by_sound_id.get(2, 0)) > 0,
		"the rendered ghost has a real (non-zero) length")
	# An already-known id renders nothing (instant path): the map is unchanged.
	var before: int = int(page._ghost_by_sound_id[2])
	page._reproject_sound_id(2)
	_assert_eq(int(page._ghost_by_sound_id[2]), before,
		"re-selecting a known id does not re-render (instant, from the cached map)")
	page.free()


## The debounced ghost render must do NOTHING (schedule no timer, render nothing) when there's
## nothing to render: a silent id (0/1, no ghost), an already-cached id (the instant _rebuild_
## score covered it), or an effect with no FEDS bank. These are the early-outs that keep the
## ~0.6s render off the common paths — asserted synchronously on a bare page (no tree/SPU).
func _test_schedule_ghost_reproject_skips_when_nothing_to_render() -> void:
	var page = Page.new()
	# Already-cached id: the map is not disturbed and no render is triggered.
	page._sound_env = {"feds_bank": true, "sound_containers": {}}   # non-empty → not the no-env path
	page._ghost_by_sound_id = {5: 42}
	page._schedule_ghost_reproject(5)
	_assert_eq(int(page._ghost_by_sound_id.get(5, -1)), 42, "a cached sound_id renders nothing (map untouched)")
	# Silent id (< 2): never has a ghost.
	page._schedule_ghost_reproject(1)
	_assert_true(not page._ghost_by_sound_id.has(1), "a silent id (0/1) schedules no render")
	# No FEDS env: nothing to render against.
	page._sound_env = {}
	page._schedule_ghost_reproject(9)
	_assert_true(not page._ghost_by_sound_id.has(9), "with no FEDS bank, a new id schedules no render")
	page.free()


## The container-edit SNAPPINESS guard (the #289 lag fix): a container mode/id edit must
## NOT pay the offline SPU ghost re-render unless it actually moved the container's
## resolved FIRST fire. A mode flip (first fire is id_a for every mode 0-4) keeps the
## cached ghost untouched — the whole rebuild is pure re-projection, instant. An id_a
## edit DOES move the first fire, so the stale ghost is dropped and re-projected (here
## the new pair is deliberately out of bank range, so the re-render early-outs without
## touching the SPU — the test stays deterministic engine-or-not).
func _test_container_edit_keeps_cached_ghost_when_first_fire_unchanged() -> void:
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	# One trigger firing sid 2 → container 0 (PARITY_A, a=5 b=9): first fire = id_a = 5.
	ed.sound = {"for_each": [{"channel_index": 0, "max_keyframe": 1, "keyframes": [
		{"duration_frames": 10, "sound_id": 2}]}]}
	ed.sound_containers = {"containers": [
		{"mode": 1, "id_a": 5, "id_b": 9, "id_c": 0, "index": 0}]}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))

	var page = Page.new()
	page._effect_data = ed
	page._timeline = tl
	var host := _FakeEditHost.new()
	host.bind(ed)
	page._host = host
	# A 5-pair bank: id 5 → pair 4 (in range); id 9 → pair 8 (OUT of range, render no-ops).
	var fb = load("res://addons/exmateria_sound/runtime/feds_bank.gd").new()
	fb.pair_count_plus1 = 6
	# This fixture carries no FEDS bytes — the pair LANES are not this test's subject, and
	# nothing it asserts reads a decoded note. Say so, with one null slot per track, rather
	# than leaving the offset table accidentally EMPTY: that is what made `_track_view`
	# fail an index read ten times over, twice each, under a green verdict (#468). Zero is
	# the table's documented "no track here" sentinel, so this is the honest declaration of
	# a bank with no music in it, not a workaround.
	fb.track_offsets = PackedInt32Array()
	for _t in range(fb.num_pairs * 2):
		fb.track_offsets.append(0)
	page._sound_env = {"feds_bank": fb, "sound_containers": ed.sound_containers}
	page._ghost_by_sound_id = {2: 30}   # the cached ghost a snappy edit must NOT drop

	# Mode flip 1→4: fires 2,3,… reorder but fire 0 stays id_a → pair unchanged → the
	# cached ghost survives (NO erase, NO render — the lag fix).
	page._apply_edit({"channel": "sound_container", "index": 0, "field": "mode"}, 4)
	_assert_eq(int(page._ghost_by_sound_id.get(2, -1)), 30,
		"a mode change keeps the cached ghost (no SPU re-render)")

	# id_a 5→9: the FIRST fire moves → the stale ghost must be dropped and re-projected.
	page._apply_edit({"channel": "sound_container", "index": 0, "field": "id_a"}, 9)
	_assert_true(int(page._ghost_by_sound_id.get(2, -1)) != 30,
		"an id_a edit (first fire moved) drops the stale ghost and re-projects")
	page.free()
	tl.free()


## A host double that applies the edit through the REAL EffectEditSession (so the live sound
## dict gets the new sound_id and the page's re-derive reads it), returning the real res flags.
class _FakeEditHost extends RefCounted:
	var _session = null
	func bind(ed) -> void:
		_session = load("res://src/effects/studio/EffectEditSession.gd").new(ed)
	func studio_apply_edit(ref: Dictionary, raw, defer_refold = false) -> Dictionary:
		return _session.apply_edit(ref, raw) if _session != null else {}


## An inspector double: records how many times the page re-derived it and the sections it was
## last handed, so a test can assert a derived row (the "Plays" link) refreshed live.
class _FakeInspector extends Node:
	var renders: int = 0
	var last_sections: Array = []
	# The page writes this on every re-derive (EffectStudioPage.gd:4445, and :710 for the
	# focus inspector). A stub standing in for the real EffectKeyframeInspector must carry
	# it or the assignment throws `Invalid assignment of property or key
	# 'name_column_width'` and takes the re-derive down with it.
	var name_column_width: float = 0.0
	func show_target(_target, _header, sections, _a = null, _b = null, _c = null,
			_d = null, _e = null, _f = null, _g = null, _h = null,
			hide_inert = false, marker = {}, on_action = null) -> void:
		renders += 1
		last_sections = sections


## True if any section carries a field named `name`.
func _section_has_field(sections: Array, name: String) -> bool:
	for s in sections:
		for f in s.get("fields", []):
			if str(f.get("name", "")) == name:
				return true
	return false


func _span(phase: String, channel_index: int, kf_index: int, sound_id: int, duration: int) -> Dictionary:
	return {
		"phase": phase,
		"channel_index": channel_index,
		"keyframe_index": kf_index,
		"fields": {
			"channel": channel_index,
			"sound_id": sound_id,
			"duration_frames": duration,
		},
	}


func _fake_data() -> RefCounted:
	# Raw sound dict mirroring parse_sound_keyframes' shape.
	var data := _FakeData.new()
	data.sound = {
		"phase1": [
			{"channel_index": 0, "max_keyframe": 3, "keyframes": [
				{"duration_frames": 0, "sound_id": 0},
				{"duration_frames": 5, "sound_id": 2},
			]},
		],
		"for_each": [
			{"channel_index": 0, "max_keyframe": 1, "keyframes": [{"duration_frames": 0, "sound_id": 0}]},
			{"channel_index": 1, "max_keyframe": 1, "keyframes": [{"duration_frames": 0, "sound_id": 0}]},
			{"channel_index": 2, "max_keyframe": 1, "keyframes": [{"duration_frames": 10, "sound_id": 3}]},
		],
	}
	return data


class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var sound = null


func _field(section: Dictionary, name: String) -> Dictionary:
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
