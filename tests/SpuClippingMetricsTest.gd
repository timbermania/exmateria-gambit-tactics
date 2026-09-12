extends Node

## SpuClippingMetricsTest — the "SPU limits" metrics suite for the typewriter-
## burst popping report. Where MusicTypewriterStressTest chases a music-buffer
## SKIP (refuted on this box), this measures SATURATION / HEADROOM at every stage
## a signal sums, and decides WHICH pop mechanism is in play:
##
##   (a) summed-mix clipping  — the mix crosses a rail (in-core int16, SFX-bus
##       limiter, or the SFX+music sum at Master). Fix = headroom (turn the click
##       level down / ensure the limiter path), mirroring the DAW "instrument too
##       hot" fix.
##   (b) per-retrigger discontinuity — each glyph hard key-ons the click sample,
##       so a fast type-out is a burst of instantaneous amplitude steps → a click
##       by construction. Shows as final-mix max sample-to-sample JUMP scaling
##       with click rate WITHOUT any stage's peak crossing the rail. Fix = a tiny
##       attack/release or crossfade on the retrigger, and/or a rate cap.
##
## Three instrumented stages, per second, per unit-summation point:
##   1. Native SPU rail  (ExMateriaEffectSfx.debug_snapshot().rail) — the summed
##      voices INSIDE each unit's C++ core before clip_pcm16. pre_clamp_peak is
##      the overshoot factor (1.0 == exactly at the rail); `click` is the reserved
##      typewriter unit specifically. This is the one clip GDScript can't see.
##   2. SFX-bus tap      (AudioEffectCapture on the SFX bus) — the domain bus's own
##      peak and clip count, POST its HardLimiter. Until #385 task 3 this stage read
##      a GDScript `BusLimiter`'s stats dictionary; that class is gone and its job is
##      an AudioEffectHardLimiter on this bus, which has no stats to read — so the
##      stage is now MEASURED off the signal instead of reported by the limiter.
##      (Reading the deleted key would have silently returned 0 and made the gate
##      below vacuous, which is the failure this rig exists to catch.)
##   3. Master tap       (AudioEffectCapture on bus 0) — true final-mix peak, clip
##      count, and max sample-to-sample jump (the discontinuity / pop proxy).
##
## Drives the REAL per-glyph path (SfxRouter.play_cue("ui.text_typing") →
## ExMateriaEffectSfx.play_click retrigger) at a swept rate, over music. Each phase
## resets the per-window counters so every printed value is a per-SECOND rate.
##
## Run (HEADFUL, audible — NEVER --headless):
##   godot --path . res://tests/SpuClippingMetricsTest.tscn
## Force-kill a hung headful run: timeout -s KILL 40 godot --path . res://...

const FULL_SCALE := 32767.0

# Click-rate sweep (clicks/sec). rate 0 = music-only baseline; the ramp isolates
# whether each metric scales with retrigger rate.
const PHASES := [
	{"label": "baseline (music only)", "rate": 0,   "secs": 4.0},
	{"label": "clicks 15/s (spaced)",  "rate": 15,  "secs": 4.0},
	{"label": "clicks 30/s",           "rate": 30,  "secs": 4.0},
	{"label": "clicks 60/s (bursty)",  "rate": 60,  "secs": 4.0},
	{"label": "clicks 120/s (storm)",  "rate": 120, "secs": 4.0},
]

# Gates. A burst phase that trips any of these fails the suite.
const RAIL_HIT_RATE_FAIL := 100     # in-core clamp cutting >N samples/s = saturation pop
const BUS_CLAMP_RATE_FAIL := 100    # SFX-bus samples at the rail per second, post-limiter
const MASTER_CLIP_RATE_FAIL := 100  # device-rail clip/s (SFX+music sum)
const MAXJUMP_FAIL := 0.5           # instantaneous final-mix step >= 0.5 FS = definite click
const MAXJUMP_WARN_FACTOR := 3.0    # burst maxjump >= Nx baseline = softer discontinuity signal
const MAX_FIRES_PER_FRAME := 8      # cap catch-up so a slow frame can't machine-gun

