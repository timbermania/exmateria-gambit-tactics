extends Node3D
# test-kind: logic
# seeded-break: commented out the vitals refresh (the set_unit_view line) in FormationDetailTransition._remove_focused_slot so the preview re-gate re-applies the STALE build-time `_current`; the 'vitals gauge shows the reduced live HP' assert reds (gauge keeps the with-helmet HP), while the seed/unequip drive + preview-gate-off asserts stay green

## Regression guard (diagnosing-bugs), REMOVE side of FormationEquipVitalsRefreshTest: removing HP/MP
## gear must drop the vitals HP/MP numerator to the live (reduced) value, not leave the stale
## build-time HP. _remove_focused_slot repaints the stats band via set_stats_view but originally never
## refreshed the vitals; the now-empty slot re-gates the preview OFF via set_vitals_preview(false),
## which re-applies the STALE `_current` (still holding the removed item's HP). Mirrors
## FormationEquipRemoveTest's proven seed-then-Remove drive, but seeds an HP helmet in HEAD.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const HP_HELMET := 154   # Crystal Helmet: hp_bonus +120.

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


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
		_finish(); return
	var sel = form.selected_character()

	# Seed the HP helmet into HEAD BEFORE the screen builds (mirrors FormationEquipRemoveTest's seed), so
	# the build-time vitals view already includes its +120 HP and removing it is an observable drop.
	sel.progression.equipment[UnitProgression.EquipSlot.HEAD] = HP_HELMET
	var hp_with: int = sel.progression.get_effective_hp()

	# Drive to the settled Item→Equip screen, then choose "Remove" (row 2).
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_finish(); return

	# The vitals gauge starts on the WITH-helmet HP (build-time bind).
	_expect(int(d.rendered_vitals_hp_mp().get("hp", -1)) == hp_with,
		"precondition: vitals gauge not bound to the seeded (with-helmet) HP")

	menu.move_down(); menu.move_down()
	_expect(menu.selected_row() == 2, "list-menu not on the 'Remove' row (got %d)" % menu.selected_row())
	menu.confirm()                                     # §15.31: ○ on "Remove" → remove-mode slot focus
	_expect(d.is_slot_focused(), "'Remove' did not hand focus into the Eqp slot panel (§15.31)")

	# Navigate the glove to HEAD (row 2, the seeded slot).
	host._input(_action("ui_down"))
	host._input(_action("ui_down"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.HEAD, "slot cursor not on the seeded HEAD slot")
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == HP_HELMET,
		"precondition: HEAD should hold the seeded helmet")

	# --- ACT: ○ on the filled HEAD slot removes the helmet (§15.31). ---
	host._input(_action("ui_accept"))
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == -1,
		"○ did not unequip the HEAD helmet (still holds %d)"
		% sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD))

	# The now-empty slot re-gates the preview OFF — settle a few frames.
	for i in 60:
		await get_tree().process_frame
		if not d.is_vitals_preview():
			break

	var hp_without: int = sel.progression.get_effective_hp()
	_expect(hp_without < hp_with, "test setup: removing the HP helmet did not lower effective HP")

	# THE ASSERTION: the vitals gauge shows the reduced live HP, not the stale with-helmet value.
	var v_after := d.rendered_vitals_hp_mp()
	_expect(not d.is_vitals_preview(), "still in vitals preview after remove (gauge stuck on dashes)")
	_expect(int(v_after.get("hp", -1)) == hp_without,
		"vitals gauge shows HP=%s but the live unit has %d (vitals not refreshed on remove)"
		% [v_after.get("hp"), hp_without])

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipRemoveVitals test")
	else:
		print("[PASS] FormationEquipRemoveVitals: vitals HP gauge tracks the live unit after a remove")
	get_tree().quit()
