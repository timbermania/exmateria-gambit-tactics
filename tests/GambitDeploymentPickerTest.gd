extends "res://src/scenes/GambitBattle.gd"
# test-kind: gpu
# seeded-break: drop the subtractive dim in src/ui3/formation/FormationMapHost.gd:347 (`_raise_pick_dim()` -> `pass`) — 'a subtractive dim was raised behind the grid instead', 'the dim's material is HELD, not discarded at build' and 'with the dim at exactly its authored strength' red; 83 assertions still pass (re-measured after arm 9 landed). Arm 9's own seed: revert `_close_picker`'s screen-first branch in src/scenes/GambitBattle.gd (drop the `leave()` and call `_end_pick()` unconditionally) — 'and the Status screen comes down with it', 'the coordinator is back at IDLE' and 'the pad is the battlefield's again' red, 83 still pass; measured, that is the bug this arm was written against. Arm 10's own seed: restore the `_on_menu_cancelled` one-press exit in src/ui3/formation/FormationDetailTransition.gd (append `if not action_rows.is_empty() and current_state() != State.IDLE: leave()` after its `close_action_menu()`) — 7 assertions red ('leaves you ON the Status screen' got 6 want 1, 'the Status panels are still up', 'the grid is still there', 'the camera is STILL taken'), 103 still pass; measured, and that is the ADR-0261 defect verbatim. ⚠️ It only reds THROUGH `_settle()`: without it the arm asserts 4 frames after the press, the 31-frame teardown has not landed yet, and the seeded defect scores GREEN — measured, the route is half the guard. DO NOT seed the picker's own opening (e.g. forcing `_open_deployment_picker`'s eligible-is-empty refusal): the test then waits for a pick that never arrives and HANGS to the 300 s timeout with NO verdict, which clause 8 rules is not a red at all — measured, not guessed

## The DEPLOYMENT PICKER, end to end on the real Gariland cast (#941) — the half of deployment
## that decides WHO fights, driven through the real screen rather than around it.
##
## A subclass of the production host, like [GambitBattleTest]: the thing under test is the host's
## own wiring of the map-hosted Formation screen (ADR-0137), so a harness that mounted its own
## coordinator would be testing the harness. `GambitBattleTest` owns the LATCH and the on-map
## editing verbs; this owns the picker, and the two do not overlap.
##
##   1. **○ on an empty zone tile raises the ROSTER GRID over the battlefield.** Not "deploys
##      `benched()[0]`", which is what it used to do and which agreed with the reserve BY
##      ACCIDENT OF ROSTER ORDER (#940's own note). The grid is the same 4x2 grid the
##      out-of-battle Formation screen uses — this host builds it lazily and answers "who is
##      selected" from it for the length of the pick, because a benched unit stands on no tile
##      the cursor could name.
##   2. **The backdrop does NOT come with it.** `paints_own_backdrop()` stays false, which is the
##      whole reason this is the map host with its grid switched on rather than the roster host
##      mounted over a battlefield: the roster host paints a cobble floor over the map you are
##      deploying onto. Asserted structurally, since a test cannot look at the screen.
##   3. **Arrows walk the grid, FOR REAL.** Physical `InputEventKey`s through
##      `Input.parse_input_event`, so the action lookup, the frozen cursor's swallow and the
##      host's own routing are all in the path. Setting `selected_cell` directly would skip
##      every one of them, and the routing is where "the key does nothing" lives.
##   4. **Tab opens the menu on the DEPLOY row set**, at its own home — over a grid, through the
##      MAIN-menu door, which is the door a plain roster uses and which this host refuses at
##      every other moment. It is the one row set this host still owns the dispatch for: the
##      other four rows it supplies are the coordinator's own verbs, dispatched there by name
##      (#1007).
##   5. **The chosen row lands the unit on the tile the picker was opened FROM** — not on the
##      cursor's tile, and not after a second question. The grid then goes away.
##   6. **✕ backs out without deploying.**
##   7. **The grid offers what the tile would actually TAKE.** With four of five Gariland tiles
##      held by cadets the reserve holds the last slot, so the grid holds exactly one name.
##   8. **The grid COMES IN — the dim ramps and the units travel.** A fade that never runs and one
##      that completes instantly end at the same rest state, so every other arm in this file passes
##      either way; this one reads the gesture MID-FLIGHT. The pure half ([FormationPickIn]'s
##      statics) is asserted for shape without a screen, and the live half is caught between
##      `begin_pick` and the landing.
##   9. **The deploy row reached through the STATUS SCREEN takes that screen with it.** ○ on a grid
##      cell opens the picked unit's Status screen over the pick, and Tab there carries the SAME
##      deploy row — so the pick can end with a screen standing on it. Every arm above reaches the
##      row from the bare grid, where there is nothing left to unwind, so none of them can see it.
##  10. **✕ walks the stack DOWN, one level per press** (ADR-0261) — the user's report, the opposite
##      door out of arm 9's state. Menu → Status → grid → battlefield, three presses, and the
##      claims (the camera takeover, which is `TileCursor._input_allowed()`'s gate) stay held until
##      the last one. It used to tear the WHOLE screen down on the first press and release the
##      takeover with the grid still up, waking the battlefield cursor under a live screen that no
##      remaining press could close.
##
## Run: "$GODOT" --path . res://tests/GambitDeploymentPickerTest.tscn   (timeout, not --quit-after)

