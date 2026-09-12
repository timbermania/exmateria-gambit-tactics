extends Node
## Capture rig for the periodic typewriter "click" hunt.
##
## Fires the REAL typewriter cue (SfxRouter "ui.text_typing") at 120/s, no music,
## and records TWO ways so we can localize the click:
##   1. OFFLINE — deterministic render_subs() of the SFX SPU mix (capture_mode).
##      Shows clicks that live in the SYNTHESIS/MIX (retrigger step, pool events).
##   2. LIVE    — AudioEffectCapture tap on the Master bus while the real
##      producer thread plays. Adds anything from the live audio path
##      (AudioStreamGenerator refills / underruns) that offline can't show.
## If the periodic click is in LIVE but NOT offline → it's the live audio path,
## not the SPU. Each capture also auto-measures the spacing between broadband
## transients so we get the click RATE as a number.
##
## WAVs land under user://typewriter_captures/ (absolute path printed at start).
## Run:  godot --path . res://tests/TypewriterClickCapture.tscn

const CLICK_RATE := 120           # glyphs/sec
const OFFLINE_SECONDS := 3.0
const LIVE_SECONDS := 4.0
const SUBS_PER_FRAME := 8          # 240 Hz IRQ / 30 fps (matches EffectSoundCaptureTest)
const STEP_THRESH := 0.12          # |sample delta| / FS that counts as a transient
const DEBOUNCE_SAMPLES := 64       # min gap between two counted transients

var _live_cap: AudioEffectCapture
var _live_pcm := PackedInt32Array()
var _live_t := 0.0
var _live_click_acc := 0.0
var _live_running := false
var _live_stats_zeroed := false
var _out_dir := "user://typewriter_captures"


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a capture rig for the periodic typewriter-click hunt — its `PASS: the scheduler held its lead` line IS a gate (late/dropped), the rest is prose")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[tw-capture] audio engines not ready"); get_tree().quit(1); return

	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[tw-capture] output dir: %s" % ProjectSettings.globalize_path(_out_dir))

	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)

	# ---- OFFLINE captures (deterministic) at 3 ms and 0 ms ----
	_offline_capture(3.0, "%s/offline_120hz_3ms.wav" % _out_dir)
	_offline_capture(0.0, "%s/offline_120hz_0ms.wav" % _out_dir)

	# ---- LIVE capture (real producer + Master-bus tap) at 3 ms ----
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(3.0)
	_live_cap = AudioEffectCapture.new()
	_live_cap.buffer_length = 2.0  # big ring so a frame hitch can't overflow → no fake stitches
	AudioServer.add_bus_effect(0, _live_cap)  # bus 0 = Master → true final output
	_live_cap.clear_buffer()
	print("[tw-capture] live capture: 120/s over Master bus for %.1fs …" % LIVE_SECONDS)
	_live_running = true  # _process now fires clicks + drains the tap
	_live_stats_zeroed = false


func _offline_capture(fade_ms: float, path: String) -> void:
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(fade_ms)

	var subs_total := int(OFFLINE_SECONDS * 240.0)
	var subs_per_click := 240.0 / float(CLICK_RATE)  # subs between clicks
	var acc := 0.0
	var pcm := PackedInt32Array()
	for s in range(subs_total):
		acc += 1.0
		if acc >= subs_per_click:
			acc -= subs_per_click
			SfxRouter.play_cue("ui.text_typing")
		pcm.append_array(ExMateriaEffectSfx.render_subs(1))
	ExMateriaEffectSfx.capture_mode = false

	_write_wav(path, pcm)
	var m := _measure_clicks(pcm)
	print("[tw-capture] OFFLINE fade=%.1fms -> %s | %s" % [fade_ms, path.get_file(), m])


func _process(delta: float) -> void:
	if not _live_running:
		return
	_live_t += delta
	# Zero the scheduler counters once the live arm is actually RUNNING, not when
	# it is set up. Going live re-arms every stream (capture_mode parks them, and
	# the offline arms above ran parked), and each re-arm rewinds its SPU's clocks
	# while the audio thread is already mixing — a handful of register writes land
	# overdue during that ramp. Those belong to the transition, not to the flood
	# this rig measures, and counting them made the gate below fire at late=4 while
	# an 18 s steady-state run measured 0.
	if not _live_stats_zeroed and _live_t >= 0.5:
		_live_stats_zeroed = true
		ExMateriaEffectSfx.reset_audio_stats()
	# Fire clicks at CLICK_RATE.
	_live_click_acc += delta * float(CLICK_RATE)
	var fires := 0
	while _live_click_acc >= 1.0 and fires < 16:
		SfxRouter.play_cue("ui.text_typing")
		_live_click_acc -= 1.0
		fires += 1
	# Drain the Master-bus tap into the PCM buffer.
	while _live_cap.get_frames_available() > 0:
		var frames := _live_cap.get_buffer(_live_cap.get_frames_available())
		for fr in frames:
			_live_pcm.append(int(clampf(fr.x, -1.0, 1.0) * 32767.0))
			_live_pcm.append(int(clampf(fr.y, -1.0, 1.0) * 32767.0))
	if _live_t >= LIVE_SECONDS:
		_finish_live()


