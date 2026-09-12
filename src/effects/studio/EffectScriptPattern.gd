extends RefCounted
## PURE script-pattern logic (#273, ADR-0094). The GDScript mirror of
## tools/write_effect_script.py, working on the OBSERVABLE root: `script.json` is
## root-only (parse stops at the first `end`), so the for-each child bytes are not
## on the Godot side at all — but the pattern, texture page and callbacks all live
## in the root, which is enough to detect, classify swappability, and regenerate the
## canonical root op-list for a swap (the score re-flows off the re-detected pattern
## and the byte-exact whole-section rewrite happens in the Python writer at save).
##
## detect        — 3-phase (op41 outer + op31 branch_target_type) / 1-phase (op40,
##                 no op41) / Custom, ports the Lua detect_script_pattern.
## extract_prologue — {texture_page, callbacks:[[slot,id]...]} or {} if not canonical.
## regenerate_root_ops — the canonical root op-dicts (script.json shape) for a pattern.
## classify      — {mode, swappable, read_only_reason}; the strict-canonical + DATA
##                 gate: swappable iff DATA-format AND the root regenerates itself.

const P_3PHASE := "3-phase"
const P_1PHASE := "1-phase"
const P_CUSTOM := "Custom"

const OP_GOTO_YIELD := 0
const OP_END := 4
const OP_SET_TEXTURE_PAGE := 5
const OP_LOAD_CALLBACK := 6
const OP_BRANCH_COUNT_EQ := 22
const OP_BRANCH_ANIM_DONE := 29
const OP_BRANCH_ANIM_DONE_COMPLEX := 30
const OP_BRANCH_TARGET_TYPE := 31
const OP_UPDATE_ALL_PARTICLES := 37
const OP_INIT_PHYSICS_PARAMS := 39
const OP_FOR_EACH := 40
const OP_PROCESS_TIMELINE_FRAME := 41
const OP_CLEAR_TIMELINE_A := 42

# opcode -> (name, size). Only the ops the canonical prologue+root bodies use.
const _META := {
	0: ["goto_yield", 4],
	4: ["end", 2],
	5: ["set_texture_page", 2],
	6: ["load_callback", 4],
	22: ["branch_count_eq", 6],
	29: ["branch_anim_done", 4],
	30: ["branch_anim_done_complex", 4],
	31: ["branch_target_type", 4],
	37: ["update_all_particles", 2],
	39: ["init_physics_params", 2],
	40: ["for_each", 2],
	41: ["process_timeline_frame", 4],
	42: ["clear_timeline_a", 2],
}

# Canonical bodies (after the prologue), as [label, opcode, [args]] where an arg is
# either a literal int or a label String resolved to its absolute-within-section
# offset. Mirrors the real E001 (3-phase root) and E043 (1-phase) layouts.
const _BODY_1PHASE := [
	["btt", OP_BRANCH_TARGET_TYPE, ["end"]],
	["bad", OP_BRANCH_ANIM_DONE, ["wait"]],
	["fe", OP_FOR_EACH, []],
	["up1", OP_UPDATE_ALL_PARTICLES, []],
	["gy1", OP_GOTO_YIELD, ["bad"]],
	["wait", OP_UPDATE_ALL_PARTICLES, []],
	["bce", OP_BRANCH_COUNT_EQ, [0, "end"]],
	["gy2", OP_GOTO_YIELD, ["wait"]],
	["end", OP_END, []],
]

# The 3-phase ROOT only (the for-each child is not in script.json). `child` is the
# offset just past `endroot` — the value process_timeline_frame carries as its arg.
const _BODY_3PHASE_ROOT := [
	["btt", OP_BRANCH_TARGET_TYPE, ["endroot"]],
	["bad", OP_BRANCH_ANIM_DONE_COMPLEX, ["wait"]],
	["ptf", OP_PROCESS_TIMELINE_FRAME, ["child"]],
	["up1", OP_UPDATE_ALL_PARTICLES, []],
	["gy1", OP_GOTO_YIELD, ["bad"]],
	["wait", OP_UPDATE_ALL_PARTICLES, []],
	["bce", OP_BRANCH_COUNT_EQ, [0, "endroot"]],
	["gy2", OP_GOTO_YIELD, ["wait"]],
	["endroot", OP_END, []],
]


static func other(pattern: String) -> String:
	"""The opposite swappable pattern."""
	return P_1PHASE if pattern == P_3PHASE else P_3PHASE


static func detect(script_ops: Array) -> String:
	"""3-phase (op41 + op31) / 1-phase (op40, no op41) / Custom. Ports the Lua
	detect_script_pattern; runs on the root (all script.json holds)."""
	var has_outer := false
	var has_for_each := false
	var has_target_type := false
	for op in script_ops:
		if not (op is Dictionary):
			continue
		match int(op.get("opcode", -1)):
			OP_PROCESS_TIMELINE_FRAME:
				has_outer = true
			OP_FOR_EACH:
				has_for_each = true
			OP_BRANCH_TARGET_TYPE:
				has_target_type = true
	if has_outer and has_target_type:
		return P_3PHASE
	if has_for_each and not has_outer:
		return P_1PHASE
	return P_CUSTOM


