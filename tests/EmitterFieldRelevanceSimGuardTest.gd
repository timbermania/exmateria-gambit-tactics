extends Node
## Real-sim guards for the EmitterFieldRelevance DEAD edges (ADR-0089 salience
## amendment). The project rule: an RE conclusion must be static-rooted AND
## dynamically validated — so each Dead edge the oracle encodes is proven here by
## setting the gate in the ACTUAL engine (ParticlePhysics / ActiveEmitter /
## EffectParticleRenderer / ParticleSubsystem) and asserting the gated field
## cannot move the output. If one of these fails, the inventory is lying and the
## oracle must be corrected — the guard is the source of truth, not the ADR.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EmitterFieldRelevanceSimGuardTest.tscn

const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const EffectCurve = ExMateriaEffects.EffectCurve
const EffectEmitter = ExMateriaEffects.EffectEmitter
const EffectData = ExMateriaEffects.EffectData
const ActiveEmitter = preload("res://addons/exmateria_effects/particles/ActiveEmitter.gd")
const ParticlePool = preload("res://addons/exmateria_effects/particles/ParticlePool.gd")
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")
const EffectParticleRenderer = preload("res://addons/exmateria_effects/render/EffectParticleRenderer.gd")
const ParticleSubsystem = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_guard_no_curve_deads_end_axis()
	_guard_homing_zero_deads_target_offset()
	_guard_homing_zero_deads_homing_blend()
	_guard_color_disabled_deads_color_curves()
	_guard_disabled_child_mode_deads_child_index()
	_guard_inertia_4096_is_not_a_clean_neutral()
	_guard_zero_velocity_deads_inertia()
	_guard_drag_is_a_velocity_source_not_a_consumer()
	_guard_gravity_revives_inertia()
	_guard_align_to_velocity_does_not_dead_launch_angle()
	_guard_velocity_inward_not_moot_when_radial_zero()
	_guard_outward_radial_zero_deads_launch_direction()
	_guard_inward_deads_launch_direction()
	_guard_skip_mode_deads_whole_velocity_family()

	print("\n=== EmitterFieldRelevanceSimGuardTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterFieldRelevanceSimGuardTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterFieldRelevanceSimGuardTest")
		get_tree().quit(0)


## EDGE: curve == none ⇒ the group's END axis is Dead.
## Proof against the real interpolators: with curve == null, interpolate_simple /
## _vec3 / _range all return the START value and never touch the end argument. So
## editing the end axis cannot change any spawned value — it is Dead.
func _guard_no_curve_deads_end_axis() -> void:
	# interpolate_simple: sweep the end value across extremes, result is pinned to start.
	var base := ParticlePhysics.interpolate_simple(5.0, -999.0, null, 3)
	var alt := ParticlePhysics.interpolate_simple(5.0, 999.0, null, 3)
	_assert_eq(base, 5.0, "interpolate_simple returns start when curve is null")
	_assert_eq(base, alt, "…and the end value cannot move it (end axis Dead)")

	# interpolate_vec3: same, per component.
	var vb := ParticlePhysics.interpolate_vec3(Vector3(1, 2, 3), Vector3(-9, -9, -9), null, 3)
	var va := ParticlePhysics.interpolate_vec3(Vector3(1, 2, 3), Vector3(9, 9, 9), null, 3)
	_assert_true(vb == Vector3(1, 2, 3), "interpolate_vec3 returns start when curve is null")
	_assert_true(vb == va, "…end vector cannot move it (end axis Dead)")

	# interpolate_range: with no curve the draw is over the START min/max only; a
	# fixed RNG makes the draw deterministic so we can compare end variations.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var r0 := ParticlePhysics.interpolate_range(4.0, 4.0, -100.0, -100.0, null, 3, rng)
	rng.seed = 12345
	var r1 := ParticlePhysics.interpolate_range(4.0, 4.0, 100.0, 100.0, null, 3, rng)
	_assert_eq(r0, 4.0, "interpolate_range draws from the start range when curve is null")
	_assert_eq(r0, r1, "…the end range cannot move it (end axis Dead)")

	# Positive control: WITH a curve, the end axis DOES move the result — proving the
	# gate is the curve's presence, not something else.
	var curve := EffectCurve.from_array([0.0, 1.0], 0)  # sample_by_frame: even→0, odd→1
	var live_a := ParticlePhysics.interpolate_simple(0.0, 10.0, curve, 1)  # curve_t = 1 → full end
	_assert_eq(live_a, 10.0, "with a curve the end axis is read (control: end is Live)")


