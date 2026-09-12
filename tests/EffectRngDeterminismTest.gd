extends Node
## Per-instance RNG determinism (ADR-0070). The effect sim must replay
## bit-for-bit within one instance so the Effect Studio can scrub the playhead
## back and forth without the particle cloud shimmering. This drives the RNG
## seam at two levels:
##   1. ParticlePhysics stochastic helpers accept a seeded RandomNumberGenerator
##      (same seed → identical draw; null → global fallback, unchanged behaviour).
##   2. A real ParticleSubsystem, pumped through the EffectTimeline with a seeded
##      instance RNG, produces the identical particle cloud across
##      reset()→re-seed→replay.
## Pure GDScript / no GPU (ParticleSubsystem is RD-free); loads a real effect dir.

const ParticlePhysicsClass = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const ParticleSubsystemClass = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")
const CameraSubsystemClass = preload("res://addons/exmateria_effects/subsystem/CameraSubsystem.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const EffectPhase = ExMateriaEffects.EffectPhase

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


const STEP := 1.0 / 30.0


func _ready() -> void:
	_test_physics_helpers_take_seeded_rng()
	_test_subsystem_replay_is_deterministic()
	_test_camera_shake_honours_seeded_rng()
	_test_scrub_reproduces_cloud()

	if _failed:
		print("[FAIL] EffectRngDeterminism test")
	else:
		print("[PASS] EffectRngDeterminism: seeded RNG pins physics helpers, full particle cloud, and camera shake")
	get_tree().quit()


func _rng(seed_val: int):
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _test_physics_helpers_take_seeded_rng() -> void:
	var base := Vector3(0, -1, 0)
	var spread := Vector3(0.5, 0.5, 0.5)

	# Same seed → identical cone direction (reproducible).
	var a := ParticlePhysicsClass.random_cone_direction(base, spread, _rng(1234))
	var b := ParticlePhysicsClass.random_cone_direction(base, spread, _rng(1234))
	_check(a == b, "same-seed cone direction reproducible: %s vs %s" % [a, b])

	# Different seed → different direction (the rng is actually consumed).
	var c := ParticlePhysicsClass.random_cone_direction(base, spread, _rng(9999))
	_check(a != c, "different-seed cone direction differs")

	# null rng → global fallback, still a valid (finite, unit-ish) direction.
	var d := ParticlePhysicsClass.random_cone_direction(base, spread, null)
	_check(d.is_finite(), "null rng falls back to global randf without crashing")

	# interpolate_range with no curve draws from the rng: same seed → same value.
	var r1 := ParticlePhysicsClass.interpolate_range(0.0, 10.0, 0.0, 10.0, null, 0, _rng(42))
	var r2 := ParticlePhysicsClass.interpolate_range(0.0, 10.0, 0.0, 10.0, null, 0, _rng(42))
	_check(r1 == r2, "same-seed interpolate_range reproducible: %f vs %f" % [r1, r2])


# --- Full-cloud determinism (the ADR-0070 oracle) ------------------------------

## Build a real ParticleSubsystem for `effect_dir`, seed its instance RNG to
## `seed_val`, pump it through the EffectTimeline for `frames` fixed frames, and
## return the snapshot of every active particle's position. Same seed →
## identical snapshot; the whole point of the deterministic-replay change.
func _run_cloud(effect_dir: String, seed_val: int, frames: int) -> Array:
	var data = EffectDataClass.load_from_directory(effect_dir)
	if data == null:
		return []
	var mgr = ParticleSubsystemClass.new()
	mgr.rng = _rng(seed_val)
	mgr.initialize(data, 512)
	mgr.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var tl = EffectTimelineClass.new()
	var p1d := 0
	var p2s := 0
	if data.timeline:
		p1d = data.timeline.phase1_duration
		p2s = p1d + data.timeline.phase2_delay
	tl.setup(p1d, p2s, data.time_scale)
	tl.set_subsystems([mgr])
	mgr.timeline = tl
	tl.start()
	for _i in range(frames):
		tl.tick(STEP)
	var snap: Array = []
	for p in mgr.get_active_particles():
		snap.append(p.position)
	return snap


## Find the first effect that actually spawns a non-trivial, spread-varied cloud
## so the determinism assertion has teeth (an effect with zero spread would be
## deterministic even on the global RNG). Returns "" if none in the probe set.
func _find_stochastic_effect(frames: int) -> String:
	for i in range(0, 40):
		var dir := "res://assets/effects/E%03d" % i
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var snap := _run_cloud(dir, 1, frames)
		if snap.size() < 8:
			continue
		# Require positional variance — otherwise the cloud is fixed regardless of RNG.
		var spread := 0.0
		for p in snap:
			spread += (p - snap[0]).length()
		if spread > 0.01:
			return dir
	return ""


func _test_subsystem_replay_is_deterministic() -> void:
	var frames := 45
	var dir := _find_stochastic_effect(frames)
	_check(dir != "", "found a stochastic effect to exercise (else the test is vacuous)")
	if dir == "":
		return

	var a := _run_cloud(dir, 777, frames)
	var b := _run_cloud(dir, 777, frames)
	_check(a.size() == b.size(), "same-seed cloud has same particle count (%d vs %d)" % [a.size(), b.size()])
	var same := a.size() == b.size()
	if same:
		for i in range(a.size()):
			if a[i] != b[i]:
				same = false
				break
	_check(same, "%s: same-seed replay reproduces the identical particle cloud" % dir)

	# The seed must actually matter — a different seed should move the cloud.
	var c := _run_cloud(dir, 888, frames)
	var differs := c.size() != a.size()
	if not differs:
		for i in range(a.size()):
			if a[i] != c[i]:
				differs = true
				break
	_check(differs, "%s: a different seed produces a different cloud (RNG is consumed)" % dir)


## Camera SHAKE must be deterministic under the instance RNG too, so scrubbing
## reproduces the same jitter. Exercise one shake frame through the instance seam.
func _shake_once(seed_val: int) -> Vector3:
	var cam = CameraSubsystemClass.new()
	cam.rng = _rng(seed_val)
	cam.angle_state = "SHAKE_DIRECT"
	cam.angle_to = Vector3.ZERO
	cam.angle_shake_amp = Vector3(10, 10, 10)
	cam.angle_total = 100
	cam._advance_angle()
	return cam.current_angles


func _test_camera_shake_honours_seeded_rng() -> void:
	_check(_shake_once(5) == _shake_once(5), "same-seed camera shake reproducible")
	_check(_shake_once(5) != _shake_once(6), "different-seed camera shake differs")


# --- The scrub gesture (backward seek must reproduce the frame) ----------------

## Build a real subsystem+timeline with a seeded instance RNG registered for
## reset re-seeding, apply the `seek_path` (a sequence of seek targets, the last
## being where we snapshot), and return the resulting particle cloud.
func _seek_cloud(effect_dir: String, seed_val: int, seek_path: Array) -> Array:
	var data = EffectDataClass.load_from_directory(effect_dir)
	if data == null:
		return []
	var r = _rng(seed_val)
	var mgr = ParticleSubsystemClass.new()
	mgr.rng = r
	mgr.initialize(data, 512)
	mgr.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var tl = EffectTimelineClass.new()
	var p1d := 0
	var p2s := 0
	if data.timeline:
		p1d = data.timeline.phase1_duration
		p2s = p1d + data.timeline.phase2_delay
	tl.setup(p1d, p2s, data.time_scale)
	tl.set_subsystems([mgr])
	tl.set_rng(r, seed_val)   # so a backward seek's reset() re-seeds
	mgr.timeline = tl
	tl.start()
	for target in seek_path:
		tl.seek(int(target))
	var snap: Array = []
	for p in mgr.get_active_particles():
		snap.append(p.position)
	return snap


func _clouds_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _test_scrub_reproduces_cloud() -> void:
	var n := 45
	var dir := _find_stochastic_effect(n)
	if dir == "":
		return   # already flagged by the replay test

	# Seek straight to N vs. scrub forward→back→forward and land on N again.
	var direct := _seek_cloud(dir, 20260713, [n])
	var scrubbed := _seek_cloud(dir, 20260713, [n, 2, n])
	_check(_clouds_equal(direct, scrubbed),
		"%s: scrubbing back to frame 2 and forward to %d reproduces the exact cloud" % [dir, n])
