extends Node
# test-kind: logic
# seeded-break: EffectViewerScene.reconcile_studio_camera's ownership branch inverted (`free_cam or frame <= 0` -> `free_cam or frame > 0`, the scene now owns the camera while the effect plays and releases while parked) — frame-0 CURSOR/dagger-visible, frame-5 TAKEOVER/dagger-hidden, held-frame-42, frame-0-reclaim, and the two free-cam-OFF re-acquire arms red; the free-cam-ON arms stay green (invariant under the inversion); GREEN unbroken on the reverted tree

## TDD guard for the Effect Studio camera-ownership invariant:
##
##   The camera owner is a PURE FUNCTION OF THE PLAYHEAD.
##     frame 0  → the SCENE (tile cursor) owns the camera; dagger visible.
##     frame ≠ 0 → the EDITOR (effect) owns the camera (TAKEOVER); dagger hidden.
##
## This is the fix for the "no cursor at boot" regression: selecting/parking a
## camera-bearing effect at frame 0 must NOT seize the camera. Only moving the
## playhead past 0 (Play/scrub) hands it to the effect; returning to 0 (Stop/
## scrub-to-0) hands it back to the cursor.
##
## We drive the REAL EffectViewerScene.reconcile_studio_camera() against a REAL
## PlayerCamera + TileCursor (the shipping coupling), asserting camera_mode AND
## the dagger's visibility at each playhead position. The `acquire` callable
## mirrors the host's _acquire_effect_camera by requesting takeover on the real
## camera, so we exercise the actual CURSOR↔TAKEOVER machinery — not a mock.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/EffectStudioCameraOwnershipTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
## The schema façade for the cell type (ADR-0212 dec. 1). Cells are
## `Vector3i(x, z, level)` since ADR-0219 and `TerrainCell.ground(x, z)` is how a
## site that means the ground plane says so.
const TerrainCell = ExMateriaSchema.TerrainCell

const Lattice = ExMateriaBattlefield.Lattice


const EffectViewerScene := preload("res://src/scenes/EffectViewerScene.gd")
# The HOST mount (ADR-0204 dec. 1), not the addon scene: it INHERITS the addon's
# camera, so every node path is byte-identical, and it is what production instances.
const PlayerCameraScene := preload("res://assets/scenes/CombatCamera.tscn")
const TileCursorScene := preload("res://assets/scenes/CombatCursor.tscn")

var _failed: int = 0


## The addon's terrain fixture (ADR-0218 dec. 1/2) — a real `Lattice` over real
## `Tile`s minted by `DynamicTerrainBuilder`, which is what this test used to build
## by hand. It replaced the host's shared cursor/camera stand-in (deleted, ADR-0210
## dec. 2's `FakeBattlefieldMap`), whose lattice overrode all five port members and
## whose cells carried nothing but `grid` — and it replaced the `extends Node` map
## wrapper with it, because a `Node3D` exposing `lattice` satisfies the
## `procedural_map_path` probe on its own.
const TerrainFixture = ExMateriaBattlefield.TerrainFixture


## A minimal stand-in for the live EffectInstance: exposes the two things
## studio_set_free_camera's rescrub touches — a camera_controller (presence gates
## the rescrub; effects with no camera don't need one) and a seek() recorder.
class _FakeEffect extends Node:
	var camera_controller = RefCounted.new()   # non-null → "this effect drives a camera"
	var _frame: int = 0
	var seeks: Array = []
	var refolds: int = 0
	func get_effect_frame() -> int:
		return _frame
	func seek(f: int) -> void:
		seeks.append(f)
	func refold() -> void:
		refolds += 1


func _ready() -> void:
	await _run()
	_run_freecam_rescrub()
	if _failed > 0:
		print("[FAIL] EffectStudioCameraOwnership: %d assertion(s) failed" % _failed)
	else:
		print("[PASS] EffectStudioCameraOwnership: owner is a pure function of the playhead (0=cursor, ≠0=effect); free-cam OFF rescrubs")
	get_tree().quit(1 if _failed > 0 else 0)


## Turning free-cam OFF at a frame > 0 re-acquires the effect camera, which seeds a
## FRESH base pose. The camera controller only recomputes its pose on a clock
## advance, so a PARKED effect would sit at the bare base until played. The host
## must force a deterministic rescrub (reset → re-pump to the current frame) so the
## effect camera pose is recomputed against the new base immediately. Turning it ON
## must NOT rescrub (the effect keeps its clock; only ownership changes).
func _run_freecam_rescrub() -> void:
	var host = EffectViewerScene.new()
	var fake := _FakeEffect.new()
	fake._frame = 40
	host._current_effect = fake

	# Toggle ON: hands the camera to the scene, effect clock untouched — no rescrub.
	host.studio_set_free_camera(true)
	_expect(fake.refolds == 0,
		"free-cam ON must not rescrub, got %d refold(s)" % fake.refolds)

	# Toggle OFF at frame 40: rescrub the current frame (refold = reset → re-pump), so the
	# effect camera pose recomputes against the fresh base without scrubbing away and back.
	host.studio_set_free_camera(false)
	_expect(fake.refolds == 1,
		"free-cam OFF must rescrub the current frame via refold(), got %d refold(s)" % fake.refolds)

	host.free()