## EDGE: homing_strength == 0 ⇒ target offset is Dead.
## Proof against ActiveEmitter._initialize_particle: it reads target_offset only
## inside `if not is_zero_approx(particle.homing_strength)`. So with homing zero,
## a spawned particle's homing_target stays at its initialize() default (ZERO)
## regardless of the emitter's target_offset — editing target_offset is inert.
func _guard_homing_zero_deads_target_offset() -> void:
	# homing = 0, big target_offset → target unread → homing_target stays ZERO.
	var p_off := _spawn_one(0.0, Vector3(5, 5, 5))
	_assert_true(p_off.homing_target == Vector3.ZERO,
		"homing 0: target_offset is unread, homing_target stays ZERO (Dead)")

	# Positive control: homing != 0 → target_offset IS read → homing_target moves.
	var p_on := _spawn_one(1.0, Vector3(5, 5, 5))
	_assert_true(p_on.homing_target != Vector3.ZERO,
		"homing set: target_offset is read (control: target offset Live)")

	# Sign control: negative homing (repel) also reads the target — the gate is != 0.
	var p_neg := _spawn_one(-1.0, Vector3(5, 5, 5))
	_assert_true(p_neg.homing_target != Vector3.ZERO,
		"negative homing still reads target_offset (gate is != 0, not > 0)")


## EDGE: homing_strength == 0 ⇒ the homing-blend curve is Dead.
## Proof against ParticlePhysics.update_particle_fixed: the homing path (the only
## reader of homing_curve_index) is skipped when is_zero_approx(homing_strength).
## So two particles that differ ONLY in homing_curve_index integrate identically.
func _guard_homing_zero_deads_homing_blend() -> void:
	var phys := ParticlePhysics.new()
	phys.effect_data = EffectData.new()
	# frame-0 sample 0.5 → blend value +0.5·255−128, distinct from the no-curve
	# default (−128), so assigning the blend curve visibly changes the homing path.
	phys.effect_data.curves.append(EffectCurve.from_array([0.5, 1.0], 0))

	var a := _homing_particle(0.0, 0)   # homing off, no blend curve
	var b := _homing_particle(0.0, 1)   # homing off, blend curve 0 assigned
	phys.update_particle_fixed(a)
	phys.update_particle_fixed(b)
	_assert_true(a.velocity == b.velocity and a.acceleration == b.acceleration,
		"homing 0: homing_curve_index cannot move output (blend Dead)")

	# Positive control: with homing != 0 the blend curve DOES change acceleration.
	var c := _homing_particle(2.0, 0)
	var d := _homing_particle(2.0, 1)
	phys.update_particle_fixed(c)
	phys.update_particle_fixed(d)
	_assert_true(c.acceleration != d.acceleration,
		"homing set: homing_curve_index moves acceleration (control: blend Live)")


## EDGE: colour enable (flags_lo bit 6) off ⇒ colour R/G/B are Dead.
## Proof against EffectParticleRenderer: _setup_emitter_caches only resolves the
## colour curve refs when flags["color_curve_enabled"] is true; otherwise it caches
## null and _compute_color_modulate returns white regardless of the colour_curves
## indices. So editing the colour curves is inert when the enable bit is off.
func _guard_color_disabled_deads_color_curves() -> void:
	var curve := EffectCurve.from_array([0.25, 0.75], 0)  # a non-white curve

	# Disabled: colour curves point at the curve, but the modulate is white.
	var r_off := EffectParticleRenderer.new()
	r_off.effect_data = _one_emitter_effect(false, curve)
	r_off._setup_emitter_caches()
	var p := Particle.new()
	p.emitter_index = 0
	p.age = 0
	var mod_off: Color = r_off._compute_color_modulate(p)
	_assert_true(mod_off.r == 1.0 and mod_off.g == 1.0 and mod_off.b == 1.0,
		"colour disabled: modulate is white, colour curves unread (Dead)")
	r_off.free()

	# Positive control: enabled → the curve drives the modulate (not white).
	var r_on := EffectParticleRenderer.new()
	r_on.effect_data = _one_emitter_effect(true, curve)
	r_on._setup_emitter_caches()
	var mod_on: Color = r_on._compute_color_modulate(p)
	_assert_true(mod_on.r != 1.0,
		"colour enabled: the colour curve drives the modulate (control: Live)")
	r_on.free()


