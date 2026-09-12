extends Node3D
# test-kind: logic
# seeded-break: inverted the re-home branch condition in _open_sub_menu (if false and _parked_menu ... so the parked instance is never reused) — the pre-ADR-0088 teardown+rebuild shape, a fresh menu built on every sub-screen switch; the 'the SAME menu instance must survive Item→Equip' and 'the SAME menu instance must survive Ability entry' asserts red (different instance ids), the parked-mid-slide (null answer / not freed / hidden) + re-homed content (rows/container/aperture/row-0) asserts stay green

## Guard (§15.23 / ADR-0088 Amendment 2 §4 — place_at's first production consumer):
## the Item→Equip and Ability sub-menu switches RE-HOME the LIVE StartActionMenu
## instead of teardown+rebuild. §15.23 proves the ROM re-renders the SAME slot-6
## list-menu window in place (the "Order Unit ghost"), so the port keeps ONE menu
## instance across the switch:
##   - choosing Item/Ability PARKS the menu (hidden, answers null, input falls
##     through) — it is NOT freed while the roster slide runs;
##   - at settle the SAME instance is re-homed (place_at + set_rows + box-open
##     replay) as the Equip/Ability list-menu at its §15.23 container.
## Covers BOTH entry contexts: the main-formation menu (plain roster) and the
## detail-screen START menu.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

var _failed := false


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

	# --- 1. main-menu context: START on the roster → Item → the SAME instance -----
	host._input(_action("formation_start_menu"))
	var menu = host.action_menu()
	_expect(menu != null, "START on the roster did not open the main menu")
	if menu == null:
		_finish()
		return
	var menu_id: int = menu.get_instance_id()

	menu.confirm()   # row 0 = "Item" → the Equip entry begins
	# Parked, not freed: the accessor answers null (the menu is not open), input no
	# longer routes to it, but the INSTANCE survives hidden through the slide.
	_expect(host.action_menu() == null, "action_menu() must answer null while parked mid-slide")
	_expect(is_instance_valid(menu), "the menu must NOT be freed on Item (§15.23 in-place switch)")
	_expect(is_instance_valid(menu) and not menu.visible, "the parked menu must be hidden mid-slide")

	await _pump_until(func(): return host.is_equip_screen_open(), 240)
	_expect(host.is_equip_screen_open(), "Equip screen did not settle")
	var equip = host.action_menu()
	_expect(equip != null and equip.get_instance_id() == menu_id,
		"the SAME menu instance must survive Item→Equip (got %s, want id %d)"
		% [equip.get_instance_id() if equip != null else -1, menu_id])
	if equip != null:
		_expect(equip.visible, "the re-homed Equip menu must be visible")
		_expect(equip.rows == StartActionMenu.ROWS_EQUIP and equip.row_count() == 4,
			"re-homed menu content must be Equip/Best/Remove/List, got %s" % [equip.rows])
		_expect(equip.selected_row() == 0, "re-homed menu selection must reset to row 0")
		_expect(equip.container_rect() == Rect2i(StartActionMenu.EQUIP_CONTAINER),
			"re-homed menu container = %s, want EQUIP_CONTAINER" % equip.container_rect())
		# The box-open REPLAYS at the new home: pump past the beat, then the settled
		# aperture is the full Equip container.
		await _pump_until(func(): return equip.aperture() == Rect2i(StartActionMenu.EQUIP_CONTAINER), 120)
		_expect(equip.aperture() == Rect2i(StartActionMenu.EQUIP_CONTAINER),
			"box-open did not replay/settle at the Equip home (aperture %s)" % equip.aperture())

	# --- unwind to the roster for the second context ------------------------------
	host.action_menu().cancel()
	await _pump_until(func(): return host.detail_overlay() == null, 300)
	_expect(host.detail_overlay() == null, "Equip esc did not unwind")
	if host.action_menu() != null:
		host.action_menu().cancel()   # close the reopened main menu
		await get_tree().process_frame

	# --- 2. detail-screen context: ○ → START → Ability → the SAME instance --------
	form._unhandled_input(_action("ui_accept"))
	_expect(host.detail_overlay() != null, "○-press did not open the detail overlay")
	host.open_action_menu()
	var menu2 = host.action_menu()
	_expect(menu2 != null, "START on the detail screen did not open the action menu")
	if menu2 == null:
		_finish()
		return
	var menu2_id: int = menu2.get_instance_id()
	menu2.move_down()   # row 1 = "Ability"
	menu2.confirm()
	_expect(host.action_menu() == null, "action_menu() must answer null while parked (Ability)")
	_expect(is_instance_valid(menu2), "the menu must NOT be freed on Ability (§15.23 RE27 mirror)")

	await _pump_until(func(): return host.is_equip_screen_open(), 240)
	var ability = host.action_menu()
	_expect(ability != null and ability.get_instance_id() == menu2_id,
		"the SAME menu instance must survive Ability entry")
	if ability != null:
		_expect(ability.rows == StartActionMenu.ROWS_ABILITY and ability.row_count() == 3,
			"re-homed menu content must be Set/Remove/Learn, got %s" % [ability.rows])
		_expect(ability.container_rect() == Rect2i(StartActionMenu.ABILITY_CONTAINER),
			"re-homed menu container = %s, want ABILITY_CONTAINER" % ability.container_rect())

	_finish()


## Pump real process frames until `cond` holds or `max_frames` elapse.
func _pump_until(cond: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationMenuRehome test")
	else:
		print("[PASS] FormationMenuRehome: one menu instance survives Item→Equip / Ability (parked → place_at + set_rows)")
	get_tree().quit()
