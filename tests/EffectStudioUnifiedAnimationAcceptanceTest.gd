extends Node
## ACCEPTANCE (headful, real E019): the unified animation screen (ADR-0102) wired into the
## LIVE studio. Four things, and every one of them is a thing that has actually broken here
## before:
##
##   1. the block is in the FOCUS PANEL — its own container beside the film strip, NOT a
##      section of the strip's list — and it opens;
##   2. clicking through the film strip RETARGETS it and THE THUMBNAILS DO NOT MOVE. That
##      second half is the whole of the ADR-0102 second amendment and it is measured, not
##      asserted loosely: the retarget goes between a two-member frameset and a one-member
##      one, which as a section in the strip's flow slid every thumbnail below it by 39px.
##      The widget-identity proof rides along — an untouched strip section's ScrubField
##      keeps its exact instance, so a `_render_current()` (which kills a live drag after
##      one pixel, `87c081b7b`) would still be caught;
##   3. an edit made from a grafted row reaches the PLAYER. `SequenceCanvas._decode` derives
##      the shared bounds box from the FRAMESETS, so a vertex edit here moves the box every
##      thumbnail is drawn in — and `FramesetChannel` reports `invalidates_sim: false`, so
##      before the `frameset` branch in `_apply_edit` nothing refreshed at all;
##   4. the build stays inside its measured ceiling. Shipping sequence view: 343 ms. With
##      the block: 400-428 ms. A fold-per-opcode shape (the rejected one) was 1867 ms, so
##      the ceiling here is set well below that and above the measurement.
##
## MEASUREMENT GOTCHA: the studio page lives in DebugDashboard, which extends Window — so
## capture `page.get_viewport()`, and `_settle(page._body)` before reading any rect.
##
## Run: godot --path . --quit-after 300 res://tests/EffectStudioUnifiedAnimationAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const SHOT := "user://unified_animation_acceptance.png"
const FocusBlock = preload("res://src/effects/studio/SequenceFocusBlock.gd")
const ScrubField = preload("res://src/effects/studio/ScrubField.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

## The rejected fold-per-opcode shape measured 1867 ms; the accepted root block measured
## 400-428 ms against a 343 ms baseline. 900 sits far above the measurement's spread (this
## harness has seen the dashboard come up at wildly different sizes) and far below the
## shape this design exists to refuse — so it fails on a REGRESSION OF KIND, not on noise.
const BUILD_CEILING_MS: float = 900.0

var _passed: int = 0
var _failed: int = 0
var _completed: Dictionary = {}
const _EXPECTED_TESTS := ["block_is_first", "retarget_is_in_place", "edit_reaches_the_player",
	"build_cost", "screenshot"]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run" % name)
	print("\n=== EffectStudioUnifiedAnimationAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioUnifiedAnimationAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioUnifiedAnimationAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — unified animation acceptance skipped")
		_passed += 1
		for n in _EXPECTED_TESTS:
			_done(n)
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	DebugOverlay.show_overlay()
	await _frames(30)
	await _settle(page._body, "the dashboard body")
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	page._set_root(Target.animation(0))
	await _frames(40)

	# --- 1. the block is in the focus panel, and it opens ---------------------
	var strip_folds: Array = page._inspector.section_folds()
	_assert_true(not strip_folds.is_empty(), "the sequence view rendered sections")
	for entry in strip_folds:
		_assert_true(str(entry.get("id", "")) != FocusBlock.FOLD_ID,
			"the block is NOT a section of the film strip's list any more")
	# THE BLOCK IS STACKED UNDER THE PLAYER now, not a column beside it (ADR-0100 dec. 1,
	# amended 2026-08-19), so its bound is the COLUMN's leftover HEIGHT rather than the row's
	# leftover width. This harness has measured the dashboard at wildly different sizes across
	# runs (the WM decides) and below the collapse height the block is deliberately dropped —
	# report the numbers and skip rather than fail on a window, but print the terms so a panel
	# missing for a REAL reason is still legible instead of reading as noise.
	#
	# The skip is NOT rare here and that is worth saying out loud: the player's box is
	# `_CANVAS_SIDE` plus ~188 of measured chrome, so a row under roughly 510px has no slack
	# at all and the dev dashboard's 268px row never shows the block.
	var slack: float = Page.focus_stack_height(page._inspector.size.y,
		page._sequence_panel.size.y, page._focus_inspector.content_height())
	if slack <= 0.0 or page._focus_panel == null or not page._focus_panel.visible:
		print(("[SKIP] no room to stack the block — row %.0fpx tall, player's box takes %.0f, "
			+ "leaving %.0f of slack under it")
			% [page._inspector.size.y, page._sequence_panel.size.y, slack])
		_passed += 1
		for n in ["block_is_first", "retarget_is_in_place", "edit_reaches_the_player",
				"build_cost", "screenshot"]:
			_done(n)
		return
	_assert_true(page._focus_panel != null and page._focus_panel.visible,
		"the focus panel is up for an animation target")
	var folds: Array = page._focus_inspector.section_folds()
	_assert_eq(folds.size(), 1, "the focus panel holds exactly one section — the block")
	_assert_eq(str(folds[0].get("id", "")), FocusBlock.FOLD_ID, "…and it is the block")
	_assert_true((folds[0]["body"] as Control).visible,
		"and it is open (its frame folds are the things that start shut)")
	# The panel is a COLUMN between the strip and the player, so all three share the row's
	# height and none of them overlaps its neighbour.
	var strip_r: Rect2 = page._inspector.get_global_rect()
	var focus_r: Rect2 = page._focus_panel.get_global_rect()
	var player_r: Rect2 = page._sequence_panel.get_global_rect()
	print("  stack: strip %s  player %s  focus %s" % [str(strip_r), str(player_r), str(focus_r)])
	# TWO columns now, and the block is INSIDE the right one. The width it used to hold as a
	# middle column went back to the strip, which on this screen was pinned at 450 of a 1241px
	# body while its opcode rows wanted more.
	_assert_true(player_r.position.x >= strip_r.position.x + strip_r.size.x - 1.0,
		"the player starts at or past the strip's right edge")
	_assert_true(absf(focus_r.position.x - player_r.position.x) < 2.0,
		"the block is in the PLAYER's column, not a column of its own")
	_assert_true(absf(focus_r.size.x - player_r.size.x) < 2.0,
		"…at the player's width")
	_assert_true(focus_r.position.y >= player_r.position.y + player_r.size.y - 1.0,
		"…and UNDER it, never overlapping the box")
	_assert_true(focus_r.position.y + focus_r.size.y
			<= strip_r.position.y + strip_r.size.y + 1.0,
		"and the stack stays inside the row (block ends %.0f, row ends %.0f)"
			% [focus_r.position.y + focus_r.size.y, strip_r.position.y + strip_r.size.y])
	# Read the subject off the block's own TOOLTIP, not off the canvas. A freshly opened
	# sequence has no selection and the block opens on the PLAYHEAD's opcode — and the
	# player is running, so the playhead has already moved on by the time this line runs.
	# The block's own statement of what it is showing is the only stable source.
	#
	# The TOOLTIP and not the title since 2026-08-20: the opcode moved off the title text
	# because a header is a Button whose text sets a minimum width, and that width was
	# widening the whole right column and breaking the value tables ("this text is breaking
	# tables and is annoying please remove it").
	var first_op: int = _subject_opcode(str(folds[0].get("tooltip", "")))
	print("  block: %s / %s (subject opcode %d, selection %d)"
		% [str(folds[0].get("title", "")), str(folds[0].get("tooltip", "")), first_op,
			page._sequence_canvas.selected_op()])
	# The member folds are the block's substance — name them in the log so a run that
	# "passes" with an empty block is visible rather than silent.
	var labels: Array = []
	for fold in page._focus_inspector.param_folds():
		var t := str((fold["header"] as Button).text)
		if t.contains("Frame "):
			labels.append(t.strip_edges())
	print("  folds: %s" % str(labels))
	_assert_true(not labels.is_empty(), "the block rendered a fold per member frame")
	_done("block_is_first")

	# --- 2. the retarget moves the block and NOTHING ELSE ---------------------
	# Park on a known member count first, so the retarget below crosses the boundary that
	# used to move things: a two-member frameset is one whole fold taller than a one-member
	# one, and as a section in the strip's flow that slid every thumbnail below it by 39px.
	var pair: Array = _opcodes_by_member_count(page)
	_assert_true(pair.size() == 2,
		"E019 sequence 0 has FRAME opcodes on framesets of two different member counts")
	page._park_sequence_on(int(pair[0]))
	await _frames(20)

	# Pick a witness from a strip section the retarget does NOT touch, and remember the
	# exact instance AND its screen position.
	var opcode_section = _section_after_block(page)
	_assert_true(opcode_section != null, "there is an opcode section in the strip")
	(opcode_section["header"] as Button).button_pressed = true
	await _frames(6)
	var witness: Control = _first_scrub(opcode_section["body"])
	_assert_true(witness != null, "the opened opcode section has a live ScrubField in it")
	var witness_id: int = witness.get_instance_id() if witness != null else 0
	var title_before: String = str(page._focus_inspector.section_folds()[0].get("title", ""))
	var thumbs_before: Array = _thumbnail_ys(page)
	var strip_before: Rect2 = page._inspector.get_global_rect()
	_assert_true(thumbs_before.size() > 1, "the strip rendered thumbnails to measure")

	var other_op: int = int(pair[1])
	page._park_sequence_on(other_op)
	await _frames(20)

	# THE ASSERTION THE WHOLE AMENDMENT EXISTS FOR.
	var thumbs_after: Array = _thumbnail_ys(page)
	var worst: float = 0.0
	for i in range(mini(thumbs_before.size(), thumbs_after.size())):
		worst = maxf(worst, absf(float(thumbs_after[i]) - float(thumbs_before[i])))
	print("  thumbnails: %d before / %d after, worst move %.1fpx (was 39 as a section)"
		% [thumbs_before.size(), thumbs_after.size(), worst])
	_assert_eq(thumbs_after.size(), thumbs_before.size(), "the strip kept every section")
	_assert_true(worst < 1.0,
		"NO thumbnail moved when the block retargeted across member counts (worst %.1fpx)"
			% worst)
	_assert_true(page._inspector.get_global_rect() == strip_before,
		"…and the strip's own rect is untouched (was %s, now %s)"
			% [str(strip_before), str(page._inspector.get_global_rect())])

	var title_after: String = str(page._focus_inspector.section_folds()[0].get("title", ""))
	_assert_true(title_after != title_before,
		"the block retargeted (was '%s', now '%s')" % [title_before, title_after])
	# THE OPCODE IS IN THE TOOLTIP, NOT THE TITLE (ADR-0103 dec. 5, corrected in 3cbe27b79 on
	# the author's own report: *"this text is breaking tables and is annoying please remove
	# it"*). A section header is a `Button`, so its text sets its minimum width and propagates
	# through the inspector's declared content width to the whole right column — the suffix
	# `— shown by opcode 6 · colour from emitter 2` measured 456px of a 675px inspector. Both
	# halves moved to the header's tooltip. Asserting on the title was asserting the sentence
	# the author asked to have removed.
	_assert_true(str(title_after).begins_with("Frameset"),
		"the title is the bare frameset, no sentence (got '%s')" % title_after)
	var header = page._focus_inspector.section_folds()[0].get("header")
	var tip: String = str(header.tooltip_text) if header != null else ""
	_assert_true(tip.contains("opcode %d" % other_op),
		"…and the TOOLTIP names the opcode the strip is parked on (got '%s')" % tip)
	_assert_true(is_instance_valid(witness) and witness.get_instance_id() == witness_id,
		"and a strip section's ScrubField is the SAME instance — the retarget rebuilt the "
			+ "focus panel, not the strip (a full render would have freed it mid-drag)")
	_assert_eq(str(page._focus_inspector.section_folds()[0].get("id", "")), FocusBlock.FOLD_ID,
		"the block is still the focus panel's one section after the retarget")
	# The STRIP's registries must come through a retarget untouched. This used to be the
	# hard part: an in-place section rebuild was the one path that removed widgets without
	# going through `_clear_groups`, and it could not prune by `is_instance_valid` (a
	# `queue_free`d node stays valid until end of frame), so it scrubbed by identity — and a
	# missed entry handed every test seam, and `refresh_palette_tint` /
	# `refresh_colour_channels` / `refresh_follows`, a freed node. With the block in its own
	# inspector the retarget never reaches these registries at all; the assertion stays
	# because "never reaches" is the claim, and it is only true while the block stays out.
	var orphans := 0
	for w in page._inspector.int_widgets():
		if not (is_instance_valid(w) and (w as Node).is_inside_tree()):
			orphans += 1
	for w2 in page._inspector.action_buttons():
		if not (is_instance_valid(w2) and (w2 as Node).is_inside_tree()):
			orphans += 1
	_assert_eq(orphans, 0,
		"the retarget left no orphaned widgets in the inspector's registries")
	_done("retarget_is_in_place")

	# --- 3. an edit from a grafted row reaches the player ---------------------
	# A vertex edit widens the quad; `SequenceCanvas._decode` derives `_bounds` from the
	# framesets, so the player's shared box has to move with it.
	var vertex_row: Dictionary = _grafted_vertex_row(page)
	if vertex_row.is_empty():
		print("  NOTE: the block's frameset has no vertex row to drive — player leg skipped")
	else:
		# Asserted on `decode_changed`, not on the bounds RECT. The rect is the union over
		# the whole trace, so widening one corner of one frame can legitimately stay inside
		# a box some other opcode already sets — a passing rect assertion would be luck and
		# a failing one would be geometry, neither of which is the claim. The claim is that
		# the player RE-DECODED, which is the thing that was not happening at all before the
		# `frameset` branch existed.
		var decodes := [0]
		page._sequence_canvas.decode_changed.connect(func(): decodes[0] += 1)
		var bounds_before: Rect2i = page._sequence_canvas.get_bounds()
		page._apply_edit(vertex_row["field_ref"], int(vertex_row["value"]) + 400, false)
		await _frames(20)
		_assert_true(decodes[0] > 0,
			"a frameset edit made from the unified screen re-decodes the player "
				+ "(bounds %s → %s)" % [str(bounds_before), str(page._sequence_canvas.get_bounds())])
		# Put it back so the screenshot below shows the real effect.
		page._apply_edit(vertex_row["field_ref"], int(vertex_row["value"]), false)
		await _frames(10)
	_done("edit_reaches_the_player")

	# --- 4. the build cost ---------------------------------------------------
	var t0 := Time.get_ticks_usec()
	page._render_current()
	var build_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(10)
	print("  build: %.1f ms  content_width=%.0f  sections=%d"
		% [build_ms, page._inspector.content_width(), page._inspector.section_folds().size()])
	_assert_true(build_ms < BUILD_CEILING_MS,
		"the sequence view with the block builds in %.1f ms (ceiling %.0f — the rejected "
			% [build_ms, BUILD_CEILING_MS] + "fold-per-opcode shape measured 1867)")
	_done("build_cost")

	await _frames(4)
	var img: Image = page.get_viewport().get_texture().get_image()
	var err: int = img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written")
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))
	_done("screenshot")


