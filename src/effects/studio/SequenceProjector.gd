extends RefCounted
## The **animation** target-kind projector (ADR-0073, #275): the sequence view — a
## two-row summary header above ONE COLLAPSIBLE SECTION PER OPCODE, titled exactly like
## effect-editor/ui/sequences_tab.lua's instruction list ("1: FRAME fs=3 dur=8 depth=1"),
## carrying that opcode's PICTURE beside the title and its editable fields inside. So the
## whole stream can be retimed without drilling in, and the collapsed sections read top to
## bottom as the sequence's film strip (#247, ADR-0100).
##
## There WAS a second kind here, `sequence_op` — one opcode focused, showing just its own
## parameter group and a link back. ADR-0100 made the sequence view render exactly that
## section in place, so drilling in showed strictly less for the price of the whole strip;
## no UI has produced one since, and ADR-0102 removed the last reason to want it. Deleted
## 2026-08-19. If a future feature needs to address one instruction, mint the kind again —
## do not re-add an opcode LINK ROW to justify it (those rows held the inspector at 1068px
## of a 1241px body, which is what cost the sequence player its column the first time).
##
## v1 SCOPE (locked with the user 2026-08-18, see #275): opcode PARAMETERS only.
## The opcode stream's shape — how many opcodes, in what order, of what type — is
## structural (opcodes are variable-size) and is display-only here.
##
## Sequences are plain JSON-shaped Dictionaries (`parse_animations_section()`'s shape
## verbatim) — no wrapper class. No `class_name` (ADR-0004); target loaded at call
## time to avoid a parse-time cycle, mirroring the other target-kind projectors.

## The six RE-documented depth-sort modes, named as in the Lua sequences tab's
## DEPTH_MODE_OPTIONS (the mode drives the particle's GPU sort key).
const _DEPTH_MODES := [
	"0: Standard (Z>>2)",
	"1: Forward 8",
	"2: Fixed Front (8)",
	"3: Fixed Back (0x17E)",
	"4: Fixed 16 (0x10)",
	"5: Forward 16",
]


static func header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	match Target.kind(target):
		"animation":
			return _animation_header(target, effect_data, Target)
	return []


static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	match Target.kind(target):
		"animation":
			return _animation_sections(target, effect_data)
	return []


static func _animation_header(target: Dictionary, effect_data, Target) -> Array:
	var anim_idx := int(target.get("ref", {}).get("index", -1))
	var group := int(target.get("ref", {}).get("group", 0))
	var opcodes := _resolve_opcodes(effect_data, anim_idx)
	if opcodes.is_empty():
		return []
	var rows: Array = [
		{"label": "Sequence", "value": "sequence %d (%d opcodes)" % [anim_idx, opcodes.size()]},
		# "%d ticks", not "%d ticks before the terminator". The sentence was the widest cell
		# in this view's header grid (223px of 581), and the header is the widest thing in
		# the view — so it set the declared `content_width()` the ADR-0102 focus column is
		# claimed from, and the prose came straight out of the frame parameters beside it.
		# The terminator is what a sequence's duration is measured to by definition; it is
		# in the tooltip for whoever has not met one yet.
		{"label": "Plays for", "value": "%d ticks" % _total_duration(opcodes),
			"tooltip": "Total dwell of every opcode, up to the terminator that ends the stream."},
	]
	# The lens this sequence is being READ through, stated plainly — a FRAME opcode's
	# frameset field is relative to it, so the same stream shows different sprites at a
	# different group. Named only when it shifts something (group 0 is the whole story for
	# 383 of 401 effects); see InspectionTarget.animation.
	if group != 0:
		rows.append({"label": "Frameset group", "value":
			"group %d (FRAME framesets shift by %d — this is how the emitter that brought "
			% [group, effect_data.frameset_group_offset(group)]
			+ "you here plays it)"})
	# NO per-opcode rows here. They used to live in this header — one LINK row each,
	# carrying the opcode's picture — and they were a SECOND copy of the opcode list
	# that the sections below already render editably. Deleting them is what frees the
	# header (see ADR-0100): the picture and the label both moved onto the opcode's own
	# collapsible section, and the header shrank back to its two summary rows, which is
	# what lets the player dock beside the inspector instead of under it.
	return rows


static func _animation_sections(target: Dictionary, effect_data) -> Array:
	var anim_idx := int(target.get("ref", {}).get("index", -1))
	var group := int(target.get("ref", {}).get("group", 0))
	var opcodes := _resolve_opcodes(effect_data, anim_idx)
	var out: Array = []
	for i in range(opcodes.size()):
		# COLLAPSED by default: with one section per opcode and the picture riding the
		# title, the shut sections stack into a vertical film strip you can read at a
		# glance, and opening one is the act of editing it. The inspector remembers the
		# toggle for the session, so an edit's live reproject never snaps them back.
		out.append(_opcode_section(anim_idx, i, opcodes[i], group, effect_data, true))
	return out
