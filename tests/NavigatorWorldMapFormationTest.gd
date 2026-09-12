extends Node
## The world map's START-menu → Formation hand-off, on the LIVE walk.
##
## Reported from play: *"when I go to the formation screen from the world map on the
## navigator main scene it just goes black."*
##
## The cause is a layer conflict that only exists on this path. `_fade_battlefield_out`
## tweens the inherited `_fade_rect` to alpha 1 and LEAVES it there — it stands in for the
## torn-down battlefield while the map is up, and the map's own CanvasLayer covers it only
## because that layer is added later at the same layer 100. Hiding the map layer to show
## Formation un-hides the rect, and **Formation cannot draw over it**: `Formation.tscn` is a
## `Node3D` with its own orthographic `Camera3D`, so it renders through the 3D world, and a
## `CanvasLayer` at layer 100 covers all 3D no matter what is mounted beneath.
##
## `run_formation_view` — the debug-gated one — mounts identically and is fine, because it
## runs while the battlefield is still up and the rect is still transparent. Same code, two
## outcomes, decided entirely by state the mount does not look at.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 1800 res://tests/NavigatorWorldMapFormationTest.tscn

const TIMEOUT_MS := 40000
const WM_WINDOW_FORMATION := 7

var _passed := 0
var _failed := 0
var _nav: Node = null
var _done := false
var _start_ms := 0


func _ready() -> void:
	var nav_script: GDScript = load("res://src/scenarios/NavigatorMain.gd")
	var consts: Dictionary = nav_script.get_script_constant_map()
	var start_root := int(consts.get("START_ROOT", 1))
	var stop_root := int(consts.get("STOP_ROOT", 0))

	var plan := GameNavigator.new().plan_actions(start_root, stop_root,
			StoryMutationScript.build())
	var idx := -1
	for i in range(plan.size()):
		if String(plan[i].get("kind", "")) == "world_map":
			idx = i
			break
	if idx < 0:
		_true("the shipped walk plans a world_map action", false)
		_finish()
		return

	ScenarioDebugSession.navigator_start_root = start_root
	ScenarioDebugSession.navigator_stop_root = stop_root
	ScenarioDebugSession.navigator_start_action = idx

	_start_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)
	await _drive()


func _drive() -> void:
	var view: Node = null
	while view == null and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		view = _find_world_map()
	_true("the navigator mounted the world map", view != null)
	if view == null:
		_finish()
		return

	var layer := view.get_parent() as CanvasLayer
	var rect: ColorRect = _nav._fade_rect

	# The precondition that makes this path different from `run_formation_view`. If this
	# ever stops holding, the bug is gone for a reason this test no longer describes.
	_true("the battlefield fade rect is OPAQUE while the map is up",
			rect != null and rect.color.a >= 1.0)
	_true("the map's layer is visible", layer != null and layer.visible)

	# Drive the row the START menu reports, rather than injecting input: the menu's own
	# navigation is WorldMapStartMenuTest's subject, and this is about what the navigator
	# does with the row.
	_nav._on_world_map_menu_row(view, WM_WINDOW_FORMATION)
	await get_tree().process_frame
	await get_tree().process_frame

	var formation := _find_formation()
	_true("Formation mounted", formation != null)
	_eq("...and it is a Node3D, so a CanvasLayer would cover it",
			formation is Node3D if formation != null else false, true)
	_true("the map layer is hidden while Formation is up", layer != null and not layer.visible)
	# THE ASSERTION. Black screen = this rect still opaque over Formation's 3D.
	_eq("the fade rect is lifted so Formation is visible", rect.color.a, 0.0)

	# ...and it goes back, or the map returns onto a torn-down battlefield.
	if formation != null and formation.has_signal("dismissed"):
		formation.dismissed.emit()
	var restored := false
	while not restored and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		restored = rect.color.a >= 1.0
	_true("the fade rect is restored when Formation closes", restored)
	_true("the map layer comes back", layer != null and layer.visible)

	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _nav != null and is_instance_valid(_nav):
		_nav.queue_free()
	await get_tree().process_frame
	if _failed > 0:
		print("[FAIL] NavigatorWorldMapFormationTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorWorldMapFormationTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _find_world_map() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		return null
	for child in _nav.get_children():
		if not (child is CanvasLayer):
			continue
		for gc in child.get_children():
			if gc.has_signal("dismissed") and "_standalone" in gc:
				return gc
	return null


func _find_formation() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		return null
	for child in _nav.get_children():
		if child is Node3D and child.name.begins_with("Formation"):
			return child
	return null


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _true(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s" % what)
