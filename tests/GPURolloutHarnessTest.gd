extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: skip the post-beat restore in src/gpu/RolloutHarness.gd:200 (`var restored := _sim.restore_battle(_live_battle, pristine)` -> `:= true`), which is precisely the 'wrong, partial, or skipped' restore the header names — the 'battle' and 'results' slices both diverge at their first differing int, 'slot 0 still carries the rollout seed 1' reds, and the after-every-arm re-check reds too (6 total). The fleet-clock positive control stays green, which is what shows a harness that ran ZERO ticks could not have passed this by doing nothing

## `RolloutHarness` end to end on a real fleet (#895, §7).
##
## The harness's whole contract is that a thinking beat is INVISIBLE to the
## battle it forks from. `step_tick` dispatches over every battle in the batch —
## there is no per-battle active mask — so running a 60-tick horizon carries the
## LIVE battle 60 ticks forward too, and only `restore_battle` puts it back. If
## that restore is wrong, partial, or skipped, the player's battle silently jumps
## into a future nobody played.
##
## PASS: after a beat, battle 0 is BIT-IDENTICAL across all four snapshot slices
##       (battle image, cooldowns, gambits, results); the fleet slots really ran
##       the horizon, really carry their assigned CRN seed, and really carry
##       their assigned candidate; the same candidate under the same seed in two
##       different slots produces the identical result record; and the refusal
##       paths refuse without disturbing battle 0.
## FAIL: any of those. The bit-identity arm is the one that matters — a beat that
##       "worked" but left the live battle 60 ticks on has done more damage than
##       one that returned nothing.
##
## ⚠️ THE IDENTITY ARM READS THE BUFFER, NOT A SUMMARY. Map #886's own lesson
## (ADR-0245): "the queue moved" is not evidence a turn was spent, and a state
## check that samples a derived number can pass while the underlying bytes are
## wrong. `snapshot_battle` is the raw four-slice read, so comparing two of them
## compares the state itself.
##
## Small on purpose: 8 battles x 4 unit slots. Fleet size is not what this
## proves — ADR-0237 measured cost, and a suite that allocates a 256-battle fleet
## on a shared box loses its Vulkan device instead of failing an assertion.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/GPURolloutHarnessTest.tscn

const FLEET_BATTLES := 8        # K=4 candidates x M=2 seeds
const FLEET_UNITS := 4          # 2v2 — teams split at the midpoint
const K := 4
const M := 2
const HORIZON := 60             # ticks per rollout; a full H=300 buys nothing here
const PREFORK := 40             # advance the live battle first — §7 forks MID-battle
const ACTOR := 2                # a team-1 unit: the enemy is the one that thinks

var _failed := false
var _sim: GPUBatchSimulator = null
var _cells: Array = []


func get_test_name() -> String:
	return "GPU Rollout Harness"


