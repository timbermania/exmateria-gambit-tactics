extends Node

## SfxOneShotSessionDrainTest — W11/R28. Pins the ONE-SHOT silence reap.
##
## `_reap_dead_sessions`' "still audible" condition asks `_unit_voice_count(u)`,
## which is a per-UNIT question. Every `play_one_shot` cast packs onto the
## MAX_EVENT_UNITS=2 reserved event cores, so while ANY blip on a core is audible
## every other session bound to it is un-reapable. Under sustained combat that is
## permanently true: measured at 80 units, 99.5 % of all reap skips, `killed` = 0
## after the first window, and 240 drained sessions still linked into their core's
## entity list and sequenced every sub — which put the SPU scheduler over its
## 4.16 ms/sub budget and made a main-thread cue wait 25.7 ms on `_audio_mutex`.
## `ONE_SHOT_SILENCE_SUBS` is the narrow way past the veto. See
## `godot-learning/docs/GPU-ARENA-PERF.md` → Round 28.
##
## The contract, both halves:
##   1. a ONE-SHOT cast that is sequencing-done and silent for
##      ONE_SHOT_SILENCE_SUBS drains EVEN WHILE ITS CORE STAYS AUDIBLE;
##   2. a non-one-shot cast NEVER takes that path — it keeps the veto.
##
## Counted work, not wall clock (W8's ruling): the assertions are session counts
## and the `silence_freed` counter, driven by `render_subs()` so the IRQ clock is
## exact. A fresh `init_as_capture()` engine is used deliberately — its units are
## not streaming, so `_unit_voice_count` reads `get_active_voice_count()`
## synchronously instead of the audio thread's published count, which would make
## the "is the core still audible" precondition racy.
##
## Run:  godot --path . res://tests/SfxOneShotSessionDrainTest.tscn

const SfxEngineClass = preload("res://addons/exmateria_sound/runtime/effect_sfx_engine.gd")
const BANK := "res://assets/audio/sfx_banks/system.feds"

const CASTS := 200         # >> MAX_EVENT_UNITS * EVENT_SESSIONS_PER_UNIT (16)
const SUBS_BETWEEN := 4    # blips must OVERLAP, or the core goes quiet between reaps
# The steady state is arrival_rate x (grace + silence) = (1 per SUBS_BETWEEN) x
# (24 + 120) = ~36 in flight, plus the tail still inside its grace. Measured 52
# with the fix and 200 -- every single cast, nothing ever reaped -- with the
# veto restored, so this bound sits well clear of both. The SUBS_BETWEEN=4
# cadence is load-bearing: at 20 the core goes quiet between reaps, the ordinary
# path drains everything, and this arm CANNOT FAIL. The seeded-defect run is
# what caught that, and it is why the fixture overlaps its blips.
const BOUND := 100

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not (ExMateriaAudioEngine != null and ExMateriaAudioEngine.ready_ok):
		print("[FAIL] SfxOneShotSessionDrainTest: audio engine not ready (SPU GDExtension missing?)")
		get_tree().quit(1)
		return

	_check(SfxEngineClass.ONE_SHOT_SILENCE_SUBS > SfxEngineClass.ONE_SHOT_REAP_GRACE_SUBS,
		"ONE_SHOT_SILENCE_SUBS (%d) is longer than the dispatch grace (%d)" % [
			SfxEngineClass.ONE_SHOT_SILENCE_SUBS, SfxEngineClass.ONE_SHOT_REAP_GRACE_SUBS])

	_test_one_shot_drains_while_core_audible()
	_test_non_one_shot_never_takes_the_silence_path()

	print("\n=== SfxOneShotSessionDrainTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] SfxOneShotSessionDrainTest: ran zero assertions")
		get_tree().quit(1)
	elif _failed > 0:
		print("[FAIL] SfxOneShotSessionDrainTest")
		get_tree().quit(1)
	else:
		print("[PASS] SfxOneShotSessionDrainTest")
		get_tree().quit(0)


