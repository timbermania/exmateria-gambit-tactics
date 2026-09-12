extends RefCounted

## One clock per unit (ADR-0020). The single time seam between the host's pump
## (CombatLoop tick / Unit._process delta) and a unit's animation playbacks, and
## the SOLE owner of time: the delta→frames accumulator, the tick-vs-delta mode,
## and the walk-speed multiplier. The six AnimationPlaybacks it drives are pure
## frame counters (they no longer own any of that).
##
## It pumps two sets — the normal set (BODY / WEP1 / EFF1) and the React set —
## so callers collapse their six-way pump into one clock call. The normal set
## scales with the speed multiplier; the React set advances at its authored
## cadence (ADR-0025, display-only), so each has its own accumulator. Because one
## multiplier now scales the whole normal set together, the ADR-0020 drift bug
## (BODY outpacing its un-multiplied WEAPON/EFFECT) is fixed here.

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const AnimationPlayback = preload("res://addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd")
const PlaybackSet = preload("res://addons/exmateria_sprite_rig/sequence/PlaybackSet.gd")

const FRAME_DURATION: float = AnimationPlayback.FRAME_DURATION

# The two PlaybackSets this clock pumps (ADR-0025): the normal set and the
# React set. Each is a {BODY, WEP1, EFF1} triple.
var _normal: PlaybackSet
var _react: PlaybackSet

# Delta-mode accumulators (seconds), one per set — the React set is not scaled.
var _accum_normal: float = 0.0
var _accum_react: float = 0.0

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — who pumps a clock is a VALUE SET the hosts
## that own the pumps have to say, so it is the kernel's; this class keeps its name
## and stays the sole owner of time. `ClockOwner`, not the bare word, which names no
## subject at all.
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

## Who owns this clock — the ONE thing that decides which pump advances it
## (ADR-0083). Exactly one owner per unit, so a unit can never ride two clocks:
##   SELF     — delta-driven; `Unit._process` pumps `tick(delta)` (free-roam smoothness).
##   SCENARIO — the `ScenarioVM` body pump owns it (openers, cutscenes, deployment breathe).
##   COMBAT   — the `CombatLoop` tick owns it (live combat, GPUArena).
## The VM/CombatLoop pumps each drive ONLY the units they own; the scenario→battle
## transition is a single SCENARIO→COMBAT handoff (`NavigatorMain._go_live`).
var owner: ClockOwner = ClockOwner.SELF

## Host-pumped vs delta-pumped — the derived predicate `owner != SELF` (ADR-0083
## folded the old standalone flag into `owner` so the two can't drift). When true,
## `tick(delta)` is a no-op and `advance_frame()` drives frames instead (tick-locked
## to whichever host owns the clock). Read-only: assign `owner`, not this.
var tick_based: bool:
	get: return owner != ClockOwner.SELF

## Walk-speed scaling for delta mode (was `type1_playback.playback_speed_multiplier`,
## BODY-only — the drift-bug source). Now the clock's single multiplier scales the
## whole normal set together.
var speed_multiplier: float = 1.0


func _init(normal_set: PlaybackSet, react_set: PlaybackSet) -> void:
	_normal = normal_set
	_react = react_set


## Delta-mode pump (Unit._process). Accumulates real time and steps each set one
## frame at a time; the normal set is scaled by `speed_multiplier`, the React set
## runs unscaled. No-op in tick mode (advance_frame drives instead).
func tick(delta: float) -> void:
	if tick_based:
		return
	_accum_normal += delta * speed_multiplier
	while _accum_normal >= FRAME_DURATION:
		_accum_normal -= FRAME_DURATION
		_normal.advance_frame()
	_accum_react += delta
	while _accum_react >= FRAME_DURATION:
		_accum_react -= FRAME_DURATION
		_react.advance_frame()


## Tick-mode pump (CombatLoop). Advances the normal set `normal_reps` times and
## the React set `react_reps` times — the two cadences the host distinguishes:
## the normal set scales with the unit's gameplay anim speed, while React
## normally advances once per IRQ (authored cadence, ADR-0025). The post-victory
## freeze-march advances both at the same repeat count, so it passes them equal.
func advance_frame(normal_reps: int = 1, react_reps: int = 1) -> void:
	for _r in range(normal_reps):
		_normal.advance_frame()
	for _r in range(react_reps):
		_react.advance_frame()
