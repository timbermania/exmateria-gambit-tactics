extends Node
## E2E proof of the KEY ROLL's vertical drag (ADR-0085 amendment 2026-08-21d §7): open a
## pair in roll mode, feed the panel REAL InputEvents for a press → motion → release, and
## read back the FEDS blob byte plus the bar's new row. Shoots before/after.
##
##   EFFECT=E011 PAIR=0 ROWS=-3 OUT=/tmp/roll \
##     godot --path . --quit-after 700 res://tools/probe_roll_keydrag.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E011"
	var pair_idx: int = int(OS.get_environment("PAIR")) if OS.has_environment("PAIR") else 0
	var rows: int = int(OS.get_environment("ROWS")) if OS.has_environment("ROWS") else -3
	var out: String = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/roll"
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
		print("[keydrag] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(25)
	page._set_root(Target.pair(pair_idx))
	await _frames(12)
	var panel = page._pair_panel
	if not panel.visible:
		print("[keydrag] pair did not open")
		get_tree().quit(1)
		return

	var vp := SubViewport.new()
	vp.size = Vector2i(1700, 1200)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	panel.get_parent().remove_child(panel)
	vp.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = Vector2(1700, 1200)
	panel.toggle_roll()
	panel._roll_fitted = false
	panel._refit()
	await _frames(10)

	# The widest AUTHORED, non-borrowed note bar on track A — the easiest thing to grab.
	var lay: Dictionary = panel.layout(panel._view, 1700.0, panel._state(),
			panel._axis_obj(), panel._anchor)
	var target := {}
	for b in lay.get("span_bars", []):
		if bool(b.get("rest", false)) or bool(b.get("ghost", false)) or bool(b.get("flowed", false)):
			continue
		if int(b.get("track", -1)) != 0:
			continue
		if target.is_empty() or (b["rect"] as Rect2).size.x > (target["rect"] as Rect2).size.x:
			target = b
	if target.is_empty():
		print("[keydrag] no draggable note bar")
		get_tree().quit(1)
		return
	var ev_index := int(target["event_index"])
	var bank = page._host.studio_effect_data().feds_bank
	var byte_at := -1
	for tr in panel._view.get("tracks", []):
		for n in (tr as Dictionary).get("notes", []):
			if int(n.get("event_index", -1)) == ev_index and int(tr.get("track_idx", -1)) \
					== int((panel._view.get("tracks", [])[0] as Dictionary).get("track_idx", -1)):
				byte_at = int(n.get("offset", -1)) + 1
	var before_byte: int = bank.raw[byte_at] if byte_at >= 0 else -1
	print("[keydrag] grabbing ordinal %d key=%d row=%d octave=%d data_byte@%d=%d"
			% [int(target["ordinal"]), int(target["relative_key"]), int(target["row"]),
			int(target["octave"]), byte_at, before_byte])
	_shoot(vp, panel, "%s/%s_p%d_key_before.png" % [out, want, pair_idx])

	var start: Vector2 = (target["rect"] as Rect2).get_center()
	_press(panel, start)
	# Cross the threshold VERTICALLY first, so the axis lock picks the key gesture.
	_motion(panel, start + Vector2(0.0, 6.0))
	await _frames(2)
	_motion(panel, start + Vector2(0.0, float(rows) * panel.ROLL_ROW_H))
	await _frames(6)
	_release(panel, start + Vector2(0.0, float(rows) * panel.ROLL_ROW_H))
	await _frames(12)

	var after_byte: int = bank.raw[byte_at] if byte_at >= 0 else -1
	var lay2: Dictionary = panel.layout(panel._view, 1700.0, panel._state(),
			panel._axis_obj(), panel._anchor)
	var moved := {}
	for b in lay2.get("span_bars", []):
		if int(b.get("track", -1)) == 0 and int(b.get("event_index", -1)) == ev_index \
				and not bool(b.get("ghost", false)) and not bool(b.get("flowed", false)):
			moved = b
	print("[keydrag] byte %d -> %d (key %d -> %d), row %d -> %d, delta_rows=%d"
			% [before_byte, after_byte, before_byte / 19, after_byte / 19,
			int(target["row"]), int(moved.get("row", -99)), rows])
	print("[keydrag] duration index PRESERVED: %s (%d -> %d)"
			% [str(before_byte % 19 == after_byte % 19), before_byte % 19, after_byte % 19])
	_shoot(vp, panel, "%s/%s_p%d_key_after.png" % [out, want, pair_idx])
	get_tree().quit(0)


func _shoot(vp, panel, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var h := int(minf(1200.0, panel.custom_minimum_size.y + 4.0))
	img.get_region(Rect2i(0, 0, 1700, maxi(64, h))).save_png(path)
	print("[keydrag] wrote %s" % path)


func _press(panel, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	panel._gui_input(e)


func _motion(panel, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	panel._gui_input(e)


func _release(panel, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	panel._gui_input(e)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
