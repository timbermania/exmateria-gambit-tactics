# psx-faithful-sim: a bit-exact transcription of the ROM's `{28} Walk To` ROUTE
# planner. The `& 0xFF` corner arithmetic, the signed-16-bit compares and the
# `surface & 0x3F` cost index ARE the hardware's arithmetic, not a conversion of
# it; routing any of them through `PsxMagnitude` would replace the thing under test
# with a model of it, and the byte-for-byte score against nine live PCSX captures
# is the whole point of the file. ADR-0091 §4, ADR-0226.
extends RefCounted
## The ROM's `{28} Walk To` ROUTING half: a start and a destination in, the ROM's
## own route BYTE BUFFER out. The sibling of [RomWalkStepper], which is the render
## half — that one turns this buffer into a per-frame trajectory.
##
## This is a TRANSCRIPTION, not a model. Every branch below is a line of
## `battle_decompilation.c` cited by address, there are no free parameters, and it
## is scored against the wire:
## `research/scenario29_walk_vs_jump/evidence/rom_event_flood.py` is the same
## planner in Python at **224 of 224 flood tiles exact on budget and roughness**
## and **9 of 9 live PCSX captures byte-for-byte**, and `EventPathfinderTest`
## replays those same captures against THIS file.
##
##     FUN_8017813C @ 0x8017813C   the driver: the caps, the round loop, the walk-back
##     FUN_80174E84 @ 0x80174E84   the pass map
##     FUN_80175EA0 @ 0x80175EA0   the adjacent expander (span 0)
##     FUN_801764D8 @ 0x801764D8   the LEAP expander    (span 1..stateB+0x05)
##     FUN_8017567C @ 0x8017567C   per-direction source setup
##     FUN_80175958 @ 0x80175958   the relaxation, and every rejection code
##     FUN_80176164 @ 0x80176164   the ceiling query
##     FUN_8017622C @ 0x8017622C   the leap clearance (a swept-volume overlap)
##     FUN_801779DC @ 0x801779DC   walk-back, adjacent predecessors
##     FUN_80177C08 @ 0x80177C08   walk-back, span predecessors
##     FUN_80177794 @ 0x80177794   predecessor acceptance
##     FUN_80177E64 @ 0x80177E64   candidate ranking
##     FUN_80176C90 @ 0x80176C90   the route-byte emitter
##
## 🔴 **THIS IS NOT A BFS, AND THE ROUTE IS NOT A PATH OF CELLS.** What this file
## replaced was a 4-directional uniform-cost breadth-first search that emitted one
## tile per step. Three things were wrong with that and only the third is visible
## from outside:
##
##   1. the flood is a **cost** flood, not a step count. The start is seeded with
##      `budget + 1` = 125 and every step SUBTRACTS the destination surface's cost
##      out of the SCUS row at `0x8005EA50`. Water costs 2, a road costs 1, an
##      obstacle costs 0xFF. A uniform-cost search cannot express "around" — it can
##      only express "shortest";
##   2. the route is rebuilt by walking **backward** from the target with no
##      predecessor links anywhere, accepting a predecessor `P` iff
##      `budget[P] - cost[surface(C)] - span == budget[C]`, and tie-breaking on
##      span, then roughness, then "keep going the same direction";
##   3. **a step may span more than one tile.** `FUN_801764D8` is a SECOND expander
##      that relaxes the tile `span + 1` away when the tiles flown over are clear.
##      That is the leap, `extra` in the route byte, and a one-tile-per-step planner
##      cannot encode it at all. It is why the shipped game waded the Igros moat for
##      ten steps where the ROM leaps it in eight (#803).
##
## 🔴 **TWO DIRECTION TABLES, TWO JOBS.** [constant DIRS] is the flood's expansion
## order and carries the two CORNER SHIFTS each direction reads a tile's height with.
## The route BYTE's direction field is a different encoding again — `rb >> 6` is
## `+X, -X, -Y, +Y`, emitted by `FUN_80176C90` and consumed by `FUN_80069F14`.
## Conflating them scrambled an entire 32-variant model search once; research README
## §17.3 and §17.7.
##
## 🔴 **PSX COORDINATES THROUGHOUT.** Cells here are `(x, psx_y, level)`. The
## ADR-0052 Z flip `psx_y = size_z - 1 - grid_z` is the CALLER's, applied once at the
## boundary — [RomTerrain] does it when it reads the map, and `ScenarioVM` does it
## for the start and the target. Skipping it returns a plausible route on a MIRRORED
## map and never throws.
##
## OTHER UNITS DO NOT BLOCK (ROM-verified, terrain-only routing). The flood builds
## its pass map by calling the shared map-builder `FUN_80174E84` with mode `a0 = 3`
## (`ori a0,zero,0x3` in the delay slot at `0x801784B4`). Mode 3 branches PAST the
## entire unit-occupancy phase — gate `0x8017505C` skips the loop at `0x8017506C`
## that would otherwise clear the standable flag on each occupied tile. So the event
## map is rebuilt each `{28} Walk To` from TERRAIN flags only; no unit position is
## ever folded in, and this class has no query for one. The occupancy-AWARE build
## (`a0 = 1`) belongs to the separate gameplay pathfinder `FUN_80178CA4`, which
## `{28} Walk To` never reaches.
##
## Scope: the ROM routes ONLY `{28} Walk To` through here — `FUN_8008C664`, the sole
## entry, has a single caller. Sprite Move / Jump / Warp are deliberately not
## pathfound.
## Vault: [[Walk To Opcode]]

