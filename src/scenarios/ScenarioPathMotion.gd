class_name ScenarioPathMotion
extends RefCounted
## One scripted `{28} Walk To` traversal, as a pure, scene-free value object
## (ADR-0055) — the world-space ADAPTER over [ExMateriaBattlefield.RomWalkStepper],
## which is the ROM's own per-frame walk stepper.
##
## It is a SIBLING of [ScenarioMotion], not a subclass: Sprite Move (`{3B}`/`{6E}`)
## is a single straight `+0x60`-offset lerp (`FUN_80146940`) and stays correct as
## `ScenarioMotion`; Walk To is a different opcode that walks a route buffer tile by
## tile through a state machine with four vertical cases, so it gets its own model.
##
## 🔴 **THIS CLASS NO LONGER MODELS THE WALK. IT CONVERTS COORDINATES.**
##
## What it replaced held `enum VMode { FLAT, FALL, HOP, RAMP }` and armed one of
## four vertical *shapes* per tile from that tile's elevation delta. The ROM has no
## vertical modes: it has ONE integrator (`unit_move_stepper @ 0x8006AF7C`) with
## four vertical CASES and one gravity, a leap and a hop differ only in what seeds
## `+0x2C` and `+0x28`/`+0x30`, a descent is not a case at all (the walk cases
## integrate gravity themselves), and a sub-level slope is a Y term in the direction
## vector rather than a ramp. `RAMP` and `FALL` were shapes the hardware does not
## have. #803 §19 item 8, §22.2, §24.3.
##
## So the motion is now decided entirely inside `RomWalkStepper`, which is scored
## **43 510 of 43 510 field-frames over thirteen PSX captures**
## (`RomWalkStepperTest`), and everything below is the two jobs that are genuinely
## this class's:
##
##   1. **Coordinates.** The stepper works in the ROM's render units — 28 per tile
##      edge, 12 per elevation level, **Y negative up**. The VM wants Godot world
##      metres. One linear map, anchored on the caller's own start waypoint.
##   2. **The clock.** The ROM integrates once per VBlank; `advance(dt)` takes
##      seconds. The whole trajectory is stepped ONCE at [method configure] and
##      `advance` walks a cursor along it, so the result is deterministic,
##      framerate-independent, and `dur_s` is known before the first frame — which
##      is what the `{29}` Wait Walk watchdog needs.
##
## ⚠️ **The cadence is not `224/Speed`.** That number is an approximation of an
## integer recurrence and this class no longer computes it: `vec3_normalize` returns
## **4095**, not 4096, for a cardinal axis (a GTE LUT artefact, §22.3, confirmed at
## four magnitudes), so a Speed-8 walk covers a tile in 29 frames and not 28. The
## frame count now falls out of the stepper rather than being predicted.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line
# per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const MapConstants = ExMateriaBattlefield.MapConstants
const RomWalkStepper = ExMateriaBattlefield.RomWalkStepper
## And the same for `addons/exmateria_platform`, which shed `DisplayPort` — the
## name of a hardware standard — under ADR-0212 dec. 1.
const PsxNum = ExMateriaPlatform.PsxNum

## Render units per tile edge, and per elevation level — the ROM's geometry, and
## the only two numbers the coordinate map needs.
const _RENDER_PER_TILE: float = 28.0

## A ROM frame budget no `{28}` walk can legitimately exceed. The longest scored
## capture is 458 frames (Speed 3.5, ten tiles); this is the guard against a route
## the stepper cannot finish, not a policy about walk length.
const _MAX_ROM_FRAMES: int = 4000

## Route direction (`rb >> 6`: +X, −X, −Y, +Y) to the Godot grid delta the adapter
## faces on. The stepper's PSX `+Y` is this frame's `+Z`: the legacy path builds its
## own local terrain, so it needs no ADR-0052 flip — the frame is self-consistent,
## and a caller supplying REAL tiles owes the flip before it builds the terrain.
const _DIR_TO_GRID := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]


