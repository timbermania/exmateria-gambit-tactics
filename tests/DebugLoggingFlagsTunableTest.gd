extends Node
## Guard: the plain-var, panel-exposed DebugConfig debug flags are Tune tunables
## (ADR-0068 decision 10 — debug-only preferences bind like anything else). Each
## property coalesces a committed `debug.*` override over its code default (false),
## and an assignment routes the write through Tune — so a scrub in the F3 panel /
## generated dashboard persists across scene reloads and the flag is enumerable.
## DebugConfig is the OWNER; consumers read `DebugConfig.<flag>` live, so no fan-out
## (decision 12). Before the migration these were plain stored bools that ignored
## Tune, which reds this guard.
##
##
## #1218 ADDED A SECOND ARM: `addons/exmateria_effects/install/EffectsDebug.gd`.
## `Effects` stopped reading `DebugConfig` and now PULL-reads the same four slugs
## through `ExMateriaPlatform.TunePort`, so there are two owners of one registry
## and nothing checked that they agree. A typo in one of `EffectsDebug`'s four
## string literals binds a NEW slug rather than failing: `Tune.bind` registers
## whatever it is handed, the reader returns `false` forever, and the addon's
## verbosity silently detaches from the panel toggle that scrubs it. The arm below
## is SET-EQUAL in both directions — `EffectsDebug.slugs()` against the four
## `DebugConfig` properties — so a renamed slug reds AND a slug dropped from the
## expected set while still bound reds. It lives in this file rather than a new one
## because it shares this file's whole setup (Tune + DebugConfig) and the charter
## prices a test at one ~2.3 s Godot boot.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/DebugLoggingFlagsTunableTest.tscn

# Every plain-var flag migrated in this batch, paired with its code default. The
# LoggingDebugPanel toggles the first 12; show_depth_center + perf_spike_log_enabled
# are the other plain-var panel toggles (UnitShaderDebugPanel / PerfDebugPanel).
# `audio_monitor_enabled` LEFT this set at #408 — a system logs itself (ADR-0140 dec. 5),
# so the gate is ExMateriaEffectSfx's static var on the `audio.monitor_enabled` slug.
# `land_skirt_debug_enabled` LEFT at #500 for the same reason — the gate is now
# SkirtGeometryGenerator's static var on `skirt.land_debug`.
const FLAGS := {
	"map_debug_enabled": false,
	"iteration_debug_enabled": false,
	"gpu_debug_enabled": false,
	"action_debug_enabled": false,
	"camera_debug_enabled": false,
	"screen_debug_enabled": false,
	"palette_debug_enabled": false,
	"particle_debug_enabled": false,
	"timeline_debug_enabled": false,
	"emitter_debug_enabled": false,
	"transition_debug_enabled": false,
	"reaction_debug_enabled": false,
	"show_depth_center": false,
	"perf_spike_log_enabled": true,
}

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const TunePort = ExMateriaPlatform.TunePort

# The four flags `EffectsDebug` owns on the addon side, spelled as the
# `DebugConfig` PROPERTY name. `_test_effects_debug_slugs` derives the slug as
# "debug.%s" and compares that set against `EffectsDebug.slugs()`, so this list
# and the addon's four literals are the two halves of the set equality. Every one
# is also a key of FLAGS above — the third arm asserts that, which is what keeps
# the two lists in this file from drifting apart.
const EFFECTS_DEBUG_FLAGS := {
	"particle_debug_enabled": "particle",
	"iteration_debug_enabled": "iteration",
	"timeline_debug_enabled": "timeline",
	"camera_debug_enabled": "camera",
}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	for flag: String in FLAGS:
		_test_flag(flag, FLAGS[flag])
	_test_effects_debug_slugs()

	print("\n=== DebugLoggingFlagsTunableTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DebugLoggingFlagsTunableTest")
		get_tree().quit(1)
	else:
		print("[PASS] DebugLoggingFlagsTunableTest")
		get_tree().quit(0)


func _test_flag(flag: String, default_value: bool) -> void:
	var slug := "debug.%s" % flag
	Tune.clear(slug)  # start from the code default (shared autoload)

	# No override -> the property returns the code default.
	_check("%s: default is %s" % [flag, default_value], DebugConfig.get(flag), default_value)

	# A committed override coalesces through the property (the whole point).
	Tune.set_value(slug, not default_value)
	_check("%s: override coalesces through the property" % flag,
		DebugConfig.get(flag), not default_value)
	Tune.clear(slug)

	# An assignment routes the write through Tune (write-through, not a private bool).
	DebugConfig.set(flag, not default_value)
	_check("%s: assignment writes through to Tune" % flag,
		bool(Tune.bind(slug, default_value)), not default_value)
	Tune.clear(slug)  # restore shared autoload state


