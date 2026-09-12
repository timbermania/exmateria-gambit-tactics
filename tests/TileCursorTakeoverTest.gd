extends Node

## Reproduces and asserts on the takeover ↔ cursor interaction the GPUArena
## hits on every cinematic spell. Drives the camera through:
##
##   CURSOR → request_takeover → apply_takeover → release_takeover → CURSOR
##
## with a TileCursor present in the scene (mirroring GPUArena's wiring),
## asserting at each edge that nothing crashes and the right things happen:
##  - TAKEOVER edge hides the cursor sprite + gates its input.
##  - apply_takeover writes pos/rot/size to the camera body.
##  - release_takeover lerps back; with a cursor present, the body returns
##    toward the cursor's last-known world position.
##  - After release, cursor sprite re-shows and input ungates.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
## The schema façade for the cell type (ADR-0212 dec. 1). Cells are
## `Vector3i(x, z, level)` since ADR-0219 and `TerrainCell.ground(x, z)` is how a
## site that means the ground plane says so.
const TerrainCell = ExMateriaSchema.TerrainCell

const Lattice = ExMateriaBattlefield.Lattice
const MapConstants = ExMateriaBattlefield.MapConstants


# The HOST mount (ADR-0204 dec. 1), not the addon scene: it INHERITS the addon's
# camera, so every node path is byte-identical, and it is what production instances.
const PlayerCameraScene := preload("res://assets/scenes/CombatCamera.tscn")
const TileCursorScene := preload("res://assets/scenes/CombatCursor.tscn")


## The addon's terrain fixture (ADR-0218 dec. 1/2) — a real `Lattice` over real
## `Tile`s minted by `DynamicTerrainBuilder`, which is what this test used to build
## by hand. It replaced the host's shared cursor/camera stand-in (deleted, ADR-0210
## dec. 2's `FakeBattlefieldMap`), whose lattice overrode all five port members and
## whose cells carried nothing but `grid` — and it replaced the `extends Node` map
## wrapper with it, because a `Node3D` exposing `lattice` satisfies the
## `procedural_map_path` probe on its own.
const TerrainFixture = ExMateriaBattlefield.TerrainFixture


func _ready() -> void:
	var failed: int = await _run()
	if failed > 0:
		print("[FAIL] TileCursor takeover: %d assertion(s) failed" % failed)
	else:
		print("[PASS] TileCursor takeover: CURSOR↔TAKEOVER round-trip works without crashing")
	get_tree().quit(0 if failed == 0 else 1)


