extends "res://src/scenes/GambitBattle.gd"

## The GambitBattle host, end to end: one integer in, a battle that ends by annihilation
## out (ADR-0242, #892). A subclass of the real host, not a re-implementation of it — the
## thing under test is the boot and the deployment, so a harness that stood its own cast
## up would be testing the harness.
##
## Deliberately NOT `--combat-autostart`. The auto-fill path is one line and a rig that
## used it would never touch the assignment, which is where the whole decision lives; arm
## 3 drives the CURSOR instead, through the same `_on_cursor_confirmed` a player presses.
##
##   1. **One integer is the whole boot.** Scenario 9 hands over the map, the cast and the
##      zone. The arm that matters is that every ROM-placed unit stands on the tile the
##      ROM gave it: the ATTACK.OUT zone table is player start tiles only, so an
##      implementation that ran the owned side's zone assignment over the enemies too
##      would look fine until you noticed the enemy party standing in your deployment box.
##   2. **Deployment is a turn with the clock stopped, and there is no GPU battle yet.**
##      `state == DEPLOYMENT`, `taker == -1`, the world frozen, and
##      `combat_loop.gpu_simulator == null` — that last one is the load-bearing assertion.
##      It is what "placements stay CPU-side and land in ONE write at commit" MEANS, and
##      nothing else in the tree checks it.
##   2b. **Auto-place fills and does not start.** The F3 debug toggle
##      (`DebugConfig.gambit_auto_deploy`) is the "stop hand-placing five units on every
##      reload" convenience; the arm holds it to being a FILL — cap reached, deployment still
##      open, no GPU battle — and to never overwriting a placement already made.
##   3. **The cursor is the editor, and the pick is a LATCH.** The first ○ moves nothing —
##      it lights the tile `SELECTED` and frees the cursor; the second moves or swaps, and a
##      misfire outside the zone refuses and KEEPS the selection. Plus ✕'s two meanings (let
##      go / recall), two refusals (the mandatory unit will not bench, and once he IS benched
##      the tile he vacated stops accepting anybody else — the RESERVE, asserted where the
##      player meets it rather than at the commit), the facing every drop computes, and the
##      zone paint read back off the rendered tiles.
##   4. **Commit is the one write.** The simulator appears, sized by the SQUAD; the bench
##      is not in the battle at all; and `_commandable` is exactly the units the player
##      deployed — the guest (Delita, ENTD-blue on team0) fights beside you and is NOT
##      yours to steer, which is the host's answer to a question the director refuses.
##   4a. **A turn OPENS WITH A BEAT** (`docs/TURN-OPEN-BEAT-DESIGN.md`) — the camera travels to
##      the taker, input is refused for the length of the travel, the cursor lands on the
##      taker's cell, `Home` brings it back after the player roams, and the AT marker seam is
##      shown on open and hidden on commit. It shares arm 4b's setup exactly (a commandable turn
##      held open on a live battle), which is why it is an arm here and not a second process —
##      TEST-CHARTER clause 13.
##   4d. **Space is STOP/GO and Esc is the classic pause.** Space commits an open turn, and on the
##      between-turn stretch it is a plain toggle on whether the battle runs — there is no state
##      in which it does nothing. Esc raises a modal pause screen over any state, swallows even
##      Space, and restores exactly what it paused over (a stopped clock stays stopped). ○ over another unit opens that unit's screen
##      WITHOUT committing, which is a regression arm: two listeners share `cursor_confirmed` and
##      the screen reads `can_open` at delivery, so a commit made in this host's handler used to
##      flip the predicate mid-emission and fire both.
##   4e. **A TURN OPENS ON A UNIT THAT IS STANDING ON ITS OWN TILE.** The reported bug:
##      logical position is the DESTINATION for the whole duration of a movement step, so a
##      freeze that landed mid-step opened the turn — and travelled the camera — to a cell the
##      taker's sprite had not reached, which reads as a turn opening on empty ground. The
##      kernel's turn brake settles a ready unit first (`config.turn_brake_battle`), and the
##      gate refuses to freeze while any ready unit is mid-step. Carries its own positive
##      control, because "no taker was ever mid-step" is what a battle where NOBODY walks says
##      too.
##   5. **A turn freezes the world on the exact tick.** Observed from inside the signal,
##      because that is the only place "frozen" is checkable before somebody commits.
##   6. **Annihilation ends the battle.** The ROM's own rule (`Victory`: >=1 player
##      standing, 0 enemies standing), reached by playing the real Gariland fight with
##      every turn committed unchanged — which is also the first time anyone has watched
##      the between-turn stretch at its real rate.
##
## Run: "$GODOT" --path . res://tests/GambitBattleTest.tscn   (timeout, not --quit-after)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.


const SCENARIO := 9
const BATTLE_SEED := 424242
## Belt on every drive loop. A director that never re-opens would otherwise hang, and a
## hang is a worse verdict than a failure because nothing names it.
const MAX_FRAMES := 12000

var _passed: int = 0
var _failed: int = 0
## (taker, combat_active) from inside `turn_opened` — "frozen" is only checkable there.
var _freezes: Array = []
## `turn_marker_unit` as of each `turn_committed`, read from INSIDE the signal for the same
## reason `_freezes` is: `TurnDirector.commit` DRAINS, so by the time the call returns a second
## ready unit may already have opened a turn and put the marker back up on ITSELF. Read after
## the fact, "the marker came down" is an assertion about the battle seed; read here it is an
## assertion about the host. (Arm 4b's `not adjustment.is_open() or …` note is the same trap,
## found the same way.)
var _marker_at_commit: Array[int] = []
var _marker_node_at_commit: Array[bool] = []
## While true, a player turn is NOT auto-committed — arm 4b needs one held open long enough to
## edit on. Without it the drive loop below spends every commandable turn the instant it opens and
## the arm waits forever for one that is already gone.
var _hold_turns: bool = false
## Arm 4e's hold, and a WIDER one: `_hold_turns` only stays the test's own auto-pass for a
## COMMANDABLE taker, while the host spends an enemy's turn itself
## (`GambitBattle._on_turn_opened` -> `call_deferred("_pass_turn")`). Arm 4e has to hold every
## turn, because the enemies are the units the rollout AI actually walks — sampling only the
## player's turns would sample the units least likely to be mid-step.
var _hold_every_turn: bool = false
var _turns: int = 0


func get_test_name() -> String:
	return "GambitBattleTest"


func _ready() -> void:
	DebugConfig.combat_seed = BATTLE_SEED
	DebugConfig.active_scenario_id = SCENARIO
	# The assignment is the subject; auto-fill would skip it.
	DebugConfig.combat_autostart = false
	# The auto-place debug toggle is AUTOSAVE, so a developer who ticked it once has it
	# committed in `config/tune_overrides.json` and every arm below would boot onto a full
	# zone. Pinned OFF here for the same reason `combat_autostart` is — and arm 2b turns it
	# on deliberately, which is the only place in this file it may be on.
	DebugConfig.gambit_auto_deploy = false

	await super._ready()

	if lattice == null or director == null or assignment == null:
		print("[FAIL] GambitBattleTest: the host did not boot")
		get_tree().quit(1)
		return

	# Connected AFTER the host's own handler, so its non-commandable auto-pass has already
	# been queued by the time this runs and the two never race for the same turn.
	director.turn_opened.connect(_observe_turn)
	director.turn_committed.connect(_observe_commit)

	_arm_1_one_integer_boots_the_battle()
	_arm_2_deployment_is_a_stopped_clock()
	_arm_2b_auto_place_is_a_fill_and_not_a_start()
	_arm_3_the_cursor_edits_the_assignment()
	_arm_4_commit_is_the_one_write()
	await _arm_4a_the_turn_opens_with_a_beat()
	await _arm_4b_the_adjustment_turn_crosses_to_the_gpu()
	# 4e RUNS FIRST OF THE FOUR, out of its own numbering, and the position was MEASURED
	# rather than chosen. Gariland with the rollout AI on ends by annihilation in about ten
	# turns and every arm here wants some of them, so the order is a budget:
	#
	#   4e LAST      — 1 sample against a floor of 2; `victory_achieved` five frames in.
	#   4e BETWEEN   — the battle ended DURING 4e, and 4d then found no steerable turn at
	#     4c and 4d     all: "a turn opened on a unit the player may steer" red, ~400 s run.
	#   4e FIRST     — measured green, 3 samples, arms 4c/4d/5/6 all reached their subjects.
	#
	# The number is 4e's identity in the list above; this is the order.
	await _arm_4e_the_turn_opens_on_a_settled_taker()
	await _arm_4c_the_enemy_thinks()
	await _arm_4d_space_is_the_go_key()
	await _arm_5_and_6_turns_and_annihilation()

	print("\n=== GambitBattleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GambitBattleTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GambitBattleTest")
		get_tree().quit(1)
	else:
		print("[PASS] GambitBattleTest: scenario %d booted, %d deployed of %d, %d turns over %d freezes, battle ended by annihilation" % [
			SCENARIO, _commandable.size(), assignment.candidates().size(),
			_turns, _freezes.size()])
		get_tree().quit(0)


