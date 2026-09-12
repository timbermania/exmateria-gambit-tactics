extends RefCounted

## Data container for a doodad (reusable map content piece).
##
## A doodad contains all data needed to place a piece of content in the world:
## - Terrain: tile data with heights, surface types, vertices
## - Geometry: visual mesh data (pre-correlated with TriangleMetadata)
## - Palettes: color palette data
## - Manifest: palette animation settings
## - Texture: indexed color texture
##
## Examples: MAP022 (large base map), wooden_house (3×3 building), tree (1×1 foliage)

# Doodad metadata
var name: String = ""                # Unique doodad identifier (e.g., "MAP022", "wooden_house")

# Data loaded from files
var terrain: Dictionary = {}         # From terrain.json (tile data)
var geometry: Dictionary = {}        # From geometry_linked.json (pre-correlated triangles)
var palettes: Dictionary = {}        # From palettes.json (color palettes)
var manifest: Dictionary = {}        # From manifest.json (doodad-level: palette animation)
var texture: Texture2D = null        # From texture_indexed.tga or .png
var palette_texture: Texture2D = null  # Generated from palettes.json (16x32 lookup texture)

# Cached computed properties
var _bounds_cache: Rect2i = Rect2i()
var _bounds_cached: bool = false


func _init(doodad_name: String = ""):
	"""Initialize doodad with optional name.

	Args:
		doodad_name: Unique identifier for this doodad
	"""
	name = doodad_name


## Get the bounding rectangle of this doodad in tile coordinates.
##
## Calculates from terrain.terrain.level_0 array dimensions.
## Cached after first calculation.
##
## Returns:
##     Rect2i with position (0, 0) and size (width, height) in tiles
func get_bounds() -> Rect2i:
	if _bounds_cached:
		return _bounds_cache

	# Default bounds if no terrain data
	if not terrain.has("terrain"):
		push_warning("[Doodad.get_bounds] terrain has no 'terrain' key. Keys: %s" % terrain.keys())
		_bounds_cache = Rect2i(0, 0, 0, 0)
		_bounds_cached = true
		return _bounds_cache

	var terrain_data = terrain["terrain"]

	# Try to use size_x and size_z directly if available (simpler and more reliable)
	if terrain_data.has("size_x") and terrain_data.has("size_z"):
		var size_x = terrain_data["size_x"]
		var size_z = terrain_data["size_z"]
		_bounds_cache = Rect2i(0, 0, size_x, size_z)
		_bounds_cached = true
		return _bounds_cache

	if not terrain_data.has("level_0"):
		push_warning("[Doodad.get_bounds] terrain.terrain has no 'level_0' key. Keys: %s" % terrain_data.keys())
		_bounds_cache = Rect2i(0, 0, 0, 0)
		_bounds_cached = true
		return _bounds_cache

	var level_0 = terrain_data["level_0"]

	# Terrain is 2D array [z][x], so:
	# - Height (z-extent) = number of rows = level_0.size()
	# - Width (x-extent) = number of columns = row[0].size()

	var min_x = 0
	var min_z = 0
	var max_x = 0
	var max_z = 0

	if level_0 is Array and level_0.size() > 0:
		# Iterate through all tiles to find actual bounds from tile coordinates
		for z in range(level_0.size()):
			var row = level_0[z]
			if not row is Array:
				continue

			for x in range(row.size()):
				var tile = row[x]
				if not tile is Dictionary:
					continue

				# Get actual tile coordinates (don't trust array indices)
				var tile_x = tile.get("x", x)
				var tile_z = tile.get("z", z)

				# Update bounds
				if z == 0 and x == 0:
					# First tile - initialize bounds
					min_x = tile_x
					min_z = tile_z
					max_x = tile_x
					max_z = tile_z
				else:
					min_x = mini(min_x, tile_x)
					min_z = mini(min_z, tile_z)
					max_x = maxi(max_x, tile_x)
					max_z = maxi(max_z, tile_z)

		# Convert to Rect2i (position + size)
		# Add 1 to max because bounds are inclusive
		_bounds_cache = Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)
	else:
		push_warning("[Doodad.get_bounds] level_0 is not a valid array: type=%s, size=%s" % [typeof(level_0), level_0.size() if level_0 is Array else "N/A"])
		_bounds_cache = Rect2i(0, 0, 0, 0)

	_bounds_cached = true
	return _bounds_cache


## Check if doodad has valid data loaded.
##
## Returns:
##     true if all required data is present
func is_valid() -> bool:
	return (
		not terrain.is_empty() and
		not geometry.is_empty() and
		not palettes.is_empty() and
		texture != null
	)


