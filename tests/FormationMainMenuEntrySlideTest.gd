extends Node3D
# test-kind: logic
# seeded-break: split the EQUIP recipe's ONE concurrent group into two SEQUENTIAL groups ([equip_chrome] then [equip_slide], forward hook kept on the chrome group) in _build_recipes — the pre-ADR-0084 deferred-split shape; the Item (Equip) + Ability arms' 'roster did NOT slide WHILE the chrome was rising (must be CONCURRENT, not deferred)' AND 'entry crossed into a second group — the split must share the chrome's group' asserts red (4 total), the Change-Job arm (separate CHANGE_JOB recipe) + all snap/slide asserts stay green

## Main-menu sub-screen entries SLIDE the top chrome (FORMATION_SCREEN.md §15.1/§15.5) —
## the fix for the "binary flip" the user reported entering Change-Job from the main menu.
##
## Entering a sub-screen from the MAIN-formation menu (START on the plain roster → Change Job /
## Item / Ability) used to SNAP the vitals+nameplate PAIR straight to the Status-screen TOP. Under
## ADR-0084 the chrome + the roster split are ONE CONCURRENT group (user 2026-08-08: the game plays
## them together): the pair rises DOCKED→TOP WHILE the roster split (the job wheel / the Equip slide)
## runs in the SAME frames — no barrier deferring the split behind the chrome. Driven by the
## coordinator's ONE Player, not a self-clock — so this pumps host._process, not DetailScene._process.
##
## This guards the CONCURRENCY at the host seam; the slide MATH is DetailEntrySlideTest.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

const TICK := 2.0 / 60.0
const DOCKED_VITALS := Vector2(13, 177)   # UnitInfoCluster.LAYOUT_DOCKED (roster bottom)
const TOP_VITALS := Vector2(13, 32)       # UnitInfoCluster.LAYOUT_TOP (Status-screen top)

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	await _check_entry(FormationDetailTransition.CHANGEJOB_MENU_ROW, "Change Job")
	await _check_entry(FormationDetailTransition.EQUIP_MENU_ROW, "Item (Equip)")
	await _check_entry(FormationDetailTransition.ABILITY_MENU_ROW, "Ability")

	if _failed:
		print("[FAIL] FormationMainMenuEntrySlide test")
	else:
		print("[PASS] FormationMainMenuEntrySlide: main-menu Change-Job/Equip/Ability SLIDE the chrome (docked→top) CONCURRENTLY with the roster split (one merged group)")
	get_tree().quit()


## Drive one main-menu entry (row `menu_row`) and assert the chrome SLIDES docked→top (not a snap),
## and that the roster split runs CONCURRENTLY with the chrome (same group), not deferred behind it.
func _check_entry(menu_row: int, label: String) -> void:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	host.set_process(false)   # drive the entry by hand for determinism

	var form = host._formation
	if form == null or form.selected_character() == null:
		_expect(false, "%s: no formation/selection" % label)
		host.queue_free()
		return

	# Open the MAIN-formation menu (START on the plain roster — NO detail overlay), navigate to the row.
	host.open_main_menu()
	var menu = host.action_menu()
	_expect(menu != null, "%s: START did not open the main menu" % label)
	if menu == null:
		host.queue_free()
		return
	for _n in menu_row:
		menu.move_down()
	_expect(menu.selected_row() == menu_row, "%s: nav did not land on row %d" % [label, menu_row])
	menu.confirm()

	var d = host.detail_overlay()
	_expect(d != null, "%s: entry did not build the detail overlay" % label)
	if d == null:
		host.queue_free()
		return
	d.set_process(false)

	# THE REGRESSION: the pair must start DOCKED (a slide), NOT snapped to the Status top.
	_expect(d._cluster != null and d._cluster.vitals_origin_px().is_equal_approx(DOCKED_VITALS),
		"%s: chrome SNAPPED to top instead of sliding (vitals=%s, want docked %s)"
		% [label, (d._cluster.vitals_origin_px() if d._cluster else "none"), DOCKED_VITALS])
	# CONCURRENCY: the chrome + the roster split share ONE group — the Player is on group 0 with 2 beats.
	_expect(host._player.is_playing() and not host._playing_reversed and host._player.current_group_index() == 0,
		"%s: entry did not start on the merged concurrent group (group 0)" % label)

	# Pump the merged group via the host Player — the chrome rises DOCKED→TOP through INTERMEDIATE frames
	# WHILE the roster slides. Track the selected unit moving in the SAME frames the chrome is mid-rise.
	var sel: Vector2i = form.selected_cell
	var start_x: float = form.cell_anchor_screen_px(sel).x
	var saw_intermediate := false
	var roster_moved_during_chrome := false
	for _i in VitalsSlideAnimator.settle_frame() + 1:
		host._process(TICK)
		var y: float = d._cluster.vitals_origin_px().y
		if y > TOP_VITALS.y + 1.0 and y < DOCKED_VITALS.y - 1.0:
			saw_intermediate = true
			if absf(form.cell_anchor_screen_px(sel).x - start_x) > 0.5:
				roster_moved_during_chrome = true
	_expect(saw_intermediate,
		"%s: chrome did not pass through intermediate slide frames (snap?)" % label)
	_expect(roster_moved_during_chrome,
		"%s: roster did NOT slide WHILE the chrome was rising (must be CONCURRENT, not deferred)" % label)
	_expect(d._cluster.vitals_origin_px().is_equal_approx(TOP_VITALS),
		"%s: chrome did not reach the Status top after the slide (vitals=%s)" % [label, d._cluster.vitals_origin_px()])
	# The chrome (the shorter beat) has settled at TOP; the longer roster split is still running in the
	# SAME group — the Player has NOT crossed a barrier (still group 0), proving no chrome→split sequencing.
	_expect(not host._player.is_playing() or host._player.current_group_index() == 0,
		"%s: entry crossed into a second group — the split must share the chrome's group" % label)

	host.queue_free()
	await get_tree().process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