# === Arms =====================================================================

func _arm_1_one_integer_boots_the_battle() -> void:
	var scenario: Dictionary = ScenarioDatabase.get_scenario(SCENARIO)
	_eq(scenario_id, SCENARIO, "booted the scenario it was told to")
	_true(not _owned.is_empty(), "the owned side was composed")
	_true(not _enemies.is_empty(), "the enemy side was composed")
	# The ROM places everything except your squad, and it places it exactly.
	var authored := 0
	for unit in _guests + _enemies:
		if not unit.has_meta(ScenarioCast.ENTD_TILE_META):
			_true(false, "%s carries no authored ENTD tile" % unit.name)
			continue
		var want: Vector3i = unit.get_meta(ScenarioCast.ENTD_TILE_META)
		var got: Vector3i = unit.get_current_cell()
		_eq(Vector2i(got.x, got.y), Vector2i(want.x, want.y),
			"%s stands on its authored ENTD tile" % unit.name)
		authored += 1
	_true(authored > 0, "at least one unit was ROM-placed")
	# The zone is the player's alone: no ROM-placed unit is standing in it.
	for unit in _guests + _enemies:
		var cell: Vector3i = unit.get_current_cell()
		_true(not assignment.tiles.has(Vector2i(cell.x, cell.y)),
			"%s is not standing in the player's deployment zone" % unit.name)


func _arm_2_deployment_is_a_stopped_clock() -> void:
	_eq(director.state(), TurnDirector.State.DEPLOYMENT, "the director is in DEPLOYMENT")
	_eq(director.taker(), -1, "deployment has no taker")
	_true(not combat_active, "the world is frozen")
	# The load-bearing one: nothing is in the GPU buffer, so there is nothing to write to
	# and nothing to snapshot. This is what makes the assignment CPU-side by construction.
	_eq(combat_loop.gpu_simulator, null, "no GPU battle exists during deployment")
	_eq(assignment.tiles.size(), 8, "the real zone's tiles")
	_eq(assignment.cap, 5, "the real zone's squad cap")
	_eq(assignment.placed_count(), 0, "deployment opens with an empty field")


## The F3 auto-place toggle ([member DebugConfig.gambit_auto_deploy]): it FILLS the zone and
## starts nothing. Asserted here rather than left to a hand check because the failure mode of a
## debug convenience is silence — it stops filling, you re-place five units by hand, and nobody
## writes a bug for the tool they stopped noticing. Two claims: the fill reaches the cap with the
## deployment still open (a fill that also committed would be `--combat-autostart`, which this
## deliberately is not), and a second apply never overwrites placements that already exist.
##
## Leaves the assignment EMPTY again: the arms below are written against the opening state, and
## `clear()` is what "throw my placements away" means during deployment (there is no snapshot).
func _arm_2b_auto_place_is_a_fill_and_not_a_start() -> void:
	_eq(assignment.placed_count(), 0, "the deployment opens with nobody placed")
	_apply_auto_deploy(true)
	_eq(assignment.placed_count(), assignment.cap, "auto-place fills the zone to the cap")
	_eq(director.state(), TurnDirector.State.DEPLOYMENT, "and leaves the deployment OPEN")
	_eq(combat_loop.gpu_simulator, null, "it places; it does not start the battle")

	var kept = assignment.unit_at(assignment.tiles[0])
	_apply_auto_deploy(true)
	_eq(assignment.unit_at(assignment.tiles[0]), kept,
		"a second apply refuses an assignment somebody has already placed on")

	assignment.clear()
	_show_assignment()
	_eq(assignment.placed_count(), 0, "cleared back to the opening state for the arms below")


