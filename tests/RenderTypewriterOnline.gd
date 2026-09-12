extends Node
## LIVE ("online") typewriter capture — the A/B counterpart to RenderTypewriterOffline.
##
## Fires the REAL cue SfxRouter.play_cue("ui.text_typing") in REAL TIME (producer
## thread running, no capture_mode) at the same cadences as the offline tool, and
## taps the Master bus with AudioEffectCapture to record the TRUE final output.
## This is the path that still clicks by ear — capture it here so it can be A/B'd
## against the clean offline_<rate>_nobus.wav in the same folder.
##
## WAVs -> user://typewriter_online/  (absolute path printed; copy to /tmp to A/B).
## Run: godot --path . res://tests/RenderTypewriterOnline.tscn

const SECONDS := 5.0
const FADE_MS := 3.0
const RATES := [15.0, 30.0]     # match the offline renders
var _out_dir := "user://typewriter_online"

var _cap: AudioEffectCapture
var _pcm := PackedInt32Array()
var _rate := 0.0
var _t := 0.0
var _click_acc := 0.0
var _running := false
var _queue: Array = []


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] the LIVE capture counterpart to RenderTypewriterOffline — it writes WAVs and asserts nothing")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		print("[tw-online] ExMateriaEffectSfx not ready"); get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[tw-online] output dir: %s" % ProjectSettings.globalize_path(_out_dir))
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)

	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 2.0   # big ring so a frame hitch can't overflow -> no fake stitches
	AudioServer.add_bus_effect(0, _cap)   # bus 0 = Master = true final output

	_queue = RATES.duplicate()
	_start_next()


func _start_next() -> void:
	if _queue.is_empty():
		print("[tw-online] done — A/B online_*.wav vs offline_*_nobus.wav.")
		get_tree().quit(0)
		return
	_rate = _queue.pop_front()
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()   # per-run underrun count (not cumulative)
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(FADE_MS)
	_pcm = PackedInt32Array()
	_t = 0.0
	_click_acc = 0.0
	_cap.clear_buffer()
	_running = true
	print("[tw-online] capturing %.0f glyphs/s live for %.1fs …" % [_rate, SECONDS])


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	_click_acc += delta * _rate
	var fires := 0
	while _click_acc >= 1.0 and fires < 16:
		SfxRouter.play_cue("ui.text_typing")
		_click_acc -= 1.0
		fires += 1
	while _cap.get_frames_available() > 0:
		for fr in _cap.get_buffer(_cap.get_frames_available()):
			_pcm.append(int(clampf(fr.x, -1.0, 1.0) * 32767.0))
			_pcm.append(int(clampf(fr.y, -1.0, 1.0) * 32767.0))
	if _t >= SECONDS:
		_finish()


func _finish() -> void:
	_running = false
	var path := "%s/online_%dhz_%dms.wav" % [_out_dir, int(_rate), int(FADE_MS)]
	_write_wav(path, _pcm)
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var sc: Dictionary = snap.get("scheduler", {})
	print("[tw-online] wrote %s  | sched late=%d dropped=%d  peak=%.3fFS" % [
		path.get_file(), int(sc.get("late", -1)), int(sc.get("dropped", -1)), _peak(_pcm)])
	_start_next()


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
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		print("[tw-online] could not open %s" % path); return
	fh.store_buffer("RIFF".to_ascii_buffer()); fh.store_32(36 + bytes.size())
	fh.store_buffer("WAVE".to_ascii_buffer()); fh.store_buffer("fmt ".to_ascii_buffer())
	fh.store_32(16); fh.store_16(1); fh.store_16(2); fh.store_32(rate)
	fh.store_32(rate * 2 * 2); fh.store_16(2 * 2); fh.store_16(16)
	fh.store_buffer("data".to_ascii_buffer()); fh.store_32(bytes.size())
	fh.store_buffer(bytes); fh.close()
