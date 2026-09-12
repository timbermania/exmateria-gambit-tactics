extends Node
## Throwaway visual harness: boot the Formation scene, open the F3 dashboard, and
## screenshot the dashboard WINDOW to /tmp/dashboard_capture.png — so an agent can
## see exactly what the user sees in the Designer cell.

func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a throwaway visual harness — it screenshots the F3 dashboard window and asserts nothing")
	var scene = load("res://assets/scenes/Formation.tscn").instantiate()
	add_child(scene)
	for i in 40:
		await get_tree().process_frame
	var overlay = get_node("/root/DebugOverlay")
	overlay.show_overlay()
	for i in 40:
		await get_tree().process_frame
	var dash: Window = overlay.get("_dashboard")
	if dash == null:
		print("[dashboard_capture] NO DASHBOARD")
		get_tree().quit(1)
		return
	var img: Image = dash.get_texture().get_image()
	img.save_png("/tmp/dashboard_capture.png")
	print("[dashboard_capture] saved %dx%d" % [img.get_width(), img.get_height()])
	# Expand the "Detail / Status Screen" panel fold + its "Equip picker" section, then re-capture.
	var folds: Array = (dash.get("_cell_folds") as Dictionary).get(BaseDebugPanel.Category.DESIGNER, [])
	for f: Dictionary in folds:
		var t := f["toggle"] as Button
		if t.text.contains("Detail / Status Screen"):
			t.button_pressed = true   # emits toggled → refresh shows the content
	for i in 10:
		await get_tree().process_frame
	for btn in dash.find_children("", "Button", true, false):
		if (btn as Button).toggle_mode and (btn as Button).text.contains("Equip picker"):
			(btn as Button).button_pressed = true
	for i in 10:
		await get_tree().process_frame
	var img2: Image = dash.get_texture().get_image()
	img2.save_png("/tmp/dashboard_capture_expanded.png")
	print("[dashboard_capture] saved expanded %dx%d" % [img2.get_width(), img2.get_height()])
	get_tree().quit(0)