func _arm_3_the_cursor_edits_the_assignment() -> void:
	# Fill the zone WITHOUT the picker — this arm is about the latch, and the picker has its own
	# rig (`GambitDeploymentPickerTest`). `place` is what the picker's chosen row calls anyway.
	var order: Array = assignment.candidates()
	for i in range(assignment.cap):
		assignment.place(order[i], assignment.tiles[i])
	_show_assignment()
	_eq(assignment.placed_count(), assignment.cap, "the squad is at the cap")

	# THE LATCH (#941). The first press moves NOTHING: it lights the tile and frees the cursor.
	var moved = assignment.unit_at(assignment.tiles[0])
	_on_cursor_confirmed(assignment.tiles[0])
	_eq(_latched_tile, assignment.tiles[0], "confirm on an occupied tile latches that TILE")
	_eq(assignment.tile_of(moved), assignment.tiles[0], "and the unit has not moved")
	_eq(_marking_at(assignment.tiles[0]), CellMarking.Kind.SELECTED,
		"the latched tile wears SELECTED")

	# A misfire OUTSIDE the zone refuses and KEEPS the selection — that is the whole point of the
	# rule: a mis-aimed press must not cost the player the pick they just made.
	var outside := Vector2i(-99, -99)
	_on_cursor_confirmed(outside)
	_eq(_latched_tile, assignment.tiles[0], "a confirm outside the zone stays latched")
	_eq(assignment.tile_of(moved), assignment.tiles[0], "and moved nothing")

	# The second press on a FREE zone tile is the move.
	var free_tile: Vector2i = assignment.free_tiles()[0]
	_on_cursor_confirmed(free_tile)
	_eq(_latched_tile, DeploymentAssignment.NO_TILE, "confirm on a free tile resolves the latch")
	_eq(assignment.tile_of(moved), free_tile, "and the unit moved there")
	_eq(assignment.placed_count(), assignment.cap, "moving did not change the squad size")
	_eq(_marking_at(assignment.tiles[0]), CellMarking.Kind.PLACEMENT_PLAYER,
		"the vacated tile is back to plain zone green — SELECTED has its own slot")

	# The second press on an OCCUPIED tile is the swap, and it is not a bench-then-place: the
	# squad size is invariant across it and both units end on each other's tiles.
	var a_tile: Vector2i = assignment.tile_of(moved)
	var b_tile: Vector2i = assignment.tiles[1]
	var b = assignment.unit_at(b_tile)
	_true(b != null and b != moved, "there is a second unit to swap with")
	_on_cursor_confirmed(a_tile)
	_on_cursor_confirmed(b_tile)
	_eq(assignment.tile_of(moved), b_tile, "the latched unit took the other's tile")
	_eq(assignment.tile_of(b), a_tile, "and the other took its tile")
	_eq(assignment.placed_count(), assignment.cap, "a swap does not change the squad size")
	_eq(_latched_tile, DeploymentAssignment.NO_TILE, "and the latch is released")

	# Backspace WHILE LATCHED cancels the latch and benches nobody — the latch is the more recent
	# intent, so it is what ✕ answers.
	# On a NON-mandatory tile, deliberately. `a_tile` holds the unit that was NOT the latch above,
	# and after the swap `b_tile` holds the mandatory one — so a ✕ that fell through to the recall
	# path there would be REFUSED by the mandatory rule and look identical to a correct let-go.
	# Measured: seeded that way, the arm passed. Roster order again.
	var before: int = assignment.placed_count()
	var settled_here = assignment.unit_at(a_tile)
	_true(settled_here != null and not assignment.is_mandatory(settled_here),
		"the cancel arm is standing on a unit that COULD be benched")
	_on_cursor_confirmed(a_tile)
	_eq(_latched_tile, a_tile, "a fresh latch for the cancel arm")
	_on_cursor_cancelled(a_tile)
	_eq(_latched_tile, DeploymentAssignment.NO_TILE, "Backspace while latched lets go")
	_eq(assignment.placed_count(), before, "and benched nobody")
	_true(assignment.is_placed(settled_here), "the unit it was latched on is still on the field")

	# The mandatory rule, from the player's side of it — both halves.
	var mandatory = null
	for unit in assignment.candidates():
		if assignment.is_mandatory(unit):
			mandatory = unit
			break
	_true(mandatory != null, "scenario 9 names a mandatory unit")
	if mandatory == null:
		return
	_true(assignment.is_placed(mandatory), "the mandatory unit is on the field")
	_on_cursor_cancelled(assignment.tile_of(mandatory))
	_true(assignment.is_placed(mandatory), "Backspace refuses to bench the mandatory unit")

	# Backspace on a settled NON-mandatory unit RECALLS it.
	var recalled = null
	for row in assignment.squad():
		if not assignment.is_mandatory(row["unit"]):
			recalled = row["unit"]
			break
	_true(recalled != null, "there is a cadet on the field to recall")
	if recalled != null:
		_on_cursor_cancelled(assignment.tile_of(recalled))
		_true(not assignment.is_placed(recalled), "Backspace on a settled unit recalls it")
		_eq(assignment.placed_count(), assignment.cap - 1, "the squad is one smaller")

	# FACING (#941): every deployed unit looks at the nearest authored enemy, recomputed on every
	# edit. Asserted against the same nearest-ENTD-tile answer the host computes, from the OUTSIDE
	# — an arm that re-ran the host's own helper would assert nothing.
	for row in assignment.squad():
		var tile: Vector2i = row["tile"]
		_eq(row["unit"].facing_direction, _expected_facing(tile),
			"%s faces the nearest enemy from %s" % [row["unit"].name, str(tile)])

	# Put the recalled cadet back: the reserve arm below is about a FULL squad losing its mandatory
	# unit, and a squad already one short would leave a slot free for reasons that are not the
	# reserve's — which is exactly the confound the reserve exists to be distinguished from.
	if recalled != null:
		assignment.place(recalled, assignment.free_tiles()[0])
	_eq(assignment.placed_count(), assignment.cap, "the squad is full again before the reserve arm")

	# The RESERVE, on the REAL Gariland cast rather than on stand-ins. Take the mandatory unit off
	# (the host will not do it for you) and the tile he vacated stops accepting anybody else, with
	# the squad one under the cap.
	var his_tile: Vector2i = assignment.tile_of(mandatory)
	assignment.unplace(mandatory)
	_eq(assignment.reserved_slots(), 1, "benching him puts the slot back on hold")
	var cadet = null
	for unit in assignment.benched():
		if not assignment.is_mandatory(unit):
			cadet = unit
			break
	_true(cadet != null, "the real roster has a benched cadet to try it with")
	if cadet != null:
		_true(not assignment.place(cadet, his_tile),
			"a cadet cannot take the held slot even though the tile is empty")
		_eq(assignment.unit_at(his_tile), null, "and the tile is still empty")
	# Refill by hand — the picker is the player's door to this and it has its own rig.
	assignment.place(mandatory, his_tile)
	for unit in assignment.benched():
		if assignment.placed_count() >= assignment.cap:
			break
		var free := assignment.free_tiles()
		if free.is_empty():
			break
		assignment.place(unit, free[0])
	_show_assignment()
	_eq(assignment.placed_count(), assignment.cap, "back to a full squad")

	# The zone is PAINTED, and it is GREEN (#941): blue would mean "you may NOT place here".
	var green := 0
	for tile in assignment.tiles:
		if _marking_at(tile) == CellMarking.Kind.PLACEMENT_PLAYER:
			green += 1
	_true(green >= assignment.tiles.size() - 1,
		"every zone tile is painted PLACEMENT_PLAYER (%d of %d; the cursor owns at most one)"
			% [green, assignment.tiles.size()])

	# Leave a CANONICAL layout behind. Arms 5 and 6 play the battle this assignment produces, and
	# "does Gariland end by annihilation" is a question about a specific deployment — an arm that
	# inherited whatever tiles the edit arms above happened to leave would be measuring a different
	# battle every time one of them changed. `auto_fill` is the one layout the host can reproduce.
	assignment.auto_fill()
	_show_assignment()
	_eq(assignment.placed_count(), assignment.cap, "and the canonical layout is at the cap")


func _arm_4_commit_is_the_one_write() -> void:
	var squad_size: int = assignment.placed_count()
	var benched: Array = assignment.benched()
	_true(commit_deployment(), "the assignment committed")
	_true(combat_loop.gpu_simulator != null, "the GPU battle exists after commit")
	_eq(units.size(), squad_size + _guests.size() + _enemies.size(),
		"the battle holds squad + guests + enemies")
	# The bench is not in the battle. `queue_free` lands at the end of the frame, so this
	# asks the question that matters now: none of them is in the cast.
	for unit in benched:
		_true(not units.has(unit), "%s stayed on the bench" % unit.name)
	_true(units.size() <= combat_loop.units_per_battle,
		"the simulator was sized by the squad that took the field")
	_eq(director.state(), TurnDirector.State.RUNNING, "committing deployment starts the clock")
	_true(combat_active, "and the world is live")

	# Whose turns you may steer: exactly the units you deployed.
	_eq(_commandable.size(), squad_size, "one commandable unit per deployed unit")
	for i in _commandable.keys():
		_true(assignment.is_placed(units[i]), "commandable unit %s was deployed" % units[i].name)
	for guest in _guests:
		_true(not _commandable.has(units.find(guest)),
			"the guest %s fights beside you and is not yours to steer" % guest.name)
	for enemy in _enemies:
		_true(not _commandable.has(units.find(enemy)), "the enemy %s is not yours" % enemy.name)


