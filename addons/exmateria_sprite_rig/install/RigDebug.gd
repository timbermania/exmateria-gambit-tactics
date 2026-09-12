extends RefCounted

## The rig's diagnostics, read through the PLATFORM PORT instead of the host's
## `Debug` system (#744, 2026-09-01).
##
## WHAT THIS SEVERS. `check_addon_portability.py` arm 1 scored **21 lines** in this
## addon reaching `Debug` — `DebugConfig` 17 and `GameLogger` 4 — which is 21 of
## ADR-0215's P3a 27. Every one was a diagnostic: sixteen gate a `print`, one gates
## a detection heuristic, one reads a pose offset, four log. None is rig behaviour
## the host has to supply, and an addon that will not parse in a project without a
## `DebugConfig` autoload fails goal #5 for four `print` gates.
##
## 🔴 THE FLAGS WERE ALREADY TUNABLES; NOTHING NEW IS INVENTED HERE. Three of the
## five properties this file replaces are `DebugConfig` *facades over `Tune`* —
## `DebugConfig.iteration_debug_enabled` is literally `_dbg_get(false,
## "debug.iteration_debug_enabled")`, an ADR-0068 slug with a code default. So the
## rig was reaching a host autoload to read a registry the platform port already
## exposes. Reading the slug directly is the same value from the same registry
## with one fewer dependency, and `addons/exmateria_battlefield/terrain/SkirtConfig.gd`
## is the precedent for the shape. The other two (`evtchr_row_detect_enabled`,
## `pose_octant_camera_offset_12bit`) were plain `var`s; this pass makes them
## slugs too, so `DebugConfig` and this file cannot disagree about a value.
##
## 🔴 `TunePort`, NOT `Tune`. `Tune` is a host autoload and naming it is
## standalone-parse debt (`check_addon_portability` arm 2) even though arm 1
## cannot see it — `platform` is a tier, not a system. `TunePort` is the port
## ADR-0175 dec. 2 built for exactly this, with a defined absent behaviour, and
## ADR-0217 P3b books the kernel and the port as the CONFORMANT residual. Going
## through the port keeps this severance out of P3b's debt as well as out of P3a's.
##
## Nothing here is instantiated; the class is a namespace of statics.

const TunePort = ExMateriaPlatform.TunePort

## The slugs. Spelled `debug.*` because that is what `src/debug/DebugConfig.gd`
## already registers them as — a second spelling would be a second registry.
const SLUG_ITERATION := "debug.iteration_debug_enabled"
const SLUG_ACTION := "debug.action_debug_enabled"
const SLUG_TRANSITION := "debug.transition_debug_enabled"
const SLUG_EVTCHR_ROW_DETECT := "debug.evtchr_row_detect_enabled"
const SLUG_POSE_OCTANT_OFFSET := "debug.pose_octant_camera_offset_12bit"

## The pose-octant camera offset's code default, 12-bit. Duplicated from
## `DebugConfig` deliberately: with no `Tune` registry present `get_value` returns
## the fallback the CALLER names, so the addon has to carry the number it wants in
## a project that has neither. `DebugConfig` names the same one.
const POSE_OCTANT_OFFSET_DEFAULT: int = 0x400


## Bind at class load — the house shape for a static-only tunable owner
## (ADR-0173, `check_tune_owner_self_registration.py` S1), and the same one
## `addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd` already uses two
## directories over.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Register all five slugs (ADR-0068 R2) so the readers below can PULL-read.
##
## 🔴 THIS IS NOT OPTIONAL BOILERPLATE — WITHOUT IT EVERY READER BELOW ASSERTS.
## `get_value` is R5's pull-read and it asserts a prior `bind`; the five slugs
## used to be bound only LAZILY, by `src/debug/DebugConfig.gd`'s own `_dbg_get`
## (`if not Tune.is_registered(slug): Tune.bind(...)`) on its first read of the
## matching property. So a slug was registered only if the HOST had happened to
## read it first — the exact host-order dependency this severance exists to
## remove. Booting `res://tests/UnitDisplayPaintGoldenTest.tscn` printed
##
##     [Tune] get_value(debug.pose_octant_camera_offset_12bit) before its bind
##     Invalid call. Nonexistent 'int' constructor.
##
## on repeat — the second line being `int(null)` after the assert. Binding here
## is what makes the read order-independent, and it is what an owner does.
##
## Two binds for one slug is the SUPPORTED shape, not a collision: `Tune._register`
## is first-write-wins and `bind` records each distinct use-site (M3). Whichever of
## this file and `DebugConfig` runs first wins, and they declare the same literals
## deliberately, so the winner does not matter. The offset binds as a FLOAT because
## `DebugConfig` routes it through `_dbg_get_num`/`_dbg_set_num`; a rival int
## registration would make the two disagree about the slug's type.
static func register_tunables() -> void:
	if Engine.is_editor_hint():
		return
	TunePort.bind(SLUG_ITERATION, false)
	TunePort.bind(SLUG_ACTION, false)
	TunePort.bind(SLUG_TRANSITION, false)
	TunePort.bind(SLUG_EVTCHR_ROW_DETECT, false)
	TunePort.bind(SLUG_POSE_OCTANT_OFFSET, float(POSE_OCTANT_OFFSET_DEFAULT))


## Verbose per-frame animation iteration tracing.
static func iteration() -> bool:
	return bool(TunePort.get_value(SLUG_ITERATION, false))


## Action / weapon / reaction tracing.
static func action() -> bool:
	return bool(TunePort.get_value(SLUG_ACTION, false))


## Animation-state transition tracing.
static func transition() -> bool:
	return bool(TunePort.get_value(SLUG_TRANSITION, false))


## The EVTCHR palette-row detection heuristic. Not a print gate — this one changes
## what the layer manager DOES, which is why it is named apart from the three above.
static func evtchr_row_detect() -> bool:
	return bool(TunePort.get_value(SLUG_EVTCHR_ROW_DETECT, false))


## The F3-panel pose-octant camera offset, 12-bit.
static func pose_octant_offset_12bit() -> int:
	return int(TunePort.get_value(SLUG_POSE_OCTANT_OFFSET, POSE_OCTANT_OFFSET_DEFAULT))


## An animation-category debug line.
##
## 🔴 THE FOUR CALLS THIS REPLACES COULD NOT EMIT. They were
## `GameLogger.debug(Category.ANIMATION, …)`, and `GameLogger.gd:31` sets
## `Category.ANIMATION: Level.ERROR` as its default while `_apply_debug_config()`
## (`:48-56`) only ever raises CAMERA and MAP to `Level.DEBUG`. Nothing in the tree
## raises ANIMATION, so `_should_log` rejected all four unconditionally. They were a
## host dependency that bought nothing. Gated on `iteration()` they can actually
## fire, which is strictly more than they did.
static func log_animation(message: String) -> void:
	if not iteration():
		return
	print("[sprite-rig] ", message)
