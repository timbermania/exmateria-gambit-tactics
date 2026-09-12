extends Node

## End-to-end test for the W-press → cursor → camera → SFX chain.
##
## Verifies the actual user-visible behavior the handoff promised:
##  1. A synthetic "camera_up" press advances the cursor's grid_pos by the
##     camera-relative cardinal delta (at default yaw, W → +X / NORTH).
##  2. cursor_moved fires with the new grid_pos + tile.
##  3. PlayerCamera.follow_cursor is invoked, updating _follow_target to the
##     new tile's world position.
##  4. SfxRouter.cue_requested fires with name="ui.cursor_move", bank="system",
##     slot=3 (the canonical FFT Move Cursor sample) — driven by
##     `BattlefieldWiring.wire_cursor`, which is where the host connects
##     `cursor_stepped` to the cue since #589 inverted that reach out of the addon.
##  5. Grid clamp: pressing into an empty cell does NOT advance grid_pos and
##     does NOT play the cue (no off-grid step).
##  6. Free-pan override (PlayerCamera.free_camera()) gates the cursor's
##     input handler — W press is ignored, no cursor_moved, no cue.
##
## Synthesizes input via Input.parse_input_event(InputEventAction) so the
## test exercises the real _unhandled_input + _try_step + emit chain, not a
## white-box direct call into _try_step.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
## The schema façade for the cell type (ADR-0212 dec. 1). Cells are
## `Vector3i(x, z, level)` since ADR-0219 and `TerrainCell.ground(x, z)` is how a
## site that means the ground plane says so.
const TerrainCell = ExMateriaSchema.TerrainCell

const CursorRig = ExMateriaBattlefield.CursorRig
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

## The free-pan gate's slug, spelled here rather than read off `PlayerCamera`
## (ADR-0210 dec. 3). `PlayerCamera` is an addon `class_name` that
## `DECLARED_PUBLISHED` does not name, so naming it as a type is an arm-3 reach —
## and a Tune slug is a STRING KEY, not a compiled symbol, so the type reference
## bought nothing the literal does not.
##
## 🔴 A BARE LITERAL WOULD ROT SILENTLY if the camera renamed the slug, which is
## the whole reason the reach existed. So the spelling is CHECKED against the
## registry the camera itself binds — `PlayerCamera._static_init()` calls
## `register_tunables()` at CLASS LOAD, so instantiating the mount registers it.
## The `Tune.is_registered()` guard in the free-pan block below is the assertion,
## and it is a PREDICATE and not a tautology — measured, not reasoned: a scene that
## loads nothing reads `false` for this slug. Same shape as ADR-0209 dec. 3's
## `Tune.is_registered("cursor.height")`, which is the ruling that also says why the
## const read is DELETED rather than moved to the schema.
const FREE_CAMERA_SLUG := "camera.free_camera_enabled"


func _ready() -> void:
	var failed: int = await _run()
	if failed > 0:
		print("[FAIL] TileCursor integration: %d assertion(s) failed" % failed)
	else:
		print("[PASS] TileCursor integration: W-press → cursor → camera → SFX chain works end-to-end")
	get_tree().quit(0 if failed == 0 else 1)


