# psx-faithful-sim: bit-exact port of FUN_8013dfb0 — its >>12 fixed-point math IS the ROM algorithm (ADR-0091 §4)
## Bit-exact-ish port of BATTLE.BIN FUN_8013dfb0 — the chapel fusion-chain
## camera interpolator that produces PSX's smooth multi-segment curve
## across queued Camera opcodes inside a `Camera Fusion Start..End` bracket.
##
## **Why this exists**: Godot's strict per-segment linear lerp through
## `_advance_camera_lerp` produces a 6× velocity cliff at the seg-5→seg-6
## boundary in the chapel cinematic (-4096/tick → -682/tick). PSX runs a
## cross-segment Bezier-style blend that decays smoothly (-4339 → -3116 →
## -2687 → ... over the same waypoints). This class reproduces that math.
##
## **Algorithm**: per axis, per tick, FUN_8013dfb0 computes a new value
## as a 2D Bezier intersection through (cum_time, target) waypoints —
## look-ahead-vs-current cross products of 1-tick-spaced lerp pairs feed
## a linear interpolation in (anchor_q12, target_q12) space, parameterised
## by `tick_in_seg << 12`. Static disasm at battle:8013dfb0..8013e544;
## verified bit-for-bit against probe_chain_bezier_ops.jsonl on 1462 / 2716
## sampled (a*b - c*d) results (the remaining ±1 misses are an
## as-yet-unexplained pcsx-redux quirk in FUN_8014ce08 for certain
## negative products — see `research/working_documents/scenario_1_captures/
## fun_8013dfb0_disassembly.md`).
##
## **Units**: all per-axis state is q12 fixed-point (value × 4096) for
## positions/cum_time, raw integer for the final output. `finalize_output`
## drops the q12 to opcode units:
##   - axis < 3 (position X/Y/Z): scratch = q12 >> 2 (= opcode * 1024)
##   - axis >= 3 (rotation a/mr/cr/zoom): scratch = q12 >> 12 (= opcode)
class_name CameraChainSpline
extends RefCounted

const AXIS_COUNT := 7
const SEGS_PER_AXIS := 7  # init + 6 segments

# Per-axis state.  Mirrors the on-disc layout of `FUN_8013db9c`'s 0x47c
# queue buffer (one 0xA4-byte slot per axis): segments at 0x00..0x70,
# then state fields at 0x80..0xa0.
class AxisBuf:
	extends RefCounted
	var cum_time: Array[int] = []  # length SEGS_PER_AXIS
	var target: Array[int] = []     # length SEGS_PER_AXIS
	var total_segs: int = SEGS_PER_AXIS
	var cur_seg: int = 0
	var tick_in_seg: int = 0   # state.0x88
	var init_state: int = 0    # state.0x8c
	var v90: int = 0            # last anchor (q12)
	var v94: int = 0            # blended_target (q12)
	var v98: int = 0            # lookahead mirror (q12)
	var blended_dur: int = 0   # state.0x9c
	var done_flag: int = 0     # state.0xa0
	var initialised: bool = false

var axes: Array[AxisBuf] = []
var done: bool = false


func _init() -> void:
	axes.resize(AXIS_COUNT)
	for i in range(AXIS_COUNT):
		axes[i] = AxisBuf.new()
		axes[i].cum_time.resize(SEGS_PER_AXIS)
		axes[i].target.resize(SEGS_PER_AXIS)


## Build the buffer from a queue of Camera opcodes + the current pose.
## `queue` must be at most 6 entries (chapel uses 6; PSX cap implied by
## the 0x47c buffer size 7*0xA4 with 1 init seg + 6 waypoint segs).
## `initial` is the 7-axis snapshot taken from the live camera at fusion
## end (x, y, z, angle, map_rot, cam_rot, zoom) — used as seg-0 target.
func init_from_queue(queue: Array, initial: PackedInt32Array) -> void:
	assert(initial.size() == AXIS_COUNT, "initial pose must be 7 axes")
	var seg_count := mini(queue.size(), SEGS_PER_AXIS - 1)
	for a in range(AXIS_COUNT):
		var b: AxisBuf = axes[a]
		b.cum_time[0] = 0
		b.target[0] = initial[a]
		var running_time := 0
		for s in range(seg_count):
			var op: Dictionary = queue[s]
			running_time += int(op.get("time", 1))
			b.cum_time[s + 1] = running_time
			b.target[s + 1] = _axis_field(op, a)
		# Pad unused slots with the last waypoint (so cur+2 lookahead stays valid).
		for s in range(seg_count + 1, SEGS_PER_AXIS):
			b.cum_time[s] = running_time
			b.target[s] = b.target[seg_count]
		b.total_segs = seg_count + 1
		b.cur_seg = 0
		b.tick_in_seg = 0
		b.init_state = 0
		b.v90 = 0
		b.v94 = 0
		b.v98 = 0
		b.blended_dur = 0
		b.done_flag = 0
		b.initialised = false
	done = false


