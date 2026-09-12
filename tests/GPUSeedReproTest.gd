extends GPUCombatTestBase

## GPU Seed Reproducibility Test
##
## Verifies that the RNG pipeline produces identical results when given
## the same seed. Tests two levels:
## 1. The placement policy + the battle seed draw (run twice, compare)
## 2. GPU combat simulation (run N ticks twice with same battle seed,
##    compare all unit states including HP — covers evasion rolls)
##
## ⚠️ LEVEL 1 IS NARROWER THAN IT WAS, AND THE NARROWING IS THE POINT. It used to run
## `PlacementTileGenerator.generate()` (two seeded flood-grown islands + Poisson-sampled
## contested tiles) and `AIPlacementController`, both retired with the deployment march
## by ADR-0258. What is left of that layer is [PlacementPolicy], which is DETERMINISTIC
## BY CONSTRUCTION — it draws no random numbers at all — so the arm asserts the property
## the surviving code actually has: the same lattice yields the same cell set, and the
## seeded `battle_seed` draw that feeds level 2 reproduces. Deleting level 1 outright was
## rejected: the seed draw is the input to everything below it, and an arm that stops
## being interesting is not the same as an arm with nothing left to say.


# 🔴 NO `TerrainCell` ALIAS HERE, AND THAT IS DELIBERATE. This script
# EXTENDS `GPUCombatTestBase.gd`, which declares one, and GDScript refuses a
# member that already exists in the parent — a parse error that takes this
# whole file out. An alias is a per-CLASS declaration, not a per-file one;
# the inherited constant is what the use sites below read (ADR-0212 dec. 1).

const TEST_SEED = 12345
const COMBAT_TICKS = 800  # Enough ticks for multiple attacks + evasion rolls

var _failed: bool = false
var _fail_reason: String = ""
var _test_started: bool = false


func get_test_name() -> String:
	return "GPU Seed Reproducibility Test"


# 4v4 melee units with evasion stats so evade/block rolls happen
func get_team0_unit_configs() -> Array:
	return [
		{"name": "P1", "pos_x": 3, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 12, "ma": 8, "wp": 6, "brave": 60, "faith": 50,
		 "mp": 50, "max_mp": 50, "speed": 80, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 15, "s_ev": 20, "w_ev": 10, "body_sprite_id": 0x02,
		 "gambits": [make_attack_gambit()]},
		{"name": "P2", "pos_x": 4, "pos_z": 6, "hp": 180, "max_hp": 180,
		 "pa": 10, "ma": 10, "wp": 7, "brave": 55, "faith": 60,
		 "mp": 80, "max_mp": 80, "speed": 90, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 10, "s_ev": 15, "w_ev": 5, "body_sprite_id": 0x02,
		 "gambits": [make_attack_gambit()]},
		{"name": "P3", "pos_x": 3, "pos_z": 7, "hp": 220, "max_hp": 220,
		 "pa": 14, "ma": 6, "wp": 5, "brave": 70, "faith": 40,
		 "mp": 30, "max_mp": 30, "speed": 70, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 20, "s_ev": 10, "w_ev": 15, "body_sprite_id": 0x02,
		 "gambits": [make_attack_gambit()]},
		{"name": "P4", "pos_x": 4, "pos_z": 8, "hp": 160, "max_hp": 160,
		 "pa": 8, "ma": 12, "wp": 8, "brave": 45, "faith": 70,
		 "mp": 100, "max_mp": 100, "speed": 100, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 5, "s_ev": 25, "w_ev": 20, "body_sprite_id": 0x02,
		 "gambits": [make_attack_gambit()]},
	]


