extends Node3D
# test-kind: render
# seeded-break: inverted DetailScene._apply_item_name_bg's bg-ink swap (on -> not on); name columns keep foreground ink when backgrounded, so the re-ink asserts red
## §15.21 coverage for the per-slot ITEM/ABILITY NAME columns — headful integration guard.
##
## When the lower Status/Eqp/Ability panel is sent to background (the list-menu takes focus, or the
## picker opens over it), the WHOLE subtree recolours to its deactivated blue-grey CLUTs. The frame,
## bands, tabs, category icons and stats text already do (they ride _lower_mats / _stats_text_mats).
## But the per-slot name columns live in their OWN mat lists (_equip_item_mats / _ability_item_mats,
## split out for their box-open clip), and NOTHING re-inked them — so the item/ability NAMES stayed
## tan while everything around them went blue. They use the same 3-ink formation_font_opaque shader
## as the list-menu rows, so the fix is the same ink-twin swap the rows already do.
##
## This proves the names re-ink to the §15.21 bg twins on BOTH backgrounding entry points
## (set_slot_panel_backgrounded — picker open; set_backgrounded — start-menu focus), survive a
## rebuild-while-backgrounded (a selection/commit repaint), and return to foreground on restore.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new(); e.action = name; e.pressed = true; return e


func _v4(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, c.a)


## Assert every name-column glyph mat is at the given ink state (fg twin vs §15.21 bg twin).
func _assert_ink(mats: Array, bg: bool, who: String) -> void:
	var want_light := _v4(StartActionMenu._ROW_INK_BG_LIGHT) if bg else _v4(UIUnitNameplate.INFO_INK_DARK)
	var want_dark := _v4(StartActionMenu._ROW_INK_BG_DARK) if bg else _v4(UIUnitNameplate.INFO_INK_LIGHT)
	_expect(mats.size() > 0, "%s: expected name glyphs to be mounted" % who)
	for m in mats:
		_expect(m.get_shader_parameter("palette_light") == want_light,
			"%s: palette_light not %s (got %s)" % [who, "BG" if bg else "FG", m.get_shader_parameter("palette_light")])
		_expect(m.get_shader_parameter("palette_dark") == want_dark,
			"%s: palette_dark not %s (got %s)" % [who, "BG" if bg else "FG", m.get_shader_parameter("palette_dark")])


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"; add_child(host)
	for _i in 4:
		await get_tree().process_frame
	var form = host._formation
	if form == null or form.selected_character() == null:
		_finish(); return
	var sel = form.selected_character()
	sel.progression.current_job_id = "4a"
	sel.progression.sub_job_id = "4b"            # secondary -> "Item"
	sel.progression.equipped_support = 460       # -> "EquipAxe"

	# Drive into the settled Ability sub-screen (names mounted in _ability_item_mats).
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().move_down(); host.action_menu().confirm()   # "Ability"
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	if d == null or not d.ability_only:
		_expect(false, "did not settle into the ability sub-screen")
		_finish(); return

	# Foreground to start.
	_assert_ink(d._ability_item_mats, false, "ability names (initial fg)")

	# (1) Picker-open backgrounding: the names must go blue with the panel.
	d.set_slot_panel_backgrounded(true)
	_assert_ink(d._ability_item_mats, true, "ability names (slot-panel bg)")

	# (2) A rebuild WHILE backgrounded (selection/commit repaint) must preserve the bg ink.
	d.set_stats_view(DetailScene.stats_view_from_character(sel))
	_assert_ink(d._ability_item_mats, true, "ability names (rebuilt while bg)")

	# (3) Restore -> foreground.
	d.set_slot_panel_backgrounded(false)
	_assert_ink(d._ability_item_mats, false, "ability names (restored fg)")

	# (4) The start-menu focus path (set_backgrounded, whole subtree) blues them too.
	d.set_backgrounded(true)
	_assert_ink(d._ability_item_mats, true, "ability names (whole-subtree bg)")
	d.set_backgrounded(false)
	_assert_ink(d._ability_item_mats, false, "ability names (whole-subtree restore)")

	# --- The EQUIP name column rides the SAME fix (different panel) — prove it on a fresh host. ---
	await _check_equip_names()

	_finish()


## The equip sub-screen's per-slot ITEM name column must blue on picker-open backgrounding too — the
## same _apply_item_name_bg fix, guarding the _equip_item_mats path against a separate regression.
func _check_equip_names() -> void:
	var host2: FormationDetailTransition = FormationDetailTransition.new()
	host2.name = "Host2"; add_child(host2)
	for _i in 4:
		await get_tree().process_frame
	var form2 = host2._formation
	if form2 == null or form2.selected_character() == null:
		return
	form2.selected_character().progression.equipment[UnitProgression.EquipSlot.RIGHT_HAND] = 19  # Broad Sword
	form2._unhandled_input(_action("ui_accept"))
	var d2 = host2.detail_overlay()
	host2.open_action_menu()
	host2.action_menu().confirm()                         # "Item" -> the Equip slide begins
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host2.equip_step()
	if d2 == null or not d2.equip_only:
		_expect(false, "did not settle into the equip sub-screen")
		return
	_assert_ink(d2._equip_item_mats, false, "equip names (initial fg)")
	d2.set_slot_panel_backgrounded(true)
	_assert_ink(d2._equip_item_mats, true, "equip names (slot-panel bg)")
	d2.set_slot_panel_backgrounded(false)
	_assert_ink(d2._equip_item_mats, false, "equip names (restored fg)")


func _finish() -> void:
	if _failed:
		print("[FAIL] DetailItemNameBackgroundTest")
	else:
		print("[PASS] DetailItemNameBackgroundTest: name columns re-ink to §15.21 bg twins on both bg paths + survive rebuild")
	get_tree().quit()
