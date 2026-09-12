extends Node

## SfxTraceProbeGateTest — the PARITY TRACE probes in `tick_irq_start_for_runtime`
## must not do their work when tracing is off.
##
## THE DEFECT THIS GUARDS. `_EffectPlaySound.tick_irq_start_for_runtime` runs on
## the LIVE audio path, once per 240 Hz IRQ PER ACTIVE SPU UNIT. Its body is
## entirely parity capture — `_emit_envelope_tail_for_runtime` plus the two noise
## emits — and `_Trace.emit` is cheap when disabled, but its ARGUMENTS are not:
## between them they call `mixer.get_voice_debug_info()` 49 times (24 voices,
## twice, plus one), each building a Dictionary across the GDExtension boundary,
## and then throw every row away.
##
## The gate was `if _cadence_anchored:` alone, which is a parity-anchor condition,
## not a "is anyone recording" one. Measured on the live scheduler: 818 us per
## active unit per sub against a 4.16 ms budget, so the engine ran out of budget
## at FOUR concurrent casts — half the transient pool. Past that the audio clock
## fell to 115 subs/s, the scheduler lead went to MINUS SIX SECONDS (register
## writes reaching the audio thread long after their own frame), a main-thread
## `_audio_mutex` acquirer waited 33 ms and the game dropped to 29 fps. Adding
## `and _Trace.is_enabled()` holds 240 subs/s, +25 ms lead and 60 fps at the full
## 8-unit pool. #668.
##
## Music never showed it — separate SPU, main-thread stamping, a 2.0 s lead
## against SFX's 25 ms — which is exactly how the report arrived: "the music
## always sounds good, even when the other noises are sounding off".
##
## Two arms, and the SECOND is what keeps the first from being vacuous:
##   1. the gated entry point costs an order of magnitude less than the payload
##      it must not build (a RATIO, so it does not encode this machine's speed)
##   2. the payload builder is genuinely expensive here — if it were not, arm 1
##      would pass however the gate was written
##
## Plus two preconditions asserted outright, because either one silently makes
## the whole test measure the wrong branch: tracing must be OFF, and
## `_cadence_anchored` must be ON (the gate's other term).
##
## Run:  godot --path . res://tests/SfxTraceProbeGateTest.tscn

const PlaySound_ = preload("res://addons/exmateria_sound/runtime/effect_sound/play_sound.gd")
const Trace_ = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")

const ITERS := 2000
# The gated call is ~2 us and the payload it skips is ~800 us, so a 10x floor has
# ~40x of margin while staying far away from timer noise.
const MIN_RATIO := 10.0
# Arm 2: the payload has to actually cost something on this machine, or arm 1's
# ratio is measuring nothing. 50 us/call is a tenth of what it measures live.
const MIN_PAYLOAD_US := 50.0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var failed := false

	# A real, instrument-loaded SPU — get_voice_debug_info on a bare one would not
	# cost what it costs in the game.
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()
	var units: Array = ExMateriaEffectSfx._units
	if units.is_empty():
		print("[FAIL] no SFX unit to probe")
		ExMateriaEffectSfx.capture_mode = false
		get_tree().quit(1)
		return
	var mixer = units[0]["mixer"]

	# --- preconditions ------------------------------------------------------
	if Trace_.is_enabled():
		print("[FAIL] trace sink is open — this test measures the DISABLED path")
		failed = true
	var anchored_was: bool = PlaySound_._cadence_anchored
	# The gate is `_cadence_anchored and _Trace.is_enabled()`. With the anchor
	# false the body is skipped for the OTHER reason and removing the trace term
	# would not show up at all, so assert it on rather than hope for it.
	PlaySound_._cadence_anchored = true
	if not PlaySound_._cadence_anchored:
		print("[FAIL] could not anchor the cadence — arm 1 would be vacuous")
		failed = true

	# --- arm 1: the gated entry point does not build the payload ------------
	var gated_us := _time_calls(func(i: int): PlaySound_.tick_irq_start_for_runtime(mixer, i))
	# --- arm 2: ...and the payload is genuinely expensive -------------------
	var payload_us := _time_calls(func(i: int): PlaySound_._emit_envelope_tail_for_runtime(mixer, i))

	PlaySound_._cadence_anchored = anchored_was
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false

	if payload_us < MIN_PAYLOAD_US:
		print("[FAIL] arm 2: the skipped payload costs only %.2f us/call (< %.1f) — "
				% [payload_us, MIN_PAYLOAD_US]
				+ "arm 1's ratio proves nothing on this build")
		failed = true
	var ratio := payload_us / maxf(0.001, gated_us)
	if ratio < MIN_RATIO:
		print("[FAIL] arm 1: tick_irq_start_for_runtime costs %.2f us/call against a "
				% gated_us
				+ "%.2f us payload (ratio %.1fx < %.1fx) — it is BUILDING the parity "
				% [payload_us, ratio, MIN_RATIO]
				+ "trace payload with no trace sink open. Restore the "
				+ "`and _Trace.is_enabled()` term on the _cadence_anchored gate.")
		failed = true

	if failed:
		print("[FAIL] SfxTraceProbeGateTest")
		get_tree().quit(1)
	else:
		print("[PASS] trace probe gated: %.2f us/call vs %.2f us of skipped payload (%.0fx)"
				% [gated_us, payload_us, ratio])
		get_tree().quit(0)


func _time_calls(fn: Callable) -> float:
	# Warm once so the first call's script/binding setup isn't in the sample.
	fn.call(0)
	var t0 := Time.get_ticks_usec()
	for i in range(ITERS):
		fn.call(i)
	return float(Time.get_ticks_usec() - t0) / float(ITERS)