func _finish_live() -> void:
	_live_running = false
	var path := "%s/live_120hz_3ms.wav" % _out_dir
	_write_wav(path, _live_pcm)
	var m := _measure_clicks(_live_pcm)
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var peak := _peak(_live_pcm)
	print("[tw-capture] LIVE fade=3.0ms -> %s | peak=%.3fFS | %s" % [path.get_file(), peak, m])
	# #123's original failure — the generator's ring starving on a main-thread frame
	# hitch — cannot happen any more: #385 task 3 deleted the ring, and each unit's
	# SPU is rendered inside `_mix` on the audio thread. So this gate is repointed
	# rather than deleted, onto the failure the streamed path CAN have: the
	# scheduler falling behind the audio clock (`late`, a register write applied
	# after its own frame passed) or overrunning its ring (`dropped`, a write lost
	# outright). A 120/s click flood in UNLOCKED mode with no music is the
	# worst-case load for exactly that.
	#
	# NOTE the defaults are -1, not 0: reading a key this snapshot no longer
	# publishes must fail loudly here, not sail through a `> 0` gate as a clean
	# bill. -1 trips the check below.
	var sc: Dictionary = snap.get("scheduler", {})
	var late := int(sc.get("late", -1))
	var dropped := int(sc.get("dropped", -1))
	print("[tw-capture] LIVE engine stats: sched late=%d dropped=%d lead=%.1fms | preempts=%d cap_doublings=%d" % [
		late, dropped, float(sc.get("lead_ms", 0.0)),
		int(snap.get("preempts", -1)), int(snap.get("cap_doublings", -1))])
	if late != 0 or dropped != 0:
		print("[tw-capture] FAIL: scheduler late=%d dropped=%d under a 120/s click flood (#123 successor gate)"
			% [late, dropped])
		get_tree().quit(1)
		return
	print("[tw-capture] PASS: the scheduler held its lead. WAVs written for optional spectrogram review.")
	get_tree().quit(0)


# Detect broadband transients (large inter-sample steps) on the mono sum and
# report count + median spacing → an approximate click rate. Interleaved stereo.
func _measure_clicks(pcm: PackedInt32Array) -> String:
	var n_frames := pcm.size() / 2
	if n_frames < 4:
		return "no data"
	const FS := 32767.0
	var thresh := int(STEP_THRESH * FS)
	var hits := PackedInt32Array()
	var prev := 0
	var last_hit := -DEBOUNCE_SAMPLES
	for i in range(n_frames):
		var mono := (pcm[i * 2] + pcm[i * 2 + 1]) / 2
		if i > 0 and absi(mono - prev) >= thresh and (i - last_hit) >= DEBOUNCE_SAMPLES:
			hits.append(i)
			last_hit = i
		prev = mono
	if hits.size() < 2:
		return "transients=%d (too few to measure spacing)" % hits.size()
	var gaps := PackedFloat32Array()
	for k in range(1, hits.size()):
		gaps.append(float(hits[k] - hits[k - 1]))
	gaps.sort()
	var median := gaps[gaps.size() / 2]
	var rate := 44100.0 / median
	var secs := float(n_frames) / 44100.0
	return "transients=%d over %.2fs (~%.1f/s) | median spacing %.0f smp = %.1f ms (~%.1f Hz)" % [
		hits.size(), secs, float(hits.size()) / secs, median, median / 44.1, rate]


func _peak(pcm: PackedInt32Array) -> float:
	var pk := 0
	for v in pcm:
		var a := absi(v)
		if a > pk: pk = a
	return float(pk) / 32767.0


func _write_wav(path: String, pcm: PackedInt32Array) -> void:
	var n := pcm.size()
	var bytes := PackedByteArray(); bytes.resize(n * 2)
	for i in range(n):
		var s: int = clampi(pcm[i], -32768, 32767)
		if s < 0: s += 65536
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var rate := int(ExMateriaSpu.Spu.SAMPLE_RATE)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[tw-capture] could not open %s" % path); return
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + bytes.size())
	f.store_buffer("WAVE".to_ascii_buffer()); f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16); f.store_16(1); f.store_16(2); f.store_32(rate)
	f.store_32(rate * 2 * 2); f.store_16(2 * 2); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(bytes.size())
	f.store_buffer(bytes); f.close()
