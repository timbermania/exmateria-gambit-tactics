extends RefCounted
## Chunked offline ghost renderer — the picker-freeze fix's engine-side half.
##
## SoundGhostProjector.render_pair synthesises a FEDS pair to silence through the real
## SPU in ONE gulp; a long ring-out makes that a multi-second main-thread block, which
## froze every effect pick (_load_effect rendered all firing sounds synchronously).
## This queue renders the SAME captures resumably: step(budget_ms) runs render slices
## inside a per-frame time budget and carries the mid-sound state across calls, so the
## page can pump it from _process while the UI stays live. Only WHEN a ghost arrives
## changes — the render sequence is exactly render_pair's, and SoundRenderQueueTest
## holds the results to that oracle (up to the engine's pre-existing ±1-2-frame tail
## wobble: voice-pool slot bookkeeping outlives panic(), so ANY render's borderline
## tail frame — sync included — varies with cast history; see the test header).
##
## Engine discipline (why this is not a Thread): ExMateriaEffectSfx is one shared SPU —
## live playback, auditions, and captures all mutate the same units/sessions. A capture
## is only deterministic while nothing else touches the engine, so the queue holds
## `capture_mode` (producer parked) for the WHOLE of one sound's render, across yields.
## The page must abort() (requeue in-flight, release the engine) before anything
## audible runs — transport play, a scrub's re-pump, an audition — and resume after;
## a restarted render re-panics and reproduces the equivalent result.
##
## No class_name (ADR-0004) — instantiate by path.

const GhostProjector = preload("res://src/effects/studio/SoundGhostProjector.gd")

# One render slice = one engine.render_subs(SUBS_PER_FRAME) reduced to a frame RMS —
# the exact loop body of render_pair, with the same stop rule (constants shared from
# SoundGhostProjector so the two can never disagree).
const SUBS_PER_FRAME := 8

var _pending: Array = []          # [{sid:int, pair_idx:int}] not yet started, in order

# In-flight job state (flat members, not a Dictionary — packed arrays are
# copy-on-write, so `dict["raw"].append(...)` would mutate a temporary).
var _job_active := false
var _job_sid: int = 0
var _job_pair_idx: int = -1
var _job_token: int = 0
# Per-job render params (render_pair's, carried across yields). A bare {sid, pair_idx}
# job keeps the defaults — whole-pair, normalized, trimmed — so the ghost-length path is
# unchanged. The energy-band path passes single_track (0/1/-1), normalized/trim false, and
# an opaque `tag` echoed back so the caller assembles per-track + joint as they complete.
var _job_single_track: int = -1
var _job_normalized := true
var _job_trim := true
var _job_tag = null
var _raw := PackedFloat32Array()  # per-frame RMS so far
var _quiet: int = 0               # consecutive sub-silence frames (the stop rule)
var _engine = null                # engine holding our capture bracket while a job is open
var _was_capture := false         # capture_mode to restore when the bracket closes


## Replace the whole queue — the effect-switch path. The in-flight job dies (its
## partial render is discarded, the engine released) and only `jobs` remain:
## [{sid, pair_idx}] in render order.
func reset(jobs: Array) -> void:
	_kill_job()
	_pending = jobs.duplicate()


## Append ONE job to the back of the queue, deduped by sid — a job for the same sid already
## pending or in flight wins (a burst of edits to one sound enqueues a single render, which
## reads the latest in-place-mutated bytes at step time). The incremental edit-path counterpart
## to reset()'s bulk effect-switch replace: an edited sound's ghost re-render joins the queue
## without discarding the load-time renders still draining.
func enqueue(job: Dictionary) -> void:
	var sid: int = int(job.get("sid", -1))
	if _job_active and _job_sid == sid:
		return
	for p in _pending:
		if int(p.get("sid", -1)) == sid:
			return
	_pending.append(job)


## Pause for live audio: requeue the in-flight job at the FRONT (its render restarts
## from scratch on resume — a capture interleaved with live sessions would be corrupt)
## and release the engine (capture_mode restored). No-op when nothing is in flight.
func abort() -> void:
	if not _job_active:
		return
	_pending.push_front({"sid": _job_sid, "pair_idx": _job_pair_idx,
		"single_track": _job_single_track, "normalized": _job_normalized,
		"trim": _job_trim, "tag": _job_tag})
	_kill_job()


func is_idle() -> bool:
	return _pending.is_empty() and not _job_active