func _run() -> void:
	# === Real PlayerCamera + TileCursor on a one-tile map (shipping wiring) =====
	var camera = PlayerCameraScene.instantiate()
	add_child(camera)

	# One square at (1,1), at the real height-0 surface. It used to be one hand-made
	# `Tile` pinned to `Vector3(1, 0, 1)` — the grid corner. Production puts a tile at
	# the MEAN of its four corners, so the same square is really at (1.5, 0.036, 1.5)
	# (ADR-0218 dec. 3). Nothing below reads the number; the camera is aimed through
	# `world_position_at`, which is why the re-base costs this file no assertion.
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

	cursor.move_to(Vector2i(1, 1))
	# ONE typed fetch at the seam, `Lattice`-typed from here on (ADR-0192 dec. 3): a
	# chained `fixture.lattice.x()` is criterion 2's duck-typed reach and
	# `check_lattice_ports` arm 2 is enforcing.
	var lat: Lattice = fixture.lattice
	camera.follow_cursor(lat.world_position_at(TerrainCell.ground(1, 1)), true)
	await get_tree().process_frame

	var highlight: MeshInstance3D = cursor.get_node_or_null("HighlightMesh") as MeshInstance3D
	if highlight == null:
		print("[FAIL] setup: cursor HighlightMesh missing")
		_failed += 1
		return

	# `acquire` mirrors the host's _acquire_effect_camera: put the real camera
	# into TAKEOVER. Idempotent (the mode setter no-ops when already TAKEOVER).
	var acquire := func() -> void: camera.request_takeover(self)

	# === Frame 0: scene owns the camera, dagger visible (BOOT/SELECT state) =====
	# Start in CURSOR; reconciling at frame 0 must LEAVE it in CURSOR (no takeover
	# on load) — this is the regression that hid the cursor at boot.
	EffectViewerScene.reconcile_studio_camera(camera, 0, acquire)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.CURSOR,
		"frame 0 → CURSOR (scene owns), got mode %d" % camera.camera_mode)
	_expect(highlight.visible, "frame 0 → dagger visible")

	# === Frame > 0: editor owns the camera, dagger hidden (PLAY / SCRUB) ========
	EffectViewerScene.reconcile_studio_camera(camera, 5, acquire)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.TAKEOVER,
		"frame 5 → TAKEOVER (effect owns), got mode %d" % camera.camera_mode)
	_expect(not highlight.visible, "frame 5 → dagger hidden")

	# === A further frame > 0 (still playing / natural-end freeze) stays TAKEOVER =
	# The reconcile calls acquire every frame > 0; it must be idempotent, not
	# thrash the mode or re-show the cursor.
	EffectViewerScene.reconcile_studio_camera(camera, 42, acquire)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.TAKEOVER,
		"frame 42 (held) → still TAKEOVER, got mode %d" % camera.camera_mode)
	_expect(not highlight.visible, "frame 42 (held) → dagger still hidden")

	# === Back to frame 0: scene reclaims the camera, dagger returns (STOP) ======
	EffectViewerScene.reconcile_studio_camera(camera, 0, acquire)
	# Let release_takeover's return ease finish and the cursor re-show.
	for _i in 20:
		await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.CURSOR,
		"frame 0 again → CURSOR (scene reclaims), got mode %d" % camera.camera_mode)
	_expect(highlight.visible, "frame 0 again → dagger visible")

	# === Free camera: force the scene-owns branch regardless of the playhead ====
	# A debug toggle to fly the camera while the effect keeps playing. `free_cam`
	# is a SECOND input to ownership: the scene owns the camera when free_cam is on
	# OR the playhead is at 0. It behaves exactly like frame 0 at any frame.

	# Get back into TAKEOVER first (frame > 0, free_cam off = today's behavior).
	EffectViewerScene.reconcile_studio_camera(camera, 30, acquire, false)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.TAKEOVER,
		"free-cam setup: frame 30, free_cam off → TAKEOVER, got %d" % camera.camera_mode)

	# Toggle free-cam ON at a frame > 0: the effect keeps playing but the camera is
	# handed back to the scene (cursor returns), exactly like scrubbing to frame 0.
	EffectViewerScene.reconcile_studio_camera(camera, 30, acquire, true)
	for _i in 20:
		await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.CURSOR,
		"free-cam ON at frame 30 → CURSOR (scene owns), got %d" % camera.camera_mode)
	_expect(highlight.visible, "free-cam ON at frame 30 → dagger visible")

	# Still free-cam ON at a later frame: stays with the scene (never re-acquires).
	EffectViewerScene.reconcile_studio_camera(camera, 60, acquire, true)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.CURSOR,
		"free-cam ON at frame 60 → still CURSOR, got %d" % camera.camera_mode)

	# Toggle free-cam OFF at a frame > 0: the effect re-takes the camera.
	EffectViewerScene.reconcile_studio_camera(camera, 60, acquire, false)
	await get_tree().process_frame
	_expect(camera.camera_mode == camera.CameraMode.TAKEOVER,
		"free-cam OFF at frame 60 → TAKEOVER (effect reclaims), got %d" % camera.camera_mode)
	_expect(not highlight.visible, "free-cam OFF at frame 60 → dagger hidden")


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed += 1

