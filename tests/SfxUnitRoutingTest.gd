extends Node

## SfxUnitRoutingTest — verifies UNLOCKED routing puts each concurrent cast on
## its OWN SPU unit (one cast per unit), so concurrent casts mix at the bus
## limiter rather than summing + brick-wall-clipping inside one unit's C++ core
## (and each cast gets its own reverb tank — no cross-cast tail smear).
##
## Before the change, _pick_unit packed casts onto the first unit with a free
## pair, so 3 single-pair casts all landed on unit 0 (one unit, session_count=3).
## After: 3 casts -> 3 distinct units, each session_count == 1.
##
## Run:  godot --path . res://tests/SfxUnitRoutingTest.tscn

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var ok := _test_one_cast_per_unit()

	if ok:
		print("[PASS] SFX unit routing: one cast per unit")
		get_tree().quit(0)
	else:
		print("[FAIL] SFX unit routing")
		get_tree().quit(1)


func _test_one_cast_per_unit() -> bool:
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()

	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	if loaded == null or not loaded.has_sound():
		print("[routing] no sound data for E065")
		ExMateriaEffectSfx.capture_mode = false
		return false
	var fb = loaded.feds_bank

	# Three concurrent casts, each dispatching a single pair (binds it to a unit).
	const CASTS := 3
	var tokens: Array = []
	for k in range(CASTS):
		var t: int = ExMateriaEffectSfx.begin_effect()
		tokens.append(t)
		ExMateriaEffectSfx.play_pair(t, fb, 0, 1)

	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var units: Array = snap.get("units", [])
	var occupied := 0
	var max_sessions := 0
	for u in units:
		var sc: int = int(u.get("sessions", 0))
		if sc > 0:
			occupied += 1
		max_sessions = maxi(max_sessions, sc)

	# One cast per unit: as many occupied units as casts, none holding more than 1.
	var ok: bool = occupied == CASTS and max_sessions == 1

	for t in tokens:
		ExMateriaEffectSfx.end_effect(t)
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false

	print("[routing] %d casts -> occupied_units=%d max_sessions_on_a_unit=%d -> %s"
		% [CASTS, occupied, max_sessions, "OK" if ok else "BAD: casts packed onto shared unit(s)"])
	return ok
