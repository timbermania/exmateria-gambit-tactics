class_name SequenceChannel
extends RefCounted
## Write-side channel encoder for animation SEQUENCE opcode parameters (#275).
## An animation is a plain JSON-shaped Dictionary at `data.animations[index]`
## (no wrapper class, matching `parse_animations_section()`'s output shape
## verbatim: `godot-learning/tools/parse_effect.py`), holding an ordered
## `opcodes` array of `{type, ...params}` dicts.
##
## `apply_raw` writes one raw parameter on the live opcode dict and returns the
## snapshot the choke point records for undo.
##
## Sequences are BAKED, not read-live: `ParticleAnimator._bake_animations` runs
## once at subsystem setup and flattens each sequence into per-tick frame data,
## so an edit only reaches the preview after a re-fold — hence
## `invalidates_sim = true` (the opposite of FramesetChannel's read-live frames).
##
## v1 SCOPE (locked with the user 2026-08-18, see #275): IN-PLACE PARAMETER
## EDITS ONLY. No insert/delete/reorder of opcodes, no changing an opcode's
## TYPE, no adding/removing sequences — this channel has no `insert_event`/
## `delete_event`/`snapshot`/`restore` verbs by design. Opcodes are
## variable-size (FRAME 3 B, LOOP 1 B, SET_OFFSET 5 B, ADD_OFFSET 3 B), so any
## structural change is a section regeneration + offset-table rewrite + header
## pointer fixup, deferred to a follow-on. Every v1 edit is a scalar byte write
## the choke point's default undo path replays.
## Channels supply encoders, not mutation logic; the single choke point is
## `EffectEditSession.apply_edit` (#255).

# Opcode type -> the parameter names it owns. A field is only writable on the
# opcode type that actually encodes it, so a mis-addressed edit is refused
# rather than silently inventing a key on the wrong opcode's dict.
const _FIELDS_BY_TYPE := {
	"FRAME": ["frameset", "duration", "depth_mode"],
	"SET_OFFSET": ["x", "y"],
	"ADD_OFFSET": ["dx", "dy"],
	"LOOP": [],
}


## Write one raw parameter for the opcode named by `field_ref` and return the
## snapshot the choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var op: Dictionary = _resolve_opcode(data, field_ref)
	if op.is_empty():
		push_error("SequenceChannel: no opcode for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	var op_type: String = str(op.get("type", ""))

	if not _FIELDS_BY_TYPE.has(op_type):
		push_error("SequenceChannel: unknown opcode type '%s'" % op_type)
		return {}
	if not (field in _FIELDS_BY_TYPE[op_type]):
		push_error("SequenceChannel: '%s' is not a parameter of a %s opcode" % [field, op_type])
		return {}

	var before = op.get(field)
	op[field] = int(new_raw)
	return {
		"before_raw": before,
		"after_raw": int(new_raw),
		"invalidates_sim": true,
		"faithful": _faithful_verdict(field, int(new_raw)),
	}


## Non-destructive Faithful advisory (#255): Free always accepts the write, but
## a parameter only lowers to E###.BIN if it fits its on-disk encoding width.
## `frameset` IS the opcode byte itself and must stay <= 0x7F to remain a FRAME
## (0x81/0x82/0x83 are the other opcodes) — the tightest bound here, and the one
## place a parameter edit could otherwise change an opcode's TYPE.
static func _faithful_verdict(field: String, raw: int) -> Dictionary:
	var bounds: Dictionary = {
		"frameset": [0, 127],
		"duration": [0, 255],
		"depth_mode": [0, 255],
		"x": [-32768, 32767], "y": [-32768, 32767],
		"dx": [-128, 127], "dy": [-128, 127],
	}
	if not bounds.has(field):
		return {"ok": true, "reason": ""}
	var lo: int = bounds[field][0]
	var hi: int = bounds[field][1]
	if raw < lo or raw > hi:
		if field == "frameset":
			return {"ok": false, "reason":
				"frameset = %d is outside 0..127 — the FRAME opcode byte IS the frameset index, so a larger value would re-encode the opcode as LOOP/SET_OFFSET/ADD_OFFSET (Free-only)" % raw}
		return {"ok": false, "reason":
			"%s = %d is outside the %d..%d encoding (Free-only)" % [field, raw, lo, hi]}
	return {"ok": true, "reason": ""}


static func _resolve_opcode(data, field_ref: Dictionary) -> Dictionary:
	if data == null or not (data.animations is Array):
		return {}
	var anim_idx: int = int(field_ref.get("animation_index", -1))
	if anim_idx < 0 or anim_idx >= data.animations.size():
		return {}
	var anim = data.animations[anim_idx]
	if not (anim is Dictionary):
		return {}
	var opcodes = anim.get("opcodes", [])
	if not (opcodes is Array):
		return {}
	var op_idx: int = int(field_ref.get("opcode_index", -1))
	if op_idx < 0 or op_idx >= opcodes.size():
		return {}
	var op = opcodes[op_idx]
	return op if op is Dictionary else {}
