extends Node
## Render the FEDS pair band into a fixed-size SubViewport so the WM never gets a vote
## (memory: studio-layout-measure-band-render-subviewport). Shoots the PANEL whole, which
## is what a legibility question needs; the band ARITHMETIC is measured separately.
##
##   EFFECT=E090 PAIR=3 ROLL=1 COLLAPSE=0 OUT=/tmp/roll VPW=1700 VPH=1100 \
##     godot --path . --quit-after 700 res://tools/probe_roll_shot.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E011"
	var pair_idx: int = int(OS.get_environment("PAIR")) if OS.has_environment("PAIR") else 0
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/roll"
	DirAccess.make_dir_recursive_absolute(out)
	var vpw: int = int(OS.get_environment("VPW")) if OS.has_environment("VPW") else 1700
	var vph: int = int(OS.get_environment("VPH")) if OS.has_environment("VPH") else 1100

	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[rollshot] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)
	page._set_root(Target.pair(pair_idx))
	await _frames(12)
	if not page._pair_panel.visible:
		print("[rollshot] %s pair %d did not open" % [want, pair_idx])
		get_tree().quit(1)
		return
	if OS.get_environment("UNWIND") == "1":
		page._pair_panel.set_all_unwound(true)
		await _frames(8)
	if OS.get_environment("COLLAPSE") != "":
		for tok in OS.get_environment("COLLAPSE").split(",", false):
			page._pair_panel.toggle_section(int(tok))
		await _frames(8)
	if OS.get_environment("ROLL") == "1":
		page._pair_panel.toggle_roll()
		await _frames(8)
	elif OS.has_environment("PPF"):
		page._timeline.axis.configure(page._timeline.axis.base_x,
				float(OS.get_environment("PPF")))
		page._timeline.axis.scroll_x = maxf(0.0,
				float(int(page._pair_panel._anchor.get("frame", 0)))
				* page._timeline.axis.pixels_per_frame)
		page._timeline.queue_redraw()
		await _frames(8)

	# Reparent JUST the pair panel into a fixed-size SubViewport and give it the width the
	# band would have on a maximised window. The panel is a pure Control that lays itself
	# out from `size` + its own state, so this is the real picture, not a mock.
	var panel = page._pair_panel
	var vp := SubViewport.new()
	vp.size = Vector2i(vpw, vph)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	panel.get_parent().remove_child(panel)
	vp.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = Vector2(vpw, vph)
	# The roll fits itself on the FIRST refit after a resize, so re-arm the fit now that
	# the panel finally has the width it will really have.
	if OS.get_environment("ROLL") == "1":
		panel._roll_fitted = false
	panel._refit()
	await _frames(10)
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var h := int(minf(float(vph), panel.custom_minimum_size.y + 4.0))
	img = img.get_region(Rect2i(0, 0, vpw, maxi(64, h)))
	var name := "%s_p%d%s" % [want, pair_idx, "_roll" if OS.get_environment("ROLL") == "1" else "_lanes"]
	img.save_png("%s/%s.png" % [out, name])
	var lay: Dictionary = panel.layout(panel._view, float(vpw), panel._state(),
			panel._axis_obj(), panel._anchor)
	var by_row := {}
	var rests := 0
	for b in lay.get("span_bars", []):
		var k := "t%d r%d" % [int(b.get("track", -1)), int(b.get("row", -1))]
		by_row[k] = int(by_row.get(k, 0)) + 1
		if bool(b.get("rest", false)):
			rests += 1
	print("[rollshot] bars=%d rests=%d rows=%s" % [(lay.get("span_bars", []) as Array).size(),
			rests, str(by_row)])
	print("[rollshot] wrote %s/%s.png  content_h=%d" % [out, name, int(panel.custom_minimum_size.y)])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
