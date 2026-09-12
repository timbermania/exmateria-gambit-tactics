extends Node
## NOT A GUARD — the screenshot rig for ADR-0099 dec. 5e. The unit and wiring tests both
## assert the MODE survives a thumbnail change; this exists because a persisted mode is only
## safe if the control SAYS SO, and "the toggle row is present and correct" is a claim about
## a picture ([[render-atlas-crops-and-look-at-them]]). The same surface has already shipped
## a control that passed every predicate at zero pixels wide.
##
## Run: godot --path . --quit-after 600 res://tests/RegionScopePersistShot.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const RegionScope = preload("res://src/effects/studio/FramesetRegionScope.gd")

var _out: String = "user://shots"


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a screenshot rig for the ADR-0099 dec. 5e scope toggle — its own header says NOT A GUARD")
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
	var restore: float = 1.0
	if win != null:
		restore = win.content_scale_factor
		win.content_scale_factor = 0.55
	await _frames(20)

	# E317 frameset 15: the region at (56,8,32,32) reaches six frames across framesets
	# 15/17/18/19/20/21, which is the author's own reported case ("only thumbnail 1
	# changed. I thought the change was effect wide?") and the one where a scope that
	# resets on a thumbnail change is unusable.
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E317"):
			dir = d
	if dir == "":
		print("[SHOT] E317 not in catalogue"); get_tree().quit(1); return
	page._load_effect(dir)
	await _frames(60)
	page._set_active_tab("texture")
	page._set_root(Target.frameset(15))
	await _frames(40)

	var panel = page._texture_panel
	# NO POINTING NEEDED. E317 frameset 15 samples exactly one region, which is 90.5% of the
	# corpus, so the resting bind resolves it on arrival and the blast radius can be stated
	# without the author aiming at anything. (Driving `_on_group_region_locked` with a member
	# index the frameset does not have re-binds to NO region — the rig lying, not the
	# surface: frameset 15 has one frame, index 0.)
	await _shoot(page, "s1-effect-wide-at-rest")

	var scope = panel.region_scope()
	scope.set_scope(RegionScope.SCOPE_FRAMESET)
	await _frames(20)
	await _shoot(page, "s2-narrowed-to-frameset-wide")

	# THE GESTURE THE AUTHOR REPORTED: change the thumbnail. Every one of these used to
	# land back on `Effect`.
	page._set_root(Target.frameset(17))
	await _frames(40)
	await _shoot(page, "s3-after-the-thumbnail-change")

	# And a hand-built subset, which is the one thing that does NOT survive — it degrades
	# to `Frameset`, visibly, on the same radio.
	page._set_root(Target.frameset(15))
	await _frames(40)
	var row: Array = scope.region_framesets()
	if row.size() > 2:
		scope.toggle_frameset(int(row[1]))
		await _frames(20)
		await _shoot(page, "s4-a-subset-ticked")
		page._set_root(Target.frameset(0))
		await _frames(40)
		await _shoot(page, "s5-subset-degraded-on-a-new-region")

	if win != null:
		win.content_scale_factor = restore
		await _frames(10)
		UserSettings.save_debug_window(win.position, win.size,
			DebugConfig.debug_overlay_visible, restore)
	print("[SHOT] done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shoot(page, name: String) -> void:
	await RenderingServer.frame_post_draw
	page.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	var scope = page._texture_panel.region_scope()
	var modes := ["Effect", "Frameset", "Pick"]
	var pressed := "none"
	var texts: Array = []
	if scope != null:
		for b in scope._scope_buttons:
			texts.append("%s%s" % [b.text, "*" if b.button_pressed else ""])
			if b.button_pressed:
				pressed = modes[int(b.get_meta("scope_mode", 0))]
	print("[SHOT] %s  bound=(fs %d, fr %d)" % [name,
		page._texture_panel.bound_frameset(), page._texture_panel.bound_frame()])
	print("        scope=%s  row=%s  members=%d  selected=%d" % [pressed, texts,
		0 if scope == null else scope.members().size(),
		0 if scope == null else scope.selected_members().size()])
	var rail = page._texture_panel.rail()
	if rail != null:
		print("        rail visible=%s tiles=%d rect=%s" % [
			rail.visible, rail.row().size(), rail.get_global_rect()])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
