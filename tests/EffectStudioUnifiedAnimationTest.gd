extends Node
## TDD guard for the **unified animation screen** (ADR-0102) — the focus block that puts
## the selected opcode's frameset and every member frame at the top of a sequence's own
## section list.
##
## The two assertions the design turns on:
##   1. a grafted frameset row carries the SAME `field_ref` the frame DETAIL screen emits.
##      That is the whole basis for composing instead of writing a fourth projector: the
##      ref is absolute (`channel/frameset_index/frame_index/field`) and `apply_edit`
##      routes on the channel alone, so the row edits the right frame from anywhere.
##   2. THE GROUP LENS, mutation-tested. Point the same opcode at a non-zero frameset group
##      and the block must move to the SHIFTED frameset — its rows must address that one,
##      not the raw stored index. Get this wrong and an author edits a sprite they are not
##      looking at, silently, and only for the 18-of-401 effects that have a second group.
##
## Plus the shape rules: UV rows read-only with the fan-out stated, the block emitted even
## for an opcode that shows no sprite (as a title and nothing else — the focus panel's slot
## is reserved so the strip beside it cannot move), frame folds shut, the block open, and
## no control of any kind above the frames.
##
## Pure statics against a synthetic effect — no scene, no window. The live wiring
## (`selection_changed` → the focus panel) is EffectStudioUnifiedAnimationAcceptanceTest's.
##
## Run: godot --path . --quit-after 8 res://tests/EffectStudioUnifiedAnimationTest.tscn

const EffectData = ExMateriaEffects.EffectData

const FocusBlock = preload("res://src/effects/studio/SequenceFocusBlock.gd")
const FramesetProjector = preload("res://src/effects/studio/FramesetProjector.gd")
const SequenceProjector = preload("res://src/effects/studio/SequenceProjector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}
const _EXPECTED_TESTS := [
	"field_refs_match_the_detail_screen", "group_lens_shifts_the_block",
	"uv_is_read_only_with_the_fan_out", "the_graft_survives_a_projector_resection",
	"block_survives_a_spriteless_opcode",
	"folds_shut_block_open", "block_carries_no_pin", "every_member_gets_a_fold",
	"frames_lead_and_the_first_opens",
]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	_run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run" % name)
	print("\n=== EffectStudioUnifiedAnimationTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioUnifiedAnimationTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioUnifiedAnimationTest")
		get_tree().quit(0)


func _run() -> void:
	_test_field_refs_match_the_detail_screen()
	_test_group_lens_shifts_the_block()
	_test_uv_is_read_only_with_the_fan_out()
	_test_the_graft_survives_a_projector_resection()
	_test_block_survives_a_spriteless_opcode()
	_test_folds_shut_block_open()
	_test_block_carries_no_pin()
	_test_every_member_gets_a_fold()
	_test_frames_lead_and_the_first_opens()


## THE COMPOSITION CLAIM. Every editable row the block grafts must carry byte-for-byte the
## same `field_ref` the frame's own screen puts on the same field — else the graft is a
## restatement that can drift, and the "no fourth projector" argument collapses.
func _test_field_refs_match_the_detail_screen() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)

	# Frameset 1 / frame 0 — opcode 1 stores `fs=1`, so that is the frame the block shows.
	var detail: Dictionary = {}   # field name -> field_ref, as the frame screen emits it
	for sec in FramesetProjector.sections(Target.frame(1, 0), ed, {}):
		for f in sec.get("fields", []):
			if f.has("field_ref"):
				detail[str(f.get("name", ""))] = f["field_ref"]
	_assert_true(detail.size() >= 12, "the frame detail screen emits its editable rows (%d)" % detail.size())

	var checked := 0
	for f in block.get("fields", []):
		if not f.has("field_ref"):
			continue
		var fr: Dictionary = f["field_ref"]
		# BOTH channels: the four stored `frameset` bytes AND the six derived `frameset_quad`
		# transform terms. The derived ones matter MORE to this claim, not less — a term is
		# not a byte, so if the two surfaces minted their addresses separately there would be
		# nothing but the name keeping them pointed at the same frame.
		if not (String(fr.get("channel", "")) in ["frameset", "frameset_quad"]):
			continue
		if int(fr.get("frame_index", -1)) != 0:
			continue   # frame 1's rows carry the same shape at a different index
		var name := str(f.get("name", ""))
		_assert_true(detail.has(name), "the block's '%s' row is a row the frame screen has too" % name)
		if detail.has(name):
			_assert_eq(fr, detail[name], "the block's '%s' field_ref is the detail screen's" % name)
			checked += 1
	_assert_true(checked >= 10,
		"and enough rows were compared to mean it (%d — palette, blend, the two flags, and the six transform terms)"
			% checked)
	_done("field_refs_match_the_detail_screen")


