extends Node

## Headless in-game audio capture harness for the parity rig.
##
## Drives the SAME ExMateriaEffectSfx that the game uses (autoload, continuous-
## clock SPU, frame-paced sub-ticks) but in `capture_mode` so the script
## explicitly drives render_subs(N) for N deterministic IRQ ticks and writes
## interleaved-stereo PCM16 to <out-dir>/spu_mix.wav.
##
## Invoked by exmateria-sound/workspace/orchestrator/run_effect_iteration.py
## via --also-render-in-game. Output is compared against the parity rig's
## exmateria-sound Godot render (NOT against PCSX directly) to isolate the
## game-integration delta from the addon delta.
##
## Usage:
##   godot --path godot-learning res://tests/RenderInGameAudio.tscn -- \
##       --feds=<path> [--pair=0] [--pulses=1680] --out-dir=<dir>
##
## V1 limitations (intentional):
##   - No savestate residue seeding (noise LFSR / LFO subslots / SPU registers).
##     Voice 19 noise and any LFO-residue-sensitive voice will diverge.
##   - Full mix only; no per-voice WAVs (ExMateriaEffectSfx's render path is mix-only).

var _feds_path: String = ""
var _pair: int = 0
var _pulses: int = 1680
var _out_dir: String = ""


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a render TOOL — it needs --feds=<path> and --out-dir=<dir>, writes a WAV, and asserts nothing")
	_parse_args()
	if _feds_path.is_empty() or _out_dir.is_empty():
		push_error("RenderInGameAudio: missing --feds=<path> or --out-dir=<dir>")
		get_tree().quit(2); return
	if not ExMateriaAudioEngine.ready_ok:
		push_error("RenderInGameAudio: ExMateriaAudioEngine failed to boot (waveset missing?)")
		get_tree().quit(3); return
	if not ExMateriaEffectSfx.ready_ok:
		push_error("RenderInGameAudio: ExMateriaEffectSfx failed to boot")
		get_tree().quit(4); return

	# Suppress the engine's _process auto-render BEFORE the audition so the only
	# subs we account for are the ones we explicitly drive below.
	ExMateriaEffectSfx.capture_mode = true

	var token := ExMateriaEffectSfx.audition(_feds_path, _pair)
	if token == 0:
		push_error("RenderInGameAudio: audition failed for %s pair=%d"
				% [_feds_path, _pair])
		get_tree().quit(5); return

	var pcm := ExMateriaEffectSfx.render_subs(_pulses)
	if pcm.is_empty():
		push_error("RenderInGameAudio: render_subs returned empty")
		get_tree().quit(6); return

	DirAccess.make_dir_recursive_absolute(_out_dir)
	var wav_path := _out_dir.path_join("spu_mix.wav")
	_write_wav_stereo_pcm16(wav_path, pcm, ExMateriaSpu.Spu.SAMPLE_RATE)
	print("[RenderInGameAudio] wrote %s (%d frames, %d samples, pair=%d, pulses=%d)"
			% [wav_path, pcm.size() / 2, pcm.size(), _pair, _pulses])
	get_tree().quit(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--feds="):
			_feds_path = arg.substr(7)
		elif arg.begins_with("--pair="):
			_pair = int(arg.substr(7))
		elif arg.begins_with("--pulses="):
			_pulses = int(arg.substr(9))
		elif arg.begins_with("--out-dir="):
			_out_dir = arg.substr(10)


# Interleaved-stereo PCM16 -> 16-bit stereo WAV (matches the parity rig's
# format from harness_lib/render_output_utils.gd::save_wav_stereo_bytes).
func _write_wav_stereo_pcm16(path: String, pcm: PackedInt32Array, sample_rate: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("RenderInGameAudio: cannot open %s for write" % path)
		return
	var data_size := pcm.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)               # PCM
	f.store_16(2)               # stereo
	f.store_32(sample_rate)
	f.store_32(sample_rate * 4) # byte rate (2 ch * 2 bytes)
	f.store_16(4)               # block align
	f.store_16(16)              # bits/sample
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_size)
	for v in pcm:
		var s := v
		if s < 0:
			s += 65536
		f.store_16(s)
	f.close()
