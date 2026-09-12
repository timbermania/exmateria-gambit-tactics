# psx-faithful-sim: a bit-exact transcription of the ROM's `{28} Walk To` render
# half — the `>>12` fixed point, the 28/12 render units and the two GTE LUTs ARE
# the hardware's own arithmetic, not a conversion of it, and routing any of them
# through `PsxMagnitude` would replace the thing under test with a model of it. The
# 43 510/43 510 field-frame score against thirteen live PSX captures is the whole
# point of the file and it does not survive a re-derivation. ADR-0091 §4, ADR-0225.
extends RefCounted
## The ROM's `{28} Walk To` RENDER half: one route byte buffer in, one per-frame
## trajectory out. The sibling of [EventPathfinder], which is the routing half.
##
## This is a TRANSCRIPTION, not a model. Every branch is a line of
## `battle_decompilation.c` cited by address, there are no free parameters, and it
## is scored against the wire: `research/scenario29_walk_vs_jump/evidence/rom_walk_render.py`
## is the same state machine in Python at **43 510 of 43 510 field-frames over 13
## PSX captures**, and `RomWalkStepperTest` replays those same thirteen captures
## against THIS file, frame for frame, over sixteen logged fields.
##
##     FUN_8006D818 @ 0x8006D818      the per-frame dispatcher AND the route stepper
##     FUN_8006CC94 @ 0x8006CC94      armed handler — the launch gate, the shape choice
##     FUN_8006CAD0 @ 0x8006CAD0      running handler — the arrival gate
##     unit_move_stepper @ 0x8006AF7C the integrator: four vertical cases, ONE gravity
##     FUN_8006C790 @ 0x8006C790      the apex — where the level commits
##     FUN_8006C4F8 @ 0x8006C4F8      touchdown: soft vs hard, sound, puff
##     FUN_8006C3D8 @ 0x8006C3D8      hard-landing recovery, held by the SEQ timer
##     FUN_8006A20C / A380 / A538 / AA80 / A7C0   walk / gait / leap / hop / big jump
##     FUN_800699F4 / 0x80069AF8      the direction vector, both signs
##     vec3_normalize @ 0x8001C068    GTE rsqrt LUT at 0x8002BA4C
##     SquareRoot0    @ 0x8001C268    GTE sqrt  LUT at 0x8002B8B8
##     FUN_8007C80C @ 0x8007C80C      ground height at a render point, slope-draped
##     FUN_8006D598 @ 0x8006D598      the two slope corners, `+0x96` and `+0x97`
##
## 🔴 **THERE ARE NO VERTICAL MODES.** The class this replaced had
## `enum VMode { FLAT, FALL, HOP, RAMP }`; the ROM has ONE integrator with four
## vertical CASES and one gravity, and a leap and a hop differ only in what seeds
## `+0x2C` and `+0x28`/`+0x30`. A descent is not a case at all — the walk cases
## integrate gravity themselves, which is why there is no drop branch anywhere. A
## sub-level slope is not a case either: it is a Y term in the direction vector.
## Research README §19 item 8, §22.2, §24.3.
##
## 🔴 **THE WALK ANIMATION IS A FUNCTION, NOT A CONSTANT.** `FUN_80082DF8` re-picks
## it from a band of `unit+0x38` on every re-latch. Speed 10 — the only speed ever
## shipped on the wire before 2026-09 — clears the first threshold by ONE subunit,
## which is why five captures and a hard-coded `14` scored 100 % for six sessions.
## 80 of the 282 shipped `{28}`s are not in that band. See [method _walk_anim].
##
## Coordinates are the ROM's throughout: **render units** (28 per tile edge, 12 per
## elevation level, **Y NEGATIVE UP**) and **subunits** (4096 per render unit) for
## position and velocity. Tile coordinates are PSX, so a caller holding Godot grid
## cells owes the ADR-0052 Z flip before it builds a [Terrain].
##
## Usage — one ROM frame per [method step], which returns `false` once the route is
## spent (the frame it returns `false` on did not happen):
##
##     var s := ExMateriaBattlefield.RomWalkStepper.new()
##     s.configure(terrain, Vector3i(2, 11, 0), route_bytes, 10.0)
##     while s.step():
##         print(s.render_x, s.render_y, s.render_z)
##
## Pure and scene-free: no nodes, no signals, no clock. `src/scenarios/ScenarioPathMotion.gd`
## is the host adapter that turns it into world-space Godot positions.


# --- ROM constants. Every one a literal in BATTLE.BIN. ------------------------

## `g_jump_arc_accel @ DAT_80096128` — subunits/frame², the ONE gravity.
const GRAVITY: int = 0x925
## A tile edge, in render units.
const TILE: int = 0x1C
## Terrain levels per column. `tile_ptr`'s `sltiu v0,a2,0x2` @ `0x8018400C` is the
## ROM's own bound, and the block after `0x8018F8CC` is exactly `0x1000` bytes =
## 2 levels x 256 slots x 8 bytes (ADR-0219). `Terrain.tile` masks with it.
const LEVELS: int = 2
## ... and in subunits (`28 << 12`).
const TILE_SU: int = 0x1C000
## The half tile a hop / big jump covers horizontally.
const HALF_TILE_SU: int = 0xE000
## One elevation level, in render units.
const LEVEL_RENDER: int = 12
## `FUN_8006A538`'s horizontal LITERAL. A leap ignores the `{28}` Speed operand.
const LEAP_SPEED: int = 0x3000
## The cap on the gravity accumulator.
const TERMINAL_VELY: int = 0x8000
## At or above this on touchdown: anim `0x20` and a landing freeze.
const HARD_LANDING_VELY: int = 0x6000
## 42 render units above ground swaps in anim `0x1F`.
const FAR_FALL_RENDER: int = 0x2A
## A drop shorter than this is instant, not a fall.
const SNAP_RENDER: int = 6

## Facing word by ROUTE direction (+X, -X, -Y, +Y) — `DAT_80067138`/`3C`.
const FACING := [0x0C00, 0x0400, 0x0000, 0x0800]
## Wind-up state by route direction — `DAT_80067140`.
const WINDUP_STATE := [0x15, 0x1D, 0x11, 0x19]
## Airborne state by route direction — `DAT_80067144`.
const AIRBORNE_STATE := [0x16, 0x1E, 0x12, 0x1A]
## These three are indexed by the DIRECTION SLOT `FUN_8006C2BC` returns, not by
## the route direction — a different table with a different order.
const APEX_SUCCESSOR := [0x13, 0x17, 0x1B, 0x1F]        # DAT_80093CA4
const HARD_LANDING := [0x14, 0x18, 0x1C, 0x20]          # DAT_80093CA8
const SOFT_LANDING_WALK := [0x02, 0x04, 0x06, 0x08]     # DAT_80093C9C
const SOFT_LANDING_GAIT := [0x0A, 0x0C, 0x0E, 0x10]     # DAT_80093CA0

## `FUN_80082DF8`'s two thresholds on `unit+0x38`: `slti v0,v1,0x3000` @ `0x80082E40`
## and `slti v0,v1,0x1401` @ `0x80082E48`.
const WALK_ANIM_FAST: int = 0x3000
const WALK_ANIM_SLOW: int = 0x1401

