extends Node3D
# test-kind: logic
# seeded-break: FormationDetailTransition._changejob_concurrent_enter_reverse reveals the grid orbs + gold box at the return-group seam (set_orbs_visible(true) + set_box_trail_visible(true) appended after the barrier + chrome hooks) — the documented 2026-08-08 regression state where the box pops in at the oval centre and rides home; 'orbs/box revealed mid-exit (popped in at the oval centre, not at home) — Bug 2' RED; chrome start-docked/raise/descent, the descent/un-slide concurrency, and the at-settle restore stays green; GREEN unbroken on the reverted tree

## FormationDetailTransition Change-Job EXIT is the ENTRY reversed (ADR-0084 invariant 1) — the
## half-landed `[chrome]` group of the canonical recipe finished. Guards the two symptoms of the
## un-modeled reverse the coordinator used to SNAP in `_restore_formation`:
##
##   Bug 1 (chrome descent). On entry the top chrome (vitals+nameplate cluster + band) RAISES
##     DOCKED→TOP; on back-out it must DESCEND TOP→DOCKED through intermediate frames, CONCURRENTLY
##     with the roster un-split (user 2026-08-08: the ring fling plays FIRST, then the chrome descent
##     and un-split go together), not teleport away.
##   Bug 2 (box/orb reveal timing). The grid orbs + gold box are hidden before the split on entry;
##     on exit they must stay HIDDEN through the ENTIRE return (the ring fling AND the concurrent
##     chrome-descent/un-split group) and be revealed only once the unit is HOME — at settle/teardown.
##     Revealing them at the concurrent-group seam popped the gold box in at the oval CENTRE and rode
##     it home (2026-08-08 regression); the reveal now falls out of _restore_formation at settle.
##
## Enters via the MAIN-formation menu (PATH 1 — chrome RAISES on entry), the reported-bug flow, so
## the exit is the literal reverse of an entry that animated the chrome up.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const ChangeJobWheel = preload("res://src/ui3/changejob/ChangeJobWheel.gd")
const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")

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
	var character = form.selected_character() if form != null else null
	_expect(form != null and character != null, "no formation/selection")
	if form == null or character == null:
		_finish()
		return

	var TOP_Y: float = UnitInfoCluster.LAYOUT_TOP["vitals"].y       # 32 — chrome up
	var DOCKED_Y: float = UnitInfoCluster.LAYOUT_DOCKED["vitals"].y  # 177 — chrome docked
	var sel: Vector2i = form.selected_cell

	# --- PATH 1 entry: open the MAIN menu on the roster, choose "Change Job" → the chrome RAISES ---
	host.open_main_menu()
	var menu = host._menu
	_expect(menu != null, "main menu did not open")
	if menu == null:
		_finish()
		return
	for _n in FormationDetailTransition.CHANGEJOB_MENU_ROW:
		menu.move_down()
	_expect(menu.selected_row() == FormationDetailTransition.CHANGEJOB_MENU_ROW,
		"nav did not reach the Change Job row")
	menu.confirm()   # → _enter_changejob_from_main_menu → recipe forward (chrome group first)

	var d = host.detail_overlay()
	_expect(d != null and d._cluster != null, "Change Job did not build the detail overlay + cluster")
	if d == null or d._cluster == null:
		_finish()
		return
	var cluster = d._cluster

	# The chrome must START docked and RAISE as a recipe beat (not snap to TOP). Right after the
	# menu confirm, before the raise beat is stepped, the cluster sits at (or near) DOCKED.
	_expect(cluster.vitals_origin_px().y >= DOCKED_Y - 1.0,
		"chrome did not start docked before the raise beat (y=%.1f, want ~%.0f)"
		% [cluster.vitals_origin_px().y, DOCKED_Y])

	# Drive the whole forward recipe to settled (chrome raise → roster split → ring build).
	var guard := 0
	while host._player.is_playing() and guard < 500:
		host._player.step()
		guard += 1
	_expect(is_instance_valid(cluster) and cluster.vitals_origin_px().y <= TOP_Y + 1.0,
		"chrome not raised to TOP after entry (y=%.1f)"
		% [cluster.vitals_origin_px().y if is_instance_valid(cluster) else -1.0])
	_expect(host.is_changejob_open(), "Change-Job screen never settled after entry")
	_expect(not form._orbs_visible and not form._box_trail_visible,
		"orbs/box not hidden on the settled Change-Job screen")

	# --- BACK OUT (×/Esc): the ANIMATED reverse. Ring flings FIRST, then chrome descends WHILE the ---
	# --- roster un-splits (concurrent); box stays hidden through the fling, revealed with that group ---
	host._exit_changejob_to_main_menu()
	_expect(host.is_changejob_exiting(), "back-out did not start the animated exit")

	var saw_descent := false                    # Bug 1: the chrome cluster moved TOP→DOCKED at all
	var box_shown_during_exit := false          # Bug 2: orbs/box revealed at ANY point mid-exit (the bug)
	var saw_unslide_with_descent := false        # concurrency: chrome mid-descent WHILE roster off-oval
	guard = 0
	while host.is_changejob_exiting() and guard < 400:
		# REVERSE play order is [ring, {chrome,split}] — the chrome descends in the SECOND group
		# (index 1), CONCURRENTLY with the roster un-slide. Group 0 is the ring fling.
		var in_return_group: bool = host._player.current_group_index() >= 1
		# Bug 2: the orbs/box must stay HIDDEN for EVERY exit frame — the fling AND the concurrent
		# return group — and pop in only once the unit is HOME (at teardown). A reveal at the return
		# seam popped the gold box in at the oval centre and rode it home.
		if form._orbs_visible or form._box_trail_visible:
			box_shown_during_exit = true
		var chrome_mid: bool = is_instance_valid(cluster) and cluster.vitals_origin_px().y > TOP_Y + 2.0
		# The selected unit is still off the oval centre while the un-slide is mid-flight.
		var roster_off_oval: bool = form.cell_anchor_screen_px(sel).distance_to(
			form.CHANGEJOB_CENTRE - Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)) > 5.0
		if chrome_mid and in_return_group and roster_off_oval:
			saw_unslide_with_descent = true
		host.changejob_exit_step()
		guard += 1
		if chrome_mid:
			saw_descent = true

	# Bug 1: the chrome DESCENDED (was TOP, slid toward DOCKED) — not snapped away by teardown.
	_expect(saw_descent, "chrome did NOT descend on back-out (snapped in teardown, not animated) — Bug 1")
	# Bug 2: the orbs/box stayed HIDDEN through the whole animated return (no centre pop-in).
	_expect(not box_shown_during_exit,
		"orbs/box revealed mid-exit (popped in at the oval centre, not at home) — Bug 2")
	# Concurrency (user 2026-08-08): the chrome DESCENT overlapped the roster un-slide in the same frames.
	_expect(saw_unslide_with_descent,
		"chrome descent and roster un-slide did NOT overlap — they must run CONCURRENTLY, not sequentially")

	# Settled → full teardown to the roster (RE25 full unwind).
	_expect(not host.is_changejob_exiting(), "exit did not settle after the concurrent chrome-descent/un-split")
	_expect(host.detail_overlay() == null, "detail overlay not torn down after exit")
	_expect(form._orbs_visible and form._box_trail_visible, "orbs/box not restored after exit")
	_expect(form.cell_anchor_screen_px(sel).distance_to(
		form.CHANGEJOB_CENTRE - Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)) > 5.0,
		"selected unit did not un-slide from the oval centre after back-out")

	_finish()


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationChangeJobExitReversal test")
	else:
		print("[PASS] FormationChangeJobExitReversal: ring flings first, then chrome descends TOP→DOCKED CONCURRENTLY with the roster un-split; orbs/box stay hidden through the ENTIRE return, revealed only at home/settle (exit == entry reversed)")
	get_tree().quit()
