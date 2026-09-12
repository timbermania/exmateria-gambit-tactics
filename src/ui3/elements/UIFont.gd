@tool
class_name UIFont
extends RefCounted
## FFT bitmap font renderer using extracted font atlas
##
## Usage:
##   var font = UIFont.new()
##   font.load_font("res://assets/fonts")
##   var texture = font.render_text("Hello World")
##
## Vault: [[Dialogue Font Palette]]
## Vault: [[Display Message Opcode]]

const FONT_PATH = "res://assets/fonts"

# Font metrics
var char_width: int = 10
var char_height: int = 14
var atlas_width: int = 640
var atlas_height: int = 490
var chars_per_row: int = 64

# Atlas texture
var atlas_texture: Texture2D = null

# Character data: index -> {width, atlas_x, atlas_y}
var characters: Dictionary = {}

# ASCII char -> FFT index mapping
var char_to_index: Dictionary = {}

# ROM-dumped 16-color dialog font CLUT (Array[Color]; see
# display_message_dialog_type_and_palette_decode.md Part 9). Empty if the
# meta predates the dump. Slots 1-3 = body ramp, 9-11 = speaker ramp.
var dialog_clut: Array[Color] = []

# font_meta.json is 275 KB and READ-ONLY for the life of the process, but UIFont is constructed
# per-owner (UIMenuText, UIUnitNameplate, UIChar, ChangeJobScreen, every detail picker, ...) —
# so each `new()` used to re-run one 12.7 ms JSON.parse. That was ~13 ms of the ~44 ms
# synchronous build behind "opening a picker lags the game". The parsed Dictionary is cached
# per font_dir and handed out as-is; treat it as IMMUTABLE (nothing outside load_font writes to
# `characters` / `char_to_index`, and UI3ManifestCacheTest pins that the cache stays honest).
static var _meta_cache: Dictionary = {}       # font_dir -> parsed manifest Dictionary
static var _meta_parse_count: int = 0         # real parses only — the cache guard's signal


func _init():
	load_font(FONT_PATH)


## How many times a font manifest has actually been read+parsed this process. A cache HIT does
## not increment it, so a guard can assert "N constructions, zero re-parses" without wall-clock.
static func manifest_parse_count() -> int:
	return _meta_parse_count


## Drop the parse cache. Only for tooling that rewrites font_meta.json in place (the @tool
## editor path) — gameplay never needs it.
static func clear_manifest_cache() -> void:
	_meta_cache.clear()


func load_font(font_dir: String) -> bool:
	"""Load font atlas and metadata from directory."""
	var meta_path = font_dir + "/font_meta.json"
	var atlas_path = font_dir + "/font_atlas.tga"

	var data = _load_manifest(font_dir, meta_path)
	if data == null:
		return false
	char_width = data.get("char_width", 10)
	char_height = data.get("char_height", 14)
	atlas_width = data.get("atlas_width", 640)
	atlas_height = data.get("atlas_height", 490)
	chars_per_row = data.get("chars_per_row", 64)
	characters = data.get("characters", {})
	char_to_index = data.get("char_to_index", {})

	dialog_clut.clear()
	for entry in data.get("dialog_clut", []):
		if entry is Array and entry.size() >= 3:
			var a := (float(entry[3]) / 255.0) if entry.size() >= 4 else 1.0
			dialog_clut.append(Color(
				float(entry[0]) / 255.0, float(entry[1]) / 255.0,
				float(entry[2]) / 255.0, a))

	# Load atlas texture
	if not ResourceLoader.exists(atlas_path):
		push_error("UIFont: Missing font_atlas.tga at %s" % atlas_path)
		return false

	atlas_texture = load(atlas_path)
	if not atlas_texture:
		push_error("UIFont: Cannot load atlas texture at %s" % atlas_path)
		return false

	return true


## Read + parse font_meta.json once per font_dir, then serve the same Dictionary forever.
## Returns null (and push_error's, exactly as the inline code did) on any failure — a failed
## parse is NOT cached, so a fixed-up file is picked up on the next construction.
static func _load_manifest(font_dir: String, meta_path: String) -> Variant:
	if _meta_cache.has(font_dir):
		return _meta_cache[font_dir]

	if not FileAccess.file_exists(meta_path):
		push_error("UIFont: Missing font_meta.json at %s" % meta_path)
		return null

	var file = FileAccess.open(meta_path, FileAccess.READ)
	if not file:
		push_error("UIFont: Cannot open %s" % meta_path)
		return null

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	_meta_parse_count += 1

	if err != OK:
		push_error("UIFont: JSON parse error in %s" % meta_path)
		return null

	_meta_cache[font_dir] = json.data
	return json.data


func get_char_index(c: String) -> int:
	"""Get FFT character index for an ASCII character."""
	if char_to_index.has(c):
		return char_to_index[c]
	# Fallback: try direct ASCII code (for unknown chars, use '?')
	return char_to_index.get("?", 0x3F)


func get_char_info(index: int) -> Dictionary:
	"""Get character info by FFT index."""
	var key = str(index)
	if characters.has(key):
		return characters[key]
	return {"width": char_width, "atlas_x": 0, "atlas_y": 0}


func get_char_width(c: String) -> int:
	"""Get pixel width of a character."""
	var index = get_char_index(c)
	var info = get_char_info(index)
	return info.get("width", char_width)