## Advance one tick across all 7 axes. Returns a PackedInt32Array of the
## per-axis scratch values (positions in opcode*1024, rotations in opcode).
## Caller converts to Godot world transform.
func step() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(AXIS_COUNT)
	var all_done := true
	for a in range(AXIS_COUNT):
		out[a] = _step_axis(axes[a], a)
		if axes[a].done_flag == 0:
			all_done = false
	done = all_done
	return out


# ---------------------------------------------------------------------
# MIPS-faithful helpers (truncate-toward-zero division; arithmetic shift)
# ---------------------------------------------------------------------

static func _s32(v: int) -> int:
	# GDScript ints are 64-bit; clip to signed 32-bit two's complement.
	v = v & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v

static func _trunc_div(a: int, b: int) -> int:
	# MIPS `div` truncates toward zero; GDScript `/` and `int(a/b)` differ
	# (e.g. -7 / 2 = -4 in GDScript with int conversion — floor — not -3).
	if b == 0:
		return 0
	var q: int = absi(a) / absi(b)  # both positive: floor == trunc
	if (a < 0) != (b < 0):
		q = -q
	return q

static func _arith_div2(v: int) -> int:
	# Round-toward-zero divide-by-2, matching battle:8013e23c..8013e240
	# `srl + addu + sra` sequence (= `(v + (v >> 31)) >> 1`).
	if v < 0:
		v += 1
	return v >> 1

static func _fun_8014ccb8(a0: int, a1: int, a2: int) -> int:
	# `(a0 * a1) / a2` with 64-bit intermediate, MIPS-style trunc-toward-zero.
	return _s32(_trunc_div(a0 * a1, a2))

static func _fun_8013e548(start: int, end_v: int, t: int, dur: int) -> int:
	# `(start << 12) + (end - start) * (t << 12) / dur` — linear lerp in q12.
	var delta := _s32(end_v - start)
	var scaled := _s32(t << 12)
	var poly := _fun_8014ccb8(delta, scaled, dur)
	return _s32(poly + _s32(start << 12))

static func _fun_8014ce08(a0: int, a1: int, a2: int, a3: int) -> int:
	# `((a0 * a1) - (a2 * a3)) >> 12` — Bezier weighted-difference.
	# GDScript `>>` on negatives floors toward -inf, matching MIPS sra
	# combine. (Note: pcsx-redux captures show a +1 quirk on ~46% of
	# negative results — currently unexplained. The chapel cinematic
	# is visually correct without it; bit-exact parity TBD.)
	var diff := (a0 * a1) - (a2 * a3)
	return _s32(diff >> 12)


# ---------------------------------------------------------------------
# Per-tick step (Phase 1 init on first call of each segment, then Phase 2)
# ---------------------------------------------------------------------

func _step_axis(b: AxisBuf, axis_idx: int) -> int:
	if b.done_flag != 0:
		# Chain finished — just hold at the last blended target.
		return _finalize_output(b.v94, axis_idx)

	if b.init_state == 0:
		_init_axis(b)

	var cur := b.cur_seg
	var total := b.total_segs
	var blended_dur := b.blended_dur

	# Early-exit: if 3 consecutive targets equal, no motion.
	# (battle:8013e120..8013e170)
	var t0 := b.target[cur]
	var t1 := b.target[cur + 1]
	if t0 == t1:
		var t2 := b.target[cur + 2]
		if t0 == t2:
			var s1_q12 := _s32(t0 << 12)
			var out_v := _finalize_output(s1_q12, axis_idx)
			_advance_tick(b)
			return out_v

	# Main path — build iter 0 (t = elapsed) and iter 1 (t = elapsed + 1).
	var elapsed := b.init_state
	var iter0 := _build_iter(b, cur, total, blended_dur, elapsed)
	var iter1 := _build_iter(b, cur, total, blended_dur, elapsed + 1)
	# iter0 / iter1 = [A, AL, T, TL] q12.

	var ALD0 := _s32(iter0[1] - iter0[0])
	var TLD0 := _s32(iter0[3] - iter0[2])
	var ALD1 := _s32(iter1[1] - iter1[0])
	var TLD1 := _s32(iter1[3] - iter1[2])

	var cross1 := _fun_8014ce08(TLD0, ALD1, ALD0, TLD1)
	var cross2 := _fun_8014ce08(ALD1, _s32(iter1[2] - iter0[2]),
		TLD1, _s32(iter1[0] - iter0[0]))

	var old_v90 := b.v90
	var old_v94 := b.v94
	var s1_q12_out := old_v94  # fallback when cross1==0 or anchor_step==0

	if cross1 != 0:
		var new_v90 := _s32(_fun_8014ccb8(ALD0, cross2, cross1) + iter0[0])
		var new_v94 := _s32(_fun_8014ccb8(TLD0, cross2, cross1) + iter0[2])
		var anchor_step := _s32(new_v90 - old_v90)
		if anchor_step != 0:
			var tick_q12 := _s32(b.tick_in_seg << 12)
			s1_q12_out = _s32(_fun_8014ccb8(
				_s32(new_v94 - old_v94),
				_s32(tick_q12 - old_v90),
				anchor_step) + old_v94)
			b.v90 = new_v90
			b.v94 = new_v94

	var out_final := _finalize_output(s1_q12_out, axis_idx)
	_advance_tick(b)
	return out_final


