extends Node
## Regression guard for BUG #2: studio SOUND EDITS must reach the runtime controller.
##
## The bug: the effect's sound is parsed TWICE into two independent in-memory copies.
## The studio (and the score/timeline) edit `EffectData.sound` — a raw dict — through the
## EffectEditSession choke point; but the playing EffectSoundController was fed a SEPARATE
## `EffectJSONLoader.load_dir()` parse (`_sound_loaded.sound_tracks`). So moving events,
## changing sound_id / duration mutated the copy the timeline draws while the controller
## kept sequencing the stale copy → the edit was audibly a no-op (exactly the user report).
##
## The fix (ADR-0085 single source of truth): EffectInstance._load_effect_sound() re-points
## `_sound_loaded.sound_tracks` at `effect_data.sound` before load_effect, so the controller's
## channels hold references into the SAME dict the studio mutates. The edit then reaches
## playback on the next replay.
##
## The loop drives the REAL path: a real loaded E317 (for_each ch0 fires sid 2 @kf1 and
## sid 3 @kf3) → the real _load_effect_sound seam → a real EffectSoundController pumped by a
## real EffectTimeline. It plays once (baseline fire count), edits kf1's sound_id 2→0 (a
## firing trigger becomes a skip) THROUGH the EffectEditSession choke point, then replays via
## EffectInstance.seek() and asserts the controller fired ONE FEWER trigger on that channel.
## Signal = EffectSoundController.pair_triggered — the honest "a trigger fired" event,
## upstream of the SPU. Deterministic, no audio device.
##
## Run: godot --path . res://tests/EffectSoundEditReachesPlaybackTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const EffectInstanceClass = ExMateriaEffects.EffectInstance
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const SoundSubsystemClass = preload("res://addons/exmateria_effects/subsystem/SoundSubsystem.gd")
const EffectEditSessionClass = preload("res://src/effects/studio/EffectEditSession.gd")

const EFFECT_DIR := "res://assets/effects/E317"   # for_each ch0: skip/fire(sid2)/skip/fire(sid3)
const EDIT_CHANNEL := 0                            # for_each channel_index 0
const EDIT_EVENT := 1                              # kf#1 — the sid-2 firing trigger
const PLAY_FRAMES := 200                           # past the whole for_each track


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] ExMateriaEffectSfx not ready")
		get_tree().quit(1)
		return
	var ok := _test_edit_reaches_playback()
	ok = _test_structural_feds_edit_reaches_playback() and ok
	if ok:
		print("[PASS] EffectSoundEditReachesPlaybackTest")
		get_tree().quit(0)
	else:
		print("[FAIL] EffectSoundEditReachesPlaybackTest")
		get_tree().quit(1)


func _test_edit_reaches_playback() -> bool:
	var effect_data = EffectDataClass.load_from_directory(EFFECT_DIR)
	if effect_data == null or not (effect_data.sound is Dictionary) or effect_data.sound.is_empty():
		print("[setup] %s has no effect_data.sound" % EFFECT_DIR)
		return false

	# Wire the sound path exactly as initialize() does, without the particle/overlay init.
	var inst = EffectInstanceClass.new()
	inst.effect_data = effect_data
	inst._load_effect_sound(EFFECT_DIR)
	if inst._sound_controller == null:
		print("[setup] _load_effect_sound armed no controller (has_sound false?)")
		inst.free()
		return false

	# The single-source link: the controller must read the SAME dict the studio edits.
	if not is_same(inst._sound_loaded.sound_tracks, effect_data.sound):
		print("[link] _sound_loaded.sound_tracks is NOT effect_data.sound — edits can't reach playback")
		inst.free()
		return false

	var fires := {"ch": [], "phase": []}  # from_channel + from_phase per trigger
	inst._sound_controller.pair_triggered.connect(func(_p: int, from_channel: int, _s: int, from_phase: String) -> void:
		(fires["ch"] as Array).append(from_channel)
		(fires["phase"] as Array).append(from_phase))

	# A real timeline drives the controller through the SoundSubsystem, like initialize().
	var header: Dictionary = inst._sound_loaded.timeline_header
	var p1d := int(header.get("phase1_duration", 0))
	var p2s := p1d + int(header.get("phase2_delay", 0))
	var timeline = EffectTimelineClass.new()
	timeline.setup(p1d, p2s, {})
	timeline.set_subsystems([null, SoundSubsystemClass.new(inst._sound_controller), null, null, null])
	timeline.start()
	inst.effect_timeline = timeline

	# Baseline play: pump forward past the whole track.
	inst.seek(PLAY_FRAMES)
	var base_ch0 := _count(fires["ch"], EDIT_CHANNEL)
	# The addon must report the FIRING PHASE (the Solo/Mute fix, #289-adjacent): E317's fires
	# are all on the for_each track, so every reported phase must be "for_each". A wrong/empty
	# phase would make the gate key "<phase>:<ci>" never match muted_sound → mute silently no-ops.
	var phases: Array = fires["phase"]
	var phase_ok := not phases.is_empty()
	for ph in phases:
		if str(ph) != "for_each":
			phase_ok = false

	# Studio edit through the SAME choke point the inspector uses: kf#1 sid 2 → 0 (skip).
	var session = EffectEditSessionClass.new(effect_data)
	var res: Dictionary = session.apply_edit({
		"channel": "sound", "phase": "for_each",
		"channel_index": EDIT_CHANNEL, "event_index": EDIT_EVENT, "field": "sound_id",
	}, 0)
	if res.is_empty():
		print("[edit] apply_edit returned empty — the choke point rejected the edit")
		inst.free()
		return false

	# Replay: rewind (backward seek re-arms the cast) then pump forward again.
	inst.seek(0)
	(fires["ch"] as Array).clear()
	inst.seek(PLAY_FRAMES)
	var after_ch0 := _count(fires["ch"], EDIT_CHANNEL)

	var ok := true
	if not phase_ok:
		print("[phase] pair_triggered reported phases %s, expected all 'for_each' — the Solo/Mute gate key can't match" % [phases])
		ok = false
	if base_ch0 != 2:
		print("[baseline] channel %d fired %d triggers, expected 2 (kf1 sid2 + kf3 sid3) — harness broken" % [
			EDIT_CHANNEL, base_ch0])
		ok = false
	if after_ch0 != base_ch0 - 1:
		print("[edit] after silencing kf1, channel %d fired %d, expected %d — the edit did NOT reach playback (BUG #2)" % [
			EDIT_CHANNEL, after_ch0, base_ch0 - 1])
		ok = false
	if ok:
		print("[edit] channel %d fired %d→%d after kf1 sid 2→0 — studio edits reach playback" % [
			EDIT_CHANNEL, base_ch0, after_ch0])
	inst.free()
	return ok


