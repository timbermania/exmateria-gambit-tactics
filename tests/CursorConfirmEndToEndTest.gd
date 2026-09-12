extends Node3D

## ADR-0137 end-to-end guard — the one thing every earlier check stepped around: a REAL key,
## through the REAL input map, into a battlefield booted at its REAL defaults.
##
## `FormationMapHostTest` covers the pure functions and the host seam; the capture prototypes
## emitted `cursor_confirmed` DIRECTLY. Between them they skipped the action lookup, the cursor's
## swallow and the listener's gate — which is precisely where "cursor on a unit, press Enter,
## nothing happens" lives. This test refuses to fake any of those.
##
## It is slow (it boots a real GPU arena). That cost IS the coverage: a REAL key, through the
## REAL input map, into a battlefield booted at its REAL defaults cannot be seen any cheaper —
## and every arm below asserts through `Input.parse_input_event`, never a signal emit.
##
## ⚠️ ADR-0258 RETIRED THE DEPLOYMENT MARCH, and with it two arms this test used to carry
## (`_test_confirm_during_march`, `_test_march_is_transient`) plus the march precondition on the
## inspect arm. What is left is what was always this test's own: the input path. The arena now
## boots straight into a placed, live battle, so Enter has exactly one meaning from the first
## frame — which is the simplification the retirement bought, stated as a test.
##
## Headful only (repo CLAUDE.md): `godot --path . res://tests/CursorConfirmEndToEndTest.tscn`

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const CellMarking = ExMateriaSchema.CellMarking
const TerrainCell = ExMateriaSchema.TerrainCell

const CONFIRM_ACTION := "cursor_confirm"
const INSPECT_ACTION := "unit_inspect"

var _failed := false
var _arena: Node3D = null
## `TileCursor` has no `class_name` since ADR-0206 — the published name is `CursorRig`.
var _cursor: Node3D = null
var _screen = null
var _host = null
var _activations := 0


func _ready() -> void:
	_test_action_is_dedicated()
	await _boot_arena()
	if _arena != null:
		await _test_inspect_is_never_gated()
		await _test_confirm_opens_the_screen()

	if _failed:
		print("[FAIL] cursor_confirm end-to-end")
	else:
		print("[PASS] cursor_confirm end-to-end: dedicated action, a real Tab inspects and a real"
			+ " Enter opens the Formation screen (ADR-0137)")
	get_tree().quit()


