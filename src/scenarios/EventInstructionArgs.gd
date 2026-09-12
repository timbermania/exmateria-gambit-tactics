class_name EventInstructionArgs
extends RefCounted

## Typed operand reader for one decoded event instruction (ADR-0059 Phase 2).
##
## Replaces `_params_dict`, which flattened `inst["params"]` to a bare `{name:int}`
## map — discarding the catalog's `bytes`/`mode`/`type` and, fatally,
## **collapsing duplicate operand names** (the `{6A}` two-`Unknown` case, and
## every one of the 28 dup-name catalog opcodes). This reader is minted by
## [EventInstructionSet] from the catalog descriptor, so the operand's width /
## `mode` / `type` come from the owned catalog (authoritative) while the value
## comes from the runtime instruction. It exposes operands both **by position**
## and **by name**, preserves duplicate names distinctly, and delegates the PSX
## numeric conventions (sign extension by width) to [PsxNum].
##
## Pure and node-free — a decode-layer object like [ScenarioDecode], testable
## without a scene (EventInstructionArgsTest).

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

# Ordered operand records, one per operand in catalog order. Each entry:
#   {"name": String, "value": int, "bytes": int, "mode": String, "type": String}
# `value` is the runtime operand (already little-endian-assembled to its width by
# the disassembler); `bytes`/`mode`/`type` are the catalog descriptor's metadata.
var _ops: Array = []


## Mint a reader from a runtime instruction dict (`{opcode, name, params:[…]}`)
## and its catalog descriptor (`EventInstructionSet.descriptor(opcode)`). Zips
## the runtime operand VALUES against the catalog operand METADATA by position;
## if the catalog lacks a position (unknown opcode), the runtime operand's own
## `bytes`/`type` fill in and `mode` is empty.
static func from_instruction(inst: Dictionary, descriptor: Dictionary) -> EventInstructionArgs:
	var reader := EventInstructionArgs.new()
	reader._build(inst.get("params", []), descriptor.get("params", []))
	return reader


func _build(runtime_params: Array, catalog_params: Array) -> void:
	for i in range(runtime_params.size()):
		var rp: Dictionary = runtime_params[i]
		var cp: Dictionary = catalog_params[i] if i < catalog_params.size() else {}
		_ops.append({
			"name": String(cp.get("name", rp.get("name", ""))),
			"value": int(rp.get("value", 0)),
			"bytes": int(cp.get("bytes", rp.get("bytes", 1))),
			"mode": String(cp.get("mode", "")),
			"type": _string_or_empty(cp.get("type", rp.get("type", ""))),
		})


static func _string_or_empty(v) -> String:
	return String(v) if v != null else ""


# --- Positional access -------------------------------------------------------

## Number of operands.
func size() -> int:
	return _ops.size()


## Raw (unsigned, as-assembled) operand value at position `i`.
func raw_at(i: int) -> int:
	return int(_ops[i]["value"])


## Raw operand value at position `i`, or `default` if `i` is out of range.
## Bounds-safe sibling of [method raw_at] for opcodes read purely positionally
## (e.g. BG Sound, whose {6A}/{6B} operands share a byte layout across differing
## catalog names — see ScenarioVM._op_bg_sound).
func nth(i: int, default: int = 0) -> int:
	return int(_ops[i]["value"]) if i >= 0 and i < _ops.size() else default


## Catalog operand name at position `i`.
func name_at(i: int) -> String:
	return String(_ops[i]["name"])


## Operand width in bytes at position `i` (1 or 2).
func width_at(i: int) -> int:
	return int(_ops[i]["bytes"])


## Operand display mode at position `i` (`"hex"` / `"unsigned"` / `""`).
func mode_at(i: int) -> String:
	return String(_ops[i]["mode"])


## Operand semantic type at position `i` (`"Unit"` / `"Variable"` / … / `""`).
func type_at(i: int) -> String:
	return String(_ops[i]["type"])


## Sign-extend the operand at position `i` by its catalog width (delegates to
## [PsxNum] — `s8` for a byte, `s16` for a half-word).
func signed_at(i: int) -> int:
	return PsxNum.s8(raw_at(i)) if width_at(i) == 1 else PsxNum.s16(raw_at(i))


# --- Named access (by catalog operand name) ----------------------------------

## True if any operand carries `name`.
func has(name: String) -> bool:
	return index_of(name) != -1


## Position of the FIRST operand named `name`, or -1 if absent.
func index_of(name: String) -> int:
	for i in range(_ops.size()):
		if _ops[i]["name"] == name:
			return i
	return -1


## Raw value of the FIRST operand named `name`, or `default` if absent. This is
## the name-keyed read `_params_dict` offered — but only the first match, so a
## dup-name opcode's later operands are reached via [method all] / positional.
func raw(name: String, default: int = 0) -> int:
	var i := index_of(name)
	return raw_at(i) if i != -1 else default


## Sign-extended value of the FIRST operand named `name` (width-driven, via
## [PsxNum]), or `default` if absent.
func signed(name: String, default: int = 0) -> int:
	var i := index_of(name)
	return signed_at(i) if i != -1 else default


## Every raw value carried by an operand named `name`, in catalog order — the
## dup-name preservation `_params_dict` cannot express (it collapses to one).
func all(name: String) -> Array:
	var out: Array = []
	for op in _ops:
		if op["name"] == name:
			out.append(int(op["value"]))
	return out


## Count of operands named `name`.
func count(name: String) -> int:
	return all(name).size()

