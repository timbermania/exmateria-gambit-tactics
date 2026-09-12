extends Node3D
# test-kind: logic
# seeded-break: _enter_sub_from_main_menu reassigns the cursor under the cover (selected_cell += Vector2i(1, 0) after parking the menu, never restored) — the stored+mutated-membership bug class the invariant designs out; 'the selected character was REASSIGNED during the transition' and 'the selected character did not survive the round-trip' red, the settled-EQUIP/IDLE state asserts + both cell-membership-set asserts + the concurrency-clean arm stay green

## ADR-0084 invariants 3 & 4 mechanized on the live coordinator (FormationDetailTransition):
##
##   - Invariant 3 (beats never reparent; membership is DERIVED, never mutated). A beat asks "who is
##     my target?" by role each play — the selected unit is never MOVED from one assembly's list to
##     another's. So a full EQUIP round-trip must leave the roster's MEMBERSHIP identical: the same
##     set of occupied cells, and the same character under the selected cell — nothing added, removed,
##     or reassigned. (If membership were stored + mutated, an exit could forget to restore it — the
##     exact bug class the ADR designs out.) The per-unit POSITION byte-restore is the seam test's job;
##     this guards the structural membership on top of it, at the settled screen AND after the exit.
##
##   - Invariant 4 (no element driven by two positional beats at once). The coordinator's real recipe
##     table must be concurrency-clean: within any group, concurrent beats drive disjoint roles. Today
##     every group is a lone beat (trivially clean); the check grows with the recipes. (The disjoint
##     LOGIC itself is unit-tested in FormationTransitionEngineTest.)

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const TransitionEngine = preload("res://src/ui3/formation/FormationTransitionEngine.gd")

const TICK := 2.0 / 60.0
const State = FormationDetailTransition.State

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	await _membership_preserved_no_reparent()
	_recipes_are_concurrency_clean()

	if _failed:
		print("[FAIL] FormationTransitionInvariants test")
	else:
		print("[PASS] FormationTransitionInvariants: membership derived not mutated across an EQUIP round-trip (inv 3), recipe table concurrency-clean (inv 4) (ADR-0084)")
	get_tree().quit()


## Invariant 3 — an EQUIP enter→leave never reparents/reassigns a unit: cell membership + the selected
## character are identical at the settled screen and after the exit.
func _membership_preserved_no_reparent() -> void:
	var host: FormationDetailTransition = await _new_host()
	if host == null:
		return
	var form = host._formation

	var cells_before := _sorted_cells(form)
	var selected_before = form.selected_character()
	var sel_id := _char_id(selected_before)

	# --- enter EQUIP and settle -------------------------------------------------
	host.enter(State.EQUIP)
	_pump_until(host, func(): return host.current_state() == State.EQUIP and not host.is_moving(), 200)
	_expect(host.current_state() == State.EQUIP, "did not reach the settled EQUIP screen")
	_expect(_sorted_cells(form) == cells_before,
		"cell membership CHANGED at the settled EQUIP screen (reparent/reassign) — before %s, now %s"
		% [cells_before, _sorted_cells(form)])
	_expect(_char_id(form.selected_character()) == sel_id,
		"the selected character was REASSIGNED during the transition (was %s, now %s)"
		% [sel_id, _char_id(form.selected_character())])

	# --- leave and settle back to the roster ------------------------------------
	host.leave()
	_pump_until(host, func(): return host.current_state() == State.IDLE and not host.is_moving(), 300)
	_expect(host.current_state() == State.IDLE, "did not settle back to IDLE after leave()")
	_expect(_sorted_cells(form) == cells_before,
		"cell membership NOT restored after the exit — membership was mutated, not derived (before %s, now %s)"
		% [cells_before, _sorted_cells(form)])
	_expect(_char_id(form.selected_character()) == sel_id, "the selected character did not survive the round-trip")

	host.queue_free()
	await get_tree().process_frame


## Invariant 4 — the coordinator's real recipes have no concurrent-target overlap.
func _recipes_are_concurrency_clean() -> void:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host2"
	add_child(host)   # _build_recipes runs synchronously at the top of _ready (before its frame await)
	var conflicts: Array = TransitionEngine.concurrency_conflicts(host.recipe_table())
	_expect(conflicts.is_empty(), "recipe table has concurrent-target conflicts (invariant 4): %s" % str(conflicts))
	host.queue_free()


# -- helpers ------------------------------------------------------------------

func _sorted_cells(form) -> Array:
	var cells: Array = form.visible_unit_cells().duplicate()
	cells.sort()
	return cells

func _char_id(character) -> String:
	if character == null:
		return "<null>"
	# A stable identity for equality across the round-trip — the object itself (never re-created here).
	return str(character.get_instance_id())

func _new_host() -> FormationDetailTransition:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	host.set_process(false)
	if host._formation == null or host._formation.selected_character() == null:
		_expect(false, "no formation/selection")
		host.queue_free()
		return null
	return host

func _pump_until(host: FormationDetailTransition, done: Callable, max_ticks: int) -> void:
	for _i in max_ticks:
		if done.call():
			return
		var d = host.detail_overlay()
		if d != null and is_instance_valid(d):
			d.set_process(false)
			d._process(TICK)
		host._process(TICK)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