## EDGE: a disabled child mode ⇒ that child-emitter index is Dead.
## Proof against the real ParticleSubsystem._process_particle_deaths: it only
## enqueues a child spawn when parent_config.is_child_death_enabled() (flags_lo
## bits 0-1 non-zero). We feed the mode through EmitterChannel's real bit→flag
## decode, drop a dead parent particle wired to a valid child index, and count
## whether the subsystem spawned. Disabled → no child (index Dead); enabled → child.
func _guard_disabled_child_mode_deads_child_index() -> void:
	_assert_eq(_child_spawns_on_death(0x00), 0, "death mode 0: no child spawns (index Dead)")
	_assert_eq(_child_spawns_on_death(0x01), 1, "death mode 1: the child spawns (index Live)")


## Run one real _process_particle_deaths with the parent's emitter_flags_lo set to
## `flags_lo` (decoded to the flag the subsystem reads), a dead parent particle
## (emitter 0) wired to child emitter 1. Returns how many NEW particles the
## subsystem spawned (the child emission).
func _child_spawns_on_death(flags_lo: int) -> int:
	var ed := EffectData.new()
	var parent := EffectEmitter.new()
	parent.index = 0
	parent.raw_data = {"emitter_flags_lo": flags_lo}
	EmitterChannel._recompute_flags(parent)  # real bit→flag decode (mirrors parse_effect.py)
	var child := EffectEmitter.new()
	child.index = 1
	child.particle_count_start = 1
	child.spawn_interval_start = 1
	ed.emitters.append(parent)
	ed.emitters.append(child)

	var sub := ParticleSubsystem.new()
	sub.initialize(ed, 16)

	# A dead parent particle wired to spawn child emitter 1 on death.
	var p := sub.particle_pool.acquire()
	p.emitter_index = 0
	p.child_emitter_on_death = 1
	p.position = Vector3.ZERO
	p.active = false  # dead → death path fires

	var before := sub.particle_pool.get_active_particles().size()
	sub._process_particle_deaths()
	var after := sub.particle_pool.get_active_particles().size()
	return after - before


## An EffectData with one emitter whose colour-curve enable flag is `enabled` and
## whose r/g/b colour curves all point at curve index 0.
func _one_emitter_effect(enabled: bool, curve: EffectCurve) -> EffectData:
	var ed := EffectData.new()
	var em := EffectEmitter.new()
	em.index = 0
	em.flags = {"color_curve_enabled": enabled}
	em.color_curves = {"r": 0, "g": 0, "b": 0}
	ed.emitters.append(em)
	ed.curves.append(curve)
	return ed


## REFUTED edge: the ADR guessed inertia's neutral is 4096 (×1.0 identity). The
## real ParticlePhysics.update_particle_fixed shows 4096 is identity ONLY when the
## particle-header inertia_threshold is 0; at the default 512 it decays velocity
## ×0.875. So no single inertia value is neutral independent of the header —
## inertia is never merely Inactive. Proven by running the real integrator.
func _guard_inertia_4096_is_not_a_clean_neutral() -> void:
	# Default threshold 512: inertia 4096 with zero accel DECAYS velocity (not identity).
	var phys := ParticlePhysics.new()
	phys.inertia_threshold = 512.0
	var p := _ballistic_particle(4096.0)
	phys.update_particle_fixed(p)
	_assert_true(p.velocity.x < 1.0 and p.velocity.x > 0.0,
		"inertia 4096 at threshold 512 decays velocity ×0.875 — NOT identity (4096-neutral refuted)")

	# Same inertia, threshold 0: NOW it is identity — proving neutrality depends on
	# the header field the oracle can't see, so there is no clean per-emitter neutral.
	var phys0 := ParticlePhysics.new()
	phys0.inertia_threshold = 0.0
	var q := _ballistic_particle(4096.0)
	phys0.update_particle_fixed(q)
	_assert_eq(q.velocity.x, 1.0,
		"same inertia at threshold 0 IS identity — neutrality is header-dependent, not 4096")