func _make_engine():
	var eng = SfxEngineClass.new()
	add_child(eng)
	if not eng.init_as_capture():
		return null
	return eng


func _drive(eng, one_shot: bool) -> Dictionary:
	## Fire CASTS blips with SUBS_BETWEEN subs rendered between each, so the
	## reserved core is continuously audible — the exact condition that made the
	## per-unit veto permanent. Returns the engine's split stats afterwards.
	var audible_seen := false
	for i in range(CASTS):
		if one_shot:
			eng.play_one_shot(BANK, i % 4, (i % 4) + 1)
		else:
			eng.audition(BANK, i % 4, (i % 4) + 1)
		eng.render_subs(SUBS_BETWEEN)
		if int(eng.debug_snapshot().get("total_voices", 0)) > 0:
			audible_seen = true
	# Sample WHILE the core is still hot. This is the discriminating moment: after
	# a long quiet tail the ordinary reap drains everything on its own, so a
	# post-drain session count cannot tell the fix from its absence (it was an arm
	# that could not fail, and the seeded-defect run is what caught that).
	var hot: Dictionary = eng.audition_split_stats()
	var hot_voices := int(eng.debug_snapshot().get("total_voices", 0))
	# Then let the tail drain past the silence window.
	eng.render_subs(SfxEngineClass.ONE_SHOT_SILENCE_SUBS * 3)
	var st: Dictionary = eng.audition_split_stats()
	st["audible_seen"] = audible_seen
	st["hot_sessions"] = int(hot["sessions"])
	st["hot_voices"] = hot_voices
	st["hot_skip_voices"] = int(hot["skip_voices"])
	return st


func _test_one_shot_drains_while_core_audible() -> void:
	var eng = _make_engine()
	if eng == null:
		_fail("one-shot arm: init_as_capture() failed")
		return
	var st := _drive(eng, true)
	# The precondition this whole item is about: the core WAS audible during the
	# run, so the per-unit veto really was in play. Asserted, not assumed — an arm
	# that silently never met its precondition would pass a broken fix.
	_check(bool(st["audible_seen"]),
		"one-shot arm: the reserved core was audible during the run (the veto was live)")
	_check(int(st["n"]) >= CASTS,
		"one-shot arm: all %d casts dispatched (n=%d)" % [CASTS, int(st["n"])])
	_check(int(st["hot_voices"]) > 0,
		"one-shot arm: the core is STILL audible at the sampling point (voices=%d) — the veto is live right now, not merely earlier" % int(st["hot_voices"]))
	_check(int(st["hot_sessions"]) <= BOUND,
		"one-shot arm: sessions bounded at %d after %d casts WHILE the core is audible (got %d)" % [
			BOUND, CASTS, int(st["hot_sessions"])])
	_check(int(st["silence_freed"]) > 0,
		"one-shot arm: the silence path fired (silence_freed=%d)" % int(st["silence_freed"]))
	eng.queue_free()


func _test_non_one_shot_never_takes_the_silence_path() -> void:
	var eng = _make_engine()
	if eng == null:
		_fail("audition arm: init_as_capture() failed")
		return
	var st := _drive(eng, false)
	_check(int(st["n"]) >= CASTS,
		"audition arm: all %d casts dispatched (n=%d)" % [CASTS, int(st["n"])])
	# The relaxation is scoped to one-shot casts. A cast whose caller keeps its
	# token may still be reaped by the ORDINARY path once its core goes quiet —
	# that is unchanged behaviour — but it must never be freed by the silence
	# fallback, which is what this counter reports.
	_check(int(st["silence_freed"]) == 0,
		"audition arm: the silence path never fired for non-one-shot casts (silence_freed=%d)" % int(st["silence_freed"]))
	eng.queue_free()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("[ok]   %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failed += 1
	print("[FAIL] %s" % what)