const StartActionMenuScript = preload("res://src/ui3/detail/StartActionMenu.gd")

const SCENARIO := 9
const BATTLE_SEED := 424242
## Belt on every wait. A screen that never comes up would otherwise hang, and a hang is a worse
## verdict than a failure because nothing names it. Counted in ITERATIONS, not in wall clock —
## and sized for a FRAME rate, not a tick rate: this host runs uncapped (~1,100 fps observed)
## while the screen's animators are delta-paced at 2/60 s, so one menu-tick can take ~19 frames.
const MAX_WAIT_FRAMES := 12000

var _passed: int = 0
var _failed: int = 0


func get_test_name() -> String:
	return "GambitDeploymentPickerTest"


func _ready() -> void:
	DebugConfig.combat_seed = BATTLE_SEED
	DebugConfig.active_scenario_id = SCENARIO
	DebugConfig.combat_autostart = false
	# AUTOSAVE, so a developer who ticked the F3 auto-place box would boot this rig onto a
	# full zone — and the picker only opens on an EMPTY tile.
	DebugConfig.gambit_auto_deploy = false

	await super._ready()

	if lattice == null or director == null or assignment == null:
		print("[FAIL] GambitDeploymentPickerTest: the host did not boot")
		get_tree().quit(1)
		return

	await _arm_1_and_2_the_grid_comes_up_without_its_backdrop()
	await _arm_3_arrows_walk_the_grid()
	await _arm_4_and_5_tab_opens_the_menu_and_the_row_deploys()
	await _arm_6_cancel_backs_out_without_deploying()
	await _arm_7_the_grid_holds_what_the_tile_would_take()
	await _arm_8_the_grid_comes_in()
	await _arm_9_deploying_from_the_status_screen_takes_the_screen_with_it()
	await _arm_10_backspace_walks_the_stack_down_one_level_at_a_time()

	print("\n=== GambitDeploymentPickerTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GambitDeploymentPickerTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GambitDeploymentPickerTest")
		get_tree().quit(1)
	else:
		print("[PASS] GambitDeploymentPickerTest: the roster grid picks who fights, and the chosen"
			+ " unit lands on the tile the picker was opened from")
		get_tree().quit(0)


# === Arms =====================================================================