## The action exists and is NOT Godot's `ui_accept`. `ui_accept` carries KEY_SPACE by default and
## Space is combat start/pause here (ADR-0137 Amendment 1 §5) — riding it would make every pause a
## confirm. Nothing else pins this, and the failure mode is silent.
func _test_action_is_dedicated() -> void:
	_expect(InputMap.has_action(CONFIRM_ACTION),
		"InputMap must register '%s' — the cursor's confirm has no meaning without it" % CONFIRM_ACTION)
	if not InputMap.has_action(CONFIRM_ACTION):
		return
	var has_enter := false
	for e in InputMap.action_get_events(CONFIRM_ACTION):
		if not (e is InputEventKey):
			continue
		_expect(e.physical_keycode != KEY_SPACE and e.keycode != KEY_SPACE,
			"'%s' must NOT carry KEY_SPACE — Space is combat start/pause" % CONFIRM_ACTION)
		if e.physical_keycode == KEY_ENTER or e.physical_keycode == KEY_KP_ENTER:
			has_enter = true
	_expect(has_enter, "'%s' must carry Enter — that is the key the player presses" % CONFIRM_ACTION)

	# INSPECT is its own action, and the two must not share a key: ACT and INSPECT are the whole
	# point of the split (ADR-0137 Amendment 2). One key doing both is the arrangement that made
	# Enter's meaning depend on the phase.
	_expect(InputMap.has_action(INSPECT_ACTION),
		"InputMap must register '%s' — inspecting a unit has no other route" % INSPECT_ACTION)
	if not InputMap.has_action(INSPECT_ACTION):
		return
	var inspect_keys: Array = []
	for e in InputMap.action_get_events(INSPECT_ACTION):
		if e is InputEventKey:
			inspect_keys.append(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	_expect(KEY_TAB in inspect_keys, "'%s' must carry Tab" % INSPECT_ACTION)
	_expect(not (KEY_ENTER in inspect_keys) and not (KEY_KP_ENTER in inspect_keys),
		"'%s' must NOT carry Enter — Enter ACTS, Tab INSPECTS" % INSPECT_ACTION)
	_expect(not (KEY_SPACE in inspect_keys),
		"'%s' must NOT carry Space — Space starts the battle" % INSPECT_ACTION)

	# The two battle keys are split, and the fused one is gone (ADR-0082's single Tab toggle).
	_expect(InputMap.has_action("battle_start"), "'battle_start' must be registered (Space)")
	_expect(InputMap.has_action("battle_pause"), "'battle_pause' must be registered (Esc)")
	_expect(not InputMap.has_action("command_mode_toggle"),
		"the fused command_mode_toggle must be gone — starting a battle and pausing one are not"
			+ " the same kind of transition, and one key for both left nothing for the map cursor")


func _boot_arena() -> void:
	var packed: PackedScene = load("res://assets/scenes/GPUArena.tscn")
	_arena = packed.instantiate()
	add_child(_arena)                 # booted at its DEFAULTS — set nothing on it
	for _i in 120:
		await get_tree().process_frame

	_cursor = _arena.get_node_or_null("TileCursor")
	_screen = _arena.get_node_or_null("PlayerCamera/FocusPoint/Camera/FormationMapScreen")
	_host = _screen.get_node_or_null("FormationMapHost") if _screen != null else null
	_expect(_cursor != null, "the arena must build a TileCursor")
	_expect(_screen != null, "the arena must mount the map-hosted Formation screen (ADR-0137)")
	_expect(_host != null, "the mounted screen must carry a FormationMapHost")
	if _host != null:
		_host.unit_activated.connect(func(_c): _activations += 1)
	if _cursor == null or _host == null:
		_arena = null


## INSPECT is never gated. It was the capability the deployment march used to swallow — refused
## for the whole of PLACEMENT while the hover band went on advertising the unit as interactive —
## and it is asserted here still, because "looking at a unit has no host-specific reason to be
## refused" is a rule about every future phase and not only about the retired one.
func _test_inspect_is_never_gated() -> void:
	var unit = _first_player_unit()
	if unit == null:
		_expect(false, "the arena should have a placed player unit at boot")
		return
	var before := _activations
	await _inspect_on(unit.get_current_cell())
	for _i in 30:
		await get_tree().process_frame
	_expect(_activations > before,
		"Tab on a unit must open its screen — inspecting cannot conflict with anything, so"
			+ " nothing has grounds to refuse it")
	_expect(_screen.current_state() != 0,
		"the coordinator must leave IDLE when the inspected screen opens; state=%d" % _screen.current_state())
	# Put the screen away so the phases below run against a live map again.
	_screen.leave()
	for _i in 120:
		await get_tree().process_frame
	_expect(_screen.current_state() == 0, "the inspected screen must close again on leave()")


## Enter on a unit opens the screen, pauses combat, and leaves the coordinator's IDLE state.
## This is the ADR-0137 feature itself, exercised through a real key rather than a direct signal
## emit. Since ADR-0258 it is true from the FIRST frame — there is no phase in which the arena
## answers ○ with something else, so no precondition guards this arm.
func _test_confirm_opens_the_screen() -> void:
	var unit = _first_player_unit()
	var cell: Vector3i = unit.get_current_cell() if unit != null else TerrainCell.NONE
	if cell == TerrainCell.NONE:
		_expect(false, "a deployed player unit should stand on a tile")
		return
	var before := _activations
	await _confirm_on(cell)
	for _i in 30:
		await get_tree().process_frame
	_expect(_activations > before,
		"Enter on a unit must open its Formation screen (unit_activated)")
	_expect(_screen.current_state() != 0,
		"the coordinator must leave IDLE when the screen opens; state=%d" % _screen.current_state())
	_expect(not _arena.combat_active,
		"opening the screen is a paused camera takeover — combat must be paused (ADR-0137)")
	# Closing it must put back what it interrupted, not force the battle live. `pause_battle` used
	# to be `combat_active = not paused`, which was harmless only while the screen was unreachable
	# before the battle started. Inspecting made it reachable before `start_battle`, and the old
	# version would have STARTED the fight the moment the player closed the screen.
	_screen.leave()
	for _i in 150:
		await get_tree().process_frame
	_expect(not _arena.combat_active,
		"closing the screen must RESTORE the prior state — it must never start the battle")


## Put the cursor on `tile` and press Enter FOR REAL: a physical `InputEventKey` through
## `Input.parse_input_event`, so the action lookup, the cursor's `_unhandled_input` gate and its
## `set_input_as_handled` swallow all run. Never `cursor_confirmed.emit` — that is the shortcut
## that hid this bug.
func _confirm_on(cell: Vector3i) -> void:
	await _press_on(cell, KEY_ENTER)


## The INSPECT half of the same gesture — Tab, for real, through the same path.
func _inspect_on(cell: Vector3i) -> void:
	await _press_on(cell, KEY_TAB)


func _press_on(cell: Vector3i, keycode: int) -> void:
	if cell == TerrainCell.NONE:
		return
	# The cursor names a COLUMN, not a cell — level cycling is deferred (#795), so the
	# level is dropped HERE, at the one place that knows the cursor cannot express it,
	# rather than by never having carried it (ADR-0219 dec. 1).
	_cursor.grid_pos = Vector2i(cell.x, cell.y)
	# `Vector2i` alone since ADR-0194 — `cursor_moved` was one of criterion 3's five rows
	# and the node half went with them.
	_cursor.cursor_moved.emit(_cursor.grid_pos)
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 4:
		await get_tree().process_frame


## The first placed player unit. Was `_first_undeployed_player_unit`, which walked the march's
## own `_remaining_player` queue; with the march gone every unit is placed at boot.
func _first_player_unit():
	for unit in _arena.team0_units:
		if is_instance_valid(unit) and unit.get_current_cell() != TerrainCell.NONE:
			return unit
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		print("  [x] %s" % message)
