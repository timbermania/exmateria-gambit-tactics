extends RefCounted

## UI's diagnostics, read through the PLATFORM PORT instead of the host's
## `DebugConfig` autoload (#1271, extraction #8 pass 6 step 2).
##
## WHAT THIS SEVERS. `tools/check_ui_autoload_reach.py` scored **8 lines** in five
## UI members gating on `DebugConfig`. An addon cannot ship `project.godot` entries
## (ADR-0262 dec. 6) and every stranger rig declares an EMPTY `[autoload]` block, so
## the identifier is simply undefined the moment `src/ui3/` becomes
## `addons/exmateria_ui/` — a parse-time break, not a degraded feature (ADR-0308).
##
## 🔴 THE FLAGS WERE ALREADY TUNABLES; NOTHING NEW IS INVENTED HERE. All three
## properties this file replaces are `DebugConfig` *facades over `Tune`* —
## `DebugConfig.iteration_debug_enabled` is literally `_dbg_get(false,
## "debug.iteration_debug_enabled")` (`src/debug/DebugConfig.gd:30`), an ADR-0068
## slug with a code default. So UI was reaching a host autoload to read a registry
## the platform port ALREADY exposes, and which UI's own 107 other reaches already
## go through. `addons/exmateria_sprite_rig/install/RigDebug.gd` solved the
## identical problem for the sprite rig at #744 and is the shape copied here.
##
## 🔴 `TunePort`, NOT `Tune`. `Tune` is a host autoload too, so naming it would
## trade one undefined identifier for another. `TunePort` is the port ADR-0175
## dec. 2 built for exactly this, with a defined absent behaviour.
##
## 🔴 TWO POPULATIONS, AND THEY ARE NOT THE SAME KIND OF GATE. Six of the eight
## lines gate NOTHING BUT A `print()`; the other two decide whether a damage number
## spawns at all and whether the charge bubble draws. `iteration()` is named apart
## from `feedback_numbers()` / `feedback_charge_bubble()` for that reason — the
## first is tracing, the second two change what the code DOES, so a project that
## drops the registry gets silence from one and the shipped default from the other.
## This is also WHY pass 6 step 1's debug inversion left all eight behind: step 1
## inverted debug PANEL MOUNTS (ADR-0257), and neither population is a panel mount.
##
## Nothing here is instantiated; the class is a namespace of statics.

const TunePort = ExMateriaPlatform.TunePort

## The slugs. Spelled `debug.*` because that is what `src/debug/DebugConfig.gd`
## already registers them as — a second spelling would be a second registry.
const SLUG_ITERATION := "debug.iteration_debug_enabled"
const SLUG_FEEDBACK_NUMBERS := "debug.feedback_numbers_enabled"
const SLUG_FEEDBACK_CHARGE_BUBBLE := "debug.feedback_charge_bubble_enabled"

## The code defaults, duplicated from `DebugConfig` deliberately: with no `Tune`
## registry present `get_value` returns the fallback the CALLER names, so the addon
## has to carry the values it wants in a project that has neither. `DebugConfig`
## names the same three (`:98`, `:105`, `:116`). The two feedback gates default ON
## because they are shipped behaviour that the F3 panel turns OFF; iteration
## tracing defaults OFF because it is developer output that `--iteration-debug`
## turns ON.
const ITERATION_DEFAULT: bool = false
const FEEDBACK_NUMBERS_DEFAULT: bool = true
const FEEDBACK_CHARGE_BUBBLE_DEFAULT: bool = true


## Bind at class load — the house shape for a static-only tunable owner (ADR-0173,
## `check_tune_owner_self_registration.py` S1), and the one `RigDebug` uses.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Register all three slugs (ADR-0068 R2) so the readers below can PULL-read.
##
## 🔴 THIS IS NOT OPTIONAL BOILERPLATE — WITHOUT IT EVERY READER BELOW ASSERTS.
## `TunePort.get_value` names a fallback, but that fallback answers only when the
## PORT is absent: with the port present it calls `Tune.get_value(slug)` unguarded,
## and that is R5's pull-read, which asserts a prior `bind`. The three slugs used to
## be bound only LAZILY, by `DebugConfig._dbg_get`'s own
## `if not Tune.is_registered(slug): Tune.bind(...)` on its first read of the
## matching property — so a slug was registered only if the HOST had happened to
## read it first, the exact host-order dependency this severance exists to remove.
## `RigDebug`'s docstring records the same failure caught in the same place:
##
##     [Tune] get_value(debug.pose_octant_camera_offset_12bit) before its bind
##
## and a GDScript error returns the TYPE DEFAULT, so an unbound read here would not
## crash — it would quietly answer `false` and silently disable the feedback HUD.
##
## Two binds for one slug is the SUPPORTED shape, not a collision: `Tune._register`
## is first-write-wins and `bind` records each distinct use-site (M3). Whichever of
## this file and `DebugConfig` runs first wins, and they declare the same literals
## deliberately, so the winner does not matter.
static func register_tunables() -> void:
	if Engine.is_editor_hint():
		return
	TunePort.bind(SLUG_ITERATION, ITERATION_DEFAULT)
	TunePort.bind(SLUG_FEEDBACK_NUMBERS, FEEDBACK_NUMBERS_DEFAULT)
	TunePort.bind(SLUG_FEEDBACK_CHARGE_BUBBLE, FEEDBACK_CHARGE_BUBBLE_DEFAULT)


## Verbose UI construction / layout tracing. A PRINT GATE — six call sites, none of
## which changes what the UI does.
static func iteration() -> bool:
	return bool(TunePort.get_value(SLUG_ITERATION, ITERATION_DEFAULT))


## The F3 Feedback HUD panel's damage-number gate. NOT a print gate: when this is
## off `FeedbackHudManager` spawns no `DamageNumber3D` at all.
static func feedback_numbers() -> bool:
	return bool(TunePort.get_value(SLUG_FEEDBACK_NUMBERS, FEEDBACK_NUMBERS_DEFAULT))


## The F3 Feedback HUD panel's charge "speech bubble" gate. Also behaviour: it
## decides which icon cell a charging unit gets, not whether a line is printed.
static func feedback_charge_bubble() -> bool:
	return bool(TunePort.get_value(SLUG_FEEDBACK_CHARGE_BUBBLE, FEEDBACK_CHARGE_BUBBLE_DEFAULT))