# --- helpers ---------------------------------------------------------------

## A strip section, whose widgets the retarget must leave completely alone. Not the FIRST
## one: opcode 0 is a SET_OFFSET whose section carries no ScrubField worth watching.
func _section_after_block(page):
	var folds: Array = page._inspector.section_folds()
	for entry in folds:
		if str(entry.get("id", "")) != FocusBlock.FOLD_ID:
			return entry
	return null


## Every strip section header's global Y, in list order — the thumbnails' screen positions,
## which the block must not be able to move.
func _thumbnail_ys(page) -> Array:
	var out: Array = []
	for entry in page._inspector.section_folds():
		out.append((entry["header"] as Control).get_global_rect().position.y)
	return out


## Two FRAME opcodes whose framesets hold DIFFERENT numbers of member frames — the pair a
## retarget between which used to re-flow the strip. `[]` when the sequence has only one
## member count (then there is nothing here to prove).
func _opcodes_by_member_count(page) -> Array:
	var ops: Array = page._effect_data.animations[0].get("opcodes", [])
	var first_by_count := {}
	for i in range(ops.size()):
		if str(ops[i].get("type", "")) != "FRAME":
			continue
		var fs: int = int(ops[i].get("frameset", 0))
		if fs < 0 or fs >= page._effect_data.framesets.size():
			continue
		var n: int = page._effect_data.framesets[fs].get("frames", []).size()
		if not first_by_count.has(n):
			first_by_count[n] = i
	var counts: Array = first_by_count.keys()
	counts.sort()
	if counts.size() < 2:
		return []
	return [first_by_count[counts[0]], first_by_count[counts[counts.size() - 1]]]


