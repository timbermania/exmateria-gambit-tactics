extends RefCounted

## Shared constants for the procedural map system.
##
## Centralizes commonly-used constants to avoid duplication across builders.

# Coordinate system conversion
const TILE_SCALE: float = 1.0 / 0.56  # FFT tiles (0.56 units) scaled to Godot (1.0 unit)

# Water rendering parameters
const WATER_WAVE_HEIGHT: float = 0.05
const WATER_WAVE_FREQUENCY: float = 5.0
const WATER_WAVE_SPEED_BASE: float = 2.0

# Animation timing (PSX NTSC framerate)
const ANIMATION_TICKS_PER_SECOND: float = 30.0

# Palette animation configuration used to live here as four constants —
# PALETTE_ANIM_{START_ID,COUNT,FRAME_COUNT,FRAME_DURATION}, "palettes 13-15, 3 frames,
# 24 ticks". They were the fallback for a model that no longer exists: one contiguous
# palette range running one schedule. The schedule is now per palette id and comes from
# the map manifest, so an absent animation is an empty table, not a guessed default.
# See texturing/PaletteAnimationTable.gd.
const MAX_PALETTE_ID: int = 15
const MAX_PALETTE_ID_FLOAT: float = 15.0

# Surface type classification
const SURFACE_WATERWAY: String = "Waterway"
const SURFACE_DEEP_WATER: String = "DeepWater"
const SURFACE_SEA: String = "Sea"
const SURFACE_UNTEXTURED: String = "Untextured"
const SURFACE_WALL: String = "Wall"
const WATER_SURFACES = [SURFACE_WATERWAY, SURFACE_DEEP_WATER, SURFACE_SEA]

# Skirt geometry parameters live in SkirtConfig (class_name, runtime-tunable
# via the F3 debug panel). This file used to mirror them as const fallbacks,
# but the mirrors drifted out of sync with SkirtConfig's defaults.

# --- the half-step height rule (ADR-0218 dec. 5) ----------------------------
#
# FFT states terrain height in integer HALF-STEPS and the world is continuous, so
# somewhere a rule turns one into the other. It was written twice: once in the
# Python exporter (`tools/fft_exporter/models/terrain.py` `calculate_vertices`,
# which bakes `vertices` into `terrain.json`) and once as
# `DynamicTerrainBuilder`'s private flat-quad fallback, whose `0.25 * h *
# TILE_SCALE = 0.4464h` DISAGREED with the exporter's `0.4286h + 0.0357`. The
# fallback is reachable only by omitting a field no shipped `terrain.json` omits,
# so the disagreement never shipped — but a test fixture that stated terrain from
# heights would have been a THIRD copy, which is why the rule is here instead.
#
# The three numbers are PSX map units, and they are what makes the `/ 28` legible:
# one tile spans 28 of them, one half-step is 12 of them, and every surface sits
# one unit proud of its half-step. Divide by the tile span and you are in world
# units, because one tile IS one world unit.

## ADR-0091: the tile span is not re-typed here. `PsxNum` owns it, this addon
## already reaches `ExMateriaPlatform` and `plugin.cfg` `deps=` declares that, so
## the 28 is one fact with one home (ADR-0212 dec. 1 for the spelling).
const PsxNum = ExMateriaPlatform.PsxNum

const PSX_UNITS_PER_TILE := PsxNum.UNITS_PER_TILE
const PSX_UNITS_PER_HALF_STEP: float = 12.0
const PSX_SURFACE_LIFT: float = 1.0


## World Y of a tile's flat surface, from its FFT half-step `height` and `depth`.
##
## `(12·(height + depth) + 1) / 28` — the exporter's `base_y` in world units.
## Slopes add `slope_height · 3/7` to their lifted corners only, which this does
## NOT do: GDScript has no rule that turns `slope_type` into which corners lift
## (ADR-0218 Context), so a sloped tile states its corners instead.
static func surface_y(height: int, depth: int = 0) -> float:
	return (PSX_UNITS_PER_HALF_STEP * float(height + depth) + PSX_SURFACE_LIFT) / PSX_UNITS_PER_TILE


## The four world-space corners of a flat tile at (`grid_x`, `grid_z`), in the
## EXPORTER'S winding — the order `terrain.json` ships and therefore the order
## every real tile in the game carries. `DynamicTerrainBuilder`'s vertex-less
## fallback copies it rather than stating a second one (#749).
##
## That this IS the exporter's order is derived and then measured. Derived:
## `models/terrain.py` `calculate_vertices` emits the FFT corners
## `(-x, z) (-x, z+28) (-x-28, z+28) (-x-28, z)`; `exporters/coordinates.py`
## `convert_position` negates X and flips Z about the map's far edge, and
## `exporters/terrain.py` `renumber_tile_z` renumbers the tile INDEX by the same
## flip — so in grid units the four land where this function puts them. Measured:
## every tile of every shipped `assets/maps/*/terrain.json` — 28,930 of them,
## both levels, all 13 slope types — carries exactly this XZ order, none other.
##
## ⚠️ Winding is not the inert detail this docstring used to call it. Three
## readers genuinely do not care (the centre is a mean, the cliff rule is
## all-pairs, the collision shape is a convex hull), which is how the fallback's
## reversed cycle survived unnoticed — but `Tile.gd`'s highlight mesh assigns
## corner `i` a FIXED UV, so a reversed cycle mirrors the RANGETILE crop on that
## tile. Face orientation is not a consequence: both overlay shaders declare
## `cull_disabled` and say why.
static func flat_quad(grid_x: int, grid_z: int, y: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(grid_x, y, grid_z + 1),
		Vector3(grid_x, y, grid_z),
		Vector3(grid_x + 1, y, grid_z),
		Vector3(grid_x + 1, y, grid_z + 1),
	])