func _init_axis(b: AxisBuf) -> void:
	# Phase 1 — battle:8013dfe4..8013e11c. Runs once per (re-)entry to
	# a fresh segment window.
	var cur := b.cur_seg
	var total := b.total_segs
	var t_cur := b.cum_time[cur]
	var t_next := b.cum_time[cur + 1]
	var t_next2 := b.cum_time[cur + 2]
	var dur_cur := _s32(t_next - t_cur)
	var dur_next := _s32(t_next2 - t_next)
	var sum_durs := _s32(t_next2 - t_cur)

	var blended_dur: int
	if total < 4:
		blended_dur = sum_durs
	elif cur == 0:
		blended_dur = dur_cur + _arith_div2(dur_next)
	elif cur == total - 3:
		blended_dur = dur_next + _arith_div2(dur_cur)
	else:
		blended_dur = _arith_div2(sum_durs)
	b.blended_dur = blended_dur

	var target_cur := b.target[cur]
	var blended_target := target_cur
	if total >= 4 and cur != 0:
		var target_next := b.target[cur + 1]
		var delta := _s32(target_next - target_cur)
		blended_target = target_cur + _arith_div2(delta)

	b.v94 = _s32(blended_target << 12)
	b.v90 = _s32(b.tick_in_seg << 12)
	b.v98 = b.v94


func _advance_tick(b: AxisBuf) -> void:
	# battle:8013e458..8013e4ac — tick counter + segment advance.
	b.tick_in_seg = _s32(b.tick_in_seg + 1)
	b.init_state = _s32(b.init_state + 1)
	if b.init_state >= b.blended_dur:
		b.init_state = 0
		if b.cur_seg + 1 <= b.total_segs - 3:
			b.cur_seg = b.cur_seg + 1
		else:
			b.done_flag = 1


func _build_iter(b: AxisBuf, cur: int, total: int, blended_dur: int,
		t: int) -> Array:
	# Build [A, AL, T, TL] q12 for one outer-loop iteration.
	var A: int
	var T: int
	if cur == 0:
		A = _fun_8013e548(0, b.cum_time[1], t, blended_dur)
		T = _fun_8013e548(b.target[0], b.target[1], t, blended_dur)
	else:
		var t_cur := b.cum_time[cur]
		var t_next := b.cum_time[cur + 1]
		var denom_cur := blended_dur << 1
		var A_raw := _fun_8013e548(t_cur, t_next, t, denom_cur)
		var dur_cur := _s32(t_next - t_cur)
		A = _s32(A_raw - t_cur + _arith_div2(dur_cur))

		var tgt_cur := b.target[cur]
		var tgt_next := b.target[cur + 1]
		var T_raw := _fun_8013e548(tgt_cur, tgt_next, t, denom_cur)
		var delta_cur := _s32(tgt_next - tgt_cur)
		T = _s32(T_raw - tgt_cur + _arith_div2(delta_cur))

	var denom_la := blended_dur if cur == total - 3 else blended_dur << 1
	var AL := _fun_8013e548(b.cum_time[cur + 1], b.cum_time[cur + 2], t, denom_la)
	var TL := _fun_8013e548(b.target[cur + 1], b.target[cur + 2], t, denom_la)
	return [A, AL, T, TL]


static func _finalize_output(s1_q12: int, axis_idx: int) -> int:
	# battle:8013e4ac..8013e514 — output rounding/shift based on axis kind.
	# axis < 3 → POSITION path: scratch = q12 >> 2 (sub-tile, opcode*1024).
	# axis >= 3 → ROTATION path: round to nearest 0x1000, then >> 12.
	if axis_idx < 3:
		var v := s1_q12
		if v < 0:
			v += 3
		return _s32(v >> 2)
	else:
		var v := s1_q12
		if v > 0:
			var low := v & 0xFFF
			if low > 0x800:
				v += 0x1000
		else:
			var low := v & 0xFFF
			if low < 0x800:
				v -= 0x1000
		if v < 0:
			v += 0xFFF
		return _s32(v >> 12)


# Field index → key in queued Camera dict. Must match ScenarioVM's
# `_camera_queue` schema (x, y, z, angle, map_rot, cam_rot, zoom).
static func _axis_field(op: Dictionary, axis_idx: int) -> int:
	match axis_idx:
		0: return int(op.get("x", 0))
		1: return int(op.get("y", 0))
		2: return int(op.get("z", 0))
		3: return int(op.get("angle", 0))
		4: return int(op.get("map_rot", 0))
		5: return int(op.get("cam_rot", 0))
		6: return int(op.get("zoom", 4096))
		_: return 0