var _phase_idx := 0
var _phase_t := 0.0
var _sec_t := 0.0
var _click_acc := 0.0

# Master-bus tap accumulators (this-second window; reset each second).
var _cap: AudioEffectCapture
# SFX-bus tap accumulators — the same instrument as the Master tap, one bus upstream.
var _sfx_cap: AudioEffectCapture
## No SFX bus means _sfx_cap is null, bus_clamp reads 0 for every phase, and
## BUS_CLAMP_RATE_FAIL can never trip. The docstring at the top of this file
## calls that "the failure this rig exists to catch" -- so it is a FAIL, not
## a warning that scrolls past.
var _sfx_bus_missing := false
var _s_peak := 0.0
var _s_clip := 0
var _m_peak := 0.0
var _m_clip := 0
var _m_maxjump := 0.0
var _m_prev := Vector2.ZERO
var _m_have := false

# Per-phase worst-of (for the summary + gate).
var _p_rail_peak := 0.0
var _p_rail_click_peak := 0.0
var _p_rail_hits := 0
var _p_bus_peak := 0.0
var _p_bus_clamp := 0
var _p_master_peak := 0.0
var _p_master_clip := 0
var _p_master_maxjump := 0.0

var _baseline_maxjump := 0.0
var _results: Array = []   # per-phase snapshot dicts for the final verdict


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
	AudioServer.add_bus_effect(0, _cap)   # bus 0 = Master → true final mix
	# Appended, so it lands AFTER MasterBus's HardLimiter and measures what the SFX
	# bus actually sends to Master rather than what the units put into it.
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx > 0:
		_sfx_cap = AudioEffectCapture.new()
		AudioServer.add_bus_effect(sfx_idx, _sfx_cap)
	else:
		_sfx_bus_missing = true
		print("[spu-metrics] no SFX bus — the SFX-bus stage would read 0 and its gate would be blind")

	var any_music := false
	for slot in [17, 18, 16, 10, 1, 0]:
		if MusicPlayer.play_slot(slot):
			any_music = true
			print("[spu-metrics] music started on slot %d" % slot)
			break
	if not any_music:
		print("[FAIL] no music slot played")
		get_tree().quit(1)
		return

	print("[spu-metrics] click-rate sweep: %s" % ", ".join(PHASES.map(func(p): return str(p["rate"]))))
	print("[spu-metrics] per-second, per stage:")
	print("[spu-metrics]   rail = native in-core SPU (pre_clamp_peak xFS / hits/s / click-unit peak)")
	print("[spu-metrics]   bus  = SFX limiter (max_peak / clamp/s / min_gain)")
	print("[spu-metrics]   mstr = Master tap (peak / clip/s / maxjump)")
	await get_tree().create_timer(1.0).timeout
	_begin_phase(0)


func _begin_phase(idx: int) -> void:
	_phase_idx = idx
	_phase_t = 0.0
	_sec_t = 0.0
	_click_acc = 0.0
	_reset_phase_worst()
	ExMateriaEffectSfx.reset_audio_stats()
	_reset_master_window()
	print("[spu-metrics] --- phase %d: %s (%d clicks/s) ---" % [idx, PHASES[idx]["label"], int(PHASES[idx]["rate"])])


func _process(delta: float) -> void:
	if _phase_idx >= PHASES.size():
		return
	_phase_t += delta
	_sec_t += delta

	_fire_clicks(delta)
	_drain_master_tap()
	_drain_sfx_tap()

	if _sec_t >= 1.0:
		_report_and_reset_second()

	if _phase_t >= float(PHASES[_phase_idx]["secs"]):
		_close_phase()
		if _phase_idx + 1 < PHASES.size():
			_begin_phase(_phase_idx + 1)
		else:
			_phase_idx = PHASES.size()
			_finish()


