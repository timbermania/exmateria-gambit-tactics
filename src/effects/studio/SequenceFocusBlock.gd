extends RefCounted
## The **unified animation screen**'s focus block (ADR-0102): one section at the TOP of an
## `animation` target's section list carrying the frameset the SELECTED opcode shows, with
## one fold per member frame — the FIRST of them open, the rest shut.
##
## COMPOSITION, NOT A FOURTH PROJECTOR. The registry (ADR-0073) exists so a field is
## declared once; this calls `FramesetProjector.sections()` and grafts the rows it returns
## rather than restating them. That is safe because a frame row's `field_ref` is
## `{channel:"frameset", frameset_index, frame_index, field}` — absolute and
## self-contained — and `EffectEditSession.apply_edit` routes on `field_ref.channel`
## alone, never on the open target. A grafted row therefore edits the right frame from
## anywhere, and stays correct when FramesetProjector changes.
##
## WHY ONE ROOT BLOCK AND NOT A FOLD PER OPCODE. Both placements were built against the
## real inspector and timed on E019 sequence 0 (36 opcodes). One root block that follows
## the selection costs **400-428 ms** to build against the shipping view's **343 ms**; a
## fold per opcode costs **1867 ms**, and neither trimming the field set (963 ms) nor
## building fold bodies lazily (558 ms floor) rescues it — the cost is ~4 ms per fold
## HEADER, 52 of them, before a single row exists. Same authoring reach, 1/20th the price.
## `content_width()` measures 677 in every variant, so the graft costs the sequence player
## beside it exactly zero width.
##
## THE BLOCK IS ALWAYS EMITTED, even for an opcode that shows no frameset (SET_OFFSET,
## ADD_OFFSET, LOOP) — but for one of those it is now a TITLE AND NOTHING ELSE. That is the
## answer to "should there even be a frameset section when SET_OFFSET and LOOP have no
## frameset parameter": there is no section any more, only the focus panel's own reserved
## slot, and for a spriteless opcode the panel states which instruction is parked there and
## stops. It used to spend a two-column row on it ("Frameset │ LOOP shows no sprite — click
## a FRAME cell in the strip"), where the label column was noise and the sentence was
## instructions for a strip the author was already clicking.
##
## The slot stays RESERVED rather than collapsing, and that is the load-bearing half: the
## panel lives beside the film strip, so a panel that vanished would hand its width back
## and re-flow the strip — the exact movement it exists to stop, just on a different click.
## (The original reason — that the in-place `rebuild_section` retarget could only address a
## section already in the list — expired with the list, and the function with it.)
##
## UV ROWS ARE READ-ONLY HERE (ADR-0099). A UV rect is a shared sheet region: E019's 184
## frames sit on 14 distinct rects and the biggest is shared by 30 frames. The safety
## against editing thirty frames believing you edited one is the region SCOPE control, and
## that control lives under the frameset canvas — which cannot be on screen here, because
## the inspector row's right column is ONE slot and the sequence player is in it. So the
## block states the fan-out and hands you to the frame's own screen. Everything else on a
## frame is strictly per-frame with no fan-out — palette, blend, semi-trans, 8bpp,
## vertices — and is safe to edit inline, so all of it is grafted verbatim.
##
## THERE IS NO PIN. The block shipped with a "📌 Pin to this frameset" toggle that froze it
## on one opcode while the playhead ran. It was in the mockup, never in the approved build
## list, and the author cut it on first real use: its row cost two lines at the very TOP of
## a block that only has a few, and the compare-against-a-moving-playhead case it existed
## for never came up. Cutting it took `PIN_ACTION`, the `seq_focus_pin` branch of
## `_run_action`, `_set_sequence_focus_pin`, `_seq_focus_pin`, `_sequence_bound_anim` (page
## state that existed ONLY to drop the pin on a re-bind) and the `pinned` parameter with it.
##
## Pure statics, no nodes, no page state: the whole block is a function of
## `(target, effect_data, op_index)`, which is what makes the group-lens mutation
## test possible without a scene. No `class_name` (ADR-0004).

