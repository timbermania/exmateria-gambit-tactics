extends Node
## NOT A GUARD — the screenshot rig for the colour picker's authoring space (ADR-0089
## decision 4, amended 2026-08-21: the picker authors the CURVE and the sprite's bound is
## reported rather than imposed). The report is about a PICTURE — *"the color picker to get
## the keyframe color really just isn't working"* — and this family has shipped a wrong
## picture under a fully green suite ([[render-atlas-crops-and-look-at-them]]).
##
## What the crops have to show, on an emitter whose sprite would have crushed the pick:
##   • the grid HOLDS white after a pick — under the old model it was clamped to `S` and,
##     because the panel re-seeds every drag frame, dragged back down under the cursor;
##   • the RENDERS-AS swatch beside it is `S ⊙ (1,1,1)` = the sprite's own colour, so the
##     bound is on screen instead of behind the pick;
##   • the dead-channel tag names the channel when the sprite has one.
##
## Subjects, from `tools/census_colour_picker_reach.gd`:
##   E008 em0 — S=(120,96,0): blue DEAD, and the two live channels under half scale.
##   E039 em2 — S=(184,104,16): all three live, blue at 6% of full.
##
## Run: godot --path . --quit-after 900 res://tests/ColourPickerReachShot.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const ColourLifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")
const SequenceThumbnail = preload("res://src/effects/studio/SequenceThumbnail.gd")
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")

var _out: String = "user://shots"


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a screenshot rig for the colour picker authoring space (ADR-0089 dec. 4) — its own header says NOT A GUARD")
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
	var restore_size := Vector2i(1261, 1390)
	if win != null:
		restore = win.content_scale_factor
		restore_size = win.size
		win.content_scale_factor = 0.55
		# The debug window's size is PERSISTED, so whatever the last rig left it at is what
		# this one opens with. The picker's grid only appears when the column's slack affords
		# 439px, so a short window shoots the header alone and says nothing about the grid.
		win.size = Vector2i(1500, 1200)
	await _frames(30)

	for spec in [["E008", 0], ["E039", 2]]:
		var dir := ""
		for d in page._effect_dirs:
			if String(d).ends_with(String(spec[0])):
				dir = d
		if dir == "":
			print("[SHOT] %s not in catalogue" % spec[0])
			continue
		page._load_effect(dir)
		await _frames(60)
		page._set_root(Target.emitter(int(spec[1])))
		await _frames(60)
		if page._sequence_life_column == null or not page._sequence_life_column.visible:
			print("[SHOT] %s em%d has no colour column — colour is off on it"
				% [spec[0], int(spec[1])])
			continue
		var n: int = page._sequence_ribbon.colors().size()
		var age: int = clampi(int(n * 0.5), 1, maxi(1, n - 1))
		var hit: Dictionary = _cell_of(page, age)
		var cell: Rect2 = hit.get("rect", Rect2())
		if cell.size.x <= 0.0:
			print("[SHOT] %s em%d: no cell for age %d" % [spec[0], int(spec[1]), age])
			continue
		hit["col"]._gui_input(_click_at(cell.position + cell.size * 0.5))
		await _frames(30)
		var s: Color = EmitterSpriteColor.representative(page._effect_data, int(spec[1]))
		await _shoot(page, "pick-%s-em%d-a-seeded" % [spec[0], int(spec[1])], s)
		# PICK WHITE — the corner the author could not reach. `pick` is the same entry the
		# widget's own `color_changed` uses, so this is the real path and not a back door.
		page._colour_picker.color = Color.WHITE
		page._colour_picker.pick(Color.WHITE)
		await _frames(30)
		await _shoot(page, "pick-%s-em%d-b-white" % [spec[0], int(spec[1])], s)

	if win != null:
		win.content_scale_factor = restore
		win.size = restore_size
		await _frames(10)
		UserSettings.save_debug_window(win.position, restore_size,
			DebugConfig.debug_overlay_visible, restore)
	print("[SHOT] done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shoot(page, name: String, s: Color) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	# THE PANEL ITSELF, cropped here rather than guessed from the outside — the debug window's
	# content scale and its persisted size both move between runs, so a crop computed off a
	# printed global rect lands on background as often as not.
	var panel: Control = page._colour_picker_panel
	if panel != null and panel.visible:
		var vp: Viewport = page.get_viewport()
		var k: float = float(img.get_width()) / maxf(1.0, vp.get_visible_rect().size.x)
		var gr: Rect2 = panel.get_global_rect().grow(6.0)
		var r := Rect2i((gr.position * k).floor(), (gr.size * k).ceil())
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 2 and r.size.y > 2:
			img.get_region(r).save_png("%s/%s-crop.png" % [_out, name])
	var p = page._colour_picker
	print("[SHOT] %s" % name)
	print("        S=(%d,%d,%d)  swatch=(%d,%d,%d)  renders_as=(%d,%d,%d)  tag=%s"
		% [s.r * 255, s.g * 255, s.b * 255,
			p.color.r * 255, p.color.g * 255, p.color.b * 255,
			p.renders_as().r * 255, p.renders_as().g * 255, p.renders_as().b * 255,
			"(none)" if p.dead_channel_tag() == "" else p.dead_channel_tag()])
	print("        grid visible=%s  panel=%s  head_floor=%.0f"
		% [str(p.visible), str(panel.get_global_rect()) if panel else "n/a",
			page.picker_head_h])


func _cell_of(page, age: int) -> Dictionary:
	for lc in page._sequence_life_columns:
		var r: Rect2 = ColourLifeColumn.rect_of_frame(age, lc._rows, SequenceThumbnail.SIDE,
			lc.size.x)
		if r.size.x > 0.0:
			return {"col": lc, "rect": r}
	return {"col": page._sequence_life_column, "rect": Rect2()}


func _click_at(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