## BUG #2's TWIN, on the FEDS bank (2026-08-19). `_load_effect_sound` re-points
## `_sound_loaded.feds_bank` at `effect_data.feds_bank`, which is enough while the object
## identity holds — a same-size param patch mutates `raw` in place and both names see it.
## Every STRUCTURAL verb breaks that: insert / delete / un-rest / paint / drag / outro /
## prune, and undo of any of them, REPLACE `data.feds_bank` with a freshly built object,
## which is exactly what makes the snapshot undo exact. The one-time re-point kept the OLD
## object, so from the first structural edit onward the studio drew one bank and Play
## sounded another — and every later param patch landed on the bank nobody was playing.
##
## The guard: after a real structural verb through the real choke point, the bank the
## audible path reaches must be the one the editor is holding.
func _test_structural_feds_edit_reaches_playback() -> bool:
	var effect_data = EffectDataClass.load_from_directory(EFFECT_DIR)
	if effect_data == null or effect_data.feds_bank == null:
		print("[setup] %s has no feds_bank" % EFFECT_DIR)
		return false
	var inst = EffectInstanceClass.new()
	inst.effect_data = effect_data
	inst._load_effect_sound(EFFECT_DIR)
	var before = effect_data.feds_bank
	if not is_same(inst._live_feds_bank(), before):
		print("[feds] the audible path does not start on EffectData's bank")
		inst.free()
		return false
	# A real structural verb through the real choke point: add an Instrument at track 0's
	# first byte boundary. Every FEDS structural verb swaps the bank; this is the cheapest.
	var session = EffectEditSessionClass.new(effect_data)
	var res: Dictionary = session.insert_event({
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": before.track_offsets[0], "opcode": 0xAC, "params": [5]})
	if res.is_empty():
		print("[feds] the structural verb was refused — harness broken")
		inst.free()
		return false
	var ok := true
	if is_same(effect_data.feds_bank, before):
		print("[feds] the verb did not swap the bank — this guard is testing nothing")
		ok = false
	if is_same(inst._sound_loaded.feds_bank, effect_data.feds_bank):
		print("[feds] `_sound_loaded.feds_bank` tracked the swap — the one-time re-point is "
				+ "no longer the hazard this guard exists for; simplify it")
		ok = false
	if not is_same(inst._live_feds_bank(), effect_data.feds_bank):
		print("[feds] the audible path is on the PRE-EDIT bank — a structural edit is silent "
				+ "and every later param patch lands on the bank nobody plays")
		ok = false
	if ok:
		print("[feds] a structural verb swapped the bank and the audible path followed it")
	inst.free()
	return ok


func _count(arr: Array, value: int) -> int:
	var n := 0
	for v in arr:
		if int(v) == value:
			n += 1
	return n
