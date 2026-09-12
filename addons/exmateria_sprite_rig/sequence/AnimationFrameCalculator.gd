extends RefCounted

## Pure functions for animation frame calculation.
##
## This class provides stateless, deterministic frame lookup for animations.
## Given an animation ID and integer frame count, returns the display frame.
## Uses integer frames throughout to match the original PSX fixed-timestep design.
##
## Every query is memoised — see "The memo" below. The answers are unchanged;
## `tests/AnimationFrameCalculatorMemoTest.gd` is the equivalence proof.

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes


# ---------------------------------------------------------------------------
# The memo (W2, docs/GPU-ARENA-PERF.md).
#
# The five queries below are pure functions of `(anim_id, sequences)` and each
# did its own uncached linear scan of the opcode array — four scans per playback
# per tick, ~23 000 scans/s at 6 playbacks x 16 units.
#
# WHY THERE IS NO INVALIDATION HOOK, AND NO STALE READ IS POSSIBLE.
# A record is keyed by animation id AND carries the opcode `Array` it was built
# from. It is returned only when `is_same()` says the caller handed us that same
# Array object. `is_same()` is reference identity — `==` on an Array is a deep
# CONTENT compare, and using an Array as a Dictionary key hashes it by content,
# so neither of those would serve.
#
# What that buys:
#   * Nothing is keyed on a UNIT. A unit changing job, sprite, equipment or team
#     cannot invalidate anything, because no unit is part of the key. There are
#     no invalidation calls anywhere in game code.
#   * `AnimationDatabase.clear_cache()` reloads the JSON into NEW Arrays, so old
#     records stop matching and are rebuilt. There is no hook to forget to call.
#   * A memo can never be more stale than the data it was built from, because it
#     is only ever used when it IS that data.
#
# The per-id bucket holds the few live corpora that can share an id (type1 vs
# wep1 vs eff1, plus the type2/mon variants) and is capped, so repeated reloads
# cannot grow it without bound.
const _MEMO_VARIANTS_PER_ID: int = 4

static var _memo: Dictionary = {}

## Returned for an id the corpus does not carry, and for a key whose value is not
## an opcode list at all — `type1_seq` and `wep1_seq` each hold a `_timings`
## DICTIONARY beside their animation entries. The scanning implementation
## iterated that dictionary's KEYS and threw `Nonexistent function 'get' in base
## 'String'` once per key. Nothing asks for `_timings` by name so it never fired
## in production, but it is a real edge: this returns the same values the aborted
## scan did (zeroes and falses), without the error spam.
## `static var`, not `const`: `PackedInt32Array()` is not a constant expression,
## and a `const` holding one is a COMPILE error that takes the whole addon down
## with it (every consumer then resolves to a GDScript with no statics).
static var _EMPTY: Dictionary = {
	"frames": PackedInt32Array(), "last": 0, "dur": 0,
	"loop": false, "pause": false, "hold": false, "ops": null,
}


static func _record(anim_id: String, sequences: Dictionary) -> Dictionary:
	if not sequences.has(anim_id):
		return _EMPTY
	var ops = sequences[anim_id]
	if typeof(ops) != TYPE_ARRAY:
		return _EMPTY

	var bucket: Array = _memo.get(anim_id, [])
	for rec in bucket:
		if is_same(rec["ops"], ops):
			return rec

	var built := _build(ops)
	bucket.push_front(built)
	if bucket.size() > _MEMO_VARIANTS_PER_ID:
		bucket.resize(_MEMO_VARIANTS_PER_ID)
	_memo[anim_id] = bucket
	return built


## One pass over the opcodes answers all five queries. `frames` is the animation
## expanded to one entry per tick, which turns `get_frame_at` into an array index.
static func _build(ops: Array) -> Dictionary:
	var frames := PackedInt32Array()
	var last: int = 0
	var loops: bool = false
	var pause: bool = false
	var has_frames: bool = false

	for op in ops:
		var op_id: int = op.get("op_code_id", 0)
		if op_id == AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			has_frames = true
			last = op.get("op_code_param_0", 0)
			for _i in range(op.get("op_code_param_1", 0)):
				frames.append(last)
		elif op_id == AnimationOpcodes.Op.INCREMENT_LOOP:
			loops = true
		elif op_id == AnimationOpcodes.Op.PAUSE_ANIMATION:
			pause = true

	return {
		"frames": frames,
		"last": last,
		"dur": frames.size(),
		"loop": loops,
		"pause": pause,
		# Hold forever = has frames to display but 0 total duration (wait=0 acts
		# as terminator), exactly as the scanning implementation defined it.
		"hold": has_frames and frames.is_empty(),
		"ops": ops,
	}


## Get display frame at specific animation frame (pure function).
##
## Args:
##     anim_id: Animation hex ID (e.g. "6" for IDLE_FRONT)
##     anim_frame: Integer frame counter (0, 1, 2, ...)
##     sequences: Dictionary of animation sequences (type1_seq, wep1_seq, etc.)
##
## Returns:
##     frame_id to display (the op_code_param_0 from LoadFrameWait)
static func get_frame_at(anim_id: String, anim_frame: int, sequences: Dictionary) -> int:
	var rec := _record(anim_id, sequences)
	var frames: PackedInt32Array = rec["frames"]
	if anim_frame < 0 or anim_frame >= frames.size():
		# Past the end the animation holds the last frame a LoadFrameWait named —
		# which is also the answer when it named none (0).
		return rec["last"]
	return frames[anim_frame]


## Get total duration of animation in frames (integer).
##
## Args:
##     anim_id: Animation hex ID
##     sequences: Dictionary of animation sequences
##
## Returns:
##     Total duration in animation frames
static func get_duration(anim_id: String, sequences: Dictionary) -> int:
	return _record(anim_id, sequences)["dur"]


## Check if animation loops (has IncrementLoop opcode).
##
## Args:
##     anim_id: Animation hex ID
##     sequences: Dictionary of animation sequences
##
## Returns:
##     true if animation loops, false otherwise
static func is_looping(anim_id: String, sequences: Dictionary) -> bool:
	return _record(anim_id, sequences)["loop"]


## Check if animation has PauseAnimation opcode (holds final frame).
##
## Args:
##     anim_id: Animation hex ID
##     sequences: Dictionary of animation sequences
##
## Returns:
##     true if animation has pause, false otherwise
static func has_pause(anim_id: String, sequences: Dictionary) -> bool:
	return _record(anim_id, sequences)["pause"]


## Check if animation is a "hold forever" type.
##
## Hold forever animations have LoadFrameWait opcodes but 0 total duration.
## In FFT, these are static pose sequences where wait=0 acts as terminator,
## causing the unit to hold that frame indefinitely until a new animation triggers.
##
## Args:
##     anim_id: Animation hex ID
##     sequences: Dictionary of animation sequences
##
## Returns:
##     true if animation should hold forever (has frames but 0 duration)
static func is_hold_forever(anim_id: String, sequences: Dictionary) -> bool:
	return _record(anim_id, sequences)["hold"]
