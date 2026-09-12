class_name FormationPickIn
extends RefCounted
## The deployment picker's PICK-IN — the ramp the picker runs on itself as the grid comes up
## over the battlefield (#941 follow-up, ADR-0249).
##
## ONE clock, two halves. The dim fades the battlefield back while the units slide in from the
## right, and those are not two animations that happen to start together: the user asked for
## exactly one gesture — [i]"darken the background with some kind of subtractive mesh to darken
## it so it moves into the foreground … especially if the units slide in from the side"[/i] — so
## the background receding and the cast arriving are the same motion seen from two sides. Two
## independent accumulators could drift apart under a frame stall and leave the grid docked over
## an un-dimmed map, which is the one frame the gesture exists to avoid.
##
## [b]Counted in vsyncs, never tweened on `delta`.[/b] ADR-0161, quoted in [FormationScreenIn]:
## [i]"a delta-driven tween would run the ramp at the display's rate and finish the open in a
## third of the time on a 144 Hz panel."[/i] That is not hypothetical here — the map host runs
## UNCAPPED (~1,100 fps measured, which is why the picker's rig budgets its waits in frames and
## not in menu ticks). So this carries the vsync debt itself, exactly as [FormationScreenIn] does.
##
## [b]Not a [UI3Beat], and not an ADR-0084 recipe.[/b] Same reason [FormationScreenIn] is not one
## and ADR-0161 §5 gives: a beat must declare a forward AND a reverse driver or the boot-time
## audit refuses to start, and the pick has no reverse ramp — [method FormationMapHost.end_pick]
## frees the dim and the grid outright (ADR-0162: a screen-covering quad is freed, never parked
## at strength 0). The pick also lives at `State.IDLE` and is not a coordinator `State` at all.
##
## [b]Every value is a PURE function of the tick[/b] ([method dim_fraction_at],
## [method slide_frame_at]), the shape [FormationScreenIn.value_at] and
## `WorldMapTownPage.set_open_frame` both have — so a rig can seek any frame of this gesture
## without running the ones before it, and can assert the SHAPE of a fade that a screenshot
## cannot. That matters more here than usual: an animation that never runs and one that
## completes instantly end at the same final state, so a rig that only reads the rest state
## cannot tell a working ramp from a missing one (#941's own lesson, twice over — see
## `has_roster_grid` and `has_pick_dim`).

## PSX vsync rate — the clock this gesture is counted in, never the display's.
const VSYNC_HZ := 60.0

## Vsyncs between steps. 2 is the quantisation three independent console tables agree on
## ([constant FormationScreenIn.STEP_TICKS]) and it is ALSO this screen's own slide rate:
## `FormationDetailTransition._EQUIP_TICK` is `2.0 / 60.0`, one [SpriteSlideAnimator] frame every
## two vsyncs. The unit slide inherits that rate rather than a new one, so the picker's units
## arrive at the speed the Equip screen's units leave.
const STEP_TICKS := 2

## Dim ramp length in vsyncs. 30 = 0.50 s, borrowed from [constant FormationScreenIn.RAMP_TICKS]
## — `WorldMapTownPage.OPEN_VSYNCS` (`@0x801533B8`, §38.7), a MEASURED length for a `WORLD.BIN`-era
## screen element coming up. Nothing in the repo has observed FFT's own deployment picker opening,
## so this is an analogy; it is an analogy to a measurement and to the right category, which is
## the bar [FormationScreenIn] set for the same borrow.
const DIM_TICKS := 30

## Vsyncs each grid ROW waits before it starts moving. The units arrive as two waves rather than
## one block: FFT's roster screens stagger, and the ROW is the unit of motion this screen already
## uses for a split (`begin_changejob_slide` sends the top row one way and the bottom row the
## other — a FIXED row split, RE29). 4 = two [constant STEP_TICKS] steps, so row 1 is exactly two
## slide-frames behind row 0.
const ROW_STAGGER_TICKS := 4


## The dim's strength as a FRACTION of its authored peak at `tick`, 0..1 — pure, so a rig can seek.
## `iv = STEP_TICKS * floor(t / STEP_TICKS)` steps the value every [constant STEP_TICKS] vsyncs
## rather than every frame, and the ramp lands exactly at full AT `t == DIM_TICKS` rather than one
## step short of it (the off-by-one [FormationScreenIn.value_at] documents).
##
## RISING, where [FormationScreenIn]'s falls: that ramp starts at a black cover and clears to
## reveal a screen, while this one starts at an undimmed battlefield and darkens it. Same shape,
## opposite direction, and the direction is the whole reason this is not a call into that class.
static func dim_fraction_at(tick: int) -> float:
	var iv := (maxi(tick, 0) / STEP_TICKS) * STEP_TICKS
	if iv >= DIM_TICKS:
		return 1.0
	return float(iv) / float(DIM_TICKS)


## The [SpriteSlideAnimator] frame row `row` is on at `tick` — pure. Below its stagger the row has
## not started (frame 0, fully off-screen); above `DIM_TICKS`-independent completion it holds at
## [constant SpriteSlideAnimator.SLIDE_DURATION] (docked). Frames advance one per
## [constant STEP_TICKS] vsyncs, which is `FormationDetailTransition._EQUIP_TICK` exactly.
static func slide_frame_at(tick: int, row: int) -> int:
	var t := maxi(tick, 0) - maxi(row, 0) * ROW_STAGGER_TICKS
	if t <= 0:
		return 0
	return mini(t / STEP_TICKS, SpriteSlideAnimator.SLIDE_DURATION)


## The tick at which EVERY row has docked and the dim has landed — the length of the whole gesture.
## The two halves do not finish together and are not made to: the dim lands at
## [constant DIM_TICKS] = 30 and the last row docks a little after it, so the stage darkens and
## then the cast finishes arriving on it.
static func total_ticks(rows: int) -> int:
	var slide_end := (maxi(rows, 1) - 1) * ROW_STAGGER_TICKS \
		+ SpriteSlideAnimator.SLIDE_DURATION * STEP_TICKS
	return maxi(DIM_TICKS, slide_end)


var _ticks: int = 0
var _tick_debt: float = 0.0
var _rows: int = 1
var _active: bool = true


func _init(rows: int = 1) -> void:
	_rows = maxi(rows, 1)


## Elapsed vsyncs (for a rig, and for a seek).
func ticks() -> int:
	return _ticks


## True while the gesture is still running. Goes false on the tick everything has landed, and the
## host stops pushing — a completed ramp must not keep writing the material every frame.
func is_active() -> bool:
	return _active


## Advance by `delta` seconds' worth of vsyncs, carrying the fraction so the gesture runs at 60 Hz
## on a 144 Hz panel — or, here, at ~1,100 fps. Returns true on the frame the gesture LANDS.
func advance(delta: float) -> bool:
	if not _active:
		return false
	_tick_debt += delta * VSYNC_HZ
	while _tick_debt >= 1.0:
		_tick_debt -= 1.0
		_ticks += 1
	if _ticks >= total_ticks(_rows):
		_ticks = total_ticks(_rows)
		_active = false
		return true
	return false


## Jump straight to `tick` — for a seek rig, or a capture that must settle the gesture.
func seek(tick: int) -> void:
	_ticks = maxi(tick, 0)
	_tick_debt = 0.0
	_active = _ticks < total_ticks(_rows)


## The dim strength to push at the CURRENT tick, scaled to `peak` (the authored tunable).
func dim_strength(peak: float) -> float:
	return peak * dim_fraction_at(_ticks)
