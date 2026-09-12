extends Node3D
## Guard: registering elements while the UI3 page is OPEN must not freeze the game.
##
## MEASURED, which is why this exists. With the page open, pressing "Learn" (which registers the
## job picker's window plus its child elements) cost **1.6-2.0 SECONDS**, against 18 ms with the
## page closed. Two multiplying causes:
##
##   * `element_registered` drove a FULL page rebuild, once PER ELEMENT — four signals in one
##     frame meant four whole-page rebuilds, three of them thrown away;
##   * one full rebuild costs ~328 ms for 18 elements / 136 rows, and that is not a hot spot
##     that can be tuned away — it is ~970 Controls being built and entering the tree. Attach
##     cost is linear in what you attach and flat regardless of the tree it joins (measured:
##     ~3 ms per element-sized group whether the page holds 1 group or 8), so there is no
##     quadratic to remove. The only way to make it cheap is to STOP DOING IT.
##
## A registration is ADDITIVE: one element appeared, so one element's rows should appear.
## Measured cost of one element-sized group, built and attached into the live page: ~3.4 ms.
## That is ~100x cheaper than the rebuild it replaces, and needs no chunking or async — the
## work simply is not large once it is scoped to what actually changed.
##
## The risk of incremental update is DRIFT: the page silently showing something a full rebuild
## would not. So the load-bearing assertion here is equality — after an incremental add or
## remove, the page must be indistinguishable from one that had rebuilt from scratch. Every
## other assertion is about cost and coalescing.
##
## Run: <GODOT> --path . --quit-after 200 res://tests/UI3RegistryPageIncrementalTest.tscn

## The WORK a picker-sized registration burst may cost. One full rebuild was ~328 ms and the
## four-per-burst it used to do ~1600 ms; an incremental add is ~3.4 ms per element. 60 ms is
## wide enough never to flake on a slower machine and still 5x under a SINGLE full rebuild, so a
## regression to rebuilding wholesale cannot hide under it.
const BURST_CEILING_MS := 60.0

var _passed := 0
var _failed := 0
var _view: UI3RegistryView = null
var _win: Window = null
var _made: Array = []


func _ready() -> void:
	_win = Window.new()
	_win.size = Vector2i(1241, 900)
	add_child(_win)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(scroll)
	_view = UI3RegistryView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_view)
	_win.show()
	for _i in 4:
		await get_tree().process_frame

	# A realistic starting page: a few roots, each with children.
	for r in range(4):
		var root := _elem("t.inc.r%d" % r)
		add_child(root)
		for c in range(2):
			root.add_child(_elem("t.inc.r%d.c%d" % [r, c]))
	await get_tree().process_frame
	_view.rebuild()
	await get_tree().process_frame

	await _test_a_burst_costs_one_rebuild_not_one_each()
	await _test_incremental_matches_a_full_rebuild()
	await _test_unregister_matches_a_full_rebuild()
	await _test_a_burst_stays_under_the_ceiling()
	await _test_a_big_burst_chunks_across_frames()
	await _test_a_freed_row_is_never_handed_out()
	await _test_a_freed_toggle_does_not_abort_fold_all()
	_finish()


## The coalescing half: N registrations in one frame must not drive N rebuilds.
func _test_a_burst_costs_one_rebuild_not_one_each() -> void:
	var before: int = _view.rebuild_count()
	var burst: Array = []
	for i in range(5):
		var e := _elem("t.inc.burst%d" % i)
		burst.append(e)
		add_child(e)                       # 5 registrations, same frame
	await get_tree().process_frame
	await get_tree().process_frame
	var did: int = _view.rebuild_count() - before
	_expect(did <= 1,
		("a 5-element burst in one frame must cost at most ONE page rebuild, it cost %d. "
		+ "This is the 4x multiplier behind the 1.6 s freeze.") % did)
	for e in burst:
		_expect(_view.element_box(e.id()) != null,
			"every element of the burst must still have a row (%s missing)" % e.id())


