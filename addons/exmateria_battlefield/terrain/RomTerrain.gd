extends RefCounted
## `terrain.json` → the ROM's own tile array, in PSX coordinates.
##
## The input both halves of `{28} Walk To` need and neither could get. The RENDER
## half ([RomWalkStepper]) reads five bytes per tile; the ROUTING half
## ([EventPathfinder]) reads eight. `TerrainCell` carries four of them — `height`,
## `impassable`, `unselectable` and a surface NAME — so a `Lattice` cannot state a
## depth, a slope or a thickness, and every shipped `assets/maps/MAP###/terrain.json`
## states all three. This reads the file rather than widening the schema: the map
## data is already on disk in exactly the shape the ROM keeps it in, minus two
## conversions — the ADR-0052 Z flip, and the exporter's two enum NAMES back into
## the bytes they were exported from.
##
## 🔴 **THE Z FLIP IS THE READER'S JOB.** `terrain.json` rows are indexed by GODOT
## grid Z; the ROM indexes by PSX Y, and ADR-0052 mirrors one about the other:
## `psx_y = size_z - 1 - grid_z`. Skipping it returns a fully-formed, plausible
## route on a MIRRORED map and never throws — it cost one research round.
## `research/scenario29_walk_vs_jump/evidence/rom_event_flood.py`'s `load_map` is
## the reference implementation and it is the scored one; this is that function.
##
## 🔴 **THE TWO NAME TABLES ARE A SECOND COPY.** `tools/fft_exporter/models/terrain.py`
## owns `TerrainSlopeType` (13) and `TerrainSurfaceType` (64) and writes their NAMES
## into the JSON; nothing in Godot can import a Python enum, so the bytes are spelled
## again here. Two spellings of one table is a defect waiting to happen, so it is
## mechanized: `tools/check_rom_terrain_tables.py` parses BOTH and fails the
## pre-flight on any disagreement — a name in one and not the other, or a name
## mapped to a different byte. Do not edit either table without the other.

const RomWalkStepper = preload("res://addons/exmateria_battlefield/motion/RomWalkStepper.gd")
## Annotated, not duck-typed: ADR-0192 dec. 2/3 wants a lattice receiver provably
## `Lattice` even inside the addon, because an unannotated one infers `Node` here
## exactly as it does in a host file and a `has_method` probe over a member that no
## longer exists answers "nothing" rather than failing.
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")

## `TerrainSlopeType` name → byte. Thirteen entries, and the value IS the ROM's
## slope-type byte: `corner()` reads it two bits at a time (`(slope_t >> shift) & 3`)
## and the pass map reads `slope_t & 5`. `Flat` is 0 and every unknown name reads as
## 0, which is what a tile with no slope is.
const SLOPE_BYTE: Dictionary = {
	"Flat": 0,
	"InclineNorth": 133,
	"InclineEast": 82,
	"InclineSouth": 37,
	"InclineWest": 88,
	"ConvexNortheast": 65,
	"ConvexSoutheast": 17,
	"ConvexSouthwest": 20,
	"ConvexNorthwest": 68,
	"ConcaveNortheast": 150,
	"ConcaveSoutheast": 102,
	"ConcaveSouthwest": 105,
	"ConcaveNorthwest": 153,
}

