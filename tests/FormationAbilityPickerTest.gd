extends Node3D
# test-kind: logic
# seeded-break: no-opped AbilityLoadout.commit_to_progression in FormationDetailTransition._on_ability_picker_chosen; commits write nothing, so the equipped_support/sub_job_id/name-column asserts red
## The ability PICKER "Set" flow (ABILITY_PICKER.md) — headful integration guard, the
## ability mirror of FormationEquipPickerTest. From the settled Ability sub-screen, choosing
## "Set" hands focus into the ability panel (§15.25-style slot focus, skipping the job-fixed
## primary), and ○ on an editable slot opens the ability picker for that slot's class:
##   (1) the picker opens with the FULL catalog for the FOCUSED slot (ADR-0197 scaffold:
##       AbilityCandidates.build_catalog — a unit-independent, >5-row scrolling list, NOT the
##       near-empty learned/unlocked set), which CONTAINS the seeded ids we then drive to;
##   (2) rows are TEXT-ONLY (no per-row type glyph — the RE correction vs the equip picker);
##   (3) ○ COMMITS the pick back to the unit's UnitProgression (equipped_support/…);
##   (4) △/× closes the picker back to slot focus.

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

	# Seed the unit as a Squire with cleared R/S/M so commits start from a known state.
	# NB: under ADR-0197 the catalog is unit-independent, so learned_abilities no longer
	# gates candidates (the full Support set contains 460 regardless) — kept only to pin the
	# ids this test drives to, and to document that seeding is now inert to the picker.
	sel.progression.current_job_id = "4a"
	sel.progression.learned_abilities = {436: true, 460: true, 486: true}
	sel.progression.equipped_reaction = -1
	sel.progression.equipped_support = -1
	sel.progression.equipped_movement = -1

	# Open detail → action menu → choose "Ability" (row 1) → the Ability slide.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○ did not open the detail overlay")
	host.open_action_menu()
	host.action_menu().move_down()          # row 0 (Item) -> row 1 (Ability)
	host.action_menu().confirm()            # "Ability" -> the Ability slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_finish()
		return
	_expect(d.ability_only, "did not settle into the ability sub-screen")

	# "Set" (row 0) hands focus into the ability panel; focus starts on the secondary row (1).
	menu.confirm()
	_expect(d.is_slot_focused(), "\"Set\" did not enter ability slot focus")
	_expect(d.slot_row() == 1, "ability focus should start on secondary(1), got %d" % d.slot_row())

	# --- Secondary slot (row 1, where focus starts): ○ opens the SUB-JOB picker. ---
	# ADR-0197: the picker shows the FULL catalog — every job by its skillset name, name-sorted
	# (a >5-row scrolling list), NOT the unit's unlocked sub-jobs. It CONTAINS Chemist (job 0x4b,
	# shown as "Item"); drive the cursor to that row via the real input path and commit → sub_job_id.
	host._input(_action("ui_accept"))
	var sp = host.ability_picker()
	_expect(sp != null and is_instance_valid(sp), "○ on the secondary slot did not open the picker")
	if sp != null:
		_expect(sp.row_count() > 5,
			"secondary catalog should be a >5-row scrolling list, got %d" % sp.row_count())
		_expect(not _find_by_id(sp, 0x4b).is_empty() and String(_find_by_id(sp, 0x4b).get("name")) == "Item",
			"secondary catalog must offer Chemist (0x4b) as 'Item'")
		_expect(_drive_to_id(host, sp, 0x4b), "could not reach the Chemist (0x4b) row in the secondary catalog")
		host._input(_action("ui_accept"))       # commit the Chemist row -> sub_job_id
		_expect(sel.progression.sub_job_id == "4b",
			"secondary commit did not set sub_job_id='4b' (got '%s')" % sel.progression.sub_job_id)
		_expect(d.is_slot_focused(), "secondary commit should return to slot focus")
		# Task 1: the commit REPAINTS the ability NAME column (not just the progression field). The
		# secondary slot (index 1) now resolves the Chemist sub-job's skillset name "Item", and the
		# name column actually mounts glyphs (count >= 1 — the primary skillset also renders).
		var names := d.ability_slot_names()
		_expect(names.size() >= 2 and String(names[1]) == "Item",
			"secondary slot name should read 'Item' after commit, got %s" % [names])
		_expect(d.ability_item_name_count() >= 1,
			"the ability name column should mount at least one name after commit, got %d" % d.ability_item_name_count())

	# Walk down to the Support slot (row 3) via the real input path.
	host._input(_action("ui_down"))         # 1 -> 2 (reaction)
	host._input(_action("ui_down"))         # 2 -> 3 (support)
	_expect(d.slot_row() == 3, "did not reach the support slot, got %d" % d.slot_row())

	# --- ACT: ○ on the support slot opens the ability picker. ---
	host._input(_action("ui_accept"))
	var p = host.ability_picker()
	_expect(p != null and is_instance_valid(p), "○ on the ability slot did not open the ability picker")
	if p == null:
		_finish()
		return
	# (1) candidates = the FULL Support catalog (a >5-row scrolling list), which CONTAINS Equip Axe (460).
	_expect(p.row_count() > 5, "support catalog should be a >5-row scrolling list, got %d" % p.row_count())
	_expect(not _find_by_id(p, 460).is_empty(), "support catalog must contain 460 (Equip Axe)")
	# (2) rows are text-only (the RE correction).
	_expect(p.row_decoration_materials().is_empty(), "ability picker rows must be text-only")
	_expect(p.visible_row_names().size() >= 1, "picker did not render any candidate name")

	# (3) ○ COMMITS the picked row (Equip Axe 460) to the unit's persistent progression.
	_expect(_drive_to_id(host, p, 460), "could not reach the Equip Axe (460) row in the support catalog")
	host._input(_action("ui_accept"))
	_expect(sel.progression.equipped_support == 460,
		"commit did not write equipped_support=460 (got %d)" % sel.progression.equipped_support)
	# Task 1: the support slot (index 3) now shows the committed ability's name in the panel.
	var abl_names := d.ability_slot_names()
	_expect(abl_names.size() > 3 and String(abl_names[3]) == "EquipAxe",
		"support slot name should read 'EquipAxe' after commit, got %s" % [abl_names])
	_expect(host.ability_picker() == null or not is_instance_valid(host.ability_picker()),
		"picker should close after the commit")
	# (4) back to slot focus (not a whole-screen unwind).
	_expect(d.is_slot_focused(), "commit should return to ability slot focus")

	_finish()


## Drive an open ability picker's cursor to the row whose id == target via the REAL input
## path (ui_down → host → picker.move_down), so the subsequent ○ commits that specific row.
## Returns false if the id isn't in the catalog.
func _drive_to_id(host, picker, target: int) -> bool:
	for _i in picker.row_count() + 1:
		if int(picker.entries[picker.selected_row()].get("id", -1)) == target:
			return true
		host._input(_action("ui_down"))
	return false


func _find_by_id(picker, target: int) -> Dictionary:
	for e in picker.entries:
		if int(e.get("id", -1)) == target:
			return e
	return {}


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationAbilityPickerTest")
	else:
		print("[PASS] FormationAbilityPickerTest: Set -> slot focus -> ○ picker -> commit -> close")
	get_tree().quit()