## #1218's guard: `EffectsDebug` and `DebugConfig` name the SAME four slugs, and
## a write through either is read by the other.
##
## 🔴 THREE ARMS, AND THE FIRST TWO ARE THE TWO DIRECTIONS OF ONE SET EQUALITY.
## Set-equal only in one direction is not a guard: a typo adds a slug the expected
## set does not have (arm A), and dropping an entry from the expected set while the
## addon still binds it leaves the addon's fourth flag unchecked (arm B). Arm C is
## the round trip, and it is the one that proves the STRING is right rather than
## merely well-formed — a slug can be in both lists and still be a slug the host
## panel does not scrub, if both lists are wrong together. Writing through
## `DebugConfig` and reading through `TunePort` can only agree if it is one slug.
func _test_effects_debug_slugs() -> void:
	var want: Array[String] = []
	for flag: String in EFFECTS_DEBUG_FLAGS:
		want.append("debug.%s" % flag)
		# Arm C's premise: every flag this arm names is one the file above already
		# scores as a DebugConfig-owned tunable.
		_check("EffectsDebug flag `%s` is a DebugConfig tunable" % flag,
			FLAGS.has(flag), true)
	want.sort()

	var got := EffectsDebug.slugs()
	got.sort()

	# Arm A — the addon binds no slug the expected set does not name (a typo).
	for slug: String in got:
		_check("EffectsDebug binds `%s`, which is expected" % slug, want.has(slug), true)
	# Arm B — the expected set names no slug the addon fails to bind.
	for slug: String in want:
		_check("EffectsDebug binds the expected `%s`" % slug, got.has(slug), true)
	_check("EffectsDebug owns exactly the expected slug set", got, want)

	# 🔴 `_static_init()` RAN AT THIS SCRIPT'S PARSE TIME, WHEN `/root` HAD NO
	# CHILDREN, so `TunePort` QUEUED all four declarations instead of delivering
	# them (see `_deferred`'s header — 78 slugs across 8 owners was the measured
	# cost of dropping them). The port flushes on its first successful resolve; one
	# idempotent re-registration from inside `_ready` is that resolve. Without this
	# line `is_registered` below reads false for a slug that is correctly declared,
	# which would make this arm score the boot order rather than the slug set.
	EffectsDebug.register_tunables()
	_check("EffectsDebug's deferred declarations have drained",
		TunePort.deferred_count(), 0)

	# Arm C — one registry, two spellings: a write through the host property is
	# read by the addon's static.
	for flag: String in EFFECTS_DEBUG_FLAGS:
		var slug := "debug.%s" % flag
		var reader: String = EFFECTS_DEBUG_FLAGS[flag]
		Tune.clear(slug)
		_check("EffectsDebug.%s(): registered before the pull-read" % reader,
			Tune.is_registered(slug), true)
		_check("EffectsDebug.%s(): code default is false" % reader,
			_read(reader), false)
		DebugConfig.set(flag, true)
		_check("EffectsDebug.%s(): reads the host property's write" % reader,
			_read(reader), true)
		Tune.clear(slug)  # restore shared autoload state
		_check("EffectsDebug.%s(): follows the slug back to the default" % reader,
			_read(reader), false)


## Call one of `EffectsDebug`'s four readers by name.
##
## 🔴 NOT `EffectsDebug.call(reader)`. `EffectsDebug` is a SCRIPT CLASS here, not an
## instance, and `Object.call` is an instance method — so the reflective spelling is a
## PARSE ERROR, *"Cannot call non-static function `call()` on the class … directly.
## Make an instance instead"*, which takes the whole file down and would have shown up
## as this test silently VANISHING from the suite rather than as a failure. `match` is
## the spelling that works, and it also means a reader renamed in the addon breaks HERE
## instead of at runtime.
func _read(reader: String) -> bool:
	match reader:
		"particle": return EffectsDebug.particle()
		"iteration": return EffectsDebug.iteration()
		"timeline": return EffectsDebug.timeline()
		"camera": return EffectsDebug.camera()
	push_error("unknown EffectsDebug reader: %s" % reader)
	return false


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
