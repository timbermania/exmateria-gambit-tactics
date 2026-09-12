class_name GambitVerdictReader
extends RefCounted

## Decoder for the per-slot GAMBIT VERDICT the kernel writes (ADR-0275 dec. 4).
##
## The kernel stamps `{verdict, condition index, condition opcode, evaluated mask}` for
## pass 1 and `{verdict, condition index, condition opcode, rank reached}` for pass 2 into
## `GM_RESERVED_14` of every gambit slot it walks, and the MEASURED PAYLOAD — the number
## that lost — into `GM_RESERVED_15`. This class turns those two ints back into names.
##
## === THE VOCABULARY IS PARSED, NEVER MIRRORED ==============================================
##
## Every `VERDICT_*` code and every `VERDICT_A_*_SHIFT` is read out of
## [code]combat_common.glslinc[/code] AT RUN TIME. A mirrored enum here would be a second
## source of truth for a table whose whole job is to be read correctly, and it would go stale
## silently — reporting the wrong NAME for the right bits, which is worse than not decoding.
## The eight field WIDTHS are DERIVED from the gaps between successive shifts and checked
## against the documented `4,2,6,4,4,2,6,3`, so a layout that changes shape fails the load
## rather than decoding garbage.
##
## === IT REPORTS ITS OWN CHECKS =============================================================
##
## [member checks] is an ordered list of `{ok, what}` — the load's own assertions, so a
## caller that is a TEST can score them ([GambitVerdictCellsTest] does exactly that, and it is
## the guard on this decoder) and a caller that is an INSTRUMENT can render them. The two
## consumers are that test and the live arm's readout panel (ADR-0275 dec. 13/20); neither
## carries its own copy of the table.
##
## === VERDICT_NONE IS AN ANSWER =============================================================
##
## `NONE == 0` means *this call did not walk this slot* — not "no reason". [method format]
## renders it as `not walked` for that reason. A slot's verdict is also only as fresh as the
## last evaluation that WALKED it: `clear_verdict` is scoped to `max_slot` and the movement
## re-evaluation path passes `current_gambit`, so a unit mid-move deliberately keeps the
## executing slot's verdict, and a panel polling every frame shows exactly that.

const KERNEL_LAYOUT := "res://src/gpu/shaders/combat_common.glslinc"

## The documented widths of the eight verdict fields, in shift order. Checked against the
## widths derived from the parsed shifts — this is the guard on the DECODER.
const FIELD_WIDTHS := [4, 2, 6, 4, 4, 2, 6, 3]

## Decoded key per field, in the same shift order.
const FIELD_KEYS := ["p1", "ci", "op", "mask", "p2", "p2ci", "p2op", "rank"]

const SHIFT_NAMES := [
	"VERDICT_A_P1_SHIFT", "VERDICT_A_P1_CI_SHIFT", "VERDICT_A_P1_OP_SHIFT",
	"VERDICT_A_P1_MASK_SHIFT", "VERDICT_A_P2_SHIFT", "VERDICT_A_P2_CI_SHIFT",
	"VERDICT_A_P2_OP_SHIFT", "VERDICT_A_P2_RANK_SHIFT",
]

## The count the kernel is expected to declare. A fourteenth code is a real event — it must
## move this number and pick up a cell in `GambitVerdictCellsTest`. Thirteen since ADR-0301
## added VERDICT_NO_RETREAT, which is the first code that reports a failure the kernel can
## only find by reading the MAP rather than a status bit, a pool or an ability record.
const EXPECTED_CODE_COUNT := 13

var consts: Dictionary = {}    # every `const int NAME = v;` in the kernel header
var code_of: Dictionary = {}   # "FIRED" -> 1
var name_of: Dictionary = {}   # 1 -> "FIRED"
var fields: Array = []         # [{key, shift, width}, ...] in shift order
var checks: Array = []         # [{ok, what}, ...] — this load's own assertions, in order


