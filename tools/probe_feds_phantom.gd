extends Node
## Boot the Effect Studio straight onto a stub pair and capture the FEDS lane panel
## with its NoEnd phantom folded, then unfolded (ADR-0085 2026-08-18). The quickest
## way to LOOK at the feature without hunting for a stub by hand.
##
## Run (NOT headless):
##   godot --path . --quit-after 700 res://tools/probe_feds_phantom.tscn
## Env: EFFECT=E317  PAIR=0  OUT=/tmp/feds_phantom

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E317"
	var pair_idx: int = int(OS.get_environment("PAIR")) if OS.has_environment("PAIR") else 0
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/feds_phantom"
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
		print("[phantom] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)
	# A tall window: the band contends with the inspector for height, and an
	# unfolded phantom is the widest thing it ever has to hold.
	var win: Window = page.get_window()
	win.size = Vector2i(1500, 1000)
	await _frames(10)
	page._set_root(Target.pair(pair_idx))
	await _frames(10)
	if not page._pair_panel.visible:
		print("[phantom] pair %d did not open" % pair_idx)
		get_tree().quit(1)
		return

	var stub := -1
	for t in range((page._pair_panel._view.get("tracks", []) as Array).size()):
		var tv: Dictionary = page._pair_panel._view["tracks"][t]
		if not (tv.get("flow_through", {}) as Dictionary).is_empty():
			stub = t
	if stub < 0:
		print("[phantom] %s pair %d has no stub — nothing to fold" % [want, pair_idx])
		get_tree().quit(0)
		return
	var ft: Dictionary = (page._pair_panel._view["tracks"][stub] as Dictionary).get("flow_through", {})
	print("[phantom] %s pair %d — stub is track %d, flows into track %d, bend %+d"
			% [want, pair_idx, stub, int(ft.get("into_track", -1)),
			int(ft.get("own_pitch_bend_total", 0))])
	await _shot(page, out, "folded")
	page._pair_panel.toggle_loop(stub, -1)
	await _frames(10)
	await _shot(page, out, "unfolded")
	print("[phantom] wrote %s/{folded,unfolded}.png" % out)
	get_tree().quit(0)


func _shot(page, out: String, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	var r: Rect2 = page._pair_scroll.get_global_rect()
	var crop := Rect2i(Vector2i(r.position), Vector2i(r.size)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size()))
	if crop.size.x > 4 and crop.size.y > 4:
		img = img.get_region(crop)
	img.save_png("%s/%s.png" % [out, tag])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