func _arm_1_and_2_the_grid_comes_up_without_its_backdrop() -> void:
	_eq(director.state(), TurnDirector.State.DEPLOYMENT, "the host opened in DEPLOYMENT")
	_eq(assignment.placed_count(), 0, "and with an empty field")
	_true(_formation_map_screen != null, "the map-hosted Formation screen is mounted")
	if _formation_map_screen == null:
		return

	var host := _map_formation_host()
	_true(host != null, "the map host is the screen's selection source")
	if host == null:
		return
	_true(not host.picking(), "no pick is open before the player asks for one")

	var tile: Vector2i = assignment.tiles[0]
	await _open_picker_on(tile)

	_true(_picker_open(), "○ on an empty zone tile opens the picker")
	_eq(_picker_tile, tile, "and it remembers the tile it was opened from")
	_true(host.picking(), "the grid is the selection source")
	# THE GRID IS BUILT, and this is the assertion the rest of the arm cannot make for it.
	# `selected_character()` reads the injected roster by index and nav falls through to
	# grid-bounds stepping when nothing is populated — so a host that never built a grid selects,
	# navigates and reports a character exactly like one that did. Seeding the build away passed
	# every other assertion in this file.
	_true(host.has_roster_grid(), "the roster grid is BUILT, not merely a list the host indexes")
	_eq(host.populated_cell_count(), mini(host.pick_count(), 8),
		"with one occupied cell per benched unit the player can see")
	_eq(host.pick_count(), assignment.benched().size(),
		"and it holds the whole bench — nothing on the field is deployable twice")
	_true(host.selected_character() != null, "a unit is selected on it")
	_true(host.picked_unit() != null, "with the battlefield unit behind it")
	_true(not assignment.is_placed(host.picked_unit()),
		"the selected unit is BENCHED — the grid offers who is not on the field")

	# The BACKDROP is the structural difference between this and mounting the roster host over a
	# battlefield: the roster host paints a cobble floor and pillarbox bars, which would cover the
	# map you are deploying onto. A test cannot look at the screen, so it asks the predicate that
	# decides it — and asks it WHILE the grid is up, which is the only moment the two could
	# disagree.
	_true(not host.paints_own_backdrop(),
		"the grid came up WITHOUT the roster's cobble backdrop")
	# …and the DIM took its place. The roster host's grid reads against a cobble floor; over the
	# map there is no backdrop at all, so the grid competes with a lit battlefield. Nothing else
	# in the picker's behaviour changes when the dim is missing, which is why it needs an
	# assertion of its own rather than being taken on trust from the screenshot.
	_true(host.has_pick_dim(), "a subtractive dim was raised behind the grid instead")
	_true(host.owns_roster_grid() == false,
		"and the host still does not CLAIM a grid — it is built for the pick and torn down after")


func _arm_3_arrows_walk_the_grid() -> void:
	var host := _map_formation_host()
	if host == null or not host.picking():
		_true(false, "arm 3 needs an open pick")
		return
	if host.pick_count() < 2:
		_true(false, "arm 3 needs a bench with more than one unit")
		return
	var first = host.picked_unit()

	await _press(KEY_RIGHT)
	var second = host.picked_unit()
	_true(second != null and second != first, "→ walks the grid to another unit")

	await _press(KEY_LEFT)
	_eq(host.picked_unit(), first, "← walks back")

	# Nothing was deployed by any of that — walking is not choosing.
	_eq(assignment.placed_count(), 0, "walking the grid deploys nobody")