func _fire_clicks(delta: float) -> void:
	var rate: int = PHASES[_phase_idx]["rate"]
	if rate <= 0:
		return
	_click_acc += delta * float(rate)
	var fires := 0
	while _click_acc >= 1.0 and fires < MAX_FIRES_PER_FRAME:
		SfxRouter.play_cue("ui.text_typing")   # real per-glyph path → play_click retrigger
		_click_acc -= 1.0
		fires += 1


func _report_and_reset_second() -> void:
	_sec_t = 0.0
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var rail: Dictionary = snap.get("rail", {})
	var rail_click: Dictionary = rail.get("click", {})

	var rail_peak := float(rail.get("pre_clamp_peak", 0.0))
	var rail_click_peak := float(rail_click.get("peak", 0.0))
	var rail_hits := int(rail.get("hits", 0))
	var bus_peak := _s_peak
	var bus_clamp := _s_clip

	print("[spu-metrics %-20s t=%4.1fs] rail peak=%.2f hits=%d clk=%.2f | sfxbus peak=%.2f clip=%d | mstr peak=%.2f clip=%d maxjump=%.3f | fps=%d" % [
		PHASES[_phase_idx]["label"], _phase_t,
		rail_peak, rail_hits, rail_click_peak,
		bus_peak, bus_clamp,
		_m_peak, _m_clip, _m_maxjump,
		Engine.get_frames_per_second()])

	# Fold into per-phase worst-of.
	_p_rail_peak = maxf(_p_rail_peak, rail_peak)
	_p_rail_click_peak = maxf(_p_rail_click_peak, rail_click_peak)
	_p_rail_hits = maxi(_p_rail_hits, rail_hits)
	_p_bus_peak = maxf(_p_bus_peak, bus_peak)
	_p_bus_clamp = maxi(_p_bus_clamp, bus_clamp)
	_p_master_peak = maxf(_p_master_peak, _m_peak)
	_p_master_clip = maxi(_p_master_clip, _m_clip)
	_p_master_maxjump = maxf(_p_master_maxjump, _m_maxjump)

	# Next second is a fresh window at every stage.
	ExMateriaEffectSfx.reset_audio_stats()
	_reset_master_window()


func _close_phase() -> void:
	var res := {
		"label": PHASES[_phase_idx]["label"],
		"rate": int(PHASES[_phase_idx]["rate"]),
		"rail_peak": _p_rail_peak,
		"rail_click_peak": _p_rail_click_peak,
		"rail_hits": _p_rail_hits,
		"bus_peak": _p_bus_peak,
		"bus_clamp": _p_bus_clamp,
		"master_peak": _p_master_peak,
		"master_clip": _p_master_clip,
		"master_maxjump": _p_master_maxjump,
	}
	_results.append(res)
	if int(PHASES[_phase_idx]["rate"]) == 0:
		_baseline_maxjump = _p_master_maxjump
	print("[spu-metrics] phase %d worst: rail peak=%.2f hits=%d | sfxbus peak=%.2f clip=%d | mstr peak=%.2f clip=%d maxjump=%.3f" % [
		_phase_idx, res["rail_peak"], res["rail_hits"], res["bus_peak"], res["bus_clamp"],
		res["master_peak"], res["master_clip"], res["master_maxjump"]])