static func extract_prologue(script_ops: Array) -> Dictionary:
	"""Read {texture_page, callbacks:[[slot,id]...]} from the prologue, or {} if it is
	not the canonical shape (set_texture_page, 0-4 load_callback, optional
	clear_timeline_a, init_physics_params)."""
	if script_ops.size() < 2:
		return {}
	var first: Dictionary = script_ops[0]
	if int(first.get("opcode", -1)) != OP_SET_TEXTURE_PAGE:
		return {}
	var texture_page := int(first.get("flags", 0))
	var i := 1
	var callbacks: Array = []
	while i < script_ops.size() and int((script_ops[i] as Dictionary).get("opcode", -1)) == OP_LOAD_CALLBACK:
		var cb: Dictionary = script_ops[i]
		callbacks.append([int(cb.get("flags", 0)), int(cb.get("arg1", 0))])
		i += 1
	if i < script_ops.size() and int((script_ops[i] as Dictionary).get("opcode", -1)) == OP_CLEAR_TIMELINE_A:
		i += 1
	if i >= script_ops.size() or int((script_ops[i] as Dictionary).get("opcode", -1)) != OP_INIT_PHYSICS_PARAMS:
		return {}
	return {"texture_page": texture_page, "callbacks": callbacks}


static func regenerate_root_ops(pattern: String, texture_page: int, callbacks: Array) -> Array:
	"""The canonical ROOT op-dicts (script.json shape: offset/opcode/name/flags/size/
	arg1/arg2) for `pattern`, preserving the prologue. For 3-phase this is the root up
	to its `end` (the for-each child is regenerated only in the byte writer);
	process_timeline_frame carries the child offset (just past `endroot`)."""
	assert(pattern == P_1PHASE or pattern == P_3PHASE)
	var ops: Array = []
	var offset := 0

	# Prologue.
	ops.append(_make_op(offset, OP_SET_TEXTURE_PAGE, texture_page))
	offset += _size(OP_SET_TEXTURE_PAGE)
	for cb in callbacks:
		ops.append(_make_op(offset, OP_LOAD_CALLBACK, int(cb[0]), int(cb[1])))
		offset += _size(OP_LOAD_CALLBACK)
	if pattern == P_1PHASE:
		ops.append(_make_op(offset, OP_CLEAR_TIMELINE_A, 0))
		offset += _size(OP_CLEAR_TIMELINE_A)
	ops.append(_make_op(offset, OP_INIT_PHYSICS_PARAMS, 0))
	offset += _size(OP_INIT_PHYSICS_PARAMS)

	var body: Array = _BODY_1PHASE if pattern == P_1PHASE else _BODY_3PHASE_ROOT

	# First pass: assign body-instruction offsets.
	var labels: Dictionary = {}
	var cursor := offset
	for entry in body:
		labels[entry[0]] = cursor
		cursor += _size(int(entry[1]))
	# `child` (3-phase) = the byte after the root's `end`.
	if pattern == P_3PHASE:
		labels["child"] = cursor

	# Second pass: emit body ops with resolved args.
	for entry in body:
		var opcode: int = int(entry[1])
		var args: Array = entry[2]
		var resolved: Array = []
		for a in args:
			resolved.append(int(labels[a]) if a is String else int(a))
		var arg1 = resolved[0] if resolved.size() >= 1 else null
		var arg2 = resolved[1] if resolved.size() >= 2 else null
		ops.append(_make_op(int(labels[entry[0]]), opcode, 0, arg1, arg2))

	return ops


static func classify(script_ops: Array, is_data: bool) -> Dictionary:
	"""{mode, swappable, read_only_reason}. The strict-canonical + DATA gate: swappable
	iff the file is DATA-format AND the root regenerates itself byte-for-byte from its
	own (pattern, prologue) — everything else (CODE, Custom, non-canonical) is read-only."""
	var mode := detect(script_ops)
	if not is_data:
		return {"mode": mode, "swappable": false,
			"read_only_reason": "CODE-format effect (script is MIPS executable, not editable)"}
	if mode == P_CUSTOM:
		return {"mode": mode, "swappable": false,
			"read_only_reason": "Custom script (not a recognized 1-phase / 3-phase pattern)"}
	var pro := extract_prologue(script_ops)
	if pro.is_empty():
		return {"mode": mode, "swappable": false, "read_only_reason": "non-canonical prologue"}
	var regen := regenerate_root_ops(mode, int(pro["texture_page"]), pro["callbacks"])
	if not _roots_equal(regen, script_ops):
		return {"mode": mode, "swappable": false,
			"read_only_reason": "non-canonical %s script body (cannot be swapped losslessly)" % mode}
	return {"mode": mode, "swappable": true, "read_only_reason": ""}


# --- helpers ------------------------------------------------------------------

static func _size(opcode: int) -> int:
	return int((_META[opcode] as Array)[1])


static func _make_op(offset: int, opcode: int, flags: int, arg1 = null, arg2 = null) -> Dictionary:
	var meta: Array = _META[opcode]
	var d := {
		"offset": offset,
		"opcode": opcode,
		"name": String(meta[0]),
		"flags": flags,
		"size": int(meta[1]),
	}
	if arg1 != null:
		d["arg1"] = int(arg1)
	if arg2 != null:
		d["arg2"] = int(arg2)
	return d


static func _roots_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		if int(x.get("opcode", -1)) != int(y.get("opcode", -2)):
			return false
		if int(x.get("flags", 0)) != int(y.get("flags", 0)):
			return false
		if int(x.get("offset", -1)) != int(y.get("offset", -2)):
			return false
		if int(x.get("arg1", -1)) != int(y.get("arg1", -1)):
			return false
		if int(x.get("arg2", -1)) != int(y.get("arg2", -1)):
			return false
	return true
