extends Node
## SoundRenderQueueTest — the chunked offline ghost renderer behind the picker-freeze
## fix. SoundRenderQueue renders the SAME per-sound SPU captures as
## SoundGhostProjector.render_pair, but resumably: step(budget_ms) runs slices of the
## render inside a per-frame time budget and carries the mid-sound state across calls,
## so a multi-second ring-out no longer blocks the main thread in one gulp.
##
## The load-bearing property: the stepped result matches the one-gulp render_pair —
## only WHEN the value arrives changes, not what it is. render_pair is the oracle,
## compared with a small tolerance: the engine's voice-POOL slot bookkeeping outlives
## panic(), so which SPU slot a cast lands on rotates with cast history, wobbling a
## borderline tail frame by ±1-2 (probed: back-to-back SYNC renders of E317 pair 2
## give lengths 51-54, reproducibly per cast ordinal — a pre-existing property of the
## sync path, not introduced by chunking).
##
## Engine-scene test (needs the native SPU + ExMateriaEffectSfx autoload) → runs WITHOUT
## --quit-after; self-quits once done.
##
## Run:  <GODOT> --path . res://tests/SoundRenderQueueTest.tscn

const EffectData = ExMateriaEffects.EffectData

const Projector = preload("res://src/effects/studio/SoundGhostProjector.gd")
const RenderQueue = preload("res://src/effects/studio/SoundRenderQueue.gd")
const EffectJSONLoaderClass = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")

const EFFECT := "res://assets/effects/E317"

# Cast-ordinal slot-rotation wobble allowance (see header): a borderline tail frame
# may shift a couple of frames between renders of the SAME pair; a WRONG sound is
# tens of frames off with an unrelated envelope shape.
const LEN_TOL := 3
const ENV_TOL := 0.05

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not ExMateriaAudioEngine.ready_ok or not ExMateriaEffectSfx.ready_ok:
		print("[FAIL] audio engines not ready")
		get_tree().quit(1)
		return

	var loaded = EffectJSONLoaderClass.load_dir(EFFECT)
	if loaded == null or not loaded.has_sound() or loaded.feds_bank == null:
		print("[FAIL] %s has no FEDS sound data" % EFFECT)
		get_tree().quit(1)
		return

	var effect_data = EffectData.load_from_directory(EFFECT)
	var containers = loaded.sound_containers
	var fb = loaded.feds_bank
	var sids: Array = Projector.firing_sound_ids(effect_data.sound)
	if sids.is_empty():
		print("[FAIL] %s has no firing sound_ids" % EFFECT)
		get_tree().quit(1)
		return

	# The oracle: the one-gulp sync renders (deterministic per SoundEnvelopeCaptureTest).
	var oracle: Dictionary = {}
	ExMateriaEffectSfx.capture_mode = true
	for sid in sids:
		var pair: int = Projector.resolve_pair_idx(containers, sid)
		oracle[sid] = Projector.render_pair(ExMateriaEffectSfx, fb, pair, sid)
	# A single-track RAW oracle (the per-track energy-band path): track 0 alone,
	# un-normalized + untrimmed — what a tagged single_track job must reproduce.
	var st_pair: int = Projector.resolve_pair_idx(containers, sids[0])
	var st_oracle: Dictionary = Projector.render_pair(ExMateriaEffectSfx, fb, st_pair, sids[0],
		8, Projector.SILENCE_RMS, Projector.SILENCE_QUIET_FRAMES, Projector.MAX_RENDER_FRAMES,
		0, false, false)
	ExMateriaEffectSfx.capture_mode = false

	_test_enqueue_appends_and_dedups_by_sid(containers, fb, sids, oracle)
	_test_a_tagged_single_track_job_renders_that_track_raw(containers, fb, sids, st_oracle)
	_test_one_job_stepped_to_completion_equals_render_pair(containers, fb, sids, oracle)
	_test_a_small_budget_spreads_one_render_across_many_steps(containers, fb, sids, oracle)
	_test_all_firing_sounds_complete_and_match(containers, fb, sids, oracle)
	_test_capture_bracket_held_mid_job_released_when_idle(containers, fb, sids)
	_test_an_unresolvable_pair_yields_an_empty_result_immediately(fb)
	_test_abort_requeues_and_a_restart_still_matches(containers, fb, sids, oracle)
	_test_reset_discards_everything_and_releases_the_engine(containers, fb, sids)

	print("\n=== SoundRenderQueueTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundRenderQueueTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundRenderQueueTest")
		get_tree().quit(0)


func _jobs_for(containers: Dictionary, sids: Array) -> Array:
	var jobs: Array = []
	for sid in sids:
		jobs.append({"sid": sid, "pair_idx": Projector.resolve_pair_idx(containers, sid)})
	return jobs


