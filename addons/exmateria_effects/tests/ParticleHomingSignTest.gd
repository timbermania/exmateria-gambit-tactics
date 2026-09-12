extends Node
## TDD guard for ParticlePhysics homing — the SIGN of homing_strength selects the
## behaviour, and NEGATIVE strength must be honoured (repulsion / flee), not dropped.
##
## PSX ground truth (research/restore_context/HOMING_SYSTEM_ANALYSIS.md §2, §7):
##   homing_strength == 0  → simple physics (drag only, NO homing)
##   homing_strength != 0  → homing physics enabled
##   positive → ATTRACT toward target, negative → REPEL from target
## The gate is `!= 0`, not `> 0`. A `<= 0` gate silently collapses repulsion into
## "no homing" — the E142 emitter-15 bug: negative homing (raw -32) + ORIGIN target =
## a mild outward dispersal that `align_to_velocity` then orients the sprite along.
## With repulsion dropped, velocity stayed 0 and every sprite pointed +X (tail right).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleHomingSignTest.tscn

const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")

const ParticlePhysicsClass = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const ParticleClass = preload("res://addons/exmateria_effects/particles/Particle.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_negative_homing_repels_from_target()
	_test_positive_homing_attracts_toward_target()
	_test_zero_homing_no_force()

	print("\n=== ParticleHomingSignTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleHomingSignTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleHomingSignTest")
		get_tree().quit(0)


func _make_particle(pos: Vector3, strength: float) -> Particle:
	var p := ParticleClass.new()
	p.initialize(pos, Vector3.ZERO, 60, 0)
	p.inertia = 4096.0
	p.weight = 0.0
	p.drag = Vector3.ZERO
	p.acceleration = Vector3.ZERO
	p.homing_strength = strength
	p.homing_target = Vector3.ZERO   # ORIGIN
	p.homing_curve_index = -1        # fixed curve_factor = -128 (strong homing)
	return p


## A particle at +X with NEGATIVE homing toward the origin must be pushed in +X
## (AWAY from the origin) — repulsion. Regression for the `<= 0` gate that dropped it.
func _test_negative_homing_repels_from_target() -> void:
	var phys := ParticlePhysicsClass.new()
	phys.gravity = Vector3.ZERO
	var p := _make_particle(Vector3(10, 0, 0), -0.5)
	# Two ticks: frame 1 sets acceleration, frame 2 folds it into velocity.
	phys.update_particle_fixed(p)
	phys.update_particle_fixed(p)
	_assert_true(p.velocity.x > 0.0,
		"negative homing REPELS: particle at +X gains +X (outward) velocity, got %s" % str(p.velocity))


func _test_positive_homing_attracts_toward_target() -> void:
	var phys := ParticlePhysicsClass.new()
	phys.gravity = Vector3.ZERO
	var p := _make_particle(Vector3(10, 0, 0), 0.5)
	phys.update_particle_fixed(p)
	phys.update_particle_fixed(p)
	_assert_true(p.velocity.x < 0.0,
		"positive homing ATTRACTS: particle at +X gains -X (inward) velocity, got %s" % str(p.velocity))


## Zero strength is the genuine "no homing" case — drag path only, no pull/push.
func _test_zero_homing_no_force() -> void:
	var phys := ParticlePhysicsClass.new()
	phys.gravity = Vector3.ZERO
	var p := _make_particle(Vector3(10, 0, 0), 0.0)
	phys.update_particle_fixed(p)
	phys.update_particle_fixed(p)
	_assert_true(is_zero_approx(p.velocity.x) and is_zero_approx(p.velocity.y) and is_zero_approx(p.velocity.z),
		"zero homing applies no force, got %s" % str(p.velocity))


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
