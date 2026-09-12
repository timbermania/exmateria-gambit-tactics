extends Node3D
# test-kind: logic
# seeded-break: FormationScene.begin_changejob_slide swaps the split targets — top-half rows exit RIGHT (EQUIP_EXIT_X) and bottom-half rows exit LEFT (CHANGEJOB_EXIT_LEFT_X); 'top-half unit … did not exit LEFT' + 'bottom-half unit … did not exit RIGHT' + 'roster not off-screen at un-slide start' RED; centre slide, the gender-filtered wheel ring + contract-in, the title plate, ←/→ rotation, and the exit fling stay green; GREEN unbroken on the reverted tree
## FormationDetailTransition START-"Change Job"→full-screen job-wheel host wire (headful) —
## FORMATION_SCREEN.md §15.24, RE round 28. Unlike Equip/Ability (lower-panel sub-states), Change Job
## is a whole NEW screen: the roster SPLITS (upper rows exit left / lower right), the selected unit
## slides to the oval CENTRE, and a ring of one generic body per gender-appropriate job surrounds it,
## with the job title bottom-middle. This guards the SEQUENCING + the data-derived wheel membership.
## (The pure wheel model — gender lock, sprites, oval — is guarded by ChangeJobWheelTest.)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const ChangeJobWheel = preload("res://src/ui3/changejob/ChangeJobWheel.gd")
const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

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
	var female: bool = character.progression != null \
		and character.progression.base_stat_type == UnitProgression.BaseStatType.FEMALE

	# Open the Status overlay (○-press) then the START action menu.
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○-press did not open the detail overlay")
	host.open_action_menu()
	_expect(host.action_menu() != null, "START did not open the action menu")

	# Move to + choose row 2 = "Change Job" → the Change-Job transition begins.
	_expect(StartActionMenu.ROWS[FormationDetailTransition.CHANGEJOB_MENU_ROW] == "Change Job",
		"ROWS[2] is not 'Change Job' (got %s)" % StartActionMenu.ROWS[FormationDetailTransition.CHANGEJOB_MENU_ROW])
	host.action_menu().move_down()   # 0 → 1
	host.action_menu().move_down()   # 1 → 2
	_expect(host.action_menu().selected_row() == FormationDetailTransition.CHANGEJOB_MENU_ROW,
		"nav did not land on the Change Job row")
	host.action_menu().confirm()
	_expect(host.action_menu() == null, "action menu still open after choosing Change Job")
	# Lower Status panels collapsed (the merged group's forward hook closes them synchronously); the
	# vitals+nameplate cluster + pager STAY (the top chrome).
	if d != null:
		_expect(d.lower_aperture().size == Vector2i.ZERO,
			"lower panel not closed at Change Job start (aperture=%s)" % d.lower_aperture())
		_expect(d._cluster != null and d._cluster.visible,
			"vitals+nameplate cluster hidden during Change Job (must stay, §15.24 beat 5)")
	# The chrome raise + roster split are ONE CONCURRENT group now (user 2026-08-08) — the split is live
	# from the group's first frame, NOT deferred behind a chrome barrier. (Path-2 detail: the chrome
	# HOLDS at TOP since it is already up, while the split runs.)
	_expect(host.is_changejob_sliding(), "choosing Change Job did not start the concurrent chrome+split group")

	var sel: Vector2i = form.selected_cell
	var centre_origin: Vector2 = form.CHANGEJOB_CENTRE - Vector2(form.BODY_ANCHOR_DX, form.BODY_ANCHOR_DY)

	# Step the entry slide to completion (builds the wheel + title frame at the end).
	for _s in SpriteSlideAnimator.SLIDE_DURATION:
		host.changejob_step()

	_expect(not host.is_changejob_sliding(), "slide did not end after SLIDE_DURATION steps")

	# Beat 3: selected unit settled at the oval CENTRE.
	_expect(form.cell_anchor_screen_px(sel).distance_to(centre_origin) <= 0.5,
		"selected did not settle at oval centre: %s (want %s)" % [form.cell_anchor_screen_px(sel), centre_origin])
	# Beats 1–2 (§15.24 item 4): the split is a FIXED top-half/bottom-half row split — TOP rows exit
	# LEFT, BOTTOM rows exit RIGHT — INDEPENDENT of the selected unit's row (oracle: Ramza selected in
	# the TOP row still sends the rest of that row LEFT, not RIGHT). With sel in row 0 this exercises
	# BOTH branches (the old `cell.y < sel.y` rule left the LEFT branch untested for a top-row selection).
	var saw_left := false
	var saw_right := false
	for cell in form.visible_unit_cells():
		if cell == sel:
			continue
		var x := form.cell_anchor_screen_px(cell).x
		if cell.y * 2 < form.ROWS:
			_expect(x <= 0.0, "top-half unit %s did not exit LEFT (x=%s)" % [cell, x])
			saw_left = true
		else:
			_expect(x >= 256.0, "bottom-half unit %s did not exit RIGHT (x=%s)" % [cell, x])
			saw_right = true
	_expect(saw_left and saw_right, "split did not diverge BOTH ways (left=%s right=%s)" % [saw_left, saw_right])

	# Beat 8: the job wheel is built — one member per gender-appropriate generic job.
	var expect_jobs := ChangeJobWheel.job_ids_for_sex(female)
	_expect(host.is_changejob_open(), "is_changejob_open() false after settle")
	_expect(form.changejob_wheel_body_count() == expect_jobs.size(),
		"wheel body count = %d, want %d (gender-filtered generic jobs)" % [form.changejob_wheel_body_count(), expect_jobs.size()])
	_expect(form.changejob_wheel_job_ids() == expect_jobs,
		"wheel job ids != gender-filtered generic set")

	# Item 1 (§15.24): every ring member casts the SAME subtractive feet shadow the roster units do.
	_expect(form.changejob_wheel_shadow_count() == expect_jobs.size(),
		"ring shadow count = %d, want %d (each member needs the roster feet decal, item 1)"
		% [form.changejob_wheel_shadow_count(), expect_jobs.size()])
	# Item 2 (§15.24): ring members are spotlight-IMMUNE — full brightness, and a sweep (which drives
	# the roster bodies off the glide pool) must LEAVE them at 1.0, not dim the far synthetic keys.
	_expect(form.changejob_wheel_min_brightness() >= 0.999,
		"ring member dimmed at build (min ambient_brightness=%.3f, want 1.0, item 2)"
		% form.changejob_wheel_min_brightness())
	form._apply_element_sweep()
	_expect(form.changejob_wheel_min_brightness() >= 0.999,
		"ring member dimmed by the spotlight sweep (min ambient_brightness=%.3f, want 1.0, item 2)"
		% form.changejob_wheel_min_brightness())

	# Gender lock (§15.24 beat 8): the wheel drops the opposite-sex-locked job.
	if female:
		_expect(form.changejob_wheel_job_ids().has("5c") and not form.changejob_wheel_job_ids().has("5b"),
			"female wheel must include Dancer (5c), exclude Bard (5b)")
	else:
		_expect(form.changejob_wheel_job_ids().has("5b") and not form.changejob_wheel_job_ids().has("5c"),
			"male wheel must include Bard (5b), exclude Dancer (5c)")

	# Gap 2 (§15.24 RE29): the ring does NOT snap to its final oval slots — it CONTRACTS in. Right after
	# build the entry factor k is off-oval (> 1); stepping it to ENTRY_DURATION settles k → 1.
	_expect(form.changejob_entry_k() > 1.0,
		"ring placed instantly (entry k=%.2f, want > 1 — must slide in, §15.24 RE29 gap 2)" % form.changejob_entry_k())
	for _e in ChangeJobWheel.ENTRY_DURATION:
		host.changejob_entry_step()
	_expect(form.changejob_entry_settled(),
		"ring entry did not settle after ENTRY_DURATION steps (k=%.2f)" % form.changejob_entry_k())

	# Beat 9: the bottom-middle job-title frame shows the highlighted (current) job — and BOX-OPENS.
	# For the CURRENT job the plate shows the NAME ONLY — NO "Lv." line (§15.24 RE30: oracle Squire-as-
	# current has no Lv; only prospective jobs show "Lv. N").
	var cj = host.changejob_screen()
	_expect(cj != null, "no Change-Job title frame at settle")
	if cj != null:
		var want_title := ChangeJobWheel.job_name(character.progression.current_job_id)
		_expect(cj.job_title() == want_title,
			"title frame = '%s', want '%s' (highlighted job)" % [cj.job_title(), want_title])
		_expect(cj.frame_materials().size() > 0, "job-title frame not built")
		_expect(cj.body_materials().size() > cj.frame_materials().size(),
			"job name not collected into the box-open body group (gap 1)")
		_expect(cj.job_level() == 0 and cj.level_cell_count() == 0,
			"current job must NOT show a Lv line (level=%d cells=%d, §15.24 RE30)"
			% [cj.job_level(), cj.level_cell_count()])

	# Gap 3 (§15.24 RE29): ←/→ ROTATES the ring — the highlighted job steps +1 and the plate updates; the
	# top-right nameplate deliberately does NOT change (stays the unit's current job).
	var front0 := form.changejob_front_index()
	var job0 := form.changejob_highlighted_job_id()
	host.changejob_rotate(1)
	_expect(form.changejob_is_rotating(), "RIGHT did not start a ring rotation (gap 3)")
	for _r in form.CHANGEJOB_ROTATE_DURATION + 1:
		host.changejob_rot_step()
	_expect(not form.changejob_is_rotating(), "rotation did not settle")
	_expect(abs(form.changejob_front_index() - (front0 + 1.0)) <= 0.001,
		"front index did not advance by +1 (from %.2f to %.2f)" % [front0, form.changejob_front_index()])
	var job1 := form.changejob_highlighted_job_id()
	_expect(job1 != job0, "highlighted job did not change on RIGHT (still %s)" % job0)
	if cj != null:
		_expect(cj.job_title() == ChangeJobWheel.job_name(job1),
			"plate title did not update to the rotated job '%s' (shows '%s')" % [ChangeJobWheel.job_name(job1), cj.job_title()])
		# A PROSPECTIVE (non-current) job DOES show "Lv. N" — and it is TEXTURE-sampled (RANGETILE "Lv."
		# word-cell + FRAMEFONT digit cells), NOT FONT.BIN glyphs (§15.24 RE30 / user note). ≥2 HUD cells.
		_expect(cj.job_level() > 0 and cj.level_cell_count() >= 2,
			"rotated (prospective) job must show a TEXTURE Lv line (level=%d cells=%d, item 3)"
			% [cj.job_level(), cj.level_cell_count()])

	# Beats 6/7: roster sort-header GONE; ◄L1/R1► pager buttons SHOWN (reused Status chrome).
	_expect(not form._header_visible, "roster sort-header still visible on the Change-Job screen (§15.22)")
	_expect(not form._orbs_visible and not form._box_trail_visible,
		"grid orbs/box not hidden on the Change-Job screen")
	if d != null:
		_expect(d.debug_pager_button_materials().size() > 0,
			"◄L1/R1► pager buttons not present on the Change-Job screen (§15.22 beat 7)")

	# Back-out (×/Esc): the whole screen tears down via an ANIMATED reverse of the entry (§15.24, user
	# 2026-08-08; oracle × back-out tmp/cx_*.png) — NOT an instant snap. Phase 0: the ring SPINS +
	# ENLARGES off-screen FIRST; phase 1: the roster UN-SPLITS back in (top-from-left / bottom-from-right)
	# WHILE the top chrome DESCENDS — the un-split and chrome descent play CONCURRENTLY ("the circle fling
	# happens first THEN the other things go together").
	var exit_front0 := form.changejob_front_index()
	host._exit_changejob_to_main_menu()
	_expect(host.is_changejob_exiting(), "back-out did not start the animated exit (instant snap?)")
	_expect(host.changejob_screen() == null, "title plate not closed at exit start")
	# The plate closes at once but the ring is still on-screen (flinging), NOT cleared instantly.
	_expect(form.changejob_wheel_body_count() > 0, "wheel cleared instantly — the exit must ANIMATE the ring off")
	_expect(form.changejob_exit_k() <= 1.001, "exit k should start at the settled oval (1.0), got %.2f" % form.changejob_exit_k())

	# Phase 0: the ring ENLARGES (k grows past 1) AND SPINS (front advances) as it flies off.
	host.changejob_exit_step()
	_expect(form.changejob_exit_k() > 1.0, "ring did not enlarge on exit (k=%.2f)" % form.changejob_exit_k())
	for _x in ChangeJobWheel.EXIT_DURATION - 1:
		host.changejob_exit_step()
	# After EXIT_DURATION steps the ring reached full extent, the wheel was dropped, phase → un-slide.
	_expect(form.changejob_wheel_body_count() == 0, "ring not cleared after the fling settled")
	_expect(form.changejob_front_index() > exit_front0 + 0.5,
		"ring did not SPIN during the exit (front %.2f → %.2f)" % [exit_front0, form.changejob_front_index()])
	_expect(host.is_changejob_exiting(), "exit ended too early (roster un-slide phase missing)")

	# Phase 1 start: the roster is fully exited again — top-half units off the LEFT (x<0), bottom-half
	# off the RIGHT (x>256), the mirror of the entry split. Stepping the un-slide returns them home.
	var saw_left_return := false
	var saw_right_return := false
	for cell in form.visible_unit_cells():
		if cell == sel:
			continue
		var x0 := form.cell_anchor_screen_px(cell).x
		if cell.y * 2 < form.ROWS:
			if x0 < 0.0:
				saw_left_return = true
		elif x0 > 256.0:
			saw_right_return = true
	_expect(saw_left_return and saw_right_return,
		"roster not off-screen at un-slide start (left=%s right=%s)" % [saw_left_return, saw_right_return])

	# Phase 1: the roster un-slide AND the chrome descent run CONCURRENTLY (user 2026-08-08) — the merged
	# group reversed drives both in the SAME frames. At phase-1 start the chrome is still at TOP (the ring
	# fling didn't touch it); stepping the merged group descends it WHILE the roster returns home.
	var cluster = d._cluster if d != null else null
	var top_ref: float = cluster.vitals_origin_px().y if is_instance_valid(cluster) else 32.0
	var saw_concurrent_descent := false
	for _u in SpriteSlideAnimator.SLIDE_DURATION:
		host.changejob_exit_step()
		var chrome_mid: bool = is_instance_valid(cluster) and cluster.vitals_origin_px().y > top_ref + 2.0
		var roster_off_oval: bool = form.cell_anchor_screen_px(sel).distance_to(centre_origin) > 5.0
		if chrome_mid and host.is_changejob_exiting() and roster_off_oval:
			saw_concurrent_descent = true
	_expect(saw_concurrent_descent,
		"chrome descent and roster un-slide did NOT overlap — they must run CONCURRENTLY (user 2026-08-08)")
	# The merged concurrent group finished in ONE SLIDE_DURATION span → full teardown: wheel cleared,
	# header restored, selected unit back off the oval centre.
	_expect(not host.is_changejob_exiting(), "exit did not settle after fling + concurrent chrome-descent/un-split")
	_expect(host.changejob_screen() == null, "title frame not freed after exit")
	_expect(form.changejob_wheel_body_count() == 0, "wheel not cleared after exit")
	_expect(form._header_visible, "header not restored after exit")
	_expect(form.cell_anchor_screen_px(sel).distance_to(centre_origin) > 5.0,
		"selected unit did not un-slide away from the oval centre after back-out")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationChangeJobTransition test")
	else:
		print("[PASS] FormationChangeJobTransition: split-slide→centre→wheel+title; ring contracts-in (gap2), plate box-opens+Lv (gap1), ←/→ rotates ring+title (gap3)")
	get_tree().quit()
