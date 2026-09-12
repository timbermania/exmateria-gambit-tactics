extends Node

## MusicTypewriterStressTest — reproduce the scenario-player "music skips while
## the typewriter runs" report as a MEASURED, red/green loop.
##
## v2: drives the REAL DialogueOverlay (the 2D prayer typewriter, Dialog 0x09 —
## the "just music with typewriter" scene). Its sink `typewriter_append` does
## `current_text += ch; _redraw_label()`, and `_redraw_label` TEARS DOWN AND
## REBUILDS a TextureRect per revealed glyph EVERY glyph (DialogueOverlay.gd:379)
## → O(n²) scene-tree node churn per message, on the MAIN thread. (The boxed
## DialogueBox uses cheap visible_chars and is NOT implicated — only the prayer
## overlay.)
##
## What the main thread can starve CHANGED with #385 tasks 1/3. It used to be
## the audio itself: SMDPlayer._push_ready_audio ran in _process, so churn
## delayed the push, AudioStreamGeneratorPlayback emptied, and get_skips() rose.
## There is no ring to empty now — the SPU renders inside the audio thread's own
## `_mix`. What the main thread still owns is the SEQUENCER: it stages each
## tick's register writes into the SPU's command queue, one second ahead of the
## audio clock. Starve that for a whole second and the audio thread reaches a
## write after its frame has passed — counted as `overdue` in the SPU's deferred
## stats, and heard as the music hesitating rather than as a dropout.
##
## So this test still measures the same claim (main-thread churn must not
## disturb the music) against the mechanism that can now carry it. The margin is
## reported per phase as the scheduler's minimum lead: overdue writes only start
## once that reaches zero, so a lead collapsing toward zero is the early warning
## an overdue count of 0 cannot give you.
##
## v1 fired only the per-glyph SFX cue and stayed GREEN on a fast box (144fps,
## no main-thread saturation). The missing ingredient was the overlay redraw.
##
## Differential ramp: phase 0 = music only (skip baseline); later phases raise
## the count of concurrently-typing overlays. If the bug is real, skips stay flat
## in phase 0 and climb as overlay count climbs.
##
## Run (HEADFUL, audible — NEVER --headless):
##   godot --path . res://tests/MusicTypewriterStressTest.tscn

const DialogueOverlayClass = preload("res://src/scenarios/DialogueOverlay.gd")

# concurrently-typing prayer overlays per phase.
const PHASES := [
	{"label": "baseline (music only)", "overlays": 0,  "secs": 6.0},
	{"label": "1 overlay",             "overlays": 1,  "secs": 6.0},
	{"label": "4 overlays",            "overlays": 4,  "secs": 6.0},
	{"label": "12 overlays",           "overlays": 12, "secs": 6.0},
]

const SKIP_RATE_FAIL_DELTA := 1.0

# A long prayer-like message so each _redraw_label rebuilds many glyphs.
const MSG_TOKENS := [
	{"type": "text", "value": "Ovelia prays to the gods for deliverance from"},
	{"type": "newline"},
	{"type": "text", "value": "the darkness that has fallen upon fair Ivalice"},
	{"type": "newline"},
	{"type": "text", "value": "on this the longest and most sorrowful night"},
]

var _phase_idx := 0
var _phase_t := 0.0
var _last_print := 0.0
var _skips_at_phase_start := 0
## Smallest scheduler lead seen this phase, in ms. The margin the music has
## before a late register write becomes possible at all.
var _min_lead_ms := 1.0e9
var _under_at_phase_start := 0
var _baseline_skip_rate := -1.0
var _worst_storm_skip_rate := 0.0
var _worst_storm_label := ""

var _overlays: Array = []   # pool of DialogueOverlay, sized to the max phase