const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")

## The four direction stubs behind `PTR_FUN_8018F500`, in the ROM's expansion order:
## `(dx, dy, shift44, shift45)`, `dy` in PSX Y. `FUN_801754D0` / `LAB_801754F4` /
## `LAB_8017551C` / `LAB_80175540`.
##
## 🔴 **THE SHIFTS ARE HALF THE TABLE.** A tile's height is not one number: it is
## `height * 2 + slope_h * ((slope_t >> shift) & 3)`, and each direction reads a
## DIFFERENT pair of corners — `shift44` is the far corner along the direction of
## travel, `shift45` the near one. Dropping them turns every sloped tile flat and
## costs the route bits 2 and 3 outright. See [method _corner].
const DIRS: Array[Vector4i] = [
	Vector4i(1, 0, 0, 2),
	Vector4i(0, 1, 6, 4),
	Vector4i(-1, 0, 2, 0),
	Vector4i(0, -1, 4, 6),
]

## `(dir bits, shift44, shift45)` for each PSX step delta, keyed `(dx, dy)`.
## `FUN_80176C90`'s own encoding, and NOT [constant DIRS]' order — see the header.
const ROUTE_BITS: Dictionary = {
	Vector2i(1, 0): Vector3i(0x00, 0, 2),
	Vector2i(-1, 0): Vector3i(0x40, 2, 0),
	Vector2i(0, -1): Vector3i(0x80, 4, 6),
	Vector2i(0, 1): Vector3i(0xC0, 6, 4),
}

## The climb limit `{28} Walk To` runs with — a ROM literal, not a unit stat.
##
## 🔴 IT IS NOT THE UNIT'S JUMP. The Walk To handler `FUN_8013E5C0` builds the
## pathfinder call with `ori a3,zero,0x3` @ `0x8013E634`, and `FUN_8017813C` fans
## that one literal out into FOUR state bytes: `+0x02 = 3 << 1` (the max single-step
## height delta, in half-levels), `+0x04 = 3` (the steep-slope threshold behind route
## bits 2 and 3), and `+0x05 = 3 >> 1 = 1` (the MAX LEAP SPAN — one extra tile, which
## is why a `{28}` walk can never emit a three-tile leap). The unit's Jump
## (`unit+0x3B`, read at `0x801747F0`) parameterizes the SEPARATE gameplay pathfinder
## `FUN_80178CA4`, which this never reaches — so wiring `UnitProgression.get_jump()`
## in here would be a plausible wrong answer.
const WALK_TO_CLIMB: int = 3

## The ROM clamps its climb argument to 7 (`sltiu v0,v0,0x8` @ `0x80178424`), so there
## is no "no limit" to ask for.
const CLIMB_CEILING: int = 7

## The move budget at `stateB+0x06`, a literal 124. The start tile is seeded with
## `MOVE_BUDGET + 1` and each step subtracts a surface cost, so a route may spend at
## most 124 points. The longest shipped `{28}` route spends 12.
const MOVE_BUDGET: int = 0x7C

## The vertical clearance a unit needs, `stateB+0x1B`, in half-levels. Six.
const CLEARANCE: int = 6

## `stateA+0x54`: four directions, no diagonals.
const DIRECTIONS: int = 4

## `stateA+0x55`: the flood relaxes TWO records per column — level 0 and level 1.
## `FUN_80175958` unpacks it as `level = i & 1`, `mode = i >> 1`; mode 1 is the
## "stand on a unit's head" bank and gameplay passes 4. `{28}` passes 2, so changing
## terrain level costs nothing and is not a fifth direction (ADR-0219).
const MODES: int = 2

## `0x7F` — the ceiling query's "nothing above this" answer.
const NO_CEILING: int = 0x7F

## The ROM's flood-record stride: `0x100` slots per level, so a record is indexed
## `level * 0x100 + psx_y * size_x + x`.
##
## 🔴 **THE BOUND IS REAL AND THE DATA CONFIRMS IT.** 256 slots per level is what
## `tile_ptr`'s block after `0x8018F8CC` holds, and across all 119 shipped
## `terrain.json`s the largest map is **MAP125 at 16 x 16 = 256 tiles exactly** —
## the ROM's ceiling, hit and never exceeded. [member _stride] therefore equals this
## on every map the ROM can address, and only widens for a synthetic map built in
## code (a test scene's `Lattice` is routinely 20 x 20). Widening rather than
## aliasing is not a deviation on the ROM's domain: the index is a bijection used
## only to key this class's own arrays, never an address, so a larger stride relabels
## the same records. The 18 wire arms are what prove it inert.
const ROM_STRIDE: int = 0x100

