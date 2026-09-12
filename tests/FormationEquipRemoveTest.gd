extends Node3D
# test-kind: logic
# seeded-break: FormationDetailTransition._remove_focused_slot returns before the unequip call (SEEDED BREAK early-return, so remove-mode accept never reaches UnitProgression.unequip_item); '○ did not unequip R.Hand' + 'Eqp icon column did not drop' + 'Eqp name column did not drop' + 'preview should turn off' RED; the 'Remove'→slot-focus entry, the occupancy-gated dashed compare panel, the filled→filled self-correction, and the stays-in-focus asserts stay green; GREEN unbroken on the reverted tree

## The equip REMOVE row (FORMATION_SCREEN.md §15.31, PORT PRODUCT DECISION) — headful integration
## guard. The mirror of §15.26's equip COMMIT: "Remove" (ROWS_EQUIP row 2) is the §15.25 slot-focus
## flow with "equip nothing" swapped in for the picker. Choosing "Remove" hands the glove into the Eqp
## slot panel exactly as row-0 "Equip" does, but arms a REMOVE sub-mode so ○ on a slot unequips it
## directly (UnitProgression.unequip_item) instead of opening the picker.
##
## This proves the settled §15.31 behavior:
##   (1) row 2 "Remove" enters slot focus (live glove, list-menu backgrounded) — like row 0, not a picker;
##   (2) the DASHED compare panel is gated on slot OCCUPANCY, driven by the SLOT cursor (not a picker):
##       present on a filled slot (R.Hand), absent on an empty one (HEAD), re-evaluated on every ↑/↓;
##   (3) ○ on a FILLED slot unequips it — get_equipped_item → -1, and the Eqp column loses BOTH the
##       ITEM.BIN icon AND the FONT name (the inverse of the commit test's before+1), stats drop;
##   (4) it STAYS in remove slot focus afterward (remove more), no whole-screen teardown; the removed
##       slot is now empty so its preview turns off (real reduced stats show).
## Out of scope (§15.31 "Deferred"): numeric before/after stat diffs (dashes both sides); "Best"/"List".

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

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
	if form == null or form.selected_character() == null:
		_finish()
		return
	var sel = form.selected_character()

	# Seed a live R.Hand equip BEFORE the screen builds (the way FormationEquipPickerTest seeds it), so
	# the Eqp column mounts the Broad Sword icon+name and removing it is an observable −1 on both counts.
	# Also seed the ADJACENT L.Hand slot so the self-correction subtest below can move filled→filled (the
	# exact case the old shadow-flag desync got wrong — a move through an empty slot would mask it).
	sel.progression.equipment[UnitProgression.EquipSlot.RIGHT_HAND] = 19  # Broad Sword
	sel.progression.equipment[UnitProgression.EquipSlot.LEFT_HAND] = 19   # display-only 2nd filled slot

	# Drive to the settled Item→Equip screen, then choose "Remove" (row 2) instead of "Equip" (row 0).
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()                      # choose "Item" → the Equip slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_finish()
		return

	# §15.31: navigate the list-menu to "Remove" (ROWS_EQUIP row 2 = ["Equip","Best","Remove","List"]) and ○.
	menu.move_down()
	menu.move_down()
	_expect(menu.selected_row() == 2, "list-menu not on the 'Remove' row (got %d)" % menu.selected_row())
	menu.confirm()                                    # §15.31: ○ on "Remove" → remove-mode slot focus
	_expect(d.is_slot_focused(), "'Remove' did not hand focus into the Eqp slot panel (§15.31)")

	# The glove seeds on slot row 0 = R.Hand (filled, seeded above).
	_expect(d.slot_row() == UnitProgression.EquipSlot.RIGHT_HAND,
		"remove-mode did not seed the glove on R.Hand (row %d)" % d.slot_row())
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND) == 19,
		"precondition: R.Hand should hold the seeded Broad Sword, got %d"
		% sel.progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND))

	# (2) The dashed compare panel is PRESENT on the filled slot (occupancy-gated preview).
	_expect(d.stats_panel_count() == 2,
		"remove-mode did not raise the dashed compare panel on the FILLED R.Hand slot (§15.31)")
	_expect(d.is_stats_preview(), "stats band did not enter dash preview on the filled slot")

	# ...and ABSENT on an empty slot. Navigate down to HEAD (row 2, empty on the bare roster).
	host._input(_action("ui_down"))
	host._input(_action("ui_down"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.HEAD,
		"slot cursor not on the empty HEAD slot (row %d)" % d.slot_row())
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == -1,
		"precondition: HEAD slot should be empty on the bare roster")
	_expect(d.stats_panel_count() == 1,
		"compare panel did not HIDE on the empty HEAD slot (occupancy gate, §15.31)")
	_expect(not d.is_stats_preview(), "stats stayed in dash preview on the empty slot")

	# ...and returns when the cursor lands back on the filled R.Hand slot (empty→filled reveal replays).
	host._input(_action("ui_up"))
	host._input(_action("ui_up"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.RIGHT_HAND,
		"slot cursor did not return to R.Hand (row %d)" % d.slot_row())
	_expect(d.stats_panel_count() == 2, "compare panel did not return on the re-filled R.Hand slot")

	# SELF-CORRECTION (regression guard): the preview gate must reconcile against the DetailScene's ACTUAL
	# state, not a private shadow flag. The §15.26 picker also writes set_stats_preview (and tears the
	# compare down on a DEFERRED box-close), so a shadow flag drifts and then SUPPRESSES the diff on a
	# filled slot. Simulate that out-of-band teardown here, then move the cursor: remove-mode must bring
	# the diff back. (With the old shadow flag this stayed collapsed — the reported "no diff" bug.)
	d.set_stats_preview(false)   # out-of-band desync, as the picker's deferred close would do
	_expect(d.stats_panel_count() == 1, "test setup: forced preview-off did not collapse the compare panel")
	# Move filled(R.Hand)→filled(L.Hand) WITHOUT passing through an empty slot. A shadow flag that still
	# reads "showing" here would early-return and leave the diff collapsed; reading the real state re-opens it.
	host._input(_action("ui_down"))   # → L.Hand (also filled)
	_expect(d.slot_row() == UnitProgression.EquipSlot.LEFT_HAND,
		"self-correction setup: cursor not on the adjacent filled L.Hand (row %d)" % d.slot_row())
	_expect(d.stats_panel_count() == 2,
		"remove-mode preview did not self-correct after an out-of-band teardown (shadow-flag desync regressed)")
	_expect(d.is_stats_preview(), "stats preview did not return on the filled slot after desync")
	host._input(_action("ui_up"))     # back to R.Hand for the removal act below
	_expect(d.slot_row() == UnitProgression.EquipSlot.RIGHT_HAND, "did not return the cursor to R.Hand")

	# The Eqp column shows the seeded Broad Sword (icon + name) before we remove it.
	var before_icons := d.equip_item_icon_count()
	var before_names := d.equip_item_name_count()
	_expect(before_icons >= 1, "the seeded R.Hand item did not mount an Eqp icon (got %d)" % before_icons)
	_expect(before_names >= 1, "the seeded R.Hand item did not mount an Eqp name (got %d)" % before_names)

	# --- ACT: ○ on the filled R.Hand slot removes its gear (§15.31). ---
	host._input(_action("ui_accept"))

	# (3) The slot is now empty (unequip_item cleared it).
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND) == -1,
		"○ did not unequip R.Hand (still holds %d)"
		% sel.progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND))

	# (4) It STAYS in remove slot focus (no whole-screen unwind) — the user can remove more.
	_expect(d.is_slot_focused(), "removing a slot left the §15.25 slot focus (should stay in remove mode)")
	_expect(host.action_menu() != null and is_instance_valid(host.action_menu()),
		"remove tore the screen down (should return to slot focus)")

	# (3) The Eqp column dropped BOTH the icon and the name for the now-empty slot — the inverse of the
	# commit test's before+1. The repaint (set_stats_view) is synchronous; a couple frames to settle.
	for _i in 8:
		await get_tree().process_frame
	_expect(d.equip_item_icon_count() == before_icons - 1,
		"Eqp icon column did not drop the removed item (icons %d, was %d)"
		% [d.equip_item_icon_count(), before_icons])
	_expect(d.equip_item_name_count() == before_names - 1,
		"Eqp name column did not drop the removed item (names %d, was %d)"
		% [d.equip_item_name_count(), before_names])

	# The removed slot is empty now → its preview turns off so the base panel shows the real reduced stats.
	_expect(not d.is_stats_preview(),
		"after removing the item the slot is empty — preview should turn off to show real reduced stats")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipRemove test")
	else:
		print("[PASS] FormationEquipRemove: 'Remove'→slot focus + occupancy-gated compare + ○ unequips (icon+name −1) + stays focused")
	get_tree().quit()