func _arm_4_and_5_tab_opens_the_menu_and_the_row_deploys() -> void:
	var host := _map_formation_host()
	if host == null or not host.picking():
		_true(false, "arm 4 needs an open pick")
		return

	await _press(KEY_TAB)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() != null)
	var menu = _formation_map_screen.action_menu()
	_true(menu != null, "Tab opens the menu over the grid")
	if menu != null:
		_eq(menu.rows, StartActionMenuScript.ROWS_DEPLOY, "on the DEPLOY row set")
		_eq(menu.row_count(), 1, "which is one row")
		_eq(menu.location, StartActionMenuScript.LOC_DEPLOY, "at the deploy home")
		_true(not menu.is_row_disabled(DEPLOY_MENU_ROW),
			"and the row is live — the bench is the player's own")

	var chosen = host.picked_unit()
	var tile: Vector2i = _picker_tile
	# Move the CURSOR somewhere else first. The unit must land on the tile the picker was opened
	# from, and a picker that read the cursor instead would pass every other arm in this file.
	tile_cursor.grid_pos = assignment.tiles[assignment.tiles.size() - 1]

	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return not _picker_open())

	_true(assignment.is_placed(chosen), "the chosen unit is deployed")
	_eq(assignment.tile_of(chosen), tile, "on the tile the picker was opened FROM")
	_eq(assignment.placed_count(), 1, "and exactly one unit was deployed")
	_true(not host.picking(), "the pick has ended")
	_true(not host.has_roster_grid(), "and the grid was torn down with it")
	_true(not host.has_pick_dim(), "and so was the dim — a screen-covering quad never outlives its screen")
	_eq(_formation_map_screen.action_menu(), null, "the menu went with it")
	_eq(_formation_map_screen.action_rows, StartActionMenuScript.ROWS_ADJUST,
		"and the host's rows are handed back, so a later △ gets the four adjustment rows (#1007)")


func _arm_6_cancel_backs_out_without_deploying() -> void:
	var tile: Vector2i = assignment.free_tiles()[0]
	var before: int = assignment.placed_count()
	await _open_picker_on(tile)
	if not _picker_open():
		_true(false, "arm 6 needs an open pick")
		return
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return not _picker_open())
	_true(not _picker_open(), "✕ backs out of the picker")
	_eq(assignment.placed_count(), before, "and deployed nobody")
	_eq(assignment.unit_at(tile), null, "the tile it was opened from is still empty")


func _arm_7_the_grid_holds_what_the_tile_would_take() -> void:
	# Fill to one under the cap with NON-mandatory units, by hand: the reserve then holds the last
	# slot, and the grid must offer only the unit it is held FOR.
	assignment.clear()
	var mandatory = null
	var cadets: Array = []
	for unit in assignment.candidates():
		if assignment.is_mandatory(unit):
			mandatory = unit
		else:
			cadets.append(unit)
	_true(mandatory != null, "scenario 9 names a mandatory unit")
	if mandatory == null:
		return
	for i in range(assignment.cap - 1):
		assignment.place(cadets[i], assignment.tiles[i])
	_show_assignment()
	_eq(assignment.placed_count(), assignment.cap - 1, "the zone is one short of the cap")
	_eq(assignment.reserved_slots(), 1, "and the reserve is holding the last slot")

	await _open_picker_on(assignment.free_tiles()[0])
	var host := _map_formation_host()
	_true(_picker_open(), "the picker opens on the held slot")
	if host != null and host.picking():
		# The SIZE first. `benched()` is roster order and Ramza is first in it, so an unfiltered
		# grid ALSO answers `picked_unit() == mandatory` at cell (0,0) — the exact accident of
		# roster order this ticket exists to remove, and an arm that only asked the second
		# question would pass on it. Measured: dropping the `effective_cap` filter leaves this
		# assertion the only one in the arm that fires.
		_eq(host.pick_count(), 1, "the grid offers exactly one name")
		_eq(host.picked_unit(), mandatory, "and it is the unit the slot is held for")
		await _press(KEY_RIGHT)
		_eq(host.picked_unit(), mandatory, "→ has nowhere to go on a one-unit grid")
	await _press(KEY_TAB)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() != null)
	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return not _picker_open())
	_true(assignment.is_placed(mandatory), "choosing him fills the held slot")
	_eq(assignment.placed_count(), assignment.cap, "and the squad reaches the cap")


