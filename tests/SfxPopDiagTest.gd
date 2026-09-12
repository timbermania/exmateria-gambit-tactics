extends Node

## SfxPopDiagTest — diagnostic harness for the "popping when multiple fires play
## at once" report. NOT a pass/fail regression: it fires N simultaneous Fire
## (E016) casts offline and prints, per mechanism, what's happening "in the data"
## so we can tell which click source is firing:
##
##   sfx_bus_peak        — how hard concurrency pushes the SFX bus (the number
##                         that decided #385 task 3 §3a: Fire x6 reaches 4.26)
##   in-core rail        — saturation INSIDE a unit's C++ core, the one clip stage
##                         a downstream bus limiter cannot undo
##   preempts            — voice pairs stolen mid-flight
##   cap_doublings       — casts forced to share a unit at the MAX_UNITS cap
##   block jump          — amplitude discontinuity across an IRQ block seam
##
## (This is the OFFLINE sum: capture_mode parks the scheduler and render_subs
## drives the units in lockstep. The live path renders one stream per unit on the
## audio thread and sums on the SFX bus — same arithmetic, different summer.)
##
## Run:  godot --path . res://tests/SfxPopDiagTest.tscn

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const EffectSoundControllerClass = preload("res://addons/exmateria_sound/runtime/effect_sound_controller.gd")

const SUBS_PER_FRAME := 8
const FRAMES := 60
const FIRE_ID := "E016"


func _ready() -> void:
	# #463: this scene is a rig, not a test. Declared FIRST so it is on the
	# record even on the early-exit paths below. The verdict reader scores it
	# NOT_A_TEST — see tests/lib/verdict.sh; it used to score NO_VERDICT, which
	# is the label for a test that did not run.
	print("[NOT_A_TEST] a limiter/pop diagnostic — it prints raw_peak and limiter gain steps for a human and asserts nothing; named *Test, but it is a rig")
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	for n in [1, 2, 3, 4, 6]:
		_run_case(n)

	get_tree().quit(0)


func _on_pair(pair_idx: int, _ch: int, sid: int, _phase: String, token: int, fb) -> void:
	ExMateriaEffectSfx.play_pair(token, fb, pair_idx, sid)


func _run_case(num_casts: int) -> void:
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()

	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/%s" % FIRE_ID)
	if loaded == null or not loaded.has_sound():
		print("[diag] %s has no sound data" % FIRE_ID)
		return
	var fb = loaded.feds_bank

	var tokens: Array = []
	var controllers: Array = []
	for k in range(num_casts):
		var t: int = ExMateriaEffectSfx.begin_effect()
		tokens.append(t)
		var stc = EffectSoundControllerClass.new()
		stc.debug_log = false
		stc.load_effect(loaded)
		stc.pair_triggered.connect(_on_pair.bind(t, fb))  # per-cast binding
		stc.start(1, 0, {})
		controllers.append(stc)

	# The offline cross-unit sum, one IRQ block at a time. This used to be fed
	# through a BusLimiter so the rig could report what the limiter DID to it; that
	# limiter is gone (#385 task 3), so what it reports now is the load the SFX bus
	# actually carries — the number that decided where the limiting goes.
	var raw_peak := 0.0
	var max_raw_jump := 0.0       # boundary discontinuity in the summed signal
	var have_prev := false
	var prev_raw := Vector2.ZERO
	var inv := 1.0 / 32767.0

	for f in range(FRAMES):
		for stc in controllers:
			stc.update(f)
		for _s in range(SUBS_PER_FRAME):
			var irq: PackedInt32Array = ExMateriaEffectSfx.render_subs(1)
			if irq.size() < 2:
				continue
			for v in irq:
				raw_peak = maxf(raw_peak, absf(float(v)) * inv)
			# Boundary jump = |first sample of this block - last sample of prev|.
			var raw_first := Vector2(float(irq[0]) * inv, float(irq[1]) * inv)
			var raw_last := Vector2(float(irq[irq.size() - 2]) * inv, float(irq[irq.size() - 1]) * inv)
			if have_prev:
				max_raw_jump = maxf(max_raw_jump, (raw_first - prev_raw).length())
			prev_raw = raw_last
			have_prev = true

	for t in tokens:
		ExMateriaEffectSfx.end_effect(t)
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var rail: Dictionary = snap.get("rail", {})
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false

	# sfx_bus_peak is the headline: the summed level the SFX bus carries with no
	# GDScript limiter in front of it. > 1.0 is the gain reduction the bus
	# HardLimiter has to apply; how far above 1.0 it climbs with concurrency is
	# what makes a per-domain limiter necessary instead of a Master-only one.
	print("[diag x%d] sfx_bus_peak=%.2f (needs %.1f dB duck) | in-core rail peak=%.2f hits=%d | preempts=%d cap_doubles=%d units=%d | block jump=%.3f"
		% [num_casts, raw_peak,
			0.0 if raw_peak <= 1.0 else linear_to_db(1.0 / raw_peak),
			rail.get("pre_clamp_peak", 0.0), int(rail.get("hits", 0)),
			snap.get("preempts", 0), snap.get("cap_doublings", 0), snap.get("units", []).size(),
			max_raw_jump])
