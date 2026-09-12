extends Node
## Probe: seek the navigator STRAIGHT to the Orbonne combat action (skipping the slow
## cinematics) to verify the ADR-0201 #189 read-path refactor headful — the battle
## still comes up as the clean team split, now resolved through the Catalog + binding
## resolver (fallback carries the unbound cast at beat 1). Watch stdout for
## "Orbonne teams ... fell back" and "battle LIVE".
##
## Run: godot --path . res://tools/probe_orbonne_battle.tscn   (NOT --headless)

func _ready() -> void:
	# plan_actions(1,7) = [scenario:1, opener:4, combat:3, victory:6, scenario:7];
	# action index 2 is the combat. run_combat self-boots the Orbonne battle world.
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 7
	ScenarioDebugSession.navigator_start_action = 2
	print("[probe] seeking navigator to Orbonne combat (action 2)")
	get_tree().change_scene_to_file("res://assets/scenes/NavigatorMain.tscn")
