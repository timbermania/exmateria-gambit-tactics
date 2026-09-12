extends Node
## END-TO-END proof for the roster-fed Gariland battle (wayfinder #234 F — the /tdd
## success gate). Boots the REAL NavigatorMain seeked to Gariland's OPENER, so the slow
## Orbonne combat is skipped but the whole roster-fed pipeline runs live — INCLUDING the
## opener cinematic (scn 10), which ends on a {80} March opcode that must be handled or
## the VM stalls and the walk hangs before deployment (the linear-walk bug):
##   opener (scn 10, ends on March) → seed owned (C) → snap-deploy onto zone-256 tiles
##   (D) → build_battle team0 = deployed-owned ∪ ENTD-blue (A) → REAL GPU combat →
##   victory beat (scn 12) → stop.
##
## Deterministic outcome: the deployed owned team is made invincible (proof tunable), so
## the auto-battle reliably resolves `winner == 0` (the 5 red thieves are defeated) — the
## same real GPU combat the Orbonne battle uses, with the deck stacked so balance can't
## flake the proof.
##
## Asserts (F's gate): combat resolves winner==0, the walk reaches walk_finished (victory
## beat played → GoToWorldMap → no successor → terminal), and no defeat halt fired.
##
## HEADFUL, real GPU — run standalone (never in the parallel suite):
##   godot --path . --quit-after 120 res://tests/NavigatorGarilandVictoryTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
## Wall-clock budget (UNSCALED — independent of Engine.time_scale + the agent-shell's
## phantom present-throttle to ~1 fps): the accelerated sim resolves in a few frames.
const TIMEOUT_MS := 120000
## Accelerate the auto-battle so it resolves in a couple of frames even at 1 fps: _process
## delta is scaled by Engine.time_scale, and CombatLoop.tick drains that delta into sim
## ticks. Bumps enemy-defeat well inside max_ticks so a REAL victory (winner==0) fires.
## Kept at 40 — per-tick unit movement is coupled to real frame delta, not pure tick count,
## so pushing time_scale higher paradoxically SLOWS the march per tick (at 120 the owned
## units barely left their deploy tiles in 20k ticks; at 40 they cross to the enemy line in
## ~6k). So the longer march the deploy-coord fix introduces is funded by more TICKS, not a
## faster clock.
const SIM_TIME_SCALE := 40.0
## The proof battle's tick budget. CombatLoop defaults to 6000, which the old (buggy)
## deploy-adjacent placement resolved inside. With the deploy-coord chirality fix the owned
## units now correctly deploy on the FAR side from the thieves (zone-256 tiles y1-3 vs
## enemies y9-13) and must path ~8 tiles across (reaching the enemy line ~tick 6000) before
## the (enemy-HP-1) lethal hits land — so the decisive victory needs a bigger budget.
## Bumped on the live loop once it exists (test-only; production balance is a follow-up,
## see NavigatorMain._on_combat_timed_out). ~175 ticks/s wall at time_scale 40, so this
## stays inside TIMEOUT_MS.
const PROOF_MAX_TICKS := 14000

## Pinned false in `_ready` — see the note there. Mirrors NavigatorMain.STOP_ON_TURN_SLUG.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _walk_finished: bool = false
var _defeated: bool = false
var _start_ms: int = 0
var _done: bool = false
## Placement-side guard (the deploy-coord chirality fix): the owned units deploy on
## zone-256's flipped tiles (y 1-3, the NEAR half of MAP022's 15-deep grid) and march
## UP toward the high-y red thieves — so the minimum grid_z any owned unit ever occupies
## ≈ its deploy tile. The pre-fix mirror bug spawned them at y 11-13 (far half, among the
## enemies), which this catches. Tracked across frames since deploy emits no signal.
var _min_deploy_z: int = 9999
var _saw_deployed: bool = false
var _tick_budget_raised: bool = false
## Deploy-facing guard (issue #3): the owned units consume zone-256's unit_facing (East,
## 0x000) so they face the far-half thieves instead of a constant spawn-default. Captured
## on FIRST sighting of each unit (still on its deploy tile, before combat re-orients it),
## keyed by instance id so it's recorded exactly once. EAST = facing_angle 0x000.
var _first_facing: Dictionary = {}


