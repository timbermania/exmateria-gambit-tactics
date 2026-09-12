extends Node
# test-kind: gpu
# seeded-break: force the gate off — `NavigatorMain.stop_on_turn_armed` -> `return false`. The policy arm, the freeze arm, the Esc-refusal arm and the Space arm all red together, because with no freeze there is no stop for any of them to be about. A second, independent seed: in `_mount_turn_director` drive the mirror off `turn_committed` instead of `resumed` (`_turn_director.turn_committed.connect(func(_t): _on_director_resumed())`) and the MIRROR arm reds on the first double-ready stop, where a commit emits while the world is still frozen. A third, for the ADR-0265 arms: delete the `if not is_commandable(taker):` branch in `_on_director_turn_opened` and arm (g) reds on the first enemy turn — the pre-0265 behaviour exactly. A fourth: drop the `_enter_command_cursor()` call from `run_combat` and arm (i) reds, because `skip_pre_battle` is set here and nothing else mounts a rig. A fifth, for the route arm (k): delete the two `set_meta` lines from `UnitSpawn.bind_for_combat` and (k) reds on the ENTD half of Gariland's cast — Delita and the five reds resolve to null while the five roster-deployed units stay resolvable, because those went through `UnitSpawn.build`. That SPLIT is why the arm lives on both battles: here it reds partially, on Orbonne it reds completely.
## The OPTED-IN half of the walk's turn policy: `navigator.stop_on_turn` (ADR-0264).
##
## `NavigatorTurnDirectorMountTest` owns the default — hands-off, the walk never freezes,
## and the three end-to-end walks depend on it. This owns the other side, and it cannot
## share that test's process: the two policies are two different walks (a stopping walk
## does not reach victory on its own), so the setup is genuinely disjoint and the split is
## the one charter clause 13 permits rather than the one it forbids.
##
## What makes the toggle more than a flipped flag is that `TurnDirector` freezing the loop
## makes it a SECOND writer of `CombatLoop.combat_active`, which `NavigatorMain` has always
## documented as `_set_combat_live`'s alone. Four of the six arms below are about that
## reconciliation and not about the stop itself:
##
##   (a) THE POLICY IS READ: the walk mounts `stops_the_world = true` when the slug is set.
##       Paired with (f), which proves the slug is the thing that decided it.
##   (b) THE WORLD ACTUALLY STOPS: a frame is observed with the director in TURN_OPEN and
##       the loop's `combat_active` false. Asserted as an OBSERVATION and not as a flag —
##       (a) already reads the flag, and a policy that never produced a stop would pass (a)
##       and hang here.
##   (c) THE MIRROR FOLLOWS: `NavigatorMain._combat_active` agrees with
##       `CombatLoop.combat_active` on every frame, through the freezes. The same invariant
##       the mount test reads on the default side, which is the point — it holds under BOTH
##       policies, so it stays one invariant instead of becoming a per-policy special case.
##   (d) ESC RAISES THE MODAL PAUSE AND CANNOT THAW THE FREEZE. This is the documented hazard
##       in its exact form: the world is frozen by the DIRECTOR, and a pause that flipped
##       `combat_active` would run the battle out from under an open turn. Esc is ALLOWED here
##       (cluster 41: a pause is available in every state, including a frozen one) and what is
##       asserted is that it saves and restores rather than assumes. Closed in the same frame,
##       because the modal swallows the Space that arm (e) needs. Driven through the real
##       `_unhandled_input` action, not by calling the handler.
##   (e) SPACE SPENDS IT, through the same real action: the turn commits, the world resumes,
##       and the battle advances through several distinct takers. This is also the
##       not-a-hang arm — a stop nothing can end is a hang with better prose. The run ends
##       on the resume rather than on the stop count, because the director drains: three
##       stops can land in a handful of frames with the world never live between them.
##   (f) AUTOPLAY DOES NOT SUPPRESS IT. The obvious design — fold the stop into the
##       `navigator.autoplay` profile, since its set state is the one that waits for a human
##       — is the one this rejects, and the whole test runs under autoplay to say so.
##       Autoplay is a state a human works in (the natural thing to have on while walking to
##       a battle you then want to stop in), the profile otherwise only ever turns gates ON,
##       and the sweep it would have protected passes `--quit-after` and reads its line
##       before combat exists. What protects the unattended walks instead is a PIN in each
##       of their `_ready`s — five of them.
##
## Three more arms landed with ADR-0265, when the stop stopped being a step-debugger and
## became a TURN. They share this setup exactly (charter clause 13) — the same walk, the
## same freeze, the same frames — so they live here rather than in a fourth navigator
## process:
##
##   (g) IT STOPS ON YOUR TURNS ONLY. Every stop observed was on a COMMANDABLE taker, and
##       the enemy/guest turns — counted on the signal, because they are spent inside the
##       same freeze and no `_process` frame sees one standing — went by without one.
##   (h) AND IT LOOKS LIKE A TURN: the AT marker sat on the taker and the badge named them
##       and the key, on every frame a stop was standing.
##   (i) THERE IS A CURSOR. This test sets `skip_pre_battle`, which is precisely the path on
##       which `_enter_command_cursor` used to be unreachable.
##
## HEADFUL, real GPU — run standalone:
##   godot --path . --quit-after 20000 res://tests/NavigatorTurnStopTest.tscn

