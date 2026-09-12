class_name WorldMapScreenIn
extends RefCounted
## The world map's SCREEN-IN — the ramp the screen runs on ITSELF as it comes up.
##
## A [b]screen-in[/b] (CONTEXT.md) is the counterpart to a [b]scene-out[/b]: a scene-out
## is authored per-scenario in the chunk ([code]{3E}[/code] + [code]{60}[/code]), while a
## screen-in is unconditional and belongs to the screen's own code and clock. §24.1
## measured the world map's as WLDCORE's own BSS — descriptors at [code]0x800D0AD0[/code]
## / [code]0x800D0AE0[/code], enable at [code]0x800D0AB8[/code], emitted from
## [code]FUN_80069810[/code] inside WLDCORE's render loop. So the map fades ITSELF in;
## the navigator does not cover it. ADR-0161.
##
## [b]The numbers below are MEASURED (ADR-0174), and they replace ADR-0161's mirror.[/b]
## §24.1 could not read the ramp because every capture the repo holds is settled — but the
## ramp is not stored, it is COMPUTED, and both of its inputs are literals in the
## instruction stream. `FUN_80069400(kind, len)` @[code]0x80069400[/code] (WLDCORE) arms
## the block: it writes [code]kind|1[/code] to the enable at [code]0x800D0AB8[/code], zeroes
## the counter at [code]0x800D0AC8[/code], and stores [param len] to [code]0x800D0ACC[/code].
## The per-frame tick @[code]0x800694A8[/code] then does the arithmetic below.
##
## [b]len is a FRAME COUNT and it is 16.[/b] Read at [code]0x8006731C[/code] — the fourth
## statement of §32.4's SCUS-called world-map entry [code]0x800672F8[/code], which fires
## [code]FUN_80069400(0, 0x10)[/code]. Twenty of the twenty-two readable WLDCORE call sites
## pass [code]0x10[/code]; the one [code]0x20[/code] is [code]0x800804BC[/code], which §32.3
## independently records as [code]FUN_80069400(2, 0x20)[/code] — the light scenario
## transition. That agreement is the check on the decode.
##
## [b]The curve is not linear from 255.[/b] For the fade-IN direction (bit 1 of kind clear)
## the tick computes two coupled outputs from [code]counter/len[/code], with MIPS integer
## division, an offset and a clamp:
## [codeblock]
##   descriptor rgb (0x800D0ADC..DE) = 0xC0 - counter*256/len,  floor 0   <-- this file
##   WORLD.BIN modulation (FUN_80106a28) = counter*128/len + 16, ceil 0x80
## [/codeblock]
## So it starts at [b]192[/b], not 255, and saturates at 0 on frame [b]12 of 16[/b] — the
## quad is done four frames before the wait is. The counter increments by [b]one[/b] per
## tick: there is no 2-frame quantisation here. That step was a fact about
## [code]FUN_801467dc[/code], the [code]{3E}[/code] worker in a DIFFERENT overlay, and
## ADR-0161 §4 said so and then shipped it anyway.
##
## [b]Restating the arithmetic instead of sharing [ScenarioColorScreen]'s is now
## VINDICATED, not merely cautious.[/b] §4's argument was that the two ramps share a
## measured blend and an assumed curve. Measured, the curves genuinely differ — different
## step, different endpoints, different clamps — so a shared kernel would have been wrong
## and would now need un-picking. (ADR-0097 refuses a global curve vocabulary for the same
## reason: the units are not interchangeable.)
##
## [b]The latch, and why [constant RAMP_TICKS] is 16 and not 12.[/b] The tick clears bit 3
## of [code]0x8004D950[/code] — the busy latch [code]FUN_80069400[/code] set — on the frame
## where [code]counter + 1 == len[/code]. A caller that fires the cue and blocks on that bit
## waits exactly [param len] frames, however early the picture finished. [method is_active]
## tracks the LATCH; [method is_drawing] tracks the picture, and they part company at 12.
## See CONTEXT.md's [b]Host cue[/b].
##
## [b]Seekable, deliberately.[/b] The pushed value is a pure function of the tick count,
## so [method value_at] answers for any frame without running the ones before it. That
## is what lets the screen-in join the contact-sheet rig (`--menu=screenin`), which SEEKS
## rather than ticks — the same shape `WorldMapTownPage.set_open_frame` has for §38.
##
## [b]Still not verified.[/b] The writer of the second descriptor pair
## ([code]0x800D0AEC..EE[/code]); whether this single quad stands for descriptor 1 or for
## the pair; and the rendered result of any of it. The arithmetic is static, the picture is
## not — `--menu=screenin` is the only instrument for the second half.

## [b]There is deliberately no STEP_TICKS here.[/b] ADR-0161 had one, set to 2 and borrowed
## from the `{3E}` worker; measured, this ramp has NO quantisation — the tick at
## 0x800694A8 advances one frame at a time. A constant equal to 1 is not a step size, it is
## an invitation to reintroduce one. [FormationScreenIn] keeps its `STEP_TICKS` because its
## ramp genuinely quantises; the asymmetry between the two files is the measurement, not an
## oversight.