## THE GROUP LENS, MUTATION-TESTED. The same opcode stores frameset 1; read through group 1
## (offset 2) it must reach frameset 3. Both the title and — the part that matters — every
## grafted `field_ref` must address 3, not 1.
func _test_group_lens_shifts_the_block() -> void:
	var ed = _effect()
	_assert_eq(ed.frameset_group_offset(1), 2, "the fixture's group 1 shifts by 2")

	var raw := FocusBlock.section(Target.animation(0, 0), ed, {}, 1)
	var shifted := FocusBlock.section(Target.animation(0, 1), ed, {}, 1)

	_assert_true(str(raw.get("title", "")).contains("Frameset 1"),
		"through group 0 the block is the raw stored index (got '%s')" % raw.get("title", ""))
	_assert_true(str(shifted.get("title", "")).contains("Frameset 3"),
		"through group 1 it is the SHIFTED frameset (got '%s')" % shifted.get("title", ""))

	# THE TITLE IS SHORT, AND THE LONG FORM IS THE TOOLTIP (author, 2026-08-20: *"this text
	# is breaking tables and is annoying please remove it"*).
	#
	# A section header is a `Button`, so its TEXT sets a minimum width that propagates
	# through the inspector's content width to the whole right column — which is how
	# "Frameset 0 — shown by opcode 1 · colour from emitter 2 (drilled from)" squeezed the
	# value tables sharing the row. ADR-0103 dec. 5 argued a title suffix "costs 0px"; that
	# was true of HEIGHT and false of the dimension that bit. Asserted here rather than left
	# to taste, because the natural thing to do with a new fact about the block is to append
	# it to the title, and this is the third surface to have learned that the inspector row
	# has no spare width.
	for t in [str(raw.get("title", "")), str(shifted.get("title", ""))]:
		_assert_true(not t.contains("opcode"),
			"the title does not carry the opcode (got '%s')" % t)
		_assert_true(not t.contains("colour from"),
			"…nor the colour rung (got '%s')" % t)
		_assert_true(t.length() <= 16,
			"…and stays short — %d chars ('%s')" % [t.length(), t])
	_assert_true(str(raw.get("tooltip", "")).contains("shown by opcode"),
		"the long form survives on the TOOLTIP (got '%s')" % raw.get("tooltip", ""))

	_assert_eq(_frameset_indices(raw), [1], "every group-0 row addresses frameset 1")
	_assert_eq(_frameset_indices(shifted), [3], "every group-1 row addresses frameset 3 — the edit lands on the shifted frameset")
	# And it agrees with the follow button beside the opcode's own Frameset editor, which is
	# the one number both are derived from.
	_assert_eq(SequenceProjector.absolute_frameset(1, 1, ed), 3,
		"the block and the opcode's follow button share one derivation")
	_done("group_lens_shifts_the_block")