## Arm 4a — THE TURN-OPEN BEAT (`docs/TURN-OPEN-BEAT-DESIGN.md`).
##
## State, never pixels: the design says so in as many words, and half this feature is a camera
## easing curve that no assertion should be pinned to. What is asserted is the four things the
## design's "Test" section names, and they are here rather than in their own scene because they
## need EXACTLY arm 4b's setup — scenario 9 booted, deployment committed, a commandable turn held
## open — and a second process costs 2.3 s on every run forever (TEST-CHARTER clause 13).
##
## The turn is CANCELLED mid-arm on purpose and it is not incidental: `TurnDirector.cancel`
## re-opens the same turn, which re-runs `_on_turn_opened`, which is the only way to observe a
## beat from a KNOWN starting cursor position. Without it the first beat of the battle is
## whatever arm 3 left the cursor on — possibly the taker's own tile, which is the degenerate
## no-travel case, and the arm would silently assert nothing about the travel at all.
##
## MEASURED, not asserted-and-hoped: every seam this arm names was deleted in turn and each
## deletion red exactly its own assertion — `cursor_rig.input_enabled = false` (2 reds),
## `cam.input_enabled = false` (yaw moved −45° → −135°), `_advance_turn_beat`'s `move_to`
## (cursor stuck at the away column), `_recenter_on_taker`'s `move_to`, and
## `hide_turn_marker()` in `_on_turn_committed` (marker still on unit 1).
##
## # seeded-break: delete the `cursor_rig.input_enabled = false` line in
## # `GambitBattle._open_turn_beat` — the "input is refused during the travel" assertion reds.
func _arm_4a_the_turn_opens_with_a_beat() -> void:
	_hold_turns = true
	var opened := await AwaitUntil.frames(self, _a_steerable_turn_is_open, 600)
	_true(opened, "a turn opened on a unit the player may steer")
	if not opened:
		_hold_turns = false
		return
	var taker: int = director.taker()
	var home: Vector3i = units[taker].get_current_cell()
	var home_column := Vector2i(home.x, home.y)

	# The marker went up at the FREEZE, so it is already on the taker before anything travelled.
	_eq(turn_marker_unit, taker, "the AT marker seam was shown on the taker when the turn opened")

	# The seam now carries the ROM's sprite. State, not pixels: that the node exists, that it is
	# a CHILD of the taker (so it dies with them — ADR-0063), and that its animation reads the
	# extraction rather than a literal. `phase_for_tick` is static and pure, so the period is
	# asserted without a rendered frame or a wall clock.
	_true(_turn_marker != null and is_instance_valid(_turn_marker),
		"the AT sprite mounted when the marker was shown")
	if _turn_marker != null and is_instance_valid(_turn_marker):
		_true(_turn_marker.get_parent() == units[taker],
			"the AT sprite is a child of the taker, not of the host")
		# The MOUNTED node reads the ROM's per-sprite-type height table (§5.2), not a
		# constant. Asserted against the taker's OWN sprite id, so this fails if the node
		# stops consulting the table — testing the pure lookup alone would only prove the
		# decision, not that the consumer makes it.
		# `is_equal_approx`, not `_eq`: `position.y` is a float32 and the expected value is
		# a float64 division, so they agree to 1.4285714 and differ in the eighth digit.
		var taker_sprite: int = units[taker].body_sprite_id
		var offsets := RangeTileAtlas.new()
		var want_y := RangeTileAtlas.overhead_raise_for_offset(
			offsets.overhead_offset_for_sprite(taker_sprite))
		_true(is_equal_approx(_turn_marker.position.y, want_y),
			"the AT sprite sits at its own sprite type's ROM height (got %f want %f)" % [
				_turn_marker.position.y, want_y])
		# …and it is the right SIZE. The quad is built at the SPRITE PIPELINE's scale
		# (`WORLD_PER_SPRITE_PX`, 8/256 — `UnitRig`'s 1x1 quad scaled 8 over a 256px sheet,
		# and `TileCursor`'s 0.75-for-24px), NOT off `camera.size`, which inflated it 1.68x
		# and by MORE as the player zoomed out. Measured on the mesh the node actually built,
		# so it fails if `_pixel_size` goes back to believing the camera.
		var quad: MeshInstance3D = null
		for child in _turn_marker.get_children():
			if child is MeshInstance3D:
				quad = child
		_true(quad != null, "the AT sprite built a quad")
		if quad != null and quad.mesh != null:
			var cell: Rect2 = RangeTileAtlas.new().active_turn_rect(0)
			var want_h: float = cell.size.y * TurnMarker3D.WORLD_PER_SPRITE_PX
			_true(is_equal_approx(quad.mesh.get_aabb().size.y, want_h),
				"the AT quad is %d native px at the sprite scale (got %f want %f)" % [
					int(cell.size.y), quad.mesh.get_aabb().size.y, want_h])
			# The ROM's own proportion: AT 12px / character 40px = 0.30. A camera-derived
			# size passes the height assertion at one zoom and breaks this at every other.
			_true(is_equal_approx(want_h / (40.0 * TurnMarker3D.WORLD_PER_SPRITE_PX), 0.3),
				"AT : character = 0.30, the ROM's proportion")
	# …and the table DISCRIMINATES. A Chocobo (0x86 CYOKO) and a generic human do not agree
	# in the ROM (-50 vs -40), so a lookup that had quietly collapsed to one constant —
	# which is exactly what shipped before — would pass every assertion above and fail here.
	var carousel := RangeTileAtlas.new()
	_true(carousel.overhead_offset_for_sprite(0x86) != carousel.overhead_offset_for_sprite(0x00),
		"a monster and a human get different marker heights")
	_eq(carousel.overhead_offset_for_sprite(0x49), Vector2i(0, -120),
		"sprite 0x49 is the KANZEN row (-120), the table's extreme")
	# The heights belong to the 22-slot CAROUSEL, not to slot 21 — `unit_sprite_poly_builder`
	# reads `unit[+0x2DF]` at `0x8007F0C4`, after every cell-selection branch has converged on
	# `LAB_8007F088`, with no slot test in between. So the status bubble reads the same rows,
	# and a bubble still pinned to one constant fails here.
	_true(is_equal_approx(_bubble_raise_for_sprite(0x49),
			RangeTileAtlas.overhead_raise_for_offset(Vector2i(0, -120))),
		"a status bubble hangs at its own sprite type's ROM carousel height, not a constant")
	_true(_bubble_raise_for_sprite(0x86) != _bubble_raise_for_sprite(0x00),
		"and that height DISCRIMINATES a monster from a human, as the marker's does")
	_eq(TurnMarker3D.phase_for_tick(0), TurnMarker3D.phase_for_tick(15),
		"the marker holds one phase for 16 frames")
	_true(TurnMarker3D.phase_for_tick(0) != TurnMarker3D.phase_for_tick(16),
		"and flips on the 16th — bit 4 of the ROM's free-running 60Hz counter")
	_eq(TurnMarker3D.phase_for_tick(0), TurnMarker3D.phase_for_tick(32),
		"period 32 frames, so the two frames alternate rather than advancing")

	# Let whatever beat the open armed run itself out, then take the cursor somewhere it is NOT.
	_true(await AwaitUntil.frames(self, _beat_is_over, 240),
		"the opening beat landed within 240 frames")
	var away := _a_column_other_than(home_column)
	_true(away != home_column, "the map has a second column to stand the cursor on")
	cursor_rig.move_to(away)
	_eq(cursor_rig.grid_pos, away, "the cursor parked away from the taker")

	# Re-open the same turn with the cursor off the taker: now there is a travel to watch.
	_true(director.cancel(), "cancel re-opened the same turn")
	_eq(director.taker(), taker, "on the same taker")

	# --- during the travel ----------------------------------------------------------------
	_true(_turn_beat_running(), "the re-opened turn armed a beat, because the cursor was away")
	_eq(cursor_rig.grid_pos, away,
		"the cursor has NOT jumped — it lands at the end of the travel, not at the start")
	_true(not cursor_rig.input_enabled, "the cursor is deaf for the length of the travel")
	_press(&"camera_right")
	_eq(tile_cursor.held_action(), &"",
		"input is refused during the travel — the step was not accepted")
	_release(&"camera_right")
	# The camera's half of the swallow, and it is not redundant with the cursor's: Q/E never
	# reach the cursor at all, and `PlayerCamera._rotate_yaw` calls `follow_cursor` on the
	# cursor's PRE-BEAT tile — so a beat that gated only the cursor could be aimed somewhere
	# else by the one key it forgot. Asserted refused-only, with no accept-after twin: a real
	# yaw would re-key `TileCursor._QUADRANT_DELTAS` and change what `camera_right` MEANS for
	# every assertion below it.
	var cam := get_node_or_null("PlayerCamera")
	_true(cam != null, "the scene has a PlayerCamera")
	var yaw_before: float = cam.y_target_rot
	_press(&"rotate_camera_cw")
	_eq(cam.y_target_rot, yaw_before, "Q/E is refused during the travel too")
	_release(&"rotate_camera_cw")

	# --- after it -------------------------------------------------------------------------
	_true(await AwaitUntil.frames(self, _beat_is_over, 240),
		"the beat landed within 240 frames")
	_eq(cursor_rig.grid_pos, home_column, "the cursor landed on the taker's cell")
	_true(cursor_rig.input_enabled, "and the cursor has its ears back")
	_press(&"camera_right")
	_eq(tile_cursor.held_action(), &"camera_right", "input is accepted again after the travel")
	_release(&"camera_right")

	# --- Home recentres -------------------------------------------------------------------
	cursor_rig.move_to(away)
	_eq(cursor_rig.grid_pos, away, "the player walked the cursor away — it is free, not locked")
	_press_key(KEY_HOME)
	_eq(cursor_rig.grid_pos, home_column, "Home snapped the cursor back to the turn taker")

	# --- the marker comes down with the turn ----------------------------------------------
	var commits := _marker_at_commit.size()
	_true(director.commit(), "the turn committed (committing unchanged IS wait)")
	_true(_marker_at_commit.size() > commits, "turn_committed fired for it")
	if _marker_at_commit.size() > commits:
		_eq(_marker_at_commit[-1], -1,
			"the AT marker seam was hidden on turn_committed, seen from inside the signal")
		_true(not _marker_node_at_commit[-1],
			"and its sprite was released with it — also from inside the signal, because the "
			+ "drain can raise the marker on the next ready unit before `commit` returns")


## The predicate arm 4a waits on. A method and not an inline lambda: a multi-line lambda body
## inside a call argument does not parse here, and a `\`-continued one-liner is worse to read
## than the name.
func _a_steerable_turn_is_open() -> bool:
	return director.state() == TurnDirector.State.TURN_OPEN and _commandable.has(director.taker())