var _cap: AudioEffectCapture
var _g_maxabs := 0.0
var _g_clip := 0
var _g_maxjump := 0.0
var _g_prev := Vector2.ZERO
var _g_have := false
## Armed once music is confirmed playing. From then on, a null SPU is not
## "0 late writes" -- it is the measurement failing, and it must not read as a
## pass. Every metric below funnels through _music_spu(), so if playback stops
## mid-run every one of them silently returns 0, `induced` cannot exceed the
## gate, and this rig prints [PASS] having measured nothing.
var _measuring := false
var _lost_music := false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = false
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()

	_cap = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _cap)

	var any_music := false
	for slot in [17, 18, 16, 10, 1, 0]:
		if MusicPlayer.play_slot(slot):
			any_music = true
			_measuring = true
			print("[stress] music started on slot %d" % slot)
			break
	if not any_music:
		print("[FAIL] no music slot played")
		get_tree().quit(1)
		return

	# Build the overlay pool (max phase size). Add to tree so each _ready runs
	# (loads the font atlas + builds its _container) before we type into it.
	var max_overlays := 0
	for p in PHASES:
		max_overlays = maxi(max_overlays, int(p["overlays"]))
	for i in range(max_overlays):
		var ov: CanvasLayer = DialogueOverlayClass.new()
		add_child(ov)
		_overlays.append(ov)
	await get_tree().process_frame
	if max_overlays > 0 and _overlays[0]._font_texture == null:
		print("[WARN] font atlas not loaded — _redraw_label will no-op; repro invalid")

	print("[stress] real DialogueOverlay ramp: %s" % ", ".join(PHASES.map(func(p): return "%s" % p["label"])))
	print("[stress] per-second: late writes / dropped writes / scheduler lead | final-mix peak/clip/maxjump | overlays fps")
	await get_tree().create_timer(1.0).timeout
	_begin_phase(0)


func _begin_phase(idx: int) -> void:
	_phase_idx = idx
	_phase_t = 0.0
	_last_print = 0.0
	_skips_at_phase_start = _music_skips()
	_under_at_phase_start = _music_underruns()
	var n: int = PHASES[idx]["overlays"]
	# (Re)start typing on the first n overlays; hide the rest.
	for i in range(_overlays.size()):
		var ov = _overlays[i]
		if i < n:
			_show(ov)
		else:
			if ov.has_method("clear"):
				ov.clear()
	print("[stress] --- phase %d: %s (%d overlays typing) ---" % [idx, PHASES[idx]["label"], n])


func _show(ov) -> void:
	# Stagger positions so they don't perfectly overlap (also mimics real UI).
	var x := 32 + (_overlays.find(ov) * 7) % 180
	var y := 24 + (_overlays.find(ov) * 11) % 140
	ov.show_overlay(MSG_TOKENS.duplicate(true), x, y, 0)


func _process(delta: float) -> void:
	if _phase_idx >= PHASES.size():
		return
	_phase_t += delta

	var n: int = PHASES[_phase_idx]["overlays"]
	for i in range(n):
		var ov = _overlays[i]
		ov.advance_frames(1)
		# Keep them continuously typing so the redraw cost stays saturated.
		if not ov._typewriter.is_active():
			_show(ov)

	_drain_master_tap()

	if _phase_t - _last_print >= 1.0:
		_last_print = _phase_t
		_report_second()

	if _phase_t >= float(PHASES[_phase_idx]["secs"]):
		_close_phase()
		if _phase_idx + 1 < PHASES.size():
			_begin_phase(_phase_idx + 1)
		else:
			_phase_idx = PHASES.size()
			_finish()


func _report_second() -> void:
	var sk := _music_skips() - _skips_at_phase_start
	var un := _music_underruns() - _under_at_phase_start
	var lead := _music_lead_ms()
	if lead < _min_lead_ms:
		_min_lead_ms = lead
	print("[stress %-20s t=%4.1fs] late=%d dropped=%d lead=%.0fms | mix peak=%.2f clip=%d maxjump=%.3f | ov=%d fps=%d" % [
		PHASES[_phase_idx]["label"], _phase_t, sk, un, lead,
		_g_maxabs, _g_clip, _g_maxjump,
		PHASES[_phase_idx]["overlays"], Engine.get_frames_per_second()])
	_g_maxabs = 0.0
	_g_clip = 0
	_g_maxjump = 0.0