## The caller's own route polyline, untouched. Read by `ScenarioApplyTest` and
## `ScenarioSpriteMoveTest` to name the seat the walk targets.
var waypoints: Array[Vector3] = []
## Motion clock (Hz) — converts `advance(dt)` seconds to ROM frames.
var tick_hz: float = 60.0
## Total ROM frames across the whole walk, after the `max_dur_s` clamp. Emergent:
## the stepper decides it, nothing predicts it.
var total_frames: float = 0.0
## Duration in seconds — surfaced for the `{29}` Wait Walk watchdog (parity with
## `ScenarioMotion.dur_s`, so the VM's `_motion_watchdog` reads it uniformly).
var dur_s: float = 0.0
## The stepper that produced the trajectory, kept for diagnostics: it holds the
## landing `sounds` and `puffs` the walk emitted, and its final tile/level.
## ⚠️ It is SPENT — the trajectory was stepped at `configure` time. Do not step it.
var stepper = null

# --- the precomputed trajectory ----------------------------------------------
## World position after N ROM frames; `_track[0]` is the start, so
## `_track.size() - 1` is the frame count.
var _track: Array[Vector3] = []
## 12-bit ORIENTATION angle to adopt at frame N, or -1 for "unchanged". Same
## indexing as `_track`.
var _turns: PackedInt32Array = PackedInt32Array()

# --- the clock ----------------------------------------------------------------
var _hf: float = 0.0                   ## elapsed ROM frames (continuous)
var _emitted: int = 0                  ## frames whose turns have been drained
var _pending_facing: int = -1          ## queued 12-bit angle (-1 = none)
## `snap_to_end` was used, so `position()` reports the SETTLED end rather than the
## clamped one. A `max_dur_s` clamp stops `advance` short of the seat on purpose —
## but a burn-through is asking for the end state, not for where the clamp fell.
var _snapped: bool = false


