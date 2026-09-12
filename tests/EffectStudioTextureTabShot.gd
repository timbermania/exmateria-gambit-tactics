extends Node
## NOT A GUARD — a screenshot rig for ADR-0130. The author reports by eye, so the tab has
## to be looked at, not just asserted about ([[render-atlas-crops-and-look-at-them]]).
##
## Shoots the same screen three ways: Values tab, Texture tab on a `frame` target (UV box +
## live handles + scope), and the Texture PAGE (dec. 8's widened gate).
##
## `content_scale_factor`, not `Window.size`: a tiling WM refuses a resize and the layout
## numbers stay at their old values, so you cannot tell it failed.
##
## Run: godot --path . --quit-after 600 res://tests/EffectStudioTextureTabShot.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _out: String = "user://shots"


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a screenshot rig for the ADR-0130 texture tab — its own header says NOT A GUARD")
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
		if String(d).ends_with("E019"):
			dir = d
	if dir == "":
		print("[SHOT] E019 not in catalogue"); get_tree().quit(1); return
	page._load_effect(dir)
	await _frames(60)

	page._set_root(Target.frame(0, 0))
	page._set_active_tab("values")
	await _frames(40)
	await _shoot(page, "1-values-tab")

	page._set_active_tab("texture")
	await _frames(40)
	await _shoot(page, "2-texture-tab-frame-target")

	# THE FOLDED STATE GETS ITS OWN SHOT. The author could fold the overlay and not unfold
	# it, and the suite was green throughout — the fold state round-tripped perfectly when
	# driven through `set_folded`, which is not the half that was broken. A picture of the
	# corner is how you see that there is nothing there that looks like a target.
	page._texture_panel.set_folded(true)
	await _frames(20)
	await _shoot(page, "7-texture-tab-folded")
	page._texture_panel.set_folded(false)
	await _frames(20)

	page._set_root(Target.frameset(10))
	await _frames(40)
	await _shoot(page, "5-texture-tab-frameset-outlines")

	page._set_root(Target.frameset(15))
	await _frames(40)
	await _shoot(page, "6-texture-tab-frameset-15")

	page._set_root(Target.emitter(0))
	await _frames(40)
	await _shoot(page, "3-texture-tab-emitter-target")

	page._set_active_tab("values")
	page._set_root(Target.texture())
	await _frames(40)
	await _shoot(page, "4-texture-page-with-picture")

	# PUT THE AUTHOR'S UI SCALE BACK BEFORE QUITTING. `DebugOverlay._notification` saves
	# `_dashboard.content_scale_factor` verbatim to `user_settings.json` on shutdown, so
	# this rig had been rewriting the dashboard's UI Scale to 0.55 on every run since it
	# was written — a screenshot rig that edits the author's settings as a side effect.
	if win != null:
		win.content_scale_factor = restore_scale
		await _frames(10)
		# WRITTEN BACK EXPLICITLY, not left to the shutdown save. The overlay ALSO persists
		# on `window_geometry_changed`, and this WM resizes the dashboard mid-run (measured
		# 1187x435 -> 2272x1069 inside one shoot), so 0.55 had already been committed to
		# disk long before the quit. Restoring the live value is not enough; the file has
		# to be corrected too.
		UserSettings.save_debug_window(win.position, win.size,
			DebugConfig.debug_overlay_visible, restore_scale)

	print("[SHOT] done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shoot(page, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("[SHOT] %s  body=%.0fx%.0f  tab=%s" % [
		path, page._body.size.x, page._body.size.y, page._active_tab])
	var c = page._texture_panel.canvas()
	print("        regions outlined=%d" % page._texture_panel.canvas().group_region_count())
	print("        panel vis=%s rect=%s | canvas rect=%s tex=%s draw_rect=%s scale=%.2f fit=%.3f" % [
		page._texture_panel.visible, page._texture_panel.get_rect(), c.get_rect(),
		"null" if c._texture == null else "%dx%d" % [c._texture.get_width(), c._texture.get_height()],
		c.current_draw_rect(), c.current_scale(),
		1.0 if c._texture == null else c.fit_scale(c.size,
			Vector2(c._texture.get_width(), c._texture.get_height()))])
	# EVERY TERM `_relayout` uses to split the row, so a layout question is answered by
	# reading this rig rather than by minting another probe.
	var col: Control = null
	for p2 in [page._frameset_panel, page._sequence_panel]:
		if p2 != null and p2.visible:
			col = p2
	var ovl = page._texture_panel.overlay()
	print("        OVERLAY rect=%s folded=%s  (port %s) -> %.1f%% of the port" % [
		ovl.get_rect(), page._texture_panel.is_folded(), c.size,
		100.0 * (ovl.size.x * ovl.size.y) / maxf(1.0, c.size.x * c.size.y)])
	print("        LEFT  panel_min=%.0f (canvas_min=%.0f)  assigned=%.0f  OVERFLOW=%.0f" % [
		page._texture_panel.get_combined_minimum_size().x,
		c.get_combined_minimum_size().x,
		page._texture_panel.size.x,
		maxf(0.0, page._texture_panel.get_combined_minimum_size().x - page._texture_panel.size.x)])
	print("        RIGHT %s rect=%s min=%.0f | inspector.content_width=%.0f focus.content_width=%.0f" % [
		"none" if col == null else col.name, "-" if col == null else str(col.get_rect()),
		0.0 if col == null else col.get_combined_minimum_size().x,
		page._inspector.content_width(),
		0.0 if page._focus_inspector == null else page._focus_inspector.content_width()])
	if col != null:
		print("        OVERLAP left_right_edge=%.0f right_left_edge=%.0f -> %s" % [
			page._texture_panel.position.x + page._texture_panel.get_rect().size.x,
			col.position.x,
			"YES %.0fpx" % maxf(0.0, page._texture_panel.position.x
				+ page._texture_panel.get_rect().size.x - col.position.x)
				if page._texture_panel.visible and page._texture_panel.position.x
					+ page._texture_panel.get_rect().size.x > col.position.x else "no"])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