## `vec3_normalize`'s reciprocal-sqrt LUT — `0x8002BA4C` + index*2, 192 s16
## entries, index = mantissa − 0x40. All twelve entries read live in 2026-09 match.
const RSQRT := [
	4096, 4064, 4033, 4003, 3973, 3944, 3916, 3888, 3861, 3835, 3809, 3783,
	3758, 3734, 3710, 3686, 3663, 3640, 3618, 3596, 3575, 3554, 3533, 3513,
	3493, 3473, 3454, 3435, 3416, 3397, 3379, 3361, 3344, 3327, 3310, 3293,
	3276, 3260, 3244, 3228, 3213, 3197, 3182, 3167, 3153, 3138, 3124, 3110,
	3096, 3082, 3069, 3055, 3042, 3029, 3016, 3003, 2991, 2978, 2966, 2954,
	2942, 2930, 2919, 2907, 2896, 2885, 2873, 2862, 2852, 2841, 2830, 2820,
	2809, 2799, 2789, 2779, 2769, 2759, 2749, 2740, 2730, 2721, 2711, 2702,
	2693, 2684, 2675, 2666, 2657, 2649, 2640, 2631, 2623, 2615, 2606, 2598,
	2590, 2582, 2574, 2566, 2558, 2550, 2543, 2535, 2528, 2520, 2513, 2505,
	2498, 2491, 2484, 2477, 2469, 2462, 2456, 2449, 2442, 2435, 2428, 2422,
	2415, 2409, 2402, 2396, 2389, 2383, 2377, 2371, 2364, 2358, 2352, 2346,
	2340, 2334, 2328, 2322, 2317, 2311, 2305, 2299, 2294, 2288, 2283, 2277,
	2272, 2266, 2261, 2255, 2250, 2245, 2239, 2234, 2229, 2224, 2219, 2214,
	2209, 2204, 2199, 2194, 2189, 2184, 2179, 2174, 2170, 2165, 2160, 2155,
	2151, 2146, 2142, 2137, 2133, 2128, 2124, 2119, 2115, 2110, 2106, 2102,
	2097, 2093, 2089, 2084, 2080, 2076, 2072, 2068, 2064, 2060, 2056, 2052,
]

## `SquareRoot0`'s LUT — `0x8002B8B8` + index*2, same indexing.
const SQRT := [
	4096, 4127, 4159, 4190, 4222, 4252, 4283, 4314, 4344, 4374, 4404, 4434,
	4463, 4492, 4521, 4550, 4579, 4608, 4636, 4664, 4692, 4720, 4748, 4775,
	4802, 4830, 4857, 4884, 4910, 4937, 4964, 4990, 5016, 5042, 5068, 5094,
	5120, 5145, 5170, 5196, 5221, 5246, 5271, 5296, 5320, 5345, 5369, 5394,
	5418, 5442, 5466, 5490, 5514, 5538, 5561, 5585, 5608, 5632, 5655, 5678,
	5701, 5724, 5747, 5769, 5792, 5815, 5837, 5860, 5882, 5904, 5926, 5948,
	5970, 5992, 6014, 6036, 6058, 6079, 6101, 6122, 6144, 6165, 6186, 6207,
	6228, 6249, 6270, 6291, 6312, 6333, 6353, 6374, 6394, 6415, 6435, 6456,
	6476, 6496, 6516, 6536, 6556, 6576, 6596, 6616, 6636, 6656, 6675, 6695,
	6714, 6734, 6753, 6773, 6792, 6811, 6830, 6850, 6869, 6888, 6907, 6926,
	6945, 6963, 6982, 7001, 7020, 7038, 7057, 7075, 7094, 7112, 7131, 7149,
	7168, 7186, 7204, 7222, 7240, 7258, 7276, 7294, 7312, 7330, 7348, 7366,
	7384, 7401, 7419, 7437, 7454, 7472, 7489, 7507, 7524, 7542, 7559, 7576,
	7594, 7611, 7628, 7645, 7662, 7680, 7697, 7714, 7731, 7747, 7764, 7781,
	7798, 7815, 7832, 7848, 7865, 7882, 7898, 7915, 7931, 7948, 7964, 7981,
	7997, 8014, 8030, 8046, 8062, 8079, 8095, 8111, 8127, 8143, 8159, 8175,
]

# --- `unit+0x7f`, the state, grouped as `unit_move_stepper` switches on it ----
const _ARMED := [1, 3, 5, 7]
const _RUNNING := [2, 4, 6, 8]
const _GAIT_ARMED := [9, 0xB, 0xD, 0xF]
const _GAIT_RUNNING := [0xA, 0xC, 0xE, 0x10]
const _WINDUP := [0x11, 0x15, 0x19, 0x1D]
const _RISING := [0x12, 0x16, 0x1A, 0x1E]
const _FALLING := [0x13, 0x17, 0x1B, 0x1F]
const _RECOVER := [0x14, 0x18, 0x1C, 0x20]
const _AIRBORNE_ANY := [0x12, 0x16, 0x1A, 0x1E, 0x13, 0x17, 0x1B, 0x1F,
	0x2D, 0x31, 0x35, 0x39]

# --- §16.4's two surface tables, verbatim -------------------------------------
const _SOUND_28 := [0x03, 0x04, 0x1D]
const _WATER := [0x09, 0x0A, 0x0B, 0x0E, 0x0F, 0x10, 0x11, 0x2D]
const _SOUND_3A := [0x14, 0x1E, 0x1F]
const _PUFF_09 := [0x01, 0x02, 0x06, 0x07, 0x08, 0x0C, 0x0D, 0x13, 0x14, 0x15,
	0x16, 0x17, 0x1A, 0x1B, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x25, 0x28,
	0x29, 0x2A, 0x2C, 0x2E]


## One map tile out of the live tile array at `DAT_8018F8CC`. `slope_t` is the raw
## byte, not the exporter's enum NAME.
##
## EIGHT fields, and the split between them is which HALF of the opcode reads them.
## The RENDER half ([RomWalkStepper]) reads the first five — surface, height, depth,
## slope height, slope type. The ROUTING half ([EventPathfinder]) reads those same
## five and three more: `thickness` for the ceiling query `FUN_80176164` (a tile's
## UNDERSIDE is its corner minus `thickness * 2`), and `impassable` / `unselectable`
## for the pass map `FUN_80174E84`. The renderer never asks any of the three,
## because by the time a route byte exists the planner has already ruled on them.
##
## ⚠️ NOT `lattice/Tile.gd`, and deliberately not called `Tile`. That one is a
## `Node3D` the host can hold; this is an immutable VALUE the walk reads and never
## publishes. `tools/check_lattice_doors.py` flagged the collision the moment this
## file was written — a door handing out a `Tile` is criterion 3's whole subject —
## and it was right to: one addon with two `MapTile`s is a register that cannot tell
## which one crossed the boundary.
class MapTile:
	extends RefCounted
	var surface: int = 0
	var height: int = 0
	var depth: int = 0
	var slope_h: int = 0
	var slope_t: int = 0
	## Tile THICKNESS — how far down the solid volume extends below the tile's own
	## corner. Read only by the routing half's ceiling query and leap-clearance test.
	var thickness: int = 0
	## Pass-map inputs, routing half only (`FUN_80174E84` @ `0x80174E84`).
	var impassable: bool = false
	var unselectable: bool = false

	func _init(p_surface: int = 0, p_height: int = 0, p_depth: int = 0,
			p_slope_h: int = 0, p_slope_t: int = 0, p_thickness: int = 0,
			p_impassable: bool = false, p_unselectable: bool = false) -> void:
		surface = p_surface
		height = p_height
		depth = p_depth
		slope_h = p_slope_h
		slope_t = p_slope_t
		thickness = p_thickness
		impassable = p_impassable
		unselectable = p_unselectable


