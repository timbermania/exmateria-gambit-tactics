class_name EvtFaceCatalog
extends RefCounted
## Resolves an EVTFACE (row, col) event-dialogue portrait to its Godot texture.
##
## The {50} Portrait Row opcode selects a row-block; the {10}/{51} Portrait byte
## picks a column (col = byte - 1). Together they address one of the 64 EVTFACE
## portraits parsed by `tools/parse_evtface.py` into
## `assets/scenarios/faces/face_r<R>_c<C>.png` (+ evtface.json). This is the
## message-box face for scripted cutscenes (e.g. Balbanes deathbed, scn14 =
## row0,col0) — distinct from the in-battle unit-SPR portrait path.
## PORTRAIT_ROW_OPCODE_50_EVTFACE.md.

const FACES_DIR := "res://assets/scenarios/faces/"
const ROWS := 8
const COLS := 8

# Cache of loaded textures keyed by "row_col"; textures are shared/immutable so a
# single instance per (row,col) is safe to reuse across every box.
static var _cache: Dictionary = {}


## Resolve EVTFACE (row, col) -> its 32x48 face Texture2D, or null if the coords
## are outside the 8x8 grid or the asset is missing (the box then draws no face
## rather than crashing).
static func face_texture(row: int, col: int) -> Texture2D:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return null
	var key := "%d_%d" % [row, col]
	if _cache.has(key):
		return _cache[key]
	var path := "%sface_r%d_c%d.png" % [FACES_DIR, row, col]
	# The faces/ assets are gitignored and regenerated per-machine; if the parser
	# hasn't been run they're simply absent. Skip quietly (the box falls back to
	# the speaker's unit-SPR face) instead of letting load() spam the log with a
	# "Failed loading resource" per missing (row,col) — matches ScenarioMapTitle /
	# ScenarioShowGraphic, which guard their parsed-PNG loads the same way.
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex != null:
		_cache[key] = tex
	return tex