func _arm_8_the_grid_comes_in() -> void:
	# --- The PURE half: FormationPickIn's statics, asserted for SHAPE without a screen. -----------
	# These need no host at all, which is the point: `dim_fraction_at` and `slide_frame_at` are pure
	# functions of the tick, so a rig can seek any frame of the gesture rather than only its end.
	_eq(FormationPickIn.dim_fraction_at(0), 0.0, "the dim starts at nothing")
	_eq(FormationPickIn.dim_fraction_at(FormationPickIn.DIM_TICKS), 1.0,
		"and lands at full exactly ON the last tick, not one step short of it")
	_eq(FormationPickIn.dim_fraction_at(FormationPickIn.DIM_TICKS * 4), 1.0, "and holds there")
	var mid := FormationPickIn.dim_fraction_at(FormationPickIn.DIM_TICKS / 2)
	_true(mid > 0.0 and mid < 1.0, "and passes THROUGH — a snap would read 0 then 1 and nothing between")
	# The quantisation is the whole reason STEP_TICKS exists: consecutive vsyncs inside one step
	# must push the SAME value. A ramp that stepped every frame would pass every assertion above.
	_eq(FormationPickIn.dim_fraction_at(2), FormationPickIn.dim_fraction_at(3),
		"the ramp steps every STEP_TICKS vsyncs, not every frame")
	_true(FormationPickIn.dim_fraction_at(2) < FormationPickIn.dim_fraction_at(4),
		"and it does step — a constant would satisfy the line above")

	# The SLIDE, per row. Row 1 is ROW_STAGGER_TICKS behind row 0, which is the stagger's only
	# observable: both rows dock, so a stagger of zero ends identically.
	_eq(FormationPickIn.slide_frame_at(0, 0), 0, "row 0 starts fully off-screen")
	_eq(FormationPickIn.slide_frame_at(FormationPickIn.ROW_STAGGER_TICKS, 1), 0,
		"and row 1 is still off-screen when row 0 has already moved")
	_true(FormationPickIn.slide_frame_at(FormationPickIn.ROW_STAGGER_TICKS, 0) > 0,
		"— row 0 HAS moved by then, which is what makes the line above a stagger and not a stall")
	_eq(FormationPickIn.slide_frame_at(9999, 1), SpriteSlideAnimator.SLIDE_DURATION,
		"every row docks in the end")
	_true(FormationPickIn.total_ticks(FormationScene.ROWS) >= FormationPickIn.DIM_TICKS,
		"the gesture is not over until both halves are")

	# --- The LIVE half: catch the real screen mid-gesture. ---------------------------------------
	assignment.clear()
	_show_assignment()
	var host := _map_formation_host()
	if host == null:
		_true(false, "arm 8 needs the map host")
		return
	var tile: Vector2i = assignment.free_tiles()[0]
	tile_cursor.grid_pos = tile
	tile_cursor.cursor_moved.emit(tile)
	await get_tree().process_frame
	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return _picker_open())
	if not host.picking():
		_true(false, "arm 8 needs an open pick")
		return

	# The gesture is RUNNING. `_press` only waits four frames and this host is uncapped at ~1,100
	# fps, so four frames is a fraction of one vsync — the pick-in cannot have landed yet.
	_true(host.pick_animating(), "opening a pick starts the pick-in — it is not already over")
	_true(host.pick_dim_strength() >= 0.0, "the dim's material is HELD, not discarded at build")
	var peak := float(Tune.get_value(FormationMapHost.PICK_DIM_SLUG))
	_true(host.pick_dim_strength() < peak,
		"and the dim is still BELOW its authored strength — it faded in rather than snapping on")
	_true(host.pick_sliding(), "the units are latched and travelling")

	# The units are genuinely OFF their cells right now. This is the assertion the rest of the file
	# cannot make: it reads the BODY holder (the sprite the player sees, a detached scene-ROOT
	# sibling of the anchor), so a slide that moved anchors and left the bodies docked — the exact
	# bug aa65e2952 fixed for the Equip slide — fails HERE and nowhere else.
	var moved := 0
	for cell in host.visible_unit_cells():
		if host.pick_slide_offset_px(cell) > 1.0:
			moved += 1
	_true(moved > 0, "and their BODIES are off their cells, not just their anchors")

	# Mid-flight the ANCHORS are off their authored origins too. Asked against
	# `FormationScene.cell_origin_px` — a STATIC the rig computes for itself — rather than against
	# the host's own latch, so the host cannot both move the units and define where they belong.
	var off_origin := 0
	for cell in host.visible_unit_cells():
		if not host.cell_anchor_screen_px(cell).is_equal_approx(
				FormationScene.cell_origin_px(cell.x, cell.y)):
			off_origin += 1
	_true(off_origin > 0, "and their anchors are off the authored grid origins")

	# Now let it land.
	await _wait_until(func() -> bool: return not host.pick_animating())
	_true(not host.pick_animating(), "the pick-in lands")
	_true(is_equal_approx(host.pick_dim_strength(), peak),
		"with the dim at exactly its authored strength")
	_true(not host.pick_sliding(), "the latch is dropped")
	# And every unit is back on its AUTHORED origin — not merely "wherever the latch said", which is
	# what a landed-state check against `pick_slide_offset_px` would degrade into (the latch is
	# cleared on landing, so that reads 0 for a unit parked off-screen just as loudly as for a
	# docked one).
	var docked := 0
	var cells := host.visible_unit_cells()
	for cell in cells:
		if host.cell_anchor_screen_px(cell).is_equal_approx(
				FormationScene.cell_origin_px(cell.x, cell.y)):
			docked += 1
	_eq(docked, cells.size(), "and every unit is docked on its own authored cell origin")
	_true(cells.size() > 0, "— on a grid that had units on it at all")

	# Backing out takes the whole gesture with it — a ramp holding a freed material would be the
	# ADR-0162 bug wearing a new name.
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return not _picker_open())
	_true(not host.pick_animating(), "✕ ends the pick-in with the pick")
	_eq(host.pick_dim_strength(), -1.0, "and there is no material left to push to")
	_eq(host.pick_in_ticks(), -1, "and no clock left running")


