extends Node3D
# test-kind: logic
# seeded-break: made _on_equip_picker_chosen early-return for every pick (if true or not equip_item(...)); the 'item equipped into HEAD / picker closed / icon column repainted' asserts red, the picker-open + slot-cursor + screen-stays-up asserts stay green

## The equip COMMIT (FORMATION_SCREEN.md §15.26, the NEXT ○ past the picker) — headful
## integration guard. From the §15.26 picker open over a focused Eqp slot, pressing ○ on a
## row commits the pick to the REAL equip mechanic (UnitProgression.equip_item), repaints
## the Eqp panel's equipped-item icon column + the stats band from the live progression, and
## closes the picker back to §15.25 slot focus. First cut (user-confirmed): set the slot
## (overwrite; no stock ledger / return-to-pool). An illegal pick (slot-mismatched item)
## NO-OPs and holds the picker open — covered in FormationEquipPickerTest.
##
##   LEGAL path here uses the HEAD slot: build_catalog(HEAD) is head armor only, so every row
##   passes can_equip_item(HEAD) — no weapon/shield split to navigate. The slot ships empty on
##   the bare catalog roster, so a successful equip adds exactly one icon to the column.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const EquipCandidates = ExMateriaAlmanac.EquipCandidates
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

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

	# Drive to the settled Item→Equip screen, then hand focus into the Eqp slot panel (§15.25).
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
	menu.confirm()                                    # §15.25: ○ on "Equip" → slot focus
	_expect(d.is_slot_focused(), "did not reach §15.25 slot focus")

	# Navigate the slot cursor from R.Hand (row 0) down to HEAD (row 2).
	host._input(_action("ui_down"))
	host._input(_action("ui_down"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.HEAD,
		"slot cursor not on HEAD (row %d)" % d.slot_row())

	# The HEAD slot ships empty on the bare catalog roster.
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == -1,
		"precondition: HEAD slot should start empty, got %d"
		% sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD))

	# ○ opens the picker for the HEAD catalog.
	host._input(_action("ui_accept"))
	var p = host.equip_picker()
	_expect(p != null and is_instance_valid(p), "○ on the HEAD slot did not open the picker")
	if p == null:
		_finish()
		return
	_expect(p.row_count() >= 1, "HEAD picker opened with no rows")
	var before_icons := d.equip_item_icon_count()
	var chosen_id := int(p.entries[p.selected_row()].get("id", -1))
	_expect(EquipCandidates.legal_for_slot(UnitProgression.EquipSlot.HEAD, chosen_id),
		"chosen HEAD row id %d is not slot-legal (test setup)" % chosen_id)

	# --- ACT: ○ commits the pick to the real equip mechanic. ---
	host._input(_action("ui_accept"))

	# The item is now equipped in the HEAD slot (set-slot first cut).
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == chosen_id,
		"○ did not equip id %d into HEAD (got %d)"
		% [chosen_id, sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD)])

	# The picker closes back to §15.25 slot focus (not a whole-screen unwind).
	_expect(host.equip_picker() == null, "commit did not close the picker")
	_expect(d.is_slot_focused(), "commit left the §15.25 slot focus (should return to it)")
	_expect(host.action_menu() != null and is_instance_valid(host.action_menu()),
		"commit tore the screen down (should return to slot focus)")

	# The Eqp column repainted the newly equipped item — the empty HEAD slot gained an icon.
	# Wait for the picker box-close to finish (the deferred un-preview repaints the stats text).
	for i in 240:
		await get_tree().process_frame
		if not d.is_stats_preview():
			break
	_expect(d.equip_item_icon_count() == before_icons + 1,
		"Eqp icon column did not repaint the new item (icons %d, was %d)"
		% [d.equip_item_icon_count(), before_icons])

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipCommit test")
	else:
		print("[PASS] FormationEquipCommit: ○ → equip_item(slot,id) + Eqp column repaint + close to slot focus")
	get_tree().quit()
