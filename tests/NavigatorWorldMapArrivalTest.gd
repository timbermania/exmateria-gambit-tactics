extends Node
## ARRIVAL — the walk does not merely PLAN the world map, it lands on it.
##
## The C2 crossing left three of the four links proven and the fourth faked:
## [method GameNavigator.plan_actions] emits the terminal `world_map` action (planner
## test), [NavigatorRunner] dispatches it and resumes on `on_world_map_finished`
## ([code]WorldMapNavigatorTest._test_runner_dispatch[/code] — but against a
## [code]FakeExecutor[/code]), and the screen mounts correctly ([WorldMapMountTest] — but
## it builds the CanvasLayer itself rather than letting the navigator build it). Nothing
## drove [method NavigatorMain.run_world_map] on a LIVE walk, so "the walk reaches the
## overworld" rested on three green tests none of which crossed that seam.
##
## `[[a-mechanism-that-could-explain-it-is-not-evidence-it-did]]`: every piece existing is
## not evidence the walk runs them in series. This runs them in series.
##
## It seeks straight to the `world_map` action, so neither battle is fought — the point
## here is the HAND-OFF, not the combat that precedes it (that is
## [code]NavigatorGarilandVictoryTest[/code], which keeps its own `stop_root = 9` bound).
## The action index is DERIVED from NavigatorMain's own shipped constants, so a walk that
## stops short fails here rather than silently seeking to something else.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 30 res://tests/NavigatorWorldMapArrivalTest.tscn

## 🔴 THIS WAS 25000, AND THE WALK REACHED THE MAP AT 24472 ms ON TRUNK — 528 ms of
## margin, on a box shared with ~45 worktrees. It was not a budget, it was a coin flip.
##
## #1168 spent 2.2 s of it legitimately: `{77}`'s 112-frame dark-screen retract is an
## authored animation that the port used to snap away in one frame, and this walk crosses
## a battle intro that now plays it (`docs/BATTLE-HANDOFF-STALL.md`). Measured after:
## 26704 ms. 45 s is ~1.7x that, which is headroom rather than a new knife-edge.
##
## The `[arrival-margin]` line below is why the number above is quotable: a wall-clock
## budget with no reported margin cannot tell "passed comfortably" from "passed on the
## last frame it had", and this test had been doing the second one for some time.
const TIMEOUT_MS := 45000

var _passed := 0
var _failed := 0
var _nav: Node = null
var _walk_finished := false
var _done := false
var _start_ms := 0