## The largest map this will plan over at all, in tiles per level. Not a ROM number —
## the ROM's is `ROM_STRIDE` — but a bound on the flood arrays, so a mock map with a
## runaway size fails loudly instead of allocating.
const MAX_TILES_PER_LEVEL: int = 0x1000

## The route buffer at `DAT_8018F7F0` is `0x80` bytes: one LENGTH byte and at most
## 127 steps. No shipped map produces a route anywhere near it — the longest is 12.
const MAX_ROUTE_STEPS: int = 127

## The SCUS movement-cost row at `0x8005EA50`, movetype 0, resolved for weather.
##
## `FUN_8017813C` copies one 0x40-byte row out of that table and consumers index it
## `surface & 0x3F`, so the row is 64 usable bytes and not 256. The five entries the
## ROM leaves at `0` are substituted from the weather at plan time — swamp, marsh,
## poisoned marsh, salt and moss cost more in rain — and `weather_cost` is that
## substitution. `evidence/dump_terrain_cost_table.py` reads the row out of the
## committed Ghidra SCUS export; `0x8005EA50` is inside SCUS, not BATTLE.BIN.
static func cost_row(weather_cost: int = 1) -> PackedInt32Array:
	var row := PackedInt32Array()
	row.resize(64)
	row.fill(1)
	for s in [0x0E, 0x0F, 0x10, 0x11, 0x2D]:      # Waterway River Lake Sea Waterfall
		row[s] = 2
	for s in [0x12, 0x19, 0x1C, 0x3F]:            # Lava Darkness Obstacle (and 0x3F)
		row[s] = 0xFF
	for s in [0x09, 0x0A, 0x0B, 0x1A, 0x24]:      # Swamp Marsh PoisonedMarsh Salt WaterPlant
		row[s] = weather_cost
	return row


## The `{28}` operand's own cost switch: `+8 == 0` FLATTENS the whole row to 1.
##
## Not a corner — **10 of the 282 shipped `{28}` instructions do it** (research README
## §20.1). A flattened row is how a scenario walks a unit straight across water it
## would otherwise route around.
static func flat_cost_row() -> PackedInt32Array:
	var row := PackedInt32Array()
	row.resize(64)
	row.fill(1)
	return row


# --- state ------------------------------------------------------------------
# `stateA` / `stateB` field names are the ROM's own byte offsets, kept so this file
# diffs line-for-line against `rom_event_flood.py`.

var _terrain                                  # RomWalkStepper.Terrain
var _nx: int = 0
var _ny: int = 0
var _cost: PackedInt32Array

var _b02: int = 0                             ## max single-step height delta (6)
var _b04: int = 0                             ## steep-slope threshold          (3)
var _b05: int = 0                             ## max leap span                  (1)
var _b06: int = MOVE_BUDGET                   ## move budget                  (124)
var _b0e: int = 7                             ## roughness on; impassable respected
var _b11: int = 0                             ## inherited — research README §20.3
var _b12: int = 1
var _b13: int = 1
var _b14: int = 1                             ## inherited AND non-zero: a depth>0
                                              ## target is REFUSED (arms R1/R2, §21.8)
var _b1b: int = CLEARANCE
var _b1c: int = 0                             ## no water-walking bits

## Slots per level. `ROM_STRIDE` on every real map; larger only for a synthetic one.
var _stride: int = ROM_STRIDE
## `_stride * LEVELS` — the records the round loop scans.
var _records: int = ROM_STRIDE * 2

var _budget: PackedInt32Array                 ## flood record +0: remaining move points
var _rough: PackedInt32Array                  ## flood record +4: largest step delta so far

## Flood record +1, the walk-back sequence number — **WRITE-ONLY on this path.**
##
## `FUN_801779DC` stamps it as it walks back, and nothing in the `{28}` chain reads
## it: the route emitter `FUN_80176C90` works off the chain, not off the records.
## Kept because this file is a transcription and the ROM does write it; SAID here
## because an unmarked write-only field sends the next reader hunting for a reader
## that does not exist. Do not "wire it up" — there is nothing to wire it to.
var _seq: PackedInt32Array