## EDGE: velocity ≡ 0 ⇒ inertia is Dead. Inertia only DECAYS an existing velocity, so with a
## particle at rest and no source of velocity (accel 0, drag 0, weight 0, homing 0), varying
## inertia across extremes cannot move the particle one unit over its whole life.
func _guard_zero_velocity_deads_inertia() -> void:
	var a := _rest_position_after(4096.0, Vector3.ZERO, 0.0, 40)
	var b := _rest_position_after(1.0, Vector3.ZERO, 0.0, 40)
	var c := _rest_position_after(0.0, Vector3.ZERO, 0.0, 40)
	_assert_eq(a, Vector3.ZERO, "a resting particle with no velocity source never moves (inertia 4096)")
	_assert_true(a == b and b == c, "…and inertia cannot move it at any value (Dead)")


## NOT an edge (drag is EXCLUDED from the gate): drag is a constant FORCE here — the engine does
## `acceleration += drag` each frame — so a non-zero drag creates velocity from REST. It is a
## velocity SOURCE, not a consumer; marking it Dead would be a lie. Proven: rest + drag moves,
## and once it moves, inertia matters again (so the zero-velocity gate must exclude drag ≠ 0).
func _guard_drag_is_a_velocity_source_not_a_consumer() -> void:
	var moved := _rest_position_after(4096.0, Vector3(0.1, 0.0, 0.0), 0.0, 40)
	_assert_true(moved.length() > 0.001, "a non-zero drag moves a resting particle — drag is a SOURCE")
	var with_hi := _rest_position_after(4096.0, Vector3(0.1, 0.0, 0.0), 0.0, 40)
	var with_lo := _rest_position_after(600.0, Vector3(0.1, 0.0, 0.0), 0.0, 40)
	_assert_true(with_hi != with_lo, "once drag creates velocity, inertia moves output again (gate excludes drag ≠ 0)")


## EDGE guard (conjunctivity): gravity is a velocity source too — a non-zero weight revives
## inertia, so the zero-velocity gate must require weight 0.
func _guard_gravity_revives_inertia() -> void:
	var with_hi := _rest_position_after(4096.0, Vector3.ZERO, 512.0, 40)
	var with_lo := _rest_position_after(600.0, Vector3.ZERO, 512.0, 40)
	_assert_true(with_hi.length() > 0.001, "a non-zero weight (gravity) moves a resting particle")
	_assert_true(with_hi != with_lo, "…and inertia moves output under gravity (gate excludes weight ≠ 0)")


## Simulate `frames` fixed steps of a particle starting AT REST (velocity 0, no acceleration,
## no homing) with the given inertia / drag / weight, at the default threshold — and return the
## final position. The test for the zero-velocity inertia gate.
func _rest_position_after(inertia: float, drag: Vector3, weight: float, frames: int) -> Vector3:
	var phys := ParticlePhysics.new()
	phys.inertia_threshold = 512.0
	var p := Particle.new()
	p.active = true
	p.velocity = Vector3.ZERO
	p.acceleration = Vector3.ZERO
	p.drag = drag
	p.weight = weight
	p.inertia = inertia
	p.homing_strength = 0.0
	for i in range(frames):
		phys.update_particle_fixed(p)
	return p.position


## REFUTED edge: does align_to_velocity (motion bit 1) dead the launch-direction
## angle? No — align_to_velocity is a RENDERER billboard rotation and never touches
## the spawned velocity. The launch angle drives velocity in ActiveEmitter
## regardless, so it stays Live. Proven: two launch angles → two velocities.
func _guard_align_to_velocity_does_not_dead_launch_angle() -> void:
	# Rotate about X (not Y — a Y rotation leaves the base DOWN launch vector invariant).
	var v_a := _spawn_velocity(Vector3(0.0, 0.0, 0.0))
	var v_b := _spawn_velocity(Vector3(PI / 2.0, 0.0, 0.0))
	_assert_true(v_a != v_b,
		"launch angle changes spawned velocity — align_to_velocity does not dead it (refuted)")