## A UV rect is a SHARED sheet region and the scope control that states a move's blast
## radius cannot be on screen here — so the block states the rect and the fan-out, offers
## no editor for it, and links to the screen where it can be edited safely.
func _test_uv_is_read_only_with_the_fan_out() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)

	for f in block.get("fields", []):
		var name := str(f.get("name", ""))
		if name.begins_with("UV"):
			_assert_eq(str(f.get("shape", "")), "const", "the '%s' row is read-only here" % name)
	var stated := false
	var linked := false
	for f in block.get("fields", []):
		if str(f.get("value", "")).contains("shared by"):
			stated = true
		if str(f.get("shape", "")) == "link" and str(f.get("name", "")) == "Sheet region":
			linked = true
			_assert_true(Target.kind(f.get("target", {})) == "frame",
				"and the link goes to the frame's own screen")
	_assert_true(stated, "the fan-out is stated ('shared by N frames') — the fixture shares one rect")
	_assert_true(linked, "with a link to where the rect CAN be edited")
	_done("uv_is_read_only_with_the_fan_out")


## THE GRAFT IS A SILENT FAILURE MODE, so it gets its own guard (2026-08-21). This block
## declares no rows of its own — it calls `FramesetProjector.sections()` and re-stamps what
## comes back — and it used to select them by matching the section title `"Frame"` and the
## row-name prefix `"UV"`. When the projector split its flat list into Appearance / Sheet
## region / Drawn quad, that title stopped existing: the filter would have matched nothing,
## every frame fold would have rendered EMPTY, and no error would have been raised anywhere.
##
## So the assertion is not "the rows are correct" but "the rows are THERE" — the drawn-quad
## facts and all eight corner rows, which are the bulk of what a frame fold is for.
func _test_the_graft_survives_a_projector_resection() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)
	var names: Array = []
	for f in block.get("fields", []):
		names.append(str(f.get("name", "")))

	for n in ["Base", "Width", "Height", "Rotation", "Shear", "Position X", "Position Y",
			"Orientation", "Palette ID", "Blend mode"]:
		_assert_true(names.has(n), "the frame fold still grafts the '%s' row" % n)

	# What the graft deliberately DROPS — including, since the transform view landed, the
	# eight RAW corner components: five terms of which four are usually at rest say the same
	# thing, and the raw bytes belong on the frame's own screen where there is room.
	# Counted over the rows that carry a frame's fold STAMP, not over the block: the frameset's own rows are appended below the frame folds
	# and legitimately carry one `Sheet` link — the per-frame copies are what a fold in
	# each of up to 14 frames would make noise, and they are gone.
	var stamped: Array = []
	for f in block.get("fields", []):
		if not (f as Dictionary).get("group", {}).is_empty():
			stamped.append(str(f.get("name", "")))
	_assert_true(not stamped.is_empty(), "the frame rows carry their fold stamp")
	for n in ["TPAGE X base", "Sheet", "Top-left X", "Bottom-right Y"]:
		_assert_true(not stamped.has(n), "…and no frame fold still grafts the '%s' row" % n)
	# The whole Sheet region section is replaced, so no editable UV row reaches this screen.
	for n in ["UV X", "UV Y", "UV Width", "UV Height"]:
		_assert_true(not names.has(n),
			"…and the shared rect has no editor here — '%s' is replaced by the read-only statement" % n)
	_done("the_graft_survives_a_projector_resection")


## The block is emitted for a SET_OFFSET too — as a TITLE AND NOTHING ELSE. The author
## asked whether a frameset section should exist at all for an opcode with no frameset
## parameter; the answer is that there is no section any more, and the focus panel's
## reserved slot states which instruction is parked in it and stops. What it must NOT do is
## go absent: the panel sits above the film strip, so a slot that collapsed would hand its
## height back and slide every thumbnail — the movement the panel exists to stop.
func _test_block_survives_a_spriteless_opcode() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 0)   # opcode 0 is SET_OFFSET
	_assert_true(not block.is_empty(), "a spriteless opcode still yields a block")
	_assert_eq(str(block.get("fold_id", "")), FocusBlock.FOLD_ID, "under the same stable fold id")
	_assert_eq(block.get("fields", []).size(), 0,
		"…carrying NO rows — the old two-column 'Frameset │ … shows no sprite' row is gone")
	var title := str(block.get("title", ""))
	_assert_true(title.contains("SET_OFFSET") and title.to_lower().contains("opcode 0"),
		"the title names the instruction the strip is parked on (got '%s')" % title)
	_assert_eq(_frameset_indices(block), [], "with no frame rows to edit")

	var missing := FocusBlock.section(Target.animation(0), ed, {}, 99)
	_assert_true(not missing.is_empty(), "an out-of-range opcode index degrades to a block too")
	_done("block_survives_a_spriteless_opcode")


