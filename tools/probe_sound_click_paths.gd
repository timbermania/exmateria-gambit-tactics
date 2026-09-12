extends Node
## Which CLICK on a sound trigger seeds the all-in-one chain page, and which does not.
## A sound lane row stacks several hit targets on the same few pixels — the fire handle,
## the anchor handle, the fixed-width select marker, the read-only ghost bar — and they do
## NOT all route through _on_span_selected. This presses at each x and reports the nav.
##
##   EFFECT=E317 godot --path . --quit-after 700 res://tools/probe_sound_click_paths.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E317"
	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[clicks] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)
	var tl = page._timeline
	tl.rebuild_layout()
	await _frames(4)

	# The first sound span that WOULD seed a chain if routed through _on_span_selected.
	var target := ""
	for lane in tl._score.get("lanes", []):
		for sp in (lane as Dictionary).get("spans", []):
			var sid := str((sp as Dictionary).get("id", ""))
			if target == "" and sid.begins_with("sound:") \
					and not page._pair_nav_for_sound_span(sid).is_empty():
				target = sid
	if target == "":
		print("[clicks] %s has no chain-seeding sound trigger" % want)
		get_tree().quit(1)
		return
	print("[clicks] target span = %s" % target)

	var probes: Array = []
	for f in tl._fire_rects:
		if str(f["span_id"]) == target:
			probes.append({"what": "fire handle", "rect": f["rect"]})
	for a in tl._anchor_rects:
		if str(a["span_id"]) == target:
			probes.append({"what": "anchor handle", "rect": a["rect"]})
	for s in tl._span_rects:
		if str((s["span"] as Dictionary).get("id", "")) == target:
			probes.append({"what": "select marker", "rect": s["rect"]})
	for g in tl._ghost_rects:
		if str(g["span_id"]) == target:
			var gr: Rect2 = g["rect"]
			probes.append({"what": "ghost bar (left)", "rect": Rect2(gr.position.x + 2.0, gr.position.y, 1.0, gr.size.y)})
			probes.append({"what": "ghost bar (middle)", "rect": Rect2(gr.get_center().x, gr.position.y, 1.0, gr.size.y)})

	for p in probes:
		var r: Rect2 = p["rect"]
		var at: Vector2 = r.get_center()
		var hit: Dictionary = tl.hit_test(at)
		# Reset, then press exactly as the author would.
		page._nav = []
		page._nav_chain = false
		_press(tl, at)
		_release(tl, at)
		await _frames(6)
		var kinds: Array = []
		for t in page._nav:
			kinds.append(str(t.get("kind", "?")))
		print("[clicks] %-20s x=%7.1f w=%5.1f  hit=%-8s -> nav=%-28s chain=%s"
				% [str(p["what"]), r.position.x, r.size.x, str(hit.get("kind", "?")),
				str(kinds), str(page._nav_chain)])
	get_tree().quit(0)


func _press(tl, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	tl._gui_input(e)


func _release(tl, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	tl._gui_input(e)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