## True while the host's turn-open beat is travelling. Named so the two `AwaitUntil` calls read
## as the state they wait for.
func _beat_is_over() -> bool:
	return not _turn_beat_running()


## Any column that is not `avoid` and that the cursor can actually seat on. Asked of the
## LATTICE and not invented, because `move_to` on a column with no ground hides the dagger and
## the arm would then be asserting about a cursor that is nowhere.
## ⚠️ `Lattice` is NOT aliased in this file and must not be — it is `GambitBattle`'s alias, and
## a subclass re-declaring a parent's `const` is `Parse Error: The member "Lattice" already
## exists in parent class`, which loads the scene with the BASE host and hangs the run for the
## full `timeout(1)`. The annotation below still satisfies `check_lattice_ports` arm 2: that
## register scans the spelling, and the spelling resolves through inheritance.
func _a_column_other_than(avoid: Vector2i) -> Vector2i:
	var lat: Lattice = lattice
	for cell in lat.all_cells():
		var column := Vector2i(cell.grid.x, cell.grid.y)
		if column != avoid and lat.ground_at(column.x, column.y) != null:
			return column
	return avoid


## Push a real action press through the viewport — NOT `Input.parse_input_event`, which writes
## the Input singleton so a POLL would pass while `_unhandled_input` never ran. The subject here
## is an event handler, so the event has to be delivered as one.
func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)


func _release(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	get_viewport().push_input(event)


## `turn_recenter` has no other binding, so this arm presses the KEY. `GambitBattle`'s
## `_unhandled_input` opens with `event is InputEventKey`, which an `InputEventAction` is not —
## an action-shaped press would be dropped on the first line and the arm would pass by
## asserting the cursor never moved from where it already was.
func _press_key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event)


## Arm 4b — the ADJUSTMENT TURN, end to end on a real battle (#894, ADR-0249).
##
## [AdjustmentTurnTest] proves the class in isolation, against a stub simulator. What it
## structurally cannot see is whether this HOST wires it to anything: a `commit` that is never
## called and a `commit` that is called on an untouched turn look identical from inside the class,
## and both would leave a player's edits stranded on the CPU forever. So this arm edits a real
## [Character] mid-battle and reads the answer back out of the GPU buffer.
##
## `brave` is the probe because it extracts straight from the progression
## (`UNIT_CONFIG_SCHEMA`, BEHAVE_RECOMPUTE) — no derived `unit_stats` in the way — so a changed
## value in the unit block can only have come through `reconfigure_unit_from`.
##
## Both directions, because they fail differently: a commit that never crosses leaves the GPU
## stale, and a cancel that restores only the GPU half leaves the CPU Character carrying an edit
## the player took back — the divergence this whole ticket exists to close, and the one no
## GPU-only snapshot can see.
func _arm_4b_the_adjustment_turn_crosses_to_the_gpu() -> void:
	_hold_turns = true
	var frames := 0
	while frames < 600 and not (director.state() == TurnDirector.State.TURN_OPEN
			and _commandable.has(director.taker())):
		await get_tree().process_frame
		frames += 1
	_true(director.state() == TurnDirector.State.TURN_OPEN and _commandable.has(director.taker()),
		"a turn opened on a unit the player may steer, within %d frames" % frames)
	if not (director.state() == TurnDirector.State.TURN_OPEN and _commandable.has(director.taker())):
		_hold_turns = false
		return

	var taker: int = director.taker()
	var unit = units[taker]
	var character = FormationMapHost.character_for_unit(unit)
	_true(character != null, "the taker resolves to a catalogue Character")
	if character == null:
		_hold_turns = false
		return

	# The scope rule, on the host's own predicate — the one the map-hosted Formation screen
	# consults. Only the taker; another unit you deployed is NOT editable on somebody else's turn.
	_true(_unit_is_steerable(unit), "the taker is steerable on its own turn")
	for i in _commandable.keys():
		if int(i) != taker:
			_true(not _unit_is_steerable(units[i]),
				"another deployed unit is not steerable on someone else's turn")
			break
	_true(adjustment.is_open() and adjustment.taker() == taker,
		"the adjustment window opened on the taker")

	var brave_before: int = character.progression.brave
	var gpu_before: int = int(_gpu_brave(taker))
	_eq(gpu_before, brave_before, "the GPU and the Character agree before any edit")

	# --- cancel: the edit is taken back on BOTH sides -------------------------------------
	adjustment.touch()
	character.progression.brave = 13
	_true(director.cancel(), "the turn cancelled")
	_eq(character.progression.brave, brave_before,
		"cancel restored the CPU half — the Character forgot the edit")
	_eq(int(_gpu_brave(taker)), gpu_before, "and the GPU half never saw it")
	_eq(director.taker(), taker, "cancel re-opened the SAME turn rather than eating it")

	# --- commit: the edit crosses ---------------------------------------------------------
	var edited: int = 77 if brave_before != 77 else 41
	adjustment.touch()
	character.progression.brave = edited
	_true(director.commit(), "the turn committed")
	_eq(int(_gpu_brave(taker)), edited,
		"the edit crossed to the GPU — reconfigure_unit_from ran on commit")
	_eq(character.progression.brave, edited, "and the Character kept it")
	# The window closes with THE TAKER'S turn, not "no window is open" — `commit` DRAINS, so a
	# second unit ready on the same tick re-opens the window on ITSELF inside the same call
	# (TurnDirector.commit). Asserting a bare `not is_open()` tests a property of the battle seed.
	# See GambitSurfaceTest arm 5, where the same assertion was measured failing that way.
	_true(not adjustment.is_open() or adjustment.taker() != taker,
		"the window closed with the taker's turn")

	# Put it back, so arms 5/6 play the battle the seed describes rather than one this arm bent.
	adjustment.open(taker, character)
	adjustment.touch()
	character.progression.brave = brave_before
	adjustment.commit(combat_loop.gpu_simulator, director.battle_id, unit)
	_eq(int(_gpu_brave(taker)), brave_before, "the probe was undone before the battle plays on")

	# Hand the battle back to the drive loop. The turn that is open RIGHT NOW opened while the
	# hold was on, so nothing queued a pass for it — spend it here or arms 5/6 wait on a world
	# that will never move again.
	_hold_turns = false
	if director.state() == TurnDirector.State.TURN_OPEN:
		call_deferred("_pass_turn")


## One unit's `brave` as the GPU holds it. The COLD reader, never the hot union — `brave` is not in
## the per-frame snapshot, and the hot path would hand back `.get()`'s default silently.
func _gpu_brave(unit_index: int) -> int:
	var states: Array = combat_loop.gpu_simulator.get_battle_unit_states(director.battle_id)
	if unit_index < 0 or unit_index >= states.size():
		return -1
	return int(states[unit_index].get("brave", -1))