## REFUTED edge: does velocity_inward (flags_lo bit 4) go moot when radial == 0?
## Not unconditionally — with align_to_facing on, velocity_inward rotates the spawn
## POSITION by the caster facing even at radial 0. So toggling it still moves output;
## it is not a clean gate. Proven: same radial 0, toggling inward changes position.
func _guard_velocity_inward_not_moot_when_radial_zero() -> void:
	var pos_out := _spawn_position(false)  # align_to_facing on, inward OFF
	var pos_in := _spawn_position(true)    # align_to_facing on, inward ON → position rotated
	_assert_true(pos_out != pos_in,
		"velocity_inward rotates position at radial 0 (align_to_facing on) — not moot (refuted)")


## EDGE: Outward mode (neither flag) with radial provably 0 ⇒ launch direction +
## direction scatter are Dead. Proof against the OUTWARD branch of the 4-mode
## dispatch: velocity = angle_to_direction(base_angle) * radial_vel. With radial 0
## the product annihilates the computed direction, so the spawned velocity is ZERO
## for ANY launch angle — editing the direction cannot move the output.
func _guard_outward_radial_zero_deads_launch_direction() -> void:
	var v_a := _spawn_velocity_mode(Vector3(0.0, 0.0, 0.0), 0.0, {})
	var v_b := _spawn_velocity_mode(Vector3(PI / 2.0, 0.0, 0.0), 0.0, {})
	_assert_true(v_a == Vector3.ZERO and v_b == Vector3.ZERO,
		"Outward radial 0: velocity is ZERO for any launch angle (direction × 0 annihilated)")

	# Positive control: radial > 0 → the launch angle DOES move velocity (direction Live).
	var live_a := _spawn_velocity_mode(Vector3(0.0, 0.0, 0.0), 3.0, {})
	var live_b := _spawn_velocity_mode(Vector3(PI / 2.0, 0.0, 0.0), 3.0, {})
	_assert_true(live_a != live_b,
		"Outward radial > 0: launch angle moves velocity (control: direction Live)")


## EDGE: Inward mode (velocity_inward only) ⇒ launch direction + direction scatter
## are Dead always. Proof against the INWARD branch: velocity is built from
## (base_pos − final_pos) × radial_vel — the launch angle is omitted from the
## formula entirely, so varying it cannot move the spawned velocity.
func _guard_inward_deads_launch_direction() -> void:
	var v_a := _spawn_velocity_mode(Vector3(0.0, 0.0, 0.0), 3.0, {"velocity_inward": true})
	var v_b := _spawn_velocity_mode(Vector3(PI / 2.0, 0.0, 0.0), 3.0, {"velocity_inward": true})
	_assert_true(v_a == v_b,
		"Inward: launch angle cannot move velocity — direction omitted from (toward center) × speed")


## EDGE: Skip mode (align_to_facing only, inward off) ⇒ the whole velocity family
## (launch direction, direction scatter, outward speed) is Dead. Proof against the
## SKIP branch: velocity = Vector3.ZERO unconditionally, so neither the launch angle
## NOR the radial speed can move the output — no motion at all.
func _guard_skip_mode_deads_whole_velocity_family() -> void:
	var v_a := _spawn_velocity_mode(Vector3(0.0, 0.0, 0.0), 0.0, {"align_to_facing": true})
	var v_b := _spawn_velocity_mode(Vector3(PI / 2.0, 0.0, 0.0), 5.0, {"align_to_facing": true})
	_assert_true(v_a == Vector3.ZERO and v_b == Vector3.ZERO,
		"Skip: velocity is ZERO for any launch angle AND any outward speed (whole family Dead)")


