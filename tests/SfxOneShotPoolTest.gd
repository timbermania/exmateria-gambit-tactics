extends Node

## SfxOneShotPoolTest — a burst of fire-and-forget game-event SFX must not grow
## the transient combat SPU pool, and must drain promptly.
##
## THE DEFECT THIS GUARDS. Every non-retrigger SfxRouter cue (play_cue,
## play_system, play_system_by_id, play_env, the combat.unit_died handler)
## funnels through _play_slot, which opened a cast nothing ever ends. Those casts
## went to _pick_unit, whose one-cast-per-unit policy spawned a whole SPU per
## blip up to MAX_UNITS, and _reap_dead_sessions charged them the full
## REAP_GRACE_SUBS (2 s) meant for a multi-pair effect that might still dispatch.
## So any repeated cue took the pool to the cap and held it there.
##
## That is not merely wasteful. Measured in GPUArena, at 8 live units the
## scheduler's per-sub stamping runs over its 4.16 ms real-time budget: the audio
## clock fell to ~130 subs/s against a required 240 (the SFX and the music both
## slow down), and a main-thread _audio_mutex acquirer waited up to 3591 ms.
##
## The fix routes one-shot casts to a bounded RESERVED event lane
## (play_one_shot / _pick_event_unit) which PACKS instead of spreading, and gives
## them ONE_SHOT_REAP_GRACE_SUBS instead of REAP_GRACE_SUBS.
##
## Four arms, in the order the defect happened:
##   1. a burst does not grow the transient pool at all
##   2. it lands on the reserved event lane, within max_event_units
##   3. the lane PACKS — a burst that fits one unit uses one unit
##   4. one-shot sessions drain in well under REAP_GRACE_SUBS
##
## Runs in capture_mode: no audio device, no scheduler thread, and render_subs
## advances the IRQ clock deterministically so arm 4 is a real clock, not a sleep.
##
## Run:  godot --path . res://tests/SfxOneShotPoolTest.tscn

const Engine_ = preload("res://addons/exmateria_sound/runtime/effect_sfx_engine.gd")

# One-shot cues, at a rate the game can genuinely reach: FormationDetailTransition
# fires play_system("invalid") on every rejected input, which is key-repeat driven.
const BURST := 8
# Ceiling for arm 4 — one sub short of the multi-pair grace. Draining inside this
# is precisely what distinguishes a one-shot session from an effect cast, so a
# revert of the grace split fails here rather than passing quietly.
const DRAIN_LIMIT_SUBS := Engine_.REAP_GRACE_SUBS - 1
const DRAIN_STEP_SUBS := 30


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var failed := false
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()

	var before: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var units_before: int = int(before.get("units", []).size())
	var max_event: int = int(before.get("max_event_units", 0))

	# The REAL router path, not a replica — play_system is what the game calls.
	var fired := 0
	for i in range(BURST):
		if SfxRouter.play_system("invalid") != 0:
			fired += 1
	if fired != BURST:
		print("[FAIL] only %d/%d cues dispatched (system bank 'invalid' missing?)" % [fired, BURST])
		ExMateriaEffectSfx.capture_mode = false
		get_tree().quit(1)
		return

	var after: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var units_after: int = int(after.get("units", []).size())
	var event_units: Array = after.get("event_units", [])

	# --- arm 1: the transient combat pool is untouched -----------------------
	if units_after != units_before:
		print("[FAIL] %d one-shot cues grew the transient pool %d -> %d (must stay put)"
				% [BURST, units_before, units_after])
		failed = true

	# --- arm 2: they went to the reserved lane, and it is bounded ------------
	var event_sessions := 0
	for u in event_units:
		event_sessions += int(u.get("sessions", 0))
	if event_sessions != BURST:
		print("[FAIL] reserved event lane holds %d sessions, expected %d"
				% [event_sessions, BURST])
		failed = true
	if event_units.size() > max_event:
		print("[FAIL] event lane spawned %d units, cap is %d" % [event_units.size(), max_event])
		failed = true

	# --- arm 3: the lane PACKS rather than spreading -------------------------
	# BURST fits EVENT_SESSIONS_PER_UNIT, so one unit must absorb all of it. This
	# is the arm that fails if one-shots are ever routed back through _pick_unit's
	# one-cast-per-unit policy while still nominally "in the lane".
	if BURST <= Engine_.EVENT_SESSIONS_PER_UNIT and event_units.size() != 1:
		print("[FAIL] %d cues fit one event unit (cap %d/unit) but occupied %d"
				% [BURST, Engine_.EVENT_SESSIONS_PER_UNIT, event_units.size()])
		failed = true

	# --- arm 4: one-shot sessions drain well inside the multi-pair grace -----
	# Drive the IRQ clock ourselves (capture_mode parks the scheduler), so this
	# measures sub-ticks, not wall time.
	var drained_at := -1
	var subs := 0
	while subs < DRAIN_LIMIT_SUBS:
		ExMateriaEffectSfx.render_subs(DRAIN_STEP_SUBS)
		subs += DRAIN_STEP_SUBS
		if int(ExMateriaEffectSfx.debug_snapshot().get("sessions", 0)) == 0:
			drained_at = subs
			break
	if drained_at < 0:
		print("[FAIL] one-shot sessions still held after %d subs (>= REAP_GRACE_SUBS %d) — "
				% [subs, Engine_.REAP_GRACE_SUBS]
				+ "they are being charged the multi-pair grace")
		failed = true
	else:
		print("[info] one-shot sessions drained at %d subs (multi-pair grace is %d)"
				% [drained_at, Engine_.REAP_GRACE_SUBS])

	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false

	if failed:
		print("[FAIL] SfxOneShotPoolTest")
		get_tree().quit(1)
	else:
		print("[PASS] one-shot SFX: transient pool %d (unchanged), event lane %d unit(s)/%d sessions, drained at %d subs"
				% [units_after, event_units.size(), BURST, drained_at])
		get_tree().quit(0)
