extends Node
## Screenshot ANY effect's FEDS pair band — the quickest look at chip density and
## the stream ordinals (ADR-0085 2026-08-18b §5/§6) on a real, busy pair, with no
## stub required. Sibling of probe_feds_phantom, which needs one.
##
## Run (NOT headless):
##   EFFECT=E001 PAIR=0 OUT=/tmp/feds_shot UNWIND=1 COLLAPSE=0 \
##     godot --path . --quit-after 700 res://tools/probe_feds_pair_shot.tscn
##
## COLLAPSE is a comma-separated list of track ordinals to fold shut first — the pair
## band's viewport is short, so folding the track you are not looking at is how you get
## the other one's lanes fully in frame.

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E001"
	var pair_idx: int = int(OS.get_environment("PAIR")) if OS.has_environment("PAIR") else 0
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/feds_shot"
	DirAccess.make_dir_recursive_absolute(out)

	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[pairshot] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)
	var win: Window = page.get_window()
	# WIN lets a short pair band be given more room: the band SHARES the editor budget
	# with the inspector (Page._editor_band), so a taller window is the only lever that
	# reliably grows it without folding away the track you came to look at.
	win.size = Vector2i(int(OS.get_environment("WINW")) if OS.has_environment("WINW") else 1500,
			int(OS.get_environment("WINH")) if OS.has_environment("WINH") else 1000)
	await _frames(10)
	page._set_root(Target.pair(pair_idx))
	await _frames(10)
	if not page._pair_panel.visible:
		print("[pairshot] %s pair %d did not open" % [want, pair_idx])
		get_tree().quit(1)
		return
	if OS.get_environment("UNWIND") == "1":
		page._pair_panel.set_all_unwound(true)
		await _frames(10)
	# PPF pins the shared TimelineAxis zoom, so a shot can be taken at the SAME scale the
	# complaint was taken at — TimelineAxis.MAX_PPF (40) is where the 2026-08-21 crammed-
	# notes screenshot sits, and it is the panel's ceiling, not a zoom you can escape.
	if OS.has_environment("PPF"):
		page._timeline.axis.configure(page._timeline.axis.base_x,
				float(OS.get_environment("PPF")))
		# configure() leaves scroll_x alone, and a pinned zoom on an old scroll puts the
		# pair off the right edge. Scroll to the pair's FIRE frame, not to frame 0 — the
		# panel projects at `fire + seconds×30`, so frame 0 is usually empty lane.
		page._timeline.axis.scroll_x = maxf(0.0,
				float(int(page._pair_panel._anchor.get("frame", 0)))
				* page._timeline.axis.pixels_per_frame)
		page._timeline.queue_redraw()
		page._pair_panel.queue_redraw()
		await _frames(10)
	# ROLL=1 opens the KEY ROLL (ADR-0085 amendment 2026-08-21d) instead of the lanes
	# reading of the time lane. The roll fits itself to the pair on open, so PPF above is
	# about the LANES shot; the roll's own zoom is ROLLPPF.
	if OS.get_environment("ROLL") == "1":
		page._pair_panel.toggle_roll()
		await _frames(10)
		if OS.has_environment("ROLLPPF"):
			page._pair_panel._roll_axis_obj().configure(page._pair_panel._roll_axis_obj().base_x,
					float(OS.get_environment("ROLLPPF")))
			page._pair_panel._refit()
			await _frames(6)
	if OS.get_environment("COLLAPSE") != "":
		for tok in OS.get_environment("COLLAPSE").split(",", false):
			page._pair_panel.toggle_section(int(tok))
		await _frames(10)
	# Re-apply the window size AFTER _set_root: the page re-latches its top-panel height
	# per root, and on some roots that resizes the window back under us.
	win.size = Vector2i(int(OS.get_environment("WINW")) if OS.has_environment("WINW") else 1500,
			int(OS.get_environment("WINH")) if OS.has_environment("WINH") else 1000)
	await _frames(20)
	var tracks: Array = page._pair_panel._view.get("tracks", [])
	var sizes: Array = []
	for tv in tracks:
		sizes.append("%d notes + %d cmds" % [(tv.get("notes", []) as Array).size(),
				(tv.get("commands", []) as Array).size()])
	print("[pairshot] %s pair %d — %s" % [want, pair_idx, ", ".join(sizes)])
	print("[pairshot] window=%s scroll=%s panel_min=%s" % [str(win.size),
			str(page._pair_scroll.get_global_rect()), str(page._pair_panel.custom_minimum_size)])
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	var r: Rect2 = page._pair_scroll.get_global_rect()
	var crop := Rect2i(Vector2i(r.position), Vector2i(r.size)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size()))
	if crop.size.x > 4 and crop.size.y > 4:
		img = img.get_region(crop)
	img.save_png("%s/%s_p%d.png" % [out, want, pair_idx])
	print("[pairshot] wrote %s/%s_p%d.png" % [out, want, pair_idx])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
