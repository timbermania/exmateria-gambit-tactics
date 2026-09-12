extends Node
# test-kind: gpu
# seeded-break: revert commandability to the deployment array — in `NavigatorMain.is_commandable` return `_deployed_owned.has(_combat_loop.units[unit_index])` (the pre-fix rule). Orbonne deploys nobody, so arm (c) reds with `commandable=0/10` and arms (e)(g) red behind it; the Gariland twin `NavigatorTurnStopTest` stays GREEN throughout, which is the whole reason this process exists. A second, independent seed: in `_deploy_owned_units` drop the line that marks a deployed unit commandable and the Gariland test reds instead, with this one green — the two writers of one fact, each with its own arm. A third, for the handback arms: delete the `_end_battle()` call from `NavigatorMain._end_combat_and_advance` and the four return arms red together while their four positive controls stay green — which is the pre-fix tree exactly, and the shape of all four Orbonne reports. A fourth, narrower: drop `_hand_off_clocks_to_scenario()` from `_end_battle` and ONLY the clock arm reds, which is ADR-0083 Amendment 1 on its own. A FIFTH, for the route arm (g): delete the two `set_meta` lines from `UnitSpawn.bind_for_combat` and (g) reds with `0 of 10` resolved — the whole predetermined cast unreadable by the map host, which is reports 3 and 5 as the player met them; every other arm here stays green, because commandability and the handback do not go through the identity meta.
## BATTLE MODE ON THE PREDETERMINED BATTLE — who it hands the player, and that it gives
## everything back when it ends.
##
## `NavigatorTurnStopTest` walks Gariland; this walks Orbonne, and the reason for a second
## process is the whole finding of ADR-0265 Amendment 1:
##
## > `_deployed_owned` is filled only through `_ensure_owned_deployed`, which self-gates on
## > `_is_roster_fed` — so on a **predetermined** battle it is empty, `_commandable` is empty,
## > and `_on_director_turn_opened` finds no commandable taker for **any** unit. Every turn is
## > `call_deferred("_pass_turn")`'d and **the world never stops.**
## >
## > `NavigatorTurnStopTest` cannot see it: it walks Gariland only.
##
## Orbonne (group root 3, ENTD 387) is the one control>0 battle in the game. Before the fix
## it reported `commandable=0/10` at the F3 State panel and spent every single turn where it
## opened; the walk was strictly worse than the round-robin stop it replaced, on the one
## battle that could show it.
##
## ⚠️ ITS ENTD NAMES THREE CONTROL SLOTS AND THE BATTLE CARRIES ONE, and the arms below say
## so on purpose. `EntdBattle.combatant_slots` drops every `always_present == false` slot as
## an event-join unit, and two of Orbonne's three control slots (0x01 and 0x04) are exactly
## that — so the composed cast contains only 0x02. ADR-0265 Amendment 1's "Ramza, Delita and
## Algus — all three the player's to steer" is a true statement about the ENTD and a false
## one about the battle this host composes from it. Whether that presence gate is right for
## a control-flagged slot is a separate question about `combatant_slots`; this test PINS the
## gap rather than papering over it, so closing it there reds here and gets read.
##
## The setup is genuinely disjoint from the Gariland test's (a different battle root, a
## different cast, a different cast SOURCE), which is the split charter clause 13 permits
## rather than the one it forbids. What it is NOT is a copy: the four `combat_active`
## reconciliation arms, the Esc refusal, the marker and the badge all live over there and are
## not repeated here. This process asks one question — does the predetermined cast take the
## player's orders — and carries only the arms that share ITS setup.
##
## ⚠️ THE LIVE-STOP ARM LIVES ON GARILAND AND CANNOT LIVE HERE. Measured: Orbonne's whole
## battle is FOUR turns and then team1 is wiped (`winner=0 t0_alive=4 t1_alive=0`), and which
## four units get them is the meter's business — the one commandable unit drew none of them in
## the measured run. An arm demanding a live freeze here would be a coin toss wearing an
## assertion, so what this process pins instead is the WIRING: the count, the identity of the
## unit the ENTD writer reached, and the rule that no stop lands on a turn that is not yours.
## "Space spends a stop" is proved end-to-end by `NavigatorTurnStopTest`, on a battle long
## enough to make it hold still.
##
## [b]THE HANDBACK ARMS SHARE THIS SETUP AND SO THEY LIVE HERE[/b] (charter clause 13). This
## is the one navigator process that runs a battle to its RESOLUTION and keeps looking, which
## is exactly the frame the handback has to be read on: the world survives it, the victory
## beat plays on that world, and every one of the four Orbonne reports was a claim taken on
## entry and never returned (ADR-0177 Amendment 3, ADR-0083 Amendment 1). Splitting them into
## a second process would pay another battle's wall clock to observe the same frame.
##
## HEADFUL, real GPU — run standalone:
##   godot --path . --quit-after 20000 res://tests/NavigatorOrbonneBattleModeTest.tscn