const SKIP_SLUG := "navigator.skip_pre_battle"
const INVINCIBLE_SLUG := "navigator.owned_invincible"
const AUTOPLAY_SLUG := "navigator.autoplay"
## Mirrors NavigatorMain.STOP_ON_TURN_SLUG — the subject of this test, set TRUE here.
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

## FRAME budget, not wall-clock (charter clause 14b), and for the same reason the mount test
## carries one: under the agent shell's phantom present-throttle a wall-clock deadline
## expires while a healthy walk is still marching.
const TIMEOUT_FRAMES := 7200
const SIM_TIME_SCALE := 40.0
const PROOF_MAX_TICKS := 14000
## How many stops to spend before the arms are satisfied. Three, because (e) claims the
## battle ADVANCES and one commit cannot show that — and because the drain inside
## `TurnDirector.commit` means a double-ready stop re-opens without resuming, which is
## exactly the case the `resumed`-vs-`turn_committed` choice in (c) is about.
const STOPS_WANTED := 3

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _done: bool = false
var _frames: int = 0
var _tick_budget_raised: bool = false

# --- What the sampling collects ----------------------------------------------
var _director = null
var _loop = null
var _saw_director: bool = false
## Set on any frame the mounted director carried the STOPPING policy — arm (a). Latched,
## because the director is freed with the battle and a freed Object reads as null.
var _saw_stops_the_world: bool = false
## Set the first frame the loop ran at all; the arms below quantify over live frames.
var _saw_live_battle: bool = false
## Arm (b): a frame with the director in TURN_OPEN and the loop frozen.
var _saw_open_turn_freeze: bool = false
## Arm (c): set the first frame the pump mirror and the loop's own gate disagree.
var _mirror_split: bool = false
## Arm (d): set if Esc, pressed under an open turn, ever left the world running.
var _esc_broke_the_freeze: bool = false
var _esc_was_tried: bool = false
## Arm (d): Esc raised the modal pause, and a second Esc put it away again.
var _esc_raised_the_screen: bool = false
var _esc_would_not_close: bool = false
## Arm (e).
var _stops_spent: int = 0
var _takers: Array = []
## Set if the world was ever observed live again AFTER a stop was spent — the resume half.
var _saw_resume_after_stop: bool = false
## Arm (g): set if the world ever STOPPED on a taker the player may not steer. A violation
## flag and not a tally, because one is the whole failure.
var _stopped_on_a_turn_not_mine: bool = false
## Arm (g)'s not-vacuous half: turns opened for a non-commandable unit (guest or enemy). If
## this is zero the arm above proved nothing — a battle with no enemy turns in it.
var _turns_not_mine: int = 0
## Arm (h): set if a stop was ever standing with the AT marker NOT on its taker.
var _marker_missed_a_stop: bool = false
## Arm (h)'s other half: set if the badge ever failed to name the open turn.
var _badge_missed_a_stop: bool = false
## Arm (i): a CursorRig existed while the battle was live. The seek path skips pre-battle,
## which is where the cursor used to be mounted — this is the arm for that defect.
## THE ROUTE ARM (reports 3 and 5). How many of the composed cast the map host can RESOLVE
## back to a Character, latched on the first live frame. A stamp arm proves the decision; only
## this proves production reaches it, which is what the last two fixes to `character_for_unit`
## each got wrong — each fixed a population and missed another. -1 = never sampled.
var _resolved_units: int = -1
var _cast_units_seen: int = 0