const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")
const FramesetProjector = preload("res://src/effects/studio/FramesetProjector.gd")
const SequenceProjector = preload("res://src/effects/studio/SequenceProjector.gd")
const CellColour = preload("res://src/effects/studio/SequenceCellColour.gd")

## The section's stable fold identity — the key the focus inspector remembers the author's
## open/shut choice under, and the handle every test names the block by. Deliberately
## constant: an id carrying the frameset index would make every retarget a NEW section,
## and the author's fold state would reset on each click through the strip.
const FOLD_ID := "seq-focus"

## The block for `op_index` of the sequence `target` addresses, ready to prepend to that
## target's sections.
##
## `provenance` is the colour-provenance rung the film strip beside this block is tinted
## by (ADR-0103 dec. 4/5). It used to ride the TITLE on the argument that "a title suffix
## costs 0px"; it rides the header's TOOLTIP since 2026-08-20, because that argument was
## about height and the cost was width. See `section` for the whole of it. It arrives as an
## argument rather than being resolved here because
## the ladder reads `_nav` — page state, which this file has none of and must keep none
## of, since being a pure function of `(target, effect_data, op_index)` is what makes the
## group-lens mutation test possible without a scene. Empty ⇒ no suffix.
static func section(target: Dictionary, effect_data, score: Dictionary,
		op_index: int, provenance: Dictionary = {}) -> Dictionary:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	if Target.kind(target) != "animation":
		return {}
	var ref: Dictionary = Target.ref(target)
	var anim_idx := int(ref.get("index", -1))
	var group := int(ref.get("group", 0))
	var op := _opcode(effect_data, anim_idx, op_index)
	# The GROUP LENS, applied here and nowhere else in this file. `absolute_frameset` is
	# SequenceProjector's single derivation, shared with the follow button beside the
	# opcode's own Frameset editor — so the block edits exactly the frameset that button
	# opens. Two copies of this sum would let them drift, and a block silently editing a
	# different frameset from the one it names is the failure the lens rides the ref to
	# prevent (ADR-0073 dec. 8).
	var fs_abs: int = -1
	if str(op.get("type", "")) == "FRAME":
		fs_abs = SequenceProjector.absolute_frameset(int(op.get("frameset", 0)), group, effect_data)

	# THE SUFFIX IS A TOOLTIP, NOT TITLE TEXT (author, 2026-08-20: *"this text is breaking
	# tables and is annoying please remove it"*).
	#
	# ADR-0103 dec. 5 put the colour rung here on the argument that **"a title suffix costs
	# 0px"** in the ~268px inspector row three surfaces share. That argument is FALSE and the
	# author found it before the arithmetic did: the section header is a `Button`, so its text
	# sets the header's minimum width, which propagates through the inspector's content width
	# and widens the whole right column — squeezing the value tables that share the row. A
	# suffix costs 0px of HEIGHT, which is the dimension that was being reasoned about; it
	# costs whatever it is wide.
	#
	# The information is not lost. The colour rung is already stated in full on the colour
	# column's slot tooltip, and the parked opcode is already on the player's own overlay
	# ("tick 6 / 37 — opcode 7"). Here it becomes the header's tooltip, where it is one hover
	# away and costs nothing at all.
	var suffix: String = "" if provenance.is_empty() else CellColour.title_suffix(provenance)

	if fs_abs < 0:
		return _wrap(_idle_title(op, op_index), [], _idle_title(op, op_index) + suffix)

	# THE FRAMES COME FIRST, and the first one opens. Both of those are corrections to what
	# shipped, and the reason is that the inspector row is ~268px tall against 2000+px of
	# content: leading with the frameset's four own rows spent the entire visible height on
	# chrome, so the screen arrived showing a header and nothing else — the folds carrying
	# the parameters it exists to expose were below the cut AND shut. Worse for the common
	# case than for the rare one: 13,854 of the corpus's framesets hold a SINGLE frame, so
	# "frame folds default shut" meant that for most framesets the block showed no frame at
	# all. One fold open costs no build time (a fold body is built either way; only
	# `visible` differs) and it is what makes the screen deliver on arrival.
	#
	# The multi-member case is still the normal case — E019's framesets are 82x two-member
	# (the classic PSX double-draw: same UV, same palette, quad offset by a pixel) and the
	# corpus tail runs to 14 (E228 frameset 50). At 14 folds that is ~56 ms, so the block
	# absorbs the worst case as a plain list, with only the first one open.
	var fields: Array = []
	var frames: Array = _frames(effect_data, fs_abs)
	var regions: Dictionary = Canvas.region_index(effect_data.framesets) if frames.size() > 0 else {}
	for m in range(frames.size()):
		var stamp := {"id": "fr:%d:%d" % [fs_abs, m], "label": "Frame %d" % m,
			"summary": _frame_summary(frames[m]), "expanded": m == 0}
		fields.append_array(_frame_fold(Target, effect_data, score, fs_abs, m, stamp, regions))

	# The frameset's OWN rows last — verbatim, including the sheet's Export/Import round
	# trip, which FramesetProjector offers at this level on purpose ("repainting one is the
	# reason an author is looking at a frame's rect in the first place"). Below the frames
	# because that is the order of interest: the round trip is a convenience reachable by a
	# scroll, the frames are why you opened the screen.
	for fsec in FramesetProjector.sections(Target.frameset(fs_abs), effect_data, score):
		fields.append_array(fsec.get("fields", []))

	return _wrap("Frameset %d" % fs_abs, fields,
		"Frameset %d — shown by opcode %d" % [fs_abs, op_index] + suffix)


