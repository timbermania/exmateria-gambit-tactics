extends Node3D
# test-kind: logic
# seeded-break: set FormationDetailTransition.begin_ability_transition()'s _sub_mode to EQUIP; the Ability row then runs the Equip recipe, so the ability_only-mode / ROWS_ABILITY / 3-row / ABILITY_CONTAINER / LOWER_FRAME_ABILITY asserts red

## FormationDetailTransition START-"Ability"→Ability-sub-screen host wire (headful) —
## FORMATION_SCREEN.md §15.23, RE round 27. The exact MIRROR of FormationEquipTransitionTest:
## proves that choosing "Ability" (row 1) plays the SAME slide/spotlight/orb-box machinery as
## Item→Equip and settles to the Ability-ONLY panel + the Set/Remove/Learn 3-item list-menu.
## Only the mode-dependent seams differ from the Equip guard:
##   - detail switches to ability_only (LEFT-relocated Ability window, LOWER_FRAME_ABILITY);
##   - the list-menu is ROWS_ABILITY (Set/Remove/Learn), 3 rows, at ABILITY_CONTAINER (200,132,56,64).
## The slide MATH is guarded by FormationEquipSlideTest; this guards the Ability SEQUENCING.

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

	# Move to + choose row 1 = "Ability" → the Ability transition begins.
	_expect(StartActionMenu.ROWS[FormationDetailTransition.ABILITY_MENU_ROW] == "Ability",
		"ROWS[1] is not 'Ability' (got %s)" % StartActionMenu.ROWS[FormationDetailTransition.ABILITY_MENU_ROW])
	host.action_menu().move_down()   # row 0 → row 1
	_expect(host.action_menu().selected_row() == FormationDetailTransition.ABILITY_MENU_ROW,
		"nav did not land on the Ability row")
	host.action_menu().confirm()
	_expect(host.is_equip_sliding(), "choosing Ability did not start the (shared) slide")
	_expect(host.action_menu() == null, "action menu still open after choosing Ability")
	# Lower Status panels collapsed; the vitals+nameplate cluster stays visible (same as Equip).
	if d != null:
		_expect(d.lower_aperture().size == Vector2i.ZERO,
			"lower panel not closed at Ability start (aperture=%s)" % d.lower_aperture())
		_expect(d._cluster != null and d._cluster.visible,
			"vitals+nameplate cluster hidden during Ability (must stay, §15.23)")

	var sel: Vector2i = form.selected_cell
	var expect_settle := SpriteSlideAnimator.SETTLE_PX - Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)

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

	# The Ability-ONLY lower panel reopened at settle (§15.23 RE27) — NOT the Eqp-only panel and
	# NOT the joint Eqp+Ability Status panel.
	if d != null:
		_expect(d.lower_aperture().size != Vector2i.ZERO,
			"lower Ability panel did not reopen at settle")
		_expect(d.ability_only and not d.equip_only,
			"detail did not switch to ability_only mode at settle (equip_only=%s ability_only=%s)" % [d.equip_only, d.ability_only])
		_expect(d._lower_frame_rect().is_equal_approx(DetailScene.LOWER_FRAME_ABILITY),
			"Ability panel frame not narrowed to LOWER_FRAME_ABILITY (got %s)" % d._lower_frame_rect())
		# LOWER_FRAME_ABILITY is NARROWER than Equip's (x13..130 vs x13..138) — the RE27 measurement.
		_expect(DetailScene.LOWER_FRAME_ABILITY.size.x < DetailScene.LOWER_FRAME_EQUIP.size.x,
			"Ability frame should be narrower than Equip (117 < 125)")

	# The Set/Remove/Learn list-menu opened — the reused slot-6 window, FOREGROUND, 3 rows.
	var menu = host.action_menu()
	_expect(menu != null, "Ability 3-item list-menu did not open at settle")
	if menu != null:
		_expect(menu.rows == StartActionMenu.ROWS_ABILITY,
			"Ability menu content != Set/Remove/Learn (got %s)" % [menu.rows])
		_expect(menu.row_count() == 3, "Ability menu not 3 rows (got %d)" % menu.row_count())
		# §15.23 RE27 (prim scan, oracle savestate7): the window body SPRTt is at display (200,132) 56×64.
		_expect(menu.container_rect() == Rect2i(StartActionMenu.ABILITY_CONTAINER),
			"Ability menu container = %s, want ABILITY_CONTAINER (200,132,56,64)" % menu.container_rect())
		# The "Menu" tab derives as container+(3,−1) = (203,131) — the prim-scanned position.
		var tab := Vector2(StartActionMenu.ABILITY_CONTAINER.position) + Vector2(StartActionMenu.TITLE_TAB_OFFSET)
		_expect(tab == Vector2(203, 131), "Ability 'Menu' tab = %s, want (203,131)" % tab)
	_expect(host.is_equip_screen_open(), "is_equip_screen_open() false after Ability settle")

	# The floor spotlight + orb/box hide behave identically to Equip (shared machinery).
	_expect(form.current_spotlight_center().distance_to(form.EQUIP_SPOTLIGHT_SETTLE) <= 0.5,
		"spotlight did not track to (164,177): %s" % form.current_spotlight_center())
	_expect(not form._orbs_visible, "grid orbs not hidden on the Ability screen")
	_expect(not form._box_trail_visible, "gold box VISUAL not hidden on the Ability screen")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationAbilityTransition test")
	else:
		print("[PASS] FormationAbilityTransition: Ability→close-lower→slide→reopen (ability_only + Set/Remove/Learn)")
	get_tree().quit()
