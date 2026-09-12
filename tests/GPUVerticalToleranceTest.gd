extends GPUCombatTestBase

## GPU Vertical Tolerance Test
##
## Tests that abilities with vertical_tolerance must reposition before casting.
##
## Uses MAP042's natural terrain (no height overrides):
##   Monk at (5,7) h=11
##   Target at (5,8) h=7 (immobile, WAIT gambit)
##   Height diff = 4
##
## Secret Fist (ID 104): range=1, vertical=0, vertical_tolerance=true
## The monk starts ADJACENT to the target but height diff (4 > 0) blocks casting.
## find_cast_position finds an h=7 tile adjacent to the target ((4,8), (6,8) or (5,9)).
## Monk paths: (5,7)h=11 -> (4,7)h=9 -> (4,8)h=7, then casts successfully.
##
## The target was (5,6) until 2026-08-22. `assets/maps/` is GITIGNORED — every map here is
## a locally-regenerated ROM export — and in the current export (5,6) is h=11, the SAME
## height as the monk. Diff 0 <= vertical 0, so the cast was never blocked, the monk went
## straight IDLE -> ACTING, and the test reported "vertical check may not have fired" — a
## drifted FIXTURE wearing the costume of a shader bug. `_check_terrain_premise` below now
## asserts the premise so the next drift says so in one line instead of costing a diagnosis.
##
## Pass criteria:
##   0. The terrain still has the height difference this test is about
##   1. Monk enters MOVING_TO_CAST (proving initial cast was blocked by vertical)
##   2. Monk eventually enters ACTING (proving it found a valid position and cast)


const ABILITY_SECRET_FIST = 104  # range=1, vertical=0, vertical_tolerance=true
const ABILITY_VERTICAL = 0       # ability_attributes.json: SecretFist vertical = 0
const MONK_X = 5
const MONK_Z = 7
const TARGET_X = 5
const TARGET_Z = 8

var _monk_moved_to_cast := false
var _monk_acted := false
var _results_printed := false


func get_test_name() -> String:
	return "GPU Vertical Tolerance Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Monk",
			"pos_x": MONK_X, "pos_z": MONK_Z,
			"hp": 500, "max_hp": 500,
			"pa": 14, "ma": 10, "wp": 5,
			"brave": 70, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
			"move": 4, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 0,
			"weapon_id": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Target",
			"pos_x": TARGET_X, "pos_z": TARGET_Z,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 0,
			"weapon_id": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_ability_gambit(ABILITY_SECRET_FIST, GPUConstants.TARGET_NEAREST_ENEMY)]
	else:
		return [make_wait_gambit()]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s (tick %d)" % [unit_name, old_name, new_name, current_tick])

	if unit_idx == 0:
		if new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
			_monk_moved_to_cast = true
			print("  [TEST] Monk entered MOVING_TO_CAST — vertical tolerance blocked initial cast")
		if new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
			_monk_acted = true
			print("  [TEST] Monk entered ACTING — Secret Fist cast after repositioning")
			call_deferred("_print_results")


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if delta < 0:
		print("  [DAMAGE] %s hit for %d! HP: %d -> %d (tick %d)" % [unit_name, abs(delta), old_hp, new_hp, current_tick])


func _process(delta):
	super._process(delta)
	if not _results_printed and current_tick >= max_ticks - 10:
		_print_results()


func _print_results():
	if _results_printed:
		return
	_results_printed = true
	print("\n=== VERTICAL TOLERANCE TEST RESULTS ===")
	var all_pass = _check_terrain_premise()
	if _monk_moved_to_cast:
		print("[PASS] Monk entered MOVING_TO_CAST (initial cast blocked by vertical tolerance)")
	else:
		print("[FAIL] Monk never entered MOVING_TO_CAST (vertical check may not have fired)")
		all_pass = false
	if _monk_acted:
		print("[PASS] Monk entered ACTING (successfully cast after repositioning to same height)")
	else:
		print("[FAIL] Monk never entered ACTING (could not find valid cast position or path)")
		all_pass = false
	if all_pass:
		print("[PASS] Vertical tolerance test passed")
	else:
		print("[FAIL] Vertical tolerance test failed")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results()


## Assert the TERRAIN this test is about, not just the behaviour it should produce.
##
## Every other assertion here is downstream of one fact: the monk's tile and the target's
## tile differ in height by more than `SecretFist.vertical` (0), and the target has a
## same-height neighbour to reposition onto. If a regenerated map export flattens that, the
## shader is right to let the cast through and the two behavioural checks below become
## meaningless — so name the premise instead of letting it fail as a phantom shader bug.
func _check_terrain_premise() -> bool:
	# Typed local for the inherited `CombatHost.lattice` — receiver inference is per file.
	var lat: Lattice = lattice
	if lat == null:
		print("[FAIL] no lattice — the height premise could not be checked at all")
		return false
	var monk_tile := lat.terrain_at(TerrainCell.ground(MONK_X, MONK_Z))
	var target_tile := lat.terrain_at(TerrainCell.ground(TARGET_X, TARGET_Z))
	if monk_tile == null or target_tile == null:
		print("[FAIL] monk (%d,%d) or target (%d,%d) is off the map" % [
			MONK_X, MONK_Z, TARGET_X, TARGET_Z])
		return false
	var diff: int = absi(int(monk_tile.height) - int(target_tile.height))
	print("[TERRAIN] monk (%d,%d) h=%d | target (%d,%d) h=%d | diff=%d | SecretFist vertical=%d" % [
		MONK_X, MONK_Z, int(monk_tile.height), TARGET_X, TARGET_Z, int(target_tile.height),
		diff, ABILITY_VERTICAL])
	if diff <= ABILITY_VERTICAL:
		print("[FAIL] the MAP no longer poses this test's question: diff %d <= vertical %d, "
			% [diff, ABILITY_VERTICAL]
			+ "so the cast is legal from the start and nothing should block it. "
			+ "`assets/maps/` is gitignored — re-pick a tile pair against the current export.")
		return false
	# ...and somewhere to reposition TO: a target neighbour at the target's own height.
	var refuge := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := lat.terrain_at(TerrainCell.ground(TARGET_X + d.x, TARGET_Z + d.y))
		if t != null and absi(int(t.height) - int(target_tile.height)) <= ABILITY_VERTICAL:
			refuge.append("(%d,%d)h=%d" % [TARGET_X + d.x, TARGET_Z + d.y, int(t.height)])
	if refuge.is_empty():
		print("[FAIL] no neighbour of the target sits within vertical %d of it — "
			% ABILITY_VERTICAL
			+ "find_cast_position has nowhere to send the monk, so this test cannot pass")
		return false
	print("[TERRAIN] cast-position candidates adjacent to the target: %s" % str(refuge))
	return true