## `tile_height_lookup` plus the two height queries built on it. Indexed
## `[level][psx_y][x]`; `level` is the ROM's two-deep terrain bank, not a Godot
## grid axis, and the ROM's own lookup CLAMPS out of range rather than failing.
class Terrain:
	extends RefCounted

	var tiles: Array = []      ## [level][psx_y][x] -> MapTile
	var nx: int = 0
	var ny: int = 0

	func _init(p_tiles: Array, p_nx: int, p_ny: int) -> void:
		tiles = p_tiles
		nx = p_nx
		ny = p_ny

	## `tile_height_lookup`. Out of range clamps, as the ROM's does.
	func tile(x: int, y: int, level: int) -> MapTile:
		return tiles[level & 1][clampi(y, 0, ny - 1)][clampi(x, 0, nx - 1)]

	## `FUN_8007C80C @ 0x8007C80C` — the DRAPED surface at a render point, in
	## render Y (negative up).
	##
	## `slope_height` spans 12 render units per unit of it across the tile,
	## linearly in a per-shape parameter `t` in 0..84. **Twelve** slope types
	## drape and every other value is flat — all twelve were exercised live in
	## 2026-09 (arm B, four captures, `rom_walk_shadow.py` at 32 160/32 160
	## corner shorts), so none of this branch table is inferred.
	func ground_at(render_x: int, render_z: int, level: int) -> int:
		var t: MapTile = tile(RomWalkStepperSelf.trunc_div(render_x, TILE),
			RomWalkStepperSelf.trunc_div(render_z, TILE), level)
		var y: int = t.height * -LEVEL_RENDER
		var sh: int = t.slope_h
		if sh == 0:
			return y
		var fx: int = (render_x % TILE) if render_x >= 0 else -((-render_x) % TILE)
		var fz: int = (render_z % TILE) if render_z >= 0 else -((-render_z) % TILE)
		var p: int = 0
		var rising: bool = true
		# (parameter, rising) — rising subtracts `t*4*sh/28`, falling subtracts
		# `sh*12` minus the same. Both run 0..12*sh across the tile.
		match t.slope_t:
			0x52: p = 3 * fx; rising = true                       # InclineEast
			0x85: p = 3 * fz; rising = true                       # InclineNorth
			0x25: p = 3 * fz; rising = false                      # InclineSouth
			0x58: p = 3 * fx; rising = false                      # InclineWest
			0x41: p = 3 * mini(fx, fz); rising = true             # ConvexNortheast
			0x96: p = 3 * maxi(fx, fz); rising = true             # ConcaveNortheast
			0x14: p = 3 * maxi(fx, fz); rising = false            # ConvexSouthwest
			0x69: p = 3 * mini(fx, fz); rising = false            # ConcaveSouthwest
			0x11:                                                 # ConvexSoutheast
				if fx < TILE - fz: p = 3 * fx; rising = true
				else: p = 3 * fz; rising = false
			0x44:                                                 # ConvexNorthwest
				if TILE - fx < fz: p = 3 * fx; rising = false
				else: p = 3 * fz; rising = true
			0x66:                                                 # ConcaveSoutheast
				if TILE - fz <= fx: p = 3 * fx; rising = true
				else: p = 3 * fz; rising = false
			0x99:                                                 # ConcaveNorthwest
				if TILE - fx < fz: p = 3 * fz; rising = true
				else: p = 3 * fx; rising = false
			_:
				return y                                          # not a drape shape
		var ramp: int = RomWalkStepperSelf.trunc_div(p * 4 * sh, TILE)
		return y - (ramp if rising else sh * LEVEL_RENDER - ramp)


## Self-reference, so the inner classes can reach the file's static helpers.
## GDScript inner classes do not see the outer script's scope.
const RomWalkStepperSelf = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")


# --- the unit record, by `unit+` offset ---------------------------------------
var pos_x: int = 0          ## `+0x18`, subunits
var pos_y: int = 0          ## `+0x1c`, subunits, NEGATIVE UP
var pos_z: int = 0          ## `+0x20`, subunits
var vel_x: int = 0          ## `+0x28`
var vel_y: int = 0          ## `+0x2c`
var vel_z: int = 0          ## `+0x30`
## `+0x38` — the walk velocity magnitude, `operand << 1` where the operand is the
## LITTLE-ENDIAN 8.8 halfword at `{28}`+6..7. For an integral Speed that collapses
## to `Speed << 9`; six shipped instructions are fractional, so it does not always.
var mag: int = 0
var alt_mag: int = 0x2000   ## `+0x3c` — the GAIT magnitude, which ACCELERATES
var render_x: int = 0       ## `+0x40`
var render_y: int = 0       ## `+0x42`, negative up
var render_z: int = 0       ## `+0x44`
var facing: int = 0         ## `+0x70`, the 12-bit PSX facing word
var tile_x: int = 0         ## `+0x7c`
var tile_y: int = 0         ## `+0x7d`
var level: int = 0          ## `+0x7e`
var state: int = 0          ## `+0x7f`
var dst_x: int = 0          ## `+0x80`
var dst_y: int = 0          ## `+0x81`
var dst_level: int = 0      ## `+0x82`
var corner_dst: int = 0     ## `+0x96`
var corner_cur: int = 0     ## `+0x97`
var route_index: int = 0    ## `+0x98`
var route: Array = []       ## `+0x9c` — `[len, b0, b1, …]`
var on_unit: int = 0        ## `+0x11e` — standing on another unit's head
var route_byte: int = 0     ## `+0x11c`
var anim: int = 0           ## `(+0x1dc) >> 1`, the RUNNING animation
var latch: int = 0          ## `+0x0c`, the PENDING animation + 1
## Bit 27 of `*(uint *)(unit+0x80)` — which of the two leap poses comes next.
var pose_toggle: int = 0
## `+0x1e2` stand-in: the SEQ frame timer that holds a hard landing / a wind-up.
var landing_freeze: int = 0
## `func_0x80044018` ids, in the order they fired.
var sounds: Array[int] = []
## `FUN_80068A20` particle types, in the order they fired.
var puffs: Array[int] = []

var terrain: Terrain = null
## `landing_frames` is `[STATIC]`: 18, from ONE capture. The mechanism is known
## (`anim != 0x20 || +0x1E2 == 0`, §19 item 11) but the NUMBER must come from SEQ
## — `src/gpu/GPUAnimationTimingLoader.gd` already loads per-anim `total_frames`
## and the equivalence to arm K's 19 VBlanks has never been checked. #803 §3.
var landing_frames: int = 18