func _run() -> int:
	var failed: int = 0

	# === Set up the fake battlefield ===========================================
	var camera = PlayerCameraScene.instantiate()
	add_child(camera)
	# CharacterBody3D._ready resolved $FocusPoint and $FocusPoint/Camera by now.

	# 3x3 grid centred on (1, 1), all at height 0. Square (1, 2) is INTENTIONALLY
	# never `put` so the off-grid clamp has something to refuse — a hole in a fixture
	# is a cell nobody stated, which is how `terrain.json` states one too (a `null` in
	# the row), so the clamp meets the same absence production would give it.
	#
	# This used to be a literal table of eight world positions on the grid CORNERS.
	# The positions are gone: a square's world position is `DynamicTerrainBuilder`'s
	# to compute now, and it computes the tile CENTRE (ADR-0218 dec. 3). The one
	# assertion that read a number out of the table is re-based below.
	var fixture := TerrainFixture.new()
	for coord in [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2),                 Vector2i(2, 2),
	]:
		fixture.put(coord)
	add_child(fixture)

	# `TileCursor` has no `class_name` since ADR-0206 — the published name is
	# `CursorRig`. A test that drives the raw implementation holds it as a node.
	var cursor: Node3D = TileCursorScene.instantiate()
	cursor.procedural_map_path = fixture.get_path()
	cursor.player_camera_path = camera.get_path()
	add_child(cursor)
	await get_tree().process_frame  # let _ready resolve refs, mesh build, signal connect

	# Wire cursor → camera follow the same way GPUArena does (the host's job).
	# Through the lattice, because that is all the payload names now (ADR-0194): the
	# signal carries `grid_pos`, and a world position for it is `world_position_at`.
	# `terrain_at` first — `Vector3.ZERO` is both "no tile" and the origin tile's own
	# position, which is the ambiguity `Lattice.world_position_at`'s ⚠️ warns about.
	# The typed handle is bound OUTSIDE the lambda: a chained `fixture.lattice.x()` is
	# criterion 2's duck-typed reach (`check_lattice_ports` arm 2 is enforcing), and the
	# port's answer is one annotated slot the calls then go through.
	var lat: Lattice = fixture.lattice
	cursor.cursor_moved.connect(func(gp: Vector2i) -> void:
		if lat.terrain_at(TerrainCell.ground(gp.x, gp.y)) != null:
			camera.follow_cursor(lat.world_position_at(TerrainCell.ground(gp.x, gp.y))))

	# ...and cursor → SFX the way GPUArena does too, which after #589 is the same
	# call: `SfxRouter.play_cue("ui.cursor_move")` used to sit INSIDE `_try_step`,
	# one line below the `cursor_moved.emit`. Without this line the cue assertion
	# below fails and nothing else does, which is the severance being exact — the
	# step, the emit, the camera follow, the off-grid clamp and the free-pan gate
	# are all still the cursor's own. This is now the end-to-end test of the
	# assembler seam, not just of the cursor.
	# Through the published port, because that is what the host passes now (ADR-0206):
	# `wire_cursor` takes a `CursorRig`, and the rig relays `cursor_stepped` from the
	# cursor it binds. Binding also stands up the CursorController — the same one
	# GPUArena gets — so this is still the shipped seam and not a test-only shortcut.
	var rig := CursorRig.bind(self, cursor, camera)
	BattlefieldWiring.wire_cursor(rig)

	# === Listeners =============================================================
	var cursor_events: Array = []  # of {grid_pos}
	cursor.cursor_moved.connect(func(gp: Vector2i) -> void:
		cursor_events.append({"grid_pos": gp}))

	var sfx_events: Array = []  # of {name, bank, slot}
	SfxRouter.cue_requested.connect(func(n: String, b: String, s: int) -> void:
		sfx_events.append({"name": n, "bank": b, "slot": s}))

	# === Seed cursor on (1, 1). The seed move_to() should fire cursor_moved
	# BUT must NOT play the cue (scene-load shouldn't make noise). ============
	cursor_events.clear()
	sfx_events.clear()
	cursor.move_to(Vector2i(1, 1))
	await get_tree().process_frame
	if cursor_events.size() != 1:
		print("[FAIL] seed: expected 1 cursor_moved, got %d" % cursor_events.size())
		failed += 1
	if not sfx_events.is_empty():
		print("[FAIL] seed: move_to() played %d cue(s) — scene load shouldn't make noise" % sfx_events.size())
		failed += 1
	if cursor.grid_pos != Vector2i(1, 1):
		print("[FAIL] seed: grid_pos = %s, expected (1, 1)" % str(cursor.grid_pos))
		failed += 1

	# === Press W. At default yaw (-45°), screen-up cardinal is +X. ==============
	cursor_events.clear()
	sfx_events.clear()
	_press_action(&"camera_up")
	await get_tree().process_frame
	_release_action(&"camera_up")
	await get_tree().process_frame

	if cursor.grid_pos != Vector2i(2, 1):
		print("[FAIL] W: grid_pos = %s, expected (2, 1)  [default yaw -45° → screen-up = +X]" % str(cursor.grid_pos))
		failed += 1
	if cursor_events.size() != 1:
		print("[FAIL] W: expected 1 cursor_moved, got %d" % cursor_events.size())
		failed += 1
	elif cursor_events[0]["grid_pos"] != Vector2i(2, 1):
		print("[FAIL] W: cursor_moved fired with grid_pos %s, expected (2, 1)" % str(cursor_events[0]["grid_pos"]))
		failed += 1

	# The tile CENTRE of square (2,1) at height 0 — `(gx + 0.5, (12·h + 1)/28, gz + 0.5)`
	# (ADR-0218 dec. 3). The old double answered the grid corner `(2, 0, 1)`; the
	# number is spelled out rather than fetched back through `world_position_at` so the
	# port and the camera cannot agree on a wrong answer.
	var expected_world := Vector3(2.5, MapConstants.surface_y(0), 1.5)
	if not camera._follow_has_target:
		print("[FAIL] W: PlayerCamera._follow_has_target false — follow_cursor was not called")
		failed += 1
	elif (camera._follow_target - expected_world).length() > 0.001:
		print("[FAIL] W: PlayerCamera._follow_target = %s, expected %s" % [
			str(camera._follow_target), str(expected_world)])
		failed += 1

	if sfx_events.size() != 1:
		print("[FAIL] W: expected 1 cue_requested, got %d" % sfx_events.size())
		failed += 1
	else:
		var ev: Dictionary = sfx_events[0]
		if ev["name"] != "ui.cursor_move":
			print("[FAIL] W: cue name = '%s', expected 'ui.cursor_move'" % ev["name"])
			failed += 1
		if ev["bank"] != "system" or ev["slot"] != 3:
			print("[FAIL] W: cue routed to {bank=%s, slot=%d}, expected {system, 3} (Move Cursor)" % [
				ev["bank"], ev["slot"]])
			failed += 1

	# === Clamp: press S from (2, 1) toward an off-grid cell. ===================
	# At default yaw, screen-down is -X → from (2, 1) tries (3, 1), which has
	# no tile. Cursor should refuse to advance and SHOULD NOT play the cue.
	cursor_events.clear()
	sfx_events.clear()
	# Hmm: from (2, 1), -X → (3, 1) is off-grid; let's actually go the other way.
	# Use camera_left: screen-left at -45° yaw = -screen_right = -(forward × UP).
	# screen_forward = (+x, 0, -z) ~ (0.707, 0, -0.707), screen_right = forward × UP = (-z, 0, -x).
	# Wait — easier: walk the cursor to (2, 2) by pressing camera_right (which
	# at default yaw maps to +Z / EAST). From (2, 1) → (2, 2) is on-grid.
	_press_action(&"camera_right")
	await get_tree().process_frame
	_release_action(&"camera_right")
	await get_tree().process_frame
	if cursor.grid_pos != Vector2i(2, 2):
		print("[FAIL] D: grid_pos = %s, expected (2, 2)  [default yaw -45° → screen-right = +Z]" % str(cursor.grid_pos))
		failed += 1
	# Now from (2, 2), press camera_up again — that's (3, 2) which is off-grid.
	cursor_events.clear()
	sfx_events.clear()
	_press_action(&"camera_up")
	await get_tree().process_frame
	_release_action(&"camera_up")
	await get_tree().process_frame
	if cursor.grid_pos != Vector2i(2, 2):
		print("[FAIL] clamp: grid_pos = %s, expected (2, 2) (off-grid step should be refused)" % str(cursor.grid_pos))
		failed += 1
	if not cursor_events.is_empty():
		print("[FAIL] clamp: cursor_moved fired %d time(s) on off-grid step" % cursor_events.size())
		failed += 1
	if not sfx_events.is_empty():
		print("[FAIL] clamp: cue_requested fired %d time(s) on off-grid step" % sfx_events.size())
		failed += 1

	# === Free-pan override: cursor input gated. ================================
	if not Tune.is_registered(FREE_CAMERA_SLUG):
		print("[FAIL] free-pan: `%s` is not a registered slug — the camera renamed "
			  % FREE_CAMERA_SLUG + "it and this test's spelling went stale")
		failed += 1
	Tune.set_value(FREE_CAMERA_SLUG, true)
	cursor_events.clear()
	sfx_events.clear()
	_press_action(&"camera_left")  # at default yaw, screen-left = -Z (would move to (2, 1))
	await get_tree().process_frame
	_release_action(&"camera_left")
	await get_tree().process_frame
	if cursor.grid_pos != Vector2i(2, 2):
		print("[FAIL] free-pan: grid_pos = %s, expected (2, 2) (cursor input must be gated)" % str(cursor.grid_pos))
		failed += 1
	if not cursor_events.is_empty():
		print("[FAIL] free-pan: cursor_moved fired %d time(s) while free-pan was active" % cursor_events.size())
		failed += 1
	if not sfx_events.is_empty():
		print("[FAIL] free-pan: cue_requested fired %d time(s) while free-pan was active" % sfx_events.size())
		failed += 1
	# === Free-pan's own directions are EVENTS too. =============================
	# The cursor is gated in free-pan, but `PlayerCamera._execute_translation` is NOT — it
	# panned the body off four `Input.is_action_pressed` reads a frame, which is the poll
	# `check_focus_anchor.py` listed PlayerCamera for. Asserted on the tracked set rather
	# than on `global_position`: the consumer is `move_and_slide()` on a body in a scene with
	# no floor, so motion is not the observable here.
	if camera.pan_directions_held() != ([] as Array[StringName]):
		print("[FAIL] free-pan: camera starts with %s held, expected none"
				% str(camera.pan_directions_held()))
		failed += 1
	_press_action(&"camera_up")
	await get_tree().process_frame
	if not camera.pan_directions_held().has(&"camera_up"):
		print("[FAIL] free-pan: a delivered press is not held — got %s"
				% str(camera.pan_directions_held()))
		failed += 1
	# The poll's signature: a direction the singleton claims with no event behind it.
	Input.action_press(&"camera_right")
	await get_tree().process_frame
	if camera.pan_directions_held().has(&"camera_right"):
		print("[FAIL] free-pan: a direction no event delivered is held — something still "
				+ "polls Input (%s)" % str(camera.pan_directions_held()))
		failed += 1
	Input.action_release(&"camera_right")
	# Alt-tab, whose release never arrives.
	camera.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	if not camera.pan_directions_held().is_empty():
		print("[FAIL] free-pan: losing the window left %s held"
				% str(camera.pan_directions_held()))
		failed += 1
	_release_action(&"camera_up")
	await get_tree().process_frame

	# Trunk moved free-camera off `DebugConfig` onto a Tune slug; the enable at the top of
	# this block already uses it, so the disable matches.
	Tune.set_value(FREE_CAMERA_SLUG, false)

	# === The held set is EVENTS, and only events. ==============================
	# `check_focus_anchor.py` lists this file for two polls of the `Input` singleton:
	# `_process` re-asked whether the tracked action was still down, and
	# `_latest_pressed_action()` scanned all four to find a replacement. A poll is the one
	# thing Focus structurally cannot gate — the switch stops Godot CALLING a non-holder, it
	# cannot stop one ASKING — so the fix is to stop asking, and these arms are what says
	# the asking is gone.

	# Latest-press-wins, and the fallback when the newer press is released. The old
	# `_latest_pressed_action()` answered this by polling, which is why it read TABLE order
	# (`CURSOR_ACTIONS`) in a machine whose whole rule is press order.
	_press_action(&"camera_up")
	await get_tree().process_frame
	_press_action(&"camera_right")
	await get_tree().process_frame
	if cursor.held_action() != &"camera_right":
		print("[FAIL] roll: held_action = '%s', expected 'camera_right' (latest press wins)"
				% cursor.held_action())
		failed += 1
	_release_action(&"camera_right")
	await get_tree().process_frame
	if cursor.held_action() != &"camera_up":
		print("[FAIL] roll: after releasing the newer press, held_action = '%s', expected "
				% cursor.held_action() + "'camera_up' — the older one is still down")
		failed += 1
	_release_action(&"camera_up")
	await get_tree().process_frame
	if cursor.held_action() != &"":
		print("[FAIL] roll: after both releases, held_action = '%s', expected none"
				% cursor.held_action())
		failed += 1

	# The singleton write with NO event behind it. This is the poll's signature: a direction
	# `Input` claims is down that was never delivered to this node must not be able to take
	# over the repeat.
	_press_action(&"camera_up")
	await get_tree().process_frame
	Input.action_press(&"camera_left")
	_release_action(&"camera_up")
	await get_tree().process_frame
	if cursor.held_action() != &"":
		print("[FAIL] singleton: held_action = '%s' — a direction no event delivered took "
				% cursor.held_action() + "over the repeat, so something still polls Input")
		failed += 1
	Input.action_release(&"camera_left")

	# Alt-tab. The poll covered this for free: the key comes up while the window is not
	# focused, the release is never delivered, and the next frame's `is_action_pressed` saw
	# it gone. Tracking has to be told, or the cursor auto-repeats forever on return.
	_press_action(&"camera_up")
	await get_tree().process_frame
	if cursor.held_action() != &"camera_up":
		print("[FAIL] focus-out: setup — held_action = '%s', expected 'camera_up'"
				% cursor.held_action())
		failed += 1
	cursor.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	if cursor.held_action() != &"":
		print("[FAIL] focus-out: held_action = '%s' — losing the window must drop the held "
				% cursor.held_action() + "direction, since its release will never arrive")
		failed += 1
	_release_action(&"camera_up")
	await get_tree().process_frame

	return failed



func _press_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _release_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