## The deploy row reached through the STATUS SCREEN — the door a player actually walks through.
## ○ on a grid cell opens the picked unit's Status screen over the pick (the grid IS a roster, and
## that is the roster's own ○), and Tab there carries the SAME one-row deploy list. Choosing it used
## to end the pick UNDERNEATH a live screen: the grid and the dim came down, the Status panels did
## not, and the coordinator still owned the pad — a deploy that had happened behind a screen the
## player could not get out of. Arms 4-7 all reach the row from the bare grid, where the coordinator
## is at IDLE and there is nothing left to unwind, so not one of them can fail on it.
func _arm_9_deploying_from_the_status_screen_takes_the_screen_with_it() -> void:
	assignment.clear()
	_show_assignment()
	var host := _map_formation_host()
	if host == null:
		_true(false, "arm 9 needs the map host")
		return
	var tile: Vector2i = assignment.free_tiles()[0]
	await _open_picker_on(tile)
	if not _picker_open():
		_true(false, "arm 9 needs an open pick")
		return
	# Let the pick-in LAND first — ○ mid-gesture is a different question, and arm 8 owns it.
	await _wait_until(func() -> bool: return not host.pick_animating())
	var chosen = host.picked_unit()
	_true(chosen != null, "the grid has a unit under its box to deploy")

	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return _formation_map_screen.detail_overlay() != null \
		and not _formation_map_screen.is_moving())
	_true(_formation_map_screen.detail_overlay() != null,
		"○ on a grid cell opens that unit's Status screen over the pick")
	_eq(_formation_map_screen.current_state(), FormationDetailTransitionScript.State.DETAIL,
		"and the coordinator is ON that screen")
	_true(host.picking(), "the pick is still open underneath it — a look is not a choice")

	await _press(KEY_TAB)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() != null)
	var menu = _formation_map_screen.action_menu()
	_true(menu != null, "Tab opens the menu on the Status screen too")
	if menu != null:
		_eq(menu.rows, StartActionMenuScript.ROWS_DEPLOY,
			"carrying the SAME deploy row — one row set on both doors (ADR-0247 §3)")

	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return not _picker_open())

	_true(assignment.is_placed(chosen), "the row deploys from the Status screen")
	_eq(assignment.tile_of(chosen), tile, "onto the tile the picker was opened from")
	# The TEARDOWN, which is what this arm exists for.
	_eq(_formation_map_screen.detail_overlay(), null, "and the Status screen comes down with it")
	_eq(_formation_map_screen.current_state(), FormationDetailTransitionScript.State.IDLE,
		"the coordinator is back at IDLE — nothing is left standing over the battlefield")
	_true(not _formation_map_screen.map_input_owned(),
		"and the pad is the battlefield's again — a screen that is gone owns no input")
	_eq(_formation_map_screen.action_menu(), null, "the menu went too")
	_true(not host.picking(), "the pick has ended")
	_true(not host.has_roster_grid(), "the grid was torn down with it")
	_true(not host.has_pick_dim(), "and so was the dim")
	_eq(_formation_map_screen.action_rows, StartActionMenuScript.ROWS_ADJUST,
		"and the host's rows are handed back")