func _close_phase() -> void:
	var sk := _music_skips() - _skips_at_phase_start
	var rate := float(sk) / float(PHASES[_phase_idx]["secs"])
	if int(PHASES[_phase_idx]["overlays"]) == 0:
		_baseline_skip_rate = rate
	elif rate > _worst_storm_skip_rate:
		_worst_storm_skip_rate = rate
		_worst_storm_label = PHASES[_phase_idx]["label"]
	print("[stress] phase %d done: %d late writes over %.0fs = %.2f/sec, min lead %.0fms" % [
		_phase_idx, sk, PHASES[_phase_idx]["secs"], rate, _min_lead_ms])
	_min_lead_ms = 1.0e9


func _finish() -> void:
	if _lost_music:
		print("[FAIL] music playback stopped during the run, so every late-write "
			+ "reading after that point was 0 by absence, not by health. This rig "
			+ "cannot report on a run it did not measure.")
		get_tree().quit(1)
		return
	var base := maxf(_baseline_skip_rate, 0.0)
	var induced := _worst_storm_skip_rate - base
	print("[stress] ===== RESULT =====")
	print("[stress] baseline late-write rate  = %.2f/sec (music only)" % base)
	print("[stress] worst storm late-write rate = %.2f/sec (%s)" % [_worst_storm_skip_rate, _worst_storm_label])
	print("[stress] typewriter-induced late writes = %.2f/sec over baseline" % induced)
	if induced > SKIP_RATE_FAIL_DELTA:
		print("[FAIL] prayer-overlay typewriter starves the music scheduler: +%.2f late writes/sec over baseline (gate %.2f). Repro confirmed." % [induced, SKIP_RATE_FAIL_DELTA])
		get_tree().quit(1)
		return
	print("[PASS] typewriter overlays did NOT induce late music writes over baseline (+%.2f, gate %.2f)." % [induced, SKIP_RATE_FAIL_DELTA])
	get_tree().quit(0)


func _drain_master_tap() -> void:
	if _cap == null:
		return
	var navail := _cap.get_frames_available()
	if navail <= 0:
		return
	var buf: PackedVector2Array = _cap.get_buffer(navail)
	for fr in buf:
		var a := maxf(absf(fr.x), absf(fr.y))
		_g_maxabs = maxf(_g_maxabs, a)
		if a >= 0.999:
			_g_clip += 1
		if _g_have:
			_g_maxjump = maxf(_g_maxjump, (fr - _g_prev).length())
		_g_prev = fr
		_g_have = true


## Register writes the audio thread reached after their own frame had passed —
## the scheduler fell a full lead behind. This is the audible symptom now, and
## it is the successor to AudioStreamGeneratorPlayback.get_skips().
func _music_skips() -> int:
	var spu = _music_spu()
	if spu == null:
		return 0
	return int(spu.get_deferred_stats().get("overdue", 0))


## Register writes DROPPED because the command ring was full. Distinct from a
## late write: this is the scheduler running further ahead than the ring can
## hold, and it should be flatly impossible (the scheduler backs off first).
func _music_underruns() -> int:
	var spu = _music_spu()
	if spu == null:
		return 0
	return int(spu.get_deferred_stats().get("overflow", 0))


## How far ahead of the audio clock the sequencer currently is, in ms. The
## margin before an overdue write becomes possible at all.
func _music_lead_ms() -> float:
	var spu = _music_spu()
	if spu == null:
		return 0.0
	var stats = spu.get_deferred_stats()
	var lead: int = int(stats.get("schedule_frame", 0)) - int(stats.get("audio_frame", 0))
	return float(lead) / 44100.0 * 1000.0


func _music_spu():
	var p = MusicPlayer._player
	if p == null or not p.is_playing():
		# Not "no late writes" -- no measurement. Latch it; _finish() fails.
		if _measuring:
			_lost_music = true
		return null
	return p.mixer
