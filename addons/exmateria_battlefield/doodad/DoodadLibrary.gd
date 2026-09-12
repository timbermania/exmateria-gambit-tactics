extends RefCounted

## Loader for doodad data from disk.
##
## Manages loading doodads from two locations, both BELOW the host-injected content root
## (`BattlefieldContent.ROOT_SETTING`; the in-repo game points it at `res://assets/`):
## 1. Maps: `<content_root>maps/` (for MAP### files)
## 2. Hand-crafted doodads: `<content_root>doodads/` (for custom doodads)
##
## Each doodad is a directory containing:
## - terrain.json (tile data)
## - geometry_linked.json (pre-correlated mesh with TriangleMetadata)
## - palettes.json (color palettes)
## - manifest.json (doodad-level: palette animation)
## - texture_indexed.tga or .png (indexed color texture)
##
## Palette texture is generated at runtime from palettes.json.
## Caches loaded doodads to avoid repeated disk I/O.

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const BattlefieldContent = preload("res://addons/exmateria_battlefield/install/BattlefieldContent.gd")
const Doodad = preload("res://addons/exmateria_battlefield/doodad/Doodad.gd")
const PaletteTextureGenerator = preload("res://addons/exmateria_battlefield/texturing/PaletteTextureGenerator.gd")


# ⚠️ Both roots were `res://assets/…` consts here. They are now composed from the
# host-injected content root — ADR-0202 dec. 5 Class B: the map tree is gitignored (a
# symlink into the asset hub) and the doodad tree is host content, so neither can ship
# inside the addon and the LITERAL is the defect. See `BattlefieldContent`.

# Cache of loaded doodads
var _cache: Dictionary = {}  # name -> Doodad


## Load a doodad by name.
##
## Searches in order:
## 1. Maps: `<content_root>maps/{name}/` (for MAP### files)
## 2. Hand-crafted doodads: `<content_root>doodads/{name}/`
##
## Caches the result for subsequent calls.
##
## Args:
##     name: Doodad name (directory name, e.g., "MAP022", "wooden_house")
##
## Returns:
##     Loaded Doodad instance, or null if loading failed
func load_doodad(name: String) -> Doodad:
	# Check cache first
	if _cache.has(name):
		return _cache[name]


	var maps_root: String = BattlefieldContent.maps_dir()
	var doodads_root: String = BattlefieldContent.doodads_dir()

	# Try maps folder first (for MAP### files)
	var map_path = maps_root + name + "/"
	if not maps_root.is_empty() and DirAccess.dir_exists_absolute(map_path):
		var doodad = _load_from_path(name, map_path)
		if doodad:
			_cache[name] = doodad
			return doodad

	# Fall back to doodads folder
	var doodad_path = doodads_root + name + "/"
	if not doodads_root.is_empty() and DirAccess.dir_exists_absolute(doodad_path):
		var doodad = _load_from_path(name, doodad_path)
		if doodad:
			_cache[name] = doodad
			return doodad

	push_error("DoodadLibrary: Doodad not found: '%s'" % name)
	return null


## Get list of all available doodads.
##
## Returns:
##     Array of doodad names (from both maps and doodads folders)
func list_doodads() -> Array[String]:
	var doodads: Array[String] = []
	var seen: Dictionary = {}

	# List maps first
	var maps_dir = DirAccess.open(BattlefieldContent.maps_dir())
	if maps_dir:
		maps_dir.list_dir_begin()
		var dir_name = maps_dir.get_next()
		while dir_name != "":
			if maps_dir.current_is_dir() and not dir_name.begins_with("."):
				if not seen.has(dir_name):
					doodads.append(dir_name)
					seen[dir_name] = true
			dir_name = maps_dir.get_next()
		maps_dir.list_dir_end()

	# Then list doodads folder
	var doodad_dir = DirAccess.open(BattlefieldContent.doodads_dir())
	if doodad_dir:
		doodad_dir.list_dir_begin()
		var dir_name = doodad_dir.get_next()
		while dir_name != "":
			if doodad_dir.current_is_dir() and not dir_name.begins_with("."):
				if not seen.has(dir_name):
					doodads.append(dir_name)
					seen[dir_name] = true
			dir_name = doodad_dir.get_next()
		doodad_dir.list_dir_end()

	return doodads


# Internal: Load doodad from a specific path
func _load_from_path(name: String, doodad_path: String) -> Doodad:
	var doodad = Doodad.new(name)

	# Load terrain.json
	doodad.terrain = _load_json(doodad_path + "terrain.json")
	if doodad.terrain.is_empty():
		push_error("DoodadLibrary: Failed to load terrain.json for '%s'" % name)
		return null

	# Load geometry_linked.json (pre-correlated from Phase 1 preprocessing)
	doodad.geometry = _load_json(doodad_path + "geometry_linked.json")
	if doodad.geometry.is_empty():
		push_error("DoodadLibrary: Failed to load geometry_linked.json for '%s'" % name)
		push_error("  Doodad must be preprocessed with: python tools/preprocess_doodad.py %s" % doodad_path)
		return null

	# Load palettes.json
	doodad.palettes = _load_json(doodad_path + "palettes.json")
	if doodad.palettes.is_empty():
		push_error("DoodadLibrary: Failed to load palettes.json for '%s'" % name)
		return null

	# Load manifest.json (doodad-level: palette animation)
	doodad.manifest = _load_json(doodad_path + "manifest.json")
	if doodad.manifest.is_empty():
		push_warning("DoodadLibrary: No manifest.json for '%s' (palette animation disabled)" % name)
		# Not fatal - doodad can work without manifest

	# Load texture_indexed (try TGA first, then PNG)
	doodad.texture = _load_texture(doodad_path + "texture_indexed.tga")
	if doodad.texture == null:
		doodad.texture = _load_texture(doodad_path + "texture_indexed.png")
	if doodad.texture == null:
		push_error("DoodadLibrary: Failed to load texture_indexed for '%s' (tried .tga and .png)" % name)
		return null

	# Generate palette texture from palettes.json
	doodad.palette_texture = PaletteTextureGenerator.create_palette_texture(doodad.palettes)
	if doodad.palette_texture == null:
		push_error("DoodadLibrary: Failed to generate palette texture for '%s'" % name)
		return null

	return doodad


# Internal: Load and parse JSON file
func _load_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("DoodadLibrary: File not found: %s" % file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("DoodadLibrary: Failed to open file: %s (Error: %d)" % [file_path, FileAccess.get_open_error()])
		return {}

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		push_error("DoodadLibrary: JSON parse error in %s at line %d: %s" % [
			file_path,
			json.get_error_line(),
			json.get_error_message()
		])
		return {}

	if not json.data is Dictionary:
		push_error("DoodadLibrary: JSON root is not a Dictionary in: %s" % file_path)
		return {}

	return json.data


# Internal: Load texture file
func _load_texture(file_path: String) -> Texture2D:
	# Load the imported texture resource. The .tga maps (texture_indexed.tga) are
	# imported lossless, so load() returns the same pixels via the optimized,
	# export-safe path. ResourceLoader.exists() gates on it being imported so an
	# un-imported file is treated as "missing" (caller falls back) instead of
	# emitting the "loaded as image file" warning.
	if not ResourceLoader.exists(file_path):
		# Not imported / missing — return null silently so the caller can fall back.
		return null
	var texture = load(file_path)
	if not texture:
		push_error("DoodadLibrary: Failed to load texture: %s" % file_path)
		return null

	return texture