func _ready() -> void:
	var nav_script: GDScript = load("res://src/scenarios/NavigatorMain.gd")
	var consts: Dictionary = nav_script.get_script_constant_map()
	var start_root := int(consts.get("START_ROOT", 1))
	var stop_root := int(consts.get("STOP_ROOT", 9))

	var plan := GameNavigator.new().plan_actions(start_root, stop_root,
			StoryMutationScript.build())
	var idx := -1
	for i in range(plan.size()):
		if String(plan[i].get("kind", "")) == "world_map":
			idx = i
			break
	_true("the SHIPPED walk (%d -> %d) plans a world_map action at all" % [start_root, stop_root],
		idx >= 0)
	if idx < 0:
		_finish()
		return
	# Seek to the VICTORY beat, not to the world_map action itself. Landing straight on
	# `world_map` would prove the mount and skip the very link this is about: that
	# finishing Gariland's victory beat ADVANCES into the map rather than ending the walk
	# (the walk used to end exactly there). The battles before it are still skipped —
	# NavigatorGarilandVictoryTest owns the combat pipeline.
	_eq("the action before the map is the victory beat",
			String(plan[idx - 1].get("kind", "")) if idx > 0 else "<none>", "victory")
	if idx > 0 and String(plan[idx - 1].get("kind", "")) == "victory":
		idx -= 1

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
	# The mount is async (load + instantiate + a process frame), so wait for the screen
	# rather than assuming it is up on the next frame.
	var view: Node = null
	while view == null and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		view = _find_world_map()
	print("[arrival-margin] world map mounted at %d ms of %d" % [Time.get_ticks_msec() - _start_ms, TIMEOUT_MS])
	_true("the navigator MOUNTED the world map on the live walk", view != null)
	if view == null:
		_finish()
		return

	_eq("the runner is in the WORLD_MAP state", _nav._nav_runner.current_state,
			GameState.State.WORLD_MAP)
	_eq("it mounted the screen, not the standalone capture rig", view._standalone, false)
	var layer := view.get_parent() as CanvasLayer
	_true("the mount is a CanvasLayer (never a SubViewport)", layer != null)
	_true("the screen itself is not a SubViewport", not (view is SubViewport))
	_eq("the walk has NOT finished while the screen is up", _walk_finished, false)

	# The transition is a screen-in, not a cut: the map RAISES ITSELF under its own
	# subtractive quad (ADR-0161) rather than under a cover the navigator tweens. Polled
	# every frame, so first sighting lands within a frame of the mount, while it is still
	# tinting.
	_true("the map raises itself rather than popping in", view.screen_in_active())

	# [b]The regression guard for a deadlock this test already caught once.[/b] The
	# navigator awaits `screen_in_finished`, and that signal is emitted from the screen's
	# own `advance()`, which runs in `_process`. Anything that stops the screen processing
	# while the ramp is in flight — `set_suspended`, `set_animated(false)` — makes that
	# await never return, and the walk hangs on a screen that is up and frozen. It presents
	# as a TIMEOUT three assertions below, which is a long way from the cause.
	_true("the screen keeps TICKING while it raises itself (a stopped clock deadlocks the "
			+ "navigator's await)", view.is_processing())

	# ...and that it RAMPS. A quad that existed for one frame and snapped to clear would
	# pass the assertion above while looking exactly like the cut this replaces, so sample
	# the pushed value every frame and require a real monotonic descent through
	# intermediate values.
	var seen: Array[float] = []
	var monotonic := true
	while view.screen_in_active() and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		var a: float = view._screen_in.current_value()
		if seen.is_empty() or not is_equal_approx(a, seen[seen.size() - 1]):
			if not seen.is_empty() and a > seen[seen.size() - 1]:
				monotonic = false
			seen.append(a)
		await get_tree().process_frame
	# THREE, not five. The bound is arithmetic, not taste: this samples once per RENDERED
	# frame, and the map advances `int(delta * VSYNC_HZ)` ticks per frame capped at
	# MAX_CATCHUP_TICKS (8). ADR-0174 measured the ramp at SIXTEEN ticks stepping every
	# tick — down from the guessed 60/2 — so the number of distinct values observable
	# here is 16 / ticks-per-frame, i.e. a function of FRAME RATE. At 60fps that is 16
	# samples and 5 is comfortable; in a loaded run it is ~4, and this arm failed for
	# that reason alone at 697/706 of the full suite while passing every time in
	# isolation. A fixed 5 was pinning the machine, not the ramp.
	#
	# Three still says the whole thing the arm exists to say. The failure it guards is a
	# quad that exists for one frame and snaps to clear, which yields ONE distinct value
	# (or two counting the landing) no matter how fast the machine is — the catch-up cap
	# cannot manufacture a third. `monotonic` and `lands fully clear` below are unchanged
	# and are the other two thirds of "it ramped".
	_true("the screen-in descends through intermediate values (%d sampled) — a ramp, not a snap"
			% seen.size(), seen.size() >= 3)
	_true("and it never brightens on the way down", monotonic)
	_true("it lands fully clear", is_equal_approx(view._screen_in.current_value(), 0.0))

	# Leave it the way a player does — `ui_cancel` is this project's leave key on the map
	# (WorldMapScene._unhandled_input), not a hand-emitted `dismissed`.
	#
	# PRESSED ON A LOOP, deliberately. The screen is SUSPENDED while it fades in, so an
	# early press is correctly swallowed; a single press fired at first sighting would be
	# eaten by the fade and this test would hang rather than fail. A player pressing again
	# is the real behaviour, and it keeps the test independent of the fade's duration.
	var waited := 0
	while not _walk_finished and waited < 900:
		if waited % 10 == 0:
			var ev := InputEventAction.new()
			ev.action = &"ui_cancel"
			ev.pressed = true
			Input.parse_input_event(ev)
		await get_tree().process_frame
		waited += 1
	_true("dismissing the map RESUMED the walk to walk_finished", _walk_finished)
	_true("and the screen was freed on the way out", _find_world_map() == null)
	# Checked on the captured reference, not by re-walking `layer` — the navigator frees the
	# whole layer on dismissal, and a freed Object cannot bind to a typed parameter.
	_true("the screen-in quad did not outlive the transition — the whole layer is freed",
			not is_instance_valid(layer))
	_finish()


## The mounted [code]WorldMapScene[/code] under the navigator, or null. Found by its
## `dismissed` signal + `_standalone` flag rather than by node name, so a rename of the
## scene root does not silently turn this test green-by-absence.
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


func _finish() -> void:
	if _done:
		return
	_done = true
	if _failed > 0:
		print("[FAIL] NavigatorWorldMapArrivalTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorWorldMapArrivalTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)