## Flood record +3, the force-reachable flag — **READ-ONLY, AND NEVER WRITTEN HERE.**
##
## 🔴 THE BRANCH THAT READS IT CANNOT BE TAKEN. `_destination_reachable` opens with
## `if _force[t] != 0: return true`, and no line in this class ever sets a record's
## +3. In the ROM another routine populates it (a scripted "this tile is reachable
## whatever the flood says" override); on the `{28} Walk To` path it is always 0, so
## that early return is unreachable and every capture scores identically with or
## without it.
##
## 🔴 FAITHFUL-BUT-INERT IS NOT THE SAME AS WRONG, and the LABEL is what keeps them
## apart. ADR-0225 recorded a branch that was unreachable AND mislabelled `[STATIC]`,
## which claims the strictly stronger "correct but unobserved"; this field is
## unreachable and, until now, merely unmarked. Carrying a field the ROM writes
## elsewhere is a transcription doing its job — deleting it would be the error, because
## whoever ports the gameplay pathfinder `FUN_80178CA4` needs it and a deleted field is
## a fact you have to rediscover from the ROM.
##
## What no score can do is tell you which it is: the branch is inert either way, so the
## captures pass identically with or without it. What found it was a census of members
## with no counterpart use — an instrument of a different KIND, not a bigger one.
var _force: PackedInt32Array
var _pass: PackedInt32Array                   ## the pass map, `FUN_80174E84`
var _a62: int = 0                             ## the round loop's high-water budget


## Plan one `{28} Walk To`.
##
## `terrain` is a [RomWalkStepper.Terrain] in PSX tile coordinates ([RomTerrain]
## builds one from a `terrain.json`); `start` and `dest` are PSX cells
## `(x, psx_y, level)`; `cost` is a row from [method cost_row] or
## [method flat_cost_row]; `climb` is the handler's literal, [constant WALK_TO_CLIMB]
## for every event walk in the game.
##
## Returns:
##     route: PackedByteArray   # the ROM's buffer — a LENGTH byte, then one per step
##     cells: Array[Vector3i]   # the PSX cells the route visits, start .. dest
##     endpoint: Vector3i       # the cell the unit ends on
##     reached_target: bool     # false ⇔ no route was emitted at all
##     refused: String          # "" when a route was emitted, else why not
##
## 🔴 **THE ROM EITHER WALKS TO THE LITERAL TARGET OR DOES NOT WALK.** There is no
## "nearest reachable tile" anywhere in `FUN_8017813C`: an unreachable target returns
## NULL and the whole opcode is a no-op. Two things can refuse it — the destination
## gate `FUN_801787E0` (which is STRICTER than standable: it rejects a depth, a steep
## slope, an Obstacle surface) and the walk-back failing to find a predecessor chain.
## `reached_target` is `false` in both cases and `route` is empty; the caller must not
## substitute a consolation destination, because the ROM does not.
func plan(terrain, start: Vector3i, dest: Vector3i, cost: PackedInt32Array,
		climb: int = WALK_TO_CLIMB) -> Dictionary:
	_terrain = terrain
	_nx = terrain.nx
	_ny = terrain.ny
	_cost = cost
	_stride = maxi(ROM_STRIDE, _nx * _ny)
	_records = _stride * RomWalkStepper.LEVELS
	var j: int = clampi(climb, 0, CLIMB_CEILING)
	_b02 = j << 1
	_b04 = j
	_b05 = j >> 1
	var refused := _bounds_refusal(start, dest)
	if refused != "":
		return _no_route(start, refused)
	_flood_from(start, dest)
	if not _destination_reachable(dest):
		return _no_route(start, "destination gate: FUN_801787E0 refuses the target tile")
	var chain: Array = _walk_back(start, dest)
	if chain.is_empty() and start != dest:
		return _no_route(start, "walk-back: no accepted predecessor chain to the target")
	var cells: Array[Vector3i] = [start]
	for i in range(chain.size() - 1, -1, -1):
		var c: Array = chain[i]
		cells.append(Vector3i(c[0], c[1], c[2]))
	return {
		"route": _route_bytes(chain),
		"cells": cells,
		"endpoint": dest,
		"reached_target": true,
		"refused": "",
	}


## The map's own bounds, checked before the flood rather than inside it: the ROM's
## record index `level * 0x100 + y * nx + x` silently aliases another tile for an
## out-of-range cell, so a caller's bad coordinate would route rather than fail.
func _bounds_refusal(start: Vector3i, dest: Vector3i) -> String:
	if _nx * _ny > MAX_TILES_PER_LEVEL:
		return "map is %dx%d = %d tiles, past this planner's %d-tile bound" \
			% [_nx, _ny, _nx * _ny, MAX_TILES_PER_LEVEL]
	for c in [start, dest]:
		if not _in_bounds(c.x, c.y) or c.z < 0 or c.z >= RomWalkStepper.LEVELS:
			return "cell (%d,%d,L%d) is off a %dx%d map" % [c.x, c.y, c.z, _nx, _ny]
	return ""


func _no_route(start: Vector3i, why: String) -> Dictionary:
	return {
		"route": PackedByteArray(),
		"cells": [start] as Array[Vector3i],
		"endpoint": start,
		"reached_target": false,
		"refused": why,
	}


# --- the map -----------------------------------------------------------------

func _tile(lvl: int, x: int, y: int):
	return _terrain.tiles[lvl][y][x]


func _idx(lvl: int, x: int, y: int) -> int:
	return lvl * _stride + y * _nx + x


## `FUN_80175618 @ 0x80175618`.
func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < _nx and y >= 0 and y < _ny