## The section envelope. OPEN by default (`collapsed: false`), with its FIRST frame fold
## open inside it — the block is what you came to the screen for, and a block that opens
## onto nothing but headers is not open in any sense the author cares about.
static func _wrap(title: String, fields: Array, tooltip: String = "") -> Dictionary:
	return {"title": title, "fields": fields, "fold_id": FOLD_ID, "collapsed": false,
		"tooltip": tooltip}


## The whole of what the panel says for an opcode that shows no sprite — a title, no rows.
## It names the INSTRUCTION rather than the absence ("opcode 0 · SET_OFFSET — no frameset"),
## because "which opcode am I parked on" is the question the author actually has while
## clicking through the strip, and the empty body answers the other one by itself.
static func _idle_title(op: Dictionary, shown: int) -> String:
	var t := str(op.get("type", ""))
	if t == "":
		return "Opcode %d — not in this sequence" % shown
	return "Opcode %d · %s — no frameset" % [shown, t]


## One member frame's rows, stamped into that frame's fold. The projector's whole SHEET
## REGION section is REPLACED by a read-only statement of the rect, its fan-out, and a link
## to the frame's own screen (see the file header); the sheet link and its Export/Import
## actions are dropped because the frameset block above already carries one copy and a
## per-frame copy in each of up to 14 folds is noise. Everything else is grafted unchanged,
## including the quad's fact rows and all eight raw corner rows.
##
## FILTERED BY `fold_id`, NEVER BY TITLE (2026-08-21). This used to keep the one section
## called "Frame" and drop the rest, and match the UV rows on a `"UV"` name prefix — so
## when the projector split its flat list into Appearance / Sheet region / Drawn quad, the
## title match would have silently grafted NOTHING and the strip's folds would have gone
## empty with no error anywhere. A title is prose and gets reworded; a fold id is an
## address, and the projector exports them as constants for exactly this.
static func _frame_fold(Target, effect_data, score: Dictionary, fs_abs: int, m: int,
		stamp: Dictionary, regions: Dictionary) -> Array:
	var out: Array = []
	for sec in FramesetProjector.sections(Target.frame(fs_abs, m), effect_data, score):
		var fold_id := str(sec.get("fold_id", ""))
		# The TPAGE section is four const rows of raw bytes; they belong on the frame's own
		# screen, where there is room for them and a reason to look.
		# The TPAGE bytes and the eight RAW CORNER components both belong on the frame's
		# own screen: there is room there, and the transform rows above say the same thing
		# in five terms of which four are usually at rest.
		if fold_id in [FramesetProjector.FOLD_TPAGE, FramesetProjector.FOLD_CORNERS]:
			continue
		if fold_id == FramesetProjector.FOLD_REGION:
			out.append_array(_uv_rows(Target, effect_data, fs_abs, m, regions, stamp))
			continue
		for f in sec.get("fields", []):
			if str(f.get("name", "")) in ["Sheet", "Export", "Import"]:
				continue
			var row: Dictionary = (f as Dictionary).duplicate(true)
			row["group"] = stamp
			out.append(row)
	return out