## Orbonne. The `--battle=3` launch path (ADR-0264), driven through `DebugConfig` exactly as
## the CLI flag drives it, so this test arrives the way a human reaching this battle does.
const ORBONNE_ROOT := 3
## Orbonne's control-flagged ENTD slots. Event uids, not loop indices.
const ORBONNE_CONTROL_UIDS := [0x01, 0x02, 0x04]
## ...and how many of them survive `EntdBattle.combatant_slots` into the battle. See the
## warning in the class docstring: 0x01 and 0x04 are `always_present == false`.
const ORBONNE_COMMANDABLE_IN_BATTLE := 1

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface; one alias line keeps the
# use site spelled the way every other consumer spells it.
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const SKIP_SLUG := "navigator.skip_pre_battle"
const STOP_ON_TURN_SLUG := "navigator.stop_on_turn"

## FRAME budget, not wall-clock (charter clause 14), and for the same reason the Gariland
## twin carries one: under the agent shell's phantom present-throttle a wall-clock deadline
## expires while a healthy walk is still marching. Larger than that test's because Orbonne's
## opener is a longer fast-forward and its meters fill more slowly.
const TIMEOUT_FRAMES := 9000
const SIM_TIME_SCALE := 40.0
const PROOF_MAX_TICKS := 20000
## The uid the ENTD writer must have reached: the only control-flagged slot that survives
## `combatant_slots` into the battle.
const ORBONNE_COMMANDABLE_UID := 0x02

var _passed: int = 0
var _failed: int = 0
var _nav: Node = null
var _done: bool = false
var _frames: int = 0
var _tick_budget_raised: bool = false

var _director = null
var _saw_director: bool = false
var _saw_live_battle: bool = false
## Set once the loop this test watched has gone — the battle resolved. Orbonne's is four
## turns long, so this and not a stop count is what ends the run.
var _battle_over: bool = false
## Arm (b): the size of the booted cast, latched — the positive control for (c). A
## `commandable` count of zero out of a cast of zero is not this defect, it is an empty
## battle, and the two must not read alike (W4: a blind instrument's zero).
var _cast_size: int = 0
## Arm (c): the commandable count read off the host's own census seam, latched at its
## maximum so a teardown cannot erase it.
var _commandable_seen: int = 0
## Arm (d): the loop indices `is_commandable` accepts, latched over the whole live stretch.
var _commandable_indices: Array = []
## Arm (d): the ENTD event uid of the unit `is_commandable` accepted. Latched on the live
## frame it is read, NOT at assert time — the cast is freed with the battle and the uid
## registry is cleared with the world, so both answers are gone by then.
var _commandable_uid: int = -1
## Arm (e): turns that opened at all, and how many were the player's. Counted on the SIGNAL,
## because a turn that is not the player's is spent inside the freeze it opened in and no
## `_process` frame ever sees one standing.
## THE ROUTE ARM (reports 3 and 5). How many of the composed cast the map host can RESOLVE
## back to a Character, latched on the first live frame. A stamp arm proves the decision; only
## this proves production reaches it, which is what the last two fixes to `character_for_unit`
## each got wrong — each fixed a population and missed another. -1 = never sampled.
var _resolved_units: int = -1
var _cast_units_seen: int = 0

var _turns_opened: int = 0
var _turns_mine: int = 0
## Arm (f): a frame with the director in TURN_OPEN and the loop's own gate false.
var _saw_open_turn_freeze: bool = false
## Arm (f): set if the world ever stopped on a taker `is_commandable` refuses.
var _stopped_on_a_turn_not_mine: bool = false
var _stops_spent: int = 0