## Advance the render inside `budget_ms`, returning the jobs that COMPLETED this call:
## [{sid, length, energy}], each identical to render_pair's result for that pair.
## Always makes at least one slice of progress (a zero budget still advances), so the
## queue can never stall. Holds engine.capture_mode from a job's first slice to its
## last; between calls a mid-render job keeps the bracket (see header).
func step(engine, feds_bank, budget_ms: float) -> Array:
	var done: Array = []
	if engine == null or not engine.ready_ok:
		return done
	var deadline: int = Time.get_ticks_usec() + int(maxf(budget_ms, 0.0) * 1000.0)
	while not is_idle():
		if not _job_active:
			_start_next(engine, feds_bank, done)
		if _job_active:
			_render_until(deadline, done)
		if Time.get_ticks_usec() >= deadline:
			break
	return done


## Pop the next pending job. An unresolvable pair completes immediately with
## render_pair's degenerate result (length 0, empty envelope) — no engine touch.
## Otherwise open the capture bracket + a fresh cast, exactly as render_pair does.
func _start_next(engine, feds_bank, done: Array) -> void:
	var j: Dictionary = _pending.pop_front()
	var sid: int = int(j["sid"])
	var pair_idx: int = int(j["pair_idx"])
	var single_track: int = int(j.get("single_track", -1))
	var tag = j.get("tag", null)
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		done.append({"sid": sid, "length": 0, "energy": PackedFloat32Array(),
			"tag": tag, "pair_idx": pair_idx})
		return
	_engine = engine
	_was_capture = engine.capture_mode
	engine.capture_mode = true
	engine.panic()   # isolate from any prior cast, as render_pair does
	var token: int = engine.begin_effect()
	if not engine.play_pair(token, feds_bank, pair_idx, sid, single_track):
		engine.end_effect(token)
		engine.panic()
		engine.capture_mode = _was_capture
		_engine = null
		done.append({"sid": sid, "length": 0, "energy": PackedFloat32Array(),
			"tag": tag, "pair_idx": pair_idx})
		return
	_job_active = true
	_job_sid = sid
	_job_pair_idx = pair_idx
	_job_token = token
	_job_single_track = single_track
	_job_normalized = bool(j.get("normalized", true))
	_job_trim = bool(j.get("trim", true))
	_job_tag = tag
	_raw = PackedFloat32Array()
	_quiet = 0


## Run render slices until the job finishes or the deadline passes — at least one
## slice either way. The loop body and stop rule mirror render_pair exactly.
func _render_until(deadline: int, done: Array) -> void:
	while _raw.size() < GhostProjector.MAX_RENDER_FRAMES \
			and _quiet < GhostProjector.SILENCE_QUIET_FRAMES:
		var rms := GhostProjector.frame_rms(_engine.render_subs(SUBS_PER_FRAME))
		_raw.append(rms)
		if rms >= GhostProjector.SILENCE_RMS:
			_quiet = 0
		else:
			_quiet += 1
		if Time.get_ticks_usec() >= deadline:
			break
	if _raw.size() >= GhostProjector.MAX_RENDER_FRAMES \
			or _quiet >= GhostProjector.SILENCE_QUIET_FRAMES:
		var length := GhostProjector.audible_length(_raw, GhostProjector.SILENCE_RMS)
		# Honor the job's trim/normalized: per-track + joint energy renders want the RAW
		# (un-normalized) envelope so the caller can shared-normalize across the set; the
		# joint additionally wants the UNTRIMMED window. Ghost-length jobs keep the trim +
		# peak-normalize defaults, so their result is byte-identical to before.
		var env := _raw.slice(0, length) if _job_trim else _raw
		var energy := GhostProjector.normalize_peak(env) if _job_normalized else env
		var sid := _job_sid
		var pair_idx := _job_pair_idx
		var tag = _job_tag
		_kill_job()
		done.append({"sid": sid, "length": length, "energy": energy,
			"tag": tag, "pair_idx": pair_idx})


## Close the in-flight job unconditionally: end its cast, panic the engine clean, and
## restore capture_mode. Shared by natural completion, abort() and reset().
func _kill_job() -> void:
	if not _job_active:
		return
	_job_active = false
	if _engine != null:
		_engine.end_effect(_job_token)
		_engine.panic()
		_engine.capture_mode = _was_capture
		_engine = null
	_raw = PackedFloat32Array()
	_quiet = 0
