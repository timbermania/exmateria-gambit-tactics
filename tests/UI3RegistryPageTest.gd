extends Node3D

## Guard (ADR-0088 slice 4b): the UI3 dashboard page — UI3RegistryView is a PURE VIEW
## over the UI3Registry read surface (roots/children_of/criteria).
##   A. Building the view registers NOTHING (no phantom slugs) and renders one row
##      per criterion: AUTHORED rows get an editable TuneField control bound to the
##      minted slug; INHERITED and DERIVED rows are read-only.
##   B. Every write goes through Tune and lands via the element's own on_update
##      (decision 12): editing the rect row's spinbox moves the live element.
##   C. The view rebuilds on register/unregister while visible.
##   D. DebugDashboard grows a 4th page "UI3" hosting the view (ADR-0035 dec. 8).

var _failed := false


func _ready() -> void:
	var win: UI3Element = UI3Element.new({
		"id": "t.pg.win",
		"rect": Rect2(76, 135, 174, 101),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.STRIPE,
		"clip": UI3Element.Clip.OWN_APERTURE,
	})
	add_child(win)
	var child: UI3Element = UI3Element.new({
		"id": "t.pg.win.row",
		"rect": UI3Element.derived([], func() -> Rect2: return Rect2(120, 152, 40, 16)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	win.add_child(child)
	# A plain DERIVED element with real DRIVERS (Amendment 3 §4): its rect is computed
	# from two ordinary pinnable binds — the page must expand them to editable controls
	# so "(derived)" stops being a read-only dead end. Bind the drivers first (the eval
	# reads their live values at adoption).
	Tune.bind("t.pg.drv.x", 120.0, {"step": 1.0})
	Tune.bind("t.pg.drv.y", 152.0, {"step": 1.0})
	var drv: UI3Element = UI3Element.new({
		"id": "t.pg.drv",
		"rect": UI3Element.derived(["t.pg.drv.x", "t.pg.drv.y"],
			func() -> Rect2: return Rect2(Tune.get_value("t.pg.drv.x"), Tune.get_value("t.pg.drv.y"), 40, 16)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	win.add_child(drv)
	# A BOX_OPEN element whose clip is PARENT_APERTURE (Amendment 3 §5): the beat drives
	# an element's OWN aperture, so it is inert here — the page must SAY SO (disable the
	# Open/Close verbs with the reason) rather than offer a button that does nothing.
	var badbox: UI3Element = UI3Element.new({
		"id": "t.pg.badbox",
		"rect": Rect2(80, 140, 40, 20),
		"transition": UI3Element.Transition.BOX_OPEN,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	win.add_child(badbox)
	# An AT_LOCATION element (ADR-0088 Amendment 3 §1): its rect answers at(location) —
	# a SHARED key-location bind owned by another class, distinct from AUTHORED (a minted
	# slug in this element's own spec). Bind the startmenu locations first so the at()
	# eval resolves (and slices 3/5 have a real <ns>.loc.* namespace to enumerate).
	StartActionMenu._bind_locations()
	var atloc: UI3Element = UI3Element.new({
		"id": "t.pg.atloc",
		"rect": UI3Element.at("startmenu.loc.equip"),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	add_child(atloc)
	# A SCREEN_ANCHORED element (ADR-0088 Amendment 4 §1): a screen-anchored assembly with
	# no independent placement — the page must render an honest knob-less row, distinct from
	# the read-only "(derived)" dead-end.
	var anchored: UI3Element = UI3Element.new({
		"id": "t.pg.anchored",
		"rect": UI3Element.screen_anchored(),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(anchored)
	await get_tree().process_frame

	# Slice 1: criteria() reports an at-location rect as Source.AT_LOCATION carrying the
	# location slug — NOT DERIVED with an empty slug (which discarded the name).
	var atloc_rect: Dictionary = {}
	for r: Dictionary in atloc.criteria():
		if r["field"] == "rect":
			atloc_rect = r
	_expect(atloc_rect.get("source") == UI3Element.Source.AT_LOCATION,
		"an at() rect must report Source.AT_LOCATION, got %s" % [atloc_rect])
	_expect(String(atloc_rect.get("slug")) == "startmenu.loc.equip",
		"the at-location rect row must carry the location slug, got %s" % [atloc_rect])

	var view := UI3RegistryView.new()
	add_child(view)

	# A. Pure view: rebuilding registers no new slugs.
	var before: Array = Tune.registered_slugs()
	view.rebuild()
	_expect(Tune.registered_slugs() == before, "the page must never register slugs (pure view)")

	var rows: Array = view.rows()
	_expect(_row(rows, "t.pg.win", "rect")["editable"] == true,
		"the AUTHORED rect row must be editable, got %s" % [_row(rows, "t.pg.win", "rect")])
	_expect(_row(rows, "t.pg.win", "ppu")["editable"] == false
		and _row(rows, "t.pg.win", "ppu")["source"] == UI3Element.Source.INHERITED,
		"the inherited ppu row must be read-only, got %s" % [_row(rows, "t.pg.win", "ppu")])
	_expect(_row(rows, "t.pg.win.row", "rect")["source"] == UI3Element.Source.DERIVED
		and _row(rows, "t.pg.win.row", "rect")["editable"] == false,
		"the derived child rect row must be read-only, got %s" % [_row(rows, "t.pg.win.row", "rect")])
	_expect(not _row(rows, "t.pg.win", "frame").is_empty(),
		"criterion rows must include the frame enum")

	# Slice 2: an AT_LOCATION rect row is EDITABLE — the location value is a real Tune
	# bind (owned by StartActionMenu), so the page binds a TuneField to it. Editing it
	# moves this window AND every rider (it re-authors the shared location definition).
	var atloc_row: Dictionary = _row(rows, "t.pg.atloc", "rect")
	_expect(atloc_row.get("editable") == true,
		"the at-location rect row must be editable (the location value is a bind), got %s" % [atloc_row])
	_expect(atloc_row.get("source") == UI3Element.Source.AT_LOCATION,
		"the at-location row must keep Source.AT_LOCATION in rows(), got %s" % [atloc_row])
	_expect(view.control_for("startmenu.loc.equip") != null,
		"the page must bind a control to the location slug (edit the shared location value)")

	# Slice 3: the AT_LOCATION row offers a RE-HOME dropdown — the element's legal
	# locations (every <ns>.loc.* slug, derived by prefix), invoking place_at. Distinct
	# blast radius from the value edit: re-homes THIS element only, at runtime, not
	# persisted (reboot returns to the host-authored home).
	var dd: OptionButton = view.rehome_dropdown("t.pg.atloc")
	_expect(dd != null, "the at-location row must offer a re-home dropdown")
	if dd != null:
		var listed: Array = []
		for i in dd.item_count:
			listed.append(String(dd.get_item_metadata(i)))
		listed.sort()
		var legal: Array = []
		for s in Tune.registered_slugs():
			if String(s).begins_with("startmenu.loc."):
				legal.append(String(s))
		legal.sort()
		_expect(listed == legal,
			"the dropdown must list exactly the startmenu.loc.* set, got %s vs %s" % [listed, legal])
		var target := "startmenu.loc.ability"
		var idx := -1
		for i in dd.item_count:
			if String(dd.get_item_metadata(i)) == target:
				idx = i
		_expect(idx >= 0, "the dropdown must include the ability home")
		if idx >= 0:
			dd.select(idx)
			dd.item_selected.emit(idx)   # OptionButton.select() does NOT emit — drive it
			_expect(atloc.rect().is_equal_approx(Rect2(Tune.get_value(target))),
				"picking a home must place_at it (rect == that location's live value), got %s" % atloc.rect())

	# Slice 4: a plain DERIVED row (empty location_slug) EXPANDS to its drivers — each
	# is an ordinary pinnable bind rendered as an editable control under the read-only
	# computed value. The rect row itself stays read-only; the drivers are the knobs.
	_expect(_row(rows, "t.pg.drv", "rect")["source"] == UI3Element.Source.DERIVED
		and _row(rows, "t.pg.drv", "rect")["editable"] == false,
		"the derived-with-drivers rect row stays read-only, got %s" % [_row(rows, "t.pg.drv", "rect")])
	_expect(view.control_for("t.pg.drv.x") != null and view.control_for("t.pg.drv.y") != null,
		"a derived row must expose editable controls for each driver (x and y)")

	# Amendment 4 §1 (Option C): a SCREEN_ANCHORED rect row keeps its honest label AND offers
	# the group-nudge <id>.origin knob — editable (moves the whole assembly), NOT a lying
	# width/height and NOT a read-only "(derived)" dead-end.
	var anch_row: Dictionary = _row(rows, "t.pg.anchored", "rect")
	_expect(anch_row.get("source") == UI3Element.Source.SCREEN_ANCHORED,
		"the screen-anchored rect row must keep Source.SCREEN_ANCHORED, got %s" % [anch_row])
	_expect(anch_row.get("editable") == true,
		"the screen-anchored rect row must offer the editable origin knob, got %s" % [anch_row])
	_expect(view.control_for("t.pg.anchored.origin") != null,
		"the page must bind a control to the <id>.origin group-nudge slug")
	var anch_box: Control = view.element_box("t.pg.anchored")
	_expect(anch_box != null, "the screen-anchored element must render a box")
	if anch_box != null:
		_expect(_box_has_label_containing(anch_box, "screen-anchored"),
			"the screen-anchored row must render an honest 'screen-anchored' label")
		_expect(not _box_has_label_containing(anch_box, "(derived)"),
			"the screen-anchored row must NOT render the (derived) dead-end tag")

	# Slice 5: a location-registry SECTION lists every registered *.loc.* slug + value,
	# editable in one place (so tuning a location is not an element-by-element hunt).
	var loc_slugs: Array = view.location_slugs()
	for known in ["startmenu.loc.start", "startmenu.loc.equip", "startmenu.loc.ability",
			"startmenu.loc.main_left", "startmenu.loc.main_right"]:
		_expect(loc_slugs.has(known),
			"the location section must list the registered location %s, got %s" % [known, loc_slugs])
		_expect(view.location_control_for(known) != null,
			"each location-section slug must expose an editable control (%s)" % known)
	for s in loc_slugs:
		_expect(String(s).contains(".loc."),
			"the location section must list ONLY location slugs, got %s" % s)
	# Read-only OWNER: which class DEFINES each location (derived from its bind site, not
	# a name transform) so it is clear what position goes to what — the section shows it,
	# and the AT_LOCATION element row names its location's owner too.
	_expect(view.location_owner("startmenu.loc.equip") == "StartActionMenu",
		"the location section must show the owning class (read-only), got %s"
		% view.location_owner("startmenu.loc.equip"))
	_expect(_row(rows, "t.pg.atloc", "rect").get("owner", "") == "StartActionMenu",
		"the at-location row must carry its location's owner, got %s"
		% [_row(rows, "t.pg.atloc", "rect")])

	# Slice E: the owner-knob section. Two directions, because either alone is vacuous — a
	# section that listed EVERY registered slug would pass the "is my knob there" half and be
	# a duplicate of the tunables registry page, and one that listed none would pass the
	# "no duplicates" half.
	UI3MoveSlideBeat.back_overshoot()   # force the shared engine's own binds to exist
	Tune.bind("t.pg.owner_knob", 3.0, {"min": 0.0, "max": 9.0, "step": 0.5})
	view.rebuild()
	var knobs: Array = view.owner_knob_slugs()
	_expect(knobs.has("t.pg.owner_knob"),
		"a class-owned slug in an element's namespace must get an owner-knob row, got %s" % [knobs])
	_expect(view.control_for("t.pg.owner_knob") != null,
		"each owner-knob row must expose an editable TuneField control")
	# The shared engines' own knobs ride in on the `ui3` namespace, which is on the page whether
	# or not any element is literally named `ui3.*` — every element uses them.
	_expect(knobs.has(UI3MoveSlideBeat.BACK_OVERSHOOT_SLUG),
		"the `ui3` engine namespace must be surfaced too, got %s" % [knobs])
	# ...and the exclusions. A driver slug is already editable under its derived row and a
	# location slug under the section above; listing either again is how a "one place for the
	# knobs" section becomes two places for some of them.
	_expect(not knobs.has("t.pg.drv.x"),
		"a slug already editable as a DRIVER row must not be repeated as an owner knob")
	for k in knobs:
		_expect(not String(k).contains(".loc."),
			"the key-location section owns .loc. slugs; the owner-knob section listed %s" % k)

	# Slice 6: beat.precondition makes Open/Close honest. Pure-assert the BOX_OPEN beat's
	# precondition: met (empty) on an OWN_APERTURE element, unmet (a reason) otherwise.
	var box_beat := UI3BoxOpenBeat.new()
	_expect(box_beat.precondition(win) == "",
		"BOX_OPEN precondition must be met on an OWN_APERTURE element, got %s" % box_beat.precondition(win))
	var bad_precond: String = box_beat.precondition(badbox)
	_expect(bad_precond != "" and bad_precond.to_lower().contains("aperture"),
		"BOX_OPEN precondition must be unmet (with an aperture reason) on a PARENT_APERTURE element, got %s" % bad_precond)
	# The page disables the verb buttons WITH the reason on that element.
	var bad_verbs: Dictionary = view.verb_buttons("t.pg.badbox")
	_expect(bad_verbs.has("open") and (bad_verbs["open"] as Button).disabled
		and (bad_verbs["close"] as Button).disabled,
		"an unmet-precondition element must have its Open/Close verbs disabled, got %s" % [bad_verbs])
	var bad_reason: String = view.verb_reason("t.pg.badbox")
	_expect(bad_reason.to_lower().contains("aperture"),
		"the disabled verbs must state the reason, got %s" % bad_reason)
	# A RIDE_PARENT child's verbs are inert BY DECLARATION ("reveals with its parent").
	var child_verbs: Dictionary = view.verb_buttons("t.pg.win.row")
	_expect((child_verbs["open"] as Button).disabled,
		"a RIDE_PARENT element's verbs must be inert (reveals with its parent)")
	_expect(view.verb_reason("t.pg.win.row").to_lower().contains("parent"),
		"a RIDE_PARENT element's verb reason must say it reveals with its parent, got %s"
		% view.verb_reason("t.pg.win.row"))
	# The BOX_OPEN + OWN_APERTURE window's verbs stay ENABLED (precondition met).
	_expect(not (view.verb_buttons("t.pg.win")["open"] as Button).disabled,
		"a met-precondition BOX_OPEN element keeps its verbs enabled")

	# B. A view edit lands on the element THROUGH Tune (decision 12): drive the rect
	# row's x spinbox and watch the origin move.
	var rect_control: Control = view.control_for("t.pg.win.rect")
	_expect(rect_control != null, "the rect row must expose its bound control")
	if rect_control != null:
		var sb: SpinBox = null
		for c in rect_control.get_children():
			if c is SpinBox:
				sb = c
				break
		_expect(sb != null, "the rect control must be per-component spinboxes")
		if sb != null:
			sb.value = 100.0   # SpinBox .value= EMITS (the known gotcha) — that IS the edit path
			_expect(win.position.is_equal_approx(Vector3(4.0, -5.4, 0.0)),
				"a page edit must move the element via its own on_update, got %s" % win.position)
			Tune.clear("t.pg.win.rect")

	# E. Per-element Open/Close VERB buttons (ADR-0088 amendment §6): the page INVOKES
	# the element's verbs — a verb is not a write, the page stays a pure view. This
	# closes the "I set it to box open — it just binary turns on" dead end: the
	# transition enum DECLARES, the buttons INVOKE.
	var verbs: Dictionary = view.verb_buttons("t.pg.win")
	_expect(verbs.has("open") and verbs["open"] is Button and verbs.has("close") and verbs["close"] is Button,
		"each element row must offer Open/Close verb buttons, got %s" % [verbs])
	var slugs_before_verbs: Array = Tune.registered_slugs()
	if verbs.has("open"):
		(verbs["open"] as Button).pressed.emit()
		_expect(not win.is_settled(),
			"the Open button must INVOKE the declared BOX_OPEN beat (element unsettled)")
		for i in 12:
			UI3Registry.transition_engine_step()
		_expect(win.is_settled(), "the invoked open must settle through the engine")
		(verbs["close"] as Button).pressed.emit()
		_expect(not win.is_settled(), "the Close button must invoke the reversed beat")
		for i in 12:
			UI3Registry.transition_engine_step()
		_expect(win.aperture().size == Vector2i.ZERO,
			"the invoked close must end shut, got %s" % win.aperture())
		win.open()
		for i in 12:
			UI3Registry.transition_engine_step()
	_expect(Tune.registered_slugs() == slugs_before_verbs,
		"verb buttons must register nothing (a verb is not a write)")

	# F. Clip-mode legibility (amendment §6): the clip criterion row explains the
	# modes in a tooltip instead of a bare enum int.
	var clip_row: Dictionary = _row(view.rows(), "t.pg.win", "clip")
	_expect(not clip_row.is_empty(), "clip criterion row missing")
	var clip_tip: String = view.row_tooltip("t.pg.win", "clip")
	_expect(clip_tip.to_lower().contains("aperture"),
		"the clip row must carry a mode-explaining tooltip, got %s" % [clip_tip])
	var tr_tip: String = view.row_tooltip("t.pg.win", "transition")
	_expect(tr_tip.to_lower().contains("open"),
		"the transition row tooltip must point at the Open/Close verbs, got %s" % [tr_tip])

	# G. Tree shape: a nested element's box renders INSIDE its parent's fold — the
	# parent header sits ABOVE its children and collapsing the parent hides them
	# (the old code appended every box to the top-level list, children first).
	var parent_box: Control = view.element_box("t.pg.win")
	var child_box: Control = view.element_box("t.pg.win.row")
	_expect(parent_box != null and child_box != null,
		"element_box must expose each element's rendered fold")
	if parent_box != null and child_box != null:
		_expect(parent_box.is_ancestor_of(child_box),
			"the child element's box must nest under the parent's fold (window above its sub-elements)")
		_expect(not _tree_children(view).has(child_box),
			"a nested element's box must not sit at the top level of the list")

	# H. Ownership map (ADR-0088 Amendment 6): the page renders an owner-color SWATCH + a
	# MUTE toggle per element row, a page-wide map toggle + Clear-all, and stays a PURE VIEW
	# — it drives a debug-only mechanism (UI3OwnerColorMap) that swaps live-mesh materials /
	# visibility, so NO debug state lands on UI3Registry and nothing registers.
	var win_swatch: Control = view.owner_swatch("t.pg.win")
	_expect(win_swatch is ColorRect, "each element row must render an owner-color swatch")
	var win_col: Color = view.owner_color("t.pg.win")
	_expect((win_swatch as ColorRect).color.is_equal_approx(win_col),
		"the swatch color must equal the element's assigned owner color (legend == on-screen)")
	_expect(not win_col.is_equal_approx(view.owner_color("t.pg.atloc")),
		"sibling elements must get distinct owner colors")
	_expect(not win_col.is_equal_approx(UI3OwnerColors.ALARM),
		"an owned element's color must never be the reserved alarm color")

	# The page-wide map toggle activates/deactivates the map and registers NOTHING.
	var slugs_before_map: Array = Tune.registered_slugs()
	_expect(view._map_toggle != null, "the page must offer a page-wide ownership-map toggle")
	view._map_toggle.button_pressed = true   # emits toggled
	_expect(view.map_active(), "toggling the map on must activate it")
	_expect(Tune.registered_slugs() == slugs_before_map,
		"the map toggle must register nothing (pure view)")
	view._map_toggle.button_pressed = false
	_expect(not view.map_active(), "toggling the map off must deactivate it")

	# The per-row Mute toggle drives that element's mute state (a verb, pure view).
	var mute_btn: Button = view.mute_button("t.pg.win")
	_expect(mute_btn != null and mute_btn.toggle_mode, "each element row must offer a Mute toggle")
	mute_btn.button_pressed = true
	_expect(view.muted_ids().has("t.pg.win"), "pressing Mute must mute that element")
	mute_btn.button_pressed = false
	_expect(not view.muted_ids().has("t.pg.win"), "un-pressing Mute must unmute")

	# Clear all drops the map AND every mute, and resets the toggle.
	view._map_toggle.button_pressed = true
	view.mute_button("t.pg.win").button_pressed = true
	view._clear_btn.pressed.emit()
	_expect(not view.map_active() and view.muted_ids().is_empty(),
		"Clear all must drop the map and every mute")
	_expect(not view._map_toggle.button_pressed, "Clear all must reset the map toggle")

	# Auto-clear on page-hide (§4): hiding the page restores the live game — map off,
	# nothing muted — so the user never leaves a debug view altering the game.
	view._map_toggle.button_pressed = true
	view.mute_button("t.pg.win").button_pressed = true
	view.visible = false
	await get_tree().process_frame
	_expect(not view.map_active() and view.muted_ids().is_empty(),
		"hiding the page must auto-clear the map and every mute")
	view.visible = true
	await get_tree().process_frame

	# I. Non-scrolling top bar (handoff #2/#3): the Ownership-map toggle, Clear all, and
	# the new Fold-all / Unfold-all buttons live in a PINNED header bar — NOT in the
	# scrolling row tree — so they stay reachable however far the element list scrolls.
	var bar: Control = view.header_bar()
	_expect(bar != null, "the view must expose a pinned header bar")
	if bar != null:
		_expect(bar.is_ancestor_of(view._map_toggle) and bar.is_ancestor_of(view._clear_btn),
			"the map toggle + Clear all must live in the pinned header bar")
		_expect(not view._body_scroll.is_ancestor_of(view._map_toggle),
			"the header chrome must NOT sit inside the scrolling body")
		_expect(view.fold_all_button() != null and view.unfold_all_button() != null,
			"the top bar must offer Fold all / Unfold all buttons")
		_expect(bar.is_ancestor_of(view.fold_all_button()) and bar.is_ancestor_of(view.unfold_all_button()),
			"Fold all / Unfold all must live in the pinned header bar too")
	# Unfold all -> every element box (incl. nested) is shown; Fold all -> nested content
	# hides and only root headers remain (roots stay open).
	view.unfold_all_button().pressed.emit()
	_expect(view.element_box("t.pg.win.row").is_visible_in_tree(),
		"Unfold all must reveal nested element boxes")
	view.fold_all_button().pressed.emit()
	_expect(view.element_box("t.pg.win").is_visible_in_tree(),
		"Fold all keeps root headers visible")
	_expect(not view.element_box("t.pg.win.row").is_visible_in_tree(),
		"Fold all must hide nested element boxes (parent collapsed)")
	view.unfold_all_button().pressed.emit()   # restore expanded for later sections

	# C. Rebuild on register while visible.
	var n_before: int = view.rows().size()
	var late: UI3Element = UI3Element.new({
		"id": "t.pg.late",
		"rect": Rect2(0, 0, 8, 8),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	add_child(late)
	await get_tree().process_frame
	_expect(view.rows().size() > n_before,
		"a registration while visible must rebuild the page (rows %d -> %d)"
		% [n_before, view.rows().size()])
	late.free()

	# D. The dashboard hosts the page as its 4th button — and switching to it with live
	# elements RENDERS them (the user-visible path, not just the scroll host flag).
	var dash := DebugDashboard.new()
	add_child(dash)
	await get_tree().process_frame
	var labels: Array = []
	for b in dash._page_buttons:
		labels.append((b as Button).text)
	_expect(labels.has("UI3"), "DebugDashboard must offer the UI3 page button, got %s" % [labels])
	dash._set_page(labels.find("UI3"))
	_expect(dash._ui3_view != null and dash._ui3_view.visible,
		"switching to the UI3 page must show the view (which owns its own scrolling body)")
	_expect(dash._ui3_view.rows().size() > 0,
		"switching to the UI3 page with live elements must render their rows, got %d"
		% dash._ui3_view.rows().size())

	# With NOTHING registered the page must say so, not render a silent blank.
	win.free()
	atloc.free()
	anchored.free()
	await get_tree().process_frame
	dash._set_page(labels.find("UI3"))
	_expect(dash._ui3_view.rows().is_empty(), "no elements -> no rows")
	_expect(dash._ui3_view.empty_state_label() != null,
		"an empty registry must render the explanatory empty state")
	dash.queue_free()

	if _failed:
		push_error("[FAIL] UI3RegistryPageTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3RegistryPageTest")
		get_tree().quit(0)


func _tree_children(view: UI3RegistryView) -> Array:
	return view._tree_box.get_children()


func _box_has_label_containing(root: Node, needle: String) -> bool:
	if root is Label and String((root as Label).text).to_lower().contains(needle.to_lower()):
		return true
	for c in root.get_children():
		if _box_has_label_containing(c, needle):
			return true
	return false


func _row(rows: Array, elem_id: String, field: String) -> Dictionary:
	for r: Dictionary in rows:
		if r["element_id"] == elem_id and r["field"] == field:
			return r
	return {}


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3RegistryPageTest] %s" % msg)