## The enemy's turn is THOUGHT ABOUT (#897, design §7, ADR-0256).
##
## The arm exists because `RolloutDriverTest` and `GPURolloutDriverTest` are both
## STRUCTURALLY unable to see whether this host wires the driver to anything — a `decide`
## never called and a `decide` that held look identical from outside, since both leave the
## gambit buffer exactly as they found it. That is #894's own lesson (its arm 4b), and it is
## why `beats_taken` exists to be read here.
##
## 🔴 AND THE AI STAYS ON FOR ARMS 5 AND 6, WHICH IS THE POINT. Wiring it turned Gariland
## into a battle that never ended — 1,734 turns to the 12,000-frame bound with `alive = [2, 0]`
## and `team1_hp = 0`, the fight long since won and the result still ONGOING. That was NOT an
## AI defect: `stage_compute.glsl` only noticed a won battle from the IDLE state, and a unit
## with a live "attack the nearest enemy" gambit and no living enemy never reaches idle — it
## re-enters WALKING toward a target that no longer resolves, `timer` restarting every tick
## (MEASURED: `state=WALKING target=<itself> timer=48 -> 47` across 800 frames). The AI is
## only what EXPOSED it, by giving units gambits at all: a scenario-booted cast has empty
## gambit lists (ADR-0242), so before this its survivors sat in IDLE and fell through.
## ADR-0256 dec. 13 hoists that check out of the IDLE path, and arm 6 below is its end-to-end
## guard — a full Gariland fight played by the rollout AI, ending by annihilation.
func _arm_4c_the_enemy_thinks() -> void:
	_true(rollout != null, "the rollout driver was mounted on the live simulator")
	if rollout == null:
		return
	_eq(combat_loop.gpu_simulator.get_num_battles(), RolloutDriver.fleet_size_now(),
		"the simulator was sized to the rollout fleet")

	# Wait for a turn nobody may steer. Bounded, because a host that never wired the driver
	# would otherwise wait here forever and be reported as a hang rather than as the defect.
	var frames := 0
	while beats_taken == 0 and frames < 3000:
		await get_tree().process_frame
		frames += 1
	_true(beats_taken > 0, "no thinking beat ran in %d frames — the host is not calling the driver" % frames)
	if beats_taken == 0:
		return

	var plan: Dictionary = last_decision.get("plan", {})
	_true(bool(last_decision.get("ok", false)),
		"the last beat produced no decision: %s" % last_decision.get("reason", ""))
	_true(plan.get("degraded", ["unset"]).is_empty(),
		"the beat degraded at Gariland's shape, which ADR-0237 dec. 4 says the cap exists to prevent: %s"
			% [plan.get("degraded", [])])
	_eq(int(plan.get("horizon", -1)), RolloutDriver.horizon,
		"the beat ran at the published horizon")
	_true(float(last_decision.get("beat_ms", -1.0)) <= float(plan.get("cap_ms", 0.0)),
		"the beat took %.1f ms against a %.1f ms cap" % [
			last_decision.get("beat_ms", -1.0), plan.get("cap_ms", 0.0)])
	_true(float(last_decision.get("value", -1.0)) >= 0.0
			and float(last_decision.get("value", -1.0)) <= 1.0,
		"the beat's winning score %.4f is outside [0, 1] — every objective bounds its value there" % last_decision.get("value", -1.0))
	print("[GambitBattleTest] %d thinking beats ran; the last took %.0f ms of a %.0f ms cap. The AI stays ON for arms 5/6 — see this arm's note."
		% [beats_taken, last_decision.get("beat_ms", 0.0), plan.get("cap_ms", 0.0)])


## How many turns arm 4e TRIES to sample. Small, and the smallness is a BUDGET and not just
## taste: Gariland with the rollout AI on ends by annihilation after single-digit turns, every
## turn this arm samples is a turn arms 4c/4d/5 do not get, and at 5 the battle was MEASURED
## ending inside arm 4d (which then reds on a world that has no turns left to open). The
## property is not statistical either — one mid-step taker is the bug, and one settled taker is
## already a sample the pre-brake code could not have produced.
const SETTLED_SAMPLES := 3
## The FLOOR the arm actually asserts, and the reason it is a floor and not `SETTLED_SAMPLES`:
## the arm races a battle whose LENGTH is not deterministic. The rollout AI's beat is bounded
## by wall clock (`_arm_4c`'s `cap_ms`), so how much of Gariland has been played by any given
## frame varies run to run, and `victory_achieved` can end the loop with 2 samples on one run
## and 5 on the next. An exact count would make the arm a wall-clock flake for a reason that
## has nothing to do with alignment. What carries the arm is the two positive controls below
## plus the per-sample properties, and the seeded break (`stage_compute.glsl`'s brake block
## deleted) was caught with 3.
const SETTLED_SAMPLES_FLOOR := 2
## Tolerance on "the sprite is on its tile", in world units. The settled path assigns
## `unit.global_position = lattice.world_position_at(cell) + distort_offset` EXACTLY, so
## this is float slack and not a budget: a single mid-step sample is a whole tile out.
const ALIGN_EPS := 0.05
## Frames arm 4e may spend collecting its samples. A CEILING and not a target: it exists so the
## arm cannot quietly play the whole Gariland fight and leave arms 4c/4d/5/6 asserting over a
## battle that was already decided.
const SETTLED_FRAME_BUDGET := 600


## A TURN OPENS ON A UNIT THAT IS STANDING ON ITS OWN TILE.
##
## The bug this arm exists for: a unit's turn came up and the camera travelled to a tile that
## looked empty, because the sprite was still short of it. Logical position is the DESTINATION
## for the whole duration of a movement step (`stage_resolve.glsl`: "CPU updates position at
## START of movement, not END"), the sprite interpolates toward it, and
## `GPUVisualBridge` publishes that destination into `movement_component.current_cell` — so the
## camera, `get_current_cell()` and `_unit_at_grid` all placed the taker a tile ahead of itself.
## Freezing then stopped the ticks that would have carried the sprite in, and it sat there for
## the whole turn.
##
## Two halves fix it and both are asserted here: the KERNEL brakes (a ready unit finishes the
## step it is on and starts no other) and the GATE waits (it refuses to freeze while any ready
## unit is mid-step). Either alone is useless — the gate without the brake never trips, because
## a continuously walking unit is never settled.
##
## 🔴 IT CARRIES ITS OWN POSITIVE CONTROL, and the control is the whole reason to trust it. "No
## sampled taker was mid-step" is exactly what a battle in which nobody walks reports, and a
## deployment-only cast with empty gambit lists is a real state of this host (ADR-0242). So the
## arm records every unit it sees mid-step during the between-turn stretches and requires that
## at least one SAMPLED TAKER is among them — the takers walk, and the arm watched them stop.
##
## `_hold_turns` is on for the arm's duration: the taker has to still be the taker when the
## frame it froze on has FINISHED, because `update_visual_positions` runs after the tick loop
## the gate breaks out of. Reading the sprite from inside `turn_opened` would read the previous
## frame's position and red on a correct fix.
##
## # seeded-break: delete the `config.turn_brake_battle == battle_id` block in
## # `stage_compute.glsl` — the brake stops firing, takers freeze mid-stretch and the drift
## # assertion reds while the control keeps passing.
func _arm_4e_the_turn_opens_on_a_settled_taker() -> void:
	_eq(combat_loop.gpu_simulator.turn_brake_battle, director.battle_id,
		"the kernel's turn brake is armed on the battle the director stops for")

	var walked: Dictionary = {}      # unit index -> seen mid-step between turns (the control)
	var samples: Array = []
	var frames := 0
	_hold_every_turn = true
	_hold_turns = true
	while samples.size() < SETTLED_SAMPLES and frames < SETTLED_FRAME_BUDGET and not victory_achieved:
		await get_tree().process_frame
		frames += 1
		if director.state() != TurnDirector.State.TURN_OPEN:
			# Between turns: the world is live and this is where walking is visible.
			for i in range(units.size()):
				if TurnDirector._is_movement_state(_gpu_state_of(i)):
					walked[i] = true
			continue
		var taker: int = director.taker()
		if taker < 0:
			continue
		samples.append(_sample_taker(taker))
		director.commit()
	_hold_turns = false
	_hold_every_turn = false
	# 🔴 SPENT HERE AND NOW, NOT `call_deferred`. The turn that is open right now opened under
	# the hold, so nothing queued a pass for it — and a DEFERRED pass is still in flight when
	# the next arm starts. Arm 4d waits for a steerable turn, finds THIS one, and the deferred
	# pass then spends it out from under it: measured as four 4d reds whose common shape was a
	# turn that was open one line earlier and gone by the next. Nothing is emitting here (this
	# is arm code, not a `turn_opened` handler), which is the only reason the deferral existed.
	if director.state() == TurnDirector.State.TURN_OPEN:
		_pass_turn()
	# One frame for the resume to land, so the next arm starts on a world that is running.
	await get_tree().process_frame

	_true(samples.size() >= SETTLED_SAMPLES_FLOOR,
		"sampled only %d held turns (floor %d, target %d) in %d frames (victory=%s) — a battle that ends first leaves the property untested"
			% [samples.size(), SETTLED_SAMPLES_FLOOR, SETTLED_SAMPLES, frames, victory_achieved])

	# --- the control, FIRST: this arm was able to see the bug ---------------------------
	var sampled_walkers: Array = []
	for s in samples:
		if walked.has(int(s["taker"])) and not sampled_walkers.has(int(s["taker"])):
			sampled_walkers.append(int(s["taker"]))
	_true(not walked.is_empty(),
		"no unit was ever seen mid-step between turns — the arm cannot see the defect it names")
	_true(not sampled_walkers.is_empty(),
		"no SAMPLED taker was ever seen mid-step (walkers seen: %s, takers sampled: %s) — the arm would pass on a cast that never moves"
			% [walked.keys(), samples.map(func(s): return s["taker"])])

	# --- the property ------------------------------------------------------------------
	var worst := 0.0
	var worst_taker := -1
	var mid_step: Array = []
	for s in samples:
		if float(s["drift"]) > worst:
			worst = float(s["drift"])
			worst_taker = int(s["taker"])
		if TurnDirector._is_movement_state(int(s["state"])):
			mid_step.append(int(s["taker"]))
	_true(mid_step.is_empty(),
		"units %s held a turn while still mid-step — the kernel did not brake" % [mid_step])
	_true(worst <= ALIGN_EPS,
		"the taker's sprite was %.3f world units off its own tile (worst: unit %d) — the turn opened on a cell the unit had not reached"
			% [worst, worst_taker])
	print("[GambitBattleTest] arm 4e: %d turns sampled, worst sprite/tile drift %.4f; %d units seen walking between turns, %d of them sampled."
		% [samples.size(), worst, walked.size(), sampled_walkers.size()])


