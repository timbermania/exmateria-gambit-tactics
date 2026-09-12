class_name EventInstructionSet
extends RefCounted

## Catalog loader / descriptor for the event-script ISA (ADR-0059).
##
## Loads the owned `event_instructions.json` and exposes each instruction's
## descriptor BY OPCODE BYTE (equivalently, by [EventInstruction] value, since
## the enum member's underlying int IS the byte): name, params, `verified`, and
## the PSX `handler` cross-ref. This is the interpreter's instruction-set
## definition, so it lives in `src/scenarios/` (not `src/data/`) — a deliberate
## departure from the XDatabase location convention, whose lazy-static-cache
## shape it otherwise follows.
##
## The [ScenarioVM] registrar reads [method unknown_opcodes] to auto-skip the 48
## unnamed opcodes under byte-keyed dispatch.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const CATALOG_PATH := "res://assets/scenarios/event_instructions.json"

# opcode byte (int) -> descriptor Dictionary {opcode, name, params, verified, handler}
static var _by_byte: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var root := JsonAsset.load_dict(CATALOG_PATH)
	var opcodes: Dictionary = root.get("opcodes", {})
	for hex_str in opcodes:
		var op := int(str(hex_str).hex_to_int())
		var entry: Dictionary = opcodes[hex_str]
		_by_byte[op] = {
			"opcode": op,
			"name": entry.get("name", "Unknown"),
			"params": entry.get("params", []),
			"verified": bool(entry.get("verified", false)),
			"handler": entry.get("handler", ""),
		}
	_loaded = true


static func descriptor(opcode: int) -> Dictionary:
	"""Descriptor for an opcode byte / [EventInstruction] value, or `{}` if the
	byte is not in the catalog."""
	_ensure_loaded()
	return _by_byte.get(opcode, {})


static func has(opcode: int) -> bool:
	_ensure_loaded()
	return _by_byte.has(opcode)


static func name_of(opcode: int) -> String:
	"""Display name for the opcode, or "Unknown" if the byte is absent."""
	return descriptor(opcode).get("name", "Unknown")


static func args(inst: Dictionary) -> EventInstructionArgs:
	"""Mint a typed [EventInstructionArgs] reader for a runtime instruction dict,
	pairing its operand VALUES with this catalog's operand widths/modes/types
	(ADR-0059 Phase 2). Replaces `_params_dict` — reads by width/type and
	preserves duplicate operand names distinctly."""
	return EventInstructionArgs.from_instruction(inst, descriptor(int(inst.get("opcode", -1))))


static func all() -> Dictionary:
	"""The full opcode-byte -> descriptor map (all 176 catalog instructions)."""
	_ensure_loaded()
	return _by_byte


static func is_unknown(opcode: int) -> bool:
	"""True for the 48 unnamed catalog opcodes (name == "Unknown") — the set the
	registrar auto-skips so byte-keyed dispatch clean-skips them instead of
	halting on a null handler."""
	return name_of(opcode) == "Unknown"


static func unknown_opcodes() -> Array:
	"""All opcode bytes whose catalog name is "Unknown", ascending."""
	_ensure_loaded()
	var out: Array = []
	for op in _by_byte:
		if _by_byte[op]["name"] == "Unknown":
			out.append(op)
	out.sort()
	return out


static func reload() -> void:
	"""Force reload (for debugging / hot edits)."""
	_loaded = false
	_by_byte = {}
	_ensure_loaded()
