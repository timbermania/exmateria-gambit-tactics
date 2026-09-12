extends Node
## EffectTimeline unit test (ADR-0012). Pure GDScript — no overlays, no SPU, no
## RenderingDevice, no scene. Drives the orchestrator with **stub tracks** and
## asserts the pump contract:
##   - tracks advanced in registration order, once per fixed frame;
##   - the fixed-timestep accumulator, incl. the first-delta clamp and catch-up;
##   - the open phase-window SET passed each frame (model C);
##   - the timeline's own pacing-curve time-scaling of the clock (ADR-0014);
##   - null tracks skipped; the start() gate; and reset().
## The interface is the test surface (ADR-0011): this exercises advance(frame,
## phase) / reset() / tick() with no real tracks.

const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const EffectPhase = ExMateriaEffects.EffectPhase

const STEP := 1.0 / 30.0  # one fixed frame (EffectTimeline.PHYSICS_TIMESTEP)

var _seq: Array = []  # shared advance-order log across tracks: [[name, frame], ...]
var _failed := false


class StubTrack:
	var tname: String
	var seq: Array
	var calls: Array = []                 # [[frame, phase], ...]
	var resets: int = 0
	func _init(n: String, shared_seq: Array) -> void:
		tname = n
		seq = shared_seq
	func advance(frame: int, phase) -> void:
		calls.append([frame, phase])
		seq.append([tname, frame])
	func reset() -> void:
		resets += 1
		calls.clear()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _make(p1: int, p2: int, ts: Dictionary = {}) -> Array:
	# [timeline, particle, a, b] — particle is first (registration order).
	var particle := StubTrack.new("particle", _seq)
	var a := StubTrack.new("a", _seq)
	var b := StubTrack.new("b", _seq)
	var tl = EffectTimelineClass.new()
	tl.setup(p1, p2, ts)
	tl.set_subsystems([particle, a, b])
	tl.start()
	return [tl, particle, a, b]


func _frames(track) -> Array:
	var out := []
	for c in track.calls:
		out.append(c[0])
	return out


func _ready() -> void:
	_test_start_gate()
	_test_first_tick_clamp_and_order()
	_test_accumulator_catchup()
	_test_phase_set()
	_test_time_scale()
	_test_null_skip()
	_test_reset()

	if _failed:
		print("[FAIL] EffectTimeline test")
	else:
		print("[PASS] EffectTimeline: order, accumulator+clamp, phase-set, time-scale, null-skip, start-gate, reset OK")
	get_tree().quit()


func _test_start_gate() -> void:
	_seq.clear()
	var particle := StubTrack.new("p", _seq)
	var tl = EffectTimelineClass.new()
	tl.setup(0, 0)
	tl.set_subsystems([particle])
	tl.tick(1.0)  # not started yet
	_check(particle.calls.is_empty(), "start gate: tick() before start() must no-op")
	_check(tl.effect_frame == 0, "start gate: effect_frame stays 0 before start()")


func _test_first_tick_clamp_and_order() -> void:
	_seq.clear()
	var r := _make(100, 200)  # big phase1 → frame 0 is phase1
	var tl = r[0]
	var particle = r[1]
	tl.tick(1.0)  # huge delta — first-tick clamp limits it to ONE step
	_check(particle.calls.size() == 1, "first-tick clamp: exactly 1 frame (got %d)" % particle.calls.size())
	_check(particle.calls[0][0] == 0, "first-tick clamp: first frame is 0")
	_check(_seq == [["particle", 0], ["a", 0], ["b", 0]],
		"registration order within a frame: got %s" % str(_seq))


func _test_accumulator_catchup() -> void:
	_seq.clear()
	var r := _make(100, 200)
	var tl = r[0]
	var particle = r[1]
	tl.tick(1.0)         # frame 0 (clamped)
	tl.tick(2.0 * STEP)  # catch up two frames: 1, 2
	_check(_frames(particle) == [0, 1, 2], "catch-up frames: got %s" % str(_frames(particle)))
	_check(tl.effect_frame == 3, "effect_frame after 3 frames == 3 (got %d)" % tl.effect_frame)
	tl.tick(STEP * 0.4)  # sub-step accumulation must not advance
	_check(_frames(particle) == [0, 1, 2], "sub-step delta does not advance a frame")