var _saw_cursor_rig: bool = false
## Arm (j): the TACTICAL STOP, probed once on a RUNNING battle after the turn arms are done.
var _tactical_probe_done: bool = false
var _tactical_stop_froze: bool = false
var _tactical_stop_resumed: bool = false
var _tactical_badge: String = ""


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

	# Same deck as the mount test: skip the pre-battle park, stack the odds so the battle is
	# a battle and not a rout in either direction.
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)
	Tune.bind(INVINCIBLE_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(INVINCIBLE_SLUG, true)
	# Pinned ON, and this is arm (f)'s setup rather than a convenience: it makes the process
	# this test runs in an autoplay process, so every battle arm below is ALSO evidence that
	# the stop survives the profile. Nothing else here needs it — the two gates autoplay
	# would otherwise supply are pinned explicitly above, so the ON is doing one job.
	Tune.bind(AUTOPLAY_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(AUTOPLAY_SLUG, true)
	# THE SUBJECT.
	Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(STOP_ON_TURN_SLUG, true)

	Engine.time_scale = SIM_TIME_SCALE
	_frames = 0

	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	add_child(_nav)


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	_raise_tick_budget()
	_sample()
	# BOTH, not just the count. `TurnDirector.commit` DRAINS — two units ready at one stop
	# re-open without resuming — so the three stops can all land inside a handful of frames
	# with the world never observed live between them. Stopping on the count alone asserted
	# the resume arm before there was a frame it could be true on, which is how it first
	# failed. The frame budget is still the backstop.
	if _frames >= TIMEOUT_FRAMES:
		_assert_and_finish()
		return
	if _stops_spent >= STOPS_WANTED and _saw_resume_after_stop:
		# Arm (j) runs LAST and only once, on a frame with the battle running and no turn open:
		# it is the one arm that needs the world NOT stopped, so it cannot share a frame with
		# the others. When it has run (or cannot), the run is over.
		if _probe_tactical_stop():
			_assert_and_finish()


func _raise_tick_budget() -> void:
	if _tick_budget_raised or _nav == null:
		return
	var loop = _nav._combat_loop
	if loop == null:
		return
	loop.max_ticks = PROOF_MAX_TICKS
	_tick_budget_raised = true


## Sampled every frame, because everything the arms need is only true WHILE the battle
## exists — and because the freeze/resume pair this test is about is a per-frame fact.
func _sample() -> void:
	if _nav == null:
		return
	var director = _nav._turn_director
	if director == null:
		return
	if _director == null:
		_director = director
		_saw_director = true
		_loop = _nav._combat_loop
		director.turn_opened.connect(_on_turn_opened)
	if bool(director.stops_the_world):
		_saw_stops_the_world = true

	var loop = _nav._combat_loop
	if loop == null or not is_instance_valid(loop):
		return
	if bool(loop.combat_active) != bool(_nav._combat_active):
		_mirror_split = true
	if bool(loop.combat_active):
		_saw_live_battle = true
		if _stops_spent > 0:
			_saw_resume_after_stop = true

	# THE ROUTE (reports 3 and 5). Read through `FormationMapHost.character_for_unit`, the
	# static the map host itself calls on every cursor move — not through the meta directly,
	# because the meta being present and the RESOLVER answering are two claims and it is the
	# second one the player sees. Latched once: the cast does not change mid-battle and the
	# units are freed with it.
	if _resolved_units < 0 and not loop.units.is_empty():
		var resolved := 0
		for u in loop.units:
			if FormationMapHost.character_for_unit(u) != null:
				resolved += 1
		_cast_units_seen = loop.units.size()
		_resolved_units = resolved
	if not _saw_live_battle:
		return

	if director.state() != TurnDirector.State.TURN_OPEN:
		return
	# A STOP is standing. The two key arms are driven here, in the state they are about, and
	# in this order: Esc must be a no-op (d), and only then does Space end it (e). Running
	# them on the same stop is deliberate — it is the same frozen world, so a Space that
	# worked would otherwise leave open whether Esc had already thawed it.
	if not bool(loop.combat_active):
		_saw_open_turn_freeze = true

	# (g)(h)(i) THE STOP IS A TURN, NOT A PAUSE (ADR-0265). Read here and not on the signal
	# because these are facts about the frame the stop is STANDING on — the beat arms inside
	# `turn_opened` and the badge is polled from `_process`, so a signal-time read would be
	# asking before either had run.
	# Annotated, not inferred: `director` is untyped here (the test holds it as `var`), so
	# `:=` cannot see through `taker()` and the file fails to PARSE — which reads as a hang,
	# not as a failure, because a script that never loaded never reaches `_finish`.
	var taker: int = director.taker()
	if not _nav.is_commandable(taker):
		_stopped_on_a_turn_not_mine = true
	else:
		if _nav._beat.marker_unit != taker:
			_marker_missed_a_stop = true
		var badge := String(_nav.stop_badge_text())
		if not badge.begins_with("YOUR TURN:") or not ("Space" in badge):
			_badge_missed_a_stop = true
	if _nav._cursor_rig != null and is_instance_valid(_nav._cursor_rig):
		_saw_cursor_rig = true

	# ESC RAISES THE MODAL PAUSE (cluster 41). It is allowed over an open turn — the clock is
	# already stopped, so refusing costs the player a key that visibly does nothing — and what
	# matters is that it neither thaws the world nor leaves it thawed on close. Closed again in
	# the SAME frame, because a modal left up swallows the Space below it and a stop nothing can
	# end is a hang with better prose.
	_press(&"battle_pause")
	_esc_was_tried = true
	if bool(loop.combat_active):
		# Esc thawed a world the director froze — the second-writer hazard, live.
		_esc_broke_the_freeze = true
	if _nav.pause_screen_open():
		_esc_raised_the_screen = true
	_press(&"battle_pause")
	if _nav.pause_screen_open():
		_esc_would_not_close = true
	if bool(loop.combat_active):
		_esc_broke_the_freeze = true
	_press(&"battle_start")
	# Space either spent this turn or drained into the next one; both END this stop, and
	# `_stops_spent` counts stops ENDED, which is the honest name for what was proved.
	if director.taker() != -1 or director.state() != TurnDirector.State.TURN_OPEN \
			or bool(loop.combat_active):
		_stops_spent += 1


## ARM (j) — THE TACTICAL STOP (cluster 41), through the real Space action on a RUNNING
## battle. Space is ONE RULE reaching three states; arms (a)-(i) exercise the turn-commit arm
## and the pre-battle park is skipped in this process, so this is the third — and it is the
## state this host did not have at all until ADR-0177 Amendment 3 step 5.
##
## Returns true when it has run (or when the run should end anyway), false to wait for a frame
## it can run on. Both presses land in ONE frame: `push_input` dispatches synchronously and
## `_set_combat_live` writes both flags in the same call, so the intermediate state is readable
## between them without waiting.
func _probe_tactical_stop() -> bool:
	if _tactical_probe_done:
		return true
	var loop = _nav._combat_loop if _nav != null else null
	if loop == null or not is_instance_valid(loop) or not bool(loop.combat_active):
		return false
	if _nav._beat.running():
		return false   # the beat swallows every key; wait for it to land
	var director = _nav._turn_director
	if director == null or director.state() != TurnDirector.State.RUNNING:
		return false
	_tactical_probe_done = true
	_press(&"battle_start")
	_tactical_stop_froze = not bool(loop.combat_active)
	_tactical_badge = String(_nav.stop_badge_text())
	_press(&"battle_start")
	_tactical_stop_resumed = bool(loop.combat_active)
	return true


## The real action, through the real `_unhandled_input`. `NavigatorMain`'s handler tests
## `event.is_action_pressed` with no `event is InputEventKey` guard ahead of it (unlike
## `GambitBattle`'s), so an action-shaped press reaches it — calling `_start_battle()`
## directly would prove the body and skip the binding, which is the half that can rot.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)


func _on_turn_opened(taker: int, _team: int) -> void:
	if taker < 0:
		return
	if not _takers.has(taker):
		_takers.append(taker)
	# Counted on the SIGNAL and not in `_sample`, because a turn that is not the player's is
	# spent inside the same freeze (`call_deferred`) and no `_process` frame ever sees it
	# standing. That invisibility is the feature; this is how the arm proves it happened.
	# `NavigatorMain`'s own handler is connected first and only defers, so `is_commandable`
	# reads the same here as it did there.
	if not _nav.is_commandable(taker):
		_turns_not_mine += 1


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

	_true(_saw_director, "the walk mounted a TurnDirector")
	_true(_saw_live_battle, "the battle went live (the arms below quantify over live frames)")

	# (a) THE POLICY IS READ.
	_true(_saw_stops_the_world,
		"the walk mounted stops_the_world=TRUE with navigator.stop_on_turn set")

	# (b) THE WORLD ACTUALLY STOPS.
	_true(_saw_open_turn_freeze,
		"a turn opened with the loop frozen (director TURN_OPEN, combat_active false)")

	# (c) THE MIRROR FOLLOWS — the same invariant the mount test reads on the default side.
	_true(not _mirror_split,
		"NavigatorMain._combat_active never disagreed with CombatLoop.combat_active")

	# (d) ESC REFUSES under an open turn — the second-writer hazard, in its exact form.
	_true(_esc_was_tried, "Esc was actually pressed under an open turn (the arms below are not vacuous)")
	_true(not _esc_broke_the_freeze,
		"Esc under an open turn left the world frozen (the director owns that stop)")
	_true(_esc_raised_the_screen, "Esc raised the MODAL pause over the open turn")
	_true(not _esc_would_not_close, "and a second Esc put it away again")

	# (e) SPACE SPENDS IT, and the battle advances — the not-a-hang arm.
	_true(_stops_spent >= STOPS_WANTED,
		"Space ended %d of %d stops" % [_stops_spent, STOPS_WANTED])
	_true(_saw_resume_after_stop, "the world ran again after a stop was spent")
	_true(_takers.size() >= 2,
		"the stops were on several distinct units — %d takers" % _takers.size())
	_true(not timed_out, "the stops were reached inside the frame budget")

	# (j) THE TACTICAL STOP — Space's third arm, on a running battle with no turn open.
	_true(_tactical_probe_done, "the tactical stop was probed on a RUNNING battle (not vacuous)")
	_true(_tactical_stop_froze, "Space STOPPED the running world")
	_true(_tactical_stop_resumed, "and Space started it again")
	# ...and the badge said which stop it was. A tactical stop and a modal pause are two
	# motionless battlefields ended by two different keys; naming the wrong one is worse than
	# naming none, because the player presses what they are told.
	_true(_tactical_badge.begins_with("STOPPED") and "Space" in _tactical_badge,
		"the badge named the tactical stop and its key — got %s" % _tactical_badge)

	# (f) AUTOPLAY DOES NOT SUPPRESS IT. Every arm above already ran in an autoplay process,
	# so this reads the predicate that decided it — the pair, not the predicate alone: (a) is
	# what proves this host consults `stop_on_turn_armed`, and this is what proves the answer
	# it gives is not a function of the profile.
	_true(bool(Tune.get_value(AUTOPLAY_SLUG)),
		"the process really is an autoplay process (the arm below is not vacuous)")
	_true(bool(_nav.stop_on_turn_armed()),
		"the stop stays armed under navigator.autoplay (it is not in the profile)")

	# (g) THE STOP IS FOR YOUR TURNS ONLY (ADR-0265). Before this, the spine had no
	# steerability concept at all, so the world stopped on every unit in the round-robin and
	# asked for a Space on turns the GPU was still driving — a pause button with extra steps.
	# The counter is the not-vacuous half: without enemy turns having opened, "we never
	# stopped on one" is a claim about an empty set.
	_true(_turns_not_mine > 0,
		"turns opened for units the player may not steer — %d of them" % _turns_not_mine)
	_true(not _stopped_on_a_turn_not_mine,
		"every stop was on a COMMANDABLE taker; the other %d were spent where they opened"
			% _turns_not_mine)

	# (h) AND IT LOOKS LIKE ONE. The AT marker is on the taker and the badge names them —
	# the two things the player sees, asserted on every frame a stop was standing rather than
	# once. `NavigatorTurnStopTest` cannot see the camera travel land (it is a frame counter
	# on a rig this test drives at 40x); `tools/probe_nav_turn_beat.tscn` is where that is
	# looked at.
	_true(not _marker_missed_a_stop, "the AT marker was on the taker for every stop")
	_true(not _badge_missed_a_stop, "the badge named the open turn and its key for every stop")

	# (i) THERE IS A CURSOR ON THE BATTLEFIELD. This test runs with `skip_pre_battle` set,
	# which is the path on which `_enter_command_cursor` used to be unreachable — the rig was
	# mounted below that gate's early return, so "play battle N" had no map cursor at all.
	_true(_saw_cursor_rig, "the battle had a CursorRig while a turn was open")

	# (k) THE WHOLE CAST HAS AN IDENTITY THE MAP HOST CAN READ (reports 3 and 5). The
	# roster-fed twin of Orbonne's arm, and the reason both exist: Gariland's cast is MIXED —
	# five units deployed from the roster through `UnitSpawn.build` (stamped since ADR-0180
	# Amendment 2) beside Delita and five ENTD reds that never touch it. Before the stamp
	# moved to the BIND seam this arm reds on the ENTD half only, which is exactly the split
	# the player saw: a plate over your own units and nothing over anyone else's.
	_true(_resolved_units >= 0,
		"the cast was sampled while the battle was live (the arm below is not vacuous)")
	_true(_resolved_units == _cast_units_seen,
		"every composed unit resolves to a Character — %d of %d"
			% [_resolved_units, _cast_units_seen])

	# The SUBJECT of the run, printed pass or fail: an arm that says "Space ended the stops"
	# is worth nothing without the counts, and these are what the next session prices a
	# policy change against.
	print("  [subject] %d stop(s) ended over %d frames, %d distinct takers, mirror split=%s"
		% [_stops_spent, _frames, _takers.size(), str(_mirror_split)])
	_finish()


func _true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	print("NavigatorTurnStopTest: %d passed, %d failed" % [_passed, _failed])
	print("TEST_RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(0 if _failed == 0 else 1)