## The load-bearing one: incremental must not drift from a full rebuild. Snapshot the page after
## an incremental add, force a full rebuild, and demand the same page.
func _test_incremental_matches_a_full_rebuild() -> void:
	var root := _elem("t.inc.added_root")
	add_child(root)
	var child := _elem("t.inc.r0.added_child")
	_find("t.inc.r0").add_child(child)
	await get_tree().process_frame
	await get_tree().process_frame

	var incremental := _snapshot()
	_view.rebuild()
	await get_tree().process_frame
	var full := _snapshot()
	_expect(incremental == full,
		("an incrementally-updated page must be indistinguishable from a rebuilt one.\n"
		+ "  incremental: %s\n  full rebuild: %s") % [incremental, full])


## ...and the same for removal, which is the easier half to get subtly wrong (a freed box must
## take its bookkeeping with it, including its descendants').
func _test_unregister_matches_a_full_rebuild() -> void:
	var doomed := _find("t.inc.r3")           # a root WITH children — its subtree must go too
	if doomed == null:
		_fail("fixture missing t.inc.r3")
		return
	var gone_ids := ["t.inc.r3", "t.inc.r3.c0", "t.inc.r3.c1"]
	doomed.get_parent().remove_child(doomed)
	doomed.free()
	await get_tree().process_frame
	await get_tree().process_frame

	for id: String in gone_ids:
		var b: Control = _view.element_box(id)
		# A stale dictionary entry pointing at a freed Control is NOT "gone" — it hands out a
		# dangling row to anything that asks. Demand the entry itself be dropped.
		_expect(b == null,
			"an unregistered element must lose its row entry (%s survived as %s)"
				% [id, ("<freed>" if b != null and not is_instance_valid(b) else str(b))])
	var incremental := _snapshot()
	_view.rebuild()
	await get_tree().process_frame
	_expect(incremental == _snapshot(),
		"after an unregister, the page must match a full rebuild.\n  was: %s\n  now: %s"
			% [incremental, _snapshot()])


## The cost assertion, in the shape the user actually hit: a picker-sized burst of
## registrations while the page is open.
##
## The WORK is timed, not the wall-clock of a frame. An idle frame in this harness costs ~66 ms
## all by itself (an agent-launched headful window is present-throttled), so timing
## `await process_frame` would measure the throttle and drown the thing under test — the exact
## mistake that left a 231 ms "cost" mis-attributed in an earlier round. The baseline is
## measured and printed alongside so the two can never be confused again.
func _test_a_burst_stays_under_the_ceiling() -> void:
	# What does a frame cost when NOTHING happens? Everything below is judged against this.
	var b := Time.get_ticks_usec()
	await get_tree().process_frame
	var idle := float(Time.get_ticks_usec() - b) / 1000.0

	var before_rebuilds: int = _view.rebuild_count()
	var t := Time.get_ticks_usec()
	for i in range(4):                        # the job picker registers 4
		add_child(_elem("t.inc.timed%d" % i))
	var press := float(Time.get_ticks_usec() - t) / 1000.0

	# Drain the queued flush synchronously and time IT — this is the work the deferred call
	# would do, with no frame wall-clock mixed in.
	t = Time.get_ticks_usec()
	_view._flush_registry_changes()
	var flush := float(Time.get_ticks_usec() - t) / 1000.0
	var total := press + flush

	_expect(_view.rebuild_count() == before_rebuilds,
		"a burst of registrations must not rebuild the whole page at all (rebuilds went %d -> %d)"
			% [before_rebuilds, _view.rebuild_count()])
	if total <= BURST_CEILING_MS:
		_passed += 1
		print("[ok] a 4-element registration burst cost %.1f ms of WORK (press %.1f + flush %.1f); "
			% [total, press, flush]
			+ "an idle frame in this harness is %.1f ms, and one full rebuild was ~328 ms" % idle)
	else:
		_failed += 1
		print(("[FAIL] a 4-element registration burst cost %.1f ms of work (press %.1f + flush %.1f), "
			+ "ceiling %.0f ms — the page is rebuilding wholesale again")
			% [total, press, flush, BURST_CEILING_MS])
	await get_tree().process_frame


