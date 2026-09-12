extends Node3D

## Guard (ADR-0088 Amendment 2 §5/§7 — the START menu's key locations + shared offsets).
##   A. OFFSET DRIVERS — the container-relative offsets shared by every window home
##      (frame inset, title tab offset, row insets) are live `startmenu.*` binds and
##      REAL drivers: scrubbing one re-places its part (chrome element / title element /
##      row block rebuild) and clearing it restores the exact golden layout. This is
##      the write-through that kills the `derived([], …)` empty-drivers silent no-op.
##   B. LOCATION SWEEP + place_at ON THE REAL WIDGET — for each `startmenu.loc.*` home:
##      place_at re-homes the live window onto the location's live value (aperture
##      re-derives), and scrubbing that location moves EVERY quad of the menu by
##      exactly the scrub delta (window at() consumer + riding children/payload),
##      restoring on clear.

const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

var _failed := false


func _ready() -> void:
	await _test_offset_drivers()
	await _test_location_sweep_and_place_at()

	if _failed:
		push_error("[FAIL] StartMenuLocationSweepTest")
		get_tree().quit(1)
	else:
		print("[PASS] StartMenuLocationSweepTest")
		get_tree().quit(0)


## A. The shared offsets are live drivers of their parts.
func _test_offset_drivers() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var base := _positions(m)

	# frame_inset drives the inset chrome ELEMENT (one knob, every variant).
	var fe: UI3Element = m.frame_element()
	_expect(fe != null, "no frame element handle")
	var fr0 := fe.rect()
	Tune.set_value(StartActionMenu.SLUG_FRAME_INSET, Rect2(4, 2, -14, -9))
	_expect(fe.rect() == Rect2(fr0.position + Vector2(2, 0), fr0.size),
		"a frame_inset scrub must re-place the chrome element (+2 x), got %s from %s" % [fe.rect(), fr0])
	Tune.clear(StartActionMenu.SLUG_FRAME_INSET)
	_expect(fe.rect() == fr0, "clearing frame_inset must restore the chrome rect, got %s" % fe.rect())

	# title_tab_offset drives the title ELEMENT.
	var te: UI3Element = m.title_element()
	_expect(te != null, "no title element handle")
	var t0 := te.rect()
	Tune.set_value(StartActionMenu.SLUG_TITLE_TAB_OFFSET, Vector2(6, -1))
	_expect(te.rect().position == t0.position + Vector2(3, 0),
		"a title_tab_offset scrub must re-place the title element (+3 x), got %s from %s"
		% [te.rect(), t0])
	Tune.clear(StartActionMenu.SLUG_TITLE_TAB_OFFSET)
	_expect(te.rect() == t0, "clearing title_tab_offset must restore the title rect, got %s" % te.rect())

	# The row insets rebuild the row block live (no element of their own — payload).
	Tune.set_value(StartActionMenu.SLUG_ROW0_TEXT_INSET_Y, 15.0)
	await get_tree().process_frame
	_expect(_positions(m) != base, "a row0_text_inset_y scrub was a silent no-op")
	Tune.clear(StartActionMenu.SLUG_ROW0_TEXT_INSET_Y)
	await get_tree().process_frame
	_expect(_positions(m) == base, "clearing row0_text_inset_y must restore the golden layout")

	Tune.set_value(StartActionMenu.SLUG_ROW_TEXT_INSET_X, 12.0)
	await get_tree().process_frame
	_expect(_positions(m) != base, "a row_text_inset_x scrub was a silent no-op")
	Tune.clear(StartActionMenu.SLUG_ROW_TEXT_INSET_X)
	await get_tree().process_frame
	_expect(_positions(m) == base, "clearing row_text_inset_x must restore the golden layout")

	m.free()


## B. Every location home: place_at lands on the live value; a location scrub moves
## EVERY quad by exactly the delta (the whole menu answers WHERE by reference).
func _test_location_sweep_and_place_at() -> void:
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var w: UI3Element = m.window()
	_expect(w != null, "no window element")

	var ppu := w.ppu()
	var scrub := Vector2(5, 3)   # display px
	var world_delta := Vector3(scrub.x * ppu, -scrub.y * ppu, 0.0)
	for loc: String in [StartActionMenu.LOC_START, StartActionMenu.LOC_EQUIP,
			StartActionMenu.LOC_ABILITY, StartActionMenu.LOC_MAIN_LEFT,
			StartActionMenu.LOC_MAIN_RIGHT]:
		w.place_at(loc)
		var home: Rect2 = Tune.get_value(loc)
		_expect(w.rect() == home,
			"place_at(%s): window rect %s != the location's live value %s" % [loc, w.rect(), home])
		_expect(w.aperture() == Rect2i(home),
			"place_at(%s): settled aperture %s did not re-derive" % [loc, w.aperture()])

		var before := _positions(m)
		var cursor_before: Vector3 = m.window().get_node("GloveCursor").global_position
		Tune.set_value(loc, Rect2(home.position + scrub, home.size))
		var after := _positions(m)
		var ok := after.size() == before.size() and before.size() > 0
		if ok:
			for i in before.size():
				if ((after[i] - before[i]) - world_delta).length() >= 0.0005:
					ok = false
					break
		_expect(ok, "scrubbing %s must move EVERY menu quad by the delta (at() consumer + riders)" % loc)
		# The glove bobs per frame (its quads are excluded from the multiset) — but its
		# ELEMENT origin must ride the window move like everything else.
		var cursor_after: Vector3 = m.window().get_node("GloveCursor").global_position
		# Report the RATIO, not just the miss. "Did not ride" and "rode TWICE" are opposite
		# defects that this assertion cannot tell apart, and the second is what actually happens
		# when the glove's own `at()` slug IS the one being scrubbed (it moves, and it also rides
		# the parent that moved) — a bare pass/fail sent the last reader hunting the wrong bug.
		var moved: Vector3 = cursor_after - cursor_before
		var ratio := moved.length() / world_delta.length() if world_delta.length() > 0.0 else 0.0
		_expect((moved - world_delta).length() < 0.0005,
			"the cursor element must ride a %s scrub ONCE — moved %s, wanted %s (%.2fx)"
				% [loc, str(moved * 25.0), str(world_delta * 25.0), ratio])
		Tune.clear(loc)
		_expect(_positions(m) == before, "clearing %s must restore the placement" % loc)
	m.free()


func _positions(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		if not is_equal_approx(a.x, b.x): return a.x < b.x
		if not is_equal_approx(a.y, b.y): return a.y < b.y
		return a.z < b.z)
	return out


## Collect quad world positions, EXCLUDING the glove cursor subtree — the glove bobs
## on a per-vsync table (§15.20/ADR-0046), so its quads legitimately differ between
## captures on different frames. Its ride is asserted via the element origin instead.
func _collect(n: Node, out: Array) -> void:
	if n.name == "GloveCursor":
		return
	if n is MeshInstance3D:
		out.append((n as MeshInstance3D).global_position)
	for c in n.get_children():
		_collect(c, out)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[StartMenuLocationSweepTest] %s" % msg)
