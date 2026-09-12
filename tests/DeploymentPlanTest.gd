extends Node
## Pure-logic guard for the snap-deployment ASSIGNMENT (wayfinder #234 D). The v1
## deployment snaps each owned unit onto a deployment-zone tile (NOT the auto-march):
## deterministic list order, Ramza first, capped by `max_squad_size`. The live
## `Unit.place_on_tile` call is verified headful; THIS tests the pure (unit → tile)
## assignment against the REAL extracted zone-256 data (independent source of truth).
##
## Zone 256 (Gariland): max_squad_size 5, 8 tiles, first = (3,1) after the ADR-0052
## chirality flip (MAP022 size_z 15, y→14−y; raw (3,13)). The 5-unit Gariland roster (C)
## fills the first 5 tiles: ramza→(3,1), then the 4 generics.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DeploymentPlanTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase


const GARILAND_ZONE_IDX := 256

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_fills_first_n_tiles_in_order()
	_test_ramza_lands_on_the_first_zone_tile()
	_test_cap_clamps_over_sized_roster()
	_test_under_sized_roster_fills_prefix()
	_test_assignments_are_collision_free()

	print("\n=== DeploymentPlanTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] DeploymentPlanTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DeploymentPlanTest")
		get_tree().quit(1)
	else:
		print("[PASS] DeploymentPlanTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _zone() -> Dictionary:
	return DeploymentZoneDatabase.get_zone(GARILAND_ZONE_IDX)


func _tiles() -> Array:
	return _zone().get("tiles", [])


func _cap() -> int:
	return int(_zone().get("max_squad_size", 0))


# --- D1: 5 owned onto zone-256 tiles → 5 assignments, list order preserved ---
func _test_fills_first_n_tiles_in_order() -> void:
	var owned := ["ramza", "g1", "g2", "g3", "g4"]
	var plan := DeploymentPlan.assign(owned, _tiles(), _cap())
	_eq(plan.size(), 5, "5 owned → 5 placements (roster == cap)")
	if plan.size() != 5:
		return
	var tiles := _tiles()
	for i in range(5):
		_eq(plan[i]["unit"], owned[i], "placement %d keeps list order" % i)
		_eq(plan[i]["tile"], tiles[i], "placement %d onto zone tile %d" % [i, i])


# --- D2: Ramza (first owned) lands on the zone's first tile = (3,1) (chirality-flipped) ---
func _test_ramza_lands_on_the_first_zone_tile() -> void:
	var plan := DeploymentPlan.assign(["ramza", "g1"], _tiles(), _cap())
	_true(plan.size() >= 1, "at least one placement")
	if plan.is_empty():
		return
	_eq(plan[0]["unit"], "ramza", "Ramza deploys first")
	_eq(int(plan[0]["tile"][0]), 3, "Ramza tile x = 3")
	_eq(int(plan[0]["tile"][1]), 1, "Ramza tile y = 1 (flipped from raw 13)")


# --- D3: a roster larger than the cap is clamped (over-cap selection is C's fog) ---
func _test_cap_clamps_over_sized_roster() -> void:
	var owned := ["ramza", "g1", "g2", "g3", "g4", "g5"]  # 6 > cap 5
	var plan := DeploymentPlan.assign(owned, _tiles(), _cap())
	_eq(plan.size(), 5, "6 owned clamped to cap 5")
	# the 6th unit is not placed.
	for p in plan:
		_true(p["unit"] != "g5", "over-cap unit g5 not deployed")


# --- D4: fewer owned than tiles → fill the prefix, leave the rest empty ---
func _test_under_sized_roster_fills_prefix() -> void:
	var plan := DeploymentPlan.assign(["ramza", "g1", "g2"], _tiles(), _cap())
	_eq(plan.size(), 3, "3 owned → 3 placements")


# --- D5: no two units share a tile ---
func _test_assignments_are_collision_free() -> void:
	var owned := ["ramza", "g1", "g2", "g3", "g4"]
	var plan := DeploymentPlan.assign(owned, _tiles(), _cap())
	var seen := {}
	for p in plan:
		var key := str(p["tile"])
		_true(not seen.has(key), "tile %s used once" % key)
		seen[key] = true
