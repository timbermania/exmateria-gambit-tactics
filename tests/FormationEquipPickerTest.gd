extends Node3D
# test-kind: logic
# seeded-break: disabled FormationDetailTransition._push_equip_delta_for_row (if true: return after its null guard) so no preview−base delta is ever pushed; the DEFECT-#8 two-panel + vitals/stats-preview + compare-element box-open/close asserts red (§5 + §7b), while the picker rows/ITEM.BIN keys + cream header + cursor hand-off + selective blue + nav + close/restore asserts stay green

## The equipment PICKER sub-state (FORMATION_SCREEN.md §15.26, RE round 35) — headful integration guard.
## From the settled Item→Equip screen with the glove FOCUSED on an Eqp slot row (§15.25), pressing ○
## opens the equipment picker one level deeper. This proves the round-35 MECHANISM (round-34 reused a
## look-alike widget + a single stats panel + dark FONT header; all corrected here):
##   (1) the picker item-list window mounts with 5-column rows carrying the ITEM.BIN `graphic` + `type`
##       bytes the icon/CLUT are keyed on (icon = ITEM.BIN via icon_uv_for, NOT a look-alike sprite);
##   (2) the "Eqp."/"ALL" header renders through the CREAM CLUT-swap mechanism (0x7cbc family), NOT the
##       dark FONT.BIN ramp (defect #5);
##   (3) the active glove cursor hands INTO the picker, anchored on its frame's LEFT edge at row 0;
##   (4) the Eqp SLOT panel goes to BACKGROUND (blue, §15.21) while the stats band stays TAN in preview
##       mode — the backgrounding is SELECTIVE, not the whole detail subtree;
##   (5) the stats band flips to TWO overlapping panels (DEFECT #8: base + delta ~2px up-left, both in
##       dash preview) and the vitals HP/MP numerator → "-";
##   (6) the §15.25 list-menu stays backgrounded and its slot glove is removed (one active cursor);
##   (7) ↑/↓ move among items; and △/× closes the picker back to §15.25 slot focus, restoring
##       everything (previews off → one stats panel, slot panel tan, slot glove back) WITHOUT teardown.
## The equip COMMIT (the NEXT ○, world_equip_commit 0x80124428) is now wired — the legal path is
## FormationEquipCommitTest; here we assert a slot-illegal pick (a shield onto the Right Hand) no-ops.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const EquipCandidates = ExMateriaAlmanac.EquipCandidates
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")

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

	# Drive to the settled Item→Equip screen, then hand focus into the Eqp slot panel (§15.25).
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○-press did not open the detail overlay")
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
	_expect(menu.is_backgrounded(), "list-menu not backgrounded at slot focus")
	_expect(d.stats_panel_count() == 1, "detail should show ONE stats panel before the picker opens")

	# (round 49) seed a live equip on the selected unit so the data-built rows can prove the
	# equipped-across-roster count flows from the ROSTER (the catalog-template roster ships bare).
	var sel = form.selected_character()
	if sel != null and sel.progression != null:
		sel.progression.equipment[UnitProgression.EquipSlot.RIGHT_HAND] = 19  # Broad Sword

	# --- ACT: ○ on the slot row opens the equipment picker (§15.26). ---
	host._input(_action("ui_accept"))
	var p = host.equip_picker()

	# (1) the picker exists; rows carry name + counts AND the ITEM.BIN icon keys (graphic + type).
	_expect(p != null and is_instance_valid(p), "○ on the slot row did not open the equipment picker")
	if p == null:
		_finish()
		return
	_expect(p.row_count() >= 1, "picker opened with no item rows")
	var e0: Dictionary = p.entries[0] if not p.entries.is_empty() else {}
	_expect(e0.has("name") and e0.has("equipped") and e0.has("owned"),
		"picker rows lack the name + equipped/owned columns")
	_expect(e0.has("graphic") and e0.has("palette"),
		"picker rows lack the ITEM.BIN `graphic`/`palette` bytes (icon = look-alike, not ITEM.BIN — defect)")
	# The icon column uses the WORLD-literal ITEM.BIN formula (geometry, not a look-alike).
	_expect(EquipPickerMenu.icon_uv_for(12) == Rect2(192, 32, 16, 16),
		"icon_uv_for is not the ITEM.BIN graphic-byte formula")
	_expect(p.body_materials().size() > 0, "picker built no body materials (frame/header/rows)")

	# (round 49) the rows are BUILT FROM ITEM DATA for the FOCUSED slot — the full slot-legal
	# catalog (EquipCandidates over items.json; hardcoded defaults are dead). Slot row 0 = R.Hand:
	# every weapon + shield, descending id, with live roster counts on the equipped item.
	var want: Array = EquipCandidates.build_catalog(
		UnitProgression.EquipSlot.RIGHT_HAND, CharacterCatalog.owned_units())
	_expect(want.size() > 100, "R.Hand catalog unexpectedly small (%d) — items.json missing?" % want.size())
	_expect(p.row_count() == want.size(),
		"picker rows %d != the R.Hand slot catalog %d (rows not data-built)" % [p.row_count(), want.size()])
	if not p.entries.is_empty() and not want.is_empty():
		_expect(int(p.entries[0]["id"]) == int(want[0]["id"]),
			"picker top row id %s != catalog top %s (descending-id order)" % [p.entries[0]["id"], want[0]["id"]])
	var bs_row := {}
	for e in p.entries:
		if int(e.get("id", -1)) == 19:
			bs_row = e
	_expect(not bs_row.is_empty() and int(bs_row.get("equipped", 0)) >= 1,
		"the equipped Broad Sword row must carry a live equipped count, got %s" % [bs_row])

	# (2) the "Eqp."/"ALL" header is BAKED RANGETILE word cells through the cream active-label CLUT
	#     0x7CBC — the SAME sheet + mechanism as the §15.19 window tabs — NOT FONT.BIN glyphs (defect #5).
	_expect(EquipPickerMenu.HEADER_EQP_CELL == "Eqp" and EquipPickerMenu.HEADER_ALL_CELL == "ALL",
		"picker header cell names are not the window-tab 'Eqp'/'ALL' cells")
	_expect(p.header_cell_materials().size() == 2,
		"picker header did not mount 2 baked cells (Eqp+ALL), got %d — still FONT?" % p.header_cell_materials().size())
	if p.header_cell_materials().size() == 2:
		var hm: ShaderMaterial = p.header_cell_materials()[0]
		_expect(hm.get_shader_parameter("index_atlas") != null,
			"header cell has no RANGETILE index_atlas — not the baked cream MECHANISM")

	# (3) the active cursor is in the picker, anchored on its frame LEFT edge at row 0 = (64,148)
	# (y = ROWS_CONTAINER 138 + 10; re-measured 2026-08-11 vs the live picker quicksave — the
	# fb4-era 146 sat the glove 2px high in the window).
	_expect(p.selected_row() == 0, "picker cursor not seeded on row 0 (got %d)" % p.selected_row())
	_expect(EquipPickerMenu.cursor_anchor_for(0) == Vector2(64, 148),
		"picker row0 anchor = %s, want (64,148) [frame-left 76 − 12, y 138+10]" % EquipPickerMenu.cursor_anchor_for(0))
	_expect(p.cursor_materials().size() > 0, "picker glove cursor not mounted")

	# (4) the Eqp SLOT panel backgrounds (blue) while the stats band stays TAN (selective swap).
	_expect(d.lower_panel_backgrounded(), "Eqp slot panel did not background (§15.21) when the picker opened")
	_expect(not d.stats_band_backgrounded(), "stats band went blue — backgrounding should be SELECTIVE (lower only)")

	# (5) DEFECT #8: the stats band becomes TWO overlapping panels (base + delta 2px up-left), both in
	#     dash preview; and the vitals flip to HP/MP-numerator-"-" preview.
	_expect(d.stats_panel_count() == 2,
		"equip-picker did not raise the SECOND stats panel (DEFECT #8), got %d" % d.stats_panel_count())
	# 2px per axis is the §15.26 slot-offset fact; the direction is the pinnable
	# detail.stats_delta_nudge_* dial (ROM adds its panel down-right — §15.26 C2).
	var doff: Vector2 = d.stats_delta_offset()
	_expect(absf(doff.x) == 2.0 and absf(doff.y) == 2.0,
		"delta stats panel offset = %s, want a 2px-per-axis slot offset" % doff)
	_expect(d.is_vitals_preview(), "vitals did not enter preview (HP/MP numerator → '-')")
	_expect(d.is_stats_preview(), "stats band did not enter preview (values → '-')")
	# ADR-0088 amendment §5: the compare panel is a registered element and the
	# ORCHESTRATOR opens it alongside the picker — a box-open reveal, not a pop.
	var comp = d.stats_compare_element()
	_expect(comp != null and is_instance_valid(comp),
		"picker open did not raise the registered compare element")
	_expect(comp != null and not comp.is_settled(),
		"the compare panel must BOX-OPEN with the picker (orchestrated verb), not pop in settled")

	# (6) the §15.25 list-menu stays backgrounded and its slot glove is gone (one active cursor).
	_expect(menu.is_backgrounded(), "list-menu un-backgrounded when the picker opened")
	_expect(not d.slot_cursor_mounted() or not _slot_glove_visible(d),
		"the §15.25 slot glove is still shown — the picker should be the single active cursor")

	# (7a) ↑/↓ move among items (wraps); the slot list underneath does NOT move.
	var n := p.row_count()
	host._input(_action("ui_down"))
	_expect(p.selected_row() == 1 % n, "↓ did not advance the picker (got %d)" % p.selected_row())
	host._input(_action("ui_up"))
	_expect(p.selected_row() == 0, "↑ did not step the picker back to row 0 (got %d)" % p.selected_row())
	# ○ is the equip COMMIT (now wired — FormationEquipCommitTest covers the legal path). Row 0 on the
	# R.Hand catalog is the highest-id hand item = a SHIELD (build_catalog lists weapons OR shields for a
	# hand), which can_equip_item REJECTS for the Right Hand (weapon-only). So this ○ must NO-OP: the
	# slot stays the seeded Broad Sword and the picker holds open (no 0x4000 grey-out layer yet).
	var id0 := int(p.entries[0].get("id", -1))
	_expect(not sel.progression.can_equip_item(UnitProgression.EquipSlot.RIGHT_HAND, id0),
		"test premise: R.Hand row 0 (id %d) should be slot-illegal (a shield), but can_equip_item accepts it" % id0)
	host._input(_action("ui_accept"))
	_expect(host.equip_picker() != null, "○ on a slot-illegal pick should NO-OP and keep the picker open")
	_expect(sel.progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND) == 19,
		"○ on a slot-illegal pick must not change the slot (R.Hand should stay the seeded Broad Sword 19)")

	# (7b) △/× closes the picker back to §15.25 slot focus, restoring everything. The picker NODE
	# lingers to play its box-CLOSE (the §15.17 aperture in reverse) then frees itself; the host's
	# accessor reads "closed" immediately (input routing has already left it).
	host._input(_action("ui_cancel"))
	_expect(host.equip_picker() == null, "△/× did not close the picker")
	# The box-close is the window ELEMENT's reversed beat now (ADR-0088): mid-close the
	# element is unsettled (the old _close_playing flag retired into the engine).
	_expect(is_instance_valid(p) and not p.window().is_settled(),
		"picker should play the box-close on △/× (not vanish instantly)")
	# The compare panel closes ALONGSIDE the picker (orchestrated verbs, amendment §5)
	# and tears down on its `closed` — not an instant set_stats_preview(false) pop.
	_expect(comp != null and is_instance_valid(comp) and not comp.is_settled(),
		"the compare panel must play its box-close with the picker")
	_expect(d.is_stats_preview(),
		"stats preview must persist through the compare close (teardown on `closed`, not instant)")
	# The close accumulates real time in 1/60s ticks (~10 ticks), so wait on the CONDITION, not a
	# frame count (a high-refresh display makes 20 frames < 10 ticks). 240 frames ≈ worst-case 1s+.
	for i in 240:
		await get_tree().process_frame
		if (not is_instance_valid(p) or p.is_queued_for_deletion()) and not d.is_stats_preview():
			break
	_expect(not is_instance_valid(p) or p.is_queued_for_deletion(),
		"picker did not free itself after the box-close finished")
	_expect(d.is_slot_focused(), "△/× left the §15.25 slot focus (should return to it, not unwind)")
	_expect(not d.is_stats_preview() and not d.is_vitals_preview(), "preview modes not cleared on picker close")
	_expect(d.stats_panel_count() == 1, "the second stats panel was not torn down on picker close")
	_expect(not d.lower_panel_backgrounded(), "Eqp slot panel still blue after the picker closed")
	_expect(d.slot_cursor_mounted() and _slot_glove_visible(d), "the §15.25 slot glove did not return on close")
	_expect(host.action_menu() != null and is_instance_valid(host.action_menu()),
		"picker close tore the screen down (should return to §15.25 slot focus)")

	_finish()


## The §15.25 slot glove's visibility (the picker hides it via set_slot_cursor_visible). The glove
## root is DetailScene._slot_cursor_root; we reach it through slot_cursor_mounted() + the node's visible.
func _slot_glove_visible(d) -> bool:
	var root = d.get_node_or_null("SlotGloveCursor")
	# The cursor root is a child of _open_root (not the DetailScene node) — find it by name in the tree.
	if root == null:
		for node in d.find_children("SlotGloveCursor", "", true, false):
			root = node
			break
	return root != null and is_instance_valid(root) and root.visible


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipPicker test")
	else:
		print("[PASS] FormationEquipPicker: ○→picker + ITEM.BIN icon keys + cream header + selective blue + two stats panels + preview + nav + back to slot focus")
	get_tree().quit()
