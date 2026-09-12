extends Node
## NOT A GUARD — the screenshot rig for the colour column's minimum age width. The author's
## report is about a PICTURE (*"things get crazy on the keyframes"*), and this family has
## shipped a wrong picture under a fully green suite four times
## ([[render-atlas-crops-and-look-at-them]]).
##
## Shoots the corpus's worst case and a middling one:
##   E088 em1 — life 128 in ONE row, the "one frame and held" case verbatim. 0.17px an age
##              at the old fixed 22px band; 106 of its 128 ages unreachable by any click.
##   E485 em8 — life 130 over two rows.
##
## Run: godot --path . --quit-after 900 res://tests/ColourColumnWidthShot.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const LifeColumn = preload("res://src/effects/studio/ColourLifeColumn.gd")

var _out: String = "user://shots"


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a screenshot rig for the colour column minimum age width — its own header says NOT A GUARD")
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
		# this one opens with — 621x688 on the first run, where the sequence panel hangs off
		# the right edge and the ribbon is not in the picture at all.
		win.size = Vector2i(1500, 1000)
	await _frames(30)

	for spec in [["E088", 1], ["E485", 8], ["E019", 0]]:
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
		# BEFORE: the band pinned at its floor, which is what every emitter got until
		# 2026-08-21. Driven through `band_max` rather than by reverting, so the two shots
		# are the same run, the same window and the same emitter.
		LifeColumn.band_max = LifeColumn.band_width
		page._bind_life_column()
		await _frames(20)
		await _shoot(page, "w-%s-em%d-a-before" % [spec[0], int(spec[1])])
		LifeColumn.band_max = 150.0
		page._bind_life_column()
		await _frames(20)
		await _shoot(page, "w-%s-em%d-b-after" % [spec[0], int(spec[1])])

	if win != null:
		win.content_scale_factor = restore
		win.size = restore_size
		await _frames(10)
		UserSettings.save_debug_window(win.position, restore_size,
			DebugConfig.debug_overlay_visible, restore)
	print("[SHOT] done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shoot(page, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = page.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	# AND A CROP OF THE COLUMN ITSELF, taken here rather than guessed from the outside. The
	# debug window's content scale and its persisted size both move between runs, so a crop
	# computed off the printed global rect lands on empty background as often as not — the
	# rig knows the transform, nothing downstream does.
	var lc0 = page._sequence_life_column
	if lc0 != null and lc0.visible:
		var vp: Viewport = page.get_viewport()
		var k: float = float(img.get_width()) / maxf(1.0, vp.get_visible_rect().size.x)
		var gr: Rect2 = lc0.get_global_rect().grow(6.0)
		var r := Rect2i((gr.position * k).floor(), (gr.size * k).ceil())
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 2 and r.size.y > 2:
			img.get_region(r).save_png("%s/%s-crop.png" % [_out, name])
	var lc = page._sequence_life_column
	var rows: Array = page._sequence_life_rows
	var widest := 0
	for r in rows:
		widest = maxi(widest, maxi(1, int(r.get("ticks", 1))))
	print("[SHOT] %s" % name)
	print("        rows=%d widest_row=%d ticks  slot=%s  cols=%s"
		% [rows.size(), widest,
			"n/a" if page._sequence_life_slot == null else str(page._sequence_life_slot.size),
			str(page._strip_split)])
	if lc != null:
		print("        band floor=%.0f  ceiling=%.1f  granted=%.1f  rect=%s  px/age=%.2f"
			% [LifeColumn.band_width, page._life_band_ceiling, lc.band(),
				lc.get_global_rect(), lc.size.x / maxf(1.0, float(widest))])
		print("        keyframes=%d  visible=%s" % [lc._keyframes.size(), lc.visible])
	# DOES THE WRAP ACTUALLY HAVE THE WIDTH IT ASKS FOR? The page bids the panel 128px wider
	# for the strip's extra columns; the slot's own declared minimum is ONE pair.
	var vis := 0
	for pr in page._sequence_life_pairs:
		if (pr as Control).visible:
			vis += 1
			print("        pair rect=%s" % str((pr as Control).get_global_rect()))
	print("        visible pairs=%d  scroll rect=%s  panel=%s"
		% [vis, str(page._sequence_strip_scroll.get_global_rect()),
			str(page._sequence_panel.get_global_rect()) if page._sequence_panel != null else "n/a"])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
