extends Node3D
# test-kind: logic
# seeded-break: zeroed the s_ev line in EquipStatDelta.compute (shield physical-block contribution -> 0) so no S-EV change is ever previewed; the 'preview delta s_ev == physical block' + 'band S-EV column painted +NN' asserts red (dash), the 'shield drives no HP/MP' assert stays green

## Regression guard (user report "picking a shield gives no stats"): cursoring a SHIELD in the L.Hand
## equip picker must preview its S-EV (shield physical-block) change — the full-band-coverage fix. The
## original preview computed only wp/wev/hp/mp, none of which a shield drives, so the compare panel
## showed all dashes. End-to-end over the real transition: the delta the cursor pushes carries s_ev,
## and the base stats band paints "+NN" in the S-EV column. (No HP/MP is correct — shields have none.)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new(); ev.action = name; ev.pressed = true; return ev


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

	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	if host.action_menu() == null or d == null:
		_finish(); return
	host.action_menu().confirm()                       # slot focus
	_expect(d.is_slot_focused(), "did not reach slot focus")

	# Navigate the slot cursor to LEFT_HAND (row 1) — the shield slot.
	host._input(_action("ui_down"))
	_expect(d.slot_row() == UnitProgression.EquipSlot.LEFT_HAND, "slot cursor not on LEFT_HAND")

	# Open the L.Hand picker and cursor to a shield.
	host._input(_action("ui_accept"))
	var p = host.equip_picker()
	_expect(p != null, "L.Hand picker did not open")
	if p == null:
		_finish(); return
	var shield_idx := -1
	for i in p.entries.size():
		if ItemDatabase.is_shield(int(p.entries[i].get("id", -1))):
			shield_idx = i
			break
	_expect(shield_idx >= 0, "no shield offered in the L.Hand catalog (test setup)")
	if shield_idx < 0:
		_finish(); return
	var guard := 0
	while p.selected_row() != shield_idx and guard < 300:
		host._input(_action("ui_down")); guard += 1
	_expect(p.selected_row() == shield_idx, "could not drive cursor to a shield row")
	await get_tree().process_frame

	var shield_id := int(p.entries[shield_idx].get("id", -1))
	var phys := ItemDatabase.get_physical_block(shield_id)
	_expect(phys > 0, "test setup: chosen shield %d has 0 physical block" % shield_id)

	# The delta the cursor pushed carries the S-EV change (was {wp,wev,hp,mp}=all-0 before the fix).
	var pd: Dictionary = d.stats_preview_delta()
	_expect(int(pd.get("s_ev", 0)) == phys,
		"preview delta s_ev=%s but shield physical_block=%d (S-EV not previewed)" % [pd.get("s_ev"), phys])

	# And the base band PAINTED the S-EV column as "+NN" (not a dash).
	var painted: Dictionary = d.stat_delta_preview_strings()
	_expect(painted.get("s_ev") == "+" + str(phys),
		"band S-EV column painted %s, expected '+%d'" % [painted.get("s_ev"), phys])
	# HP/MP genuinely unchanged for a shield — the vitals sink stays dashed (delta 0).
	_expect(int(pd.get("hp", 0)) == 0 and int(pd.get("mp", 0)) == 0,
		"shield must not drive HP/MP, got hp=%s mp=%s" % [pd.get("hp"), pd.get("mp")])

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipShieldPreview test")
	else:
		print("[PASS] FormationEquipShieldPreview: cursoring a shield previews its S-EV (physical block)")
	get_tree().quit()