## Seed the walk. `start` is the PSX start tile as `(x, psx_y, level)`; `route` is
## the ROM's own buffer — a LENGTH byte followed by the route bytes, exactly the
## `0x80` bytes `FUN_8017813C` copies into `unit+0x9c`. `speed` is the `{28}`
## operand in whole Speed units and may be FRACTIONAL (8.8; five of scenario 29's
## own instructions are). `anim0` is whatever idle was playing when the walk armed.
func configure(p_terrain: Terrain, start: Vector3i, p_route: Array,
		speed: float, anim0: int = 0, p_landing_frames: int = 18) -> void:
	terrain = p_terrain
	route = p_route.duplicate()
	landing_frames = p_landing_frames
	tile_x = start.x
	tile_y = start.y
	level = start.z
	dst_x = tile_x
	dst_y = tile_y
	dst_level = level
	var ground: int = terrain.ground_at(tile_x * TILE + 14, tile_y * TILE + 14, level)
	pos_x = (tile_x * TILE + 14) << 12
	pos_y = ground << 12
	pos_z = (tile_y * TILE + 14) << 12
	vel_x = 0
	vel_y = 0
	vel_z = 0
	# `unit_movement_arm @ 0x8008C77C`: `+0x38 = param_5 << 1`, where `param_5` is
	# the raw 8.8 halfword. Go through the operand rather than shifting an int, or
	# the six fractional `{28}`s decode to the wrong magnitude.
	mag = (int(round(speed * 256.0)) & 0xFFFF) << 1
	alt_mag = 0x2000
	render_x = tile_x * TILE + 14
	render_y = ground
	render_z = tile_y * TILE + 14
	facing = 0
	state = 0
	corner_dst = 0
	corner_cur = 0
	route_index = 0
	on_unit = 0
	route_byte = 0
	anim = anim0
	latch = 0
	pose_toggle = 0
	landing_freeze = 0
	sounds = []
	puffs = []


# --- fixed-point primitives. MIPS divides and shifts round TOWARD ZERO. -------