## A burst far bigger than one frame's budget must SPREAD, not stall — and must still arrive
## complete and in registration order. This is the "async" half: no single flush may blow past
## the budget by more than the one element it is always allowed to finish.
func _test_a_big_burst_chunks_across_frames() -> void:
	var ids: Array = []
	for i in range(12):
		var e := _elem("t.inc.big%02d" % i)
		ids.append(e.id())
		add_child(e)

	# The first flush must stop at the budget rather than draining all twelve.
	var t := Time.get_ticks_usec()
	_view._flush_registry_changes()
	var first := float(Time.get_ticks_usec() - t) / 1000.0
	var placed_after_first := 0
	for id: String in ids:
		if _view.element_box(id) != null:
			placed_after_first += 1
	_expect(placed_after_first < ids.size(),
		("a 12-element burst must not all land in ONE flush — the budget is what keeps a frame "
		+ "from stalling (placed %d of %d in %.1f ms)") % [placed_after_first, ids.size(), first])
	_expect(placed_after_first >= 1,
		"a flush must always place at least one element, or the queue can never drain")

	# ...and it must finish, with NO flush overrunning the budget by more than the single element
	# each one is always allowed to complete. Drive the flushes directly and time each: pumping
	# frames instead would measure frame wall-clock, and would pass vacuously if the elements
	# happened to be cheap enough to all fit one flush.
	var flushes: Array = []
	var worst_overrun := 0.0
	var guard_i := 0
	while guard_i < 40:
		var remaining := 0
		for id: String in ids:
			if _view.element_box(id) == null:
				remaining += 1
		if remaining == 0:
			break
		var ft := Time.get_ticks_usec()
		_view._flush_registry_changes()
		var ms := float(Time.get_ticks_usec() - ft) / 1000.0
		flushes.append(ms)
		# A flush may exceed the budget only by the cost of the one element it finishes. Track
		# how far past the budget the SLOWEST went, relative to that flush's own per-element cost.
		if ms > _view.FLUSH_BUDGET_MS:
			worst_overrun = maxf(worst_overrun, ms - _view.FLUSH_BUDGET_MS)
		guard_i += 1

	var missing: Array = []
	for id: String in ids:
		if _view.element_box(id) == null:
			missing.append(id)
	_expect(missing.is_empty(),
		"a chunked burst must eventually place EVERY element; still missing %s after %d flushes"
			% [missing, flushes.size()])
	# One element on a real page costs ~15 ms, so budget + 40 ms is a wide allowance for "the
	# one element a flush is always permitted to finish" without admitting a whole unbudgeted
	# batch (12 elements would be ~180 ms).
	_expect(worst_overrun <= 40.0,
		("no flush may run away past the %.0f ms budget — the worst overran it by %.1f ms, "
		+ "which means the budget check is not stopping the batch. Flushes: %s")
			% [_view.FLUSH_BUDGET_MS, worst_overrun, flushes])
	print("[ok] a 12-element burst drained over %d budgeted flushes (%d placed in the first, %.1f ms); worst overrun %.1f ms"
		% [flushes.size() + 1, placed_after_first, first, worst_overrun])

	# And the chunked result is still the same page a full rebuild would give.
	var chunked := _snapshot()
	_view.rebuild()
	await get_tree().process_frame
	_expect(chunked == _snapshot(),
		"a chunked burst must land the same page as a full rebuild.\n  chunked: %s\n  full: %s"
			% [chunked, _snapshot()])


## element_box() must never hand out a row whose Control has been freed — an entry that answers
## "yes, here it is" with a dangling object is worse than a missing one (reveal_element would
## scroll to nothing, and a guard would assert against a corpse).
func _test_a_freed_row_is_never_handed_out() -> void:
	var victim := _find("t.inc.r0")
	if victim == null:
		_fail("fixture missing t.inc.r0")
		return
	var box: Control = _view.element_box(victim.id())
	_expect(box != null, "fixture element must have a row to begin with")
	if box == null:
		return
	box.get_parent().remove_child(box)
	box.free()                                   # the row is gone; the registry never heard
	_expect(_view.element_box(victim.id()) == null,
		"a freed row must not be handed out even before the prune — the accessor must check validity")

	# Any flush must notice and prune, rather than keep serving the corpse.
	_view._flush_registry_changes()
	_expect(_view.element_box(victim.id()) == null,
		"a freed row must be pruned from element_box(), got %s" % _view.element_box(victim.id()))
	_expect(_view.fold_toggle(victim.id()) == null,
		"a freed row must take its fold toggle with it")
	for r: Dictionary in _view.rows():
		_expect(String(r.get("element_id", "")) != victim.id(),
			"a freed row must not survive in rows() (%s)" % r)
	_view.rebuild()                              # leave the page whole for anything after
	await get_tree().process_frame


