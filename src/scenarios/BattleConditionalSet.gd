class_name BattleConditionalSet
extends RefCounted

## Catalog loader / descriptor for the BattleConditionals mini-ISA (ADR-0059).
##
## The sibling of [EventInstructionSet] for the second, smaller event-script
## language: the 2-byte requirement opcodes a battle's [ScenarioDirector]
## evaluates (`Variable ==`, `Unit Present`, `HP <=`, `Run Scenario`, …). Loads
## the owned `battle_conditional_opcodes.json` and hands back each opcode's
## descriptor BY OPCODE (equivalently by [BattleConditionalOpcode] value, since the
## enum member's underlying int IS the 2-byte opcode): name, params, `verified`.
##
## Lives in `src/scenarios/` beside the interpreter it defines (the ISA of the
## BattleConditionals language), the same placement rule as [EventInstructionSet] —
## not `src/data/` with the content stores. The runtime **records** (extracted
## per-battle sets) stay in [BattleConditionalDatabase]; this is the *language
## definition* those records are written in.
##
## Mints the SAME [EventInstructionArgs] reader the event ISA uses: a requirement
## record has the identical `{opcode, name, params:[{name,value,bytes,type}]}`
## shape, so the director reads its operands by name/type (`a.raw("Value")`) with
## catalog-driven widths instead of hand-counted positional `params[i].value`.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const CATALOG_PATH := "res://assets/scenarios/battle_conditional_opcodes.json"

# opcode (int) -> descriptor Dictionary {opcode, name, params, verified}
static var _by_op: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var root := JsonAsset.load_dict(CATALOG_PATH)
	var opcodes: Dictionary = root.get("opcodes", {})
	for hex_str in opcodes:
		var op := int(str(hex_str).hex_to_int())
		var entry: Dictionary = opcodes[hex_str]
		_by_op[op] = {
			"opcode": op,
			"name": entry.get("name", "Unknown"),
			"params": entry.get("params", []),
			"verified": bool(entry.get("verified", false)),
		}
	_loaded = true


static func descriptor(opcode: int) -> Dictionary:
	"""Descriptor for a requirement opcode / [BattleConditionalOpcode] value, or `{}`
	if the opcode is not in the catalog."""
	_ensure_loaded()
	return _by_op.get(opcode, {})


static func has(opcode: int) -> bool:
	_ensure_loaded()
	return _by_op.has(opcode)


static func name_of(opcode: int) -> String:
	"""Display name for the opcode, or "Unknown" if absent."""
	return descriptor(opcode).get("name", "Unknown")


static func args(req: Dictionary) -> EventInstructionArgs:
	"""Mint a typed [EventInstructionArgs] reader for a runtime requirement record,
	pairing its operand VALUES with this catalog's operand widths/types (ADR-0059).
	The director then reads by name (`a.raw("Value")`) instead of hand-counting
	`params[i].value`."""
	return EventInstructionArgs.from_instruction(req, descriptor(int(req.get("opcode", -1))))


static func all() -> Dictionary:
	"""The full opcode -> descriptor map (all 22 catalog requirement opcodes)."""
	_ensure_loaded()
	return _by_op


static func reload() -> void:
	"""Force reload (for debugging / hot edits)."""
	_loaded = false
	_by_op = {}
	_ensure_loaded()