func get_team1_unit_configs() -> Array:
	return [
		{"name": "E1", "pos_x": 8, "pos_z": 5, "hp": 200, "max_hp": 200,
		 "pa": 11, "ma": 9, "wp": 7, "brave": 65, "faith": 55,
		 "mp": 60, "max_mp": 60, "speed": 85, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 12, "s_ev": 18, "w_ev": 8, "body_sprite_id": 0x05,
		 "gambits": [make_attack_gambit()]},
		{"name": "E2", "pos_x": 7, "pos_z": 6, "hp": 190, "max_hp": 190,
		 "pa": 13, "ma": 7, "wp": 6, "brave": 50, "faith": 45,
		 "mp": 40, "max_mp": 40, "speed": 75, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 18, "s_ev": 12, "w_ev": 12, "body_sprite_id": 0x05,
		 "gambits": [make_attack_gambit()]},
		{"name": "E3", "pos_x": 8, "pos_z": 7, "hp": 210, "max_hp": 210,
		 "pa": 9, "ma": 11, "wp": 5, "brave": 55, "faith": 65,
		 "mp": 70, "max_mp": 70, "speed": 95, "move": 4, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 8, "s_ev": 22, "w_ev": 6, "body_sprite_id": 0x05,
		 "gambits": [make_attack_gambit()]},
		{"name": "E4", "pos_x": 7, "pos_z": 8, "hp": 170, "max_hp": 170,
		 "pa": 15, "ma": 5, "wp": 9, "brave": 75, "faith": 35,
		 "mp": 20, "max_mp": 20, "speed": 65, "move": 3, "jump": 3,
		 "weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		 "c_ev": 25, "s_ev": 8, "w_ev": 18, "body_sprite_id": 0x05,
		 "gambits": [make_attack_gambit()]},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	var all_configs = get_team0_unit_configs() + get_team1_unit_configs()
	if unit_idx < all_configs.size():
		return all_configs[unit_idx].get("gambits", [make_attack_gambit()])
	return [make_attack_gambit()]


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), regression_logging)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here (the field is inherited from `CombatHost`, and the register's
	# receiver inference is per file), then stored.
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_fail("Map has no lattice")
		_finish()
		return

	# --- Part 1: Tile generation + AI placement determinism ---
	print("\n--- Part 1: Tile Generation + AI Placement ---")
	var run1 = _run_placement(lattice, TEST_SEED)
	var run2 = _run_placement(lattice, TEST_SEED)
	_compare_placement_runs(run1, run2)

	if _failed:
		_finish()
		return

	# --- Part 2: GPU combat determinism ---
	print("\n--- Part 2: GPU Combat Determinism (%d ticks) ---" % COMBAT_TICKS)

	_setup_distance_field()
	_setup_gpu_simulator()
	await _create_units()

	# Run 1: initialize battle with fixed seed, step N ticks, snapshot
	var snap1 = _run_combat(TEST_SEED)

	# Run 2: reinitialize with same seed, step same N ticks, snapshot
	var snap2 = _run_combat(TEST_SEED)

	_compare_combat_snapshots(snap1, snap2)

	_finish()


func _process(_delta):
	# No tick processing — we step manually in _run_combat
	pass


func _run_placement(lat: Lattice, seed_value: int) -> Dictionary:
	"""Run the placement policy + the seeded battle-seed draw."""
	var result: Dictionary = {}

	# The set IS coordinates (ADR-0164 dec. 2 / ADR-0166 dec. 3), so the `_tiles_to_coords`
	# projection this used to need is gone — the reproducibility claim is compared on
	# exactly the value the policy produced.
	result["placement_cells"] = PlacementPolicy.new(lat).placement_cells()

	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	result["battle_seed"] = rng.randi()

	return result


func _run_combat(battle_seed: int) -> Array[Dictionary]:
	"""Initialize GPU battle with fixed seed, run COMBAT_TICKS, return state snapshots."""
	if not gpu_simulator:
		_fail("GPU simulator not available")
		return []

	# Build GPU configs
	var gpu_team0: Array = []
	var gpu_team1: Array = []
	var team0_configs = get_team0_unit_configs()
	var team1_configs = get_team1_unit_configs()

	for i in range(team0_units.size()):
		gpu_team0.append(_build_gpu_config(
			team0_units[i].movement_component.current_cell, team0_configs[i]))

	for i in range(team1_units.size()):
		gpu_team1.append(_build_gpu_config(
			team1_units[i].movement_component.current_cell, team1_configs[i]))

	gpu_simulator.set_battle_units(0, gpu_team0, gpu_team1, battle_seed)

	# Set gambits
	for i in range(team0_units.size()):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0))
	for i in range(team1_units.size()):
		gpu_simulator.set_unit_gambits(0, team0_units.size() + i, get_gambits_for_unit(team0_units.size() + i, 1))

	gpu_state_reader.initialize(gpu_simulator, 0)

	# Step ticks and snapshot at intervals
	var snapshots: Array[Dictionary] = []
	var snapshot_interval = 100
	for tick in range(COMBAT_TICKS):
		gpu_simulator.step_tick(1)

		if (tick + 1) % snapshot_interval == 0:
			var states = gpu_state_reader.get_all_unit_states()
			var snap: Dictionary = {"tick": tick + 1, "states": []}
			for s in states:
				snap["states"].append({
					"hp": s.get("hp", 0),
					"mp": s.get("mp", 0),
					"pos_x": s.get("pos_x", 0),
					"pos_z": s.get("pos_z", 0),
					"state": s.get("state", 0),
					"flags": s.get("flags", 0),
					"ct": s.get("ct", 0),
					"atb": s.get("atb", 0),
				})
			snapshots.append(snap)

	return snapshots


