class_name ScenarioBackground
extends RefCounted
## {2E} Background — the full-screen Gouraud gradient backdrop (the Orbonne
## storm sky + its scripted lightning flashes). Pure model (no scene deps),
## unit-tested against a live PSX capture; ScenarioVM owns one.
##
## FFT decode (research/working_documents/LIGHTNING_FLASH_OPCODE_2E_BACKGROUND.md):
## the opcode carries `[Rt,Gt,Bt, Rb,Gb,Bb, Time, Unk]`. The PSX handler
## (dispatch 0x80145074 → setter `FUN_80090048` @ 0x80090048) drives a RAM
## gradient block (`0x800a1b18` top / `0x800a1b30` bottom, 16.16 fixed-point)
## rendered as a 4-vertex Gouraud full-screen quad: the Top colour at the top
## two vertices, the Bottom colour at the bottom two.
##
## Ramp model (verified live, byte-exact — see the living doc §4): the setter
## writes a per-frame delta `(target - current) / (Time*8)` and the ticker adds
## it each frame, so the gradient converges LINEARLY over exactly `Time*8`
## frames, landing on target, then holds. `Time == 0` snaps instantly. This is a
## simpler model than the {32}/{33} CLUT DDA tables — a plain linear lerp.
##
## The `Unk` byte selects which PSX setter path runs (Unk!=0 → bare
## `FUN_800935f4`; Unk==0 → `FUN_800901f8`, which additionally refreshes a
## secondary "resting" gradient copy `0x800a1b48/4c`). Both paths render the
## primary gradient IDENTICALLY, so `Unk` is irrelevant to the visible flash and
## is ignored here (confirmed live: Gap 1, living doc §3/§7.1).

## Current corner colours (normalized [0,1]). Top = both top vertices, Bottom =
## both bottom vertices (the quad is a pure vertical gradient).
var top: Vector3 = Vector3.ZERO
var bottom: Vector3 = Vector3.ZERO

# Active linear ramp toward (_to_top,_to_bottom). _ramp_frames counts DOWN to 0.
var _ramp_frames: int = 0
var _ramp_total: int = 0
var _from_top: Vector3 = Vector3.ZERO
var _from_bottom: Vector3 = Vector3.ZERO
var _to_top: Vector3 = Vector3.ZERO
var _to_bottom: Vector3 = Vector3.ZERO


## Frame count a given `Time` byte ramps over: `Time*8` (0 == instant snap).
## Mirrors `FUN_80090048`'s `a3 = Time << 3` divisor exactly.
static func ramp_frames_for_time(time: int) -> int:
	return 0 if time <= 0 else time * 8


## Apply a {2E} op. `top_rgb`/`bottom_rgb` are the raw 0..255 operand bytes;
## `time` is the ramp Time byte (0 == snap). Both corners ramp together over the
## same frame count.
func apply(top_rgb: Vector3, bottom_rgb: Vector3, time: int) -> void:
	var tt := top_rgb / 255.0
	var tb := bottom_rgb / 255.0
	if time <= 0:
		# Snap.
		top = tt
		bottom = tb
		_ramp_frames = 0
		_ramp_total = 0
	else:
		_from_top = top
		_from_bottom = bottom
		_to_top = tt
		_to_bottom = tb
		_ramp_total = ramp_frames_for_time(time)
		_ramp_frames = _ramp_total


## Advance one 60 Hz tick. Returns true while a ramp is in flight (i.e. the
## caller should re-push the corners to the background quad this frame).
func tick() -> bool:
	if _ramp_frames <= 0:
		return false
	_ramp_frames -= 1
	if _ramp_frames <= 0:
		# Final frame lands exactly on target.
		top = _to_top
		bottom = _to_bottom
		return true
	var done := 1.0 - float(_ramp_frames) / float(_ramp_total)
	top = _from_top.lerp(_to_top, done)
	bottom = _from_bottom.lerp(_to_bottom, done)
	return true


## True while a ramp is still converging (used by settle predicates/tests).
func is_ramping() -> bool:
	return _ramp_frames > 0


## Snap an in-flight gradient ramp straight to its target corners without spending
## frames — the fast-play settle guarantee (ScenarioVM.settle_screen_effects). Returns
## true if it snapped (caller re-pushes the corners), false if nothing was ramping.
## Mirrors letting `tick()` run to its final frame.
func settle() -> bool:
	if _ramp_frames <= 0:
		return false
	top = _to_top
	bottom = _to_bottom
	_ramp_frames = 0
	_ramp_total = 0
	return true
