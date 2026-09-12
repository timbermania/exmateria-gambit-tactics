extends Node

## Guard (#1271): `src/ui3/UIDebug.gd` — UI's three diagnostic flags, read through
## `TunePort` instead of the `DebugConfig` autoload.
##
## WHAT NO STATIC GUARD CAN SEE. `check_ui_autoload_reach.py` proves the reaches are
## GONE and `check_tune_owner_self_registration.py` S1 proves `_static_init` calls
## `register_tunables`. Neither can see the failure this file exists for: a slug that
## is READ but never BOUND. `TunePort.get_value` names a fallback, but that fallback
## answers only when the PORT is absent — with the port present it calls
## `Tune.get_value(slug)`, which is ADR-0068 R5's pull-read and asserts a prior
## `bind`. And a GDScript error returns the TYPE DEFAULT, so an unbound read does not
## crash: it quietly answers `false` and silently disables the feedback HUD.
##
## So arm 2 asserts REGISTRATION, not just the value. It is the only arm that can
## tell "bound by `UIDebug` at class load" from "bound by `DebugConfig` because the
## host happened to read the property first" — the host-order dependency the whole
## severance exists to remove.
##
## 🔴 THE ABSENT ARM SEEDS A NON-DEFAULT FIRST. Two of the three flags default to the
## value they already hold at boot, so asserting the default after the registry goes
## away would be VACUOUS — it would pass whether the port answered the fallback,
## answered a cached value, or answered nothing. Each arm 3 assertion is preceded by
## a seed that moves the value off its default while still bound (#1263's lesson).
##
## The absent case is manufactured by renaming the `Tune` autoload node and dropping
## the port's resolution cache, the way `TunePortTest.gd` does — truthful, because
## `_resolve()` is a `get_node_or_null` against that name and a consuming project
## without the `[autoload]` line differs in exactly that lookup failing.

const UIDebug = preload("res://src/ui3/UIDebug.gd")
const TunePort = ExMateriaPlatform.TunePort

var _passed := 0
var _failed := 0


func _ready() -> void:
	# 🔴 ORDER IS LOAD-BEARING. Arm 2 must run BEFORE anything touches a
	# `DebugConfig` property: `_dbg_get` binds lazily on first read, so a single
	# earlier read makes the slug registered no matter what `UIDebug` did, and the
	# arm silently stops being able to tell the two apart. Arm 1 reads all three.
	_test_every_slug_read_is_a_slug_bound()
	_test_reads_agree_with_the_autoload()
	_test_absent_registry_answers_the_shipped_defaults()

	print("\n=== UIDebugSlugTest: %d passed, %d failed ===" % [_passed, _failed])
	print("[PASS] UIDebugSlugTest" if _failed == 0 else "[FAIL] UIDebugSlugTest")
	get_tree().quit(1 if _failed > 0 else 0)


## ONE REGISTRY, NOT TWO. `UIDebug` and `DebugConfig` name the same slugs and the
## same literals on purpose; if they ever disagree, the F3 panel and the UI are
## reading different values and the panel silently stops controlling the UI.
func _test_reads_agree_with_the_autoload() -> void:
	_eq(UIDebug.iteration(), DebugConfig.iteration_debug_enabled,
		"iteration() agrees with DebugConfig.iteration_debug_enabled")
	_eq(UIDebug.feedback_numbers(), DebugConfig.feedback_numbers_enabled,
		"feedback_numbers() agrees with DebugConfig.feedback_numbers_enabled")
	_eq(UIDebug.feedback_charge_bubble(), DebugConfig.feedback_charge_bubble_enabled,
		"feedback_charge_bubble() agrees with DebugConfig.feedback_charge_bubble_enabled")

	# And they TRACK: a write through the panel's setter must move UIDebug's read.
	# Without this the arm above passes for two constants that happen to match.
	var boot: bool = DebugConfig.feedback_numbers_enabled
	DebugConfig.feedback_numbers_enabled = not boot
	_eq(UIDebug.feedback_numbers(), not boot,
		"a write through DebugConfig moves UIDebug's read — one registry, not two")
	DebugConfig.feedback_numbers_enabled = boot


## ARM 2 — every slug a reader names is a slug `register_tunables` bound.
## Derived from the readers' own constants, so a fourth flag added without a
## matching `bind` reds here instead of erroring at runtime into a type default.
func _test_every_slug_read_is_a_slug_bound() -> void:
	for slug in [UIDebug.SLUG_ITERATION, UIDebug.SLUG_FEEDBACK_NUMBERS,
			UIDebug.SLUG_FEEDBACK_CHARGE_BUBBLE]:
		_eq(Tune.is_registered(slug), true,
			"`%s` is registered — the read is R5-legal without DebugConfig having run" % slug)


## ARM 3 — the state the whole severance is for, and the one no scene here boots in.
func _test_absent_registry_answers_the_shipped_defaults() -> void:
	var node := get_tree().root.get_node_or_null(^"Tune")
	if node == null:
		_fail("the Tune autoload is not in this tree — the absent arm cannot run")
		return

	# Seed all three OFF their defaults, so the assertions below can fail.
	var boot_it: bool = DebugConfig.iteration_debug_enabled
	var boot_fn: bool = DebugConfig.feedback_numbers_enabled
	var boot_cb: bool = DebugConfig.feedback_charge_bubble_enabled
	DebugConfig.iteration_debug_enabled = not UIDebug.ITERATION_DEFAULT
	DebugConfig.feedback_numbers_enabled = not UIDebug.FEEDBACK_NUMBERS_DEFAULT
	DebugConfig.feedback_charge_bubble_enabled = not UIDebug.FEEDBACK_CHARGE_BUBBLE_DEFAULT
	_eq(UIDebug.iteration(), not UIDebug.ITERATION_DEFAULT,
		"the seed moved iteration() off the value the absent arm asserts")
	_eq(UIDebug.feedback_numbers(), not UIDebug.FEEDBACK_NUMBERS_DEFAULT,
		"the seed moved feedback_numbers() off the value the absent arm asserts")
	_eq(UIDebug.feedback_charge_bubble(), not UIDebug.FEEDBACK_CHARGE_BUBBLE_DEFAULT,
		"the seed moved feedback_charge_bubble() off the value the absent arm asserts")

	node.name = "Tune_absent_probe"
	TunePort._forget_port()

	_eq(UIDebug.iteration(), UIDebug.ITERATION_DEFAULT,
		"absent: iteration() answers the shipped default, not the seeded value")
	_eq(UIDebug.feedback_numbers(), UIDebug.FEEDBACK_NUMBERS_DEFAULT,
		"absent: feedback_numbers() answers ON — the HUD ships enabled")
	_eq(UIDebug.feedback_charge_bubble(), UIDebug.FEEDBACK_CHARGE_BUBBLE_DEFAULT,
		"absent: feedback_charge_bubble() answers ON")

	node.name = "Tune"
	TunePort._forget_port()
	DebugConfig.iteration_debug_enabled = boot_it
	DebugConfig.feedback_numbers_enabled = boot_fn
	DebugConfig.feedback_charge_bubble_enabled = boot_cb
	_eq(UIDebug.feedback_numbers(), boot_fn,
		"the registry came back — a failed lookup is never cached as a negative")


func _eq(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		_passed += 1
		print("  [x] %s" % what)
	else:
		_failed += 1
		print("  [ ] %s (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("  [ ] %s" % what)