## One CORNER of a tile, in half-levels, as the flood measures height.
##
## `height * 2 + slope_h * ((slope_t >> shift) & 3)`, wrapped to a byte. The two bits
## the shift selects are that corner's share of the slope, 0..3 — which is why a
## direction's `shift44` / `shift45` pair is not decoration: the same tile is a
## different height depending on which way you cross it.
func _corner(lvl: int, x: int, y: int, shift: int) -> int:
	var m = _tile(lvl, x, y)
	return (m.height * 2 + m.slope_h * ((m.slope_t >> shift) & 3)) & 0xFF


## Sign-extend a 16-bit compare. The ROM's height differences are `s16` subtractions
## of unsigned bytes, so `4 - 250` is `-246` and not `0x10A`; comparing the raw
## difference inverts the answer on every wrap.
static func to_s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## `FUN_80174E84 @ 0x80174E84` — the pass map, rebuilt for every plan.
##
## Bit `0x10` is standable, `0x40` steep, `0x02` a slope whose type is a pure
## incline, `0x80` unselectable, `0x01` the round loop's "open" mark.
func _build_pass() -> void:
	_pass = PackedInt32Array()
	_pass.resize(_records)
	for lvl in RomWalkStepper.LEVELS:
		for y in _ny:
			for x in _nx:
				var m = _tile(lvl, x, y)
				var p: int = 0
				if (m.slope_t & 5) == 1 or (m.slope_t & 5) == 4:
					p |= 2
					if m.slope_h > 2:
						p |= 0x40
				elif m.slope_h > _b04:
					p |= 0x40
				if (not m.unselectable and not m.impassable
						and (m.depth == 0 or _b11 == 0)
						and (m.depth < 4 or _b13 == 0)):
					p |= 0x10
				if m.unselectable:
					p |= 0x80
				elif _b0e == 0 and m.impassable and (m.surface & 0x3F) != 0x3F:
					p |= 0x10
				_pass[_idx(lvl, x, y)] = p


## `FUN_80176164 @ 0x80176164` — the lowest tile UNDERSIDE strictly above `floor`
## in column `(x, y)`, or [constant NO_CEILING].
##
## A tile's underside is its corner minus `thickness * 2`, which is the one place
## `thickness` is read at all. This is what makes a bridge deck a ceiling over the
## moat rather than a second floor.
func _ceiling(x: int, y: int, shift: int, floor_h: int) -> int:
	var best: int = NO_CEILING
	for lvl in RomWalkStepper.LEVELS:
		var m = _tile(lvl, x, y)
		if m.unselectable:
			continue
		var h: int = (_corner(lvl, x, y, shift) - m.thickness * 2) & 0xFF
		if floor_h < h and h <= best:
			best = h
	return best


## `FUN_8017622C @ 0x8017622C` — the leap's clearance test: does any solid volume in
## column `(x, y)` overlap a unit flying over it with its feet at `feet`?
##
## A SWEPT-VOLUME OVERLAP, not a height comparison. Each level contributes a slab
## from its underside to its top (its higher corner plus its own depth), and the leap
## is blocked if the flier's `feet .. feet + clearance` band touches one — or if the
## column's lowest underside is above the feet at all, which is the "you are flying
## through a floor" case.
func _leap_blocked(x: int, y: int, sh44: int, sh45: int, feet: int) -> bool:
	var clear: int = _b1b
	var lowest: int = NO_CEILING
	for lvl in RomWalkStepper.LEVELS:
		var t: int = _idx(lvl, x, y)
		var m = _tile(lvl, x, y)
		if _pass[t] & 0x80:                        # unselectable
			if _pass[t] & 4:                       # ... but a unit stands there
				return true
			continue
		var ca: int = _corner(lvl, x, y, sh44)
		var cb: int = _corner(lvl, x, y, sh45)
		var under: int
		var top: int
		if cb < ca:
			under = (cb - m.thickness * 2) & 0xFF
			top = (ca + m.depth * 2) & 0xFF
		else:
			under = (ca - m.thickness * 2) & 0xFF
			top = (cb + m.depth * 2) & 0xFF
		if under < lowest:
			lowest = under
		if feet < under and under < feet + clear:
			return true
		if feet < top and top < feet + clear:
			return true
		if under <= feet and feet + clear <= top:
			return true
	return lowest != NO_CEILING and feet < lowest


## `FUN_8017567C @ 0x8017567C` — per-direction source setup.
## Returns `[code, src_height, ceiling_src]`; code 0 means "go on".
func _src_setup(lvl: int, sx: int, sy: int, sh44: int, sh45: int) -> Array:
	var m = _tile(lvl, sx, sy)
	var h44: int = _corner(lvl, sx, sy, sh44)
	var h45: int = _corner(lvl, sx, sy, sh45)
	var t: int = _idx(lvl, sx, sy)
	var ceil_src: int = _ceiling(sx, sy, sh44, h44)
	if to_s16(h44 - h45) >= 0 and (_pass[t] & 0x40):
		return [3, h44, ceil_src]
	if m.depth != 0 and (_b1c & 0xC0):             # water-walking; never for `{28}`
		h44 = (h44 + m.depth * 2) & 0xFF
		if _b1c & 0x40:
			h44 = (h44 - 2) & 0xFF
	if _budget[t] < 2:
		return [4, h44, ceil_src]
	return [0, h44, ceil_src]


