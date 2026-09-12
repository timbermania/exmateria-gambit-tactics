extends Node
## Pure-logic guard for the DEPLOYMENT ASSIGNMENT — the editable one (ADR-0242, #892).
##
## [DeploymentPlan] is ONE assignment, computed; [DeploymentAssignment] is the assignment
## the player edits, and its whole content is the two questions deployment asks: **who
## fights** (the cap is smaller than the roster, so somebody stays benched) and **where
## they stand**. This file tests those rules against the REAL extracted zone-256 data, so
## a change to `deployment_zones.json` that broke the cap would show up here rather than
## as a strange battle four systems away.
##
## No scene, no map, no GPU — the assignment holds units as opaque `Object`s and is
## constructed BEFORE any of those exist, which is the design's own claim (deployment is
## CPU-side, and `boot_battle` at commit is what puts units in the buffer). A test that
## needed a battle to run would be testing something else.
##
## The arms, and what each one falsifies:
##
##   1. The zone is the ROM's — 8 tiles, cap 5, first tile (3,1). If this drifts, every
##      number below is measuring an invented zone.
##   2. The cap is a cap on the SQUAD, not on edits — a sixth body is refused while
##      MOVING an already-placed unit is always free. The cheap wrong implementation
##      (count the placements) forbids dragging a unit around a zone you have filled.
##   2b. The mandatory unit HOLDS A SLOT. Four cadets fill a 5-cap Gariland zone and the
##       fifth is refused for anyone but Ramza; the moment he is down the reserve is
##       discharged and the cap is 5 again. This is the arm for the difference between
##       refusing a SQUAD at the commit and refusing a PLACEMENT when it is made — the
##       version without it is legal all the way to Space and then says "Ramza must be
##       deployed" over a full zone.
##   3. A tile holds one unit, and unplacing frees it.
##   4. `auto_fill` honours the mandatory flag BY CONSTRUCTION. The mandatory unit is put
##      LAST in roster order on purpose: an implementation that leans on
##      "`owned_units()` happens to return Ramza first" passes with him first and fails
##      here, which is the whole reason the arm exists.
##   5. `problems()` names the rule you tripped — the deployment screen has to say WHY
##      commit is refused, and a bool cannot.
##   6. `clear()` is what cancel means here. There is no snapshot to restore because
##      nothing has been written anywhere yet (ADR-0239: the director holds none in
##      DEPLOYMENT), so this is the ONLY undo deployment has.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DeploymentAssignmentTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase


const GARILAND_SCENARIO := 9
const GARILAND_ZONE_IDX := 256
## The mandatory unit's catalogue slug — the ATTACK.OUT flags bit 0 rule, which
## `scenarios.json` carries as `ramza_mandatory` and Gariland (9) sets.
const RAMZA_SLUG := "ramza"

var _passed: int = 0
var _failed: int = 0
## Every stand-in unit made, freed at the end — they are real `Node`s so that
## `get_instance_id()` and `name` behave exactly as they do for a `Unit`.
var _made: Array[Node] = []


func _ready() -> void:
	_test_zone_is_the_roms()
	_test_cap_bounds_the_squad_not_the_edits()
	_test_the_mandatory_unit_holds_a_slot()
	_test_a_tile_holds_one_unit()
	_test_auto_fill_honours_the_mandatory_flag()
	_test_problems_name_the_rule()
	_test_clear_is_the_deployment_cancel()

	for node in _made:
		node.free()
	_made.clear()

	print("\n=== DeploymentAssignmentTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] DeploymentAssignmentTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DeploymentAssignmentTest")
		get_tree().quit(1)
	else:
		print("[PASS] DeploymentAssignmentTest: cap / mandatory reserve / exclusivity / mandatory-by-construction / problems / clear, over the real zone %d" % GARILAND_ZONE_IDX)
		get_tree().quit(0)


# === Arms =====================================================================

