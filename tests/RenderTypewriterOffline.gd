extends Node
## Offline typewriter render tool for by-ear iteration (NO live/threading).
##
## For each cadence it renders one deterministic WAV from the sub clock:
##   _nobus = _sum_pcm(sfx,bg)  — the offline cross-unit sum
##
## It USED to render a second arm through `BusLimiter` so you could A/B the bus
## offline. #385 task 3 deleted that class: limiting is now an
## AudioEffectHardLimiter on the SFX bus, which is a Godot mixer stage with no
## offline entry point, so the second arm cannot be recreated here and has been
## dropped rather than faked. (It was measured bit-identical at SFX-only levels
## anyway — the bus was passthrough below full-scale.) By-ear A/B of the bus
## limiter belongs in the running game now; this stays the deterministic source
## oracle for the CLICK itself.
##
## WAVs -> user://typewriter_offline/ (absolute path printed).
## Run: godot --path . res://tests/RenderTypewriterOffline.tscn

const SECONDS := 5.0
const SUBS_PER_SEC := 240.0
# (rate_glyphs_per_sec, fade_ms) — realistic cadences + a de-click A/B.
const RENDERS := [
	[15.0, 3.0],   # slow boxed-ish cadence
	[30.0, 3.0],   # overlay-ish cadence
	[30.0, 0.0],   # de-click OFF (A/B: does the retrigger step click?)
]
var _out_dir := "user://typewriter_offline"


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] an offline render tool — it writes WAVs for a human to A/B by ear and asserts nothing")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		print("[tw-offline] ExMateriaEffectSfx not ready"); get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[tw-offline] output dir: %s" % ProjectSettings.globalize_path(_out_dir))
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)

	for r in RENDERS:
		_render(r[0], r[1])

	print("[tw-offline] done — the WAVs above are the deterministic click oracle.")
	get_tree().quit(0)


func _render(rate: float, fade_ms: float) -> void:
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(fade_ms)

	var subs_total := int(SECONDS * SUBS_PER_SEC)
	var subs_per_glyph := SUBS_PER_SEC / rate
	var acc := 0.0
	var nobus := PackedFloat32Array()
	var inv := 1.0 / 32768.0
	for s in range(subs_total):
		acc += 1.0
		if acc >= subs_per_glyph:
			acc -= subs_per_glyph
			SfxRouter.play_cue("ui.text_typing")
		# ONE split -> both mixes, sample-aligned.
		var split: Dictionary = ExMateriaEffectSfx._render_sub_split()
		var g: PackedInt32Array = ExMateriaEffectSfx._sum_pcm(split["sfx"], split["bg"])
		for v in g:
			nobus.append(clampf(float(v) * inv, -1.0, 1.0))
	ExMateriaEffectSfx.capture_mode = false

	var tag := "%dhz_%dms" % [int(rate), int(fade_ms)]
	_write_wav("%s/offline_%s_nobus.wav" % [_out_dir, tag], nobus)
	var peak := 0.0
	for v in nobus:
		peak = maxf(peak, absf(v))
	print("[tw-offline] %s (%.0f gl/s, de-click %.0f ms): %d samples, peak=%.3fFS" % [
		tag, rate, fade_ms, nobus.size(), peak])


func _write_wav(path: String, f32: PackedFloat32Array) -> void:
	var n := f32.size()
	var bytes := PackedByteArray(); bytes.resize(n * 2)
	for i in range(n):
		var s: int = clampi(int(f32[i] * 32767.0), -32768, 32767)
		if s < 0: s += 65536
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var rate := int(ExMateriaSpu.Spu.SAMPLE_RATE)
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		print("[tw-offline] could not open %s" % path); return
	fh.store_buffer("RIFF".to_ascii_buffer()); fh.store_32(36 + bytes.size())
	fh.store_buffer("WAVE".to_ascii_buffer()); fh.store_buffer("fmt ".to_ascii_buffer())
	fh.store_32(16); fh.store_16(1); fh.store_16(2); fh.store_32(rate)
	fh.store_32(rate * 2 * 2); fh.store_16(2 * 2); fh.store_16(16)
	fh.store_buffer("data".to_ascii_buffer()); fh.store_32(bytes.size())
	fh.store_buffer(bytes); fh.close()
