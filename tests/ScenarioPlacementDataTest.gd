extends Node

## Data-layer test for scenario-sourced placement (ADR-0043), JSON only — no map
## or terrain needed. Asserts the deployment-zone / ENTD databases and the red-first /
## clamp logic against the committed artifacts. The coord->Tile resolution (possible
## map mirror/shift) is verified separately, headful, in GPUArena.
##
## ⚠️ THE `can_source` ARMS ARE GONE AND THEIR REPLACEMENT IS STRONGER, because ADR-0258
## removed what they were about. `ScenarioPlacementSource.can_source` answered "is this
## scenario sourceable, or do we fall back to a procedural board" — and ADR-0043's
## procedural fallback is retired along with the deployment march it fed. Scenario
## sourcing is no longer one of two modes; it is the ONLY way a unit reaches a tile
## (`GPUArena._place_units_at_defaults`), so the question worth asking is not "may we
## source this one" but "does the zone every shipped scenario points at actually
## resolve" — a missing zone is now a warning and a straggler spread, not a fallback.
##
## Run: "$GODOT" --path . tests/ScenarioPlacementDataTest.tscn (no --headless)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const EntdPositionDatabase = ExMateriaAlmanac.EntdPositionDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase


const GARILAND_SCENARIO := 9
const GARILAND_DEPLOY_IDX := 256
const GARILAND_ENTD_IDX := 388

var _failures: int = 0


func _ready() -> void:
	print("\n=== ScenarioPlacementDataTest ===")

	_test_deployment_zone_gariland()
	_test_entd_enemies_red_first()
	_test_every_shipped_zone_resolves()
	_test_start_facing_points_at_the_enemy()

	if _failures == 0:
		print("[PASS] ScenarioPlacementDataTest: all checks passed")
	else:
		print("[FAIL] ScenarioPlacementDataTest: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: %s" % msg)
	else:
		print("  FAIL: %s" % msg)
		_failures += 1


func _test_deployment_zone_gariland() -> void:
	var zone := DeploymentZoneDatabase.get_zone(GARILAND_DEPLOY_IDX)
	_check(not zone.is_empty(), "deployment zone 256 exists")
	_check(int(zone.get("max_squad_size", 0)) == 5, "Gariland max_squad_size == 5")
	_check(int(zone.get("map_id", -1)) == 22, "Gariland zone map_id == 22")
	var tiles: Array = zone.get("tiles", [])
	_check(tiles.size() == 8, "Gariland deployment zone has 8 tiles (got %d)" % tiles.size())
	# The ROM-validated tile set, AFTER the ADR-0052/0057 chirality flip the
	# parser applies (y -> size_z-1-y; Gariland MAP022 size_z 15 -> 14-y). These
	# are the Godot-native coords the placement pipeline consumes, so the owned
	# units land on the same side as the zone (matches tools/test_parse_placement.py
	# test_gariland_deployment_idx_256_chirality_flipped).
	var expected := {
		Vector2i(3, 1): true, Vector2i(3, 2): true, Vector2i(4, 2): true,
		Vector2i(5, 2): true, Vector2i(6, 2): true, Vector2i(6, 3): true,
		Vector2i(7, 2): true, Vector2i(7, 3): true,
	}
	var all_match := true
	for t in tiles:
		if not expected.has(Vector2i(int(t[0]), int(t[1]))):
			all_match = false
	_check(all_match, "all 8 tiles match the ROM-validated set")


func _test_entd_enemies_red_first() -> void:
	var raw := EntdPositionDatabase.get_enemies(GARILAND_ENTD_IDX)
	_check(raw.size() == 6, "Gariland entd 388 has 6 enemy positions (got %d)" % raw.size())

	var ordered := EntdPositionDatabase.get_enemies_red_first(GARILAND_ENTD_IDX)
	# The blue guest (team_color 0) must be ordered LAST, after the 5 reds.
	var red_count := 0
	for e in ordered:
		if int(e.get("team_color", -1)) == 1:
			red_count += 1
	_check(red_count == 5, "5 red enemies among the 6 (the 6th is a guest)")
	# First 4 (the clamp window for a 4-unit roster) must all be red.
	var first4_all_red := true
	for i in range(mini(4, ordered.size())):
		if int(ordered[i].get("team_color", -1)) != 1:
			first4_all_red = false
	_check(first4_all_red, "first 4 (roster clamp) are all red, no guest")


