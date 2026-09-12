extends Node3D
# test-kind: logic
# seeded-break: replaced the reversed-recipe replay in _begin_sub_exit_reverse with an instant _teardown_sub_screen() (skipped _play_recipe(_recipes["EQUIP"], true, ...)) — the pre-ADR-0084 Esc teleport after the lower close; the Item (Equip) + Ability arms' 'chrome did not pass through intermediate slide frames on exit (teleport)', 'band cross-fade did not run backward', 'roster did NOT un-slide WHILE the chrome descended' and 'lower panel not fully closed at the first chrome-descent frame' asserts red (8 total), the overlay-persists / no-snap / Bug-2 close-first ordering + post-settle teardown asserts stay green

## Main-menu sub-screen EXITS SLIDE the top chrome back down (ADR-0084) — the RED
## observation of the Esc-teleport bug, the mirror of the entry-slide guard
## (FormationMainMenuEntrySlideTest, FORMATION_SCREEN.md §15.1/§15.5).
##
## Entering the main-menu Equip/Ability screen SLIDES the vitals+nameplate PAIR
## docked→top (the "binary flip" fix, 4a2cc7f83). But Esc from that screen used to
## `queue_free` the overlay INSTANTLY (`_exit_equip_to_main_menu`) — a teleport: the
## chrome vanished with no reverse animation, while ○-press Status close animated.
##
## ADR-0084 routes every exit through the coordinator's `leave()`, which replays the
## entry's chrome slide REVERSED (top→docked) with the §15.6 band cross-fade run
## backward, and does the instant teardown only when the pair is docked again
## (`settled`), never before. This guards the reverse SEQUENCING at the host seam:
##   - the overlay persists to animate (NOT freed the same frame as Esc),
##   - the pair passes through INTERMEDIATE slide frames (NOT snapped to docked),
##   - the band cross-fade runs BACKWARD (roster band fades back IN),
##   - the CHROME slide stays box-less (the aperture never GROWS — no spurious box-open),
##   - the lower Eqp/stats panel box-CLOSES FIRST (aperture shrinks to nothing) and only THEN
##     does the chrome descend — sequential, "menu closes, then everything else at once" (Bug 2,
##     user 2026-08-08); it never blinks out LAST at teardown,
##   - only after the pair docks is the overlay torn down + the main menu reopened.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")

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
	await _check_exit(FormationDetailTransition.EQUIP_MENU_ROW, "Item (Equip)")
	await _check_exit(FormationDetailTransition.ABILITY_MENU_ROW, "Ability")

	if _failed:
		print("[FAIL] FormationMainMenuExitSlide test")
	else:
		print("[PASS] FormationMainMenuExitSlide: Esc from the main-menu Equip/Ability screen SLIDES the chrome back (top→docked), band cross-fade backward, teardown deferred to settle")
	get_tree().quit()