## Fold-all walks every collected toggle. If one has been freed, a TYPED read of it raises
## "Trying to assign invalid previously freed instance" and ABORTS the loop — leaving every
## LATER element at whatever fold state it had. That is not hypothetical: the identical ordering
## in UI3OwnerColorMap.deactivate meant one freed payload mesh stopped the map restoring
## anything (see UI3OwnershipMapTest slice 7). This path now runs on every map pick, because a
## pick folds everything before isolating its target.
func _test_a_freed_toggle_does_not_abort_fold_all() -> void:
	_view.rebuild()
	await get_tree().process_frame
	var registry := get_node_or_null("/root/UI3Registry")
	var ids: Array = []
	for e: UI3Element in registry.elements():
		if _view.fold_toggle(e.id()) != null:
			ids.append(e.id())
	_expect(ids.size() >= 3, "fixture needs a few foldable elements, got %d" % ids.size())
	if ids.size() < 3:
		return

	_view._on_unfold_all()
	await get_tree().process_frame
	# Kill ONE element's row out from under the page, without telling it.
	var victim: String = ids[0]
	var box: Control = _view.element_box(victim)
	box.get_parent().remove_child(box)
	box.free()

	# Fold-all must still reach every SURVIVING toggle.
	_view._on_fold_all()
	var still_open: Array = []
	for id: String in ids:
		if id == victim:
			continue
		var t: Button = _view.fold_toggle(id)
		if t != null and t.button_pressed:
			still_open.append(id)
	_expect(still_open.is_empty(),
		("a freed toggle must not abort fold-all — these were never reached: %s") % [still_open])
	_view.rebuild()
	await get_tree().process_frame


## Everything about the page that a full rebuild determines: which elements have rows, in what
## order, with which fold state and which criterion rows. Two pages with the same snapshot are
## the same page as far as anything downstream can tell.
func _snapshot() -> String:
	var parts: Array = []
	var registry := get_node_or_null("/root/UI3Registry")
	for e: UI3Element in registry.elements():
		var box: Control = _view.element_box(e.id())
		if box == null:
			continue
		var t: Button = _view.fold_toggle(e.id())
		# The RENDERED swatch, not _map.owner_color_for() — the point is what the user sees. The
		# owner ramp re-spreads whenever membership changes, so an incremental update that
		# forgets to repaint leaves every existing row wearing a stale colour while the map
		# reports the new one. Comparing the map against itself would call that agreement.
		var sw: ColorRect = _view.owner_swatch(e.id()) as ColorRect
		parts.append("%s[fold=%s,swatch=%s]" % [e.id(),
			("1" if (t != null and t.button_pressed) else "0"),
			(sw.color.to_html(false) if sw != null and is_instance_valid(sw) else "NONE")])
	parts.sort()
	var row_ids: Array = []
	for r: Dictionary in _view.rows():
		row_ids.append("%s/%s" % [r.get("element_id", ""), r.get("field", "")])
	row_ids.sort()
	return "%s || rows=%s" % ["".join(parts), "".join(row_ids)]


func _elem(id: String) -> UI3Element:
	var e := UI3Element.new({
		"id": id,
		"rect": Rect2(0, 0, 8, 8),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_made.append(e)
	return e


func _find(id: String) -> UI3Element:
	var registry := get_node_or_null("/root/UI3Registry")
	for e: UI3Element in registry.elements():
		if e.id() == id:
			return e
	return null


func _expect(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_fail(msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("[FAIL] " + msg)


func _finish() -> void:
	print("\n=== UI3RegistryPageIncrementalTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UI3RegistryPageIncrementalTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3RegistryPageIncrementalTest")
		get_tree().quit(0)
