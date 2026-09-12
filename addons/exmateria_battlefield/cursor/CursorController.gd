extends Node

## Wires a TileCursor to a PlayerCamera and the map's tile highlights, so a host
## scene gets full cursor behaviour by dropping in one node instead of copy-
## pasting the glue. Owns three responsibilities that every cursor host shared:
##
##   - camera-follow: forward TileCursor.cursor_moved → PlayerCamera.track_cursor
##   - tile highlight: paint CURSOR_ACTIVE into the cursor's own SLOT of the cell
##     under it, and empty that slot when the cursor leaves
##
## The highlight tracks camera mode: on TAKEOVER (an effect drives the camera)
## the TileCursor hides its dagger, so we empty the cursor slot too — otherwise a
## stray CURSOR_ACTIVE overlay lingers under a hidden cursor — then repaint when
## control returns to CURSOR mode.
##
## 🔴 IT PAINTS THROUGH THE PUBLISH AND REMEMBERS NOTHING (ADR-0221 dec. 4). There
## used to be an `_active_prev_type` here: the highlight the cursor displaced when
## it ARRIVED, put back when it left. That value is stale by construction — anything
## painting the tile in between made it a lie — so the cursor's restore-on-leave
## erased a march pick, and a `_process` override re-asserted CURSOR_ACTIVE every
## frame to paper over the same collision on the one square where it did not show.
## Both are gone. `TileHighlights` stacks the markings in slots and hands the tile
## the topmost, so emptying the cursor's slot reveals whatever is beneath it and
## there is nothing for this file to save.
##
## The TileCursor stays deliberately dumb (it only emits signals); this is the
## piece that knows about the camera and the highlights. Build/seed *timing* is
## left to the host — it legitimately differs per scene (GPUArena seeds inline
## after apply_scenario; EffectViewer rebuilds via change_map) — so the host
## calls seed_from_map() once its map's tiles exist.

## 🔴 THIS FILE HAS NO `class_name`, AND THAT IS THE DECISION (ADR-0206, applying
## ADR-0192 dec. 4 a second time). ADR-0164 dec. 4 criterion 1 scans `class_name`s, so a
## type without one cannot be in the published set — and a door on a class nobody can name
## is not a door. Four host scenes used to write `CursorController.new()`; they now name
## `CursorRig`, which `preload`s this. The runner-up was keeping the name and asking hosts
## to prefer the rig, which makes *published* a naming convention — the exact thing
## criterion 1 exists to replace.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const TileHighlights = preload("res://addons/exmateria_battlefield/overlay/TileHighlights.gd")

const TileCursorScript := preload("res://addons/exmateria_battlefield/cursor/TileCursor.gd")

var _cursor: TileCursorScript
var _camera  # PlayerCamera — untyped because PlayerCamera declares no class_name, so it can't be statically typed here (same as TileCursor._player_camera)

# The cell currently wearing CURSOR_ACTIVE in the cursor's slot, as a CELL and not a
# node (ADR-0219 dec. 1): the publish is keyed by `Vector3i`, so holding the node
# would only be a second handle on the same square. `TerrainCell.NONE` means the
# cursor has painted nothing yet.
var _active_cell: Vector3i = TerrainCell.NONE

# The highlight publish, acquired from the map in `seed_from_map` — the same place
# and the same one-untyped-step read the `Lattice` comes from. `null` until then, and
# a controller with no publish simply paints nothing.
var _highlights: TileHighlights = null


## Bind the cursor + camera and start listening for cursor moves. Idempotent —
## safe to call more than once (the signal connect is guarded).
func setup(cursor: TileCursorScript, camera) -> void:
	_cursor = cursor
	_camera = camera
	if _cursor != null and not _cursor.cursor_moved.is_connected(_on_cursor_moved):
		_cursor.cursor_moved.connect(_on_cursor_moved)
	if _camera != null and _camera.has_signal("camera_mode_changed") \
			and not _camera.camera_mode_changed.is_connected(_on_camera_mode_changed):
		_camera.camera_mode_changed.connect(_on_camera_mode_changed)