## Configure from a route POLYLINE — the legacy surface, and since ADR-0226 the one
## NO caller uses: `{28} Walk To` goes through [method configure_rom]. Kept because
## it is the honest surface for a caller that genuinely has only a polyline, and
## because it is what `ScenarioPathMotionTest` drives. `pts` is the per-tile waypoint list (start .. endpoint inclusive,
## each `(grid+0.5, tile_world_y, grid+0.5)`), `speed` the `{28}` Speed operand,
## `hz` the motion clock, `max_dur_s` the play-through clamp (INF = none).
##
## ⚠️ **A POLYLINE IS NOT TERRAIN, and this is where the fidelity is lost.** The
## stepper reads five bytes per tile — surface, height, depth, slope height and
## slope type — and a list of waypoints states exactly one of them, approximately:
## each tile's height, rounded to the nearest whole elevation level from its
## waypoint's world Y. On the flat tiles that are almost all of every map that
## rounding is EXACT (the exporter bakes `(12·(height + depth) + 1)/28`, so
## consecutive waypoints differ by whole levels); on a sloped tile it rounds the
## tile's centre and the drape is gone.
##
## What that costs, precisely: **no gait** (route bits 2/3 need a slope height), **no
## drape** (a sub-level slope is walked flat instead of as a Y term in the direction
## vector), and **no splash and no landing sound** (both keyed on `surface` and
## `depth`). Climbs, descents, hops, the animation band and the cadence are all exact,
## because none of them reads a byte a polyline cannot state.
##
## ⚠️ It also cannot state a LEAP, and the reason has moved. It used to be that the
## shipped planner could not emit one; since ADR-0226 it can, and a polyline still
## cannot carry it — `_grid_delta_to_route_byte` emits `extra = 0` because a waypoint
## list has no way to say a step spanned two tiles. `configure` is now the surface for
## a caller that has only a polyline, and every `{28} Walk To` uses
## [method configure_rom] instead.
func configure(pts: Array, speed: float, hz: float, max_dur_s: float) -> void:
	waypoints = []
	for p in pts:
		waypoints.append(p as Vector3)
	tick_hz = maxf(hz, 1.0)
	if waypoints.size() < 2:
		_seed_degenerate()
		return

	# 1. The cell chain, cardinal and duplicate-free. A diagonal segment (only the
	#    coarse `[start, target]` fallback ever produces one) is decomposed X then Z,
	#    because the ROM's route buffer has no diagonal to encode it with.
	var cells: Array[Vector2i] = []
	var cell_y: Array[float] = []
	for i in waypoints.size():
		var c := Vector2i(int(floor(waypoints[i].x)), int(floor(waypoints[i].z)))
		var wy: float = waypoints[i].y
		if cells.is_empty():
			cells.append(c)
			cell_y.append(wy)
			continue
		if c == cells[cells.size() - 1]:
			continue
		var from: Vector2i = cells[cells.size() - 1]
		while from.x != c.x:
			from.x += signi(c.x - from.x)
			cells.append(from)
			cell_y.append(wy)
		while from.y != c.y:
			from.y += signi(c.y - from.y)
			cells.append(from)
			cell_y.append(wy)
	if cells.size() < 2:
		_seed_degenerate()
		return

	# 2. Heights, in whole elevation levels relative to the start, then lifted so
	#    the lowest tile is 0 (the ROM's height is an unsigned byte).
	var level_world: float = MapConstants.PSX_UNITS_PER_HALF_STEP / MapConstants.PSX_UNITS_PER_TILE
	var rel: Array[int] = []
	var lowest: int = 0
	for i in cells.size():
		var h := int(round((cell_y[i] - cell_y[0]) / level_world))
		rel.append(h)
		lowest = mini(lowest, h)
	var base: int = -lowest

	# 3. A local PSX tile frame with a one-tile margin, so the ROM's own clamping
	#    lookup never has to answer for a cell the route named.
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_z: int = cells[0].y
	var max_z: int = cells[0].y
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
	var nx: int = max_x - min_x + 3
	var ny: int = max_z - min_z + 3
	var origin := Vector2i(min_x - 1, min_z - 1)

	var heights: Array = []
	for _lvl in 2:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				row.append(base)
			rows.append(row)
		heights.append(rows)
	for i in cells.size():
		var t := cells[i] - origin
		for lvl in 2:
			heights[lvl][t.y][t.x] = rel[i] + base

	# 4. The route buffer: a LENGTH byte then one byte per step, `(dir << 6)`. Every
	#    step spans one tile, so `extra` is 0 and no leap can be encoded — which is
	#    a true statement about the shipped planner, not a simplification here.
	# ⚠️ The ROM's buffer is `0x80` bytes — one LENGTH byte and at most 127 steps —
	# and the stepper reads a length of `0xFE`/`0xFF` as a TERMINATOR, so a 254-step
	# chain would arm a walk that ends on its first frame rather than a long one. No
	# shipped map can produce a route this long; the cap is here so that if one ever
	# does, the walk is truncated visibly instead of silently not happening.
	var steps: int = mini(cells.size() - 1, 127)
	if steps < cells.size() - 1:
		push_warning("[ScenarioPathMotion] route of %d steps exceeds the ROM's 127-step buffer; truncated"
			% (cells.size() - 1))
	var route: Array = [steps]
	for i in range(steps):
		var d := cells[i + 1] - cells[i]
		route.append(_grid_delta_to_route_byte(d))

	var terrain = RomWalkStepper.terrain_flat(heights, nx, ny)
	var start := Vector3i(cells[0].x - origin.x, cells[0].y - origin.y, 0)
	# `psx_rows` 0: the frame built above is indexed by GODOT grid Z, not PSX Y, so
	# the coordinate map must not mirror it.
	_run(terrain, start, route, speed, origin, waypoints[0].y,
		base * -RomWalkStepper.LEVEL_RENDER, max_dur_s, 0)


