class_name GloveCursorBob
extends RefCounted

## Pure phase machine for the ROM-faithful GLOVE-cursor bob (ADR-0046, §15.20).
##
## FFT's WORLD-map glove (hand) cursor bobs from a `[threshold, signed-offset]`
## pair table, NOT from the battle knife's parallel offset/hold pair.
## `glove_cursor_bob_lookup` (WORLD `FUN_800ec504`) computes `t = timer % period`
## (period = the table's LAST threshold — idle 46, select 38) then returns the
## offset of the FIRST pair whose threshold is strictly greater than `t`. The
## result is added to the cursor **X** — the bob axis is left↔right for the
## glove, not vertical like the knife. Two variants: `glove_idle` at rest,
## `glove_select` while the selection is moving.
##
## These functions are PURE (frame -> offset) and unit-tested with no node in
## the tree. The owning menu holds the integer frame counter and the cached pair
## arrays; this class never holds state.
##
## Consumers (six, all `src/ui3/detail/`): DetailScene, StartActionMenu,
## EquipPickerMenu, JobPickerMenu, LearnAbilityMenu, AbilityPickerMenu.
##
## ⚠️ This is the GLOVE half only. The tile cursor (the on-grid knife) bobs on Y
## from a step/hold table and lives in `Battlefield` as `TileCursorBob` — the two
## share no code, no reader, and since extraction #3 pass 4 no asset.
## CONTEXT.md's rule stands: name the cursor when you say "bob".
##
## Vault: [[Start Action Menu]]

const TABLE_PATH := "res://assets/sprites/glove_cursor.json"


## Load a glove threshold-pair table (`glove_idle` / `glove_select`) from
## glove_cursor.json. Returns an `Array` of `[threshold:int, offset:int]` pairs,
## or an empty Array if the file/key is missing or not a `threshold_pairs` table.
static func load_glove_pairs(key: String = "glove_idle") -> Array:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("GloveCursorBob: table not found at %s" % TABLE_PATH)
		return []
	var text := FileAccess.get_file_as_string(TABLE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(key):
		push_warning("GloveCursorBob: '%s' missing in %s" % [key, TABLE_PATH])
		return []
	var entry: Dictionary = parsed[key]
	if entry.get("format", "") != "threshold_pairs":
		push_warning("GloveCursorBob: '%s' is not a threshold_pairs table" % key)
		return []
	var out: Array = []
	for p in entry.get("pairs", []):
		out.append([int(p[0]), int(p[1])])
	return out


## The bob period of a glove pair table = its LAST threshold (idle 46, select 38).
static func glove_period(pairs: Array) -> int:
	if pairs.is_empty():
		return 1
	return int(pairs[pairs.size() - 1][0])


## The signed bob offset (applied to cursor X) active on monotonic `frame`. Wraps
## `frame` into the period, then returns the offset of the first pair whose threshold
## is strictly greater than the wrapped time (WORLD `FUN_800ec504`). Empty ⇒ 0.
static func glove_offset_for_frame(pairs: Array, frame: int) -> int:
	if pairs.is_empty():
		return 0
	var period := glove_period(pairs)
	if period <= 0:
		return 0
	var t := frame % period
	if t < 0:
		t += period
	for p in pairs:
		if t < int(p[0]):
			return int(p[1])
	return int(pairs[pairs.size() - 1][1])