## `FUN_80175958 @ 0x80175958` — the relaxation. Returns the ROM's own rejection
## code, or 0 when the destination record was improved.
##
## The four codes 4/5/6 are a HEADROOM test, not a height comparison — each asks
## whether a body of `_b1b` half-levels fits under a ceiling. Code 8 is the rule that
## makes a leap a leap: **a leap may never climb.**
func _relax(src_t: int, src_h: int, ceil_src: int, dlvl: int, dx: int, dy: int,
		sh44: int, sh45: int, span: int) -> int:
	var dt: int = _idx(dlvl, dx, dy)
	var m = _tile(dlvl, dx, dy)
	if not (_pass[dt] & 0x10):
		return 2
	var near: int = _corner(dlvl, dx, dy, sh45)
	var far: int = _corner(dlvl, dx, dy, sh44)
	var ceil_dst: int = _ceiling(dx, dy, sh45, near)
	if to_s16(far - near) > 0 and (_pass[dt] & 0x40):
		return 3
	if src_h + _b1b > ceil_dst:
		return 4
	if near + _b1b > ceil_src:
		return 5
	if near + _b1b > ceil_dst:
		return 6
	near = (near + m.depth * 2) & 0xFF             # feet stand on the water SURFACE
	var delta: int
	if src_h < near:
		if span != 0:
			return 8                                # a leap may never climb
		delta = near - src_h
	else:
		delta = src_h - near
	if delta > _b02:
		return 9
	var rough: int = maxi(_rough[src_t], delta)
	if _b0e == 0:
		rough = 0
	var fresh: int = _budget[src_t] - span - _cost[m.surface & 0x3F]
	if to_s16(fresh) < 1:
		return 0x0E
	if fresh < _budget[dt]:
		return 0x0F
	if fresh == _budget[dt] and _rough[dt] <= rough:
		return 0x10
	_budget[dt] = fresh
	_rough[dt] = rough
	if fresh > 1:
		_pass[dt] |= 1
		_a62 = maxi(_a62, fresh)
	return 0


## `FUN_80175EA0` + `FUN_801764D8` — everything reachable from one source tile.
##
## TWO expanders per direction, and the second is the whole of #803. The first
## relaxes the adjacent tile at span 0. The second walks outward while the tiles
## being flown OVER are clear, relaxing the tile `span + 1` away at span 1..`_b05`.
## `{28}` runs with `_b05 == 1`, so a leap clears exactly one tile — which is why the
## Igros moat is leapable and a two-tile channel is not (arm K).
func _expand(src_t: int) -> void:
	@warning_ignore("integer_division")
	var lvl: int = src_t / _stride
	var rem: int = src_t % _stride
	@warning_ignore("integer_division")
	var sy: int = rem / _nx
	var sx: int = rem % _nx
	for i in DIRECTIONS:
		var d: Vector4i = DIRS[i]
		var dx: int = d.x
		var dy: int = d.y
		var sh44: int = d.z
		var sh45: int = d.w
		# --- FUN_80175EA0: the adjacent step ---------------------------------
		if _in_bounds(sx + dx, sy + dy):
			var a: Array = _src_setup(lvl, sx, sy, sh44, sh45)
			if a[0] == 0:
				for dl in MODES:
					_relax(src_t, a[1], a[2], dl, sx + dx, sy + dy, sh44, sh45, 0)
		# --- FUN_801764D8: the LEAP ------------------------------------------
		var s: Array = _src_setup(lvl, sx, sy, sh44, sh45)
		if s[0] != 0:
			continue
		var span: int = 1
		var cx: int = sx + dx
		var cy: int = sy + dy
		while span <= _b05:
			if to_s16(_budget[src_t] - span) < 2:
				break
			if not _in_bounds(cx, cy):
				break
			if _leap_blocked(cx, cy, sh44, sh45, s[1]):
				break
			var lx: int = sx + dx * (span + 1)
			var ly: int = sy + dy * (span + 1)
			if not _in_bounds(lx, ly):
				break
			for dl in MODES:
				_relax(src_t, s[1], s[2], dl, lx, ly, sh44, sh45, span)
			span += 1
			cx = lx
			cy = ly


