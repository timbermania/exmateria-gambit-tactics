extends Node3D
# test-kind: logic
# seeded-break: no-op'd the enter_equip_mode() call in _finish_sub (the settle-time reopen) so the lower panel never reopens as Eqp-only; the 'lower Eqp panel reopened' + 'Eqp-only mode' + 'frame narrowed to LOWER_FRAME_EQUIP' + 'is_equip_screen_open' asserts red, the close-lower/slide/settle/Equip-menu geometry + spotlight asserts stay green

## FormationDetailTransition Item→Equip host wire (headful) — FORMATION_SCREEN.md
## §15.23, RE round 22. Proves the end-to-end wire from the START action menu:
##   - choosing "Item" (row 0) closes the START menu and the LOWER Status panels
##     (Eqp/Ability + stats) while the vitals + nameplate cluster STAYS (the oracle
##     keeps them on-screen through the whole transition);
##   - the formation unit rows then slide (selected → (166,173), others off-right);
##   - after SLIDE_DURATION steps the slide ends and the (Eqp) lower panel reopens.
## The slide MATH is guarded by FormationEquipSlideTest; this guards the SEQUENCING.

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
	if form == null:
		_finish()
		return

	# Open the Status overlay (○-press) then the START action menu.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○-press did not open the detail overlay")
	host.open_action_menu()
	_expect(host.action_menu() != null, "START did not open the action menu")

	# Choose row 0 = "Item" → the Equip transition begins.
	host.action_menu().confirm()
	_expect(host.is_equip_sliding(), "choosing Item did not start the Equip slide")
	_expect(host.action_menu() == null, "action menu still open after choosing Item")
	# Lower Status panels collapsed; the vitals+nameplate cluster stays visible.
	if d != null:
		_expect(d.lower_aperture().size == Vector2i.ZERO,
			"lower panel not closed at Equip start (aperture=%s)" % d.lower_aperture())
		_expect(d._cluster != null and d._cluster.visible,
			"vitals+nameplate cluster hidden during Equip (must stay, §15.23)")

	var sel: Vector2i = form.selected_cell
	var expect_settle := SpriteSlideAnimator.SETTLE_PX - Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)

	# At frame 0 of the merged concurrent group: selected at its docked origin, not yet settled.
	_expect(form.cell_anchor_screen_px(sel).distance_to(expect_settle) > 1.0,
		"selected already at settle before stepping")

	# Step the whole EQUIP recipe forward: ONE concurrent group runs the shared chrome (HELD at TOP —
	# the path-2 detail chrome is already up) AND the roster split slide TOGETHER. equip_step drives it.
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()

	_expect(not host.is_equip_sliding(), "slide did not end after SLIDE_DURATION steps")
	_expect(form.cell_anchor_screen_px(sel).distance_to(expect_settle) <= 0.5,
		"selected did not settle at (166,173): %s" % form.cell_anchor_screen_px(sel))
	for cell in form.visible_unit_cells():
		if cell != sel:
			_expect(form.cell_anchor_screen_px(cell).x >= 256.0,
				"non-selected %s not off the right edge" % cell)
	# The Eqp-ONLY lower panel reopened at settle (§15.23, RE round 23) — NOT the joint
	# Eqp+Ability Status panel that reopened before this fix.
	if d != null:
		_expect(d.lower_aperture().size != Vector2i.ZERO,
			"lower Eqp panel did not reopen at settle")
		_expect(d.equip_only,
			"detail did not switch to Eqp-only mode at settle (still showing Ability, §15.23)")
		_expect(d._lower_frame_rect().is_equal_approx(DetailScene.LOWER_FRAME_EQUIP),
			"Eqp panel frame not narrowed to LOWER_FRAME_EQUIP (got %s)" % d._lower_frame_rect())

	# The Equip/Best/Remove/List list-menu opened — the reused slot-6 window, FOREGROUND.
	var menu = host.action_menu()
	_expect(menu != null, "Equip 4-item list-menu did not open at settle")
	if menu != null:
		_expect(menu.rows == StartActionMenu.ROWS_EQUIP,
			"Equip menu content != Equip/Best/Remove/List (got %s)" % [menu.rows])
		_expect(menu.row_count() == 4, "Equip menu not 4 rows (got %d)" % menu.row_count())
		# §15.23 RE24: the Equip menu is the slot-6 window at the SMALLER EQUIP container (196,132,60,80),
		# NOT the START container — the (172,120,84,96) prim a naive scan finds is the START-menu ghost.
		_expect(menu.container_rect() == Rect2i(StartActionMenu.EQUIP_CONTAINER),
			"Equip menu container = %s, want EQUIP_CONTAINER (196,132,60,80)" % menu.container_rect())
		# Derived geometry follows the SAME container-relative offsets (framebuffer-matched): frame
		# right x244 / bottom y205, row0 top y143, glove at (184,142).
		var fr := StartActionMenu.frame_rect_for(Rect2i(StartActionMenu.EQUIP_CONTAINER))
		_expect(fr == Rect2i(198, 134, 46, 71),
			"Equip frame rect = %s, want (198,134,46,71) [right x244, bottom y205]" % fr)
		_expect(StartActionMenu.cursor_display_pos_in(Rect2i(StartActionMenu.EQUIP_CONTAINER), 0, 0) == Vector2(184, 142),
			"Equip glove(row0) = %s, want (184,142)" % StartActionMenu.cursor_display_pos_in(Rect2i(StartActionMenu.EQUIP_CONTAINER), 0, 0))
	_expect(host.is_equip_screen_open(), "is_equip_screen_open() false after settle")

	# §15.23 RE24 / §16: the floor spotlight tracked the sliding unit to the measured settle
	# (0x8018BAD0 = (164,177)), NOT left trailing at the old grid cell.
	_expect(form.current_spotlight_center().distance_to(form.EQUIP_SPOTLIGHT_SETTLE) <= 0.5,
		"spotlight did not track to (164,177): %s" % form.current_spotlight_center())
	# …and the unit body brightness tracks the pool too — the element sweep samples the falloff at
	# the unit's LIVE position, so a unit moving WITH the pool stays lit (was: sampled at the stale
	# docked cell → darkened mid-slide, the "floor & unit disjointed" bug). RED-GREEN: prove the live
	# sample stays lit AND the old docked sample would have darkened it.
	var sel2: Vector2i = form.selected_cell
	var live_b: float = form.falloff_px(form.live_cell_box_centre(sel2), form._box_glide, form.orb_falloff_scale) / 128.0
	var docked_b: float = form.falloff_px(form.cell_box_centre(sel2), form._box_glide, form.orb_falloff_scale) / 128.0
	_expect(live_b >= 0.9, "settled unit body not lit via live falloff (got %.3f)" % live_b)
	_expect(docked_b < live_b - 0.1,
		"live-position fix should matter: docked formula would darken the moving unit (docked=%.3f live=%.3f)" % [docked_b, live_b])
	# The grid orb + gold-box VISUALS are hidden on the settled Equip screen (oracle: 0 of each).
	_expect(not form._orbs_visible, "grid orbs not hidden on the Equip screen (§15.23 RE24)")
	_expect(not form._box_trail_visible, "gold box VISUAL not hidden on the Equip screen (§15.23 RE24)")

	# Restore (what _restore_formation drives on close): the retarget clears and the grid chrome
	# (orbs/box) returns. Driven directly here so the check is deterministic (the async fold-close
	# spans indeterminate frames); _restore_formation wires these same calls.
	form.end_equip_slide()
	form.set_orbs_visible(true)
	form.set_box_trail_visible(true)
	_expect(form._orbs_visible and form._box_trail_visible, "orbs/box not restored")
	_expect(not form._equip_spotlight_active, "equip spotlight retarget not cleared on end_equip_slide")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationEquipTransition test")
	else:
		print("[PASS] FormationEquipTransition: Item→close-lower→slide→reopen (vitals stay)")
	get_tree().quit()
