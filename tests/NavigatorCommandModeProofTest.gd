extends Node
## HEADFUL end-to-end proof for COMMAND MODE (ADR-0082) on the roster-fed Gariland path. Complements
## the fast FSM guard (NavigatorCommandModeTest): this boots the REAL NavigatorMain — real GPU, real
## world, real deploy — with the pre-battle skip OFF, so the walk PARKS in Deployment command mode.
## It then proves what the bare-construct test can't:
##   (a) the CombatLoop exists UP FRONT at Deployment, FROZEN (combat_active == false) — not "no loop
##       yet". Deployment and a mid-battle Pause are the literal same flag state.
##   (c) the roam cursor exists and is SEEDED ON THE LEADER (first deployed owned unit), so the
##       handoff never lands on world-origin.
##   (b/d) TAB drives the full cycle: Deployment → Live (sim arms) → Paused (sim freezes) → Live.
##
## Real GPU, standalone (never in the parallel suite):
##   godot --path . --quit-after 120 res://tests/NavigatorCommandModeProofTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

const SKIP_SLUG := "navigator.skip_pre_battle"
## UNSCALED wall-clock budget (independent of time_scale + the agent-shell present-throttle).
const TIMEOUT_MS := 120000
## Accelerate the async walk (world boot → opener fast-forward → deploy) so it reaches the Deployment
## park in a few frames. Matches NavigatorGarilandVictoryTest's rationale.
const SIM_TIME_SCALE := 40.0

## Pinned false in `_ready` — see the note there. Mirrors NavigatorMain.STOP_ON_TURN_SLUG.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _start_ms: int = 0
var _done: bool = false
var _asserted: bool = false


func _ready() -> void:
	var action_index := _gariland_opener_index()
	if action_index < 0:
		print("  [FAIL] could not locate Gariland opener action in the plan")
		_failed += 1
		_finish()
		return
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = action_index

	# Skip OFF is the whole point: the walk must PARK in Deployment command mode (not auto-advance).
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, false)

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


func _process(_delta: float) -> void:
	if _done:
		return
	# Fire the assertions the moment the walk parks in Deployment (loop + cursor built, sim frozen).
	if not _asserted and _nav != null and bool(_nav._pre_battle_active):
		_assert_command_mode()
		return
	if (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS:
		print("  [FAIL] timed out before the walk parked in Deployment command mode")
		_failed += 1
		_finish()


func _assert_command_mode() -> void:
	_asserted = true

	# Start and pause are SEPARATE keys (ADR-0137 Amendment 2 split ADR-0082's one Tab toggle:
	# starting a battle is a one-way phase exit, pausing is a repeatable toggle). Neither is Enter,
	# which the map cursor owns, and neither is Tab, which now means "inspect the cursored unit".
	_true(InputMap.has_action("battle_start"), "battle_start action is registered (Space)")
	_true(InputMap.has_action("battle_pause"), "battle_pause action is registered (Esc)")
	_true(not InputMap.has_action("command_mode_toggle"),
		"the fused command_mode_toggle is gone — it was the key with three meanings")

	# (a) FROZEN loop up front — the freeze model, not "no loop yet".
	var loop = _nav._combat_loop
	_true(loop != null, "Deployment: a CombatLoop exists up front (built before go-live)")
	if loop != null:
		_true(not bool(loop.combat_active), "Deployment: the loop is FROZEN (combat_active == false)")
	_true(not bool(_nav._combat_active), "Deployment: the pump flag is frozen (combat_active == false)")

	# (c) Cursor seeded on the leader.
	var deployed: Array = _nav._deployed_owned
	_true(deployed.size() > 0, "Deployment: owned units were deployed")
	var cursor = _nav._cursor_rig    # the PORT since ADR-0206; `grid_pos` is its getter
	_true(cursor != null, "Deployment: the roam cursor rig is built")
	if cursor != null and deployed.size() > 0 and is_instance_valid(deployed[0]):
		var want: Vector3i = deployed[0].get_current_cell()
		if want != TerrainCell.NONE:
			# The cursor is seeded with the leader's COLUMN — it has no level to be
			# seeded with, level cycling being deferred (#795). Asserting the column is
			# the whole claim this test ever made (ADR-0219 dec. 1).
			_eq(cursor.grid_pos, Vector2i(want.x, want.y),
				"cursor is seeded on the leader's tile %s" % str(want))
		else:
			_true(false, "leader has a current tile to seed the cursor on")

	# (b/d) The cycle: Deployment → Live (Space) → Paused → Live (Esc).
	_nav._start_battle()          # Deployment → Live (leaves the park; run_combat arms + goes live)
	# run_combat is async (awaits _ensure_battle_world, a no-op here since the world is up), so the
	# go-live flip lands within a frame; verify on the next process tick via a deferred continuation.
	call_deferred("_assert_after_go_live")


func _assert_after_go_live() -> void:
	# WAIT for the async go-live, do not GUESS at it. This used to be two `process_frame`s, which
	# is a race: `run_combat` awaits `_ensure_battle_world`, and how many frames that takes is not
	# ours to predict. Measured on an idle machine, back to back with nothing else running: one run
	# 11 passed / 5 failed, the next 16 / 0, same binary and same code. All five failures were
	# downstream of this one wait — the loop simply had not gone live yet — so the suite reported a
	# product bug that did not exist, twice, in two different sessions.
	#
	# A guard that fails when it is EARLY is worse than no guard: it trains you to re-run until
	# green, which is the habit that hides a real regression. Poll the condition with a generous
	# bound instead; if the flip genuinely never lands, the assertions below still fail and say so.
	var loop = _nav._combat_loop
	var waited := 0
	while waited < 240:
		loop = _nav._combat_loop
		if loop != null and bool(loop.combat_active) and bool(_nav._combat_active):
			break
		await get_tree().process_frame
		waited += 1
	_true(not bool(_nav._pre_battle_active), "Deployment→Live: Space left the pre-battle park")
	_true(loop != null and bool(loop.combat_active), "Deployment→Live: the loop is LIVE (combat_active true)")
	_true(bool(_nav._combat_active), "Deployment→Live: the pump flag is live")

	_nav._toggle_tactical_stop()   # Live → STOPPED
	_true(loop != null and not bool(loop.combat_active), "Live→Paused: Esc freezes the loop")
	_true(not bool(_nav._combat_active), "Live→Paused: the pump flag is frozen")

	_nav._toggle_tactical_stop()   # STOPPED → Live
	_true(loop != null and bool(loop.combat_active), "Paused→Live: Esc re-arms the loop")
	_true(bool(_nav._combat_active), "Paused→Live: the pump flag is live")

	_finish()


func _gariland_opener_index() -> int:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "opener" and int(a.get("beat", {}).get("scenario_id", -1)) == 10:
			return i
	return -1


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	Tune.clear(SKIP_SLUG)
	var wall_s := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	print("\n=== NavigatorCommandModeProofTest: %d passed, %d failed (%.1fs wall) ===" % [_passed, _failed, wall_s])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorCommandModeProofTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorCommandModeProofTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorCommandModeProofTest")
		get_tree().quit(0)