## Integer divide rounding TOWARD ZERO, as MIPS `div` does — NOT GDScript's `/`
## on floats and not a floor.
static func trunc_div(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if ((a < 0) == (b < 0)) else -q


## `if (v < 0) v += 0xFFF; v >> 12` — the ROM's toward-zero `>>12`.
static func sar12(v: int) -> int:
	return ((v + 0xFFF) >> 12) if v < 0 else (v >> 12)


## GTE register 31: the count of leading SIGN bits of the 32-bit LZCS value.
static func lzcr(x: int) -> int:
	x &= 0xFFFFFFFF
	if (x >> 31) != 0:
		x = (~x) & 0xFFFFFFFF
	if x == 0:
		return 32
	var n: int = 0
	while x > 0:
		x >>= 1
		n += 1
	return 32 - n


## `vec3_normalize @ 0x8001C068` → the GTE worker at `0x8001C0C4`, returning the
## unit vector as `Vector3i` in 1/4096ths.
##
## 🔴 A cardinal axis comes back as **4095, not 4096** — which is the whole reason
## a Speed-10 walk moves 5118 subunits a frame against a magnitude of 5120. The
## cadence is not `224/Speed` exactly; it falls out of this.
static func vec3_normalize(x: int, y: int, z: int) -> Vector3i:
	var v0: int = x * x + y * y + z * z            # GTE SQR, sf = 0
	var v1: int = lzcr(v0) & ~1                    # LZCS / LZCR, forced even
	var shift: int = (31 - v1) >> 1
	var mant: int = (v0 << (v1 - 0x18)) if v1 >= 0x18 else (v0 >> (0x18 - v1))
	var t: int = RSQRT[mant - 0x40]                # lh at 0x8002BA4C
	return Vector3i((t * x) >> shift, (t * y) >> shift, (t * z) >> shift)


## `SquareRoot0 @ 0x8001C268`. LZCR-normalise, one LUT read, one shift back.
##
## NOT `64*sqrt(x)`: that approximation is 0.15 % high and misses the hop's launch
## velocity by 25 subunits. This is exact.
##
## ⚠️ UNDEFINED for a negative `a0`, in the ROM and here. The ROM indexes before
## `0x8002B8B8` and reads whatever precedes the LUT; GDScript indexes from the END
## of `SQRT` and returns a plausible number. Neither is meaningful and neither is
## reachable from `{28}` — but `arm_hop` can be handed one by an adversarial route,
## because the gate that CHOSE the hop (`cur_h + 1 < dst_h`) and the rise it then
## measures (`_rise_half_levels`, off the unit's live render Y) read different
## things. Deliberately not clamped: a clamp would be this file inventing a
## behaviour the hardware does not have, which is the one thing it must not do.
static func square_root0(a0: int) -> int:
	var v0: int = lzcr(a0)
	if v0 == 32:
		return 0
	var t2: int = v0 & ~1
	var t1: int = (19 - t2) >> 1
	var t3: int = t2 - 24
	var mant: int = (a0 << t3) if t3 >= 0 else (a0 >> (24 - t2))
	var t5: int = SQRT[mant - 0x40]
	return (t5 << t1) if t1 >= 0 else (t5 >> -t1)


## `project_velocity_onto_dir @ 0x80069DFC` — `(mag * dir) >> 12`, toward zero.
func _project_velocity(magnitude: int) -> void:
	vel_x = sar12(magnitude * vel_x)
	vel_y = sar12(magnitude * vel_y)
	vel_z = sar12(magnitude * vel_z)


# --- terrain queries ----------------------------------------------------------

## `FUN_8007D3F4` — the drape under the unit's own render position, at `+0x7e`.
func _ground_under() -> int:
	return terrain.ground_at(render_x, render_z, level)


## `FUN_8007D350` — the drape at the DESTINATION tile's centre, at `+0x82`.
func _ground_at_dest() -> int:
	return terrain.ground_at(dst_x * TILE + 14, dst_y * TILE + 14, dst_level)


## `FUN_8008278C @ 0x8008278C` — `tile[+3] >> 5`, the DEPTH nibble of the tile under
## the unit's RENDER position. The exporter already decodes `b3 >> 5` into `depth`,
## so this is that field read where the unit is standing, not a re-shift.
func _depth_under() -> int:
	return terrain.tile(trunc_div(render_x, TILE), trunc_div(render_z, TILE), level).depth


# --- route-byte decode --------------------------------------------------------

## `rb >> 6` — 0 = +X, 1 = −X, 2 = −Y, 3 = +Y. ⚠️ This is NOT the planner's
## neighbour-expansion order; they are two tables doing two jobs (§17.3, §17.7).
static func route_dir(rb: int) -> int:
	return rb >> 6


## `rb & 3` — the EXTRA tiles a leap spans beyond the first. A `{28}` walk can
## never emit more than 1 (the planner's max leap span is `jump >> 1`).
static func route_extra(rb: int) -> int:
	return rb & 3


## `FUN_8006C2BC @ 0x8006C2BC` — 0 = −Y, 1 = +X, 2 = +Y, 3 = −X.
##
## Derived from CURRENT vs DESTINATION tile every frame; it is NOT the state, and
## it is NOT [method route_dir]'s order.
func _direction_slot() -> int:
	if tile_y < dst_y:
		return 2
	if tile_y > dst_y:
		return 0
	if dst_x < tile_x:
		return 3
	if tile_x < dst_x:
		return 1
	return 2


## `FUN_800699F4 @ 0x800699F4` (sign −1) and `walk_route_consumer @ 0x80069AF8`
## (sign +1). ONE function, twice, with the Y term negated:
##
##     dir = (28·dx, sign · (corner − 1) · slope_height · 6, 28·dz)
##
## The armed half of a step uses `unit+0x97` (the CURRENT tile's corner) and sign
## −1; the running half uses `unit+0x96` (the DESTINATION's) and sign +1. A
## sub-level slope is exactly this Y term — there is no ramp case anywhere.
func _dir_vector(t: MapTile, corner: int, sign: int) -> void:
	var y: int = sign * (corner - 1) * t.slope_h * 6
	var d: int = route_dir(route_byte)
	var x: int = [TILE, -TILE, 0, 0][d]
	var z: int = [0, 0, -TILE, TILE][d]
	var v := vec3_normalize(x, y, z)
	vel_x = v.x
	vel_y = v.y
	vel_z = v.z


# --- the animation latch, `set_unit_animation_with_flags @ 0x80081978` --------

func _set_anim(anim_id: int, p_facing: int) -> void:
	facing = p_facing
	latch = anim_id + 1


## The next-frame consumer: `+0x1DC = id*2 + mirror`, so `anim = +0x1DC >> 1`. An
## animation latched on one frame is PAINTED on the next, which is why a launch
## frame still logs the walk anim.
func _paint_anim() -> void:
	if latch != 0:
		anim = latch - 1
		latch = 0


## `FUN_80082DF8 @ 0x80082DF8` — the walk anim is a BAND of `unit+0x38`, re-chosen
## fresh on every re-latch:
##
##     +0x38 <  0x1401   →  anim 14      (Speed ≤ 10)
##     +0x38 <  0x3000   →  anim 12      (Speed 11..23)
##     else              →  anim 13      (Speed ≥ 24)
##
## `depth_class` is `FUN_8008278C`'s return, `tile[+3] >> 5` — the DEPTH nibble of
## the tile under the unit's render position (`0x80082E1C`). At depth ≥ 2 the same
## three bands select 11 / 9 / 10 instead: the WADING set.
##
## ⚠️ The wading column is `[STATIC]`: no capture has ever put the unit on a
## depth-2 tile at re-latch time — MAP009's moat is depth 1 — so only the
## `depth_class < 2` column is scored against hardware. #803 §3.
##
## 🔴 It is `[STATIC]` and it IS REACHED. `rom_walk_render.py` made `depth_class` a
## defaulted parameter and then never passed it, which made the wading band
## *unreachable* rather than merely unscored — while the file's own comment claimed
## the opposite. The ROM has no such parameter: `FUN_80082DF8` calls
## `FUN_8008278C` itself, at `0x80082E1C`, off the tile under `+0x40`/`+0x44`. Wired
## here and in the spec on 2026-09-03; both still score 43 510/43 510, which is the
## evidence that wiring it moves nothing a capture has seen.
##
## ⚠️ A mounted unit (`+0x130 == 1`) short-circuits to anim `0x32` at `0x80082E14`,
## before any of this. Unreachable from `{28}`, so it is not transcribed.
func _walk_anim(depth_class: int = 0) -> int:
	var fast: int = 13 if depth_class < 2 else 10
	var mid: int = 12 if depth_class < 2 else 9
	var slow: int = 14 if depth_class < 2 else 11
	if mag >= WALK_ANIM_FAST:
		return fast
	return slow if mag < WALK_ANIM_SLOW else mid


# --- the five step arms. Each sets state, facing, destination and velocity. ---

## `+0x80/+0x81 = +0x7c/+0x7d ± (1 + extra)`, `+0x82 = rb >> 5 & 1`.
##
## Shared VERBATIM by A20C, A380, A538, AA80, A7C0 and A080 — which is why a
## leap's two-tile step is a RENDER-side fact and not a routing one.
func _set_destination() -> void:
	var d: int = route_dir(route_byte)
	var extra: int = route_extra(route_byte)
	dst_x = tile_x
	dst_y = tile_y
	if d == 0:
		dst_x = tile_x + 1 + extra
	elif d == 1:
		dst_x = tile_x - 1 - extra
	elif d == 2:
		dst_y = tile_y - 1 - extra
	else:
		dst_y = tile_y + 1 + extra
	dst_level = (route_byte >> 5) & 1


## `FUN_8006A20C @ 0x8006A20C` — the ordinary walk. The anim is NOT set here; it
## is re-latched out of [method _walk_anim].
func _arm_walk(cur_tile: MapTile) -> void:
	var corner: int = corner_cur
	var d: int = route_dir(route_byte)
	state = [3, 7, 1, 5][d]
	facing = FACING[d]
	_set_destination()
	latch = _walk_anim(_depth_under()) + 1
	_dir_vector(cur_tile, corner, -1)
	_project_velocity(mag)


## `FUN_8006A380 @ 0x8006A380` — the steep-slope GAIT. Anim `0x23`, and it runs on
## `+0x3c`, a magnitude that ACCELERATES under the same gravity.
func _arm_gait(cur_tile: MapTile) -> void:
	var corner: int = corner_cur
	var d: int = route_dir(route_byte)
	state = [0xB, 0xF, 9, 0xD][d]
	_set_anim(0x23, FACING[d])
	_set_destination()
	_dir_vector(cur_tile, corner, -1)
	_project_velocity(alt_mag)


## `FUN_8006A538 @ 0x8006A538` — the LEAP. It derives NOTHING from terrain:
##
##     n            = (extra·0x1C000 + 0xE000) / 0x6000     frames to the apex
##     unit+0x2c    = −n · 0x925
##     unit+0x28/30 = ±0x3000                               a LITERAL
##
## `extra <= 1` goes straight airborne on one of the two alternating poses;
## `extra >= 2` gets the wind-up state and anim `0x1E` instead.
func _arm_leap() -> void:
	var d: int = route_dir(route_byte)
	var extra: int = route_extra(route_byte)
	var n: int = (extra * TILE_SU + HALF_TILE_SU) / 0x6000
	vel_y = -n * GRAVITY
	if extra < 2:
		state = AIRBORNE_STATE[d]
		_set_anim(0x31 if pose_toggle != 0 else 0x30, facing)
		pose_toggle ^= 1
	else:
		state = WINDUP_STATE[d]
		_set_anim(0x1E, FACING[d])
	vel_x = 0
	vel_z = 0
	if d == 0:
		vel_x = LEAP_SPEED
	elif d == 1:
		vel_x = -LEAP_SPEED
	elif d == 2:
		vel_z = -LEAP_SPEED
	else:
		vel_z = LEAP_SPEED
	_set_destination()


## `dest height in half-levels + render_y / 6` — the rise the arc must make.
##
## Note it is measured against the unit's LIVE render Y, not against the current
## tile's record: `+0x42 / 6` is the unit's own height in half-levels.
func _rise_half_levels(dst_tile: MapTile) -> int:
	return (dst_tile.height * 2 + dst_tile.slope_h * corner_dst
		+ trunc_div(render_y, 6))


## `FUN_8006AA80 @ 0x8006AA80` — a HALF arc onto a tile at least one level higher:
##
##     v = SquareRoot0((6·dh + 1) · 0x925 · 2)     dh in HALF-levels
##     n = v / 0x925 ;  horizontal = ±0xE000 / n
##
## The horizontal here does NOT come from the `{28}` Speed operand, which is why a
## climbing step at Speed 3.5 costs 38 frames rather than 64.
func _arm_hop(dst_tile: MapTile) -> void:
	var d: int = route_dir(route_byte)
	var dh: int = _rise_half_levels(dst_tile)
	var v: int = square_root0((dh * 6 + 1) * GRAVITY * 2)
	vel_y = -v
	var n: int = trunc_div(v, GRAVITY)
	var h: int = trunc_div(HALF_TILE_SU, n)
	state = [0x16, 0x1E, 0x12, 0x1A][d]
	facing = FACING[d]
	vel_x = 0
	vel_z = 0
	if d == 0:
		vel_x = h
	elif d == 1:
		vel_x = -h
	elif d == 2:
		vel_z = -h
	else:
		vel_z = h
	_set_destination()
	_set_anim(0x31 if pose_toggle != 0 else 0x30, facing)
	pose_toggle ^= 1


## `FUN_8006A7C0 @ 0x8006A7C0` — the ≥ 4-level climb, anim `0x1E`. A TWO-phase
## arc: rise time from one `SquareRoot0`, fall time from a second, and the half
## tile spread over their sum.
##
## ⚠️ UNREACHABLE from `{28}` (§17.4) — the planner's climb gate is 3 levels, so
## nothing this file can be handed will reach it. Transcribed for completeness and
## scored by nothing; do not read a green suite as covering it.
func _arm_big_jump(dst_tile: MapTile) -> void:
	var d: int = route_dir(route_byte)
	var extra: int = route_extra(route_byte)
	var dh: int = _rise_half_levels(dst_tile) + 2     # note the +2 the hop has not
	var v: int = square_root0((dh + (extra + 1) * 2) * 6 * GRAVITY * 2)
	vel_y = -v
	var n: int = trunc_div(v, GRAVITY)
	var v2: int = square_root0((extra + 1) * 0xC * GRAVITY * 2)
	n += trunc_div(v2, GRAVITY)
	var h: int = trunc_div(HALF_TILE_SU, n)
	state = WINDUP_STATE[d]
	_set_anim(0x1E, FACING[d])
	vel_x = 0
	vel_z = 0
	if d == 0:
		vel_x = h
	elif d == 1:
		vel_x = -h
	elif d == 2:
		vel_z = -h
	else:
		vel_z = h
	_set_destination()


# --- the three boundary predicates. All render units; a tile edge is 28. ------

## `FUN_8006CBB8 @ 0x8006CBB8` — 7 units short of the CURRENT tile's far edge.
##
## The armed half of a step is therefore only 7 render units long, and the shape
## for the whole rest of the step is chosen there, three quarters of the way
## across the tile being LEFT.
func _gate_launch(d: int) -> bool:
	if d == 1:
		return (tile_x + 1) * TILE - 7 <= render_x
	if d == 3:
		return render_x <= tile_x * TILE + 7
	if d == 2:
		return (tile_y + 1) * TILE - 7 <= render_z
	return render_z <= tile_y * TILE + 7


## `FUN_8006C878 @ 0x8006C878` — the DESTINATION tile's CENTRE. A walk step runs
## centre to centre; only the airborne gate is a quarter tile.
func _gate_walk_arrival(d: int) -> bool:
	if d == 1:
		return dst_x * TILE + 14 <= render_x
	if d == 3:
		return render_x <= dst_x * TILE + 14
	if d == 2:
		return dst_y * TILE + 14 <= render_z
	return render_z <= dst_y * TILE + 14


## `FUN_8006C41C @ 0x8006C41C` — a quarter tile into the DESTINATION.
func _gate_touchdown(d: int) -> bool:
	if d == 1:
		return dst_x * TILE + 7 <= render_x
	if d == 3:
		return render_x <= (dst_x + 1) * TILE - 7
	if d == 2:
		return dst_y * TILE + 7 <= render_z
	return render_z <= (dst_y + 1) * TILE - 7


## `FUN_8006C94C @ 0x8006C94C` — quantise the axis of travel to the launch gate.
## This is what keeps a route from drifting: the sub-unit remainder is thrown away
## once per step, at the LAUNCH point, never at the destination.
func _snap_to_launch(d: int) -> void:
	if d == 1:
		render_x = (tile_x + 1) * TILE - 7
		pos_x = render_x << 12
	elif d == 3:
		render_x = tile_x * TILE + 7
		pos_x = render_x << 12
	elif d == 2:
		render_z = (tile_y + 1) * TILE - 7
		pos_z = render_z << 12
	elif d == 0:
		render_z = tile_y * TILE + 7
		pos_z = render_z << 12


## `FUN_8006CA3C @ 0x8006CA3C` — quantise to the destination tile's centre.
func _snap_to_centre(d: int) -> void:
	if d == 1 or d == 3:
		render_x = dst_x * TILE + 14
		pos_x = render_x << 12
	else:
		render_z = dst_y * TILE + 14
		pos_z = render_z << 12


# --- `unit_move_stepper @ 0x8006AF7C` — the integrator ------------------------

## The per-frame position integrator: ONE gravity, four vertical cases.
##
## Horizontal is unconditional (`pos += vel`). A DESCENT is not one of the four —
## the two walk cases integrate gravity themselves, which is why the ROM has no
## drop branch anywhere and why the `VMode.FALL` this file replaced was a mode the
## hardware does not have.
func _unit_move_stepper() -> void:
	var nx: int = trunc_div(pos_x + vel_x, TILE_SU)
	var nz: int = trunc_div(pos_z + vel_z, TILE_SU)
	# The level commits the frame the unit's NEXT position lands on the destination
	# tile — BEFORE the switch, so the first case's identical re-test can never
	# fire. That copy is dead code in the ROM.
	if nx == dst_x and nz == dst_y and level != dst_level:
		level = dst_level

	pos_x += vel_x
	pos_z += vel_z
	render_x = sar12(pos_x)
	render_z = sar12(pos_z)
	var g1: int = _ground_under()      # FUN_8007D3F4 — under the unit, right now
	var g2: int = _ground_at_dest()    # FUN_8007D350 — at the destination centre
	var st: int = state

	if st in _ARMED or st in _GAIT_ARMED:
		var gait: bool = st in _GAIT_ARMED
		pos_y += vel_y
		var t: MapTile = terrain.tile(nx, nz, level)
		var y: int = sar12(-pos_y)
		if y <= -g1:                                   # on (or through) the ground
			pos_y = g1 << 12
			if gait and alt_mag < TERMINAL_VELY:
				alt_mag += GRAVITY                     # the gait magnitude ACCELERATES
			_dir_vector(t, corner_cur, -1)
			_project_velocity(alt_mag if gait else mag)
			_tail()
			return
		if y < -g1 + SNAP_RENDER:
			pos_y = g1 << 12                           # a sub-half-level drop is instant
		elif vel_y < TERMINAL_VELY:
			vel_y += GRAVITY
		if sar12(-pos_y) >= FAR_FALL_RENDER - g1:
			state = 0x1A
			_set_anim(0x1F, facing)
		_tail()
		return

	if st in _RUNNING or st in _GAIT_RUNNING:
		var gait2: bool = st in _GAIT_RUNNING
		pos_y += vel_y
		var t2: MapTile = terrain.tile(nx, nz, level)
		var y2: int = sar12(-pos_y)
		if y2 <= -g1:
			pos_y = g1 << 12
			if gait2 and alt_mag < TERMINAL_VELY:
				alt_mag += GRAVITY
			_dir_vector(t2, corner_dst, 1)             # NOTE: +0x96, and sign +6
			_project_velocity(alt_mag if gait2 else mag)
		y2 = sar12(-pos_y)
		if -g1 < y2:                                   # still above the ground
			if y2 < -g1 + SNAP_RENDER:
				pos_y = g1 << 12
			elif vel_y < TERMINAL_VELY:
				vel_y += GRAVITY
			if FAR_FALL_RENDER - g2 <= sar12(-pos_y):
				state = 0x1B
				_set_anim(0x1F, facing)
		_tail()
		return

	if st in _AIRBORNE_ANY:
		if vel_y < TERMINAL_VELY:
			vel_y += GRAVITY
		pos_y += vel_y
		if vel_y > 0 and sar12(-pos_y) < -g1:
			pos_y = g1 << 12                           # never sink below ground
		_tail()
		return
	_tail()


## `FUN_8008957C @ 0x8008957C` — project position to render, at the tail.
##
## This is the ONLY per-frame writer of `unit+0x42`; `unit_move_stepper` itself
## never touches it, which is why every vertical case works in `+0x1c`.
func _tail() -> void:
	render_x = sar12(pos_x)
	render_y = sar12(pos_y)
	render_z = sar12(pos_z)


# --- the per-state handlers ---------------------------------------------------

## `FUN_8006D598 @ 0x8006D598` — `+0x97` (current) and `+0x96` (destination).
##
## Exactly the per-direction shifts the PLANNER uses for `stateA+0x44/+0x45`
## (§21.2): router and renderer agree on what a tile's height is.
func _pick_corners(cur_tile: MapTile, dst_tile: MapTile) -> void:
	var d: int = route_dir(route_byte)
	if d == 0:                                   # +X
		corner_dst = (dst_tile.slope_t & 0x0C) >> 2
		corner_cur = cur_tile.slope_t & 3
	elif d == 1:                                 # −X
		corner_dst = dst_tile.slope_t & 3
		corner_cur = (cur_tile.slope_t & 0x0C) >> 2
	elif d == 2:                                 # −Y
		corner_dst = dst_tile.slope_t >> 6
		corner_cur = (cur_tile.slope_t & 0x30) >> 4
	else:                                        # +Y
		corner_dst = (dst_tile.slope_t & 0x30) >> 4
		corner_cur = cur_tile.slope_t >> 6
	if on_unit != 0:
		corner_cur = 0
	if (route_byte & 0x10) != 0:
		corner_dst = 0


## `FUN_8006BAD8 @ 0x8006BAD8` — the tile the current route byte points at.
func _neighbour_tile() -> MapTile:
	var d: int = route_dir(route_byte)
	var extra: int = route_extra(route_byte)
	var x: int = tile_x
	var y: int = tile_y
	if d == 0:
		x += 1 + extra
	elif d == 1:
		x -= 1 + extra
	elif d == 2:
		y -= 1 + extra
	else:
		y += 1 + extra
	return terrain.tile(x, y, (route_byte >> 5) & 1)


## `b2*2 + (b3 & 0x1f)*corner` — the SAME formula the planner uses (§21.2).
static func _tile_half_levels(t: MapTile, corner: int) -> int:
	return (t.height * 2 + t.slope_h * corner) & 0xFF


## `FUN_8006CC94 @ 0x8006CC94` — integrate, then at the launch gate CHOOSE.
func _handle_armed(cur_tile: MapTile, dst_tile: MapTile) -> void:
	var d: int = _direction_slot()
	_unit_move_stepper()
	if not _gate_launch(d):
		return
	_snap_to_launch(d)
	if (route_byte & 3) != 0:                     # checked FIRST: a leap is a leap
		alt_mag = 0x2000
		_arm_leap()
		on_unit = 0
		return
	var cur_h: int = _tile_half_levels(cur_tile, corner_cur)
	var dst_h: int = _tile_half_levels(dst_tile, corner_dst)
	# `FUN_8007CFF8`'s water term is added to `cur_h` TWICE and to `dst_h` never —
	# a transcription-visible ROM bug, inert for `{28}` because the term is 0 for a
	# cutscene actor (§20.3).
	if cur_h + 1 < dst_h:                         # ≥ 1 level up
		alt_mag = 0x2000
		if cur_h + 7 < dst_h:                     # ≥ 4 levels up
			_arm_big_jump(dst_tile)
		else:
			_arm_hop(dst_tile)
		on_unit = 0
	elif ((route_byte >> 3) & 1) != 0:
		_arm_gait(cur_tile)
		state = 0x0E                              # a LITERAL, not a direction table
	else:
		_arm_walk(cur_tile)
		state = 6                                 # ditto


## `FUN_8006CAD0 @ 0x8006CAD0` — integrate, then at the tile CENTRE finish.
##
## The step only finishes when BOTH gates pass: horizontally at the centre and
## vertically at or below the ground. A descent parks at the centre with zero
## horizontal velocity and keeps falling — that IS the drop case.
func _handle_running() -> void:
	var d: int = _direction_slot()
	_unit_move_stepper()
	if not _gate_walk_arrival(d):
		return
	_snap_to_centre(d)
	vel_z = 0
	vel_x = 0
	var g: int = _ground_under()
	if g <= render_y:
		tile_x = dst_x
		tile_y = dst_y
		vel_y = 0
		pos_y = g << 12
		render_y = sar12(pos_y)
		state = 0


## `FUN_8006C790 @ 0x8006C790` — the rising half. It does NOT integrate, and it
## FALLS THROUGH to `FUN_8006C4F8` in the dispatcher, so a rising frame runs both.
##
## The level commits here, which is why the first half of a leap draws its shadow
## on the departure level and the second half on the arrival one.
func _handle_apex() -> void:
	var d: int = _direction_slot()
	if vel_y >= 0:
		state = APEX_SUCCESSOR[d]
		level = dst_level
		on_unit = 0


## `FUN_8006C4F8 @ 0x8006C4F8` — integrate, then touchdown.
func _handle_airborne(cur_tile: MapTile) -> void:
	var d: int = _direction_slot()
	_unit_move_stepper()
	if not _gate_touchdown(d):
		return
	vel_z = 0
	vel_x = 0
	var g: int = _ground_under()
	if render_y < g:                               # still above the ground
		return
	var soft: bool = (anim - 0x30 >= 0 and anim - 0x30 < 2) and vel_y < HARD_LANDING_VELY
	if soft:
		vel_y = 0
		if ((route_byte >> 3) & 1) != 0:
			_arm_gait(cur_tile)
			state = SOFT_LANDING_GAIT[d]
		else:
			_arm_walk(cur_tile)
			state = SOFT_LANDING_WALK[d]
		var t: MapTile = terrain.tile(dst_x, dst_y, dst_level)
		if t.depth == 0:
			return                                 # a soft landing on dry land is SILENT
		if (t.height + t.depth) * LEVEL_RENDER <= -render_y:
			return                                 # landed above the water surface
	else:
		vel_y = 0
		state = HARD_LANDING[d]
		landing_freeze = landing_frames
		_set_anim(0x20, facing)
	if (route_byte & 0x10) != 0:
		sounds.append(0x28)                        # landed on another unit's head
		return
	var lt: MapTile = terrain.tile(dst_x, dst_y, dst_level)
	sounds.append(landing_sound(lt.surface))
	var puff: int = landing_puff(lt.surface)
	if puff >= 0:
		puffs.append(puff)


## `FUN_8006C3D8 @ 0x8006C3D8` — held while anim `0x20`'s SEQ timer runs.
func _handle_recover(cur_tile: MapTile) -> void:
	if landing_freeze > 0:
		landing_freeze -= 1
		return
	var d: int = _direction_slot()
	if ((route_byte >> 3) & 1) != 0:
		_arm_gait(cur_tile)
		state = SOFT_LANDING_GAIT[d]
	else:
		_arm_walk(cur_tile)
		state = SOFT_LANDING_WALK[d]


## `FUN_8006B994 @ 0x8006B994` → `func_0x80044018(id)`. §16.4's table, verbatim;
## the 46-surface accounting closes exactly, but ⚠️ **nothing has ever been HEARD
## fire** — the sound is `[STATIC]`, like the puff. #803 §3.
static func landing_sound(surface: int) -> int:
	if surface in _SOUND_28:
		return 0x28
	if surface in _WATER:
		return 0x23
	if surface in _SOUND_3A:
		return 0x3A
	return 0x29


## `FUN_8006BA38 @ 0x8006BA38`. Returns **−1** where the ROM emits NOTHING — the
## `None` of the Python transcription, and not a particle id.
static func landing_puff(surface: int) -> int:
	if surface in _WATER:
		return 0x0F            # FUN_80068AF4 — the SPLASH
	if surface in _PUFF_09:
		return 0x09            # FUN_80068B14 — the solid-ground dust
	return -1


## `0x8007EB4C`–`0x8007EB74`, the tail of the sprite pass `FUN_8007E9A8`: a sprite
## is never drawn below its own ground.
##
##     a0 = FUN_8007D3F4(unit)          ; the drape under +0x40/+0x44, at +0x7e
##     if ((short)a0 < unit->0x42) {    ; negative is UP: the ground is ABOVE
##         unit->0x42 = a0
##         unit->0x1c = (short)a0 << 12
##     }
##
## It runs BEFORE the movement pass in the frame and reads the render position the
## PREVIOUS frame's `_tail` left behind. This one BRANCH — not a term — is the
## whole of §24.8's residual: a hop whose horizontal crosses into a destination
## tile HIGHER than the sprite has climbed to is lifted to that tile's surface for
## one frame, and the integrator then adds that frame's velY on top. Four handoffs
## searched the mover for it; it was never in the mover.
func _floor_clamp() -> void:
	var g: int = _ground_under()
	if g < render_y:
		render_y = g
		pos_y = g << 12


## `FUN_8006D818 @ 0x8006D818` — ONE game-loop frame: dispatch, then step the
## route. Returns `false` once the route is spent; the frame it returns `false` on
## did not happen, so a caller collects state AFTER a `true`.
func step() -> bool:
	_floor_clamp()                                # FUN_8007E9A8's tail, first
	_paint_anim()
	var cur_tile: MapTile = terrain.tile(tile_x, tile_y, level)
	var dst_tile: MapTile = _neighbour_tile()
	var st: int = state

	if st in _ARMED or st in _GAIT_ARMED:
		_handle_armed(cur_tile, dst_tile)
	elif st in _RUNNING or st in _GAIT_RUNNING:
		_handle_running()
	elif st in _WINDUP:
		if landing_freeze > 0:                    # +0x1e2, the wind-up anim's timer
			landing_freeze -= 1
		else:
			state = st + 1
			_set_anim(0x1F, facing)
			sounds.append(0x27)                   # FUN_8006B960(unit, 0x27)
	elif st in _RISING:
		_handle_apex()                            # NO break — falls through
		_handle_airborne(cur_tile)
	elif st in _FALLING:
		_handle_airborne(cur_tile)
	elif st in _RECOVER:
		_handle_recover(cur_tile)

	if state == 0:                                # the step finished: advance
		var n: int = route[0]
		if n == 0xFE or n == 0xFF or n == 0 or route_index >= n:
			return false                          # FUN_8006BCE4 — the walk is over
		route_byte = route[1 + route_index]
		route_index += 1
		cur_tile = terrain.tile(tile_x, tile_y, level)
		dst_tile = _neighbour_tile()
		_pick_corners(cur_tile, dst_tile)         # FUN_8006D598
		if ((route_byte >> 2) & 1) != 0:          # bit 2 — LEAVING a steep tile
			_arm_gait(cur_tile)
		else:
			alt_mag = 0x2000
			_arm_walk(cur_tile)
	return true


# --- construction helpers -----------------------------------------------------

## Build a [Terrain] from a packed `[level][psx_y][x] -> [surface, height, depth,
## slope_h, slope_t]` array — the shape `tests/fixtures/rom_walk/*.json` ships and
## the shape a `terrain.json` reader produces after the ADR-0052 Z flip.
static func terrain_from_packed(packed: Array, nx: int, ny: int) -> Terrain:
	var tiles: Array = []
	for lvl in 2:
		var rows: Array = []
		for y in ny:
			var row: Array = []
			for x in nx:
				var r: Array = packed[lvl][y][x]
				row.append(MapTile.new(int(r[0]), int(r[1]), int(r[2]),
					int(r[3]), int(r[4])))
			rows.append(row)
		tiles.append(rows)
	return Terrain.new(tiles, nx, ny)


## Build a FLAT [Terrain] `nx × ny` from a `[level][psx_y][x] -> height` array —
## the honest terrain a caller that has only a waypoint POLYLINE can state.
##
## ⚠️ It has no drape, no depth and no surface, so no gait, no splash and no
## sub-level slope can fire on it. That is a statement about the CALLER's data,
## not about this file: see `ScenarioPathMotion.configure`.
static func terrain_flat(heights: Array, nx: int, ny: int,
		surface: int = 0x03) -> Terrain:
	var tiles: Array = []
	for lvl in 2:
		var rows: Array = []
		for y in ny:
			var row: Array = []
			for x in nx:
				row.append(MapTile.new(surface, int(heights[lvl][y][x]), 0, 0, 0))
			rows.append(row)
		tiles.append(rows)
	return Terrain.new(tiles, nx, ny)
