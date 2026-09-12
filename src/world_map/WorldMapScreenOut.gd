class_name WorldMapScreenOut
extends RefCounted
## The world map's SCREEN-OUT — the ramp it runs on itself as it LEAVES.
##
## [b]The arithmetic is measured; firing it here is a PRODUCT choice.[/b] Keep those two
## apart, because only the first is a fidelity claim.
##
## MEASURED (ADR-0174 §2): the cue at [code]FUN_80069400(kind, len)[/code] is one routine
## with TWO arms, and bit 1 of `kind` is the direction. The per-frame tick at
## [code]0x800694A8[/code] computes the descriptor at [code]0x800D0ADC..DE[/code] as:
## [codeblock]
##   out  (kind & 2)     counter*256/len + 32,   ceil 0xFF   <-- this file
##   in  !(kind & 2)     0xC0 - counter*256/len, floor 0     <-- WorldMapScreenIn
## [/codeblock]
## So the console's fade-out is not the fade-in reversed: it starts at [b]32[/b] and
## saturates at [b]255[/b], where the in-arm starts at 192 and saturates at 0. Reversing
## the in-arm would have started at 0 and ended at 192 — level 24 of 31, which is not
## black. That difference is the whole reason this file restates the formula instead of
## running [WorldMapScreenIn] backwards.
##
## NOT MEASURED, and this is the honest half: [b]nothing establishes that the console fires
## an out-cue when the map hands off to a battle.[/b] ADR-0174 read the map's ENTRY call
## site ([code]0x8006731C[/code], `FUN_80069400(0, 0x10)` — direction in, len 16) and
## nothing else about the exit. The `&2` guard means firing the direction you are already
## in is a no-op, so an unconditional exit fire would be silent on a screen that never
## faded in — but that is an argument about harmlessness, not evidence of a call site.
##
## Which is why the behaviour sits behind [member SCREEN_OUT_DEFAULT] and its
## `world_map.screen_out` tunable rather than being switched on unconditionally: the port
## wants the transition to stop cutting to black in one frame, and the ROM's own out-curve
## is the right shape to do it with, but the claim "FFT does this here" is NOT being made.
## If someone reads the exit path and finds the call site, this docstring is what they
## should come and delete.
##
## `len` is [constant RAMP_TICKS] = 16 on the same reading that gave the in-arm its 16 —
## twenty of the twenty-two readable WLDCORE call sites pass `0x10`.

## [b]Whether the map fades out at all.[/b] ADR-0068 tunable `world_map.screen_out` — a
## `static var` and not a `const`, because the rule is that the value has ONE home and the
## F3 panel is a view onto it.
##
## The home is HERE and not on [WorldMapScene] for a reason the guard states better than a
## comment could: `WorldMapScene` is a declared root's assembler, so `tools/check_root_set.py`
## check 4 requires that nothing CALLS it — and a panel naming a const on it is a call. It
## reds the moment you try. The knob belongs with the mechanism regardless; this file is what
## the tunable turns off.
##
## Default ON, and a tunable rather than a hardcoded `true` because the CURVE is measured and
## the CALL SITE is not — see this class's header.
static var SCREEN_OUT_DEFAULT := true
const SCREEN_OUT_SLUG := "world_map.screen_out"


## Register to the static-var home ONCE at class load (ADR-0068 R2), from this class's own
## `_static_init` and from nowhere else. `_static_init` fires once per class load per process
## and cannot re-fire, so a test that calls `Tune.reset()` and then spawns this owner finds an
## empty registry — that test wants `Tune.reset_overrides()`, which leaves every declaration
## standing. Wanting a way back from the total clear is what used to force `Tune` to hold a
## list of its owners' script paths; ADR-0173 fixed the clear instead and deleted the list.
## `tools/check_tune_owner_self_registration.py` is what keeps this file self-registering.
static func register_tunables() -> void:
	Tune.bind(SCREEN_OUT_SLUG, SCREEN_OUT_DEFAULT)


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Frames the ramp runs. The console's `len`, written once at `0x800D0ACC`.
const RAMP_TICKS := 16

## Where the subtractive quad starts, 0..255 — the `+ 32` offset in the out-arm's tick.
## Not 0: the console's fade-out opens ALREADY slightly down, which is why a cut to a
## fade-from-nothing looks wrong beside it.
const START_VALUE := 32

## The console's numerator: the descriptor ramps `START_VALUE + counter*RAMP_SCALE/len`.
const RAMP_SCALE := 256

## The out-arm's ceiling — `0xFF`, where the in-arm floors at 0.
const CEIL_VALUE := 255

