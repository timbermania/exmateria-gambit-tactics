extends Node3D
# test-kind: logic
# seeded-break: mirrored the unit centre in open_main_menu (main_container_for(2*SCREEN_CENTER_X - unit_cx) instead of main_container_for(unit_cx)) so the menu opens on the SAME side as the unit (the pre-RE26 overlap bug); the 'LEFT-half unit: menu should open RIGHT', 'RIGHT-half unit: menu should open LEFT', 'main menu not on the expected side', 'main menu container does not match its location' and 'reopened menu not on the expected side' asserts red, the 5-item row set + Item->Equip entry + esc round-trip/redock/orb-restore asserts stay green

## FormationDetailTransition MAIN-formation START menu + Equip esc-unwind (headful) —
## FORMATION_SCREEN.md §15.20 grid context / §15.23, RE round 25-26 (oracle savestate4/6). Proves:
##   - pressing START on the PLAIN roster opens the 5-item START menu OPPOSITE the selected unit's
##     screen half (RE26): unit LEFT half → menu top-RIGHT (172,32); unit RIGHT half → menu
##     top-LEFT (10,32) — so it never overlaps the unit;
##   - choosing "Item" (row 0) there enters the Equip sub-screen (settled detail + §15.23 slide);
##   - esc on the Equip list-menu unwinds the WHOLE screen back to the MAIN roster + reopens the
##     START menu on the correct side — the detail overlay is gone and every unit is re-docked.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null and form.selected_character() != null, "no formation/selection")
	if form == null:
		_finish()
		return

	# --- 1. side flip (RE26): menu opens opposite the selected unit's half -------------------
	var left_cell := _find_cell(form, true)    # a populated cell on the LEFT half (unit x<128)
	var right_cell := _find_cell(form, false)  # …and one on the RIGHT half (unit x>=128)
	if left_cell.x >= 0:
		form.set_selected_cell(left_cell)
		host.open_main_menu()
		_expect(host.action_menu() != null and host.action_menu().container_rect() == Rect2i(StartActionMenu.MAIN_CONTAINER_RIGHT),
			"LEFT-half unit %s: menu should open RIGHT (172,32), got %s" % [left_cell, _cr(host)])
		host.close_action_menu()
	if right_cell.x >= 0:
		form.set_selected_cell(right_cell)
		host.open_main_menu()
		_expect(host.action_menu() != null and host.action_menu().container_rect() == Rect2i(StartActionMenu.MAIN_CONTAINER),
			"RIGHT-half unit %s: menu should open LEFT (10,32), got %s" % [right_cell, _cr(host)])
		host.close_action_menu()

	# --- 2. full round-trip: START on roster → Item → Equip → esc → main + redock ------------
	var sel: Vector2i = form.selected_cell
	# Policy returns a KEY-LOCATION slug (ADR-0088 Amendment 2); the menu records the
	# picked location and derives its container from the location's live value.
	var expected := StartActionMenu.main_container_for(form.selected_unit_screen_center().x)
	var docked := form.cell_anchor_screen_px(sel)

	host._input(_action("formation_start_menu"))   # START on the plain roster
	var menu = host.action_menu()
	_expect(menu != null and host.detail_overlay() == null, "START on roster did not open the main menu (no detail)")
	_expect(menu != null and menu.location == expected,
		"main menu not on the expected side %s, got %s" % [expected, _cr(host)])
	_expect(menu != null and menu.container_rect() == Rect2i(Tune.get_value(expected)),
		"main menu container %s does not match its location %s" % [_cr(host), expected])
	_expect(menu != null and menu.rows == StartActionMenu.ROWS and menu.row_count() == 5,
		"main menu should be the 5-item START set")

	# Item (row 0) → build the detail overlay and SLIDE the chrome (docked→top); the Equip roster
	# slide is DEFERRED to entry_slide_done (§15.1/§15.5), so it is NOT sliding yet — driving the
	# chrome slide to settle is what starts it (guarded in detail by FormationMainMenuEntrySlideTest).
	menu.confirm()
	_expect(host.detail_overlay() != null, "Equip entry did not build the detail overlay")
	# Pump real frames through the chrome entry-slide → entry_slide_done → the Equip roster slide,
	# to the settled Equip screen (the host + detail _process own the menu-tick cadence).
	await _pump_until(func(): return host.is_equip_screen_open(), 240)
	_expect(host.is_equip_screen_open(), "Equip screen not open after the chrome slide + roster slide")

	host.action_menu().cancel()   # esc on the Equip list-menu → animated full unwind (no teleport)
	await _pump_until(func(): return host.detail_overlay() == null, 240)
	_expect(host.detail_overlay() == null, "detail overlay not torn down on Equip esc")
	_expect(not host.is_equip_screen_open() and not host.is_equip_sliding(), "Equip screen still open after esc")
	var back = host.action_menu()
	_expect(back != null and back.location == expected,
		"reopened menu not on the expected side %s, got %s" % [expected, _cr(host)])
	_expect(form.cell_anchor_screen_px(sel).distance_to(docked) <= 0.5,
		"unit not re-docked after esc: %s (want %s)" % [form.cell_anchor_screen_px(sel), docked])
	_expect(form._orbs_visible and form._box_trail_visible, "orbs/box not restored after esc")

	if back != null:
		back.cancel()
		await get_tree().process_frame
		_expect(host.action_menu() == null, "main menu did not close on esc back to the roster")

	_finish()


## Find a populated grid cell whose unit sprite-centre is on the requested half (left=true → x<128).
## Returns Vector2i(-1,-1) if none. Uses the docked cell centre (the roster is docked).
func _find_cell(form, left: bool) -> Vector2i:
	for cell in form.visible_unit_cells():
		var cx: float = form.cell_anchor_screen_px(cell).x + form.BODY_ANCHOR_DX
		if (cx < StartActionMenu.SCREEN_CENTER_X) == left:
			return cell
	return Vector2i(-1, -1)


## Pump real process frames until `cond` holds or `max_frames` elapse (a cap so a stall still quits —
## a hung test with buffered prints is indistinguishable from a slow one at the redirected log).
func _pump_until(cond: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame


func _cr(host):
	return host.action_menu().container_rect() if host.action_menu() != null else "no-menu"


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationMainMenuNav test")
	else:
		print("[PASS] FormationMainMenuNav: side-flip + roster START→menu, Item→Equip, esc→main+redock")
	get_tree().quit()