## The data under everything else. Read from the extracted table, not restated.
func _test_zone_is_the_roms() -> void:
	var zone: Dictionary = DeploymentZoneDatabase.get_zone(GARILAND_ZONE_IDX)
	_eq(zone.get("tiles", []).size(), 8, "zone 256 tile count")
	_eq(int(zone.get("max_squad_size", -1)), 5, "zone 256 max_squad_size")
	var a := _assignment(8)
	_eq(a.tiles.size(), 8, "assignment tile count")
	_eq(a.cap, 5, "assignment cap")
	_eq(a.tiles[0], Vector2i(3, 1), "first zone tile")
	# Scenario 9 sets ATTACK.OUT flags bit 0 — the fact the mandatory rule rests on.
	_true(bool(ScenarioDatabase.get_scenario(GARILAND_SCENARIO).get("ramza_mandatory", false)),
		"scenario 9 ramza_mandatory")


## A sixth body is refused; moving the five you have is free.
func _test_cap_bounds_the_squad_not_the_edits() -> void:
	var a := _assignment(8)
	var cast: Array = a.candidates()
	for i in range(a.cap):
		_true(a.place(cast[i], a.tiles[i]), "place unit %d" % i)
	_eq(a.placed_count(), 5, "squad is at the cap")
	_true(not a.place(cast[5], a.tiles[5]), "a sixth body is refused")
	_eq(a.placed_count(), 5, "the refusal changed nothing")
	# The move that the naive "count the placements" cap would forbid.
	_true(a.place(cast[0], a.tiles[7]), "a placed unit may move to a free tile")
	_eq(a.tile_of(cast[0]), a.tiles[7], "and it moved")
	_eq(a.placed_count(), 5, "moving did not grow the squad")
	# Off-zone tiles are not deployment tiles.
	_true(not a.place(cast[5], Vector2i(99, 99)), "an off-zone tile is refused")


## The reserve: a mandatory unit is never placed for you, but a slot is kept for it.
func _test_the_mandatory_unit_holds_a_slot() -> void:
	var a := _assignment(8, 7)  # mandatory unit LAST, so nothing places it by accident
	var cast: Array = a.candidates()
	var ramza = cast[7]
	_eq(a.cap, 5, "the zone cap")
	_eq(a.reserved_slots(), 1, "one mandatory unit is holding a slot")
	_eq(a.effective_cap(cast[0]), 4, "a cadet may take four of the five")
	_eq(a.effective_cap(ramza), 5, "the mandatory unit itself is not held back by its own slot")

	for i in range(4):
		_true(a.place(cast[i], a.tiles[i]), "cadet %d takes a tile" % i)
	_eq(a.placed_count(), 4, "four deployed, one slot held")
	_true(not a.place(cast[4], a.tiles[4]), "a fifth CADET is refused while the slot is held")
	_eq(a.placed_count(), 4, "the refusal changed nothing")
	# Rearranging what is already down stays free — the reserve bounds the squad, not edits.
	_true(a.place(cast[0], a.tiles[6]), "a placed cadet may still move")
	_eq(a.placed_count(), 4, "moving did not spend the held slot")

	_true(a.place(ramza, a.tiles[4]), "the mandatory unit may take the held slot")
	_eq(a.reserved_slots(), 0, "the reserve is discharged once he is down")
	_eq(a.effective_cap(cast[4]), 5, "and the cap is the zone's again")
	_eq(a.placed_count(), 5, "five deployed")
	_true(a.is_committable(), "and the squad is committable")

	# Benching him puts the reserve back, and the freed tile is his, not a cadet's.
	_true(a.unplace(ramza), "benching the mandatory unit")
	_eq(a.reserved_slots(), 1, "the slot is held again")
	_true(not a.place(cast[4], a.tiles[4]), "a cadet cannot take the tile he vacated")
	_true(a.place(ramza, a.tiles[4]), "he can")