# --- The handback (ADR-0177 Amendment 3 / ADR-0083 Amendment 1) -----------------------------
## Latched WHILE the battle is live — each one is the positive control for its own return arm,
## because "the cursor is gone" and "there was never a cursor" are the same reading.
var _held_focus: bool = false
var _held_cursor: bool = false
var _held_screen: bool = false
var _held_combat_clocks: int = 0
## Read on the frame the battle is found resolved.
var _focus_after: Array = []
var _cursor_after: bool = false
var _screen_after: bool = false
var _combat_clocks_after: int = -1


func _ready() -> void:
	Tune.bind(SKIP_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(SKIP_SLUG, true)      # in-memory only (no file write from set_value)
	Tune.bind(STOP_ON_TURN_SLUG, false, {}, Tune.Persist.AUTOSAVE)
	Tune.set_value(STOP_ON_TURN_SLUG, true)
	# THE LAUNCH, through the same field `--battle=3` writes. Not `navigator_start_root`: an
	# explicit seek takes the chaining planner and a different action index, and the point is
	# to arrive by the route a player takes.
	DebugConfig.battle_seek_root = ORBONNE_ROOT

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
	# The battle RESOLVING is what ends this run — Orbonne's is four turns and then team1 is
	# gone. The frame budget is the backstop, not the plan.
	if _battle_over or _frames >= TIMEOUT_FRAMES:
		_assert_and_finish()


## Raised so the tick cap is not what ends this run — a decisive result is.
func _raise_tick_budget() -> void:
	if _tick_budget_raised or _nav == null:
		return
	var loop = _nav._combat_loop
	if loop == null:
		return
	loop.max_ticks = PROOF_MAX_TICKS
	_tick_budget_raised = true


func _sample() -> void:
	if _nav == null:
		return
	# THE LOOP IS TESTED FIRST, and that ordering is load-bearing: `_free_turn_queue_hud`
	# nulls `_turn_director` as the battle ends, so a director-first guard would return
	# before ever noticing that the battle was over and the run would burn the whole frame
	# budget waiting for something that had already happened.
	var loop = _nav._combat_loop
	if loop == null or not is_instance_valid(loop):
		if _saw_live_battle and not _battle_over:
			_battle_over = true
			_read_handback()
		return

	var director = _nav._turn_director
	if director == null:
		return
	if _director == null:
		_director = director
		_saw_director = true
		director.turn_opened.connect(_on_turn_opened)

	# The census seam the F3 State panel reads (ADR-0177 Amendment 3). Latched at its maximum
	# rather than sampled once: the battle is torn down at the end of the run and an arm that
	# read it on the wrong frame would report the teardown.
	var census: Dictionary = _nav.debug_battle_state()
	_cast_size = maxi(_cast_size, int(census.get("cast_size", 0)))
	_commandable_seen = maxi(_commandable_seen, int(census.get("commandable_count", 0)))

	if bool(loop.combat_active):
		_saw_live_battle = true
	if not _saw_live_battle:
		return
	# The claims, latched while they are STANDING. Each is the positive control for the return
	# arm below it: "no cursor now" and "no cursor ever" are the same reading otherwise (W4).
	if Focus.stack_names().has("battle"):
		_held_focus = true
	if _nav._cursor_rig != null and is_instance_valid(_nav._cursor_rig):
		_held_cursor = true
	if _nav._formation_map_screen != null and is_instance_valid(_nav._formation_map_screen):
		_held_screen = true
	_held_combat_clocks = maxi(_held_combat_clocks, _combat_owned_bodies())

	# WHO the host says is yours, read through the same public reader production uses. Latched
	# on the first live frame; the identity is recovered here rather than at assert time
	# because the units are freed with the battle.
	if _commandable_indices.is_empty():
		for i in range(loop.units.size()):
			if _nav.is_commandable(i):
				_commandable_indices.append(i)
				_commandable_uid = _uid_of(loop.units[i])

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

	if director.state() != TurnDirector.State.TURN_OPEN:
		return
	if not bool(loop.combat_active):
		_saw_open_turn_freeze = true
	# Annotated, not inferred: `director` is untyped here, so `:=` cannot see through
	# `taker()` and the file fails to PARSE — which reads as a HANG, not as a failure.
	var taker: int = director.taker()
	if not _nav.is_commandable(taker):
		_stopped_on_a_turn_not_mine = true
	# Space, through the real action, so a stop that DOES land cannot hang the run.
	_press(&"battle_start")
	if director.taker() != -1 or director.state() != TurnDirector.State.TURN_OPEN \
			or bool(loop.combat_active):
		_stops_spent += 1


## The real action, through the real `_unhandled_input` — calling `_start_battle()` directly
## would prove the body and skip the binding, which is the half that can rot.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)


func _on_turn_opened(taker: int, _team: int) -> void:
	if taker < 0:
		return
	_turns_opened += 1
	# `NavigatorMain`'s own handler is connected first and only defers, so `is_commandable`
	# reads the same here as it did there.
	if _nav.is_commandable(taker):
		_turns_mine += 1


func _assert_and_finish() -> void:
	if _done:
		return
	var timed_out := _frames >= TIMEOUT_FRAMES

	_true(_saw_director, "the launched battle mounted a TurnDirector")
	_true(_saw_live_battle, "Orbonne went live (the arms below quantify over live frames)")
	_true(not timed_out, "the battle resolved inside the %d-frame budget" % TIMEOUT_FRAMES)

	# (b) THE POSITIVE CONTROL. Without it a `commandable == 0` and an empty battle read
	# alike, and "nobody is commandable" would be indistinguishable from "nobody is here".
	_true(_cast_size > 0, "the predetermined cast booted — %d unit(s)" % _cast_size)

	# (c) THE DEFECT. ADR-0265 dec. 3 resolved steerability off `_deployed_owned`, which a
	# predetermined battle never fills, so this battle handed the player nobody.
	_true(_commandable_seen > 0,
		"Orbonne's ENTD cast is COMMANDABLE — %d of %d" % [_commandable_seen, _cast_size])

	# THE GAP, PINNED. Three control-flagged slots in the ENTD, one in the battle: the other
	# two are `always_present == false` and `EntdBattle.combatant_slots` drops them. Asserted
	# as an equality against a named constant rather than as `> 0`, so closing that gate
	# somewhere else REDS here and gets read instead of silently changing what the player
	# steers on the game's first battle.
	_true(_commandable_seen == ORBONNE_COMMANDABLE_IN_BATTLE,
		"%d of the ENTD's %d control slots reach the composed cast — got %d"
			% [ORBONNE_COMMANDABLE_IN_BATTLE, ORBONNE_CONTROL_UIDS.size(), _commandable_seen])

	# (d) AND IT IS THE RIGHT BODY. A count alone would be satisfied by marking any unit
	# commandable; this is the arm that says the ENTD writer landed the flag on the unit whose
	# slot carries it, through the uid registry rather than through the writer's own rule.
	_true(_commandable_indices.size() == 1,
		"exactly one loop index is commandable — %s" % str(_commandable_indices))
	_eq(_commandable_uid, ORBONNE_COMMANDABLE_UID,
		"the commandable unit is ENTD uid 0x%02X" % ORBONNE_COMMANDABLE_UID)

	# (e) The other positive control: turns have to have OPENED for (f) to be about anything.
	_true(_turns_opened > 0, "turns opened on this battle — %d of them (%d the player's)"
		% [_turns_opened, _turns_mine])

	# (f) NO STOP ON A TURN THAT IS NOT YOURS. Non-vacuous by (e): every turn this battle
	# opened in the measured run was an enemy's, and not one of them froze the world for a
	# press the player could not answer — which is the pre-ADR-0265 behaviour this rules out.
	_true(not _stopped_on_a_turn_not_mine, "no stop landed on a NON-commandable taker")
	# ...and if one of the player's turns did come up, it stopped the world and Space ended it.
	# Reported either way: a zero here is a fact about the meter, not about the fix, and the
	# end-to-end stop is proved on Gariland where the battle is long enough to hold still.
	if _turns_mine > 0:
		_true(_saw_open_turn_freeze,
			"the player's turn STOPPED the world (director TURN_OPEN, combat_active false)")
		_true(_stops_spent > 0, "Space ended it")
	else:
		print("  [note] no commandable turn came up in %d turns — the live-stop arms are"
			% _turns_opened + " not exercised this run (see the class docstring)")

	# (g) THE WHOLE CAST HAS AN IDENTITY THE MAP HOST CAN READ (reports 3 and 5). Orbonne is
	# the population that failed: every one of its units is ENTD-spawned, so not one of them
	# passes through `UnitSpawn.build`, and before the stamp moved to the BIND seam
	# `character_for_unit` answered null for all of them. On the map host a null is an empty
	# tile — no vitals, no nameplate, and Tab refusing to open the screen.
	_true(_resolved_units >= 0,
		"the cast was sampled while the battle was live (the arm below is not vacuous)")
	_eq(_resolved_units, _cast_units_seen,
		"every composed unit resolves to a Character — %d of %d"
			% [_resolved_units, _cast_units_seen])

	# ---- THE HANDBACK (ADR-0177 Amendment 3, ADR-0083 Amendment 1) -------------------------
	# Four claims, each with the positive control that took it. Without the paired latch every
	# one of these arms passes on a battle that never happened.
	_true(_battle_over, "the battle resolved and the handback edge was reached")

	_true(_held_focus, "battle mode was PUSHED (the arm below is not vacuous)")
	_true(not _focus_after.has("battle"),
		"the `battle` focus state was POPPED — stack after: %s" % str(_focus_after))

	_true(_held_cursor, "a CursorRig stood during the battle (the arm below is not vacuous)")
	_true(not _cursor_after, "the cursor rig was freed by the handback")

	_true(_held_screen, "the map-hosted Formation screen was mounted (ditto)")
	_true(not _screen_after, "the Formation screen was freed by the handback")

	# The one that made the survivors teleport through scenario 6: `clock_owner` was written
	# COMBAT in exactly one place and SCENARIO in exactly one other (spawn), so after a battle
	# every survivor rode a clock nothing pumped and `_advance_scenario_anim` skipped it by
	# design. The victory beat then moved them with nothing animating the move.
	_true(_held_combat_clocks > 0,
		"bodies were COMBAT-owned during the battle — %d (the arm below is not vacuous)"
			% _held_combat_clocks)
	_eq(_combat_clocks_after, 0,
		"every surviving body is back on the SCENARIO clock after the handback")

	_finish()


## Read the four claims on the frame the battle is found resolved. `_end_battle` runs inside
## `_end_combat_and_advance`, one line before the loop is freed, so by the time the loop reads
## null the handback has already happened — this is the first frame that can see its result.
func _read_handback() -> void:
	_focus_after = Focus.stack_names()
	_cursor_after = _nav._cursor_rig != null and is_instance_valid(_nav._cursor_rig)
	_screen_after = _nav._formation_map_screen != null \
		and is_instance_valid(_nav._formation_map_screen)
	_combat_clocks_after = _combat_owned_bodies()


## How many bodies in the tree are COMBAT-owned right now. Counted off the `units` GROUP and
## not off the loop, deliberately: the defect ADR-0083 Amendment 1 names is a survivor left
## COMBAT-owned with no `CombatLoop` to tick it, and the loop is the thing that is gone.
func _combat_owned_bodies() -> int:
	var n := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit != null and is_instance_valid(unit) and "clock_owner" in unit \
				and int(unit.clock_owner) == ClockOwner.COMBAT:
			n += 1
	return n


## The event uid `unit` is registered under, or -1. The registry is the ENTD's own name for a
## body, so this recovers "which slot is this" without re-deriving it from the flag under test.
func _uid_of(unit) -> int:
	if unit == null or not is_instance_valid(unit) or _nav == null:
		return -1
	for uid in _nav._units_by_id.keys():
		if _nav._units_by_id[uid] == unit:
			return int(uid)
	return -1


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(condition: bool, name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	_done = true
	Engine.time_scale = 1.0
	print("\n=== NavigatorOrbonneBattleModeTest: %d passed, %d failed (%d frames) ==="
		% [_passed, _failed, _frames])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorOrbonneBattleModeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorOrbonneBattleModeTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorOrbonneBattleModeTest")
		get_tree().quit(0)
