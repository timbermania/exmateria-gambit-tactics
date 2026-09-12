extends SceneTree
## Auto-capture the chapel scenario swoop to PNGs so the H1 back-rotation fix
## can be verified visually (door should stay framed across PC~100 yaw swoop).
##
## Env knobs:
##   BACKROT=0/1            override camera_backrotate_pivot (default: code default)
##   OFFX,OFFY,OFFZ         override camera_position_offset components
##   SHOT_PREFIX=/tmp/x     output path prefix (default /tmp/chapel)
##
## Run (NOT headless):  godot --path . -s res://tools/diag_scenario_screens.gd

var _scene: Node
var _vm: Node
var _f := 0
var _shot_frames := [40, 120, 240, 360, 480, 560]
var _prefix := "/tmp/chapel"

func _initialize() -> void:
	_prefix = _envs("SHOT_PREFIX", "/tmp/chapel")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 10:
		_grab_vm()  # VM exists after the scene's _ready ran
	if _shot_frames.has(_f):
		_capture(_f)
	if _f > _shot_frames[_shot_frames.size() - 1] + 5:
		quit()
		return true
	return false

func _grab_vm() -> void:
	_vm = _find_vm(_scene)
	if _vm == null:
		print("[diag] WARN: could not find ScenarioVM")
		return
	if OS.has_environment("BACKROT"):
		_vm.camera_backrotate_pivot = OS.get_environment("BACKROT") == "1"
	if OS.has_environment("OFFX") or OS.has_environment("OFFY") or OS.has_environment("OFFZ"):
		_vm.camera_position_offset = Vector3(
			float(_envs("OFFX", str(_vm.camera_position_offset.x))),
			float(_envs("OFFY", str(_vm.camera_position_offset.y))),
			float(_envs("OFFZ", str(_vm.camera_position_offset.z))))
	print("[diag] backrotate=%s invert=%s offset=%s" % [
		_vm.camera_backrotate_pivot, _vm.camera_backrotate_invert,
		str(_vm.camera_position_offset)])

func _capture(frame: int) -> void:
	var img := root.get_texture().get_image()
	var path := "%s_f%03d.png" % [_prefix, frame]
	img.save_png(path)
	var cam_desc := ""
	if _vm and _vm.player_camera:
		cam_desc = " campos=%s ortho=%.2f" % [
			str(_vm.player_camera.global_position),
			_vm.player_camera.camera.size if _vm.player_camera.camera else -1.0]
	print("[diag] shot f%03d -> %s%s" % [frame, path, cam_desc])

func _find_vm(n: Node) -> Node:
	# ScenarioVM is the node exposing reapply_last_camera() + camera knobs.
	if n.has_method("reapply_last_camera") and "camera_backrotate_pivot" in n:
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null

func _envs(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.has_environment(k) else d