func _test_a_tile_holds_one_unit() -> void:
	var a := _assignment(8)
	var cast: Array = a.candidates()
	_true(a.place(cast[0], a.tiles[0]), "first unit lands")
	_true(not a.place(cast[1], a.tiles[0]), "second unit refused on a taken tile")
	_eq(a.unit_at(a.tiles[0]), cast[0], "the tile still holds the first")
	_true(a.unplace(cast[0]), "unplace reports the change")
	_eq(a.unit_at(a.tiles[0]), null, "the tile is free")
	_true(a.place(cast[1], a.tiles[0]), "and the second can take it now")
	_eq(a.free_tiles().size(), 7, "one tile occupied, seven free")


## The arm the mandatory rule actually needs: the mandatory unit is LAST in roster order,
## so an `auto_fill` that just takes the first `cap` candidates leaves him benched.
func _test_auto_fill_honours_the_mandatory_flag() -> void:
	var a := _assignment(8, 7)  # mandatory unit at index 7 — the last one
	var ramza = a.candidates()[7]
	_true(a.is_mandatory(ramza), "the last candidate is the mandatory one")
	a.auto_fill()
	_eq(a.placed_count(), 5, "auto_fill fills exactly the cap")
	_true(a.is_placed(ramza), "auto_fill placed the mandatory unit despite roster order")
	_eq(a.tile_of(ramza), a.tiles[0], "and put him on the first zone tile")
	for row in a.squad():
		_true(a.tiles.has(row["tile"]), "auto_fill used only zone tiles")
	_eq(a.benched().size(), 3, "three left on the bench")
	_true(a.is_committable(), "an auto-filled assignment is committable")


func _test_problems_name_the_rule() -> void:
	var a := _assignment(8, 0)
	_true(_problems_mention(a, "no unit is deployed"), "an empty assignment says so")
	# Fill everything the RESERVE allows a non-mandatory unit to take — four of the five.
	# Five is no longer reachable this way, which is the reserve doing its job; `problems()`
	# is still the commit-time backstop and still has to name the rule.
	var cast: Array = a.candidates()
	for i in range(a.cap - 1):
		_true(a.place(cast[i + 1], a.tiles[i]), "cadet %d takes a tile" % i)
	_eq(a.placed_count(), 4, "four deployed, mandatory benched")
	_true(_problems_mention(a, "must be deployed"), "the mandatory unit is named")
	_true(not a.is_committable(), "and commit is refused")
	a.place(cast[0], a.tiles[4])
	_true(a.is_committable(), "committable once he is on the field")
	_eq(a.problems().size(), 0, "and nothing is left to report")


## Deployment's only undo. Nothing was written anywhere, so there is nothing to restore.
func _test_clear_is_the_deployment_cancel() -> void:
	var a := _assignment(8)
	a.auto_fill()
	_eq(a.placed_count(), 5, "filled")
	a.clear()
	_eq(a.placed_count(), 0, "clear benches everyone")
	_eq(a.benched().size(), 8, "the whole roster is back on the bench")
	_eq(a.free_tiles().size(), 8, "and every zone tile is free")
	_true(not a.is_committable(), "an empty assignment cannot start a battle")


# === Harness ==================================================================

## An assignment over `count` stand-in units and the REAL Gariland zone.
## `mandatory_index` names which candidate carries the Ramza slug (-1 for none).
func _assignment(count: int, mandatory_index: int = 0) -> DeploymentAssignment:
	var cast: Array = []
	for i in range(count):
		var node := Node.new()
		node.name = "Unit%d" % i
		if i == mandatory_index:
			node.set_meta("slug", RAMZA_SLUG)
		_made.append(node)
		cast.append(node)
	return DeploymentAssignment.for_scenario(cast, GARILAND_SCENARIO,
		func(unit) -> String: return str(unit.get_meta("slug", "")))


func _problems_mention(a: DeploymentAssignment, fragment: String) -> bool:
	for problem in a.problems():
		if problem.contains(fragment):
			return true
	return false


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)