## Configure from REAL tiles — the full-fidelity surface, with nothing missing.
##
## `terrain` is a `RomWalkStepper.Terrain` in PSX tile coordinates (the caller owes
## the ADR-0052 Z flip), `start` the PSX start cell as `(x, psx_y, level)`, `route`
## the ROM's own buffer (a LENGTH byte, then the route bytes). `grid_origin` and
## `world_y_at_start` are the coordinate anchor: the Godot grid cell that PSX
## `(0, 0)` names, and the world Y the start tile's surface sits at.
##
## `psx_rows` is the map's `size_z` when `terrain` is in REAL PSX coordinates, and
## `0` when it is not.
##
## 🔴 **THE Z FLIP LIVES HERE, AND IT IS NOT OPTIONAL.** ADR-0052 mirrors PSX Y onto
## Godot Z about `size_z - 1`, so a PSX-coordinate terrain renders BACKWARDS unless
## the coordinate map inverts it — and it inverts silently: the walk is the right
## length, the right shape and the right duration, just mirrored down the map. The
## `configure` path passes `0` because the local frame it builds is already
## Godot-oriented; `ScenarioVM._plan_walk_route` passes the real `size_z`.
##
## `pts` is the route's world-space tile centres, kept as [member waypoints] so
## "where does this walk end" stays answerable without replaying the trajectory —
## the seat is `waypoints[-1]`, which is what `ScenarioApply` and two tests read.
func configure_rom(terrain, start: Vector3i, route: Array, speed: float, hz: float,
		max_dur_s: float, grid_origin: Vector2i, world_y_at_start: float,
		psx_rows: int = 0, pts: Array = []) -> void:
	tick_hz = maxf(hz, 1.0)
	waypoints = []
	for pt in pts:
		waypoints.append(pt as Vector3)
	var ground: int = terrain.ground_at(start.x * RomWalkStepper.TILE + 14,
		start.y * RomWalkStepper.TILE + 14, start.z)
	_run(terrain, start, route, speed, grid_origin, world_y_at_start, ground,
		max_dur_s, psx_rows)


## Advance by `dt` seconds along the precomputed trajectory.
func advance(dt: float) -> void:
	if is_done():
		return
	_hf += dt * tick_hz
	_drain_turns(mini(int(floor(minf(_hf, total_frames))), _track.size() - 1))


## Current world position — the value the VM writes to the unit each frame.
##
## Interpolated between ROM frames, so a clock that is not 60 Hz still reads a
## smooth path rather than a staircase. At `tick_hz == 60` every sample lands on a
## frame boundary and the interpolation is a no-op.
func position() -> Vector3:
	if _track.is_empty():
		return Vector3.ZERO
	if _snapped:
		return _track[_track.size() - 1]
	var cap: float = clampf(_hf, 0.0, total_frames)
	var i: int = int(floor(cap))
	if i >= _track.size() - 1:
		return _track[_track.size() - 1]
	return _track[i].lerp(_track[i + 1], cap - float(i))


func is_done() -> bool:
	return _hf >= total_frames


## Jump to the settled end state (fast-play / chapel-trace burn-through). Mirrors
## `ScenarioMotion.snap_to_end`, and drains any turn the walk had left to report so
## a burnt-through walk still ends facing the way it walked.
func snap_to_end() -> void:
	_hf = total_frames
	_snapped = true
	_drain_turns(_track.size() - 1)


## Return a queued facing as a 12-bit ORIENTATION angle once, or -1 if unchanged.
##
## The VM polls this after `advance` to re-face the body on route turns without
## replaying the walk SEQ (a straight route reports its heading once, then -1).
## Emitting the ANGLE rather than the FacingDirection enum lets the VM write the
## orientation source of truth `facing_angle` directly — ADR-0057's "one truth",
## with the derived enum following. Angles are 0..0xFFF, so -1 stays a valid
## "no change" sentinel.
##
## ⚠️ This is the GODOT heading, from the step's world delta — not `unit+0x70`, the
## ROM's own facing word, which the stepper also tracks. The two are different
## encodings of the same turn and every caller here has always wanted the former.
func poll_facing_change() -> int:
	var f := _pending_facing
	_pending_facing = -1
	return f


# --- internals ----------------------------------------------------------------