## ✕ WALKS THE STACK DOWN, one level per press, and the claims stay held until it is empty (ADR-0261).
##
## The user's report, mechanized: Enter on an empty zone tile → the grid; Enter on a cell → that
## unit's Status screen over it; Tab → the menu; Backspace → **and the whole screen tore down**,
## because `_on_menu_cancelled` also called `leave()` whenever the host had supplied action rows.
## That teardown released the camera takeover with the pick's grid still on the display, and the
## takeover is `TileCursor._input_allowed()`'s gate — so the battlefield cursor came back to life
## under a live screen, with ○ dead (`_on_deployment_confirm` refuses during a pick) and ✕ swallowed
## by the cursor before the grid's own dismiss could ever see it. No press left could close it.
##
## Every assertion here shares arm 9's setup (charter clause 13), and the two are opposite doors out
## of the same state: arm 9 deploys and expects EVERYTHING to come down, this backs out and expects
## exactly one level to.
func _arm_10_backspace_walks_the_stack_down_one_level_at_a_time() -> void:
	assignment.clear()
	_show_assignment()
	var host := _map_formation_host()
	if host == null:
		_true(false, "arm 10 needs the map host")
		return
	var S = FormationDetailTransitionScript.State
	var tile: Vector2i = assignment.free_tiles()[0]
	await _open_picker_on(tile)
	if not _picker_open():
		_true(false, "arm 10 needs an open pick")
		return
	await _wait_until(func() -> bool: return not host.pick_animating())
	_eq(_formation_map_screen.current_state(), S.PICK,
		"the pick is a STACK LEVEL — the coordinator can see the grid it raised")
	_true(_formation_map_screen.claims_held(),
		"and it holds the claims: the camera is taken, so the battlefield cursor is frozen")
	_true(not _formation_map_screen.map_input_owned(),
		"but NOT the pad — the grid reads that itself, and a wholesale claim would eat its arrows")

	# ○ on a cell: the picked unit's Status screen, over the pick.
	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return _formation_map_screen.detail_overlay() != null \
		and not _formation_map_screen.is_moving())
	_eq(_formation_map_screen.current_state(), S.DETAIL, "○ on a cell stacks Status ON the pick")
	_true(_formation_map_screen.map_input_owned(), "and NOW the coordinator owns the pad")

	# Tab: the menu, carrying the deploy row.
	await _press(KEY_TAB)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() != null)
	_true(_formation_map_screen.action_menu() != null, "Tab opens the menu on it")

	# ✕ #1 — THE PRESS FROM THE REPORT. The menu closes and NOTHING else does.
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() == null)
	_eq(_formation_map_screen.action_menu(), null, "✕ closes the menu")
	# SETTLE BEFORE ASSERTING, and this is the arm's whole route (see `_settle`). Every assertion
	# below states that something did NOT happen, and a teardown is animated: read four frames after
	# the press — which is all `_press` allows — and the screen it is about to tear down is still
	# standing, so the defect reads as the fix. Measured: 31 frames.
	await _settle()
	_eq(_formation_map_screen.current_state(), S.DETAIL,
		"and leaves you ON the Status screen — the menu is one level, not the whole screen")
	_true(_formation_map_screen.detail_overlay() != null, "the Status panels are still up")
	_true(host.picking(), "and the pick is still open underneath them")
	_true(_formation_map_screen.claims_held(),
		"the claims are STILL held — a screen is up, so the battlefield cursor stays frozen")

	# ✕ #2 — off the Status screen, back to the grid it was opened from.
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return _formation_map_screen.current_state() == S.PICK)
	_eq(_formation_map_screen.current_state(), S.PICK, "✕ again pops Status and lands on the pick")
	_eq(_formation_map_screen.detail_overlay(), null, "the Status panels came down")
	_true(host.picking(), "the grid is still there — it is what you backed out TO")
	_true(host.has_roster_grid(), "and it is still built")
	_true(_formation_map_screen.claims_held(),
		"the camera is STILL taken: the grid is a screen, and a screen freezes the cursor")

	# ✕ #3 — off the grid. Only NOW is the display the battlefield's again.
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return not _picker_open())
	_eq(_formation_map_screen.current_state(), S.IDLE, "✕ off the grid empties the stack")
	_true(not host.picking(), "the pick ended")
	_true(not host.has_roster_grid(), "the grid is gone")
	_true(not host.has_pick_dim(), "and so is the dim")
	_true(not _formation_map_screen.claims_held(),
		"and ONLY now are the claims released — the invariant is 'held iff a screen is up'")
	_eq(assignment.placed_count(), 0, "backing out all the way deployed nobody")
	_eq(_formation_map_screen.action_rows, StartActionMenuScript.ROWS_ADJUST,
		"and the host's rows are handed back")


