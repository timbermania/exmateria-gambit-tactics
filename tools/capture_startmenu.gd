extends SceneTree

## Throwaway capture for the Formation START sub-menu port (§15.20), rendered OVER the
## detail screen with the engine fold ACTIVE (added to `root` so the CompositorAutopilot
## autoload attaches to the scene camera — the real overlay-depth path, unlike a bare
## SubViewport where the fold does not reach the frame and the detail occludes the menu).
## (`_fold_owns()` was the per-class copy of the predicate; ADR-0191 dec. 1 retired all
## fourteen of them into `Fold.owns()`, which is a property of the BUILD and so is true
## here either way — what a bare SubViewport loses is the compositor attachment, not the
## predicate.) Grabs on
## frame_post_draw after the box-open settles, saves the whole window, quits.
##
## Run (NOT headless):
##   godot --path . -s res://tools/capture_startmenu.gd -- --shot=/tmp/startmenu.png --settle=30

var _scene: Node
var _f := 0
var _did := false
var _quit := false
var _shot := "/tmp/startmenu_port.png"
var _settle := 30


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shot="):
			_shot = a.substr("--shot=".length())
		elif a.begins_with("--settle="):
			_settle = int(a.substr("--settle=".length()))
	_scene = load("res://src/ui3/detail/StartActionMenu.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[startmenu-cap] booting, fold-active, shot -> %s" % _shot)


func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	if _f >= _settle and not _did:
		_did = true
		var img := root.get_texture().get_image()
		img.save_png(_shot)
		var vp := root.get_viewport().get_visible_rect().size
		print("[startmenu-cap] ===== CAPTURED f=%d viewport=%s -> %s =====" % [_f, str(vp), _shot])
		_quit = true
