extends Node3D
# test-kind: logic
# seeded-break: disabled _push_equip_delta_for_row (if true: return after its null guard) so no preview−base delta is ever pushed; the initial-delta + cursor-recompute + glyph-count asserts red, the picker-open + slot-cursor navigation asserts stay green
## Equip stat-DELTA WIRING (EQUIP_STAT_PREVIEW.md) — headful integration guard. Proves the picker
## cursor drives the numeric compare panel end-to-end: opening the picker and moving the cursor make
## the transition compute `preview − base` for the item now under the cursor and push it into the
## shared compare panel (stats band + vitals numerators). Closes §15.31's "dashes both sides".
##
## Seam: FormationDetailTransition wires EquipPickerMenu.selection_changed → EquipStatDelta.compute →
## DetailScene.set_stats_preview_delta / set_vitals_preview_delta. The guard reads back the pushed
## delta (DetailScene.stats_preview_delta()) and the coloured-glyph counts.
##
## Expected values are the oracle savestates / items.json constants:
##   R.Hand empty, cursor Broad Sword (19) → wp +4 / wev +5  (blue).
##   R.Hand empty, cursor Dagger (1)       → wp +3 / wev +5.
##   Body empty,  cursor Clothes (186)     → hp +5 on the vitals numerator (blue).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const EquipStatDelta = ExMateriaAlmanac.EquipStatDelta
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. It sits at the top of
	# `_ready` rather than beside a `.new()` because a file can hold more than one host
	# factory, and whichever runs FIRST must already find a roster. Its sibling
	# `FormationEquipRemoveTest` carries the same two lines for the same reason.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	if form == null or form.selected_character() == null:
		_expect(false, "no formation/selection")
		_finish(); return

	# ESTABLISH the premise instead of assuming it. "R.Hand empty / Body empty" is NOT ambient:
	# `assets/roster/roster.json` is a gitignored, locally-regenerated fixture and it currently
	# seeds unit 0 with `weapon_id: 19` — a Broad Sword (wp 4 / wev 5). Every expectation below is
	# an item's FULL contribution, so an occupied base silently shifted all of them by −4/−5 (the
	# Broad Sword row read +0, the Dagger row −1) and the initial open pushed a REMOVE delta. That
	# was the product computing `candidate − occupant` exactly as designed; the test was reading a
	# fixture it never pinned. Clearing the two slots makes the oracle constants mean what the
	# header says they mean, on any roster.
	#
	# L.HAND TOO (#584, merged in from feature/world-map-input). "On any roster" is the claim,
	# and it takes all three: this worktree's regenerated `roster.json` also gives unit 0 a
	# SHIELD, which put `s_ev 75` into the initial-delta dict — a stat none of the oracles
	# below mention, in a comparison that asserts the dict exactly. Because the fixture is
	# gitignored and regenerated per machine, whichever slots happen to be filled differ by
	# checkout; clearing all three is the only version that does not depend on that.
	var prog = form.selected_character().progression
	prog.unequip_item(UnitProgression.EquipSlot.RIGHT_HAND)
	prog.unequip_item(UnitProgression.EquipSlot.LEFT_HAND)
	prog.unequip_item(UnitProgression.EquipSlot.BODY)

	# Drive to §15.25 slot focus with the glove on the (empty) R.Hand slot.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	host.open_action_menu()
	host.action_menu().confirm()                      # "Item" → the Equip slide
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	var menu = host.action_menu()
	if menu == null or d == null:
		_expect(false, "equip screen did not settle"); _finish(); return
	menu.confirm()                                    # ○ on "Equip" → slot focus (R.Hand, empty)
	if not d.is_slot_focused() or d.slot_row() != UnitProgression.EquipSlot.RIGHT_HAND:
		_expect(false, "did not reach R.Hand slot focus"); _finish(); return

	# --- ○ opens the equipment picker over the EMPTY R.Hand (base contribution 0). ---
	host._input(_action("ui_accept"))
	var p = host.equip_picker()
	if p == null or not is_instance_valid(p):
		_expect(false, "○ on the slot did not open the picker"); _finish(); return

	# The picker's INITIAL selection pushed a delta on open (not dashes): it equals compute() for the
	# highlighted item over the empty slot.
	_expect(not d.stats_preview_delta().is_empty(),
		"opening the picker did not push a numeric delta (still plain dashes)")
	_eq(d.stats_preview_delta(), EquipStatDelta.compute(int(p.entries[p.selected_row()]["id"]), -1),
		"initial picker delta = compute(highlighted, empty)")

	# Cursor onto Broad Sword (19): wp +4 / wev +5, both blue (4 coloured glyphs).
	_goto_id(p, 19)
	_eq(d.stats_preview_delta(), {"wp": 4, "wev": 5, "hp": 0, "mp": 0},
		"Broad Sword over empty R.Hand")
	await get_tree().process_frame
	_expect(d.stats_delta_glyph_palette_counts().get("pos", -1) == 4,
		"Broad Sword delta must render 4 blue glyphs (+4/+5), got %s" % d.stats_delta_glyph_palette_counts())

	# Moving the cursor RECOMPUTES live: onto Dagger (1) → wp +3 / wev +5.
	_goto_id(p, 1)
	_eq(d.stats_preview_delta(), {"wp": 3, "wev": 5, "hp": 0, "mp": 0},
		"Dagger over empty R.Hand (cursor move recomputes)")

	# --- Armor path: cancel, move the slot cursor to BODY, reopen the picker, cursor Clothes (186). ---
	host._input(_action("ui_cancel"))
	for _i in 30:
		await get_tree().process_frame
		if host.equip_picker() == null:
			break
	if not d.is_slot_focused():
		_expect(false, "cancel did not return to slot focus"); _finish(); return
	# R.Hand → BODY is 3 slot rows down (RIGHT_HAND 0, LEFT_HAND 1, HEAD 2, BODY 3).
	for _i in 3:
		host._input(_action("ui_down"))
	if d.slot_row() != UnitProgression.EquipSlot.BODY:
		_expect(false, "slot cursor not on BODY (got %d)" % d.slot_row()); _finish(); return

	host._input(_action("ui_accept"))
	var p2 = host.equip_picker()
	if p2 == null or not is_instance_valid(p2):
		_expect(false, "○ on the BODY slot did not open the picker"); _finish(); return
	_goto_id(p2, 186)                                  # Clothes
	_eq(d.stats_preview_delta(), {"wp": 0, "wev": 0, "hp": 5, "mp": 0},
		"Clothes over empty Body → hp +5 (armor routes to vitals, weapon fields dashed)")
	await get_tree().process_frame
	# The HP delta lands on the VITALS numerator (blue), NOT the Weap.Power row (which stays dashed).
	_expect(d.stats_delta_glyph_palette_counts().get("pos", -1) == 0,
		"an armor change must colour NO Weap.Power glyphs, got %s" % d.stats_delta_glyph_palette_counts())
	var vitals = host.detail_overlay()._cluster.vitals_panel()
	_expect(vitals != null, "no vitals panel")
	if vitals != null:
		_expect(vitals.number_glyph_palette_counts(0).get("pos", -1) == 2,
			"Clothes +5 must render 2 blue HP numerator glyphs, got %s" % vitals.number_glyph_palette_counts(0))

	_finish()


## Move the picker cursor down until it rests on the entry with id == `target` (bounded by row count).
func _goto_id(p, target: int) -> void:
	for _i in p.row_count():
		if int(p.entries[p.selected_row()].get("id", -1)) == target:
			return
		p.move_down()
	_expect(false, "picker has no row with id %d" % target)


func _eq(got: Dictionary, want: Dictionary, label: String) -> void:
	for k in want:
		if int(got.get(k, 0x7fffffff)) != int(want[k]):
			print("[FAIL] %s: field %s = %s, expected %s (full %s)" % [label, k, got.get(k), want[k], got])
			_failed = true
			return


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] " + msg)
		_failed = true


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipDeltaWiring test")
		get_tree().quit(1)
	else:
		print("[PASS] FormationEquipDeltaWiring: picker cursor drives live compute(preview−base) → stats + vitals delta")
		get_tree().quit(0)
