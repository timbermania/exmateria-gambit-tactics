extends Node
## FedsNoteAuditionEngineTest — the ENGINE-side reliability guard for the note-chip
## AUDITION CONSOLE's managed playback (ADR-0085 2026-08-13). The console used to poke
## ExMateriaAudioEngine.sfx_spu (unit 0) directly on one reserved voice; but unit 0 idles out of
## the render (session_count 0) once no cast holds it, so the producer stopped ticking it
## and the preview went SILENT after the first note. The fix routes previews through
## ExMateriaEffectSfx.audition_note_on/off — a RESERVED unit forced ACTIVE (session_count=1)
## while sounding. This guard locks that fix at the render seam.
##
## Deterministic, NOT real-time: drives ExMateriaEffectSfx in capture_mode via render_subs
## (same seam as EffectSoundCaptureTest), so there is no producer thread / master-bus
## warm-up flakiness. The audition unit renders through _render_sub_split only while
## _unit_active is true (session_count>0 or inside UNIT_IDLE_TAIL_SUBS), so:
##   - HOLD SUSTAINS PAST THE IDLE TAIL — a held note stays audible BEYOND 720 subs
##     (the idle-tail length). Remove `session_count = 1` and the unit idles at ~3 s and
##     the tail of the hold goes silent → this case fails. THIS is the fix's lock.
##   - REPEATS RELIABLY — key/off/key across many previews, each audible (voice rotation,
##     no "silent after the first").
##   - TAIL ONLY rings from the loop point and repeats.
##
## Run:  godot --path . res://tests/FedsNoteAuditionEngineTest.tscn
## Suite verdict: prints [PASS] / [FAIL] (picked up by tests/run_all_tests.sh).

const Meta = preload("res://src/effects/studio/FedsInstrumentMeta.gd")

const SUBS_PER_FRAME := 8
const SILENCE_THRESH := 0.004      # normalized peak that counts as "audible"
const IDLE_TAIL_SUBS := 720        # ExMateriaEffectSfx.UNIT_IDLE_TAIL_SUBS (mirror; ~3 s)
const MIDI_NOTE := 4 * 12 + 6      # a mid register note, matches the throwaway diag

var _wave_idx := -1                # waveset index of the sustaining instrument under test
var _inst = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	if not _pick_sustaining_instrument():
		print("[FAIL] no sustaining (looping) waveset instrument found to audition")
		get_tree().quit(1)
		return
	print("[audition] instrument waveset_idx=%d (raw id=%d) sample_size=%d"
		% [_wave_idx, _wave_idx - 1, int(_inst.sample_size)])

	ExMateriaEffectSfx.capture_mode = true
	var all_pass := true
	all_pass = _run_hold_audible() and all_pass
	all_pass = _run_sustain_past_idle_tail() and all_pass
	all_pass = _run_repeat_reliable() and all_pass
	all_pass = _run_tail_only() and all_pass
	all_pass = _run_release_on_off() and all_pass
	ExMateriaEffectSfx.capture_mode = false
	ExMateriaEffectSfx.audition_note_off()

	if all_pass:
		print("[PASS] managed note audition: held note sustains past the idle tail, repeats reliably, tail rings")
		get_tree().quit(0)
	else:
		print("[FAIL] one or more managed-audition reliability checks failed (see [hold]/[sustain]/[repeat]/[tail] lines)")
		get_tree().quit(1)


# ---- cases ------------------------------------------------------------------

## A held note is audible right after key-on.
func _run_hold_audible() -> bool:
	ExMateriaEffectSfx.audition_note_off()
	_settle()
	_hold_on()
	var env := _render(30)   # ~1 s
	ExMateriaEffectSfx.audition_note_off()
	var ok := _peak(env) >= SILENCE_THRESH
	print("[hold] key-on audible: peak=%.4f -> %s" % [_peak(env), "OK" if ok else "BAD"])
	return ok


## THE FIX: a held note must stay audible BEYOND the idle tail. Without the forced
## session_count=1, the unit idles at ~720 subs and the late window goes silent.
func _run_sustain_past_idle_tail() -> bool:
	ExMateriaEffectSfx.audition_note_off()
	_settle()
	_hold_on()
	# Render well past the idle tail (720 subs); sample the LATE window only.
	var total_subs := IDLE_TAIL_SUBS + 240   # ~4 s
	var late := PackedFloat32Array()
	var acc := 0
	while acc < total_subs:
		var sub := ExMateriaEffectSfx.render_subs(1)
		acc += 1
		if acc > IDLE_TAIL_SUBS + 60:         # only the window AFTER the idle tail lapses
			late.append(_sub_peak(sub))
	ExMateriaEffectSfx.audition_note_off()
	var ok := _peak(late) >= SILENCE_THRESH
	print("[sustain] audible past idle-tail (sub>%d): late_peak=%.4f -> %s"
		% [IDLE_TAIL_SUBS + 60, _peak(late), "OK" if ok else "BAD: unit idled out (force-active lost)"])
	return ok