## One opcode's editable parameter group. The section title is the FULL instruction
## label (`opcode_label`) — the same string the deleted header link rows carried, so
## nothing they showed is lost. The opcode's type is never editable in v1.
##
## `group` is the frameset lens the sequence is being read through (see
## InspectionTarget.animation): it never changes a STORED value — the Frameset editor
## still shows and writes the RELATIVE byte the file holds — it only decides where the
## drill-down link points. It also rides the `thumb` request, because a FRAME opcode's
## picture is the sprite the group resolves to.
static func _opcode_section(anim_idx: int, op_idx: int, op: Dictionary,
		group: int = 0, effect_data = null, collapsed: bool = false) -> Dictionary:
	var op_type := str(op.get("type", ""))
	var f := func(field: String) -> Dictionary:
		return {"channel": "sequence", "animation_index": anim_idx,
			"opcode_index": op_idx, "field": field}

	var fields: Array = []
	match op_type:
		"FRAME":
			var fs_row := {"name": "Frameset", "shape": "edit", "editor": "int", "type": "u8",
					"min": 0, "max": 127, "value": int(op.get("frameset", 0)),
					"field_ref": f.call("frameset")}
			_attach_frameset_follow(fs_row, int(op.get("frameset", 0)), group, effect_data)
			fields = [
				fs_row,
				{"name": "Duration", "shape": "edit", "editor": "int", "type": "u8",
					"min": 0, "max": 255, "value": int(op.get("duration", 0)),
					"field_ref": f.call("duration")},
				{"name": "Depth mode", "shape": "edit", "editor": "choice",
					"choices": _DEPTH_MODES, "value": int(op.get("depth_mode", 0)),
					"field_ref": f.call("depth_mode")},
			]
		"SET_OFFSET":
			fields = [
				{"name": "Offset X", "shape": "edit", "editor": "int", "type": "s16",
					"min": -32768, "max": 32767, "value": int(op.get("x", 0)),
					"field_ref": f.call("x")},
				{"name": "Offset Y", "shape": "edit", "editor": "int", "type": "s16",
					"min": -32768, "max": 32767, "value": int(op.get("y", 0)),
					"field_ref": f.call("y")},
			]
		"ADD_OFFSET":
			fields = [
				{"name": "Delta X", "shape": "edit", "editor": "int", "type": "s8",
					"min": -128, "max": 127, "value": int(op.get("dx", 0)),
					"field_ref": f.call("dx")},
				{"name": "Delta Y", "shape": "edit", "editor": "int", "type": "s8",
					"min": -128, "max": 127, "value": int(op.get("dy", 0)),
					"field_ref": f.call("dy")},
			]
		_:
			# LOOP (and any future parameterless opcode): listed, never editable.
			# "none", not "none — restarts the sequence from the beginning": at 385px this
			# was the single widest cell in the whole view (its grid measured 639 against
			# the FRAME rows' 466), for a sentence that repeats what LOOP means. Tooltip.
			fields = [{"name": "Parameters", "shape": "const", "value": "none",
				"tooltip": "LOOP takes no parameters — it restarts the sequence from the beginning."}]
	return {
		"title": opcode_label(op_idx, op),
		"fields": fields,
		# `thumb` asks the host for this row's PICTURE beside the section title (#247):
		# the animation at the row's `pos_tick` — the end of this opcode's duration, or,
		# for the first and last rows, the animation's own first and last frame
		# (`SequenceTimeline`'s 2026-08-20 model). It is a REQUEST, not the image — this
		# projector is pure and static, and resolving a thumbnail needs the texture, the
		# framesets and the sequence's shared bounds. The host supplies a provider; a host
		# without one renders the section exactly as before.
		"thumb": {"animation_index": anim_idx, "opcode_index": op_idx, "group": group},
		# The section's SESSION-FOLD identity. Deliberately not the title: an edit to
		# `duration` rewrites the title, and a key that moved with the value would shut
		# the section the author is typing into.
		"fold_id": "seq:%d:%d" % [anim_idx, op_idx],
		"collapsed": collapsed,
	}


## The Lua sequences tab's instruction-list label, verbatim in form so the two
## editors read the same (effect-editor/ui/sequences_tab.lua, `M.draw`).
static func opcode_label(index: int, op: Dictionary) -> String:
	match str(op.get("type", "")):
		"FRAME":
			return "%d: FRAME fs=%d dur=%d depth=%d" % [index,
				int(op.get("frameset", 0)), int(op.get("duration", 0)), int(op.get("depth_mode", 0))]
		"SET_OFFSET":
			return "%d: SET_OFFSET x=%d y=%d" % [index, int(op.get("x", 0)), int(op.get("y", 0))]
		"ADD_OFFSET":
			return "%d: ADD_OFFSET dx=%d dy=%d" % [index, int(op.get("dx", 0)), int(op.get("dy", 0))]
		"LOOP":
			return "%d: LOOP" % index
	return "%d: %s" % [index, str(op.get("type", "?"))]