## The taker as the PLAYER meets it: where the sprite is, against the cell every reader
## places the unit on. `get_current_cell()` is the facade the camera travel and
## `_unit_at_grid` both go through, so this is that question and not a re-derivation of it.
## `distort_offset` is subtracted because the bridge ADDS it — it is the hit/knockback
## wobble, not a position.
func _sample_taker(taker: int) -> Dictionary:
	var unit = units[taker]
	var cell: Vector3i = unit.get_current_cell()
	var here: Vector3 = unit.global_position - unit.distort_offset
	var drift: float = INF
	# `var lat: Lattice = lattice` for the reason spelled out over `_a_column_other_than`:
	# the alias is `GambitBattle`'s and a subclass may not re-declare it, but an annotated
	# local resolves through inheritance and is what `check_lattice_ports` arm 2 reads.
	var lat: Lattice = lattice
	if lat != null and lat.terrain_at(cell) != null:
		drift = here.distance_to(lat.world_position_at(cell))
	return {"taker": taker, "drift": drift, "state": _gpu_state_of(taker), "cell": cell}


## One unit's logical activity, off the per-frame snapshot the loop already built (the hot
## union is version-cached, so this is a read and not a device round trip).
func _gpu_state_of(unit_index: int) -> int:
	var states: Array = gpu_state_reader.get_all_unit_states_hot()
	if unit_index < 0 or unit_index >= states.size():
		return -1
	return int(states[unit_index].get("state", -1))
## Arm 4d — SPACE IS THE GO KEY, and ○ no longer spends a turn.
##
## Three of this host's four states show a motionless battlefield, and each used to be left by a
## different key: Space (deployment), Esc (pause), ○ (an open turn) — with Space and Esc both
## structurally dead during a turn. Space now ends both stops the player is expected to end, and ○
## is a cursor verb again.
##
## The load-bearing assertion is the ○ one, and it is a REGRESSION arm. `cursor_confirmed` has two
## listeners — this host and [FormationMapHost] — and the screen evaluates `can_open` when the
## signal reaches IT, not when it was emitted. While this host's handler still committed, that
## commit flipped `state()` to RUNNING mid-emission and the screen read the flipped value: ONE ○
## over an occupied tile both spent the turn and opened the screen on somebody else, which re-froze
## the world through `_set_screen_pause`. Measured before the fix; asserted absent here.
##
## An ARM and not a process (charter clause 13): it needs a booted host holding a steerable turn
## open on a live battle, which is arm 4a/4b's setup exactly.
func _arm_4d_space_is_the_go_key() -> void:
	_hold_turns = true
	var opened := await AwaitUntil.frames(self, _a_steerable_turn_is_open, 3000)
	_true(opened, "arm 4d: a turn opened on a unit the player may steer")
	if not opened:
		_hold_turns = false
		return
	_true(await AwaitUntil.frames(self, _beat_is_over, 300), "arm 4d: the opening beat landed")
	var taker: int = director.taker()

	# --- the badge names the stop -----------------------------------------------------------
	# Chrome, and it is asserted for the same reason the bindings are: a key that is correct and
	# invisible is still unusable, and the three stops are pixel-identical without this line.
	_true(stop_badge_text().begins_with("YOUR TURN:"),
		"arm 4d: the badge names an open turn — got %s" % stop_badge_text())
	_true("Space to commit" in stop_badge_text(),
		"arm 4d: and it advertises the key that actually ends it")
	# The LABEL and not only the string. `stop_badge_text()` is pure and a pure predicate can be
	# right while nothing draws it — the badge exists because the three stops are indistinguishable
	# on screen, so "a Label is up carrying this text" is the claim, not "a function returns it".
	_true(_pause_badge != null and _pause_badge.visible,
		"arm 4d: the badge is actually on screen during an open turn")
	if _pause_badge != null:
		_eq(_pause_badge.text, stop_badge_text(), "arm 4d: and it carries what the predicate says")

	# --- Esc pauses OVER the turn, and it is modal --------------------------------------------
	# The classic pause is available in every state, frozen ones included. What it must never do
	# is spend or resume what it paused over: it saves the clock, and closing puts that back.
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_true(pause_screen_open(), "arm 4d: Esc opened the pause screen over an open turn")
	_eq(director.state(), TurnDirector.State.TURN_OPEN, "arm 4d: which did not resume the turn")
	_eq(director.taker(), taker, "arm 4d: and did not spend it either")
	_eq(stop_badge_text(), "",
		"arm 4d: the badge stands down under the pause screen, which says PAUSED itself")
	# MODAL, and this is the assertion that says so. Space is the one key that could do real
	# damage through a pause — it commits — and it reaches neither the cursor nor the camera, so
	# `input_enabled` cannot be what stops it.
	var committed_under_pause := _marker_at_commit.size()
	_press_key(KEY_SPACE)
	await get_tree().process_frame
	_eq(_marker_at_commit.size(), committed_under_pause,
		"arm 4d: Space is swallowed by the pause screen — it did NOT commit the turn")
	_true(pause_screen_open(), "arm 4d: and the pause screen is still up")
	_true(not cursor_rig.input_enabled, "arm 4d: the cursor is deaf under the pause screen")
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_true(not pause_screen_open(), "arm 4d: Esc closed it again")
	_eq(director.taker(), taker, "arm 4d: the same turn is still open underneath")
	_true(cursor_rig.input_enabled, "arm 4d: and the cursor has its ears back")

	# --- ○ over an OCCUPIED tile does not spend the turn (the regression) --------------------
	var taker_cell: Vector3i = units[taker].get_current_cell()
	var elsewhere := _an_occupied_column_other_than(Vector2i(taker_cell.x, taker_cell.y))
	_true(elsewhere != Vector2i(-1, -1), "arm 4d: somebody else is standing on the field")
	if elsewhere != Vector2i(-1, -1):
		cursor_rig.move_to(elsewhere)
		await get_tree().process_frame
		_press_key(KEY_ENTER)
		await get_tree().process_frame
		await get_tree().process_frame
		_eq(director.state(), TurnDirector.State.TURN_OPEN,
			"arm 4d: ○ over another unit did NOT commit the turn")
		_eq(director.taker(), taker, "arm 4d: the same taker still holds it")
		# The screen it DID open is the intended half — ○ is the screen's door now, like △.
		# Unwound here rather than left standing: the Space press below has to reach this host's
		# `_unhandled_input`, and a screen on the focus stack is above it.
		_formation_map_screen.unwind_all()
		_true(await AwaitUntil.frames(self,
			func() -> bool: return not _formation_map_screen.claims_held(), 300),
			"arm 4d: the screen let go of the camera claim")

	# --- Space commits ------------------------------------------------------------------------
	cursor_rig.move_to(Vector2i(taker_cell.x, taker_cell.y))
	await get_tree().process_frame
	var committed_before := _marker_at_commit.size()
	_press_key(KEY_SPACE)
	await get_tree().process_frame
	_true(_marker_at_commit.size() > committed_before, "arm 4d: Space committed the open turn")
	# NOT `state() == RUNNING`: `commit` DRAINS, so a second unit ready on the same tick re-opens a
	# turn inside the same call and the state is TURN_OPEN again on a DIFFERENT taker. Asserting
	# RUNNING here would be an assertion about the battle seed (see arm 4b's note).
	_true(director.taker() != taker, "arm 4d: and the turn it committed was the one that was open")

	# --- Space STOPS the between-turn stretch, and Esc's stop is a different one --------------
	# The pair the whole binding rests on. Space stops the clock and nothing else — the cursor
	# still walks — and Esc takes the screen. Two stops that looked identical are the defect;
	# two that are visibly different are two features. Both halves of the toggle are pressed
	# below, because a stop nobody proved they could undo is a lock-out with better manners.
	# 🔴 THE HOLD COMES OFF BEFORE THE WAIT, AND THE WAIT IS ASSERTED. This half is about the
	# BETWEEN-TURN stretch, so it needs one to exist — and it cannot while `_hold_turns` is on:
	# the commit above DRAINS into the next turn, and a commandable next taker is held by this
	# test's own auto-pass suppressor, so `RUNNING` never arrives and the eleven assertions
	# below went silently unrun. Which taker is next is a property of the battle, so that was
	# luck, not design: it held until arm 4e started sampling turns ahead of this one and the
	# assertion count dropped 179 -> 174 with nothing red. Charter clause 10 — the wait must be
	# able to FAIL, not just to stop asserting.
	_hold_turns = false
	# ...and the turn that is ALREADY open has to be spent by hand. `_observe_turn` queues the
	# auto-pass from inside `turn_opened`, and the turn standing here opened during the commit
	# above, while the hold was still on — so dropping the flag alone changes nothing about it
	# and the wait below times out on a turn nobody will ever spend. Measured exactly that way.
	if director.state() == TurnDirector.State.TURN_OPEN:
		_pass_turn()
	var reached_a_stretch := await AwaitUntil.frames(self,
		func() -> bool: return director.state() == TurnDirector.State.RUNNING, 900)
	_true(reached_a_stretch,
		"arm 4d: the battle reached a between-turn stretch — the toggle half below is ABOUT that stretch, so it is not run at all without one")
	if reached_a_stretch:
		_press_key(KEY_SPACE)
		await get_tree().process_frame
		_true(not combat_active, "arm 4d: Space stopped the between-turn stretch")
		_true(not pause_screen_open(), "arm 4d: and it did NOT raise the pause screen")
		_true(cursor_rig.input_enabled,
			"arm 4d: Space's stop leaves the cursor live — that is what makes it the inspect stop")
		_true(stop_badge_text().begins_with("STOPPED"),
			"arm 4d: the badge names it — got %s" % stop_badge_text())

		# Esc over a stopped clock, and back. The restore is the assertion: resuming from a pause
		# taken while the clock was stopped must leave it stopped, not start the battle. One
		# shared save slot between this and the Formation screen is what would break it, which
		# is why it has its own (`_combat_active_before_pause`).
		_press_key(KEY_ESCAPE)
		await get_tree().process_frame
		_true(pause_screen_open(), "arm 4d: Esc paused over the stopped clock")
		_press_key(KEY_ESCAPE)
		await get_tree().process_frame
		_true(not pause_screen_open(), "arm 4d: and Esc closed it")
		_true(not combat_active, "arm 4d: still stopped after the pause — the world did NOT restart")
		_true(stop_badge_text().begins_with("STOPPED"), "arm 4d: the badge says so too")

		# Space again starts it. It is a TOGGLE, and the second press is the half that says so.
		_press_key(KEY_SPACE)
		await get_tree().process_frame
		_true(combat_active, "arm 4d: Space started the clock again — it is a toggle")
		await get_tree().process_frame
		_eq(stop_badge_text(), "", "arm 4d: and a running world shows no badge")
		_true(_pause_badge == null or not _pause_badge.visible,
			"arm 4d: the Label came down with it")

	print("[GambitBattleTest] arm 4d: Esc paused modally over a turn, \u25cb opened a screen without spending it, Space committed it, then stopped and restarted the clock.")

	_hold_turns = false
	if director.state() == TurnDirector.State.TURN_OPEN:
		call_deferred("_pass_turn")


