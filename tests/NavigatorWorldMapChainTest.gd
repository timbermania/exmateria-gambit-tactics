extends Node
## X1 step 5 — the walk arrives at the overworld and LEAVES it again, by itself.
##
## [NavigatorWorldMapArrivalTest] proved the walk lands on the map. It landed and stopped:
## the `world_map` action was terminal, `node_entered` had no subscriber, and the run ended
## there. This drives the other side of the same seam — `navigator.autoplay` on, no input
## at all — and requires the walk to pick the one live hand-off, resolve it to a group, and
## dispatch that group's first action.
##
## `[[a-mechanism-that-could-explain-it-is-not-evidence-it-did]]`. Every piece is already
## unit-tested against fakes: the interpreter (CampaignNodeScriptTest), the plan shape and
## the append (CampaignChainTest), the shared store (CampaignVariableStoreTest). None of
## them mounts a screen. This runs them in series, on the real scene, with the real
## tunables — which is the only arm that can fail if the wiring is wrong while every part
## is right.
##
## It seeks to the `world_map` action, so no combat is fought — that is
## NavigatorGarilandVictoryTest's job. The point here is the hand-off.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 1200 res://tests/NavigatorWorldMapChainTest.tscn

const AUTOPLAY_SLUG := "navigator.autoplay"
const TIMEOUT_MS := 40000

var _passed := 0
var _failed := 0
var _nav: Node = null
var _walk_finished := false
var _done := false
var _start_ms := 0


func _ready() -> void:
	# The profile, not the individual gate — so this also pins that `navigator.autoplay`
	# actually reaches the map gate rather than only the two that predate it.
	Tune.bind(AUTOPLAY_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(AUTOPLAY_SLUG, true)

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
	_true("the shipped walk plans a world_map action", idx >= 0)
	if idx < 0:
		_finish()
		return
	_eq("the shipped walk's map action is the LAST one — nothing followed it before now",
			idx, plan.size() - 1)

	ScenarioDebugSession.navigator_start_root = start_root
	ScenarioDebugSession.navigator_stop_root = stop_root
	ScenarioDebugSession.navigator_start_action = idx

	_start_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)
	if _nav._nav_runner == null:
		_true("navigator runner initialized", false)
		_finish()
		return
	_nav._nav_runner.walk_finished.connect(func() -> void: _walk_finished = true)
	await _drive()


func _drive() -> void:
	var planned_before: int = _nav._nav_runner._actions.size()

	var view: Node = null
	while view == null and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		view = _find_world_map()
	_true("the navigator mounted the world map", view != null)
	if view == null:
		_finish()
		return

	# The campaign opens at story 1 standing on Gariland — the ONE node in the game with a
	# live hand-off at that value (§29.5, measured against three savestates).
	_eq("the campaign is at story counter 1", Campaign.story_counter(), 1)
	var live := Campaign.live_enter_nodes()
	_eq("exactly one node offers a hand-off", live.size(), 1)
	_eq("...and it is Gariland (node index 6)", live[0] if live.size() > 0 else -1, 6)

	# No input is injected anywhere in this test. If the plan grows, autoplay did it.
	var grew := false
	while not grew and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		grew = _nav._nav_runner._actions.size() > planned_before
	_true("autoplay appended a hop to the walk without any input", grew)
	if not grew:
		_finish()
		return

	var appended: Array = _nav._nav_runner._actions.slice(planned_before)
	_eq("the hop is group 13's plan — scenario, then a fresh map", appended.size(), 2)
	if appended.size() == 2:
		_eq("first appended action is the scenario group",
				String(appended[0].get("kind", "")), "scenario")
		_eq("...rooted at 13, Balbanes's Death",
				int(appended[0].get("root", -1)), 13)
		_eq("second is another world map — the loop is closed, not one-shot",
				String(appended[1].get("kind", "")), "world_map")

	# ...and the runner actually STEPS into it. A plan that grew while the walk sat on the
	# map would satisfy everything above and still be a dead stop.
	var left := false
	while not left and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		left = _nav._nav_runner.current_state != GameState.State.WORLD_MAP
	_true("the walk LEFT the map on its own", left)
	_eq("it is playing a scenario now", _nav._nav_runner.current_state,
			GameState.State.SCENARIO)
	_eq("the walk has not finished", _walk_finished, false)

	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	Tune.clear(AUTOPLAY_SLUG)
	if _nav != null and is_instance_valid(_nav):
		_nav.queue_free()
	await get_tree().process_frame
	if _failed > 0:
		print("[FAIL] NavigatorWorldMapChainTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorWorldMapChainTest — %d/%d" % [_passed, _passed])
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