# === Harness ==================================================================

## Put the cursor on `column` and press ○ FOR REAL, then wait for the grid to come up.
func _open_picker_on(column: Vector2i) -> void:
	tile_cursor.grid_pos = column
	tile_cursor.cursor_moved.emit(column)
	await get_tree().process_frame
	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return _picker_open())


## One physical key press through the real InputMap. Four frames after, which is what the other
## input-driven rigs in this tree allow for a press to be routed and acted on.
func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 4:
		await get_tree().process_frame


## Wait until `predicate` answers true, or the belt runs out. Counts ITERATIONS: a wall-clock
## budget on a machine under load makes a slow pass look like a hang.
func _wait_until(predicate: Callable) -> void:
	var frames := 0
	while frames < MAX_WAIT_FRAMES and not bool(predicate.call()):
		await get_tree().process_frame
		frames += 1
	if frames >= MAX_WAIT_FRAMES:
		_true(false, "waited %d frames and the condition never held" % MAX_WAIT_FRAMES)


## Let an animated teardown either happen or fail to happen, before asserting which (ADR-0261).
##
## The negative assertions in arm 10 need this and the positive ones elsewhere do not: `_wait_until`
## can watch FOR a state, but nothing can watch for the absence of one, so the only honest form is
## "give it longer than the transition takes, then look". SIZED FROM A MEASUREMENT, not a guess —
## the seeded ✕-tears-down-the-screen defect left DETAIL after 31 frames, and 300 is an order of
## margin on that while still costing a fraction of a second. Frames, never wall clock (charter
## clause 14): a frame count is the same measurement under N=8 load, and a second is not.
func _settle() -> void:
	for _i in 300:
		await get_tree().process_frame


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)