## Drain the queue with `budget_ms` per step; returns {"results": Array, "steps": int}.
func _drain(q, fb, budget_ms: float, max_steps: int = 100000) -> Dictionary:
	var results: Array = []
	var steps := 0
	while not q.is_idle() and steps < max_steps:
		results.append_array(q.step(ExMateriaEffectSfx, fb, budget_ms))
		steps += 1
	return {"results": results, "steps": steps}


## enqueue() appends one job for the incremental edit path, but a second enqueue of the SAME
## sid is a no-op (dedup) — a burst of edits to one sound never piles up duplicate renders.
## The appended job still renders correctly (matches the one-gulp oracle).
func _test_enqueue_appends_and_dedups_by_sid(containers: Dictionary, fb, sids: Array, oracle: Dictionary) -> void:
	var sid: int = sids[0]
	var pair: int = Projector.resolve_pair_idx(containers, sid)
	var q = RenderQueue.new()
	q.enqueue({"sid": sid, "pair_idx": pair})
	q.enqueue({"sid": sid, "pair_idx": pair})   # dup by sid → ignored
	_assert_true(not q.is_idle(), "enqueue makes the queue non-idle")
	var results: Array = _drain(q, fb, 60000.0)["results"]
	_assert_eq(results.size(), 1, "a duplicate-sid enqueue does NOT queue a second render")
	if results.size() == 1:
		_assert_matches(results[0], oracle[sid], "an enqueued job renders identically to the one-gulp oracle")


## A job carrying single_track / normalized / trim renders THAT track's RAW envelope
## (the energy-band path), and the result ECHOES its tag + pair_idx so the caller can
## assemble the per-track + joint set as the chunked renders complete out of order.
func _test_a_tagged_single_track_job_renders_that_track_raw(containers: Dictionary, fb, sids: Array, st_oracle: Dictionary) -> void:
	var sid: int = sids[0]
	var pair: int = Projector.resolve_pair_idx(containers, sid)
	var q = RenderQueue.new()
	q.reset([{"sid": sid, "pair_idx": pair, "single_track": 0, "normalized": false, "trim": false, "tag": "a"}])
	var results: Array = _drain(q, fb, 60000.0)["results"]
	_assert_eq(results.size(), 1, "the tagged single-track job yields one result")
	if results.size() == 1:
		_assert_eq(results[0].get("tag", null), "a", "the result echoes its tag")
		_assert_eq(int(results[0].get("pair_idx", -999)), pair, "the result echoes its pair_idx")
		_assert_matches(results[0], st_oracle, "single-track raw job == render_pair(single_track=0, normalized=false, trim=false)")


## One queued sound, stepped with a huge budget, completes in one call and its
## length + envelope are EXACTLY the sync render_pair's.
func _test_one_job_stepped_to_completion_equals_render_pair(containers: Dictionary, fb, sids: Array, oracle: Dictionary) -> void:
	var sid: int = sids[0]
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, [sid]))
	_assert_true(not q.is_idle(), "a queued job makes the queue non-idle")
	var d := _drain(q, fb, 60000.0)
	var results: Array = d["results"]
	_assert_eq(results.size(), 1, "one job yields one result")
	if results.size() == 1:
		_assert_eq(int(results[0]["sid"]), sid, "the result carries its sound_id")
		_assert_matches(results[0], oracle[sid], "the stepped render matches the one-gulp render_pair")
	_assert_true(q.is_idle(), "the queue is idle after its only job completes")


## A tiny budget must still make progress every call, spreading ONE sound's render
## across many step calls — the anti-freeze property — and the value must not change.
func _test_a_small_budget_spreads_one_render_across_many_steps(containers: Dictionary, fb, sids: Array, oracle: Dictionary) -> void:
	var sid: int = sids[0]
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, [sid]))
	var d := _drain(q, fb, 0.0)   # zero budget: exactly one slice per call
	_assert_true(int(d["steps"]) > 5,
		"a zero budget spreads the render across many steps (got %d)" % int(d["steps"]))
	var results: Array = d["results"]
	_assert_eq(results.size(), 1, "the chunked render still yields exactly one result")
	if results.size() == 1:
		_assert_matches(results[0], oracle[sid], "the chunked render matches the one-gulp render")


