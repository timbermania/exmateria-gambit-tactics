extends Node
## Standalone A/B rig for the typewriter-click retrigger de-click.
##
## Fires the REAL per-glyph typewriter cue (SfxRouter "ui.text_typing" →
## ExMateriaEffectSfx.play_click retrigger) non-stop over music, so the pop is easy
## to hear and tune by ear. Open the F3 overlay → "Audio" tab → "Sound / SPU"
## panel and sweep the de-click fade (0 = original pop, 3 = default, 5/10 =
## gentler) live while it types.
##
## Keys:
##   1 / 2 / 3 / 4  — set click rate to 15 / 30 / 60 / 120 per second
##   Space          — pause / resume the click stream
##   M              — toggle music underneath
##   F3             — toggle the debug overlay (Audio tab has the de-click knob)
##
## IT ENDS ON ITS OWN (#472). It used to have no exit condition at all, so every
## `tools/run_unlisted_audio_binders.sh` run paid the full `timeout 360` for it and it
## scored HUNG — a rig is allowed to assert nothing, it is not allowed to hang. It now
## runs a `TOTAL_TIME` budget then `quit(0)`, the shape `SfxLiveStressTest` already uses.
##
## A `--ci` gate would NOT have worked: that script passes no user args, so the flag would
## be false in the one run that is actually paying. The budget is unconditional instead.
##
## AND AN UNATTENDED RUN NOW PRODUCES THE A/B. Left alone it SWEEPS the de-click fade
## through the settings this docstring names (0 = original pop, 3 = default, 5/10 =
## gentler), printing one telemetry line per phase — so the rig's output survives its own
## termination instead of being a HUD nobody was watching. TOUCH ANY KEY and the sweep
## stops: the manual by-ear session is what the rig is for, and it takes precedence.

const RATES := [15, 30, 60, 120]
## Unattended budget. Four fade settings need long enough each to hear and to let the
## limiter stats settle; 12 s a phase is comfortably past both.
const FADE_SWEEP := [0.0, 3.0, 5.0, 10.0]
const PHASE_TIME := 12.0
const TOTAL_TIME := 48.0       # FADE_SWEEP.size() * PHASE_TIME

var _rate: int = 60
var _running := true
var _click_acc := 0.0
var _music_on := true
var _music_slot := -1
var _hud: Label
var _t := 0.0
var _phase := -1
var _manual := false           # a key press hands the session to the human


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the record even
	# on the early-exit path below. The verdict reader scores it NOT_A_TEST — see
	# tests/lib/verdict.sh; it used to score HUNG, which rule 1 takes before any
	# declaration, and rightly: the fix for a hang is to stop hanging (#472).
	print("[NOT_A_TEST] a by-ear A/B rig for the typewriter-click retrigger de-click — it sweeps the fade and prints engine telemetry for a human, and asserts nothing; named *Test, but it is a rig")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		push_error("[typewriter-test] audio engines not ready")
		get_tree().quit(1)
		return

	# One-cast-per-unit combat routing (same as the real dialogue path).
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = false

	_start_music()
	_ensure_audio_panel()
	_build_hud()
	print("[typewriter-test] ready — F3 → Audio tab → 'Sound / SPU' to tune the de-click")


func _start_music() -> void:
	for slot in [17, 18, 16, 10, 1, 0]:
		if MusicPlayer.play_slot(slot):
			_music_slot = slot
			print("[typewriter-test] music on slot %d" % slot)
			return
	print("[typewriter-test] no music slot available (typing only)")


func _process(delta: float) -> void:
	_t += delta
	if not _manual:
		_advance_sweep()
	if not _running:
		return
	_click_acc += delta * float(_rate)
	var fires := 0
	# Cap per-frame fires so a hitch can't dump a huge burst at once.
	while _click_acc >= 1.0 and fires < 16:
		SfxRouter.play_cue("ui.text_typing")
		_click_acc -= 1.0
		fires += 1
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# A human is here. Stop the automatic sweep and the budget — the by-ear session is
	# the point of the rig, and it must not be cut off mid-listen.
	_manual = true
	match event.keycode:
		KEY_1: _rate = RATES[0]
		KEY_2: _rate = RATES[1]
		KEY_3: _rate = RATES[2]
		KEY_4: _rate = RATES[3]
		KEY_SPACE:
			_running = not _running
			_click_acc = 0.0
		KEY_M:
			_music_on = not _music_on
			if _music_on:
				_start_music()
			else:
				MusicPlayer.stop()
		_:
			return
	get_viewport().set_input_as_handled()
	_refresh_hud()


## The unattended A/B: hold each fade setting for PHASE_TIME, printing the engine's
## telemetry at the END of the phase (so the numbers describe a settled window, not the
## transient right after the knob moved). Then quit — the budget is the exit condition
## the rig never had.
func _advance_sweep() -> void:
	var want: int = mini(int(_t / PHASE_TIME), FADE_SWEEP.size() - 1)
	if want != _phase:
		if _phase >= 0:
			_print_phase()
		_phase = want
		ExMateriaEffectSfx.set_click_retrigger_fade_ms(FADE_SWEEP[_phase])
		print("[typewriter-test] fade = %.1f ms — typing at %d/s for %.0fs"
			% [FADE_SWEEP[_phase], _rate, PHASE_TIME])
		_refresh_hud()
	if _t >= TOTAL_TIME:
		_print_phase()
		print("[typewriter-test] done — swept %d fade settings in %.0fs"
			% [FADE_SWEEP.size(), _t])
		get_tree().quit(0)


func _print_phase() -> void:
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var sc: Dictionary = snap.get("scheduler", {})
	var rail: Dictionary = snap.get("rail", {})
	print("[typewriter-test]   fade=%.1fms  voices=%d late=%d dropped=%d preempts=%d | lead=%.1fms rail peak=%.2f"
		% [ExMateriaEffectSfx.click_retrigger_fade_ms, int(snap.get("total_voices", 0)),
			int(sc.get("late", 0)), int(sc.get("dropped", 0)), int(snap.get("preempts", 0)),
			float(sc.get("lead_ms", 0.0)), float(rail.get("pre_clamp_peak", 0.0))])


func _ensure_audio_panel() -> void:
	# The overlay outlives scenes; register one SpuAudioDebugPanel if absent.
	for panel in DebugOverlay._panels.get(DebugOverlay.Category.AUDIO, []):
		if is_instance_valid(panel) and panel is ExMateriaSound.SpuAudioDebugPanel:
			return
	AudioHostAdapter.register_panels()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 16)
	_hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(_hud)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud == null:
		return
	var fade := ExMateriaEffectSfx.click_retrigger_fade_ms
	_hud.text = "Typewriter click A/B\n" \
		+ "rate: %d/s   %s   music: %s\n" % [_rate, ("RUNNING" if _running else "PAUSED"), ("on" if _music_on else "off")] \
		+ "de-click fade: %.1f ms  (F3 → Audio tab to change)\n" % fade \
		+ "keys: 1/2/3/4 = 15/30/60/120/s · Space = pause · M = music"