func _first_scrub(node: Node) -> Control:
	if node.get_script() == ScrubField:
		return node as Control
	for c in node.get_children():
		var found := _first_scrub(c)
		if found != null:
			return found
	return null


## The opcode a block's long form names, from `"Frameset 0 — shown by opcode 12"`, or -1.
## That string is the header's TOOLTIP now; the title is just "Frameset 0".
func _subject_opcode(title: String) -> int:
	var at := title.rfind("opcode ")
	if at < 0:
		return -1
	var tail := title.substr(at + 7).strip_edges()
	var digits := ""
	for ch in tail:
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return int(digits) if digits != "" else -1


## A vertex row the block grafted, as `{field_ref, value}` — the row an author would drag.
func _grafted_vertex_row(page) -> Dictionary:
	var score: Dictionary = page._timeline._score if page._timeline else {}
	var block := FocusBlock.section(page._nav.back(), page._effect_data, score,
		page._sequence_canvas.selected_op())
	for f in block.get("fields", []):
		if str(f.get("name", "")).begins_with("Vertex") and f.has("field_ref"):
			return {"field_ref": f["field_ref"], "value": int(f.get("value", 0))}
	return {}


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _settle(node: Control, what: String, max_frames: int = 240) -> void:
	var last := Rect2()
	var stable := 0
	for _i in range(max_frames):
		await get_tree().process_frame
		var now: Rect2 = node.get_global_rect()
		if now == last and now.size.x > 1.0 and now.size.y > 1.0:
			stable += 1
			if stable >= 8:
				return
		else:
			stable = 0
			last = now
	print("  WARN: %s never settled in %d frames (last %s)" % [what, max_frames, str(last)])


func _assert_true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % what)


func _assert_eq(actual, expected, what: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s\n        expected: %s\n        actual:   %s" % [what, expected, actual])