## Step the whole walk once, and record the world position and the turn at every
## ROM frame. This is where the trajectory stops being a model and becomes data.
func _run(terrain, start: Vector3i, route: Array, speed: float,
		grid_origin: Vector2i, world_y_at_start: float, start_ground_render: int,
		max_dur_s: float, psx_rows: int) -> void:
	# The coordinate map. Render X/Z divide down by the tile edge and shift onto the
	# Godot grid; render Y is NEGATIVE UP and is anchored so the start tile's own
	# surface lands exactly on the caller's start waypoint — which is what keeps a
	# walk from popping on its first frame whatever the exporter's surface lift is.
	#
	# The anchor is the start GROUND in render units, not its height in levels: a
	# start tile that is DRAPED does not sit on a whole level, and dividing its
	# ground by 12 would quantise the whole walk's Y by up to eleven twelfths of a
	# level.
	var y_anchor: float = world_y_at_start + float(start_ground_render) / _RENDER_PER_TILE

	var s = RomWalkStepper.new()
	s.configure(terrain, start, route, speed)
	stepper = s

	_track = [_to_world(s.render_x, s.render_y, s.render_z, grid_origin, y_anchor, psx_rows)]
	_turns = PackedInt32Array([-1])
	var last_dir: int = -1
	while _track.size() <= _MAX_ROM_FRAMES and s.step():
		_track.append(_to_world(s.render_x, s.render_y, s.render_z, grid_origin, y_anchor, psx_rows))
		var d: int = RomWalkStepper.route_dir(s.route_byte)
		if d != last_dir:
			last_dir = d
			# ⚠️ The route byte's ±Y is PSX Y. Under the flip a PSX −Y step heads
			# Godot +Z, so a facing derived without the mirror points BACKWARDS on
			# exactly the steps the walk turns on.
			var g: Vector2i = _DIR_TO_GRID[d]
			if psx_rows > 0:
				g.y = -g.y
			_turns.append(PsxNum.heading_to_12bit(float(g.x), float(g.y)))
		else:
			_turns.append(-1)
	# The ARRIVAL frame is a real frame and `step()` does not report it: the running
	# handler snaps to the destination centre and sets state 0, and the route-advance
	# in that SAME frame finds the buffer spent and returns false. `rom_walk_render.py`
	# drops it for the same reason (its `replay` appends after the break), which is
	# fine for a scorer comparing a prefix and wrong for a trajectory — without it the
	# walk ends a seventh of a tile short of the seat it was sent to.
	_track.append(_to_world(s.render_x, s.render_y, s.render_z, grid_origin, y_anchor, psx_rows))
	_turns.append(-1)

	_snapped = false
	total_frames = float(_track.size() - 1)
	if max_dur_s < INF:
		total_frames = minf(total_frames, max_dur_s * tick_hz)
	dur_s = total_frames / tick_hz
	_hf = 0.0
	_emitted = 0
	_pending_facing = -1


## Render units (28/tile, 12/level, Y NEGATIVE UP) to Godot world metres.
##
## X is 1:1 — ADR-0052's rotation leaves it alone — and Z is where the two frames
## disagree. With `psx_rows == 0` the caller's frame is already Godot-oriented and Z
## shifts by the origin. With `psx_rows == size_z` it is PSX Y and Z MIRRORS:
## a tile centre at render Z `k*28 + 14` is Godot world Z `size_z - (k + 0.5)`, which
## is the continuous form of `grid_z = size_z - 1 - psx_y` plus the half-tile centre.
func _to_world(rx: int, ry: int, rz: int, grid_origin: Vector2i, y_anchor: float,
		psx_rows: int) -> Vector3:
	var z: float = float(rz) / _RENDER_PER_TILE
	return Vector3(
		float(rx) / _RENDER_PER_TILE + float(grid_origin.x),
		y_anchor - float(ry) / _RENDER_PER_TILE,
		(float(psx_rows) - z) if psx_rows > 0 else (z + float(grid_origin.y)))


## A one-tile grid delta to its route byte. `dir` is `rb >> 6` in the ROM's own
## order (+X, −X, −Y, +Y) — ⚠️ NOT the planner's neighbour-expansion order, which is
## a different table doing a different job (#803 §17.3, §17.7).
static func _grid_delta_to_route_byte(d: Vector2i) -> int:
	var dir: int = 0
	if d.x > 0:
		dir = 0
	elif d.x < 0:
		dir = 1
	elif d.y < 0:
		dir = 2
	else:
		dir = 3
	return dir << 6


## Queue the latest turn among the frames newly reached, so a turn is never lost to
## a `dt` that crossed more than one frame.
func _drain_turns(upto: int) -> void:
	while _emitted < upto:
		_emitted += 1
		if _turns[_emitted] >= 0:
			_pending_facing = _turns[_emitted]


## A walk with nowhere to go: one frame, already finished, parked where it started.
func _seed_degenerate() -> void:
	var at: Vector3 = waypoints[0] if not waypoints.is_empty() else Vector3.ZERO
	_track = [at]
	_turns = PackedInt32Array([-1])
	stepper = null
	_snapped = false
	total_frames = 0.0
	dur_s = 0.0
	_hf = 0.0
	_emitted = 0
	_pending_facing = -1