## Every firing sound queued at once completes, covering exactly the queued sids,
## each matching its oracle render.
func _test_all_firing_sounds_complete_and_match(containers: Dictionary, fb, sids: Array, oracle: Dictionary) -> void:
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, sids))
	var results: Array = _drain(q, fb, 8.0)["results"]
	_assert_eq(results.size(), sids.size(), "every queued sound completes")
	var all_match := true
	for r in results:
		var sid: int = int(r["sid"])
		if not oracle.has(sid) or not _matches(r, oracle[sid]):
			all_match = false
			print("    [diff] sid %d: length %d vs oracle %s" % [sid,
				int(r["length"]), str(oracle[sid]["length"]) if oracle.has(sid) else "?"])
	_assert_true(all_match, "every chunked result matches its one-gulp oracle")


## While a job is mid-render the queue holds engine.capture_mode (the offline capture
## must not interleave with live audio); once idle it is released.
func _test_capture_bracket_held_mid_job_released_when_idle(containers: Dictionary, fb, sids: Array) -> void:
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, [sids[0]]))
	q.step(ExMateriaEffectSfx, fb, 0.0)   # one slice — job now mid-render
	_assert_true(not q.is_idle(), "one zero-budget slice leaves the job mid-render")
	_assert_true(ExMateriaEffectSfx.capture_mode, "capture_mode is held while a job is mid-render")
	_drain(q, fb, 60000.0)
	_assert_true(not ExMateriaEffectSfx.capture_mode, "capture_mode is released once the queue is idle")


## A job whose sound resolves to no FEDS pair yields the same degenerate result as
## render_pair (length 0, empty envelope) without touching the engine.
func _test_an_unresolvable_pair_yields_an_empty_result_immediately(fb) -> void:
	var q = RenderQueue.new()
	q.reset([{"sid": 7, "pair_idx": -1}, {"sid": 9, "pair_idx": 9999}])
	var results: Array = q.step(ExMateriaEffectSfx, fb, 60000.0)
	_assert_eq(results.size(), 2, "unresolvable jobs still report (empty) results")
	var all_empty := true
	for r in results:
		if int(r["length"]) != 0 or r["energy"].size() != 0:
			all_empty = false
	_assert_true(all_empty, "an unresolvable pair projects length 0 and an empty envelope")
	_assert_true(q.is_idle(), "unresolvable jobs drain the queue")
	_assert_true(not ExMateriaEffectSfx.capture_mode, "no capture bracket is left behind")


## abort() mid-render releases the engine (capture off, no live session) and requeues
## the job; a later drain restarts it from scratch and the value still matches — the
## pause-for-live-audio path must never corrupt a render.
func _test_abort_requeues_and_a_restart_still_matches(containers: Dictionary, fb, sids: Array, oracle: Dictionary) -> void:
	var sid: int = sids[0]
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, [sid]))
	q.step(ExMateriaEffectSfx, fb, 0.0)   # mid-render
	q.abort()
	_assert_true(not ExMateriaEffectSfx.capture_mode, "abort releases capture_mode")
	_assert_true(not q.is_idle(), "abort requeues the in-flight job (work is not lost)")
	var results: Array = _drain(q, fb, 8.0)["results"]
	_assert_eq(results.size(), 1, "the requeued job completes on resume")
	if results.size() == 1:
		_assert_matches(results[0], oracle[sid], "a render restarted after abort still matches the oracle")


## reset() replaces everything — an effect switch: the in-flight job dies (engine
## released), pending jobs are dropped, and only the new list renders.
func _test_reset_discards_everything_and_releases_the_engine(containers: Dictionary, fb, sids: Array) -> void:
	var q = RenderQueue.new()
	q.reset(_jobs_for(containers, sids))
	q.step(ExMateriaEffectSfx, fb, 0.0)   # mid-render on the old effect
	q.reset([])
	_assert_true(q.is_idle(), "reset([]) empties the queue")
	_assert_true(not ExMateriaEffectSfx.capture_mode, "reset releases capture_mode")
	_assert_eq(q.step(ExMateriaEffectSfx, fb, 8.0).size(), 0, "nothing renders after reset([])")


# --- helpers --------------------------------------------------------------

## Same sound? Length within the slot-rotation wobble and envelope shape within a
## small mean deviation over the common prefix (see header).
func _matches(r: Dictionary, o: Dictionary) -> bool:
	if absi(int(r["length"]) - int(o["length"])) > LEN_TOL:
		return false
	var a: PackedFloat32Array = r["energy"]
	var b: PackedFloat32Array = o["energy"]
	var n := mini(a.size(), b.size())
	if n == 0:
		return a.size() == b.size()
	var dev := 0.0
	for i in range(n):
		dev += absf(a[i] - b[i])
	return dev / float(n) <= ENV_TOL


func _assert_matches(r: Dictionary, o: Dictionary, label: String) -> void:
	if _matches(r, o):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — length %d vs %d" % [label, int(r["length"]), int(o["length"])])


# --- asserts --------------------------------------------------------------

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