## `FUN_8017813C @ 0x8017813C` — the driver's round loop.
##
## Rounds run until the budget high-water mark `stateA+0x62` can no longer beat what
## the destination already holds, which is the ROM's own early exit and the reason a
## flood over a 112-tile map settles in eight rounds rather than 112.
func _flood_from(start: Vector3i, dest: Vector3i) -> int:
	_build_pass()
	_budget = PackedInt32Array(); _budget.resize(_records)
	_seq = PackedInt32Array(); _seq.resize(_records)
	_force = PackedInt32Array(); _force.resize(_records)
	_rough = PackedInt32Array(); _rough.resize(_records); _rough.fill(0xFF)
	var st: int = _idx(start.z, start.x, start.y)
	var dt: int = _idx(dest.z, dest.x, dest.y)
	_budget[st] = _b06 + 1
	_rough[st] = 0
	_pass[st] |= 1
	_a62 = _b06 + 1
	var rounds: int = 0
	while rounds < _b06:
		if _a62 == 0 or _a62 <= _budget[dt]:
			break
		var open_: Array[int] = []
		for t in _records:
			if _pass[t] & 1:
				open_.append(t)
		for t in _records:
			_pass[t] &= ~1
		_a62 = 0
		for t in open_:
			_expand(t)
		rounds += 1
	return rounds


## `FUN_801787E0` — the destination gate, and it is STRICTER than standable.
##
## The driver returns NULL when the target tile lacks `map[t].b1` bit 5, and the whole
## `{28} Walk To` is refused: no route is emitted and the unit does not move. Depth
## alone refuses it (`_b14` is inherited non-zero), which is why a scenario cannot
## walk a unit onto a water tile even when the flood reaches it — arm P, README §21.8.
func _destination_reachable(dest: Vector3i) -> bool:
	var t: int = _idx(dest.z, dest.x, dest.y)
	var m = _tile(dest.z, dest.x, dest.y)
	if _force[t] != 0:
		return true
	return (_budget[t] != 0
		and (m.slope_h < 3 or not (_pass[t] & 0x02))
		and m.slope_h < 4
		and (m.surface & 0x3F) != 0x1C
		and (m.depth == 0 or _b14 == 0)
		and (m.depth != 3 or _b12 == 0)
		and (m.depth < 4 or _b13 == 0)
		and ((m.surface & 0x3F) != 0x12 or _b0e != 0)
		and bool(_pass[t] & 0x10))


## `FUN_801779DC` / `FUN_801773B8` / `FUN_80177794` — every accepted predecessor of
## `(x, y, lvl)` at this span, as `[rough, delta, sh44, px, py, pl]`.
##
## The walk-back MIRRORS the forward pass: the CURRENT tile plays the role of the
## forward step's destination (corner `sh44`, and it gains its own depth), and the
## CANDIDATE predecessor plays the forward source (corner `sh45`, and it does not —
## `stateB+0x1C` is 0). The candidate sits at `current + delta * (span + 1)`: the same
## four direction stubs, walked the other way round.
func _candidates(x: int, y: int, lvl: int, span: int, here: int) -> Array:
	var out: Array = []
	for i in DIRECTIONS:
		var d: Vector4i = DIRS[i]
		var dx: int = d.x
		var dy: int = d.y
		var sh44: int = d.z
		var sh45: int = d.w
		# --- FUN_80177180 @ 0x80177180: the current tile ---------------------
		var cur = _tile(lvl, x, y)
		var cur44: int = _corner(lvl, x, y, sh44)
		var cur45: int = _corner(lvl, x, y, sh45)
		var ceil_cur: int = _ceiling(x, y, sh44, cur44)
		var ct: int = _idx(lvl, x, y)
		if to_s16(cur45 - cur44) > 0 and (_pass[ct] & 0x40):
			continue                                          # code 1
		var cur_h: int = (cur44 + cur.depth * 2) & 0xFF
		if not _in_bounds(x + dx, y + dy):
			continue
		var px: int = x + dx * (span + 1)
		var py: int = y + dy * (span + 1)
		if not _in_bounds(px, py):
			continue
		for pl in MODES:
			# --- FUN_801773B8 @ 0x801773B8: the candidate --------------------
			var pt: int = _idx(pl, px, py)
			if not (_pass[pt] & 0x10):
				continue                                      # code 4
			var p45: int = _corner(pl, px, py, sh45)
			var p44: int = _corner(pl, px, py, sh44)
			var ceil_p: int = _ceiling(px, py, sh45, p45)
			if to_s16(p45 - p44) >= 0 and (_pass[pt] & 0x40):
				continue                                      # code 5
			var pred_h: int = p45                             # `stateB+0x1C == 0`: no depth
			# --- the leap's clearance, from the LAUNCH tile's feet ------------
			var blocked: bool = false
			for k in range(1, span + 1):
				if _leap_blocked(px - dx * k, py - dy * k, sh44, sh45, pred_h):
					blocked = true
					break
			if blocked:
				continue
			# --- FUN_80177794 @ 0x80177794 -----------------------------------
			if pred_h + _b1b > ceil_cur:
				continue                                      # code 1
			if cur_h + _b1b > ceil_p:
				continue                                      # code 2
			if cur_h + _b1b > ceil_cur:
				continue                                      # code 3
			var delta: int
			if pred_h < cur_h:
				if span != 0:
					continue                                  # code 4: a leap never climbs
				delta = cur_h - pred_h
			else:
				delta = pred_h - cur_h
			if delta > _b02:
				continue                                      # code 7
			if _budget[pt] == 0:
				continue
			if _budget[pt] - _cost[cur.surface & 0x3F] - span != here:
				continue
			out.append([_rough[pt], delta, sh44, px, py, pl])
	return out