## The UV rows' stand-in: the rect, how many frames share it, and the way to the screen
## where it can actually be edited safely.
static func _uv_rows(Target, effect_data, fs_abs: int, m: int, regions: Dictionary,
		stamp: Dictionary) -> Array:
	var frame: Dictionary = _frames(effect_data, fs_abs)[m]
	var block: Rect2i = Canvas.normalised_block(frame.get("uv", {}))
	var shared: int = int(regions.get(block, 1))
	var fan := ("used by this frame alone" if shared <= 1
		else "⚠ shared by %d frames in this effect" % shared)
	return [
		{"name": "UV rect", "shape": "const",
			"value": "%d,%d · %d×%d" % [block.position.x, block.position.y, block.size.x, block.size.y],
			"tooltip": "The sheet region this frame draws from. Read-only here — a rect is "
				+ "SHARED, and the scope control that states a move's blast radius lives "
				+ "under the frameset canvas, which cannot be on screen beside the player.",
			"group": stamp},
		{"name": "", "shape": "const", "value": fan, "group": stamp},
		{"name": "Sheet region", "shape": "link", "label": "edit on frame %d/%d ▸" % [fs_abs, m],
			"target": Target.frame(fs_abs, m), "group": stamp},
	]


## The fold header's one-line summary — drawn size, offset, palette and blend, the four
## facts that tell two members of a double-draw apart at a glance.
static func _frame_summary(frame: Dictionary) -> String:
	var size: Vector2i = Canvas.quad_size(frame)
	var v: Dictionary = frame.get("vertices", {})
	var tl: Array = v.get("top_left", [0, 0])
	var x: int = int(tl[0]) if tl.size() > 0 else 0
	var y: int = int(tl[1]) if tl.size() > 1 else 0
	return "%d×%d @ %d,%d · pal %d · %s" % [size.x, size.y, x, y,
		int(frame.get("palette_id", 0)), _blend_name(int(frame.get("semi_trans_mode", 0)))]


static func _blend_name(mode: int) -> String:
	match mode:
		0: return "BLEND_50"
		1: return "ADD"
		2: return "SUB"
		3: return "ADD_25"
	return "?"


static func _opcode(effect_data, anim_idx: int, op_idx: int) -> Dictionary:
	if effect_data == null or not (effect_data.animations is Array):
		return {}
	if anim_idx < 0 or anim_idx >= effect_data.animations.size():
		return {}
	var anim = effect_data.animations[anim_idx]
	if not (anim is Dictionary):
		return {}
	var ops = anim.get("opcodes", [])
	if not (ops is Array) or op_idx < 0 or op_idx >= ops.size():
		return {}
	var op = ops[op_idx]
	return op if op is Dictionary else {}


static func _frames(effect_data, fs_abs: int) -> Array:
	if effect_data == null or not (effect_data.framesets is Array):
		return []
	if fs_abs < 0 or fs_abs >= effect_data.framesets.size():
		return []
	var fs = effect_data.framesets[fs_abs]
	if not (fs is Dictionary):
		return []
	var frames = fs.get("frames", [])
	return frames if frames is Array else []