## Read `const int NAME = v;` out of the shader header and derive the field table.
## Returns false if the decode cannot be trusted; [member checks] says why in every case.
func load_layout(path: String = KERNEL_LAYOUT) -> bool:
	consts = {}
	code_of = {}
	name_of = {}
	fields = []
	checks = []

	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		_note(false, "read the kernel layout from %s" % path)
		return false
	var rx := RegEx.new()
	rx.compile("(?m)^const int ([A-Za-z_0-9]+)\\s*=\\s*(-?(?:0[xX][0-9A-Fa-f]+|[0-9]+))\\s*;")
	for m in rx.search_all(src):
		var raw: String = m.get_string(2)
		var neg: bool = raw.begins_with("-")
		if neg:
			raw = raw.substr(1)
		var v: int = raw.hex_to_int() if raw.to_lower().begins_with("0x") else raw.to_int()
		consts[m.get_string(1)] = -v if neg else v

	for key in consts.keys():
		var n: String = key
		# `VERDICT_A_*` are the bit shifts, not codes — they share the prefix and nothing else.
		if not n.begins_with("VERDICT_") or n.begins_with("VERDICT_A_"):
			continue
		var short := n.substr("VERDICT_".length())
		code_of[short] = int(consts[n])
		name_of[int(consts[n])] = short
	_note(code_of.size() == EXPECTED_CODE_COUNT,
		"the kernel declares %d verdict codes (found %d: %s)" % [
			EXPECTED_CODE_COUNT, code_of.size(), str(code_of.keys())])

	for s in SHIFT_NAMES:
		if not consts.has(s):
			_note(false, "the kernel declares %s" % s)
			return false
	for i in range(FIELD_KEYS.size()):
		var shift: int = int(consts[SHIFT_NAMES[i]])
		# Bit 31 is documented unused (it keeps int A non-negative host-side), so the last
		# field's width runs to 31 rather than to 32.
		var next_shift: int = 31 if i == FIELD_KEYS.size() - 1 else int(consts[SHIFT_NAMES[i + 1]])
		fields.append({"key": FIELD_KEYS[i], "shift": shift, "width": next_shift - shift})
		_note(next_shift - shift == int(FIELD_WIDTHS[i]),
			"verdict field `%s` is %d bits wide as documented (derived %d)" % [
				FIELD_KEYS[i], int(FIELD_WIDTHS[i]), next_shift - shift])
	return _all_ok()


## Split int A into its eight fields and carry int B through as `payload`.
func decode(word_a: int, word_b: int) -> Dictionary:
	var out: Dictionary = {"payload": word_b}
	for f in fields:
		out[f["key"]] = (word_a >> int(f["shift"])) & ((1 << int(f["width"])) - 1)
	return out


## Decode one `(unit, slot)` out of a `snapshot_battle(b)["gambits"]` slice.
func read_slot(words: PackedInt32Array, unit: int, slot: int) -> Dictionary:
	var base: int = unit * GPUCombatPacker.GAMBITS_PER_UNIT + slot * GPUCombatPacker.GAMBIT_SIZE
	if base + GPUCombatPacker.GambitField.RESERVED_15 >= words.size():
		return decode(0, 0)
	return decode(words[base + GPUCombatPacker.GambitField.RESERVED_14],
		words[base + GPUCombatPacker.GambitField.RESERVED_15])


## The one-line form both consumers print. Fixed-width so a column of slots reads down.
func format(d: Dictionary) -> String:
	return "p1=%-16s ci=%d op=%-2d mask=0b%s  p2=%-16s ci=%d op=%-2d rank=%d  payload=%d" % [
		verdict_name(int(d["p1"])), d["ci"], d["op"],
		String.num_int64(int(d["mask"]), 2).pad_zeros(4),
		verdict_name(int(d["p2"])), d["p2ci"], d["p2op"], d["rank"], d["payload"]]


## NONE is "this call did not reach this slot", and it is never blank.
func verdict_name(code: int) -> String:
	if code == int(code_of.get("NONE", 0)):
		return "NONE(not walked)"
	return name_of.get(code, str(code))


func _note(ok: bool, what: String) -> void:
	checks.append({"ok": ok, "what": what})


func _all_ok() -> bool:
	for c in checks:
		if not c["ok"]:
			return false
	return true