## `TerrainSurfaceType` name → byte. Sixty-four entries — the map is TOTAL. The planner indexes its movement
## cost row `surface & 0x3F`, and three of the bytes here are load-bearing beyond
## that: `Waterway` (14) and the other water surfaces cost 2, `Obstacle` (28) and
## `Lava` (18) cost 0xFF, and `Obstacle`'s byte is also the destination gate's own
## refusal (`(surface & 0x3F) != 0x1C`).
const SURFACE_BYTE: Dictionary = {
	"NaturalSurface": 0,
	"SandArea": 1,
	"Stalactite": 2,
	"Grassland": 3,
	"Thicket": 4,
	"Snow": 5,
	"RockyCliff": 6,
	"Gravel": 7,
	"Wasteland": 8,
	"Swamp": 9,
	"Marsh": 10,
	"PoisonedMarsh": 11,
	"LavaRocks": 12,
	"Ice": 13,
	"Waterway": 14,
	"River": 15,
	"Lake": 16,
	"Sea": 17,
	"Lava": 18,
	"Road": 19,
	"WoodenFloor": 20,
	"StoneFloor": 21,
	"Roof": 22,
	"StoneWall": 23,
	"Sky": 24,
	"Darkness": 25,
	"Salt": 26,
	"Book": 27,
	"Obstacle": 28,
	"Rug": 29,
	"Tree": 30,
	"Box": 31,
	"Brick": 32,
	"Chimney": 33,
	"MudWall": 34,
	"Bridge": 35,
	"WaterPlant": 36,
	"Stairs": 37,
	"Furniture": 38,
	"Ivy": 39,
	"Deck": 40,
	"Machine": 41,
	"IronPlate": 42,
	"Moss": 43,
	"Tombstone": 44,
	"Waterfall": 45,
	"Coffin": 46,
	"FftbgPool": 47,
	"UnusedX30": 48,
	"UnusedX31": 49,
	"UnusedX32": 50,
	"UnusedX33": 51,
	"UnusedX34": 52,
	"UnusedX35": 53,
	"UnusedX36": 54,
	"UnusedX37": 55,
	"UnusedX38": 56,
	"UnusedX39": 57,
	"UnusedX3A": 58,
	"UnusedX3B": 59,
	"UnusedX3C": 60,
	"UnusedX3D": 61,
	"UnusedX3E": 62,
	"CrossSection": 63,
}

## Where the shipped maps live is the HOST's to say, not this addon's — ADR-0202
## dec. 5. The map tree is ROM-derived and gitignored, so the addon can never ship it
## and must not name `res://assets/` either; [BattlefieldContent] is the one injection
## point, and `MAPS_SUBPATH` is already the contract for exactly this tree. A stranger
## project that declares no content root gets one legible refusal instead of a silent
## empty load.
##
## It is also an ASSET SYMLINK in this repo — absent from a bare worktree — which is
## why every fixture-scored test bakes its own tiles rather than reading through here.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")

# map name -> Terrain. Reading and converting a 14x8x2 grid is cheap; doing it on
# every `{28} Walk To` in a cutscene that issues thirty of them is not, and the map
# does not change under a scenario, and a scene that changes maps changes
# `ScenarioVM.current_map_id` with it and gets a different key.
#
# There is deliberately NO `clear_cache()`. One was written and deleted unused: its
# docstring said "tests only" and no test called it, which in a diff reads exactly
# like working code. Every test here bakes its own tiles and never reaches
# `load_map`, so the eviction it offered has no caller. If one is ever needed, add
# it then — with the caller.
static var _cache: Dictionary = {}


## The map's tiles as a [RomWalkStepper.Terrain], or `null` if it has no
## `terrain.json` (no assets symlink, an unexported map, a synthetic scene).
##
## `null` is a real answer and callers must handle it: MAP053 ships in the corpus
## with no exported terrain, and a test scene that builds its lattice by hand has no
## map name at all. It is never a silently-empty grid, because an empty grid routes.
static func load_map(map_name: String) -> RomWalkStepper.Terrain:
	if _cache.has(map_name):
		return _cache[map_name]
	var base: String = BattlefieldContent.resolve(BattlefieldContent.MAPS_SUBPATH)
	if base.is_empty():
		_cache[map_name] = null
		return null
	var path: String = "%s%s/terrain.json" % [base, map_name]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[map_name] = null
		return null
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("terrain"):
		push_error("[RomTerrain] %s is not a terrain.json" % path)
		_cache[map_name] = null
		return null
	var terrain := from_json(parsed["terrain"])
	_cache[map_name] = terrain
	return terrain


## The map name for a scenario's `map_id`, the one spelling in the game.
## `ScenarioPlayerScene` builds the same string; a second `%03d` somewhere else is a
## second place to get the padding wrong.
static func map_name_for(map_id: int) -> String:
	return "MAP%03d" % map_id


