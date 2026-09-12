extends Node3D
# test-kind: logic
# seeded-break: commented out the vitals refresh (the set_unit_view line) in _on_equip_picker_chosen so the commit-time refresh of the vitals gauge never happens and the preview un-gate re-applies the STALE build-time `_current`; the 'vitals gauge shows the live HP after commit' assert reds (gauge keeps the empty-slot 31 vs live 151), the drive/precondition + commit + preview-gate-off asserts stay green

## Regression guard (diagnosing-bugs): the VITALS HP/MP cluster must reflect the LIVE unit after an
## equip COMMIT — not revert to the stale build-time view. The commit path repaints the stats band +
## equip icons via set_stats_view, but originally never refreshed the vitals via set_unit_view; on
## picker close set_vitals_preview(false) then re-applied the STALE `_current` view, so equipping HP/MP
## gear showed the +N delta during preview and then snapped the numerator back to the OLD value ("stats
## don't update as I equip/remove"). The stats BAND (Move/Jump/Speed/AT) already updated correctly —
## this is specifically the vitals gauge. Remove-side coverage: FormationEquipRemoveVitalsTest.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const HP_HELMET := 154   # Crystal Helmet: hp_bonus +120 (HEAD armor), an unmistakable HP swing.

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

	# Drive to the settled Item→Equip screen, then hand focus into the Eqp slot panel (§15.25).
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	if host.action_menu() == null or d == null:
		_finish(); return
	host.action_menu().confirm()                       # §15.25 slot focus
	_expect(d.is_slot_focused(), "did not reach slot focus")

	# Navigate the slot cursor to HEAD (row 2) — empty on the bare catalog roster.
	host._input(_action("ui_down"))
	host._input(_action("ui_down"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.HEAD, "slot cursor not on HEAD")
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == -1,
		"precondition: HEAD should start empty")

	var hp_empty: int = sel.progression.get_effective_hp()
	# The vitals gauge starts on the un-equipped HP (sanity: the build-time view is bound).
	_expect(int(d.rendered_vitals_hp_mp().get("hp", -1)) == hp_empty,
		"precondition: vitals gauge not bound to the empty-slot HP")

	# --- Open the HEAD picker, drive to the HP helmet, commit. ---
	host._input(_action("ui_accept"))
	var p = host.equip_picker()
	_expect(p != null, "HEAD picker did not open")
	if p == null:
		_finish(); return
	var target := -1
	for i in p.entries.size():
		if int(p.entries[i].get("id", -1)) == HP_HELMET:
			target = i
			break
	_expect(target >= 0, "HP helmet %d not offered in the HEAD catalog (test setup)" % HP_HELMET)
	if target < 0:
		_finish(); return
	var guard := 0
	while p.selected_row() != target and guard < 400:
		host._input(_action("ui_down"))
		guard += 1
	_expect(p.selected_row() == target, "could not drive cursor to the HP helmet row")

	host._input(_action("ui_accept"))                  # commit
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.HEAD) == HP_HELMET,
		"commit did not equip the HP helmet")

	# Wait for the picker close + deferred un-preview to settle.
	for i in 300:
		await get_tree().process_frame
		if host.equip_picker() == null and not d.is_vitals_preview():
			break

	var hp_equipped: int = sel.progression.get_effective_hp()
	_expect(hp_equipped > hp_empty, "test setup: equipping the HP helmet did not raise effective HP")

	# THE ASSERTION: the vitals gauge shows the LIVE HP, not the stale build-time value.
	var v_after := d.rendered_vitals_hp_mp()
	_expect(not d.is_vitals_preview(), "still in vitals preview after commit+close (gauge stuck on dashes)")
	_expect(int(v_after.get("hp", -1)) == hp_equipped,
		"vitals gauge shows HP=%s but the live unit has %d (vitals not refreshed on equip commit)"
		% [v_after.get("hp"), hp_equipped])

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipVitalsRefresh test")
	else:
		print("[PASS] FormationEquipVitalsRefresh: vitals HP gauge tracks the live unit after an equip commit")
	get_tree().quit()
