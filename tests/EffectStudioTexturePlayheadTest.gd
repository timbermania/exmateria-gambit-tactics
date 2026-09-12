extends Node
## ADR-0130 dec. 4c, WIRED (2026-08-21). "Scrubbing the sequence walks the outlines around
## the sheet" was decided and never implemented: the Texture tab read `_shown_frameset()`
## once inside `_render_current`, and parking on an opcode does not render.
##
## The author found it by eye on E317 `particle:for_each:1#2` — clicked a thumbnail, got a
## box that belonged to a different frameset than the one the player was showing, and could
## DRAG it (dec. 12). A real rect, a real box, nothing on screen saying it is the wrong one:
## the ADR-0100 defect, reached through the playhead instead of through the address.
##
## LIVE by necessity. The bug is a missing signal connection, so nothing about it is
## expressible against a pure static — the whole content of the defect is "this method is
## never called."
##
## Run: godot --path . --quit-after 700 res://tests/EffectStudioTexturePlayheadTest.tscn
## Grep the SUMMARY COUNT, not `[FAIL]`.

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const SPAN := "particle:for_each:1#2"
## E317's frames.json, read off disk when this was written. Cell k of the span above shows
## frameset `_CELLS[k]`, whose sole region is `_REGION[frameset]`.
const CELLS := [15, 15, 16, 22, 22, 22]
const REGION := {15: Rect2i(56, 8, 32, 32), 16: Rect2i(8, 40, 40, 40), 22: Rect2i(8, 40, 40, 40)}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioTexturePlayheadTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTexturePlayheadTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTexturePlayheadTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E317")):
		print("[SKIP] E317 assets not available")
		_passed += 1
		return
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	DebugOverlay.show_overlay()
	await _frames(40)
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SKIP] E317 not in catalogue")
		_passed += 1
		return
	page._load_effect(dir)
	await _frames(60)
	page._set_active_tab("texture")
	page._set_root(Target.span(SPAN))
	await _frames(50)

	var sc = page._sequence_canvas
	if sc == null or not page._sequence_panel.visible:
		_failed += 1
		print("  [FAIL] span %s has no sequence player to scrub" % SPAN)
		return
	var trace: Array = sc.get_trace()
	_assert_eq(trace.size(), CELLS.size(), "the span still decodes to %d cells" % CELLS.size())

	for op in range(mini(trace.size(), CELLS.size())):
		sc.select_op(op)
		await _frames(30)
		var want: int = CELLS[op]
		_assert_eq(int(trace[op].get("frameset", -1)), want,
			"cell %d still shows frameset %d" % [op, want])
		# THE REGRESSION. Before the fix these two diverged from op 2 onward.
		_assert_eq(page._texture_panel.bound_frameset(), page._shown_frameset(),
			"op %d: the tab is bound to the frameset the player is showing" % op)
		_assert_eq(page._texture_panel.bound_frameset(), want,
			"op %d: …and that frameset is %d" % [op, want])
		# …and the BOX follows, not just the address.
		var blocks: Array = []
		for r in page._texture_panel.canvas().group_regions_bound():
			blocks.append(r["block"])
		_assert_eq(blocks, [REGION[want]],
			"op %d: the drawn box is frameset %d's rect" % [op, want])

	# THE PARK SURVIVES AN EDIT. The author: "select the 3rd thumbnail, move the yellow box,
	# it auto selects the first thumbnail." `_render_current` ran `bind_sequence`, which
	# resets `_tick` and deselects, on every commit.
	sc.select_op(2)
	await _frames(30)
	_assert_eq(sc.selected_op(), 2, "parked on the 3rd cell")
	var fs_now: int = page._texture_panel.bound_frameset()
	var regions: Array = page._texture_panel.canvas().group_regions_bound()
	_assert_eq(regions.size(), 1, "…which draws one box")
	var b: Rect2i = regions[0]["block"]
	# Commit a drag exactly as releasing the mouse does.
	page._on_texture_tab_group_uv_changed(int(regions[0]["members"][0]),
		{"x": b.position.x + 2, "y": b.position.y + 2,
		"width": b.size.x, "height": b.size.y})
	await _frames(30)
	_assert_eq(sc.selected_op(), 2, "the drag leaves the 3rd cell parked")
	_assert_eq(page._texture_panel.bound_frameset(), fs_now,
		"…and the tab still shows that cell's frameset")
	var after: Array = page._texture_panel.canvas().group_regions_bound()
	_assert_eq(after[0]["block"], Rect2i(b.position.x + 2, b.position.y + 2, b.size.x, b.size.y),
		"…and the box is where it was dragged to, not back at the old rect")

	# A `frame` target pins its own frameset — the playhead must NOT move it.
	page._set_root(Target.frame(15, 0))
	await _frames(40)
	var pinned: int = page._texture_panel.bound_frameset()
	sc.select_op(3)
	await _frames(30)
	_assert_eq(page._texture_panel.bound_frameset(), pinned,
		"a frame target keeps its own frameset while the player moves off it")
	_assert_eq(page._texture_panel.bound_frame(), 0, "…and its own frame")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])