## Ramp length in vsyncs — the `len` argument to `FUN_80069400`, and the number of frames a
## host blocks on the busy latch. MEASURED as 16 at 0x8006731C. Note the PICTURE lands at
## `START_VALUE * RAMP_TICKS / 256` = tick 12; this constant is the LATCH, not the landing.
const RAMP_TICKS := 16

## Where the subtractive quad starts, 0..255. MEASURED as 0xC0 = 192, the `0xC0` literal at
## 0x8006963C. [b]This is NOT fully black[/b] — level 24 of 31 — and on console it does not
## need to be: there is no mount frame to hide, the map is already built, and subtractive
## holds black for every pixel dimmer than the ramp. The port asks this quad to do a second
## job (cover the mount frame) that the console's never had; whether 192 is enough for that
## is a question for `--menu=screenin`, not for arithmetic.
const START_VALUE := 192

## The console's numerator: the descriptor ramps `START_VALUE - counter*RAMP_SCALE/len`.
const RAMP_SCALE := 256

## PSX framebuffer channel step. `psx_expand_555.gdshader` states the rule: the world map
## composites in the GPU's own 5-bit channels and every quad is baked as `8 * v` for a
## level v in 0..31, with the expansion to 8 bits running ONCE on the finished frame.
## At len 16 every measured value is already a multiple of 8, so this bake is currently a
## no-op — it is kept because it stops being one the moment the length changes.
const LEVEL_STEP := 8.0

var _ticks: int = 0
var _active: bool = true


## The pushed value at [param tick], 0..255, quantised to a 5-bit level.
##
## Mirrors the tick at [code]0x800694A8[/code], fade-IN arm: `0xC0 - counter*256/len`,
## floored at 0, in INTEGER arithmetic — the console divides with MIPS `div`, so the
## fencepost is the console's and not a rounding choice of ours.
static func value_at(tick: int) -> float:
	var t := clampi(tick, 0, RAMP_TICKS)
	var raw := START_VALUE - (t * RAMP_SCALE) / RAMP_TICKS
	if raw <= 0:
		return 0.0
	# Bake to the framebuffer's own levels BEFORE the blend, so the frame computes
	# `e(B - F)` and not `e(B) - e(F)` — the ±1 error psx_expand_555 exists to close.
	return floor(float(raw) / LEVEL_STEP) * LEVEL_STEP


## The tick the PICTURE lands on — the first frame at value 0. Derived, not a constant:
## `0xC0 - t*256/16 <= 0` first holds at t == 12. Four frames before [constant RAMP_TICKS],
## which is the LATCH. Exposed so nothing has to hardcode 12.
static func land_tick() -> int:
	for t in range(0, RAMP_TICKS + 1):
		if value_at(t) <= 0.0:
			return t
	return RAMP_TICKS


## Advance one vsync. No-op once landed. Driven from `WorldMapScene.advance`, on the same
## clock as the bob and §38's town-page open — never from a [Tween]: a delta-driven ramp
## runs at the display's refresh rate, which measured 143.9 Hz here.
func tick() -> void:
	if not _active:
		return
	_ticks += 1
	if _ticks >= RAMP_TICKS:
		_ticks = RAMP_TICKS
		_active = false


## Jump straight to [param tick] without running the frames before it — the contact-sheet
## rig's entry point. Does not emit anything; the caller pushes and renders.
func seek(tick: int) -> void:
	_ticks = clampi(tick, 0, RAMP_TICKS)
	_active = _ticks < RAMP_TICKS


## Snap to landed. The capture rig's settle: `--shot=` wants the settled frame, and it
## freezes the vsync clock, so without this a capture would hold whatever frame of the
## ramp the warm-up happened to reach. Same guarantee `WorldMapTownPage.OPEN_VSYNCS`
## gives §38 in `_capture`.
func settle() -> void:
	seek(RAMP_TICKS)


## True while the LATCH is still held — i.e. while a console host would still be blocking
## on bit 3 of `0x8004D950`. Runs four frames past the last visible frame; see the class
## docs. The navigator polls this BEFORE awaiting
## [signal WorldMapScene.screen_in_finished] — an await armed after the signal already
## fired is §18.2's hang, and the screen-in only advances inside `advance()`, so a
## check-then-await in one frame cannot interleave.
func is_active() -> bool:
	return _active


## Vsyncs elapsed, for tests and the F3 panel.
func ticks() -> int:
	return _ticks


## Current pushed value, 0..255, 5-bit baked.
func current_value() -> float:
	return value_at(_ticks)


## True while the quad is actually tinting anything. At value 0 the subtraction is a
## no-op and the quad is hidden — matching both `FUN_8008f208` (the PSX skips the draw
## at colour (0,0,0)) and §24.1's own reading of WLDCORE's enable gate, whose test is on
## the descriptor's r/g/b: *"is this fade tinting anything at all"*.
## Goes false at tick 12 of 16, four frames before [method is_active] does.
func is_drawing() -> bool:
	return current_value() > 0.0