## The walk-back itself: destination → start, one accepted predecessor at a time.
##
## Returns the chain as `[[x, y, lvl, span, px, py, pl], …]` running dest → start, or
## an EMPTY chain when the unit already stands on its target. `plan` distinguishes
## the two; `if chain.is_empty()` alone scores a zero-step walk as a failure and
## invents a ship-gate violation that is not there — the corpus contains two.
##
## `FUN_80177E64 @ 0x80177E64` is the ranking, and it is three tie-breaks deep:
## SPAN first (the adjacent pass runs before the span pass, so a one-tile step always
## beats a leap to the same tile), then ROUGHNESS, then "keep going the same
## direction". The value CARRIED FORWARD is `max(step delta, predecessor roughness)`;
## the value COMPARED against it is the next candidate's RAW roughness. They are not
## the same number and swapping them changes routes.
func _walk_back(start: Vector3i, dest: Vector3i) -> Array:
	var x: int = dest.x
	var y: int = dest.y
	var lvl: int = dest.z
	var prev_dir: int = 0
	var chain: Array = []
	var seq: int = 0
	for _step in _records:
		var t: int = _idx(lvl, x, y)
		seq += 1
		_seq[t] = seq
		var here: int = _budget[t]
		if here == 0:
			return []
		if x == start.x and y == start.y and lvl == start.z:
			return chain
		var best: Array = []
		for span in range(0, _b05 + 1):
			# `FUN_80175568` resets the ranking for each pass, and the driver only
			# reaches the span pass when the adjacent one found nothing.
			var b_rough: int = 0xFF
			for c in _candidates(x, y, lvl, span, here):
				if not best.is_empty():
					if b_rough < c[0]:
						continue
					if b_rough == c[0] and prev_dir != c[2]:
						continue
				b_rough = maxi(c[1], c[0])
				best = [span, c[2], c[3], c[4], c[5]]
			if not best.is_empty():
				break                                  # adjacent-first: span 0 wins
		if best.is_empty():
			return []
		chain.append([x, y, lvl, best[0], best[2], best[3], best[4]])
		prev_dir = best[1]
		x = best[2]
		y = best[3]
		lvl = best[4]
	return []


## `FUN_80176C90 @ 0x80176C90` — the emitted `DAT_8018F7F0` buffer: a count, then one
## byte per step.
##
## The byte is `dir << 6 | level << 5 | bit3 | bit2 | extra`:
##   * bits 6-7 the direction, in `FUN_80069F14`'s encoding ([constant ROUTE_BITS]);
##   * bit 5 the LEVEL the step lands on — 12 of the 209 replayed corpus routes set
##     it, seven of them in scenario 29, and no live capture ever has;
##   * bit 3 the tile being ENTERED is steep AND descends along the direction of
##     travel; bit 2 the tile being LEFT is steep. Both feed the renderer's gait;
##   * bits 0-1 `extra`, the leap's span. **This is the byte the shipped BFS could
##     never emit**, and the whole of #803.
func _route_bytes(chain: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(chain.size() - 1, -1, -1):
		var c: Array = chain[i]
		var x: int = c[0]
		var y: int = c[1]
		var lvl: int = c[2]
		var span: int = c[3]
		var px: int = c[4]
		var py: int = c[5]
		var pl: int = c[6]
		var dx: int = 0 if x == px else (1 if x > px else -1)
		var dy: int = 0 if y == py else (1 if y > py else -1)
		var bits: Vector3i = ROUTE_BITS[Vector2i(dx, dy)]
		var b: int = bits.x | ((lvl & 1) << 5) | (span & 3)
		# bit 2: the tile being LEFT is steep. No direction condition.
		if _steep(pl, px, py):
			b |= 4
		# bit 3: the tile being ENTERED is steep AND DESCENDS along the direction of
		# travel (corner `sh44` below corner `sh45`).
		if _steep(lvl, x, y) and to_s16(_corner(lvl, x, y, bits.y)
				- _corner(lvl, x, y, bits.z)) < 0:
			b |= 8
		out.append(b)
	if out.size() > MAX_ROUTE_STEPS:
		push_warning("[EventPathfinder] route of %d steps exceeds the ROM's %d-step buffer"
			% [out.size(), MAX_ROUTE_STEPS])
	var buf := PackedByteArray([out.size()])
	buf.append_array(out)
	return buf


## The emitter's steep-slope predicate, shared by route bits 2 and 3.
func _steep(lvl: int, x: int, y: int) -> bool:
	var m = _tile(lvl, x, y)
	if m.slope_h > _b04:
		return true
	return m.slope_h > 2 and bool(_pass[_idx(lvl, x, y)] & 2)
