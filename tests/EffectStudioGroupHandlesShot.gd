extends Node
## NOT A GUARD — the screenshot rig for ADR-0130 dec. 12. Two entries in this project's
## memory and ADR-0089's own build notes all say the same thing about this exact surface:
## every number in the suite was still correct and only a screenshot caught the defect.
## So the N live boxes get looked at ([[render-atlas-crops-and-look-at-them]]).
##
## Shoots E066 frameset 59 — 5 distinct regions with 5 overlapping pairs, one of them
## (144,136,104,112) containing three of the others. That is the hardest picture the corpus
## offers for this feature and the one the grab-priority rule exists for.
##
## Run: godot --path . --quit-after 600 res://tests/EffectStudioGroupHandlesShot.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _out: String = "user://shots"


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a screenshot rig for ADR-0130 dec. 12 live boxes — its own header says NOT A GUARD")
	DirAccess.make_dir_recursive_absolute(_out)
	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	var page = scn._studio_page
	if page == null:
		print("[SHOT] no studio page"); get_tree().quit(1); return
	DebugOverlay.show_overlay()
	await _frames(40)

	var win: Window = page.get_window()
	var restore_scale: float = 1.0
	if win != null:
		restore_scale = win.content_scale_factor
		win.content_scale_factor = 0.55
	await _frames(20)

	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E066"):
			dir = d
	if dir == "":
		print("[SHOT] E066 not in catalogue"); get_tree().quit(1); return
	page._load_effect(dir)
	await _frames(60)

	page._set_active_tab("texture")
	page._set_root(Target.frameset(59))
	await _frames(40)
	await _shoot(page, "g1-frameset59-five-live-regions")

	page._set_root(Target.emitter(0))
	await _frames(60)
	await _shoot(page, "g2-emitter-target")

	# The `frame` target must be UNCHANGED: one live box, its dim siblings around it.
	page._set_root(Target.frame(59, 0))
	await _frames(40)
	await _shoot(page, "g3-frame-target-unchanged")

	# ── THE SCOPE CONTROL'S THREE READINGS (2026-08-21) ──
	#
	# The author asked what the member list was for, so the three states its label has to
	# distinguish get shot. Only the first was ever reachable from this rig, and it was the
	# one that read "No region" while five draggable boxes sat on the sheet.
	page._set_root(Target.frameset(59))
	await _frames(30)
	await _shoot(page, "g4-resting-five-regions-none-pointed-at")

	# POINTED AT one of the five. E066 frameset 59's (144,136,104,112) block holds frames 1
	# and 5, both in this frameset — the "all here" reading.
	page._texture_panel._on_group_region_hovered(1)
	await _frames(20)
	await _shoot(page, "g5-pointed-at-a-two-member-region")

	# PINNED, with the rail up — the state the whole scope toggle is for. Region 0 of E066
	# frameset 59 is used by 15 frames across 15 framesets, so this is also the rail's
	# scaling case: fifteen tiles in one port.
	page._texture_panel.canvas().set_locked_region(0)
	await _frames(20)
	await _shoot(page, "g5b-pinned-with-the-rail")

	# AND WITH A SUBSET TICKED, so the SPLIT wording and the dimmed tiles are both looked at.
	var scope0 = page._texture_panel.region_scope()
	var row: Array = scope0.region_framesets()
	if row.size() > 2:
		scope0.toggle_frameset(int(row[1]))
		scope0.toggle_frameset(int(row[2]))
		await _frames(20)
		await _shoot(page, "g5c-a-subset-ticked")

	# THE SPLIT, which is the reading the author actually hit and the one no shot had. E317
	# frameset 15's (56,8,32,32) is used by six frames in framesets 15/17/18/19/20/21 — one
	# here, five the view cannot show.
	var e317 := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			e317 = d
	if e317 != "":
		page._load_effect(e317)
		await _frames(60)
		page._set_active_tab("texture")
		page._set_root(Target.frameset(15))
		await _frames(40)
		page._texture_panel._on_group_region_hovered(2)
		await _frames(20)
		await _shoot(page, "g6-split-across-framesets-not-shown")

	if win != null:
		win.content_scale_factor = restore_scale
		await _frames(10)
		UserSettings.save_debug_window(win.position, win.size,
			DebugConfig.debug_overlay_visible, restore_scale)

	print("[SHOT] done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shoot(page, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	var c = page._texture_panel.canvas()
	var scope = page._texture_panel.region_scope()
	print("[SHOT] %s  tab=%s  bound=(fs %d, fr %d)" % [name, page._active_tab,
		page._texture_panel.bound_frameset(), page._texture_panel.bound_frame()])
	print("        group_live=%s  regions=%d  canvas_rect=%s  scale=%.2f" % [
		c.group_live, c.group_region_count(), c.get_rect(), c.current_scale()])
	for r in c.group_regions_bound():
		print("          block=%s members=%s anchors=%s" % [r["block"], r["members"], r["anchors"]])
	print("        scope visible=%s members=%d" % [
		"n/a" if scope == null else str(scope.visible),
		0 if scope == null else scope.members().size()])
	var rail = page._texture_panel.rail()
	print("        rail visible=%s rect=%s tiles=%d" % [
		"n/a" if rail == null else str(rail.visible),
		"n/a" if rail == null else str(rail.get_global_rect()),
		0 if rail == null else rail.row().size()])
	var ov = page._texture_panel.overlay()
	print("        overlay global_rect=%s  folded=%s" % [
		"n/a" if ov == null else str(ov.get_global_rect()),
		page._texture_panel.is_folded()])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
