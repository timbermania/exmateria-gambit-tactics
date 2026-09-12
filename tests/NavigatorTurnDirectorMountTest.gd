extends Node
# test-kind: gpu
# seeded-break: stop the walk mounting the director in src/scenarios/NavigatorMain.gd (`_turn_director = TurnDirector.mount(_combat_loop)` -> `= null`) — the PLACEMENT claim itself, so 8 arms red: 'the walk mounted a TurnDirector on its bare CombatLoop', 'the director is a child of the LOOP, not of the scene', and the whole forecast-strip chain under it (mounted, camera-parented, in front of the camera, repainted, queue > 1). That the strip arms fall with the director is the coupling ADR-0239 predicts, not a redundancy
## HEADFUL end-to-end proof for #898 (design S11): the WALK mounts the turn director.
##
## The claim under test is a PLACEMENT claim, and it is the reason ADR-0239 made the
## director a component of the [CombatLoop] rather than of [CombatHost]: `NavigatorMain`
## runs a bare loop and extends no host at all, so anything the director had quietly taken
## from `GPUArena` would have to be rebuilt here. The check is that it did not — the mount
## is one line, and the forecast strip (ADR-0244), which rides the CAMERA rather than the
## host scene, comes across in a second.
##
## It runs the REAL Gariland battle — same seek, same invincibility, same tick budget as
## `NavigatorGarilandVictoryTest` — because the interesting arms are all about a battle
## that is genuinely running:
##
##   (a) PLACEMENT: the director is a child of the LOOP, and the walk is not a `CombatHost`.
##   (b) THE STRIP RIDES THE CAMERA: the HUD's parent is the camera, and it sits at the
##       camera-local depth plane. ADR-0244 found that a UI3 host left at the camera's own
##       origin draws perfectly and is INVISIBLE, and that no layout test can see it — so
##       the depth is asserted here, where a real camera exists.
##   (c) THE QUEUE ADVANCES: several distinct units take a turn over the battle. Note what
##       this does NOT prove — a director that announced turns and spent nothing still
##       changes hands here (unspent meters stop at their own crossing values, so a growing
##       ready set keeps handing the head to a larger overshoot, and deaths do it too).
##       `TurnDirectorTest` arm 6C is the one that reads the buffer.
##   (d) THE DEFAULT IS HANDS-OFF: this test sets no `navigator.stop_on_turn`, so the walk
##       must mount `stops_the_world = false` and the director must never freeze the loop.
##       That is now a claim about the DEFAULT rather than about a hardcode — the policy
##       became a tunable, and the default is what the three end-to-end walks depend on: a
##       world that stopped on every turn with nobody to press Space would hang all of them.
##       `NavigatorMain._combat_active` must also agree with `CombatLoop.combat_active` on
##       EVERY frame. That second arm is unchanged and is deliberately NOT scoped to the
##       default: under the opted-in policy the director freezes and the mirror FOLLOWS it
##       in the same call stack, so the two agree under both policies and this arm reads the
##       same invariant either way (`NavigatorTurnStopTest` asserts it on the other side).
##   (e) THE WALK SURVIVES: winner==0 and the walk reaches its terminal state. A director
##       that stopped for a turn nobody can take would hang here instead, which is the
##       failure this policy exists to prevent.
##   (f) THE STRIP IS FREED with the battle: it is parented to the camera, which outlives
##       every battle in the walk.
##   (g) THE GAMBIT DOOR EXISTS on this host: the mounted Formation screen carries
##       `StartActionMenu.ROWS_ADJUST`. `mount_over_map` does not arm the row set, and an
##       empty one silently falls back to the ROM's five — whose row 3 is "Remove Unit", a
##       label `MENU_LABEL_STATE` does not know, so Tab -> row 3 -> ○ did nothing at all.
##       Asserted HERE because every other test that mounts this screen runs on the
##       `GambitBattle` host, which arms the rows itself: the shipped bug was invisible to
##       all of them and is invisible to any arm that does not name THIS host.
##
## HEADFUL, real GPU — run standalone:
##   godot --path . --quit-after 20000 res://tests/NavigatorTurnDirectorMountTest.tscn

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
## FRAME budget, not a wall-clock one (charter clause 14b: a verdict may not depend on
## measured duration outside a `perf` test). 7200 frames is the old 120 s deadline at 60 fps,
## and the walk resolves in a few hundred — the accelerated battle is fast.
##
## The unit change is a FIX, not a transcription. The walk is driven by `_process`, so under
## the agent shell's phantom present-throttle (1-2 fps, a Wayland present block rather than
## real slowness) a wall-clock deadline expires while a perfectly healthy walk is still
## marching. A frame budget throttles with the thing it is budgeting.
const TIMEOUT_FRAMES := 7200
## Matches `NavigatorGarilandVictoryTest`: 40 is where the owned units cross the map inside
## the tick budget (higher paradoxically slows the march, which is coupled to frame delta).
const SIM_TIME_SCALE := 40.0
## The proof battle's tick budget, for the same reason that test carries one: the corrected
## deploy side puts the owned units ~8 tiles from the thieves.
const PROOF_MAX_TICKS := 14000

