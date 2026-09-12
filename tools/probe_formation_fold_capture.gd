extends Node3D

## Throwaway ROOT-viewport capture rig for the ADR-0077 formation fold (halo + box + occlusion).
## Unlike tools/probe_formation_capture.gd (which nests Formation in a SubViewport), this runs
## Formation as a child of the REAL scene root, so the CompositorAutopilot autoload — which watches
## get_viewport().get_camera_3d() on the ROOT viewport — actually attaches the engine fold to the
## Formation camera. A SubViewport capture would silently MISS the fold (the halo/box would look
## vanished even though they render fine in a real window). Sizes the window to the 256x240 virtual
## framebuffer so the PNG is ~1:1 with the oracle. Waits for the fold to settle, screenshots, quits.
##
## Run (headful, on the fork): godot --path . res://tools/probe_formation_fold_capture.tscn
## Optional: pass a selected cell to move the box, e.g. --sel=2,1
## Optional: pass a sort key to page the readout column, e.g. --sort=mp (§12.3.5:
##   hp/mp/ct/lv_exp/brave_faith). Set before the scene enters the tree so _ready
##   builds it directly (no live-page flash) — the A/B target for each sort state.

var _frames := 0
var _out := "res://formation_fold_capture.png"
var _pressed := ""   # "left"/"right": hold that L2/R2 button pressed for the capture


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(256, 240))
	var scene: Node = load("res://assets/scenes/Formation.tscn").instantiate()
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--sel="):
			var parts := a.substr("--sel=".length()).split(",")
			if parts.size() == 2:
				scene.selected_cell = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--out="):
			_out = a.substr("--out=".length())
		elif a.begins_with("--sort="):
			scene.active_sort_key = a.substr("--sort=".length())
		elif a.begins_with("--pressed="):
			_pressed = a.substr("--pressed=".length())
	add_child(scene)
	# Hold a pressed L2/R2 button for the capture (§12.3.5): pin the side WITHOUT a frame
	# countdown (set the field, not set_sort_key) so the flash persists past frame 6.
	if _pressed != "":
		scene._pressed_side = _pressed
		scene._build_sort_header()


func _process(_delta: float) -> void:
	_frames += 1
	# The fold needs a couple frames (autopilot attach on frame 1, seed/fold/resolve after).
	if _frames < 6:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("FORMATION_FOLD_CAPTURE_SAVED %dx%d -> %s"
		% [img.get_width(), img.get_height(), ProjectSettings.globalize_path(_out)])
	get_tree().quit()