## Spawn one particle through the REAL ActiveEmitter with a chosen launch angle,
## radial speed, and velocity-mode flags; return its spawned velocity. Spread stays
## zero so the mode's velocity math is the only variable under test.
func _spawn_velocity_mode(angle: Vector3, radial: float, flags: Dictionary) -> Vector3:
	var cfg := EffectEmitter.new()
	cfg.index = 0
	cfg.velocity_base_angle_start = angle
	cfg.velocity_base_angle_end = angle
	cfg.radial_velocity_min_start = radial
	cfg.radial_velocity_max_start = radial
	cfg.radial_velocity_min_end = radial
	cfg.radial_velocity_max_end = radial
	cfg.flags = flags
	return _spawn_with(cfg, 0.0).velocity


## A particle moving +X with zero acceleration/drag, for the inertia identity test.
func _ballistic_particle(inertia: float) -> Particle:
	var p := Particle.new()
	p.active = true
	p.velocity = Vector3(1, 0, 0)
	p.acceleration = Vector3.ZERO
	p.drag = Vector3.ZERO
	p.weight = 0.0
	p.inertia = inertia
	p.homing_strength = 0.0
	return p


## Spawn one particle through the real ActiveEmitter with a given launch angle
## (radial fixed non-zero so velocity is non-zero); return its velocity.
func _spawn_velocity(angle: Vector3) -> Vector3:
	var cfg := EffectEmitter.new()
	cfg.index = 0
	cfg.velocity_base_angle_start = angle
	cfg.velocity_base_angle_end = angle
	cfg.radial_velocity_min_start = 3.0
	cfg.radial_velocity_max_start = 3.0
	cfg.radial_velocity_min_end = 3.0
	cfg.radial_velocity_max_end = 3.0
	cfg.flags = {"align_to_velocity": true}  # renderer flag — must not affect velocity
	return _spawn_with(cfg, 0.0).velocity


## Spawn one particle with align_to_facing on and radial 0, toggling velocity_inward;
## return its position. A non-zero base position + caster facing exposes the
## position rotation that is_unit_oriented (inward AND align_to_facing) applies.
func _spawn_position(inward: bool) -> Vector3:
	var cfg := EffectEmitter.new()
	cfg.index = 0
	cfg.position_start = Vector3(1, 0, 0)
	cfg.position_end = Vector3(1, 0, 0)
	cfg.radial_velocity_min_start = 0.0
	cfg.radial_velocity_max_start = 0.0
	cfg.flags = {"align_to_facing": true, "velocity_inward": inward}
	return _spawn_with(cfg, PI / 2.0).position


## Spawn a single particle through the REAL ActiveEmitter with a given homing
## strength and target offset; return the initialized particle.
func _spawn_one(homing: float, target_offset: Vector3) -> Particle:
	var cfg := EffectEmitter.new()
	cfg.index = 0
	cfg.homing_strength_min_start = homing
	cfg.homing_strength_max_start = homing
	cfg.homing_strength_min_end = homing
	cfg.homing_strength_max_end = homing
	cfg.target_offset_start = target_offset
	cfg.target_offset_end = target_offset
	cfg.particle_count_start = 1
	cfg.particle_count_end = 1
	var p := _spawn_with(cfg, 0.0)
	return p


## Run ActiveEmitter._initialize_particle with a fully-built config and a caster
## facing angle; return the spawned particle. Anchors default to origin.
func _spawn_with(cfg: EffectEmitter, facing: float) -> Particle:
	var ae := ActiveEmitter.new()
	var pool := ParticlePool.new(8)
	var phys := ParticlePhysics.new()
	ae.initialize(cfg, EffectData.new(), pool, phys, 120)
	ae.anchor_target = Vector3.ZERO
	ae.caster_facing_angle = facing
	var p := Particle.new()
	ae._initialize_particle(p)
	return p


## A particle primed for the physics velocity update: nonzero velocity + drag so
## the two integration paths (drag vs homing blend) are distinguishable.
func _homing_particle(homing: float, curve_index: int) -> Particle:
	var p := Particle.new()
	p.active = true
	p.velocity = Vector3(1, 0, 0)
	p.acceleration = Vector3(0.1, 0, 0)
	p.drag = Vector3(0.02, 0, 0)
	p.inertia = 4096.0
	p.homing_strength = homing
	p.homing_curve_index = curve_index
	p.homing_target = Vector3(10, 0, 0)
	return p


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
