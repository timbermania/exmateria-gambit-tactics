extends Node
## Deterministic seek pump on EffectTimeline (ADR-0070 / CONTEXT "Playhead / scrub").
## The Effect Studio scrubs by seeking the live clock to an arbitrary frame, and
## that seek must be **frame-exact** and reproduce the identical subsystem state —
## NOT wall-clock `tick(delta)` (whose accumulator + one-frame time-mod lag drift).
## Contract under test (stub tracks, pure GDScript):
##   - seek(N) leaves effect_frame == N;
##   - seek(N) pumps advance() exactly the same (frame, phase) sequence as N
##     single-frame ticks — forward from the current frame;
##   - a backward seek reset()s (each track reset) then re-pumps from 0;
##   - reset() re-applies the stored per-instance RNG seed (deterministic replay).

const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const EffectPhase = ExMateriaEffects.EffectPhase

const STEP := 1.0 / 30.0

var _failed := false


class StubTrack:
	var calls: Array = []      # [frame, ...]
	var resets: int = 0
	func advance(frame: int, _phase) -> void:
		calls.append(frame)
	func reset() -> void:
		resets += 1
		calls.clear()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _make(p1: int, p2: int) -> Array:
	var track := StubTrack.new()
	var tl = EffectTimelineClass.new()
	tl.setup(p1, p2)
	tl.set_subsystems([track])
	tl.start()
	return [tl, track]


func _ready() -> void:
	_test_seek_lands_on_frame()
	_test_seek_matches_sequential_ticks()
	_test_forward_seek_pumps_only_delta()
	_test_backward_seek_resets_and_repumps()
	_test_same_frame_seek_is_a_noop()
	_test_rescrub_refolds_the_current_frame()
	_test_reset_reseeds_rng()

	if _failed:
		print("[FAIL] EffectSeek test")
	else:
		print("[PASS] EffectSeek: frame-exact seek, forward-pump, backward reset+repump, rng re-seed")
	get_tree().quit()


func _test_seek_lands_on_frame() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	tl.seek(17)
	_check(tl.effect_frame == 17, "seek(17) → effect_frame == 17 (got %d)" % tl.effect_frame)


## seek(N) from 0 must pump the identical frame sequence as N single-frame ticks.
func _test_seek_matches_sequential_ticks() -> void:
	# Reference: N sequential fixed ticks (frames 0..N-1).
	var ref := _make(3, 6)
	var ref_tl = ref[0]
	var ref_track = ref[1]
	ref_tl.tick(1.0)              # frame 0 (first-tick clamp)
	for _i in range(11):
		ref_tl.tick(STEP)        # frames 1..11
	# Seek path: seek straight to 12.
	var s := _make(3, 6)
	var s_tl = s[0]
	var s_track = s[1]
	s_tl.seek(12)
	_check(s_track.calls == ref_track.calls,
		"seek(12) advance-sequence matches 12 sequential ticks:\n  seek=%s\n  tick=%s" % [
			str(s_track.calls), str(ref_track.calls)])
	_check(s_tl.effect_frame == 12, "seek(12) leaves effect_frame 12")


func _test_forward_seek_pumps_only_delta() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	var track = r[1]
	tl.seek(5)
	track.calls.clear()
	tl.seek(9)   # forward from 5 → should pump exactly frames 5,6,7,8
	_check(track.calls == [5, 6, 7, 8],
		"forward seek pumps only the delta (got %s)" % str(track.calls))


func _test_backward_seek_resets_and_repumps() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	var track = r[1]
	tl.seek(10)
	tl.seek(4)   # backward → reset + re-pump from 0
	_check(track.resets >= 1, "backward seek reset the track")
	_check(track.calls == [0, 1, 2, 3],
		"backward seek re-pumps from 0 to target (got %s)" % str(track.calls))
	_check(tl.effect_frame == 4, "backward seek lands on 4 (got %d)" % tl.effect_frame)


## A re-seek to the CURRENT frame folds nothing — the trap the Studio's post-edit
## re-fold fell into (a folded channel like camera never re-showed the edit). This
## PINS the no-op so `rescrub()` (below) is the deliberate escape, not an accident.
func _test_same_frame_seek_is_a_noop() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	var track = r[1]
	tl.seek(7)
	track.calls.clear()
	tl.seek(tl.effect_frame)   # seek(7) while already at 7 → nothing pumps
	_check(track.calls.is_empty(),
		"a same-frame seek folds nothing (got %s)" % str(track.calls))
	_check(track.resets == 0, "a same-frame seek does not reset")


## rescrub() re-folds the CURRENT frame in place: reset() + re-pump from 0 to the
## current effect_frame, so a data edit that only shows after a re-fold (folded
## channels — camera framing) is recomputed. Distinct from seek(effect_frame)'s no-op.
func _test_rescrub_refolds_the_current_frame() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	var track = r[1]
	tl.seek(7)                 # pumps 0..6, lands at 7
	track.calls.clear()
	tl.rescrub()
	_check(track.resets >= 1, "rescrub resets before re-pumping")
	_check(track.calls == [0, 1, 2, 3, 4, 5, 6],
		"rescrub re-pumps 0..6 to re-fold frame 7 (got %s)" % str(track.calls))
	_check(tl.effect_frame == 7, "rescrub lands back on the same frame (got %d)" % tl.effect_frame)


func _test_reset_reseeds_rng() -> void:
	var r := _make(100, 200)
	var tl = r[0]
	var rng := RandomNumberGenerator.new()
	tl.set_rng(rng, 4242)
	# Consume the rng, then reset — the seed must be re-applied so the next draw
	# reproduces the first draw (deterministic in-instance replay).
	rng.seed = 4242
	var first := rng.randf()
	rng.randf()  # advance the stream
	tl.reset()
	_check(rng.randf() == first,
		"reset() re-seeds the instance RNG so the stream replays identically")
