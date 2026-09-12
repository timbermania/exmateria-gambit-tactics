extends Node
## Deterministic (offline) probe for the retrigger-COLLISION hypothesis.
##
## Live 30/s clicks look like a blip cut mid-attack (step ~0.19) with no de-click.
## Suspicion: two glyph key-ons land with too few (or zero) producer renders
## between them, so the de-click captures a stale residual and the loud attack is
## chopped. Offline we control the sub-spacing exactly. For each spacing we fire
## many retrigger pairs and report the worst inter-sample step. If tight spacing
## (0-2 subs) yields ~0.19 steps while wide spacing (8) stays ~0.06, the collision
## mechanism is confirmed and we have a deterministic repro to fix against.
##
## Run: godot --path . res://tests/TypewriterCollisionProbe.tscn

const SPACINGS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12]  # subs between the two key-ons
const FADES := [0.0, 3.0, 10.0]
const PAIRS := 40


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a deterministic offline probe for the retrigger-COLLISION hypothesis — it prints per-sample levels and asserts nothing")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		print("[collide] not ready"); get_tree().quit(1); return
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)

	# Header row
	var hdr := "[collide] spacing:"
	for sp in SPACINGS:
		hdr += "  %5d" % sp
	print(hdr)
	for fade in FADES:
		var row := "[collide] fade=%2.0fms" % fade
		for sp in SPACINGS:
			var mx := _probe(sp, fade)
			row += "  %s%.3f" % ["*" if mx > 0.12 else " ", mx]
		print(row)
	print("[collide] ('*' = click ~0.19; the clean glyph-onset baseline is ~0.07)")
	_dump_seam(2, 3.0)
	_dump_seam(1, 3.0)
	_dump_solo()
	print("[collide] done.")


func _dump_solo() -> void:
	# Render ONE blip alone (no retrigger) for 6 subs and print around sample 367
	# (the 2-sub mark). If A drops to 0 here on its own, the click is A's natural
	# envelope/sample end — not the retrigger.
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(3.0)
	SfxRouter.play_cue("ui.text_typing")
	var pcm := ExMateriaEffectSfx.render_subs(6)
	ExMateriaEffectSfx.capture_mode = false
	print("[collide] --- SOLO blip (no retrigger), samples 358..380 ---")
	for i in range(358, 381):
		print("[collide]   s%d  L=%+.4f" % [i, float(pcm[i * 2]) / 32768.0])
	get_tree().quit(0)


func _dump_seam(spacing: int, fade_ms: float) -> void:
	# Re-render one pair and print the samples around the worst step so we can see
	# the click SHAPE (is the residual ramped or chopped?).
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(fade_ms)
	var pcm := PackedInt32Array()
	SfxRouter.play_cue("ui.text_typing")
	pcm.append_array(ExMateriaEffectSfx.render_subs(maxi(spacing, 1)))
	SfxRouter.play_cue("ui.text_typing")
	pcm.append_array(ExMateriaEffectSfx.render_subs(6))
	ExMateriaEffectSfx.capture_mode = false
	var n := pcm.size() / 2
	var best := 1
	var bestd := 0.0
	for i in range(1, n):
		var d: float = absf(float(pcm[i * 2]) - float(pcm[(i - 1) * 2]))
		if d > bestd: bestd = d; best = i
	print("[collide] --- seam dump spacing=%d fade=%.0f (worst step at sample %d) ---" % [spacing, fade_ms, best])
	var lo: int = maxi(best - 6, 0)
	for i in range(lo, mini(best + 7, n)):
		var mark := "  <== STEP" if i == best else ""
		print("[collide]   s%d  L=%+.4f%s" % [i, float(pcm[i * 2]) / 32768.0, mark])


func _probe(spacing: int, fade_ms: float) -> float:
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.set_click_retrigger_fade_ms(fade_ms)
	var pcm := PackedInt32Array()
	# Warm gap so each pair starts from the same state.
	for _i in range(PAIRS):
		SfxRouter.play_cue("ui.text_typing")          # glyph A
		pcm.append_array(_render(maxi(spacing, 0)))     # let A attack for `spacing` subs
		SfxRouter.play_cue("ui.text_typing")           # glyph B (the retrigger that may chop A)
		pcm.append_array(_render(8))                    # render B out
	ExMateriaEffectSfx.capture_mode = false
	return _max_step(pcm)


func _render(subs: int) -> PackedInt32Array:
	if subs <= 0:
		return PackedInt32Array()
	return ExMateriaEffectSfx.render_subs(subs)


func _max_step(pcm: PackedInt32Array) -> float:
	var n := pcm.size() / 2
	var mx := 0.0
	var prev := 0.0
	for i in range(n):
		var mono := (float(pcm[i * 2]) + float(pcm[i * 2 + 1])) * 0.5 / 32768.0
		if i > 0:
			mx = maxf(mx, absf(mono - prev))
		prev = mono
	return mx