func _ready() -> void:
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here, then stored (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_fail("map has no lattice")
		_finish()
		return

	_collect_cells()
	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if not df:
		_fail("no distance field")
		_finish()
		return
	if _cells.size() < FLEET_UNITS:
		_fail("map has %d walkable cells, needs %d" % [_cells.size(), FLEET_UNITS])
		_finish()
		return

	_sim = GPUBatchSimulator.new()
	if not _sim.initialize(lattice, df, FLEET_BATTLES, FLEET_UNITS):
		_sim.cleanup()
		_fail("could not initialize a %d-battle simulator (VRAM?)" % FLEET_BATTLES)
		_finish()
		return

	_run_arms()

	_sim.cleanup()
	if _failed:
		print("[FAIL] GPURolloutHarness")
	else:
		print("[PASS] GPURolloutHarness: battle 0 bit-identical after a beat, fleet ran H, CRN slots agree, refusals refuse")
	_finish()


func _process(_delta):
	pass


func _fail(msg: String) -> void:
	_failed = true
	print("[FAIL] %s" % msg)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _collect_cells() -> void:
	var cells: Array = []
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0:
			continue
		if c.impassable or c.pass_through_only:
			continue
		cells.append(c.grid)
	cells.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	_cells = cells


func _unit_cfg(seat: int, team: int) -> Dictionary:
	return {
		"name": "%s%d" % ["P" if team == 0 else "E", seat],
		"hp": 200, "max_hp": 200, "pa": 12, "ma": 10, "wp": 6,
		"brave": 60, "faith": 60, "mp": 200, "max_mp": 200,
		"speed": 8, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"c_ev": 10, "s_ev": 15, "w_ev": 10,
		"body_sprite_id": 0x02 if team == 0 else 0x05,
	}


## Seat a real 2v2 and walk it PREFORK ticks, so the beat forks a battle whose
## units are already engaged — §7's actual case, and the expensive regime
## (ADR-0237 dec. 6).
func _seat_live_battle() -> void:
	var per_team := FLEET_UNITS / 2
	var team0: Array = []
	var team1: Array = []
	for i in range(per_team):
		team0.append(_build_gpu_config(_cells[i], _unit_cfg(i, 0)))
		team1.append(_build_gpu_config(_cells[_cells.size() - 1 - i], _unit_cfg(i, 1)))
	_sim.set_battle_units(0, team0, team1, 4242)
	for i in range(FLEET_UNITS):
		_sim.set_unit_gambits(0, i, [make_attack_gambit()])
	_sim.step_tick(PREFORK)


func _snapshots_equal(a: Dictionary, b: Dictionary, label: String) -> void:
	for slice_name in ["battle", "cooldowns", "gambits", "results"]:
		var lhs: PackedInt32Array = a.get(slice_name, PackedInt32Array())
		var rhs: PackedInt32Array = b.get(slice_name, PackedInt32Array())
		if lhs == rhs:
			continue
		var first := -1
		for i in range(mini(lhs.size(), rhs.size())):
			if lhs[i] != rhs[i]:
				first = i
				break
		_fail("%s: the '%s' slice changed (sizes %d/%d, first differing int at %d)" % [
			label, slice_name, lhs.size(), rhs.size(), first])


func _run_arms() -> void:
	_seat_live_battle()
	var before: Dictionary = _sim.snapshot_battle(0)
	var before_tick := _sim.get_battle_tick(0)
	_expect(before_tick == PREFORK,
		"the live battle should stand at tick %d before the beat, reads %d" % [PREFORK, before_tick])

	var ctx := RolloutCandidates.make_context(
		"4a", [], 200, GPUAbilityLoader.build()["buffer"])
	var rows := RolloutHarness.rows_from_snapshot(before, ACTOR)
	_expect(rows.size() == GPUCombatPacker.GAMBITS_PER_UNIT,
		"the actor's gambit rows read back as %d ints" % rows.size())
	var candidates := RolloutCandidates.generate(rows, ctx, K)
	_expect(candidates.size() == K,
		"expected %d candidates, generated %d" % [K, candidates.size()])
	var seeds := RolloutHarness.crn_seeds(M, FLEET_UNITS, HORIZON)

	var harness := RolloutHarness.new(_sim, 0)
	var beat: Dictionary = harness.run(ACTOR, candidates, seeds, HORIZON)
	_expect(not beat.is_empty(), "the beat returned nothing")
	if beat.is_empty():
		return
	print("[harness] beat: fill %.2f ms  run %.2f ms  read %.2f ms  restore %.2f ms" % [
		beat["fill_ms"], beat["run_ms"], beat["read_ms"], beat["restore_ms"]])

	# --- The arm that matters: the live battle never moved.
	_snapshots_equal(before, _sim.snapshot_battle(0), "after a beat")

	# --- ...and the positive control for it: the FLEET did move. Without this,
	# a harness that ran zero ticks would pass the identity arm perfectly.
	# Slot 0 is excluded because the restore put its clock back — that is the
	# whole point of the restore, not an oversight.
	var moved := 0
	for b in range(1, K * M):
		if _sim.get_battle_tick(b) == before_tick + HORIZON:
			moved += 1
	_expect(moved == K * M - 1,
		"%d of %d fleet slots reached tick %d — the horizon did not run" % [
			moved, K * M - 1, before_tick + HORIZON])

	# --- Every slot carries the seed and the candidate it was assigned. This is
	# what makes slot `k*M+m` mean what #896 will read it as.
	#
	# 🔴 SLOT 0 IS EXEMPT, AND ITS EXEMPTION IS ITSELF AN ASSERTION. The live
	# battle is candidate 0 / seed 0's substrate, and the restore at the end of
	# the beat erases its candidacy — so after a beat it carries the LIVE seed and
	# the LIVE gambits, not the rollout's. Its result record was read before the
	# restore and is still valid; the slot is not. Asserted below, both ways, so
	# a restore that stopped covering the header would fail here as well as in the
	# identity arm.
	for ki in range(K):
		for mi in range(M):
			var slot := ki * M + mi
			var snap: Dictionary = _sim.snapshot_battle(slot)
			var header: PackedInt32Array = snap["battle"]
			if slot == 0:
				_expect(header[GPUCombatPacker.BattleHeaderField.SEED] != seeds[mi],
					"slot 0 still carries the rollout seed %d — the live battle was not restored" % seeds[mi])
				continue
			_expect(header[GPUCombatPacker.BattleHeaderField.SEED] == seeds[mi],
				"slot %d (candidate %d, seed %d) carries seed %d, expected %d" % [
					slot, ki, mi, header[GPUCombatPacker.BattleHeaderField.SEED], seeds[mi]])
			_expect(RolloutCandidates.unit_rows(snap["gambits"], ACTOR) == candidates[ki],
				"slot %d does not carry candidate %d's gambit image" % [slot, ki])

	# --- The record set is complete and addressed the way it is documented.
	var records: Array = beat["rows"]
	_expect(records.size() == K * M,
		"expected %d records, got %d" % [K * M, records.size()])
	for r in records:
		_expect(int(r["battle"]) == int(r["candidate"]) * M + int(r["seed_index"]),
			"record for candidate %d / seed %d claims battle %d" % [
				r["candidate"], r["seed_index"], r["battle"]])

	_arm_crn_identity(harness, candidates[0], seeds)
	_arm_refusals(harness, candidates, seeds, before)


## COMMON RANDOM NUMBERS, stated as a testable fact: the same candidate under the
## same seed is the same battle, wherever it sits in the fleet. `rand_int` hashes
## the battle SEED and never the battle id, so two slots holding one candidate
## must return identical records — and if they do not, either the fill wrote a
## candidate into the wrong slot or the seeds are not what they claim to be.
func _arm_crn_identity(harness: RolloutHarness, candidate: PackedInt32Array,
		seeds: PackedInt32Array) -> void:
	var twinned: Array = [candidate, candidate.duplicate()]
	var beat: Dictionary = harness.run(ACTOR, twinned, seeds, HORIZON)
	_expect(not beat.is_empty(), "the twinned beat returned nothing")
	if beat.is_empty():
		return
	var records: Array = beat["rows"]
	for mi in range(seeds.size()):
		var a: Dictionary = records[mi]
		var b: Dictionary = records[seeds.size() + mi]
		for key in ["result", "ticks", "team0_hp", "team1_hp"]:
			_expect(a[key] == b[key],
				"the same candidate under seed %d gave %s=%s in slot %d and %s in slot %d" % [
					mi, key, str(a[key]), a["battle"], str(b[key]), b["battle"]])


## Both refusal paths, and the thing that makes a refusal safe: battle 0 is
## untouched. A harness that snapshot-then-refused after filling would leave the
## fleet's candidate images sitting in the live slot.
func _arm_refusals(harness: RolloutHarness, candidates: Array,
		seeds: PackedInt32Array, before: Dictionary) -> void:
	var live_before: Dictionary = _sim.snapshot_battle(0)

	var too_big: Array = []
	for i in range(FLEET_BATTLES + 1):
		too_big.append(candidates[i % candidates.size()])
	_expect(harness.run(ACTOR, too_big, seeds, HORIZON).is_empty(),
		"a fleet request of %d battles should be refused (fleet holds %d)" % [
			too_big.size() * seeds.size(), FLEET_BATTLES])
	_snapshots_equal(live_before, _sim.snapshot_battle(0), "after an oversized request")

	var aliasing := PackedInt32Array([1, 2])
	_expect(harness.run(ACTOR, candidates, aliasing, HORIZON).is_empty(),
		"seeds 1 apart should be refused at U=%d H=%d" % [FLEET_UNITS, HORIZON])
	_snapshots_equal(live_before, _sim.snapshot_battle(0), "after an aliasing seed set")

	# The live battle is still what it was before the whole test's arms ran, not
	# merely what it was before this one.
	_snapshots_equal(before, _sim.snapshot_battle(0), "after every arm")


func _finish() -> void:
	# Charter clause 14a: a FRAME budget, not a duration. The old
	# 0.2 s timer was a bet that 0.2 s is enough on this box at this
	# load — a flake lever, and 0.2 s of pure sleeping on every green run.
	await AwaitUntil.settle(self)
	get_tree().quit(0)