## Repeated previews: key/off/key across N presses — each audible (no silent-after-first).
func _run_repeat_reliable() -> bool:
	var audible := 0
	const N := 8
	for i in range(N):
		_hold_on()
		var env := _render(8)   # short press
		if _peak(env) >= SILENCE_THRESH:
			audible += 1
		ExMateriaEffectSfx.audition_note_off()
		_render(4)              # brief gap (release)
	var ok := audible == N
	print("[repeat] %d/%d presses audible -> %s" % [audible, N, "OK" if ok else "BAD: dropped a press"])
	return ok


## Tail-only: key from the loop point (skip attack) and it rings; repeats reliably.
func _run_tail_only() -> bool:
	var meta := Meta.of(_wave_idx - 1)
	var loop_off := _tail_loop_offset(meta)
	if loop_off < 0:
		print("[tail] instrument has no usable loop point (skipping, not a failure)")
		return true
	var start_addr := ExMateriaSpu.Spu.RAM_INSTRUMENT_BASE + int(_inst.sample_offset) + loop_off
	var loop_addr := int(_inst.sample_offset) + loop_off
	var pitch := ExMateriaSound.PitchTable.note_to_pitch(MIDI_NOTE, int(_inst.fine_tune))
	var audible := 0
	const N := 4
	for i in range(N):
		ExMateriaEffectSfx.audition_note_off()
		_settle()
		ExMateriaEffectSfx.audition_note_on(_wave_idx, pitch, int(_inst.adsr1), int(_inst.adsr2),
				start_addr, loop_addr)
		var env := _render(12)
		if _peak(env) >= SILENCE_THRESH:
			audible += 1
		ExMateriaEffectSfx.audition_note_off()
	var ok := audible == N
	print("[tail] %d/%d tail-only rings audible -> %s" % [audible, N, "OK" if ok else "BAD"])
	return ok


## key-off must let it release/decay — after the idle tail lapses it is silent (not stuck).
func _run_release_on_off() -> bool:
	ExMateriaEffectSfx.audition_note_off()
	_settle()
	_hold_on()
	_render(20)
	ExMateriaEffectSfx.audition_note_off()
	# Render past the idle tail; the unit stops rendering → silence.
	var env := _render_subs_count(IDLE_TAIL_SUBS + 120)
	var last := -1
	for i in range(env.size()):
		if env[i] >= SILENCE_THRESH:
			last = i
	var ok := last >= 0 and last < env.size() - 5
	print("[release] key-off decays to silence (last audible %d/%d) -> %s"
		% [last, env.size(), "OK" if ok else "BAD: stuck note"])
	return ok


# ---- helpers ----------------------------------------------------------------

func _hold_on() -> void:
	var pitch := ExMateriaSound.PitchTable.note_to_pitch(MIDI_NOTE, int(_inst.fine_tune))
	ExMateriaEffectSfx.audition_note_on(_wave_idx, pitch, int(_inst.adsr1), int(_inst.adsr2))


## Pick the first non-silent, LOOPING (sustaining) waveset instrument, independent of the
## feature under test — Meta.loop_summary keyed on the raw id (waveset index - 1).
func _pick_sustaining_instrument() -> bool:
	var insts: Array = ExMateriaAudioEngine.waveset.instruments
	for w in range(1, insts.size()):
		var inst = insts[w]
		if inst == null or int(inst.sample_size) <= Meta.HEURISTIC_LOOP_SPAN:
			continue
		var meta := Meta.of(w - 1)
		if Meta.loop_summary_of(meta).begins_with("Sustains"):
			_wave_idx = w
			_inst = inst
			return true
	return false


func _tail_loop_offset(meta: Dictionary) -> int:
	if meta.is_empty() or bool(meta.get("is_null", false)):
		return -1
	if bool(meta.get("has_explicit_loop_start", false)) and int(meta.get("loop_offset_bytes", -1)) >= 0:
		return int(meta["loop_offset_bytes"])
	if bool(meta.get("has_loop_repeat", false)):
		return maxi(0, int(meta.get("sample_size", 0)) - Meta.HEURISTIC_LOOP_SPAN)
	return -1


## Drain the idle tail so a fresh case starts from a quiet, unforced unit.
func _settle() -> void:
	_render_subs_count(IDLE_TAIL_SUBS + 60)


func _render(frames: int) -> PackedFloat32Array:
	return _render_subs_count(frames * SUBS_PER_FRAME)


func _render_subs_count(n: int) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	for _i in range(n):
		env.append(_sub_peak(ExMateriaEffectSfx.render_subs(1)))
	return env


func _sub_peak(sub: PackedInt32Array) -> float:
	var pk := 0
	for v in sub:
		var a: int = absi(v)
		if a > pk:
			pk = a
	return float(pk) / 32767.0


func _peak(env: PackedFloat32Array) -> float:
	var p := 0.0
	for v in env:
		if v > p:
			p = v
	return p