func _finish() -> void:
	if _sfx_bus_missing:
		print("[FAIL] there is no SFX bus, so the SFX-bus stage measured nothing and "
			+ "BUS_CLAMP_RATE_FAIL (%d) could not have tripped. A gate that cannot " % BUS_CLAMP_RATE_FAIL
			+ "fail is not a gate — see this file's own header.")
		get_tree().quit(1)
		return
	print("[spu-metrics] ===== RESULT =====")
	var saturation := false   # a stage crossed a rail
	var discontinuity := false
	var fails: Array = []
	var worst_burst_maxjump := 0.0

	for res in _results:
		if int(res["rate"]) == 0:
			continue  # baseline is the reference, never a failure
		worst_burst_maxjump = maxf(worst_burst_maxjump, float(res["master_maxjump"]))
		if int(res["rail_hits"]) > RAIL_HIT_RATE_FAIL:
			saturation = true
			fails.append("%s: native SPU rail cut %d samples/s (in-core clip)" % [res["label"], res["rail_hits"]])
		if int(res["bus_clamp"]) > BUS_CLAMP_RATE_FAIL:
			saturation = true
			fails.append("%s: the SFX bus sat at the rail for %d samples/s (its HardLimiter could not hold it)" % [res["label"], res["bus_clamp"]])
		if int(res["master_clip"]) > MASTER_CLIP_RATE_FAIL:
			saturation = true
			fails.append("%s: Master hit the device rail %d samples/s (SFX+music sum)" % [res["label"], res["master_clip"]])
		if float(res["master_maxjump"]) >= MAXJUMP_FAIL:
			discontinuity = true
			fails.append("%s: final-mix step %.3f FS >= %.2f (retrigger discontinuity)" % [res["label"], res["master_maxjump"], MAXJUMP_FAIL])

	# Softer discontinuity signal: burst maxjump grows sharply over the music-only
	# baseline even if it stays under the hard gate.
	var grew := _baseline_maxjump > 0.0 and worst_burst_maxjump >= _baseline_maxjump * MAXJUMP_WARN_FACTOR
	if grew and not discontinuity:
		print("[spu-metrics] NOTE discontinuity signal: burst maxjump %.3f is %.1fx the music-only baseline %.3f — per-retrigger steps present (below the %.2f hard gate)." % [
			worst_burst_maxjump, worst_burst_maxjump / maxf(_baseline_maxjump, 0.0001), _baseline_maxjump, MAXJUMP_FAIL])

	print("[spu-metrics] mechanism: saturation(rail crossed)=%s  discontinuity(retrigger step)=%s" % [saturation, discontinuity or grew])
	if saturation:
		print("[spu-metrics]   -> SATURATION fix: reduce click level / add headroom; the SFX bus HardLimiter is downstream of the in-core clip and cannot undo it.")
	if discontinuity or grew:
		print("[spu-metrics]   -> DISCONTINUITY fix: short attack/release or 1-2 ms crossfade on the click retrigger, and/or a retrigger-rate cap.")

	if fails.is_empty():
		print("[PASS] no stage railed and no hard discontinuity during the click sweep.")
		get_tree().quit(0)
		return
	for f in fails:
		print("[spu-metrics][fail]  - %s" % f)
	print("[FAIL] %d saturation/discontinuity condition(s) tripped during the click sweep." % fails.size())
	get_tree().quit(1)


func _drain_master_tap() -> void:
	if _cap == null:
		return
	var navail := _cap.get_frames_available()
	if navail <= 0:
		return
	var buf: PackedVector2Array = _cap.get_buffer(navail)
	for fr in buf:
		var a := maxf(absf(fr.x), absf(fr.y))
		_m_peak = maxf(_m_peak, a)
		if a >= 0.999:
			_m_clip += 1
		if _m_have:
			_m_maxjump = maxf(_m_maxjump, (fr - _m_prev).length())
		_m_prev = fr
		_m_have = true


func _drain_sfx_tap() -> void:
	if _sfx_cap == null:
		return
	var navail := _sfx_cap.get_frames_available()
	if navail <= 0:
		return
	var buf: PackedVector2Array = _sfx_cap.get_buffer(navail)
	for fr in buf:
		var a := maxf(absf(fr.x), absf(fr.y))
		_s_peak = maxf(_s_peak, a)
		if a >= 0.999:
			_s_clip += 1


func _reset_master_window() -> void:
	_s_peak = 0.0
	_s_clip = 0
	_m_peak = 0.0
	_m_clip = 0
	_m_maxjump = 0.0
	_m_have = false


func _reset_phase_worst() -> void:
	_p_rail_peak = 0.0
	_p_rail_click_peak = 0.0
	_p_rail_hits = 0
	_p_bus_peak = 0.0
	_p_bus_clamp = 0
	_p_master_peak = 0.0
	_p_master_clip = 0
	_p_master_maxjump = 0.0