func _test_phase_set() -> void:
	_seq.clear()
	var r := _make(2, 4)  # phase1 [0,2), for-each [2,…), phase2 overlays at >=4
	var tl = r[0]
	var particle = r[1]
	tl.tick(1.0)         # frame 0
	tl.tick(5.0 * STEP)  # frames 1..5
	var expect := {
		0: [EffectPhase.PHASE1],
		1: [EffectPhase.PHASE1],
		2: [EffectPhase.PHASE_FOR_EACH],
		3: [EffectPhase.PHASE_FOR_EACH],
		4: [EffectPhase.PHASE_FOR_EACH, EffectPhase.PHASE2],
		5: [EffectPhase.PHASE_FOR_EACH, EffectPhase.PHASE2],
	}
	for c in particle.calls:
		var f: int = c[0]
		_check(c[1] == expect[f], "phase at frame %d: expected %s got %s" % [f, str(expect[f]), str(c[1])])


func _test_time_scale() -> void:
	_seq.clear()
	# The timeline owns time-modulation now (ADR-0014): a pattern-2 pacing curve of
	# pacing 4 yields factor BASE(2)/4 = 0.5 (half speed). phase1_duration 0 → the
	# effect is in for-each from frame 0. The factor is derived during the pump and
	# applies on the NEXT accumulation (one-frame lag); the phase1→for-each reset
	# edge forces BASE on the first for-each frame, so 0.5 lands after frame 1.
	var ts := {"flags": {"time_scale_pattern2": true}, "for_each": [4, 4, 4, 4, 4, 4, 4, 4]}
	var r := _make(0, 200, ts)
	var tl = r[0]
	var particle = r[1]
	tl.tick(1.0)   # first-tick clamp → frame 0 (factor 1.0; reset edge keeps it 1.0)
	tl.tick(STEP)  # factor still 1.0 → frame 1; AFTER frame 1 the factor becomes 0.5
	_check(_frames(particle) == [0, 1],
		"time-scale: priming frames 0,1 at full speed (got %s)" % str(_frames(particle)))
	tl.tick(STEP)  # delta * 0.5 = half a step → no new frame
	_check(_frames(particle) == [0, 1],
		"time-scale 0.5: half a step does not advance (got %s)" % str(_frames(particle)))
	tl.tick(STEP)  # + another half → one full step → frame 2
	_check(_frames(particle) == [0, 1, 2],
		"time-scale 0.5: two half-steps advance one frame (got %s)" % str(_frames(particle)))


func _test_null_skip() -> void:
	_seq.clear()
	var particle := StubTrack.new("particle", _seq)
	var b := StubTrack.new("b", _seq)
	var tl = EffectTimelineClass.new()
	tl.setup(100, 200)
	tl.set_subsystems([particle, null, b])  # a null in the middle
	tl.start()
	tl.tick(1.0)
	_check(particle.calls.size() == 1 and b.calls.size() == 1,
		"null-skip: non-null tracks advance, null is skipped without crashing")


func _test_reset() -> void:
	_seq.clear()
	var r := _make(100, 200)
	var tl = r[0]
	var particle = r[1]
	var a = r[2]
	var b = r[3]
	tl.tick(1.0)
	tl.tick(2.0 * STEP)
	tl.reset()
	_check(tl.effect_frame == 0, "reset: effect_frame back to 0 (got %d)" % tl.effect_frame)
	_check(particle.resets == 1 and a.resets == 1 and b.resets == 1,
		"reset: each track reset exactly once")
	tl.tick(1.0)  # first-tick clamp re-applies after reset
	_check(particle.calls.size() == 1 and particle.calls[0][0] == 0,
		"reset: clock restarts at frame 0 with the first-tick clamp")
