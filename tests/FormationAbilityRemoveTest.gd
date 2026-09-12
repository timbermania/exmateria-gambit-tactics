extends Node3D
# test-kind: logic
# seeded-break: early-returned FormationDetailTransition._remove_focused_ability_slot before AbilityLoadout.clear_in_progression; removes do nothing, so the sub_job_id/equipped_support/name-blank asserts red

## The ability REMOVE row (ability sub-menu ROWS_ABILITY row 1) — headful integration guard, the
## ability mirror of FormationEquipRemoveTest. "Remove" is the ability "Set" slot-focus flow with
## "equip nothing" swapped in for the picker: choosing "Remove" hands the glove into the ability slot
## panel exactly as "Set" (row 0) does, but arms an ability-remove sub-mode so ○ on a focused slot
## CLEARS it (AbilityLoadout.clear_in_progression) instead of opening the picker.
##
## This proves the settled behavior:
##   (1) row 1 "Remove" enters ability slot focus (live glove, list-menu backgrounded), starting on the
##       secondary row (1) — like "Set", not a picker (the job-fixed primary is skipped);
##   (2) ○ on a FILLED slot clears it — the persistent field returns to none (sub_job_id "" / equipped_*
##       -1) and the ability NAME column drops that slot's name to blank;
##   (3) it STAYS in remove slot focus afterward (remove more), no whole-screen teardown;
##   (4) ○ on an already-empty slot is a silent no-op (still focused, no crash).
## Abilities have NO numeric/stat preview, so there is no compare panel to gate (unlike equip Remove).

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


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

	# Seed a Squire with two OCCUPIED ability slots so removing them is observable: a secondary sub-job
	# (Chemist 0x4b -> skillset "Item", slot 1) and a support ability (Equip Axe 460 -> "EquipAxe", slot 3).
	sel.progression.current_job_id = "4a"
	sel.progression.learned_abilities = {460: true}
	sel.progression.sub_job_id = "4b"                 # secondary occupied -> "Item"
	sel.progression.equipped_support = 460            # support occupied -> "EquipAxe"
	sel.progression.equipped_reaction = -1
	sel.progression.equipped_movement = -1

	# Open detail → action menu → "Ability" (row 1) → the Ability slide settles.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○ did not open the detail overlay")
	host.open_action_menu()
	host.action_menu().move_down()                    # row 0 (Item) -> row 1 (Ability)
	host.action_menu().confirm()                      # "Ability" -> the Ability slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_finish()
		return
	_expect(d.ability_only, "did not settle into the ability sub-screen")

	# (1) Navigate the list-menu to "Remove" (ROWS_ABILITY row 1 = ["Set","Remove","Learn"]) and ○.
	menu.move_down()
	_expect(menu.selected_row() == 1, "list-menu not on the 'Remove' row (got %d)" % menu.selected_row())
	menu.confirm()                                    # ○ on "Remove" → remove-mode ability slot focus
	_expect(d.is_slot_focused(), "'Remove' did not hand focus into the ability slot panel")
	_expect(d.slot_row() == 1, "remove-mode did not seed the glove on secondary(1), got %d" % d.slot_row())

	# Precondition: the two seeded slots resolve their names in the ability NAME column.
	var names0 := d.ability_slot_names()
	_expect(names0.size() >= 4 and String(names0[1]) == "Item",
		"precondition: secondary slot should read 'Item', got %s" % [names0])
	_expect(String(names0[3]) == "EquipAxe",
		"precondition: support slot should read 'EquipAxe', got %s" % [names0])

	# --- ACT 1: ○ on the FILLED secondary slot (row 1, where focus starts) clears it. ---
	host._input(_action("ui_accept"))
	_expect(sel.progression.sub_job_id == "",
		"○ did not clear the secondary sub-job (still '%s')" % sel.progression.sub_job_id)
	_expect(d.is_slot_focused(), "clearing a slot left slot focus (should stay in remove mode)")
	_expect(host.action_menu() != null and is_instance_valid(host.action_menu()),
		"clearing a slot tore the screen down (should stay in remove slot focus)")
	var names1 := d.ability_slot_names()
	_expect(names1.size() >= 4 and String(names1[1]) == "",
		"the secondary slot name did not go blank after remove, got %s" % [names1])

	# --- ACT 2: walk to the support slot (row 3) and ○ to clear it. ---
	host._input(_action("ui_down"))                   # 1 -> 2 (reaction)
	host._input(_action("ui_down"))                   # 2 -> 3 (support)
	_expect(d.slot_row() == 3, "did not reach the support slot, got %d" % d.slot_row())
	var before_names := d.ability_item_name_count()
	host._input(_action("ui_accept"))
	_expect(sel.progression.equipped_support == -1,
		"○ did not clear equipped_support (still %d)" % sel.progression.equipped_support)
	var names2 := d.ability_slot_names()
	_expect(String(names2[3]) == "",
		"the support slot name did not go blank after remove, got %s" % [names2])
	_expect(d.is_slot_focused(), "clearing the support slot left slot focus")

	# The NAME column actually dropped a mounted glyph-set (repaint is synchronous; a few frames to settle).
	for _i in 8:
		await get_tree().process_frame
	_expect(d.ability_item_name_count() < before_names or before_names == 0,
		"the ability name column did not drop the removed slot's name (names %d, was %d)"
		% [d.ability_item_name_count(), before_names])

	# --- ACT 3: ○ on the now-EMPTY support slot is a silent no-op (still focused, no crash). ---
	host._input(_action("ui_accept"))
	_expect(sel.progression.equipped_support == -1, "no-op ○ on an empty slot changed the field")
	_expect(d.is_slot_focused(), "no-op ○ on an empty slot dropped slot focus")

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationAbilityRemoveTest")
	else:
		print("[PASS] FormationAbilityRemoveTest: 'Remove'→ability slot focus + ○ clears slot (name blanks) + stays focused + empty no-op")
	get_tree().quit()