func _test_folds_shut_block_open() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)
	_assert_true(not bool(block.get("collapsed", false)),
		"the block itself OPENS — it is what you came to this screen for")
	var stamped := 0
	for f in block.get("fields", []):
		var g: Dictionary = f.get("group", {})
		if not g.is_empty():
			stamped += 1
			_assert_true(str(g.get("id", "")).begins_with("fr:"),
				"a frame row is stamped into its own fold (id '%s')" % g.get("id", ""))
	_assert_true(stamped > 0, "the frame rows are folded (folds default shut in the inspector)")
	_done("folds_shut_block_open")


## THERE IS NO PIN, and no other action row either. The block shipped with a
## "📌 Pin to this frameset" toggle that froze it on one opcode while the playhead ran; it
## was in the mockup, never in the approved build list, and the author cut it on first real
## use. What made it worth cutting rather than shrinking is the row it cost: an `action`
## renders through the same two-column grid as everything else, so it spent a label column
## ("Following") and a full row at the very TOP of a block whose first screenful is the
## whole point. Guarded as "no actions" rather than "no pin": the failure to prevent is a
## control re-appearing above the frames, whatever it is called.
func _test_block_carries_no_pin() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 2)      # opcode 2 → frameset 0
	_assert_eq(_frameset_indices(block), [0], "the block is about the opcode it was asked for")
	_assert_true(not str(block.get("title", "")).contains("PINNED"), "no pin tell on the title")
	for f in block.get("fields", []):
		_assert_true(str(f.get("action", {}).get("kind", "")) != "seq_focus_pin",
			"no pin action survives anywhere in the block")
	# The stronger half, and the one that keeps a REPLACEMENT out: the block's very first
	# row is already inside a frame fold. Anything reinstated above the frames — a pin, a
	# "Following" readout, a hint — breaks this before it breaks anything visual. (The
	# frameset's own Export/Import actions are grafted at the END and are not this.)
	var first: Dictionary = block.get("fields", [])[0] if not block.get("fields", []).is_empty() else {}
	_assert_true(str(first.get("group", {}).get("id", "")).begins_with("fr:"),
		"the block's first row is a frame's — nothing sits above the frames (got '%s')"
			% str(first.get("name", "")))
	_done("block_carries_no_pin")


## The multi-member case is the NORMAL case (E019's framesets are 82x two-member; the
## corpus tail runs to 14), so every member gets its own fold — no member picker.
func _test_every_member_gets_a_fold() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)   # frameset 1 has 2 members
	var fold_ids: Dictionary = {}
	for f in block.get("fields", []):
		var g: Dictionary = f.get("group", {})
		if not g.is_empty():
			fold_ids[str(g.get("id", ""))] = true
	_assert_eq(fold_ids.keys().size(), 2, "one fold per member frame")
	_assert_true(fold_ids.has("fr:1:0") and fold_ids.has("fr:1:1"),
		"keyed by (frameset, member) — got %s" % str(fold_ids.keys()))
	_done("every_member_gets_a_fold")


