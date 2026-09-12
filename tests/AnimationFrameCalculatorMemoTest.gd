extends Node
## Characterization test for W2 — memoizing `AnimationFrameCalculator`.
##
## The invariant W2 must protect is stated in `docs/GPU-ARENA-PERF.md` as **"not a
## single animation frame may change"**. This test is what makes that assertion
## mechanical: it runs the calculator's five public queries over the REAL SEQ
## corpus and compares every answer against an **independently structured**
## reference built in this file.
##
## ### Why the reference is written the way it is
##
## `get_frame_at()` answers by *scanning* the opcode list and returning as soon as
## the running duration passes the requested frame. The reference instead
## **expands** the opcode list into an explicit per-frame table once and then
## *indexes* it. Those are different algorithms over the same data, so an
## off-by-one in either one shows up as a disagreement.
##
## That is deliberate: expansion-then-index is also the shape a memo will take, so
## this test is the equivalence proof the memo has to clear before it can land.
##
## ### What this proves, and what it does NOT
##
## Proves: for every animation id in the corpora below, at every frame from 0 past
## the end of the animation, the scanning implementation and an expanded table
## agree — on the displayed frame, the duration, and the three boolean shape
## queries.
##
## Does NOT prove: that either one matches the PSX. This is a characterization
## test — it freezes current behaviour so a refactor cannot move it. If the
## current behaviour is wrong, this test faithfully preserves the wrong answer.
##
## Non-vacuity is asserted, not assumed: the SEQ corpus is ROM-derived and
## gitignored (`SpriteRigContentRoot`), so on a checkout that never populated it
## every dictionary reads empty and every comparison passes over nothing. The
## floors below fail loudly in that case rather than reporting a green.
##
## Run headful; reads stdout; auto-quits.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line
# per file keeps every use site's spelling.
const AnimationFrameCalculator = ExMateriaSpriteRig.AnimationFrameCalculator
const AnimationDatabase = ExMateriaSpriteRig.AnimationDatabase
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

## Corpora to sweep. `type1` is the body SEQ every human unit plays; `wep`/`eff1`
## are the shared layers, and they are separate dictionaries on the same set — so
## a memo keyed on the wrong thing would cross them, and this catches that.
const SETS := [["TYPE1", "type1"], ["MON", "mon"]]

## Frames past the end of an animation exercise `get_frame_at`'s fall-through
## return (hold the last frame forever), which the in-range path never reaches.
const OVERSHOOT := [1, 2, 3, 17, 512]

## Floors that make a vacuous corpus a FAIL rather than a green. Measured against
## the populated tree at the time of writing (type1 alone carries far more).
const MIN_ANIM_IDS := 40
const MIN_COMPARISONS := 2000

var _failures: Array[String] = []
var _comparisons: int = 0
var _anim_ids: int = 0
var _looping: int = 0
var _paused: int = 0
var _hold_forever: int = 0
var _skipped_keys: int = 0


func _ready() -> void:
	for pair in SETS:
		var anims = AnimationDatabase.get_set(pair[0], pair[1])
		if anims == null:
			_fail("%s::%s — AnimationDatabase.get_set returned null" % [pair[0], pair[1]])
			continue
		_sweep("%s::%s type1_seq" % [pair[0], pair[1]], anims.type1_seq)
		_sweep("%s::%s wep_seq" % [pair[0], pair[1]], anims.wep_seq)
		_sweep("%s::%s eff1_seq" % [pair[0], pair[1]], anims.eff1_seq)

	# --- non-vacuity, asserted rather than assumed -------------------------------
	if _anim_ids < MIN_ANIM_IDS:
		_fail("vacuous corpus: %d animation ids swept, floor is %d. The SEQ tree is "
			% [_anim_ids, MIN_ANIM_IDS]
			+ "ROM-derived and gitignored — see SETUP.md — so this is an unpopulated "
			+ "checkout, not a passing test.")
	if _comparisons < MIN_COMPARISONS:
		_fail("vacuous sweep: %d comparisons, floor is %d" % [_comparisons, MIN_COMPARISONS])
	# Each boolean query needs at least one animation that answers true, or its
	# branch was never exercised and the sweep says nothing about it.
	if _looping == 0:
		_fail("no looping animation in the corpus — is_looping's true branch unexercised")
	if _hold_forever == 0:
		_fail("no hold-forever animation — is_hold_forever's true branch unexercised")

	print("[AnimFrameMemo] %d anim ids, %d comparisons | looping=%d pause=%d hold_forever=%d non_array_keys=%d"
		% [_anim_ids, _comparisons, _looping, _paused, _hold_forever, _skipped_keys])

	if _failures.is_empty():
		print("[PASS] AnimationFrameCalculatorMemoTest")
	else:
		for f in _failures:
			print("  - [FAIL] %s" % f)
		print("[FAIL] AnimationFrameCalculatorMemoTest (%d disagreements)" % _failures.size())

	get_tree().quit()


