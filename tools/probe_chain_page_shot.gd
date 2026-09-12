extends Node
## Shoot the WHOLE studio page after a sound-event click — the "all-in-one sound page"
## (ADR-0085 amendment 2026-08-21 chain inspection). Rendered into a fixed-size
## SubViewport so the tiling WM never gets a vote on the page height.
##
##   EFFECT=E026 OUT=/tmp/chain VPW=1700 VPH=1220 \
##     godot --path . --quit-after 700 res://tools/probe_chain_page_shot.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E026"
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/chain"
	DirAccess.make_dir_recursive_absolute(out)
	var vpw: int = int(OS.get_environment("VPW")) if OS.has_environment("VPW") else 1700
	var vph: int = int(OS.get_environment("VPH")) if OS.has_environment("VPH") else 1220

	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[chainshot] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)

	var vp := SubViewport.new()
	vp.size = Vector2i(vpw, vph)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var parent = page.get_parent()
	parent.remove_child(page)
	vp.add_child(page)
	page.position = Vector2.ZERO
	page.size = Vector2(vpw, vph)
	await _frames(12)

	# WHY a click seeds or does not, per sound span — the diagnosis the picture cannot give.
	var env_empty: bool = page._sound_env.is_empty()
	print("[chainshot] sound_env empty=%s  keys=%s" % [str(env_empty),
			str(page._sound_env.keys()) if not env_empty else "-"])
	print("[chainshot] sound doc phases=%s" % str(page._effect_data.sound.keys()))
	# EVERY span on every SOUND lane, whatever its id shape — the trigger bar and the ghost
	# are two different objects on one row, and only one of them may be seeding.
	for lane in page._timeline._score.get("lanes", []):
		var ld: Dictionary = lane
		var lid := "%s %s %s" % [str(ld.get("id", "")), str(ld.get("label", "")), str(ld.get("kind", ""))]
		if not lid.to_lower().contains("sound"):
			continue
		print("[chainshot] LANE %s spans=%d" % [lid, (ld.get("spans", []) as Array).size()])
		for sp in ld.get("spans", []):
			var d: Dictionary = sp
			print("[chainshot]    span id=%-26s role=%-10s seeds=%-5s keys=%s"
					% [str(d.get("id", "?")), str(d.get("role", "event")),
					str(not page._pair_nav_for_sound_span(str(d.get("id", ""))).is_empty()),
					str(d.keys())])
	for sid in _sound_event_ids(page):
		var role := str(_role_of(page, sid))
		var snd := int(page._span_sound_id(sid))
		var pair := -1
		if not env_empty:
			pair = int(page.GhostProjector.resolve_pair_idx(page._sound_env["sound_containers"], snd)) 					if page.get("GhostProjector") != null else -1
		print("[chainshot]   %-26s role=%-10s sound_id=%d seeds=%s"
				% [sid, role, snd, str(not page._pair_nav_for_sound_span(sid).is_empty())])
	var span_id: String = OS.get_environment("SPAN")
	if span_id == "":
		for sid in _sound_event_ids(page):
			if not page._pair_nav_for_sound_span(sid).is_empty():
				span_id = sid
				break
	if span_id == "":
		# Nothing seeds — click the first sound event anyway, because the point of this probe
		# is to see what the AUTHOR gets, not to only shoot the happy path.
		var all := _sound_event_ids(page)
		if all.is_empty():
			print("[chainshot] %s has no sound events at all" % want)
			get_tree().quit(1)
			return
		span_id = str(all[0])
		print("[chainshot] NOTHING SEEDS — clicking %s to shoot what the author gets" % span_id)
	# PRESS the trigger the way a mouse does, through the timeline's own routing, rather than
	# calling _on_span_selected: the two are NOT the same door (the fire handle covers the
	# select marker), and calling the handler directly is exactly what hid the 2026-08-21e bug.
	page._timeline.rebuild_layout()
	var at := _press_point(page, span_id)
	if at.x >= 0.0:
		print("[chainshot] pressing %s at %s -> hit=%s" % [span_id, str(at),
				str(page._timeline.hit_test(at).get("kind", "?"))])
		_press(page._timeline, at)
		_release(page._timeline, at)
	else:
		page._on_span_selected(span_id)
	await _frames(20)

	var kinds: Array = []
	for t in page._nav:
		kinds.append(str(t.get("kind", "?")))
	print("[chainshot] clicked %s → nav=%s chain=%s" % [span_id, str(kinds), str(page._nav_chain)])
	var groups: Array = []
	for s in page._sections_for_render(page._timeline._score):
		groups.append("%s%s" % [str(s.get("title", s.get("fold_key", "?"))),
				"(folded)" if bool(s.get("collapsed", false)) else ""])
	print("[chainshot] sections=%s" % str(groups))
	print("[chainshot] inspector_content_h=%d  pair_panel_visible=%s  pair_want=%d"
			% [int(page._inspector.content_height()), str(page._pair_panel.visible),
			int(page._pair_panel.custom_minimum_size.y)])
	print("[chainshot] inspector_rect=%s pair_scroll_rect=%s"
			% [str(page._inspector.get_rect()), str(page._pair_scroll.get_rect())])

	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s_chain.png" % [out, want])
	print("[chainshot] wrote %s/%s_chain.png" % [out, want])
	get_tree().quit(0)


## Where a mouse would land to select `span_id` — its own select rect's centre.
func _press_point(page, span_id: String) -> Vector2:
	for h in page._timeline._span_rects:
		if str((h["span"] as Dictionary).get("id", "")) == span_id:
			return (h["rect"] as Rect2).get_center()
	return Vector2(-1.0, -1.0)


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


func _role_of(page, span_id: String) -> String:
	for lane in page._timeline._score.get("lanes", []):
		for span in (lane as Dictionary).get("spans", []):
			if str((span as Dictionary).get("id", "")) == span_id:
				return str((span as Dictionary).get("role", "event"))
	return "?"


func _sound_event_ids(page) -> Array:
	var out: Array = []
	for lane in page._timeline._score.get("lanes", []):
		for span in (lane as Dictionary).get("spans", []):
			var sid := str((span as Dictionary).get("id", ""))
			if sid.begins_with("sound"):
				out.append(sid)
	return out


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