## A parsed `terrain.json` `"terrain"` dict → tiles in PSX coordinates.
##
## Separate from [method load_map] so the conversion — the Z flip and the two name
## lookups, which is all of the risk — can be driven from a literal dict with no
## `res://assets` anywhere near it.
static func from_json(d: Dictionary) -> RomWalkStepper.Terrain:
	var nx: int = int(d.get("size_x", 0))
	var ny: int = int(d.get("size_z", 0))
	if nx <= 0 or ny <= 0:
		push_error("[RomTerrain] terrain has no size (%dx%d)" % [nx, ny])
		return null
	var tiles: Array = []
	for lvl in 2:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			row.resize(nx)
			rows.append(row)
		tiles.append(rows)
	for lvl in 2:
		var level_rows = d.get("level_%d" % lvl, [])
		for gz in ny:
			# ADR-0052: the exporter's row `gz` is the PSX row `ny - 1 - gz`.
			var psx_y: int = ny - 1 - gz
			for x in nx:
				var r = level_rows[gz][x] if gz < level_rows.size() \
					and x < (level_rows[gz] as Array).size() else {}
				tiles[lvl][psx_y][x] = _tile_from_row(r)
	return RomWalkStepper.Terrain.new(tiles, nx, ny)


## One `terrain.json` tile row → one [RomWalkStepper.MapTile].
##
## An absent field reads as the ROM's zero, and an unknown enum NAME reads as byte 0
## rather than raising: `Flat` and `NaturalSurface` are both 0, and both are what a
## tile the exporter could not classify behaves as.
static func _tile_from_row(r: Dictionary) -> RomWalkStepper.MapTile:
	return RomWalkStepper.MapTile.new(
		int(SURFACE_BYTE.get(String(r.get("surface_type", "")), 0)),
		int(r.get("height", 0)),
		int(r.get("depth", 0)),
		int(r.get("slope_height", 0)),
		int(SLOPE_BYTE.get(String(r.get("slope_type", "")), 0)),
		int(r.get("thickness", 0)),
		bool(r.get("impassable", false)),
		bool(r.get("unselectable", false)))

## The scene's `Lattice` as ROM tiles — the DEGRADED input, for a map with no
## `terrain.json`.
##
## 🔴 **THIS IS NOT A SECOND PLANNER, IT IS A POORER MAP.** There is one route
## planner and it always runs; what changes is how much of a tile the caller can
## state. A `TerrainCell` carries height, impassable, unselectable and a surface
## NAME — which is four of the eight bytes plus one lookup — and it carries no
## `depth`, `slope_height`, `slope_type` or `thickness` at all. So a route planned
## from a lattice has no draped corners, no water depth and no ceilings, which means
## no steep-slope route bits and a leap-clearance test that sees only floors.
##
## Reached by a scene that builds its terrain in code rather than loading a map —
## every scenario test does — and never by a shipped scenario, which always has a
## `map_id`. `ScenarioVM` warns when it lands here, because a silent downgrade of
## the map under a planner scored on real tiles is exactly the kind of thing that
## reads as a routing bug months later.
static func from_lattice(lattice: Lattice) -> RomWalkStepper.Terrain:
	if lattice == null:
		return null
	var cells: Array = lattice.all_cells()
	if cells.is_empty():
		return null
	var nx: int = 0
	var ny: int = 0
	for c in cells:
		nx = maxi(nx, c.grid.x + 1)
		ny = maxi(ny, c.grid.y + 1)
	if nx <= 0 or ny <= 0:
		return null
	var tiles: Array = []
	for _lvl in RomWalkStepper.LEVELS:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				# An absent cell is UNSELECTABLE, which is what the pass map and the
				# ceiling query both read as "there is nothing here" — not a
				# height-0 floor, which would be standable and would route.
				row.append(RomWalkStepper.MapTile.new(0, 0, 0, 0, 0, 0, false, true))
			rows.append(row)
		tiles.append(rows)
	for c in cells:
		if c.grid.x < 0 or c.grid.x >= nx or c.grid.y < 0 or c.grid.y >= ny:
			continue
		if c.grid.z < 0 or c.grid.z >= RomWalkStepper.LEVELS:
			continue
		tiles[c.grid.z][ny - 1 - c.grid.y][c.grid.x] = RomWalkStepper.MapTile.new(
			int(SURFACE_BYTE.get(c.surface_type, 0)), c.height, 0, 0, 0, 0,
			c.impassable, c.unselectable)
	return RomWalkStepper.Terrain.new(tiles, nx, ny)