## PSX framebuffer channel step, as [WorldMapScreenIn] — the world map composites in the
## GPU's own 5-bit channels and every quad is baked as `8 * v` for a level v in 0..31.
## Here it is NOT a no-op: the ceiling 255 bakes to 248, which is level 31, full black.
const LEVEL_STEP := 8.0

## [b]The deadlock bound, in frames that made NO PROGRESS.[/b] All THREE waiters on this
## ramp count with THIS — `WorldMapScene._run_screen_out`, `WorldMapScreenOutTest`, and
## `WorldMapMountTest`, the last of which kept a `RAMP_TICKS * 12` of its own for a commit
## after the other two were converted — so the bound has one spelling and one place to argue
## with. If a fourth waiter appears, it reads this constant and
## `WorldMapScene.screen_out_ticks()`; it does not invent a frame count.
##
## The unit is the whole point. A waiter resumes once per RENDERED frame; the ramp advances
## once per VSYNC, at `WorldMapScene.VSYNC_HZ` (60), so a display at R Hz spends `RAMP_TICKS
## * R/60` frames on a perfectly healthy fade. A flat `RAMP_TICKS * k` therefore has a
## margin that SHRINKS as the machine gets faster and inverts around 480 fps, where the
## guard starts firing on success and cutting the fade short. Frames-without-progress has no
## such crossover: at any refresh a live ramp advances at least once every `ceil(R/60)`
## frames, so this only expires when nothing is ticking the ramp at all — which is the one
## thing it is here to catch.
##
## 240 is four seconds at 60 Hz and ~1.7 s at the 143.9 Hz measured on this machine. Large
## on purpose: a hang reads as "nothing happened" rather than as an error, so the cost of
## expiring late is a slow exit and the cost of expiring early is a bug that only appears on
## someone else's monitor.
const STALL_FRAMES := 240

var _ticks: int = 0
var _active: bool = true


## The pushed value at [param tick], 0..255, quantised to a 5-bit level.
##
## Mirrors the tick at [code]0x800694A8[/code], fade-OUT arm: `counter*256/len + 32`,
## ceiled at 0xFF, in INTEGER arithmetic — the console divides with MIPS `div`, so the
## fencepost is the console's and not a rounding choice of ours.
static func value_at(tick: int) -> float:
	var t := clampi(tick, 0, RAMP_TICKS)
	var raw := START_VALUE + (t * RAMP_SCALE) / RAMP_TICKS
	if raw > CEIL_VALUE:
		raw = CEIL_VALUE
	# Bake to the framebuffer's own levels BEFORE the blend, so the frame computes
	# `e(B - F)` and not `e(B) - e(F)` — the same ±1 error psx_expand_555 closes for the
	# in-arm. 255 bakes DOWN to 248 here, which is level 31 and is full black in 5 bits.
	return floor(float(raw) / LEVEL_STEP) * LEVEL_STEP


## The tick the PICTURE lands on — the first frame at the ceiling. Derived, not a constant:
## `32 + t*256/16 >= 255` first holds at t == 14, two frames before [constant RAMP_TICKS].
## The in-arm's equivalent is 12 of 16; both land before the LATCH does, which is the shape
## ADR-0174 measured rather than a coincidence. Exposed so nothing hardcodes 14.
static func land_tick() -> int:
	var top := value_at(RAMP_TICKS)
	for t in range(0, RAMP_TICKS + 1):
		if value_at(t) >= top:
			return t
	return RAMP_TICKS


## Advance one vsync. No-op once landed. Driven from `WorldMapScene.advance`, on the same
## clock as the bob and the in-arm — never from a [Tween], for the reason ADR-0161 gives:
## a delta-driven ramp runs at the display's refresh rate, which measured 143.9 Hz here.
func tick() -> void:
	if not _active:
		return
	_ticks += 1
	if _ticks >= RAMP_TICKS:
		_ticks = RAMP_TICKS
		_active = false


## Jump straight to [param tick] without running the frames before it — the contact-sheet
## rig's entry point, and the seam a test drives instead of spending 16 real frames.
func seek(tick: int) -> void:
	_ticks = clampi(tick, 0, RAMP_TICKS)
	_active = _ticks < RAMP_TICKS


## Snap to landed — fully black, ramp finished.
func settle() -> void:
	seek(RAMP_TICKS)


## The value the quad should show this frame.
func current_value() -> float:
	return value_at(_ticks)


## True while the ramp is still in flight.
func is_active() -> bool:
	return _active


## The tick the ramp is on, for a test or a contact sheet that wants to label a frame.
func ticks() -> int:
	return _ticks
