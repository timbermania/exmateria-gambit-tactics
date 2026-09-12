extends SceneTree

## Throwaway A/B capture rig for the Formation body/shadow calibration (#173,
## FORMATION_ELEMENT_PLACEMENT.md §7). Renders Formation.tscn into a SubViewport
## sized to the EXACT 256x240 FFT virtual framebuffer, so the saved PNG is 1:1
## with virtual pixels (no letterbox / stretch to undo — compare directly with the
## oracle roster_catalogue_captures/t04.png). Waits a few frames, screenshots, quits.
## Not shipped — run: godot --path . --script res://tools/probe_formation_capture.gd

var _frames := 0
var _viewport: SubViewport


func _initialize() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 240)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_viewport)
	var scene: Node = load("res://assets/scenes/Formation.tscn").instantiate()
	# `--isolate` renders unit bodies only (no orb/box/shadow/HP) for clean
	# visible-extent measurement against the oracle.
	if "--isolate" in OS.get_cmdline_user_args() or "--isolate" in OS.get_cmdline_args():
		scene.debug_bodies_only = true
	# Optional box-level overrides for the display-space composite tuning loop:
	#   --box-add=0.25 --box-sub=0.30
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--box-add="):
			scene.box_add_level = float(a.substr("--box-add=".length()))
		elif a.begins_with("--box-sub="):
			scene.box_sub_level = float(a.substr("--box-sub=".length()))
	_viewport.add_child(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img := _viewport.get_texture().get_image()
	var iso := "--isolate" in OS.get_cmdline_user_args() or "--isolate" in OS.get_cmdline_args()
	var path := "res://formation_iso_capture.png" if iso else "res://formation_skel_capture.png"
	img.save_png(path)
	print("FORMATION_CAPTURE_SAVED %dx%d -> %s"
		% [img.get_width(), img.get_height(), ProjectSettings.globalize_path(path)])
	return true
