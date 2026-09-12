extends Node3D
# test-kind: logic
# seeded-break: disabled the roster-host enter(DETAIL) build (elif false around open_detail in FormationDetailTransition.enter); the 'overlay created / docked pair+readouts+header hidden / Esc started a close' asserts red, the S2 latch + state asserts stay green

## FormationDetailTransition host guard (headful) — the end-to-end ○-press wire
## (FORMATION_SCREEN.md §15.5): a formation ○-press opens a DetailScene overlay bound
## to the selected unit and starts the slide transition, and Esc closes it back to the
## roster. Proves the WIRING + view threading; the transition's own phase ordering is
## guarded by DetailTransitionTest.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

const TICK := 2.0 / 60.0   # one menu tick (drives the reverse transition by hand)

var _failed := false


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
	# Let the host _ready finish (it awaits a frame before seeding the roster).
	for _i in 4:
		await get_tree().process_frame

	var form = host._formation
	_expect(form != null and form.selected_character() != null,
		"host has no formation / no selected unit after ready")
	var sel = form.selected_character()

	# --- S2: the sort-header visibility latch (§15.22) — hidden while the Status screen is up,
	# and a sort-page rebuild (`_build_sort_header`) must honour the latch, not re-show it. Tested
	# on the real header in isolation (direct API), independent of the transition wiring below.
	_expect(form.is_header_visible() and form._header_root != null and form._header_root.visible,
		"sort-header should start visible")
	form.set_header_visible(false)
	_expect(not form.is_header_visible() and not form._header_root.visible,
		"set_header_visible(false) did not hide _header_root")
	form._build_sort_header()   # a rebuild while hidden must stay hidden (latched, like the readouts)
	_expect(not form.is_header_visible() and not form._header_root.visible,
		"sort-header re-appeared after a rebuild while hidden")
	form.set_header_visible(true)
	_expect(form.is_header_visible() and form._header_root.visible,
		"set_header_visible(true) did not restore the header")

	# --- Enter/○ on the roster opens the detail overlay + starts the transition ---
	form._unhandled_input(_action("ui_accept"))
	var d = host.detail_overlay()
	_expect(d != null, "○-press did not create a DetailScene overlay")
	if d != null:
		# The overlay's shared pair starts DOCKED (over the formation's pair) and the
		# lower Eqp/Ability panel is CLOSED — the transition is mid-slide, not settled.
		_expect(d._cluster != null and d._cluster.vitals_origin_px().is_equal_approx(Vector2(13, 177)),
			"overlay cluster not docked at transition start (%s)" % (d._cluster.vitals_origin_px() if d._cluster else "none"))
		_expect(d._open_root != null and d.lower_aperture().size == Vector2i.ZERO,
			"overlay lower panel not closed at transition start (aperture=%s)" % d.lower_aperture())
		# Views were threaded (the vitals panel got the selected unit's view).
		_expect(not d._unit_view.is_empty(), "overlay vitals view not bound from the selected unit")
	# The formation's own docked pair is hidden so the pair doesn't double-draw.
	_expect(form._cluster != null and not form._cluster.visible,
		"formation docked pair not hidden during the transition")
	# The grid's per-unit HP readouts blank while the overlay is up (unit sprites stay).
	_expect(not form._cell_readouts_visible,
		"grid HP readouts not hidden while the detail overlay is up")
	# S4 (§15.22): the roster sort-header is HIDDEN entirely (the Status screen shows its own
	# ◄L1/R1► corner buttons instead), and the formation must NOT go to background on detail-open —
	# backgrounding is a MENU-open concern only (retires commit 863427d11's open_detail wiring).
	_expect(not form.is_header_visible(),
		"sort-header not hidden while the detail overlay is up (§15.22)")
	_expect(not form.is_backgrounded(),
		"formation backgrounded on detail-open — must blue on menu-open only (§15.22)")

	# --- START opens the §15.20 action menu OVER the detail screen ---------------
	host._input(_action("formation_start_menu"))
	var menu = host.action_menu()
	_expect(menu != null, "START did not open the action menu over the detail screen")
	if menu != null:
		_expect(menu.selected_row() == 0, "action menu did not start on row 0 (Item)")
		# While the menu owns the pad, ↓ moves the MENU selection (not the roster behind it).
		host._input(_action("ui_down"))
		_expect(menu.selected_row() == 1, "↓ did not move the action-menu selection (got %d)" % menu.selected_row())
		# ○/Enter on an OUT-OF-SCOPE row (3 = "Remove Unit") reports the choice and closes back to
		# the detail screen. Rows 0-2 are real sub-screen ENTRIES (Item/Ability/Change Job) — this
		# section is about the menu itself, so it must not walk onto another screen: the Esc check
		# below is the DETAIL reverse, and from a sub-screen `leave()` would correctly unwind instead.
		host._input(_action("ui_down"))
		host._input(_action("ui_down"))
		_expect(menu.selected_row() == 3, "↓ did not reach the out-of-scope row (got %d)" % menu.selected_row())
		host._input(_action("ui_accept"))
		_expect(host.action_menu() == null, "confirm did not close the action menu")
		_expect(host.detail_overlay() != null, "confirm wrongly tore down the detail overlay")
		_expect(host.current_state() == FormationDetailTransition.State.DETAIL,
			"confirming an out-of-scope row left the coordinator on %d, not DETAIL" % host.current_state())

	# Re-open, then △/Esc CANCELS the menu — back to the detail screen, NOT closing it.
	host._input(_action("formation_start_menu"))
	_expect(host.action_menu() != null, "START did not re-open the action menu")
	host._input(_action("ui_cancel"))
	_expect(host.action_menu() == null, "△/Esc did not close the action menu")
	_expect(host.detail_overlay() != null, "cancelling the menu wrongly closed the detail overlay")

	# --- Backspace/✕ closes the overlay by playing the transition in REVERSE -----
	form._unhandled_input(_action("ui_cancel"))
	var closing = host.detail_overlay()
	_expect(closing != null, "Esc did not start a close (overlay already gone)")
	# Pump the reverse transition (box-close → gap → slide-down) to completion; the overlay
	# frees itself via the `closed` signal, so drive it by hand until the host drops it.
	if closing != null:
		for _i in 80:
			if host.detail_overlay() == null:
				break
			closing._process(TICK)
	_expect(host.detail_overlay() == null,
		"reverse transition did not finish / overlay not freed")
	_expect(form._cluster != null and form._cluster.visible,
		"formation docked pair not restored after closing detail")
	_expect(form._cell_readouts_visible,
		"grid HP readouts not restored after closing detail")
	_expect(form.is_header_visible(),
		"sort-header not restored after closing the detail overlay (§15.22)")
	# (sel is only used to prove selection resolved; the overlay bound the same unit.)
	_expect(sel != null, "selected unit vanished")

	if _failed:
		print("[FAIL] FormationDetailTransition test")
	else:
		print("[PASS] FormationDetailTransition: ○-press → detail overlay + slide, Esc closes (§15.5)")
	get_tree().quit()


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