func _sweep(label: String, sequences: Dictionary) -> void:
	if sequences.is_empty():
		return
	for anim_id in sequences.keys():
		# ⚠ Not every key of a SEQ dictionary is an opcode list. `type1_seq` and
		# `wep1_seq` each carry a `_timings` DICTIONARY alongside their 227/94
		# animation entries. Iterating a Dictionary yields its keys, so a sweep that
		# does not filter here calls `.get()` on a String and throws once per opcode.
		# The production scan never trips this because nothing ever asks for
		# `_timings` by name — but an eager memo that expands every key WOULD.
		if typeof(sequences[anim_id]) != TYPE_ARRAY:
			_skipped_keys += 1
			continue
		var aid := str(anim_id)
		_anim_ids += 1

		# --- the three shape queries ---------------------------------------------
		var got_dur: int = AnimationFrameCalculator.get_duration(aid, sequences)
		var ref_dur: int = _ref_duration(aid, sequences)
		_compare(label, aid, "duration", got_dur, ref_dur)

		var got_loop: bool = AnimationFrameCalculator.is_looping(aid, sequences)
		var ref_loop: bool = _ref_has_op(aid, sequences, AnimationOpcodes.Op.INCREMENT_LOOP)
		_compare(label, aid, "is_looping", int(got_loop), int(ref_loop))
		if got_loop:
			_looping += 1

		var got_pause: bool = AnimationFrameCalculator.has_pause(aid, sequences)
		var ref_pause: bool = _ref_has_op(aid, sequences, AnimationOpcodes.Op.PAUSE_ANIMATION)
		_compare(label, aid, "has_pause", int(got_pause), int(ref_pause))
		if got_pause:
			_paused += 1

		var table: PackedInt32Array = _ref_expand(aid, sequences)
		var got_hold: bool = AnimationFrameCalculator.is_hold_forever(aid, sequences)
		# hold-forever == has LoadFrameWait frames but zero total duration.
		var ref_hold: bool = _ref_has_op(aid, sequences, AnimationOpcodes.Op.LOAD_FRAME_WAIT) \
			and ref_dur == 0
		_compare(label, aid, "is_hold_forever", int(got_hold), int(ref_hold))
		if got_hold:
			_hold_forever += 1

		# --- every in-range frame, then past the end ------------------------------
		for f in range(ref_dur):
			_compare(label, aid, "frame[%d]" % f,
				AnimationFrameCalculator.get_frame_at(aid, f, sequences), table[f])
		for over in OVERSHOOT:
			var f: int = ref_dur + over
			_compare(label, aid, "frame[%d] (past end)" % f,
				AnimationFrameCalculator.get_frame_at(aid, f, sequences),
				_ref_last_frame(aid, sequences))


## Expand the opcode list into an explicit frame-per-tick table — the
## structurally-independent counterpart to `get_frame_at`'s scan.
func _ref_expand(anim_id: String, sequences: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for op in sequences.get(anim_id, []):
		if op.get("op_code_id", 0) != AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			continue
		var frame_id: int = op.get("op_code_param_0", 0)
		for _i in range(op.get("op_code_param_1", 0)):
			out.append(frame_id)
	return out


## The frame held once the animation runs past its own length: the LAST
## LoadFrameWait's frame id, regardless of that opcode's wait.
func _ref_last_frame(anim_id: String, sequences: Dictionary) -> int:
	var last := 0
	for op in sequences.get(anim_id, []):
		if op.get("op_code_id", 0) == AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			last = op.get("op_code_param_0", 0)
	return last


func _ref_duration(anim_id: String, sequences: Dictionary) -> int:
	var total := 0
	for op in sequences.get(anim_id, []):
		if op.get("op_code_id", 0) == AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			total += op.get("op_code_param_1", 0)
	return total


func _ref_has_op(anim_id: String, sequences: Dictionary, op_id: int) -> bool:
	for op in sequences.get(anim_id, []):
		if op.get("op_code_id", 0) == op_id:
			return true
	return false


func _compare(label: String, anim_id: String, what: String, got: int, expected: int) -> void:
	_comparisons += 1
	if got != expected:
		_fail("%s anim '%s' %s: got %d, reference says %d" % [label, anim_id, what, got, expected])


func _fail(msg: String) -> void:
	if _failures.size() < 40:
		_failures.append(msg)
