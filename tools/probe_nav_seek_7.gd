extends Node
## One-shot probe: seek the runtime navigator straight to group 7 (Military Academy) and
## bound the walk at group 9 (Gariland), so we can verify the NEW scn-8 playback + the
## 7→9 handoff without sitting through groups 1–6 at ~1fps. Sets the seek on the
## ScenarioDebugSession autoload (survives the scene change), then boots NavigatorMain.
##
## Run: godot --path . res://tools/probe_nav_seek_7.tscn   (headful; ~watch the log)

func _ready() -> void:
	ScenarioDebugSession.navigator_start_root = 7
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = 0
	print("[probe_nav_seek_7] seek set: start_root=7 stop_root=9 → booting NavigatorMain")
	get_tree().change_scene_to_file("res://assets/scenes/NavigatorMain.tscn")
