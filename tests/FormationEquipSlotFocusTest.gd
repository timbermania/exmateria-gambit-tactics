extends Node3D
# test-kind: logic
# seeded-break: dropped row 0 from the _on_equip_menu_chosen hand-off condition ((row == 0 or row == 2) -> (row == 2)) so confirming "Equip" no longer enters slot focus; the focus-transfer + cursor-mounted + menu-background + old-cursor-removed + every slot-nav + no-teardown-on-× asserts red (14 of them), the menu-row/precondition asserts stay green

## The Eqp slot-list FOCUS sub-state (FORMATION_SCREEN.md §15.25, RE round 33) — headful guard.
## From the settled Item→Equip screen (§15.23) with the Equip/Best/Remove/List list-menu open and
## the glove on "Equip" (row 0), pressing ○ (confirm) hands INPUT FOCUS from the list-menu into the
## Eqp slot panel. This proves:
##   (1) the glove cursor is mounted over the Eqp panel, anchored on the FRAME's left edge
##       (LOWER_FRAME_EQUIP (14,136), F3-pins materialised 2026-08-11) pointing at slot row 0
##       (R.Hand) — cursor_display_pos_in(frame,row,0) = (2, 146) (half-off-screen left), NOT
##       the list-menu container;
##   (2) the list-menu goes to BACKGROUND (§15.21 CLUT swap) while the panel is focused;
##   (3) ↑/↓ cycle the cursor through all 5 SLOT_ROWS (R/L.Hand, Head, Body, Accessory), wrapping;
##   (4) △/× returns focus to the list-menu (un-backgrounds it) WITHOUT tearing the screen down.
## Out of scope (the NEXT ○): the per-slot item picker.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

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

	# Drive to the settled Item→Equip screen: ○ opens the detail overlay, START opens the action
	# menu, "Item" (row 0) starts the Equip transition, then step the slide to settle.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○-press did not open the detail overlay")
	host.open_action_menu()
	host.action_menu().confirm()                      # choose "Item" → the Equip slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()

	var menu = host.action_menu()
	_expect(menu != null, "Equip list-menu did not open at settle")
	if menu == null or d == null:
		_finish()
		return
	_expect(menu.rows == StartActionMenu.ROWS_EQUIP, "not on the Equip list-menu (rows=%s)" % [menu.rows])
	_expect(not menu.is_backgrounded(), "Equip list-menu started backgrounded (should be foreground)")
	_expect(not d.is_slot_focused(), "slot list already focused before ○")

	# --- ACT: ○ (confirm) on the "Equip" row (row 0) hands focus into the Eqp panel. ---
	menu.confirm()

	# (1) the glove cursor is mounted over the Eqp panel at slot row 0's LEFT-EDGE anchor.
	_expect(d.is_slot_focused(), "○ on Equip did not transfer focus to the Eqp slot list")
	_expect(d.slot_cursor_mounted(), "slot glove cursor not mounted over the Eqp panel")
	_expect(d.slot_row() == 0, "slot cursor not seeded on row 0 (R.Hand): got %d" % d.slot_row())
	_expect(d.slot_cursor_anchor() == Vector2(2, 146),
		"slot glove(row0) anchor = %s, want (2,146) [frame-left 14 − 12, y 136+10]" % d.slot_cursor_anchor())

	# (2) the list-menu is sent to BACKGROUND (§15.21) while the panel holds focus, and its OWN glove
	# cursor is REMOVED — a single active cursor on screen (the panel's), the old one is gone.
	_expect(menu.is_backgrounded(), "list-menu did not background (§15.21) when focus left it")
	_expect(not menu.cursor_visible(), "old list-menu cursor still shown after focus moved to the panel")

	# (3) ↓ cycles through all 5 SLOT_ROWS and wraps; each row re-anchors on the frame's left edge.
	for expected_row in [1, 2, 3, 4, 0]:
		host._input(_action("ui_down"))
		_expect(d.slot_row() == expected_row, "↓ did not advance to row %d (got %d)" % [expected_row, d.slot_row()])
		_expect(d.slot_cursor_anchor() == Vector2(2, 146 + expected_row * 16),
			"row %d anchor = %s, want %s" % [expected_row, d.slot_cursor_anchor(), Vector2(2, 146 + expected_row * 16)])
	# …and ↑ steps back / wraps (from row 0 → row 4).
	host._input(_action("ui_up"))
	_expect(d.slot_row() == 4, "↑ from row 0 did not wrap to row 4 (got %d)" % d.slot_row())
	# While slot-focused the list-menu must NOT consume ↑/↓ (its own cursor stays put on row 0).
	_expect(menu.selected_row() == 0, "backgrounded list-menu cursor moved on slot nav (row %d)" % menu.selected_row())

	# (4) △/× returns focus to the list-menu (un-backgrounds it) and does NOT tear the screen down.
	host._input(_action("ui_cancel"))
	_expect(not d.is_slot_focused(), "△/× did not leave slot focus")
	_expect(not d.slot_cursor_mounted(), "slot glove cursor still mounted after backing out")
	_expect(not menu.is_backgrounded(), "list-menu still backgrounded after focus returned")
	_expect(menu.cursor_visible(), "list-menu cursor not restored when focus returned")
	_expect(host.action_menu() != null and is_instance_valid(host.action_menu()),
		"△/× from slot focus tore the screen down (should return to the list-menu)")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipSlotFocus test")
	else:
		print("[PASS] FormationEquipSlotFocus: ○→panel focus + list-menu blue + slot nav + back")
	get_tree().quit()