## WHAT THE FIRST SCREEN SHOWS. The inspector row is ~268px against 2000+px of content, so
## the block's first handful of rows ARE the feature as far as an author is concerned. Ship
## it leading with the frameset's own four rows and the frames land below the cut, shut, and
## the screen arrives showing a header and nothing else — which is exactly what happened.
## Two invariants keep it honest, and both are about order and openness, not content.
func _test_frames_lead_and_the_first_opens() -> void:
	var ed = _effect()
	var block := FocusBlock.section(Target.animation(0), ed, {}, 1)   # frameset 1, 2 members

	var first_frame_row := -1
	var first_frameset_row := -1
	var fields: Array = block.get("fields", [])
	for i in range(fields.size()):
		var stamped: bool = not (fields[i].get("group", {}) as Dictionary).is_empty()
		if stamped and first_frame_row < 0:
			first_frame_row = i
		if not stamped and str(fields[i].get("name", "")) == "Header flags":
			first_frameset_row = i
	_assert_true(first_frame_row >= 0, "the block carries frame rows")
	_assert_true(first_frameset_row >= 0, "and the frameset's own rows")
	_assert_true(first_frame_row < first_frameset_row,
		"the FRAMES lead (frame row %d before frameset row %d) — leading with the frameset's"
			% [first_frame_row, first_frameset_row]
			+ " Sheet/Export/Import spent the whole visible height on chrome")

	var opened: Array = []
	for f in fields:
		var g: Dictionary = f.get("group", {})
		if not g.is_empty() and bool(g.get("expanded", false)) and not (str(g.get("id", "")) in opened):
			opened.append(str(g.get("id", "")))
	_assert_eq(opened, ["fr:1:0"],
		"exactly the FIRST frame's fold asks to open — 13,854 corpus framesets hold a single"
			+ " frame, so all-shut meant the block showed no frame at all")
	_done("frames_lead_and_the_first_opens")


# --- fixtures -------------------------------------------------------------

## Sequence 0: `0: SET_OFFSET`, `1: FRAME fs=1`, `2: FRAME fs=0`.
## Four framesets; group 1 starts at frameset 2, so the opcode storing 1 reaches
## frameset 1 through group 0 and frameset 3 through group 1 — the mutation test's whole
## point. Framesets 1 and 3 hold TWO members each and both members share one UV rect, so
## the fan-out line has something true to say.
func _effect() -> EffectData:
	var ed = ExMateriaEffects.EffectData.new()
	ed.animations = [{"opcodes": [
		{"type": "SET_OFFSET", "x": 0, "y": 0},
		{"type": "FRAME", "frameset": 1, "duration": 4, "depth_mode": 2},
		{"type": "FRAME", "frameset": 0, "duration": 2, "depth_mode": 2},
	]}]
	ed.framesets = [
		_frameset(1, 16, 16, 0),
		_frameset(2, 32, 40, 1),
		_frameset(1, 8, 8, 2),
		_frameset(2, 64, 72, 3),
	]
	var offsets: Array[int] = [0, 2]   # the field is Array[int]; an untyped literal is refused
	ed.frameset_group_offsets = offsets
	return ed


func _frameset(members: int, uv_x: int, uv_y: int, palette: int) -> Dictionary:
	var frames: Array = []
	for m in range(members):
		frames.append({
			"uv": {"x": uv_x, "y": uv_y, "width": 24, "height": 24},
			"vertices": {"top_left": [-m, -m], "top_right": [24 - m, -m],
				"bottom_left": [-m, 24 - m], "bottom_right": [24 - m, 24 - m]},
			"palette_id": palette, "semi_trans_mode": 1, "semi_trans_on": true,
			"is_8bpp": false,
			"texture_page": {"x_base": 0, "y_base": 0, "blend": 1, "color_depth": 1},
		})
	return {"frames": frames, "header_flags": 0}


## Every distinct `frameset_index` the block's editable rows address, sorted — the answer
## to "which frameset would an edit made here actually land on".
func _frameset_indices(block: Dictionary) -> Array:
	var seen: Dictionary = {}
	for f in block.get("fields", []):
		var fr: Dictionary = f.get("field_ref", {})
		if String(fr.get("channel", "")) == "frameset" and fr.has("frame_index"):
			seen[int(fr.get("frameset_index", -1))] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s\n        expected: %s\n        actual:   %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s — expected true" % label)