func _ready() -> void:
	# Seek to Gariland's OPENER action (skip Orbonne's slow combat; the seek still folds the
	# earlier catalogue deltas). Playing the opener exercises the {80} March opcode at its
	# end — the linear-walk stall this test must guard. Derived, not hardcoded.
	var action_index := _gariland_opener_index()
	if action_index < 0:
		print("  [FAIL] could not locate Gariland opener action in the plan")
		_failed += 1
		_finish()
		return
	ScenarioDebugSession.navigator_start_root = 1
	ScenarioDebugSession.navigator_stop_root = 9
	ScenarioDebugSession.navigator_start_action = action_index

	# Auto-advance the pre-battle breakpoint + stack the deck so winner==0 is deterministic.
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)
	Tune.bind(INVINCIBLE_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(INVINCIBLE_SLUG, true)

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
	add_child(_nav)   # NavigatorMain._ready plans + begins the (async) walk

	# The runner exists after _ready; the walk is parked at its first await (world boot),
	# so no terminal signal has fired yet — connecting here can't miss it.
	if _nav._nav_runner != null:
		_nav._nav_runner.walk_finished.connect(_on_walk_finished)
		_nav._nav_runner.defeated.connect(_on_defeated)
	else:
		print("  [FAIL] navigator runner did not initialize")
		_failed += 1
		_finish()


func _process(_delta: float) -> void:
	if _done:
		return
	_raise_tick_budget()
	_sample_deploy_side()
	if _walk_finished or _defeated or (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS:
		_assert_and_finish()


## Give the proof battle a larger tick budget the moment its CombatLoop exists. The loop
## is created mid-walk (after deploy) and starts pumping immediately; _process catches it
## within a frame or two, well before the 6000-tick default would trip.
func _raise_tick_budget() -> void:
	if _tick_budget_raised or _nav == null or not ("_combat_loop" in _nav):
		return
	var loop = _nav._combat_loop
	if loop == null:
		return
	loop.max_ticks = PROOF_MAX_TICKS
	_tick_budget_raised = true


## Track the lowest grid_z any deployed owned unit occupies. Sampled every frame from
## first sighting; since they start on the near-half deploy tiles and march toward the
## far-half enemies, the running minimum recovers the deploy side (mirror-bug-proof).
func _sample_deploy_side() -> void:
	if _nav == null or not ("_deployed_owned" in _nav):
		return
	for unit in _nav._deployed_owned:
		if unit == null or not is_instance_valid(unit):
			continue
		var cell: Vector3i = unit.get_current_cell()
		if cell == TerrainCell.NONE:
			continue
		_saw_deployed = true
		_min_deploy_z = mini(_min_deploy_z, cell.y)
		# Record each unit's facing exactly once, at first sighting (deploy pose).
		var iid: int = unit.get_instance_id()
		if not _first_facing.has(iid):
			_first_facing[iid] = int(unit.facing_angle)


func _on_walk_finished() -> void:
	_walk_finished = true


func _on_defeated() -> void:
	_defeated = true


func _gariland_opener_index() -> int:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	for i in range(plan.size()):
		var a: Dictionary = plan[i]
		if String(a.get("kind", "")) == "opener" and int(a.get("beat", {}).get("scenario_id", -1)) == 10:
			return i
	return -1


func _assert_and_finish() -> void:
	if _done:
		return
	var timed_out := (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS
	_true(not (timed_out and not _walk_finished), "walk completed within budget (no hang)")
	_true(_walk_finished, "walk_finished emitted (victory beat → GoToWorldMap → terminal)")
	_true(not _defeated, "no defeat halt")
	var winner := int(_nav._last_combat_winner) if _nav != null else -99
	_eq(winner, 0, "combat resolved winner==0 (red thieves defeated)")
	# Placement-side guard: owned units deployed on the NEAR half (zone-256's flipped
	# tiles y 1-3), not the far-half mirror (y 11-13) among the thieves. MAP022 is 15
	# deep, so mid == 7. Guards the deploy-coord chirality fix end-to-end.
	_true(_saw_deployed, "owned units were sighted on their deploy tiles")
	_true(_saw_deployed and _min_deploy_z < 7,
		"owned deploy side is near-half (min grid_z %d < 7, not the y11-13 mirror)" % _min_deploy_z)

	# Deploy-facing (issue #3): the zone data carries the East (0x000) unit facing the parser
	# lifts from unit_facing=2, and the deploy path applies it — the owned units face the
	# far-half thieves, not a constant spawn default.
	var zone := DeploymentZoneDatabase.get_zone(256)
	_eq(int(zone.get("unit_facing_12bit", -1)), 0x000,
		"zone 256 unit_facing_12bit == 0x000 (East, parser-derived)")
	var faced_east := false
	for f in _first_facing.values():
		if int(f) == 0x000:
			faced_east = true
	_true(faced_east, "a deployed owned unit was first sighted facing East (0x000) — deploy facing applied")

	_assert_identity_materialized()

	# Camera (issues #1+#2, FFT-FAITHFUL): the victory beat (scn 12) drives the camera via its
	# OWN op-10 {1F} Focus(0x01) → op-11 {19} Camera, which re-aims onto the deployed Ramza —
	# now that he's registered under RAMZA_EVENT_UID (0x01) in the VM's unit registry. Prove
	# the Focus RESOLVED onto a live unit (not the "target not present" authored-pose fallback
	# = the old "pans to nowhere") and that the resolved target is Ramza's position. Reading
	# the camera-body distance would be wrong here — the opcode poses the body at an offset +
	# zoom, so it deliberately does NOT sit on Ramza; the FOCUS TARGET does.
	var director = _nav._vm.camera_director if _nav != null and _nav._vm != null else null
	if director != null:
		_true(bool(director.last_focus_resolved),
			"scn-12 victory Focus resolved onto a live unit (not authored-pose fallback)")
		if _nav._deployed_owned.size() > 0 and is_instance_valid(_nav._deployed_owned[0]):
			var leader_pos: Vector3 = _nav._deployed_owned[0].global_position
			var focus_target: Vector3 = director.last_focus_target_godot
			var dist := focus_target.distance_to(leader_pos)
			_true(bool(director.last_focus_resolved) and dist < 2.0,
				"victory camera Focus aimed at Ramza (%.2f tiles from him, not the authored pose)" % dist)
	else:
		_true(false, "camera director reachable for the Focus-resolution assertion")
	_finish()


## Identity materialization (fix #3, ADR-0079): the deploy seam SELECTS the leader's
## active Form and stamps its `special_name` one line before `resolve()`, so the
## deployed protagonist resolves UNIQUE (his `ramza_1` template folder) rather than the
## generic Squire. His squadmates carry no Form, so they still job-route (empty template
## folder). One mechanism fixes body sprite AND dialogue portrait (both run the resolver).
func _assert_identity_materialized() -> void:
	var deployed: Array = _nav._deployed_owned if _nav != null else []
	var leader = deployed[0] if deployed.size() > 0 else null
	_true(leader != null, "a leader unit was deployed")
	if leader != null:
		var folder := String(leader.template_folder)
		_true(folder.contains("ramza"),
			"deployed leader resolves UNIQUE (template_folder '%s' is Ramza's, not a job-routed generic)" % folder)
	# A generic squadmate stays job-routed: no Form on file → miss → empty template folder.
	var saw_generic_jobroute := false
	for i in range(1, deployed.size()):
		var u = deployed[i]
		if is_instance_valid(u) and String(u.template_folder) == "":
			saw_generic_jobroute = true
	_true(saw_generic_jobroute, "a generic squadmate still job-routes (empty template_folder)")
	# The seam materializes the catalogue Character's special_name at DEPLOY (not a durable
	# mint byte): Ramza's Ch1 Form == special_name 1 (template_residue.json '1' → ramza_1).
	var owned: Array = CharacterCatalog.owned_units()
	if not owned.is_empty():
		_eq(int(owned[0].special_name), 1,
			"deploy seam materialized the leader's active Form (special_name 1)")


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
	var wall_s := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	print("\n=== NavigatorGarilandVictoryTest: %d passed, %d failed (%.1fs wall) ===" % [_passed, _failed, wall_s])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorGarilandVictoryTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorGarilandVictoryTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorGarilandVictoryTest")
		get_tree().quit(0)