func _compare_placement_runs(run1: Dictionary, run2: Dictionary) -> void:
	"""Compare two placement runs."""
	var keys = ["placement_cells", "battle_seed"]

	for key in keys:
		var v1 = run1[key]
		var v2 = run2[key]

		if v1 is Array:
			if v1.size() != v2.size():
				_fail("Placement %s: size mismatch (%d vs %d)" % [key, v1.size(), v2.size()])
				return
			for i in range(v1.size()):
				if v1[i] != v2[i]:
					_fail("Placement %s[%d]: %s != %s" % [key, i, str(v1[i]), str(v2[i])])
					return
		else:
			if v1 != v2:
				_fail("Placement %s: %s != %s" % [key, str(v1), str(v2)])
				return

	# 🔴 PRINT THE SUBJECT, NOT ONLY THE VERDICT. An empty cell set compares equal to
	# an empty cell set, so "identical" over 0 tiles is a run that examined nothing.
	var n: int = (run1["placement_cells"] as Array).size()
	print("  Placement cells: %d (identical)" % n)
	print("  Battle seed: %d (identical)" % run1["battle_seed"])
	if n == 0:
		_fail("the placement policy returned NO cells — 'identical' over an empty set is vacuous")


func _compare_combat_snapshots(snap1: Array[Dictionary], snap2: Array[Dictionary]) -> void:
	"""Compare GPU combat snapshots from two runs."""
	if snap1.size() != snap2.size():
		_fail("Combat snapshot count mismatch: %d vs %d" % [snap1.size(), snap2.size()])
		return

	var damage_observed := false

	for s_idx in range(snap1.size()):
		var s1 = snap1[s_idx]
		var s2 = snap2[s_idx]
		var tick = s1["tick"]
		var states1: Array = s1["states"]
		var states2: Array = s2["states"]

		if states1.size() != states2.size():
			_fail("Tick %d: unit count mismatch (%d vs %d)" % [tick, states1.size(), states2.size()])
			return

		for u_idx in range(states1.size()):
			var u1: Dictionary = states1[u_idx]
			var u2: Dictionary = states2[u_idx]

			for field in ["hp", "mp", "pos_x", "pos_z", "state", "flags", "ct", "atb"]:
				if u1[field] != u2[field]:
					_fail("Tick %d, unit %d, %s: %s != %s" % [tick, u_idx, field, str(u1[field]), str(u2[field])])
					return

			# Check if damage has occurred (HP < max)
			if u1["hp"] < get_team0_unit_configs()[0]["max_hp"]:
				damage_observed = true

	# Report results
	var final = snap1[-1]["states"]
	var hp_summary := ""
	for i in range(final.size()):
		var f: Dictionary = final[i]
		hp_summary += "  Unit %d: HP=%d pos=(%d,%d) state=%d\n" % [i, f["hp"], f["pos_x"], f["pos_z"], f["state"]]

	print("  %d snapshots compared across %d ticks (identical)" % [snap1.size(), COMBAT_TICKS])
	print("  Damage observed: %s" % ("YES" if damage_observed else "NO"))
	print("  Final state:\n%s" % hp_summary.strip_edges())

	if not damage_observed:
		_fail("No damage occurred in %d ticks — evasion determinism not tested" % COMBAT_TICKS)


func _fail(reason: String) -> void:
	if not _failed:
		_failed = true
		_fail_reason = reason
		print("\n[FAIL] %s" % reason)


func _finish() -> void:
	print("\n--- Seed Reproducibility Test Complete ---")

	if _failed:
		print("\n[FAIL] %s" % _fail_reason)
	else:
		print("\n[PASS] All outputs identical (placement + %d ticks of combat with evasion)" % COMBAT_TICKS)

	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if _failed else 0)


# Override callbacks — not processing combat events
func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass

func on_hp_changed(_unit_idx: int, _old_hp: int, _new_hp: int, _delta: int):
	pass

func on_victory(_winning_team: int):
	pass
