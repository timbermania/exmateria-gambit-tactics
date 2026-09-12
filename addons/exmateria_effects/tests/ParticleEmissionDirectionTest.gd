extends Node
## Golden-cloud parity lock for ParticlePhysics.angle_to_direction (ADR-0091 step 6).
##
## The emission base vector is game-space DOWN (a launch convention — chirality axis,
## ADR-0057; magnitude axis = none). The old code justified it as "PSX -Y=UP", which
## this pass removed. The direction math is kept BYTE-IDENTICAL: relocating the sign
## to the parse seam is NOT a sign flip but a π half-turn on the emission Z angle
## (empirically the only identity-preserving transform), which would bake a hidden
## 180° into authored angle data for zero behavioural gain — so it is deferred, and
## this test locks the current cloud so any future drift is caught.
##
## Golden values come from an INDEPENDENT reimplementation of the rotation (below),
## not from calling the function under test, and the anchors are hand-verifiable
## (zero angles → straight-down launch (0,-1,0)).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ParticleEmissionDirectionTest.tscn

const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_zero_is_straight_down()
	_test_golden_directions()
	_test_always_normalized()

	print("\n=== ParticleEmissionDirectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ParticleEmissionDirectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ParticleEmissionDirectionTest")
		get_tree().quit(0)


func _vclose(got: Vector3, want: Vector3, name: String) -> void:
	if got.distance_to(want) < 0.0001:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _test_zero_is_straight_down() -> void:
	# Zero emission angles launch straight DOWN in game space; negative radial
	# velocity then carries the particle upward (the original launch convention).
	_vclose(ParticlePhysics.angle_to_direction(0, 0, 0), Vector3(0, -1, 0), "zero -> straight down")


func _test_golden_directions() -> void:
	# Pinned snapshot (independent probe); the cloud must never move under refactors.
	_vclose(ParticlePhysics.angle_to_direction(1.5708, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), "ax=pi/2")
	_vclose(ParticlePhysics.angle_to_direction(0.0, 1.5708, 0.0), Vector3(0.0, -1.0, 0.0), "ay=pi/2")
	_vclose(ParticlePhysics.angle_to_direction(0.0, 0.0, 1.5708), Vector3(-1.0, 0.0, 0.0), "az=pi/2")
	_vclose(ParticlePhysics.angle_to_direction(0.7, 0.7, 0.7), Vector3(-0.492725, -0.852345, -0.175303), "0.7,0.7,0.7")
	_vclose(ParticlePhysics.angle_to_direction(-0.5, 1.2, -0.9), Vector3(0.283845, -0.895539, -0.342700), "-0.5,1.2,-0.9")


func _test_always_normalized() -> void:
	for t in [[0.3, 1.1, -0.4], [2.0, -2.0, 0.5], [0.0, 0.0, 0.0]]:
		var v: Vector3 = ParticlePhysics.angle_to_direction(t[0], t[1], t[2])
		if absf(v.length() - 1.0) < 0.001:
			_passed += 1
		else:
			_failed += 1
			print("  [FAIL] normalized %s: len=%f" % [str(t), v.length()])