## Any column with a standing unit on it that is not `avoid`, or `(-1, -1)` if the field has only
## one occupant left. Asked of the host's own `_unit_at_grid`, which is the same answer the
## Formation screen reads — a column this says is occupied is a column ○ can open a screen on.
func _an_occupied_column_other_than(avoid: Vector2i) -> Vector2i:
	for unit in _all_standing_units():
		var cell: Vector3i = unit.get_current_cell()
		var column := Vector2i(cell.x, cell.y)
		if column != avoid and _unit_at_grid(column) != null:
			return column
	return Vector2i(-1, -1)


## Arms 5 and 6 share one drive loop: every turn is committed unchanged (which IS "wait"),
## and the battle is played until the engine declares annihilation.
func _arm_5_and_6_turns_and_annihilation() -> void:
	var frames := 0
	while not victory_achieved and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	_true(_turns > 0, "turns opened")
	_true(not _freezes.is_empty(), "at least one freeze was observed")
	var frozen_every_time := true
	for freeze in _freezes:
		if freeze["combat_active"]:
			frozen_every_time = false
	_true(frozen_every_time, "the world was frozen at every turn_opened, seen from inside the signal")

	_true(victory_achieved, "the battle ended (annihilation) within %d frames — reached tick %d after %d turns"
		% [MAX_FRAMES, current_tick, _turns])
	if victory_achieved:
		var alive := [0, 0]
		for state in gpu_state_reader.get_all_unit_states():
			if not _is_unit_dead(state):
				alive[int(state.get("team", 0))] += 1
		_true(alive[0] == 0 or alive[1] == 0,
			"one side was annihilated (team0 %d alive, team1 %d alive)" % alive)


# === Harness ==================================================================

## The host's own auto-pass, held. Overridden rather than disconnected because the call is
## `call_deferred` from inside `_on_turn_opened` — there is no connection to break, and the
## alternative is a copy of the host's turn handling in the test.
func _pass_turn() -> void:
	if _hold_every_turn:
		return
	super()


## The marker, as of the instant a turn is spent — before `commit`'s drain can raise it again.
## Both halves: the seam's index, and whether the sprite node is still mounted.
func _observe_commit(_spent: int) -> void:
	_marker_at_commit.append(turn_marker_unit)
	_marker_node_at_commit.append(_turn_marker != null and is_instance_valid(_turn_marker))


## The observer, and the committer for the turns the host will not spend itself.
func _observe_turn(taker: int, _team: int) -> void:
	if taker < 0:
		return
	_turns += 1
	_freezes.append({"taker": taker, "combat_active": combat_active})
	if _commandable.has(taker) and not _hold_turns:
		# Committing with no edits IS "wait" (ADR-0239). Deferred so the commit never
		# re-enters the signal it is inside.
		call_deferred("_pass_turn")


## What the map is SHOWING at a deployment column — read off the rendered tile through the
## publish, not off any table this host keeps, so the arm cannot pass on bookkeeping alone.
func _marking_at(column: Vector2i) -> int:
	if _highlights == null:
		return CellMarking.Kind.NONE
	return _highlights.kind_at(_cell_of(column))


## The facing a unit on `tile` should have — the nearest authored enemy by column distance,
## computed here from the ENTD metas rather than by calling the host's helper.
func _expected_facing(tile: Vector2i):
	var best := Vector2i.ZERO
	var best_d := -1
	for enemy in _enemies:
		if not enemy.has_meta(ScenarioCast.ENTD_TILE_META):
			continue
		var cell: Vector3i = enemy.get_meta(ScenarioCast.ENTD_TILE_META)
		var d: int = absi(cell.x - tile.x) + absi(cell.y - tile.y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = Vector2i(cell.x, cell.y)
	return TileTraversalUtils.get_facing_direction_for_step(
		Vector3i(tile.x, tile.y, 0), Vector3i(best.x, best.y, 0))


## A unit-shaped stand-in carrying only `body_sprite_id` — the one property
## [StatusBubble3D.raise_for_unit] reads. Standing up a real unit for a pure height lookup
## would test the cast, not the lookup.
class _SpriteStubUnit extends Node:
	var body_sprite_id: int = 0


func _bubble_raise_for_sprite(sprite_id: int) -> float:
	var stub := _SpriteStubUnit.new()
	stub.body_sprite_id = sprite_id
	var y := StatusBubble3D.raise_for_unit(stub)
	stub.free()
	return y


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)

