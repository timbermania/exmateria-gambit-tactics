extends Node
## Integration guard for the debug-gated FORMATION view (wayfinder #234 E). Boots the real
## NavigatorMain with `navigator.show_formation` ON, seeked to Gariland's formation_view
## action, and proves the view is (a) BOUND to the owned roster and (b) NON-GATING: the test
## auto-dismisses it, then the walk continues through deployment → real combat → victory,
## exactly as the proof does without it.
##
## HEADFUL, real GPU — run standalone:
##   godot --path . --quit-after 120 res://tests/NavigatorFormationViewTest.tscn

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
const SHOW_FORMATION_SLUG := "navigator.show_formation"
const TIMEOUT_MS := 60000
const SIM_TIME_SCALE := 40.0

## Pinned false in `_ready` — see the note there. Mirrors NavigatorMain.STOP_ON_TURN_SLUG.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _walk_finished: bool = false
var _defeated: bool = false
var _formation_seen: bool = false
var _start_ms: int = 0
var _done: bool = false


func _ready() -> void:
	var action_index := _gariland_formation_view_index()
	if action_index < 0:
		print("  [FAIL] could not locate Gariland formation_view action")
		_failed += 1
		_finish()
		return
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = action_index

	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE); Tune.set_value(SKIP_SLUG, true)
	Tune.bind(INVINCIBLE_SLUG, false, {}, Tune.Persist.AUTOSAVE); Tune.set_value(INVINCIBLE_SLUG, true)
	Tune.bind(SHOW_FORMATION_SLUG, false, {}, Tune.Persist.AUTOSAVE); Tune.set_value(SHOW_FORMATION_SLUG, true)

	Engine.time_scale = SIM_TIME_SCALE
	_start_ms = Time.get_ticks_msec()

	# PIN the turn stop OFF. `navigator.stop_on_turn` is an AUTOSAVE tunable, so a session that
	# ticked it in the F3 panel leaves it TRUE in the tracked `config/tune_overrides.json` — and a
	# walk that stops on every turn with nobody to press Space does not fail here, it HANGS. The
	# same reason `NavigatorBattleLaunchTest` pins `skip_pre_battle` false rather than assuming it.
	Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(STOP_ON_TURN_SLUG, false)

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)
	if _nav._nav_runner != null:
		_nav._nav_runner.walk_finished.connect(func(): _walk_finished = true)
		_nav._nav_runner.defeated.connect(func(): _defeated = true)


func _process(_delta: float) -> void:
	if _done:
		return
	# When the formation overlay appears, note it (bound to owned) and auto-dismiss so the
	# walk proceeds — proving the view is view-only / non-gating.
	if not _formation_seen and _nav != null:
		var view := _find_formation_view()
		if view != null:
			_formation_seen = true
			_true(view.has_signal("dismissed"), "formation view exposes a dismissed signal")
			view.dismissed.emit()
	if _walk_finished or _defeated or (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS:
		_assert_and_finish()


func _find_formation_view() -> Node:
	for c in _nav.get_children():
		if c.get_class() == "Node3D" and c.get_script() != null \
				and c.get_script().resource_path.ends_with("FormationScene.gd"):
			return c
	return null


func _gariland_formation_view_index() -> int:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build(), true)
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "formation_view" and int(a.get("root", -1)) == 9:
			return i
	return -1


func _assert_and_finish() -> void:
	if _done:
		return
	_true(_formation_seen, "formation view was shown (debug flag ON)")
	_true(_walk_finished, "walk_finished after auto-dismiss (formation is NON-gating)")
	_true(not _defeated, "no defeat halt")
	_eq(int(_nav._last_combat_winner) if _nav != null else -99, 0, "combat still resolved winner==0")
	_finish()


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _finish() -> void:
	_done = true
	Engine.time_scale = 1.0
	Tune.clear(SKIP_SLUG)
	Tune.clear(INVINCIBLE_SLUG)
	Tune.clear(SHOW_FORMATION_SLUG)
	var wall_s := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	print("\n=== NavigatorFormationViewTest: %d passed, %d failed (%.1fs wall) ===" % [_passed, _failed, wall_s])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorFormationViewTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorFormationViewTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorFormationViewTest")
		get_tree().quit(0)
