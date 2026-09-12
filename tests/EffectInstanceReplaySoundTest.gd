extends Node
## Regression guard for the STUDIO SFX-replay bug: after an effect plays once, a
## studio Stop/loop-restart re-seeks the SAME instance back to 0 (EffectInstance.seek(0),
## a backward seek) and plays again — but the sound must re-fire on that second play.
##
## The bug: EffectInstance.seek() delegates to EffectTimeline.seek(), whose backward
## branch calls EffectTimeline.reset() → subsystem.reset() for each subsystem. The
## SoundSubsystem adapter's reset() is a no-op, and the sound controller's restart
## (EffectSoundController.start() + a fresh ExMateriaEffectSfx cast — a FINISHED entity
## won't sequence again) lives only in EffectInstance.reset(), which the seek path never
## calls. So the controller's channels stay `done` from the first playthrough and the
## second play fires nothing.
##
## The loop drives the REAL path: a real loaded effect (E065, fires in phase1) → a real
## EffectSoundController → EffectInstance.seek() forward (play), seek(0) (rewind), seek()
## forward (replay). Signal = EffectSoundController.pair_triggered (the honest "a trigger
## fired" event, upstream of the SPU). Deterministic, no audio device needed.
##
## Run: godot --path . res://tests/EffectInstanceReplaySoundTest.tscn

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const EffectSoundControllerClass = preload("res://addons/exmateria_sound/runtime/effect_sound_controller.gd")
const EffectInstanceClass = ExMateriaEffects.EffectInstance
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const SoundSubsystemClass = preload("res://addons/exmateria_effects/subsystem/SoundSubsystem.gd")

const EFFECT_DIR := "res://assets/effects/E065"   # Shiva — fires in phase1
const PLAY_FRAMES := 150                          # 5 s: full onset + tail past the end


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] ExMateriaEffectSfx not ready")
		get_tree().quit(1)
		return
	var ok := _test_studio_replay_refires_sound()
	if ok:
		print("[PASS] EffectInstanceReplaySoundTest")
		get_tree().quit(0)
	else:
		print("[FAIL] EffectInstanceReplaySoundTest")
		get_tree().quit(1)


func _test_studio_replay_refires_sound() -> bool:
	var loaded = EffectJSONLoaderClass.load_dir(EFFECT_DIR)
	if loaded == null or not loaded.has_sound():
		print("[setup] %s has no sound data" % EFFECT_DIR)
		return false

	var stc = EffectSoundControllerClass.new()
	if not stc.load_effect(loaded):
		print("[setup] load_effect failed")
		return false

	var fires := {"n": 0}
	stc.pair_triggered.connect(func(_p: int, _c: int, _s: int, _ph: String) -> void:
		fires["n"] += 1)

	# Minimal EffectInstance wired like initialize() does for the sound path, without
	# spawning particles/overlays. We drive its public seek() — the studio's scrub/replay
	# surface — and observe the controller re-fire.
	var inst = EffectInstanceClass.new()
	inst._sound_loaded = loaded
	inst._sound_controller = stc
	inst._sfx_token = ExMateriaEffectSfx.begin_effect()
	stc.start(1, 0, {})

	var header: Dictionary = loaded.timeline_header
	var p1d := int(header.get("phase1_duration", 0))
	var p2s := p1d + int(header.get("phase2_delay", 0))
	var timeline = EffectTimelineClass.new()
	timeline.setup(p1d, p2s, {})
	timeline.set_subsystems([null, SoundSubsystemClass.new(stc), null, null, null])
	timeline.start()
	inst.effect_timeline = timeline

	# First play: pump forward to the end.
	inst.seek(PLAY_FRAMES)
	var first := int(fires["n"])

	# Studio Stop / loop-restart: re-seek THIS instance back to 0 (a backward seek), then
	# play forward again. A fresh SFX cast must open (the old entity is finished).
	var token_before := int(inst._sfx_token)
	inst.seek(0)
	fires["n"] = 0
	inst.seek(PLAY_FRAMES)
	var second := int(fires["n"])
	var token_after := int(inst._sfx_token)

	var ok := true
	if first <= 0:
		print("[replay] the FIRST play fired no sound (%d) — harness broken" % first)
		ok = false
	if second != first:
		print("[replay] second play fired %d triggers, expected %d (the bug: replay is silent)" % [second, first])
		ok = false
	if token_after == token_before:
		print("[replay] the SFX cast token was NOT refreshed on rewind (a finished entity won't re-sequence → silent)")
		ok = false
	if ok:
		print("[replay] first=%d second=%d token %d→%d — replay re-fires + fresh cast" % [
			first, second, token_before, token_after])
	inst.free()
	return ok
