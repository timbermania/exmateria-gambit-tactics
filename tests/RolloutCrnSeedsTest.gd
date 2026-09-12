extends Node
# test-kind: logic
# seeded-break: drop 1 from the horizon term of `crn_min_separation` in src/gpu/RolloutHarness.gd:85 (`+ maxi(0, horizon) - 1`) — the off-by-one the arms exist to catch; 'separation at U=16 H=300 should be 15300', 'a 1-unit battle consumes exactly H integers', the MUST-NOT-share boundary arm and all three generated-seed disjointness asserts red (6 total), while the MUST-collide side of the boundary stays green because a too-tight separation still collides

## Pure common-random-number seed-spacing test (#895, §7). No GPU.
##
## §7 uses the SAME M seeds across all K candidates so that luck cancels in the
## comparison and only the gambit edit remains. That works only if the M seeds
## themselves draw on disjoint numbers — and the shader's RNG makes that a real
## constraint rather than a formality: `rand_int` in `combat_common.glslinc` is a
## stateless hash of `battle_seed + unit_id * 1000 + tick`, so two nearby seeds
## index into each other's stream and the replicates silently stop being
## independent.
##
## 🔴 THE ARMS DO NOT TEST THE FORMULA AGAINST ITSELF. `crn_min_separation` is a
## claim about the hash's INPUTS, so each arm below builds the actual input set
## `{S + u * 1000 + t}` for two battles and intersects them. A test that only
## asserted `seeds_are_disjoint(crn_seeds(...))` would pass for any pair of
## functions that agreed with each other, including two that were both wrong.
##
## The boundary is asserted from both sides — one below the separation MUST
## collide, and exactly the separation MUST NOT. An off-by-one here spaces the
## seeds one integer too tightly and every rollout comparison carries a bias no
## downstream test can see.

const U := 16     # ADR-0237 dec. 5: the ENTD's 16 slots are the structural worst case
const H := 300    # §7's starting horizon

var _failed := false


func _ready() -> void:
	_test_separation_formula()
	_test_boundary_is_exact()
	_test_generated_seeds_are_disjoint()
	_test_detector_rejects_a_tight_set()
	if _failed:
		print("[FAIL] RolloutCrnSeeds test")
	else:
		print("[PASS] RolloutCrnSeeds: separation matches the hash's own inputs, boundary exact both sides")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


## Every integer `rand_int` can hash for one battle at this shape.
func _inputs(seed_value: int, units: int, horizon: int) -> Dictionary:
	var out := {}
	for u in range(units):
		for t in range(horizon):
			out[seed_value + u * RolloutHarness.RNG_UNIT_STRIDE + t] = true
	return out


func _shares_a_draw(seed_a: int, seed_b: int, units: int, horizon: int) -> bool:
	var a := _inputs(seed_a, units, horizon)
	for key in _inputs(seed_b, units, horizon):
		if a.has(key):
			return true
	return false


func _test_separation_formula() -> void:
	_expect(RolloutHarness.crn_min_separation(U, H) == (U - 1) * 1000 + H,
		"separation at U=%d H=%d should be %d, got %d" % [
			U, H, (U - 1) * 1000 + H, RolloutHarness.crn_min_separation(U, H)])
	# A one-unit battle still consumes H integers.
	_expect(RolloutHarness.crn_min_separation(1, H) == H,
		"a 1-unit battle consumes exactly H integers")


## The tight arm. Small U so the input sets stay cheap to build, and the same
## clustered structure the real shape has (H below the 1000-wide unit stride).
func _test_boundary_is_exact() -> void:
	var units := 4
	var horizon := 50
	var sep := RolloutHarness.crn_min_separation(units, horizon)
	var base := 100_000

	_expect(_shares_a_draw(base, base + sep - 1, units, horizon),
		"seeds %d apart MUST share a draw — otherwise the separation is larger than it needs to be" % (sep - 1))
	_expect(not _shares_a_draw(base, base + sep, units, horizon),
		"seeds %d apart must NOT share a draw — the separation is too small" % sep)

	# And the detector agrees with the ground truth at both.
	var tight := PackedInt32Array([base, base + sep - 1])
	var exact := PackedInt32Array([base, base + sep])
	_expect(not RolloutHarness.seeds_are_disjoint(tight, units, horizon),
		"seeds_are_disjoint accepted a colliding pair")
	_expect(RolloutHarness.seeds_are_disjoint(exact, units, horizon),
		"seeds_are_disjoint rejected a provably disjoint pair")


func _test_generated_seeds_are_disjoint() -> void:
	var seeds := RolloutHarness.crn_seeds(4, U, H)
	_expect(seeds.size() == 4, "crn_seeds(4) returned %d seeds" % seeds.size())
	_expect(RolloutHarness.seeds_are_disjoint(seeds, U, H),
		"crn_seeds produced a set its own detector rejects")
	# Ground truth, pairwise, at the real shape — the arm that would catch a
	# stride computed from the wrong axis.
	for i in range(seeds.size()):
		for j in range(i + 1, seeds.size()):
			_expect(not _shares_a_draw(seeds[i], seeds[j], U, H),
				"generated seeds %d and %d share a draw at U=%d H=%d" % [seeds[i], seeds[j], U, H])


## The M seeds must be spaced for the shape they will actually run at. A set
## generated for a short horizon and then run long is exactly the mistake the
## detector exists to catch, so it must catch it.
func _test_detector_rejects_a_tight_set() -> void:
	var short_seeds := RolloutHarness.crn_seeds(4, U, 10)
	_expect(RolloutHarness.seeds_are_disjoint(short_seeds, U, 10),
		"seeds generated for H=10 should be disjoint at H=10")
	_expect(not RolloutHarness.seeds_are_disjoint(short_seeds, U, H),
		"seeds generated for H=10 must be REJECTED when the beat runs H=%d" % H)
	# Same trap on the other axis: a fleet whose battles hold more unit slots.
	var narrow := RolloutHarness.crn_seeds(4, 4, H)
	_expect(not RolloutHarness.seeds_are_disjoint(narrow, U, H),
		"seeds generated for U=4 must be REJECTED at U=%d" % U)