func _run() -> int:
	var failed: int = 0

	# === Set up the scene ======================================================
	var camera = PlayerCameraScene.instantiate()
	add_child(camera)

	# One square at (1,1) at the real height-0 surface — see the re-based expectation
	# at the end of the release-takeover block for where that number now comes from.
	var fixture := TerrainFixture.new()
	fixture.put(Vector2i(1, 1))
	add_child(fixture)

	# `TileCursor` has no `class_name` since ADR-0206 — the published name is
	# `CursorRig`. A test that drives the raw implementation holds it as a node.
	var cursor: Node3D = TileCursorScene.instantiate()
	cursor.procedural_map_path = fixture.get_path()
	cursor.player_camera_path = camera.get_path()
	add_child(cursor)
	await get_tree().process_frame

	# Mirror GPUArena's wiring + seed.
	# The typed handle is bound OUTSIDE the lambda: a chained `fixture.lattice.x()` is
	# criterion 2's duck-typed reach (`check_lattice_ports` arm 2 is enforcing), and the
	# port's answer is one annotated slot the calls then go through.
	var lat: Lattice = fixture.lattice
	cursor.cursor_moved.connect(func(gp: Vector2i) -> void:
		if lat.terrain_at(TerrainCell.ground(gp.x, gp.y)) != null:
			camera.follow_cursor(lat.world_position_at(TerrainCell.ground(gp.x, gp.y))))
	cursor.move_to(Vector2i(1, 1))
	camera.follow_cursor(lat.world_position_at(TerrainCell.ground(1, 1)), true)
	await get_tree().process_frame

	# === request_takeover edge =================================================
	# This is the line the cinematic spell hits ("takeover was going to happen").
	# Call it; it must not crash, must emit camera_mode_changed, and must hide
	# the cursor sprite.
	var mode_changes: Array = []
	camera.camera_mode_changed.connect(func(m) -> void: mode_changes.append(m))

	# Drive request_takeover from a RefCounted (NOT a Node) to mirror how
	# CinematicManager — which extends RefCounted — calls the same path.
	# This is the line GPUArena's cinematic spell hits and where the user
	# reported the crash.
	var rc_driver: RefCounted = RefCounted.new()
	camera.request_takeover(rc_driver)

	# Regression guard (the "hollow dagger" flash): the folded STP outline must hide in the SAME
	# synchronous camera_mode_changed handler as the opaque body — NOT a frame later in _process. Assert
	# BEFORE any process_frame (a process tick would hide the outline anyway, masking the bug). Only
	# meaningful when the outline producer exists (fork + Forward+); a no-op on stock (producer null).
	# See TileCursor._hide_dagger.
	var outline_producer = cursor._cursor_producer
	if outline_producer != null:
		var outline_carrier = outline_producer.carrier()
		if outline_carrier != null and outline_carrier.visible:
			print("[FAIL] takeover: folded STP outline still folding while the opaque body is hidden " +
				"(1-frame hollow-dagger flash — TileCursor._hide_dagger not called on the TAKEOVER edge)")
			failed += 1

	await get_tree().process_frame

	if camera.camera_mode != camera.CameraMode.TAKEOVER:
		print("[FAIL] request_takeover: camera_mode = %d, expected TAKEOVER" % camera.camera_mode)
		failed += 1
	if mode_changes.size() != 1:
		print("[FAIL] request_takeover: expected 1 mode change, got %d" % mode_changes.size())
		failed += 1
	elif mode_changes[0] != camera.CameraMode.TAKEOVER:
		print("[FAIL] request_takeover: signal emitted with %d, expected TAKEOVER" % mode_changes[0])
		failed += 1

	# Cursor's HighlightMesh child should now be hidden.
	var highlight: MeshInstance3D = cursor.get_node_or_null("HighlightMesh") as MeshInstance3D
	if highlight == null:
		print("[FAIL] takeover: cursor's HighlightMesh missing")
		failed += 1
	elif highlight.visible:
		print("[FAIL] takeover: cursor sprite still visible during TAKEOVER")
		failed += 1

	# === apply_takeover writes pos/rot/size ====================================
	var driver_pos := Vector3(10.0, 5.0, 7.5)
	var driver_rot := Vector3(0.0, deg_to_rad(90.0), 0.0)
	var driver_size := 8.5
	camera.apply_takeover(driver_pos, driver_rot, driver_size)
	await get_tree().process_frame

	if (camera.global_position - driver_pos).length() > 0.001:
		print("[FAIL] apply_takeover: global_position = %s, expected %s" % [
			str(camera.global_position), str(driver_pos)])
		failed += 1
	if absf(camera.camera.size - driver_size) > 0.001:
		print("[FAIL] apply_takeover: camera.size = %f, expected %f" % [
			camera.camera.size, driver_size])
		failed += 1

	# === release_takeover lerps back ===========================================
	mode_changes.clear()
	camera.release_takeover()
	await get_tree().process_frame

	if camera.camera_mode != camera.CameraMode.CURSOR:
		print("[FAIL] release_takeover: camera_mode = %d, expected CURSOR" % camera.camera_mode)
		failed += 1
	if mode_changes.size() != 1 or mode_changes[0] != camera.CameraMode.CURSOR:
		print("[FAIL] release_takeover: mode-change signal didn't fire CURSOR (got %s)" % str(mode_changes))
		failed += 1

	# Wait for the 16-frame return ease to finish.
	for _i in 20:
		await get_tree().process_frame

	# Cursor present → body lerps back toward the cursor's tile world position, which
	# is the tile CENTRE, not the grid corner (ADR-0218 dec. 3): `DynamicTerrainBuilder`
	# puts a tile at the mean of its four corners, so square (1,1) at height 0 sits at
	# (1.5, (12·0 + 1)/28, 1.5). The old double answered (1, 0, 1) and this assertion
	# was written against the double. It is spelled out rather than fetched from the
	# port so that the port and the camera are not both allowed to be wrong together.
	var expected_pos := Vector3(1.5, MapConstants.surface_y(0), 1.5)
	if (camera.global_position - expected_pos).length() > 0.1:
		print("[FAIL] release_takeover: after ease, body at %s, expected near cursor tile %s" % [
			str(camera.global_position), str(expected_pos)])
		failed += 1

	# Cursor sprite should be visible again.
	if highlight and not highlight.visible:
		print("[FAIL] post-release: cursor sprite still hidden after return to CURSOR mode")
		failed += 1

	# === Cursor input ungates after release ====================================
	var cursor_events: Array = []
	cursor.cursor_moved.connect(func(_gp: Vector2i) -> void: cursor_events.append(1))
	# Verify the input handler accepted the action by checking the held direction advanced
	# (the actual step is clamp-refused since only (1,1) has a tile).
	#
	# [b]`held_action()`, not the field.[/b] Reading `cursor._held_action` here kept working
	# by accident until the field became a list, and then it raised a SCRIPT ERROR — which
	# skips the comparison and leaves the whole check unevaluated, while the run still
	# reports PASS. Measured: 1 SCRIPT ERROR, verdict unchanged.
	var ev := InputEventAction.new()
	ev.action = &"camera_up"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	if cursor.held_action() != &"camera_up":
		print("[FAIL] post-release: cursor input gated even though mode is CURSOR")
		failed += 1
	ev.pressed = false
	Input.parse_input_event(ev)
	return failed

