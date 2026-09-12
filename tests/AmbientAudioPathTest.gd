extends Node

## AmbientAudioPathTest — verifies the dedicated ambient ({6B} BG Sound) SPU path:
## a persistent looping bed binds a RESERVED unit held OUTSIDE the MAX_UNITS
## transient combat-SFX pool, so it never consumes a combat slot, is never returned
## by _pick_unit, and never counts against the 8-unit combat budget. Its headroom is
## decoupled from combat's by playing on its OWN bus (Ambient), which is where #385
## task 3 moved the job the hand-rolled `bg_limiter` used to do; the sub-level trim
## (debug knob, default 1.0) is now the ambient players' volume_db. See /tmp handoff
## + BGSOUND_OPCODE_6B_INVESTIGATION.md.
##
## Config-level asserts (constants / the level knob) run WITHOUT a live SPU. The
## routing/budget asserts require the SPU GDExtension (as EffectSoundCaptureTest /
## SfxUnitRoutingTest do in the same run_all_tests.sh harness).
##
## Run:  godot --path . res://tests/AmbientAudioPathTest.tscn

const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
const ENV_BANK := "res://assets/audio/sfx_banks/env.feds"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Always-runnable config asserts (no SPU dependency).
	_test_config_defaults()
	_test_level_knob_clamps()

	if ExMateriaAudioEngine.ready_ok and ExMateriaEffectSfx.ready_ok:
		_test_bg_binds_reserved_unit()
		_test_combat_budget_unaffected_by_bed()
		_test_snapshot_exposes_ambient_channel()
	else:
		print("[AmbientAudioPathTest] SPU not ready — ran config asserts only")

	print("\n=== AmbientAudioPathTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] AmbientAudioPathTest: ran zero assertions")
		get_tree().quit(1)
	elif _failed > 0:
		print("[FAIL] AmbientAudioPathTest")
		get_tree().quit(1)
	else:
		print("[PASS] AmbientAudioPathTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- config (no SPU) ---------------------------------------------------------

func _test_config_defaults() -> void:
	_ok(ExMateriaEffectSfx.MAX_BG_UNITS >= 2, "MAX_BG_UNITS is a small fixed set (>=2)")
	_eq(ExMateriaEffectSfx.get_bg_level(), 1.0, "ambient level defaults to 1.0 (no trim)")


func _test_level_knob_clamps() -> void:
	ExMateriaEffectSfx.set_bg_level(0.5)
	_eq(ExMateriaEffectSfx.get_bg_level(), 0.5, "set_bg_level(0.5) applied")
	ExMateriaEffectSfx.set_bg_level(2.0)
	_eq(ExMateriaEffectSfx.get_bg_level(), 1.0, "set_bg_level clamps above 1.0")
	ExMateriaEffectSfx.set_bg_level(-1.0)
	_eq(ExMateriaEffectSfx.get_bg_level(), 0.0, "set_bg_level clamps below 0.0")
	ExMateriaEffectSfx.set_bg_level(1.0)  # restore default for the rest of the run


# --- routing (needs SPU) -----------------------------------------------------

func _mixer_in(units: Array, mixer) -> bool:
	for u in units:
		if u["mixer"] == mixer:
			return true
	return false


func _test_bg_binds_reserved_unit() -> void:
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()

	var handle: int = ExMateriaEffectSfx.begin_bg(ENV_BANK, 0, 1)  # Rain 1 = env pair 0
	if handle == 0:
		_failed += 1
		print("  [FAIL] begin_bg returned 0 (env bank / SPU issue)")
		ExMateriaEffectSfx.capture_mode = false
		return

	var session: Dictionary = ExMateriaEffectSfx._sessions.get(handle, {})
	var bound = session.get("unit", null)
	_ok(bound != null, "bg cast bound a unit")
	if bound != null:
		var mixer = bound["mixer"]
		_ok(_mixer_in(ExMateriaEffectSfx._bg_units, mixer), "bg cast bound a RESERVED ambient unit")
		_ok(not _mixer_in(ExMateriaEffectSfx._units, mixer), "bg cast did NOT bind a transient combat unit")
	_ok(ExMateriaEffectSfx._bg_units.size() >= 1, "at least one reserved ambient unit spawned")

	ExMateriaEffectSfx.stop_bg(handle)
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false


func _test_combat_budget_unaffected_by_bed() -> void:
	# A live bed must NOT cost combat a slot: with a bed playing, MAX_UNITS combat
	# casts still each get their own transient unit, and none is the bed's unit.
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.reset_audio_stats()

	var loaded = EffectJSONLoaderClass.load_dir("res://assets/effects/E065")
	if loaded == null or not loaded.has_sound():
		_failed += 1
		print("  [FAIL] no combat FEDS (E065) to test against")
		ExMateriaEffectSfx.capture_mode = false
		return
	var fb = loaded.feds_bank

	# Start the persistent bed first.
	var bed: int = ExMateriaEffectSfx.begin_bg(ENV_BANK, 0, 1)
	var bed_mixer = null
	if bed != 0:
		bed_mixer = ExMateriaEffectSfx._sessions.get(bed, {}).get("unit", {}).get("mixer", null)

	# Now fill the transient pool with MAX_UNITS concurrent combat casts.
	var n: int = ExMateriaEffectSfx.MAX_UNITS
	var tokens: Array = []
	for k in range(n):
		var t: int = ExMateriaEffectSfx.begin_effect()
		tokens.append(t)
		ExMateriaEffectSfx.play_pair(t, fb, 0, 1)

	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	var occupied := 0
	var max_sessions := 0
	for u in snap.get("units", []):
		var sc: int = int(u.get("sessions", 0))
		if sc > 0:
			occupied += 1
		max_sessions = maxi(max_sessions, sc)

	_eq(occupied, n, "all %d combat casts got a transient unit with a bed live" % n)
	_eq(max_sessions, 1, "no combat cast doubled onto a shared transient unit")
	_eq(int(snap.get("cap_doublings", -1)), 0, "bed forced zero combat in-core doublings")
	# The bed's unit is out of the transient pool entirely.
	if bed_mixer != null:
		_ok(not _mixer_in(ExMateriaEffectSfx._units, bed_mixer), "bed unit never entered the transient pool")

	for t in tokens:
		ExMateriaEffectSfx.end_effect(t)
	if bed != 0:
		ExMateriaEffectSfx.stop_bg(bed)
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false


func _test_snapshot_exposes_ambient_channel() -> void:
	ExMateriaEffectSfx.set_voice_mode(ExMateriaEffectSfx.VoiceMode.UNLOCKED)
	ExMateriaEffectSfx.capture_mode = true
	ExMateriaEffectSfx.panic()

	var bed: int = ExMateriaEffectSfx.begin_bg(ENV_BANK, 0, 1)
	var snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
	_ok(snap.has("bg_units"), "snapshot exposes bg_units")
	# The ambient/combat headroom split, asserted where it now LIVES. Until #385
	# task 3 this read `snap.has("bg_limiter")` — the presence of a second
	# hand-rolled GDScript limiter. That limiter is gone (`D3` dec. 4); the beds are
	# decoupled from combat by playing on their OWN bus, each with its own
	# HardLimiter installed by the host, so the claim is now checkable directly
	# rather than inferred from a stats dictionary existing.
	_ok(not snap.has("bg_limiter"), "the hand-rolled ambient limiter is GONE (D3 dec. 4)")
	_eq(int(snap.get("max_bg_units", -1)), ExMateriaEffectSfx.MAX_BG_UNITS, "snapshot reports max_bg_units")
	var bg_units: Array = snap.get("bg_units", [])
	var bg_sessions := 0
	for u in bg_units:
		bg_sessions += int(u.get("sessions", 0))
	# ...and the routing that replaced it: a bed plays on Ambient, combat on SFX.
	# Read as a set so a bed that silently landed in the transient pool fails here
	# rather than passing on a count that happens to match.
	for u in bg_units:
		_eq(str(u.get("bus", "")), "Ambient", "an ambient unit is routed to the Ambient bus")
	for u in snap.get("units", []):
		_eq(str(u.get("bus", "")), "SFX", "a combat unit is routed to the SFX bus")
	if bed != 0:
		_eq(bg_sessions, 1, "a live bed shows exactly one ambient-unit session")

	if bed != 0:
		ExMateriaEffectSfx.stop_bg(bed)
	ExMateriaEffectSfx.panic()
	ExMateriaEffectSfx.capture_mode = false
