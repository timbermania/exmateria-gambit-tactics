class_name ScenarioBgSound
extends RefCounted
## Event-script {6B} "BG Sound" / {6A} "Edit BG Sound" — one ambient background
## sound plus its linear volume ramp. Pure model (no scene/audio deps), owned by
## ScenarioVM (one per live bg sound, keyed by env sound id). Unit-tested against
## the live-hardware decode in
## research/working_documents/BGSOUND_OPCODE_6B_INVESTIGATION.md.
##
## PSX shape (doc §3.4/§3.5, dynamically confirmed D1–D6): {6B} spawns a
## cooperative task (kind 0x35) that plays env-bank sound `Sound` (handle
## 0x10000|Sound), sets the INITIAL volume to `StartVol` (floored at 1 — vol 0
## keys the voice off), then runs a linear ramp `StartVol → Volume` over `Time`
## frames (one step per event-fiber yield ≈ one 60 Hz vsync), landing on the
## exact `Volume`. `Time=0` snaps straight to `Volume`. {6A} Edit BG Sound is the
## SAME ramp on an already-playing bg sound with no re-trigger.
##
## The ramp mirrors the ROM loop (FUN_80149a54): at step k, `vol = k*(Target-
## Start)/Time + Start` (integer-truncated), abs'd and floored at 1 for every
## intermediate step; the final frame sets the exact `Target` (which MAY be 0 —
## a fade-to-silence that keys the voice off). `StartVol` is the ramp START
## volume, NOT "echo" — the wiki's "Echo" label is wrong (doc §4); the min-1
## guard is the tell that op[1] is a volume.

## Env-bank sound id (op[0]); handle is 0x10000|sound_id on PSX.
var sound_id: int = 0
## op[3]: 0 = tracked/replaceable background channel, ≠0 = overlay voice.
var stacking: int = 0
## Whether this env slot is a looping/continuous ambient (SfxCatalog.is_loop).
var loop: bool = false
## Audio backend handle returned by SfxRouter.play_bg (0 = not playing / miss).
var handle: int = 0
## Current integer volume 0..127 (0 only as a ramp endpoint = key-off).
var vol: int = 1

# Active ramp state. `_frames` counts DOWN to 0; `_total` is its length.
var _from: int = 1
var _to: int = 1
var _frames: int = 0
var _total: int = 0


## Arm a `StartVol → Volume` ramp over `time` frames (0 = snap). Sets `vol` to the
## initial value immediately (min-1 guard) so the caller can push it this frame,
## exactly like the PSX task's pre-ramp `FUN_8004408c(handle, StartVol)`.
func start_ramp(start_vol: int, target_vol: int, time: int) -> void:
	_from = start_vol
	_to = target_vol
	# Initial volume: floor StartVol at 1 (vol 0 would key the just-started voice
	# off). A StartVol=0 fade-in therefore begins audible at 1 and ramps up.
	vol = maxi(1, start_vol)
	if time <= 0:
		# Snap: the exact target, which may be 0 (immediate fade-to-silence).
		vol = target_vol
		_frames = 0
		_total = 0
	else:
		_total = time
		_frames = time


## Advance one 60 Hz tick. Returns true while a ramp is in flight (i.e. the caller
## should re-push `vol` to the audio backend this frame).
func tick() -> bool:
	if _frames <= 0:
		return false
	_frames -= 1
	var k := _total - _frames  # step index 1.._total
	if _frames <= 0:
		# Final frame lands on the exact target (may be 0 = key-off).
		vol = _to
	else:
		# Linear, integer-truncated — mirrors the ROM `k*(Target-Start)/Time +
		# Start`. abs guards signed deltas; intermediates floored at 1.
		var v := _from + (_to - _from) * k / _total
		vol = maxi(1, absi(v))
	return true


## True once the ramp has settled (no more per-frame pushes needed).
func is_idle() -> bool:
	return _frames <= 0


## Snap an in-flight volume ramp straight to its target without spending frames — the
## fast-play settle guarantee (ScenarioVM.settle_screen_effects). Returns true if it
## snapped (caller re-pushes `vol`), false if already idle. Mirrors letting `tick()`
## run to its final frame (the target MAY be 0 = a fade-to-silence key-off).
func settle() -> bool:
	if _frames <= 0:
		return false
	vol = _to
	_frames = 0
	_total = 0
	return true
