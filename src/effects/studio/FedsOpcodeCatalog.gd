extends RefCounted
## THE INSERT MENU IS THE CORPUS (ADR-0085 amendment 2026-08-18b §7).
##
## Structural authoring has to answer "which opcode?" and there are two bad answers.
## The decoder's full table offers opcodes no FFT sound contains — a way to end up
## debugging the decoder instead of the sound. A hand-curated short list is canon
## that rots. So the menu is the 57 opcodes that actually occur across the 2008 real
## tracks, ordered by TRACK COVERAGE, from the measured, regenerable
## `assets/feds_opcode_coverage.json`.
##
## Two exclusions, both from the slice-1 boundary (§3):
##   • the TIME-CARRYING pair (0x80 Rest / 0x81 Fermata) — slice 1 is the edits that
##     cannot move the clock, so offering these would raise the very question the
##     slice exists to avoid (what does "delete" mean for something that takes time).
##   • the FLOW opcodes — inserted anywhere but their proper place they make the
##     rest of the track unreachable or re-bracket it. `0x90 EndBar` is the single
##     exception, offered ONLY at a stub's phantom boundary, where it is the natural
##     verb the NoEnd phantom has been advertising: one byte, no earlier offset
##     moves, and the borrowing visibly stops.
##
## A new opcode starts at the CORPUS MODE for each of its parameters — the value FFT
## itself most often writes — so an inserted `Instrument` is a real instrument and an
## inserted `ADSR_Attack` does something. Same source as the inspector's empirical
## range (`feds_param_stats.json`), no hand-authored canon to rot.
##
## Which of the 57 can be emitted at all is decided HERE, not in the JSON: only the
## decoder knows an opcode's param count, and a byte stream written from any other
## count would not decode back to the same event.
##
## No class_name (ADR-0004); load()ed by path.

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const ParamStats = preload("res://src/effects/studio/FedsParamStats.gd")

const _PATH := "res://assets/feds_opcode_coverage.json"

## The two opcodes that advance the tick — everything else in the language is
## zero-tick (FedsPairModel._project_events), which is what makes slice 1 exactly
## enumerable.
const TIME_CARRYING := [0x80, 0x81]

## Flow / structure: EndBar, Loop-return, Repeat, Coda, and the loop marker.
const FLOW := [0x90, 0x91, 0x98, 0x99, 0x9A]

const END_BAR := 0x90

static var _rows: Array = []
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(_PATH):
		push_warning("FedsOpcodeCatalog: %s absent — the insert menu has no corpus" % _PATH)
		return
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for row in json.data.get("opcodes", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			_rows.append({
				"opcode": int(str(row.get("opcode", "0x00")).hex_to_int()),
				"tracks": int(row.get("tracks", 0)),
				"occurrences": int(row.get("occurrences", 0)),
			})
	f.close()


## Every opcode the corpus contains, most-covered first: [{opcode, tracks, occurrences}].
static func coverage() -> Array:
	_ensure()
	return _rows.duplicate(true)


## The offerable menu, most-covered first. `at_phantom_boundary` admits `EndBar` —
## the only flow opcode with a place it can honestly go.
## Each entry: {opcode, label, tracks, occurrences, params: PackedByteArray, bytes: PackedByteArray}
static func insert_menu(at_phantom_boundary: bool = false) -> Array:
	var out: Array = []
	for row in coverage():
		var op: int = int(row["opcode"])
		if not can_insert(op, at_phantom_boundary):
			continue
		var params := default_params(op)
		out.append({
			"opcode": op,
			"label": label_of(op),
			"tracks": int(row["tracks"]),
			"occurrences": int(row["occurrences"]),
			"params": params,
			"bytes": encode(op, params),
		})
	return out


## Is `op` offerable? Zero-tick, non-flow, and an opcode we have actually named —
## anything else could not be written back as bytes that decode to what was asked for.
##
## This asked `param_count_of(op) < 0` until #616. That was the parser's question,
## and once the size table covered all 128 opcodes it answered "yes" for every byte
## in the space, including 56 we do not implement.
static func can_insert(op: int, at_phantom_boundary: bool = false) -> bool:
	if not SMD.is_named_opcode(op):
		return false
	if op in TIME_CARRYING:
		return false
	if op in FLOW:
		return op == END_BAR and at_phantom_boundary
	return true


static func label_of(op: int) -> String:
	if SMD.is_named_opcode(op):
		return SMD.OPCODE_INFO[op][0]
	return "Unknown_%02X" % op


## The corpus MODE for each of `op`'s parameters — what FFT most often writes there.
## A param the corpus never uses falls back to 0. `0xD3 PitchBend_Add_16bit` folds
## its two bytes into one signed 16-bit sample at param index 0, so it is unfolded
## back into a high/low byte pair here.
static func default_params(op: int) -> PackedByteArray:
	var n: int = SMD.param_count_of(op)
	var out := PackedByteArray()
	if n == 0:
		return out
	var wide: Dictionary = ParamStats.of(op, 0)
	if n == 2 and int(wide.get("bits", 8)) == 16:
		var v: int = int(wide.get("mode", 0)) & 0xFFFF
		out.append((v >> 8) & 0xFF)
		out.append(v & 0xFF)
		return out
	for i in range(n):
		var st: Dictionary = ParamStats.of(op, i)
		out.append(int(st.get("mode", 0)) & 0xFF)
	return out


## The bytes an inserted opcode writes: the opcode, then its params. Params shorter
## than the decoder's count are zero-filled, longer ones truncated, so the written
## stream always decodes back to exactly this event.
static func encode(op: int, params: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	if op < 0x80 or op > 0xFF:
		return PackedByteArray()
	var n: int = SMD.param_count_of(op)
	var out := PackedByteArray()
	out.append(op & 0xFF)
	for i in range(n):
		out.append(params[i] & 0xFF if i < params.size() else 0)
	return out
