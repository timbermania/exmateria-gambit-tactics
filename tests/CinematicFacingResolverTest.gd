extends Node3D
## Scene test for CinematicFacingResolver (ADR-0039).
##
## Loads a REAL map (live terrain, MAP042) and proves the facing resolver does
## what the broken physics-raycast version could not:
##
##   1. DETECTION — the analytic terrain gate actually sees occlusion. On a map
##      with relief there is a tile + camera yaw where terrain hides the unit.
##      (The bug: the only terrain colliders are flat tile-tops, so a low-angle
##      physics ray threaded between them and NEVER reported a cliff.)
##   2. ROTATION — from an occluded base yaw, the resolver rotates to a yaw
##      whose sightline to the unit is clear of terrain. This is the user's
##      acceptance condition: for the chosen angle, nothing hits between the
##      target and the camera.
##   3. STABILITY — from an already-clear base yaw, the resolver keeps a clear
##      yaw (no needless rotation into occlusion).
##
## Prints [PASS]/[FAIL] and quits, per tests/run_all_tests.sh conventions.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice


const ResolverClass = ExMateriaEffects.CinematicFacingResolver

const PITCH := 302.0          # default battle pitch (~26.5 deg down)
const QUARTER := 1024.0       # 90 deg in PSX units

@onready var map: Node3D = $ProceduralMap


func _ready() -> void:
	# Let the map's _ready() build terrain + collision and settle in the tree.
	await get_tree().process_frame
	await get_tree().process_frame
	_run()


func _run() -> void:
	if map == null:
		_fail("map not built")
		return
	var lattice: Lattice = map.lattice
	if lattice == null:
		_fail("map lattice not built")
		return

	var resolver = ResolverClass.new(self, map)
	var gate: float = ResolverClass.GATE_VISIBLE_FRACTION

	# Find the strongest cliff scenario on the map: a tile where one cardinal
	# yaw is most-occluded by terrain AND another cardinal yaw is clear.
	var scenario := _find_cliff_scenario(resolver, gate, lattice)
	if scenario.is_empty():
		_fail("no cliff scenario found on map (terrain has no occluding relief?) — cannot exercise the gate")
		return

	var subject: Vector3 = scenario["subject"]
	var occluded_yaw: float = scenario["occluded_yaw"]
	var occ_frac: float = scenario["occluded_frac"]
	var clear_yaw: float = scenario["clear_yaw"]

	# 1. DETECTION: the occluded base really reads as occluded.
	if occ_frac >= gate:
		_fail("scenario base yaw %.0f not actually occluded (frac=%.2f)" % [occluded_yaw, occ_frac])
		return

	# 2. ROTATION: resolve from the occluded base — must move to a clear yaw.
	var focus := _spawn_focus(subject)
	var chosen: float = resolver.resolve_facing_yaw(occluded_yaw, PITCH, focus)
	var chosen_frac: float = resolver.terrain_visible_fraction(subject, PITCH, chosen)
	if is_equal_approx(chosen, occluded_yaw):
		_fail("resolver KEPT the occluded base yaw %.0f (frac=%.2f); should have rotated to a clear angle" % [
			occluded_yaw, occ_frac])
		return
	if chosen_frac < gate:
		_fail("resolver rotated %.0f -> %.0f but it is STILL terrain-occluded (frac=%.2f)" % [
			occluded_yaw, chosen, chosen_frac])
		return

	# 3. STABILITY: from an already-clear base, stay clear (don't rotate into a wall).
	var kept: float = resolver.resolve_facing_yaw(clear_yaw, PITCH, focus)
	var kept_frac: float = resolver.terrain_visible_fraction(subject, PITCH, kept)
	if kept_frac < gate:
		_fail("from clear base %.0f resolver moved to occluded yaw %.0f (frac=%.2f)" % [
			clear_yaw, kept, kept_frac])
		return

	print("[PASS] facing resolver @ subject %s: base %.0f occluded(%.2f) -> chose %.0f clear(%.2f); clear base %.0f kept clear(%.2f)" % [
		str(subject), occluded_yaw, occ_frac, chosen, chosen_frac, clear_yaw, kept_frac])
	get_tree().quit()


## Scan every tile; for each test the 4 cardinal yaws. Keep the tile whose
## most-occluded candidate has the LOWEST visible fraction while still having a
## clear sibling — the most unambiguous spot to exercise the resolver.
func _find_cliff_scenario(resolver, gate: float, lattice: Lattice) -> Dictionary:
	var best := {}
	var best_occ := gate   # only consider candidates strictly below the gate
	for cell in lattice.all_cells():
		var subject := Vector3(
			float(cell.grid.x) + 0.5,
			lattice.world_position_at(cell.grid).y,
			float(cell.grid.y) + 0.5)
		var occ_yaw := -1.0
		var occ_frac := 2.0
		var clear_yaw := -1.0
		for k in range(4):
			var yaw := float(k) * QUARTER
			var frac: float = resolver.terrain_visible_fraction(subject, PITCH, yaw)
			if frac < occ_frac:
				occ_frac = frac
				occ_yaw = yaw
			if frac >= gate and clear_yaw < 0.0:
				clear_yaw = yaw
		if occ_frac < best_occ and clear_yaw >= 0.0 and occ_yaw >= 0.0:
			best_occ = occ_frac
			best = {
				"subject": subject,
				"occluded_yaw": occ_yaw,
				"occluded_frac": occ_frac,
				"clear_yaw": clear_yaw,
			}
	return best


func _spawn_focus(world_pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = world_pos
	return n


func _fail(msg: String) -> void:
	print("[FAIL] CinematicFacingResolverTest: %s" % msg)
	get_tree().quit()