## Every scenario the game ships must point at a deployment zone that RESOLVES — a real
## record, with tiles, and a squad cap. This is the arm that used to be `can_source`, asking
## the question ADR-0258 left behind: there is no second placement mode to fall through to,
## so an unresolvable zone is a battle whose owned side spreads onto an invented row.
##
## A scenario whose `first_squad_deployment_idx` is 0 is reported, not failed: idx 0 is the
## table's empty record and some scenarios legitimately carry it (a cutscene has no squad).
## What must not happen is a NON-zero index that resolves to nothing.
func _test_every_shipped_zone_resolves() -> void:
	var checked := 0
	var empty_idx := 0
	var broken: Array[String] = []
	for id in ScenarioDatabase.all_ids():
		var sc := ScenarioDatabase.get_scenario(id)
		var idx := int(sc.get("first_squad_deployment_idx", 0))
		if idx == 0:
			empty_idx += 1
			continue
		checked += 1
		var zone := DeploymentZoneDatabase.get_zone(idx)
		if zone.is_empty() or (zone.get("tiles", []) as Array).is_empty():
			broken.append("scenario %d -> zone %d" % [id, idx])
	# 🔴 PRINT THE SUBJECT. An empty `broken` list means "nothing broken" only if something
	# was EXAMINED; with `checked == 0` it means the corpus never loaded.
	print("  (examined %d scenarios with a non-zero deployment idx; %d carry idx 0)"
		% [checked, empty_idx])
	_check(checked > 0, "the scenario corpus yields scenarios to check (got %d)" % checked)
	_check(broken.is_empty(), "every non-zero deployment idx resolves to a zone with tiles%s"
		% ("" if broken.is_empty() else " — broken: " + ", ".join(broken)))


## The squad's START FACING must point at the enemy, on BOTH shipped roster-fed battles.
##
## THE ARM IS THE DIRECTION, NOT THE NUMBER. Asserting `zone 257 -> 0x800` only restates
## the JSON: regenerate the artifact wrong and the assertion moves with it. So this derives
## the answer from the OTHER artifact — the ENTD record's Red positions — and asks whether
## the angle the zone serves actually points from the deploy tiles at them. A parser that
## drops the `zone_facing` nibble reds this without anyone maintaining an expected value.
##
## Mandalia (zone 257 / ENTD 389) is here because it is the battle that broke: its
## `zone_facing` is 2, and lifting the `unit_facing` nibble alone (right only for the
## `zone_facing == 3` family Gariland belongs to) gave 0x400 = -X, side-on to the Corps.
## Gariland (zone 256 / ENTD 388) is the control — the zone that did NOT move — so a
## regression that reds both is telling you something different from one that reds one.
##
## ENTD positions come from `EntdBattle` (`assets/scenarios/entd.json`), NOT from
## `EntdPositionDatabase` — that table is a second, divergent extraction of the same ROM
## rows whose depth axis is unflipped on 135 records (#1033), so scoring a direction
## against it would compare a flipped zone to unflipped enemies.
func _test_start_facing_points_at_the_enemy() -> void:
	# [zone_idx, entd_key, label]
	for battle in [[256, "388", "Gariland"], [257, "389", "Mandalia Plains"]]:
		var zone := DeploymentZoneDatabase.get_zone(int(battle[0]))
		var tiles: Array = zone.get("tiles", [])
		var reds: Array = []
		for slot in EntdBattle.combatant_slots(EntdBattle.record(String(battle[1]))):
			if int(slot.get("team_color", -1)) != 0:
				reds.append(slot)
		if tiles.is_empty() or reds.is_empty():
			_check(false, "%s: zone %d tiles + ENTD %s reds both resolve"
				% [battle[2], int(battle[0]), String(battle[1])])
			continue

		var zc := Vector2.ZERO
		for t in tiles:
			zc += Vector2(float(t[0]), float(t[1]))
		zc /= float(tiles.size())
		var rc := Vector2.ZERO
		for s in reds:
			rc += Vector2(float(s.get("x", 0)), float(s.get("y", 0)))
		rc /= float(reds.size())

		# Both battles are laid out squarely along the depth axis (squad on one half,
		# enemies on the other), so the wanted angle is unambiguous: on this wheel
		# 0x000 = +tile-y, 0x800 = -tile-y (`Unit._CARDINAL_TO_12BIT`). If a future
		# artifact change made a battle diagonal, the dominance check below reds rather
		# than silently scoring a coin flip.
		var d := rc - zc
		_check(absf(d.y) > absf(d.x) + 1.0,
			"%s: enemies sit squarely along the depth axis (dx %.1f, dy %.1f)"
				% [battle[2], d.x, d.y])
		var want := 0x000 if d.y > 0.0 else 0x800
		var got := int(zone.get("unit_facing_12bit", -1))
		_check(got == want,
			"%s: zone %d start facing 0x%03X points at the ENTD reds (wanted 0x%03X)"
				% [battle[2], int(battle[0]), got, want])