## Seed the cursor onto `preferred` if that grid pos has a tile, else the first
## known tile; snap the camera onto it. Hosts call this once the map is built,
## and again after any map change (the old grid pos may be off the new grid).
func seed_from_map(map, preferred: Vector2i, snap_camera: bool = true) -> void:
	# Through the PORT (ADR-0164 dec. 2), which is the whole of what this needs: a
	# cell to exist and a world position to aim the camera at. `map` itself stays
	# untyped — it is `$ProceduralMap`, which infers `Node`, and ADR-0192 dec. 3
	# accepts exactly one untyped step at the seam. The port answers null/[] before
	# the grid exists, as the old `get_tile` / `get_all_tiles` facade did.
	if _cursor == null or map == null or not ("lattice" in map):
		return
	# The map's other published surface (ADR-0164 dec. 1), read the same way and at
	# the same moment as the port. A map that exposes no publish leaves this null and
	# the cursor simply paints nothing — which is what a bare scene wants.
	_highlights = map.highlights if "highlights" in map else null
	var lattice: Lattice = map.lattice
	if lattice == null:
		return
	# `ground_at` and not `terrain_at`: `preferred` is a COLUMN the host names, and the
	# cursor seats on the ground of it (see `TileCursor._get_tile_at`).
	var cell: TerrainCell = lattice.ground_at(preferred.x, preferred.y)
	if cell == null:
		var cells: Array[TerrainCell] = lattice.all_cells()
		if cells.is_empty():
			return
		cell = cells[0]
	# move_to emits cursor_moved → _on_cursor_moved → camera.track_cursor, which
	# only *eases* on a re-seed. Follow with an explicit camera move so a fresh seed
	# (and every map-change re-seed) actually frames the tile instead of leaving the
	# camera on the old focus.
	#
	# `snap_camera` picks WHICH move, and the two cases are real (#1168). A bare scene
	# boot has no framing worth preserving and hard-cuts onto the tile, which is what
	# this always did. A seed at the end of a battle intro is taking over a camera the
	# cinematic just posed, and there the hard cut is a 6.64-unit jerk the player sees
	# the frame the dark screen finishes retracting — so that caller eases.
	var world_pos: Vector3 = lattice.world_position_at(cell.grid)
	var easing: bool = _camera != null and not snap_camera and _camera.has_method("ease_onto")
	# 🔴 PRIME THE EASE BEFORE `move_to`, NOT AFTER. `move_to` emits `cursor_moved` ->
	# `_on_cursor_moved` -> `PlayerCamera.track_cursor`, and track_cursor's FIRST call
	# ("no prior target") hard-snaps the body itself. So an ease applied afterwards had
	# nothing left to travel — target and position were already the same point, and the
	# 6.6425-unit cut still landed, from inside `move_to`. Priming here gives track_cursor
	# a prior target, which sends it down its deadzone path instead.
	if easing:
		_camera.ease_onto(world_pos)
	_cursor.move_to(Vector2i(cell.grid.x, cell.grid.y))
	if _camera != null:
		if easing:
			# Again after the move: track_cursor may have re-aimed at a deadzone-clamped
			# point, and this is the authoritative target.
			_camera.ease_onto(world_pos)
		else:
			_camera.follow_cursor(world_pos, true)


## The cursor publishes a `Vector2i` and nothing else (ADR-0194). The highlight is a
## per-NODE property, so this asks the cursor for the node it just derived — an
## addon-internal read, which is the permitted half of criterion 3 and the reason
## `_tile_under_cursor()` survived the close rather than being deleted.
func _on_cursor_moved(_grid_pos: Vector2i) -> void:
	var tile := _cursor._tile_under_cursor()
	_set_active_cell(tile.cell_key if tile != null else TerrainCell.NONE)
	if tile != null and _camera != null:
		_camera.track_cursor(tile.global_position)


## Move CURSOR_ACTIVE from whichever cell holds it to `cell`, through the publish.
##
## The old cell's slot is EMPTIED rather than restored: what is underneath it was
## never this file's to remember, and the publish still holds it (ADR-0221 dec. 1).
func _set_active_cell(cell: Vector3i) -> void:
	if cell == _active_cell:
		return
	if _highlights != null and _active_cell != TerrainCell.NONE:
		_highlights.clear(_active_cell, CellMarking.Kind.CURSOR_ACTIVE)
	_active_cell = cell
	if _highlights != null and cell != TerrainCell.NONE:
		_highlights.paint(cell, CellMarking.Kind.CURSOR_ACTIVE)


## Follow the TileCursor's own show/hide: clear the tile highlight when the camera
## is taken over (dagger hidden), repaint it when control returns to the cursor.
## A bare `else`, which it could not be before: emptying the cursor's own slot cannot
## touch a marking that is not the cursor's, so a takeover has nothing to check and
## nothing to hand back.
func _on_camera_mode_changed(new_mode) -> void:
	if _highlights == null or _active_cell == TerrainCell.NONE:
		return
	if _camera != null and new_mode == _camera.CameraMode.CURSOR:
		_highlights.paint(_active_cell, CellMarking.Kind.CURSOR_ACTIVE)
	else:
		_highlights.clear(_active_cell, CellMarking.Kind.CURSOR_ACTIVE)
