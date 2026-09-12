extends RefCounted

## Pure phase machine for the ROM-faithful TILE-cursor bob (ADR-0046).
##
## FFT plays a cursor's at-rest oscillation from a step table the ROM ships, not
## from a math curve. The tile cursor (the on-grid knife) uses a pair of parallel
## 8-entry tables: an OFFSET table `{0,1,2,3,5,3,2,1}` (vertical offset in FFT
## cursor-Y units, where 1 tile = 28) and a HOLD table `{16,8,2,2,6,4,4,10}`
## (frames to dwell on each step). A single phase index (0..7) walks the steps;
## a frame counter that advances at `VBLANK_HZ / vblanks_per_tick` selects it.
## The motion is one-sided from the resting pose — 16 frames at offset 0, a
## single excursion to 5, return — not a centered sine.
##
## These functions are PURE (frame -> phase index -> offset) and unit-tested
## against literal ROM ground truth (TileCursorBobTest), with no node in the
## tree. That is the whole reason this is a `RefCounted` beside `TileCursor`
## rather than four private methods inside it: the bob is a ROM-faithfulness
## claim, and a claim needs an oracle that can be run without a scene. The
## owning node (TileCursor) holds the integer frame counter and the cached
## `offsets`/`holds` arrays; this class never holds state.
##
## ⚠️ This is the KNIFE half only. The glove (menu/world hand) cursor bobs on X
## from a different encoding entirely and lives in `UI` as `GloveCursorBob` —
## the two share no code, no reader, and since extraction #3 pass 4 no asset.
## CONTEXT.md's rule stands: name the cursor when you say "bob".

const TABLE_PATH := "res://addons/exmateria_battlefield/cursor/tile_knife.json"


## Load a step-table entry (`tile_knife`) from tile_knife.json. Returns a
## Dictionary `{offsets, holds, tile_unit}` with Array/int values, or an empty
## Dictionary if the file or key is missing / malformed. Callers cache the
## result; this touches the filesystem.
static func load_step_table(key: String = "tile_knife") -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("TileCursorBob: table not found at %s" % TABLE_PATH)
		return {}
	var text := FileAccess.get_file_as_string(TABLE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(key):
		push_warning("TileCursorBob: '%s' missing in %s" % [key, TABLE_PATH])
		return {}
	var entry: Dictionary = parsed[key]
	if entry.get("format", "") != "step_table":
		push_warning("TileCursorBob: '%s' is not a step_table" % key)
		return {}
	# JSON numbers parse as floats; coerce to clean int arrays for consumers.
	return {
		"offsets": _to_int_array(entry.get("offsets", [])),
		"holds": _to_int_array(entry.get("holds", [])),
		"tile_unit": int(entry.get("tile_unit", 28)),
	}


static func _to_int_array(arr: Array) -> Array[int]:
	var out: Array[int] = []
	for v in arr:
		out.append(int(v))
	return out


## Total frames in one full bob cycle = sum of the hold counts (52 for the knife).
static func cycle_length(holds: Array) -> int:
	var total := 0
	for h in holds:
		total += int(h)
	return total


## Phase index (0..N-1) active on `frame`. The frame counter is monotonic; this
## wraps it into one cycle (negative frames wrap too) and walks the cumulative
## hold counts to find which step owns it. A frame on a step boundary belongs to
## the LATER step (frame == sum(holds[0..i]) starts step i+1).
static func phase_for_frame(holds: Array, frame: int) -> int:
	var cycle := cycle_length(holds)
	if cycle <= 0:
		return 0
	var f := frame % cycle
	if f < 0:
		f += cycle
	var acc := 0
	for i in holds.size():
		acc += int(holds[i])
		if f < acc:
			return i
	return holds.size() - 1  # unreachable when cycle == sum(holds)


## Vertical offset (FFT cursor-Y units, one-sided from rest) active on `frame`.
static func offset_for_frame(offsets: Array, holds: Array, frame: int) -> int:
	if offsets.is_empty():
		return 0
	return int(offsets[phase_for_frame(holds, frame)])