## Pinned false in `_ready` — see the note there. Mirrors NavigatorMain.STOP_ON_TURN_SLUG.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

const StartActionMenuScript = preload("res://src/ui3/detail/StartActionMenu.gd")

var _passed: int = 0
var _failed: int = 0
## Set on any frame the mounted director carried the STOPPING policy. See arm (d).
var _saw_stops_the_world: bool = false
var _nav: Node = null
var _walk_finished: bool = false
var _defeated: bool = false
var _frames: int = 0
var _done: bool = false
var _tick_budget_raised: bool = false
## The Formation screen's row set, latched on first sighting — the screen is freed with the
## battle, exactly like the director and the strip, so a read in the assertions would be too late.
var _saw_map_screen: bool = false
var _screen_rows: Array = []

# --- What the sampling collects ----------------------------------------------
## The director + strip, captured on first sighting: both are freed when the battle ends
## (arm f), and the assertions below run after that.
var _director = null
var _hud = null
var _loop = null
var _camera: Node3D = null
## Every unit index the director announced, in order of first announcement.
var _takers: Array = []
var _commits: int = 0
## Set the first frame the loop is live and the director is NOT in RUNNING — the freeze
## that must never happen under this policy.
var _saw_freeze: bool = false
## Latched if the kernel's turn brake was ever armed on the walk's simulator. It must not
## be: `stops_the_world = false` is what gates it, and no second flag exists.
var _saw_brake: bool = false
## Set the first frame the pump mirror and the loop's own gate disagree.
var _mirror_split: bool = false
## The strip's high-water evidence, sampled across the battle: it is torn down at the end,
## so a post-hoc read would see nothing.
var _hud_max_draws: int = 0
var _hud_max_shown: int = 0
var _hud_was_visible: bool = false
var _hud_depth: float = 0.0
var _hud_parent_is_camera: bool = false
var _director_parent_is_loop: bool = false
var _saw_live_battle: bool = false
## Latched at first sighting. NOT `_director != null` at assert time: both objects are
## freed with the battle (arm f), and a freed Object compares EQUAL to null in GDScript,
## so the post-hoc read cannot tell "never mounted" from "mounted and torn down".
var _saw_director: bool = false
var _saw_hud: bool = false


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

	# Auto-advance the pre-battle breakpoint + stack the deck so winner==0 is deterministic.
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)
	Tune.bind(INVINCIBLE_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(INVINCIBLE_SLUG, true)

	Engine.time_scale = SIM_TIME_SCALE
	_frames = 0

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
		_nav._nav_runner.walk_finished.connect(_on_walk_finished)
		_nav._nav_runner.defeated.connect(_on_defeated)
	else:
		print("  [FAIL] navigator runner did not initialize")
		_failed += 1
		_finish()


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	_raise_tick_budget()
	_sample()
	if _walk_finished or _defeated or _frames >= TIMEOUT_FRAMES:
		_assert_and_finish()


## Give the proof battle the same larger tick budget the victory proof gives it — the loop
## is created mid-walk and starts pumping immediately.
func _raise_tick_budget() -> void:
	if _tick_budget_raised or _nav == null:
		return
	var loop = _nav._combat_loop
	if loop == null:
		return
	loop.max_ticks = PROOF_MAX_TICKS
	_tick_budget_raised = true


## Everything the arms need is only true WHILE the battle exists; the strip and the
## director are freed the moment it resolves. Sampled every frame rather than read once,
## which is also what makes (c) and (d) claims about the whole battle instead of an instant.
func _sample() -> void:
	if _nav == null:
		return
	var director = _nav._turn_director
	if director == null:
		return
	if _director == null:
		# First sighting: latch the structural facts before anything can be freed.
		_director = director
		_saw_director = true
		_loop = _nav._combat_loop
		_hud = _nav._turn_queue_hud
		_saw_hud = _hud != null
		_director_parent_is_loop = (director.get_parent() == _loop)
		if _nav._player_camera != null:
			_camera = _nav._player_camera.get_node_or_null("FocusPoint/Camera")
		if _hud != null:
			_hud_parent_is_camera = (_hud.get_parent() == _camera)
			_hud_depth = _hud.position.z
		# The announcement channel, not a poll: a turn under this policy opens and is spent
		# inside one gate call, so a per-frame read of `taker()` would see -1 every time.
		director.turn_opened.connect(_on_turn_opened)
		director.turn_committed.connect(_on_turn_committed)

	# Arm (g). Latched the first frame the screen exists, for the same reason the director is:
	# it is freed with the battle. Read off the LIVE host rather than off `mount_over_map`, so an
	# arming that moves or is removed later still has to answer here.
	var screen = _nav._formation_map_screen
	if not _saw_map_screen and screen != null and is_instance_valid(screen):
		_saw_map_screen = true
		_screen_rows = Array(screen.action_rows)

	var loop = _nav._combat_loop
	if loop != null and is_instance_valid(loop):
		if bool(loop.combat_active) != bool(_nav._combat_active):
			_mirror_split = true
		if bool(loop.combat_active):
			_saw_live_battle = true
		# Checked OUTSIDE the `combat_active` test, and that is the whole point: a
		# director that freezes writes `combat_active` false, so a freeze arm gated on
		# it can never see the thing it names. Seeded `stops_the_world = true`, the
		# gated version of this line passed while the walk hung.
		if _saw_live_battle and director.state() != TurnDirector.State.RUNNING:
			_saw_freeze = true
		# THE TURN BRAKE IS NOT ARMED ON THE WALK. A host that stops for turns needs its
		# kernel to settle a ready unit before the freeze, or the turn opens on a tile the
		# taker's sprite has not reached. The walk stops for nothing, so there is nothing to
		# settle FOR — and a brake armed here would be a real behaviour change to a battle
		# nobody is playing: every unit in it is permanently ready (nothing spends a meter
		# under this policy), so the brake would stop the whole walk from moving. Sampled
		# every live frame rather than once, because the arm the mirror above exists for is
		# the same one: an armed-then-cleared field reads clean at teardown.
		if bool(loop.combat_active) and loop.gpu_simulator != null \
				and int(loop.gpu_simulator.turn_brake_battle) != -1:
			_saw_brake = true

	# The POLICY, read separately from its consequence. `_saw_freeze` can only ever report
	# that a freeze was OBSERVED, and a stopping walk that happens to be sampled between
	# stops reports nothing — so the flag itself is asserted too, and it is what tells a
	# default-flip apart from a sampling miss.
	if bool(director.stops_the_world):
		_saw_stops_the_world = true

	if _hud != null and is_instance_valid(_hud):
		_hud_max_draws = maxi(_hud_max_draws, _hud.draws())
		_hud_max_shown = maxi(_hud_max_shown, _hud.shown_indices().size())
		_hud_was_visible = _hud_was_visible or _hud.visible


func _on_turn_opened(taker: int, _team: int) -> void:
	if taker >= 0 and not _takers.has(taker):
		_takers.append(taker)


func _on_turn_committed(_taker: int) -> void:
	_commits += 1


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
	var timed_out := _frames >= TIMEOUT_FRAMES

	# (a) PLACEMENT — the whole point of the ticket.
	_true(_saw_director, "the walk mounted a TurnDirector on its bare CombatLoop")
	_true(_director_parent_is_loop, "the director is a child of the LOOP, not of the scene")
	_true(not (_nav is CombatHost),
		"NavigatorMain is not a CombatHost — the placement had nothing to inherit from")
	if _loop != null and is_instance_valid(_loop):
		_true(_loop.turn_gate.is_valid(), "the loop's turn_gate is armed by the director")

	# (b) THE STRIP RIDES THE CAMERA (ADR-0244), and is not stranded on the near plane.
	_true(_saw_hud, "the walk mounted a TurnQueueHud")
	_true(_camera != null, "the walk's camera seat exists (PlayerCamera/FocusPoint/Camera)")
	_true(_hud_parent_is_camera, "the strip's parent is the CAMERA, not the host scene")
	_true(_hud_depth < 0.0,
		"the strip sits in FRONT of the camera (z=%.1f) — at z=0 it draws and is invisible"
			% _hud_depth)
	_true(_hud_max_draws > 0, "the strip actually repainted during the battle (draws=%d)"
		% _hud_max_draws)
	_true(_hud_max_shown > 1, "the strip drew a queue of more than one entry (max=%d)"
		% _hud_max_shown)
	_true(_hud_was_visible, "the strip was visible once the battle had a queue to show")

	# (c) THE QUEUE ADVANCES.
	_true(_commits > 0, "turns were committed during the walk's battle (%d)" % _commits)
	# Deliberately NOT "the meters are being spent" — a director that announced turns
	# and consumed nothing still changes hands here, because units die and because an
	# unspent meter stops at its own crossing value, so a growing ready set keeps
	# handing the head to a larger overshoot. `TurnDirectorTest` arm 6C is
	# what reads the buffer; this is the walk-scale claim that the queue advanced.
	_true(_takers.size() >= 3,
		"the queue advanced through several units — %d distinct takers" % _takers.size())

	# (d) THE DEFAULT IS HANDS-OFF, and the pump mirror agreed with the loop throughout.
	_true(_saw_live_battle, "the battle went live (the arms below quantify over live frames)")
	_true(not _saw_stops_the_world,
		"the walk mounted the DEFAULT policy (stops_the_world=false with navigator.stop_on_turn unset)")
	_true(not _saw_freeze,
		"the director never froze the walk (the default policy spends turns where they open)")
	_true(not _saw_brake,
		"the kernel's turn brake was armed on the walk — `stops_the_world = false` is the one flag that gates it, and under it every unit is permanently ready, so a brake would stop the walk dead")
	_true(not _mirror_split,
		"NavigatorMain._combat_active never disagreed with CombatLoop.combat_active")

	# (e) THE WALK SURVIVED — the deadlock arm.
	_true(not timed_out, "the walk finished inside the wall-clock budget")
	_true(_walk_finished, "the walk reached its terminal state (victory beat played)")
	_true(not _defeated, "no defeat halt fired")

	# (f) THE STRIP IS FREED with the battle — the camera outlives it.
	_true(_nav._turn_queue_hud == null, "the strip reference is cleared when combat ends")
	if _camera != null and is_instance_valid(_camera):
		_true(_camera.get_node_or_null("TurnQueueHud") == null,
			"no strip is left behind on the camera after the battle")

	# (g) THE GAMBIT DOOR — the row set this host arms at mount.
	_true(_saw_map_screen, "the navigator mounted its map-hosted Formation screen")
	_eq(_screen_rows, Array(StartActionMenuScript.ROWS_ADJUST),
		"and armed the ADJUSTMENT row set on it, so the menu has a Gambit row")
	_true(_screen_rows.has("Gambit"),
		"the gambit door is on this host's menu — an empty row set falls back to the ROM's five, whose row 3 is 'Remove Unit' and dispatches to nothing")

	# The SUBJECT of the run, printed whether it passed or failed: an arm that says
	# "turns were spent" is worth nothing without the count it was spent on, and the
	# same numbers are what the next session prices a policy change against.
	print("  [subject] %d turns committed, %d distinct takers, strip repainted %d time(s), "
		% [_commits, _takers.size(), _hud_max_draws]
		+ "longest queue %d, strip depth z=%.1f" % [_hud_max_shown, _hud_depth])

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
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	Tune.clear(SKIP_SLUG)
	Tune.clear(INVINCIBLE_SLUG)
	print("\n=== NavigatorTurnDirectorMountTest: %d passed, %d failed (%d frames) ===" %
		[_passed, _failed, _frames])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorTurnDirectorMountTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorTurnDirectorMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorTurnDirectorMountTest")
		get_tree().quit(0)
