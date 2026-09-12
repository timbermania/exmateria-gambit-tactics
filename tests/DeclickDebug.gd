extends Node
## Ground-truth seam tracer for the spacing=2 retrigger click. Renders the A->B
## retrigger sub-by-sub and aligns voice-22 SPU state with the emitted PCM so we
## can see EXACTLY what happens at the seam (where the summed click output steps).

func _vs(tag: String) -> void:
	var mm = ExMateriaEffectSfx._click_units[0]["mixer"] if not ExMateriaEffectSfx._click_units.is_empty() else null
	if mm == null:
		print("[declick-dbg] %s (no click unit)" % tag); return
	var s := "[declick-dbg] %s" % tag
	for v in [22, 23]:
		var d: Dictionary = mm.get_voice_debug_info(v)
		s += " v%d{on=%s env=%s evol=%d lo=%d dl=%d rem=%d}" % [
			v, str(d.get("on")), str(d.get("env_state")), int(d.get("env_vol", 0)),
			int(d.get("last_out_l", 0)), int(d.get("declick_l", 0)), int(d.get("declick_remaining", 0))]
	print(s)


func _dump_pcm(pcm: PackedInt32Array, base: int, lo: int, hi: int) -> void:
	for i in range(lo, hi):
		print("[declick-dbg]   s%d  L=%+.4f" % [base + i, float(pcm[i * 2]) / 32768.0])


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a ground-truth seam tracer for the spacing=2 retrigger click — it prints voice state for a human to read and asserts nothing")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		get_tree().quit(1); return
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)

	var spacing := 2
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(3.0)
	SfxRouter.play_cue("ui.text_typing")               # glyph A
	var pcmA := ExMateriaEffectSfx.render_subs(spacing)    # A attacks for `spacing` subs
	var nA := pcmA.size() / 2
	_vs("after A render (%d samples)" % nA)
	_dump_pcm(pcmA, 0, maxi(0, nA - 8), nA)

	print("[declick-dbg] ===== keying B (retrigger) =====")
	SfxRouter.play_cue("ui.text_typing")               # glyph B
	_vs("after B play_click (pre-render, = carry point)")

	# Render B one sub at a time; the deferred key_on lands inside sub 0.
	for sub in range(3):
		var pcmB := ExMateriaEffectSfx.render_subs(1)
		_vs("after B sub %d" % sub)
		if sub == 0:
			_dump_pcm(pcmB, nA, 0, 24)
	ExMateriaEffectSfx.capture_mode = false
	print("[declick-dbg] done")
	get_tree().quit(0)