## Sum of FRAME durations up to the terminator — mirrors
## `parse_effect.calculate_animation_duration` / EffectData.get_animation_duration.
static func _total_duration(opcodes: Array) -> int:
	var total := 0
	for op in opcodes:
		if not (op is Dictionary):
			continue
		match str(op.get("type", "")):
			"FRAME":
				total += int(op.get("duration", 0))
			"LOOP":
				return total
	return total


static func _resolve_opcodes(effect_data, anim_idx: int) -> Array:
	if effect_data == null or not (effect_data.animations is Array):
		return []
	if anim_idx < 0 or anim_idx >= effect_data.animations.size():
		return []
	var anim = effect_data.animations[anim_idx]
	if not (anim is Dictionary):
		return []
	var opcodes = anim.get("opcodes", [])
	return opcodes if opcodes is Array else []


static func _resolve_opcode(effect_data, anim_idx: int, op_idx: int) -> Dictionary:
	var opcodes := _resolve_opcodes(effect_data, anim_idx)
	if op_idx < 0 or op_idx >= opcodes.size():
		return {}
	var op = opcodes[op_idx]
	return op if op is Dictionary else {}


## Which frameset a FRAME opcode's stored (RELATIVE) value actually reaches, read through
## frameset `group` — or **-1** when there is no answer (no effect data, or an absolute
## index off the end of the flat array).
##
## Public and shared on purpose. The follow button below and the unified animation screen's
## pinned block (ADR-0102) both need this number, and they must never be able to disagree
## about it: the block would then edit a different frameset from the one the link beside it
## opens, which is the exact failure the group lens was put on the ref to prevent
## (ADR-0073 dec. 8). One derivation, and it delegates the cumulative sum to
## `EffectData.frameset_group_offset`, whose docstring asks callers not to copy it.
static func absolute_frameset(relative: int, group: int, effect_data) -> int:
	# The guard PROBES before it reads. `effect_data.framesets` is itself the expression
	# that throws on an object without that property, so the old guard could not fire for
	# the case it was written for: the error aborted this function, which returned the
	# `int` default 0, and 0 sails straight through every `absolute < 0` check downstream —
	# the docstring's promised degrade turned into a follow row built on a garbage index.
	# `in` asks the object without reading it; `has_method` covers the call below. #466.
	if effect_data == null:
		return -1
	if not ("framesets" in effect_data) or not (effect_data.framesets is Array):
		return -1
	if not effect_data.has_method("frameset_group_offset"):
		return -1
	var absolute: int = relative + int(effect_data.frameset_group_offset(group))
	if absolute < 0 or absolute >= effect_data.framesets.size():
		return -1
	return absolute


## The last rung of the drill-down chain: a FRAME opcode's frameset field → the frameset
## it actually shows (ADR-0073 dec. 8).
##
## The stored field is RELATIVE to the frameset group, so the absolute index is
## `frameset + EffectData.frameset_group_offset(group)` — the same derivation the sim does
## (ActiveEmitter/ParticleSubsystem, now all one function). This is why the opcode alone has
## no correct link target and the group has to travel on the ref: at group 0 this opcode
## reaches one sprite, at group 1 a different one, and only the emitter knows which.
##
## Degrades rather than lying. With no effect_data (a bare projector call) or an absolute
## index off the end of the flat framesets array, the follow is DISABLED — the inspector
## then renders no button and the spinbox stays live so the index can be fixed in place.
static func _attach_frameset_follow(row: Dictionary, relative: int, group: int,
		effect_data) -> void:
	var absolute: int = absolute_frameset(relative, group, effect_data)
	if absolute < 0:
		row["follow"] = {"disabled": true}
		return
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	var shift: int = effect_data.frameset_group_offset(group)
	# The label names the ABSOLUTE index because that is where the button goes; the editor
	# beside it keeps showing the relative byte, so the shift is stated whenever it is
	# non-zero rather than looking like the editor and the link disagree.
	row["follow"] = {
		"label": "frameset %d" % absolute,
		"target": Target.frameset(absolute),
		"tooltip": ("Frameset %d — this opcode's stored value %d shifted by group %d's "
			+ "offset %d.") % [absolute, relative, group, shift] if shift != 0
			else "Frameset %d — group 0 applies no shift." % absolute,
	}