## Open the main-menu sub-screen for `menu_row`, drive it to fully settled, then press
## Esc and assert the chrome slides back down instead of teleporting away.
func _check_exit(menu_row: int, label: String) -> void:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	host.set_process(false)   # drive every stepper by hand for determinism

	var form = host._formation
	if form == null or form.selected_character() == null:
		_expect(false, "%s: no formation/selection" % label)
		host.queue_free()
		return

	# Open the sub-screen from the main menu, exactly as the entry guard does.
	host.open_main_menu()
	var menu = host.action_menu()
	if menu == null:
		_expect(false, "%s: START did not open the main menu" % label)
		host.queue_free()
		return
	for _n in menu_row:
		menu.move_down()
	menu.confirm()

	var d = host.detail_overlay()
	if d == null:
		_expect(false, "%s: entry did not build the detail overlay" % label)
		host.queue_free()
		return
	d.set_process(false)

	# Pump the entry chrome slide to settle → entry_slide_done → the roster slide begins.
	for _i in VitalsSlideAnimator.settle_frame() + 2:
		d._process(TICK)
		host._process(TICK)
	# Pump the Equip/Ability roster slide to settle → the lower panel + list-menu open.
	for _i in SpriteSlideAnimator.SLIDE_DURATION + 2:
		host._process(TICK)
	_expect(host.is_equip_screen_open(),
		"%s: sub-screen never fully opened (can't test the exit)" % label)
	_expect(d._cluster != null and d._cluster.vitals_origin_px().is_equal_approx(TOP_VITALS),
		"%s: chrome not at the Status top before Esc (got %s)" % [label, (d._cluster.vitals_origin_px() if d._cluster else "none")])
	var band_before: float = d.formation_band_factor()
	_expect(band_before < 0.01,
		"%s: roster band not faded out on the open screen (got %.3f)" % [label, band_before])
	var aperture_before = d.lower_aperture()

	# The entry pushed EQUIP/ABILITY onto the coordinator stack — the seam knows the current screen.
	_expect(host.current_state() != FormationDetailTransition.State.IDLE,
		"%s: coordinator did not track the open sub-screen (state=IDLE)" % label)

	# --- Esc: the exit must SLIDE, not teleport. Drive it through the ONE seam (leave()). ---
	host.leave()

	# THE REGRESSION: the overlay must persist to animate — NOT freed the same frame,
	# and the pair must still be up at the top (a slide down is about to run), NOT docked.
	var d_after = host.detail_overlay()
	_expect(d_after != null and is_instance_valid(d_after),
		"%s: Esc FREED the overlay instantly (teleport) — must persist to slide back" % label)
	if d_after == null or not is_instance_valid(d_after):
		host.queue_free()
		await get_tree().process_frame
		return
	_expect(d_after._cluster != null and not d_after._cluster.vitals_origin_px().is_equal_approx(DOCKED_VITALS),
		"%s: chrome SNAPPED to docked on Esc instead of sliding (vitals=%s)"
		% [label, (d_after._cluster.vitals_origin_px() if d_after._cluster else "none")])
	_expect(host.is_moving(),
		"%s: coordinator not moving after Esc (leave() didn't start a reverse slide)" % label)

	# Pump the reverse recipe. ADR-0084 plays it as the mirror of the (concurrent) entry: the ONE merged
	# group runs the roster un-slide AND the chrome descent TOGETHER (user 2026-08-08). The chrome must
	# pass through INTERMEDIATE frames (not one snap) and the band must cross-fade BACKWARD (roster band
	# factor rising 0→1) — all while the roster slides home in the same frames.
	var saw_intermediate := false
	var band_rose := false
	var roster_moved_during_descent := false
	var lower_shrank := false           # Bug 2: the Eqp/stats panel box-CLOSES during the exit…
	var closed_while_chrome_held := false   # …WHILE the chrome is still parked at TOP (menu closes first)
	var descent_over_open_panel := false    # VIOLATION: chrome descended while the panel was still open
	var descent_started := false
	var aperture_at_descent_start := -1
	var sel: Vector2i = form.selected_cell
	var exit_start_x: float = form.cell_anchor_screen_px(sel).x
	var last_band := band_before
	for _i in SpriteSlideAnimator.SLIDE_DURATION + VitalsSlideAnimator.settle_frame() + 20:
		if not is_instance_valid(d_after) or host.detail_overlay() == null:
			break
		d_after._process(TICK)
		host._process(TICK)
		var y: float = d_after._cluster.vitals_origin_px().y
		var chrome_mid: bool = y > TOP_VITALS.y + 1.0 and y < DOCKED_VITALS.y - 1.0
		var chrome_at_top: bool = y <= TOP_VITALS.y + 1.0
		if chrome_mid:
			saw_intermediate = true
			if absf(form.cell_anchor_screen_px(sel).x - exit_start_x) > 0.5:
				roster_moved_during_descent = true
		var b := d_after.formation_band_factor()
		if b > last_band + 0.001:
			band_rose = true
		last_band = b
		# Bug 2 (SEQUENTIAL, user 2026-08-08): the lower Eqp/stats panel box-CLOSES FIRST — the aperture
		# SHRINKS center-out while the chrome is still parked at TOP — and only ONCE it is shut does the
		# chrome descend. So (a) we must see the aperture mid-shrink with the chrome held at TOP, (b) the
		# chrome must NOT descend while the panel is still open, and (c) at the first descent frame the
		# aperture is already closed. The chrome slide is still box-less — the aperture must never GROW.
		var ap := d_after.lower_aperture().size.x
		if ap < aperture_before.size.x - 1:
			lower_shrank = true
			if chrome_at_top:
				closed_while_chrome_held = true
		if chrome_mid and ap > 1:
			descent_over_open_panel = true
		if chrome_mid and not descent_started:
			descent_started = true
			aperture_at_descent_start = ap
		_expect(ap <= aperture_before.size.x + 1,
			"%s: a box-open ran during the exit slide (aperture grew to %s)" % [label, d_after.lower_aperture()])
	_expect(saw_intermediate,
		"%s: chrome did not pass through intermediate slide frames on exit (teleport)" % label)
	_expect(band_rose,
		"%s: band cross-fade did not run backward on exit (roster band never faded back in)" % label)
	_expect(roster_moved_during_descent,
		"%s: roster did NOT un-slide WHILE the chrome descended (must be CONCURRENT, not sequential)" % label)
	# Bug 2: the lower panel folded shut FIRST (box-close while the chrome held at TOP), then the chrome
	# descended over an already-closed panel — sequential "menu closes, then everything else at once",
	# NOT rendered full-size until the overlay was freed (the "panels go away LAST" bug).
	_expect(lower_shrank,
		"%s: lower Eqp/stats panel did NOT box-close during the exit (blinked out at teardown) — Bug 2" % label)
	_expect(closed_while_chrome_held,
		"%s: lower panel did not fold shut BEFORE the chrome descended (must close FIRST) — Bug 2" % label)
	_expect(not descent_over_open_panel,
		"%s: chrome descended while the lower panel was still open (must be SEQUENTIAL: close first) — Bug 2" % label)
	_expect(descent_started and aperture_at_descent_start <= 1,
		"%s: lower panel not fully closed at the first chrome-descent frame (aperture=%d) — Bug 2" % [label, aperture_at_descent_start])

	# After the slide settles: overlay torn down, roster restored, main menu reopened.
	_expect(host.detail_overlay() == null,
		"%s: overlay not torn down after the exit slide settled" % label)
	_expect(host.action_menu() != null,
		"%s: main menu not reopened after the exit" % label)
	_expect(host.current_state() == FormationDetailTransition.State.IDLE,
		"%s: coordinator not back at IDLE after the exit settled (stack=%s)" % [label, host._stack])

	host.queue_free()
	await get_tree().process_frame


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
