extends Node

## SfxLiveStressTest — LIVE (real-time) diagnostic for the popping report. Unlike
## SfxPopDiagTest this does NOT use capture_mode: the producer thread runs in
## real time and feeds the actual AudioStreamGenerator, so the LIVE-ONLY
## mechanisms (scheduler lateness / dropped register writes) are exercised and counted.
##
## It fires a CONSTANT single Fire every 1.5 s via the game's orphan path (orphan
## when the "visual" ends, engine reaps), printing diagnostic counters once a
## second. Used to prove time-accumulation (sessions/units leaking) independent of
## concurrency — see ADR-0050. Watch `sessions`/`units` stay flat (no leak).
##
## Run (HEADFUL, audible):  godot --path . res://tests/SfxLiveStressTest.tscn

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const FIRE_ID := "E016"
const CAST_LIFETIME := 2.5     # seconds before we end_effect a cast
const TOTAL_TIME := 42.0       # long run: does CONSTANT single-fire degrade over time?

var _fb
var _t := 0.0
var _last_print := 0.0
var _next_fire := 0.5
var _live: Array = []          # {token, die_at}
var _phase_label := "single"

# GLOBAL-level instrumentation: an AudioEffectCapture on the Master bus taps the
# ACTUAL final mix (SFX + music + UI), so we measure clipping/pops at the true
# device output — the one place the SFX-bus limiter can't see (SFX+music sum).
var _cap: AudioEffectCapture
var _g_clip := 0               # samples at/over the device rail (real global clip)
var _g_maxabs := 0.0           # peak of the final mix
var _g_maxjump := 0.0          # largest sample-to-sample step in the final mix (pop proxy)
var _g_prev := Vector2.ZERO
var _g_have := false


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a live SFX stress rig — it prints engine telemetry for a human and asserts nothing; named *Test, but it is a rig")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return
	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/%s" % FIRE_ID)
	if loaded == null or not loaded.has_sound():
		print("[FAIL] %s has no sound" % FIRE_ID)
		get_tree().quit(1)
		return
	_fb = loaded.feds_bank
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = false   # PRODUCER RUNS — real-time path
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()

	# Tap the Master bus (index 0) for the true final-mix measurement.
	_cap = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _cap)

	# Reproduce the GAME condition the FEDS tester lacks: music on the Master bus,
	# summing with SFX. Try a few slots until one plays.
	var music_ok := false
	for slot in [17, 18, 16, 10, 1, 0]:
		if MusicPlayer.play_slot(slot):
			music_ok = true
			print("[live] music started on slot %d" % slot)
			break
	if not music_ok:
		print("[live] WARNING: no music slot played — SFX+music sum NOT reproduced")

	print("[live] real-time SFX stress (music=%s): constant single fire, orphan path, counters once/sec" % str(music_ok))


func _fire(n: int) -> void:
	for k in range(n):
		var t: int = ExMateriaEffectSfx.begin_effect()
		for pair in range(_fb.num_pairs):
			ExMateriaEffectSfx.play_pair(t, _fb, pair, pair + 1)
		# Mimic the GAME: orphan when the visual ends (~0.8 s), then rely on the
		# engine to reap the cast when its sound sequence finishes. If reaping
		# leaks, sessions/units will climb over the run.
		_live.append({"token": t, "die_at": _t + 0.8})


func _process(delta: float) -> void:
	_t += delta

	# Orphan casts whose "visual" ended — like the game does. The ENGINE owns
	# reaping from here; we do NOT end_effect. If it leaks, sessions climb.
	var still: Array = []
	for c in _live:
		if _t >= c["die_at"]:
			ExMateriaEffectSfx.orphan_effect(c["token"])
		else:
			still.append(c)
	_live = still

	# CONSTANT single fire throughout — testing time-accumulation, not concurrency.
	_phase_label = "single"
	if _t >= _next_fire:
		_fire(1)
		_next_fire = _t + 1.5

	# Drain the Master-bus tap: the TRUE final mix (SFX + music). Clip/jump here
	# is the "global" problem the per-stage SFX counters can't see.
	if _cap != null:
		var navail := _cap.get_frames_available()
		if navail > 0:
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

	# Print counters once a second.
	if _t - _last_print >= 1.0:
		_last_print = _t
		var s: Dictionary = ExMateriaEffectSfx.debug_snapshot()
		var sc: Dictionary = s.get("scheduler", {})
		print("[live %4.1fs] units=%d voices=%d sessions=%d | sched lead=%.1fms late=%d dropped=%d | preempts=%d cap_dbl=%d | GLOBAL(master): peak=%.2f clip=%d"
			% [_t, s.get("units", []).size(), s.get("total_voices", 0), s.get("sessions", 0),
				sc.get("lead_ms", 0.0), sc.get("late", 0), sc.get("dropped", 0),
				s.get("preempts", 0), s.get("cap_doublings", 0),
				_g_maxabs, _g_clip])
		_g_maxabs = 0.0
		_g_clip = 0   # per-window so growth over time is visible

	if _t >= TOTAL_TIME:
		for c in _live:
			ExMateriaEffectSfx.end_effect(c["token"])
		print("[live] done")
		get_tree().quit(0)
