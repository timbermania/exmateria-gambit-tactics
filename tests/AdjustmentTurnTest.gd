extends Node
# test-kind: logic
# seeded-break: drop the ownership term of the conjunction in src/gpu/AdjustmentTurn.gd:87 (`if not owned:` -> `if false:`), leaving the taker/phase term intact — exactly the 'cheap wrong version' arm 1 exists to falsify; 'deploying, an enemy is still not editable' and 'ownership still bites for the taker' red (got=false want=true), while every phase arm that turns on the SECOND term stays green, which is what shows the arms separate the two. And for arms 8-11 (#1006): set `if spent > 0:` to `if false:` in src/gpu/ImperativeGambits.gd's `cancel()`, so the turn's charges are never given back — 4 assertions red, all inside the refund arm, while `cancel()`'s RETURN value stays correct and green, which is what shows the arms separate the report from the effect
## Pure-logic guard for the ADJUSTMENT TURN — the turn as an editing window (#894, design §4).
##
## [TurnDirector] decides WHEN the world is frozen; [AdjustmentTurn] decides what the player may do
## with the freeze, and it is the second half of a pre-turn image whose first half is already
## ADR-0235's GPU snapshot. No scene, no map, no GPU: every arm below is a function of a
## [Character], a taker index and a stub simulator, which is the design's own claim — the CPU half
## of an undo is not in any SSBO.
##
## The arms, and what each one falsifies:
##
##   1. STEERABILITY IS A CONJUNCTION, and both terms bite. Not-owned is refused in every phase;
##      owned-but-between-turns is refused; owned-on-somebody-else's-turn is refused; owned-on-your
##      -own-turn is allowed; deployment allows the whole owned squad. The cheap wrong version
##      (reuse `selection_is_owned`) passes three of those five and hands your fastest unit a
##      universal remote.
##   2. CANCEL RESTORES THE SAME OBJECT. The edit is undone AND `character` is the instance every
##      holder still points at — the roster index, the owned overlay and the battlefield [Unit] all
##      hold that reference (ADR-0005), so the `from_dict`-mints-a-new-one implementation passes an
##      equality check and leaves three holders looking at the state it was asked to undo. This arm
##      asserts the instance id, which is the only thing that separates them.
##   3. AN UNTOUCHED TURN COSTS NOTHING, and a touched one writes BOTH buffers. The gambit list is
##      not in the unit block — it is its own SSBO — so a commit that called only
##      `reconfigure_unit_from` would land half an edit, and the stub counts them separately.
##   4. THE WINDOW CLOSES ONCE. Commit then cancel does not resurrect the pre-turn image and
##      un-land what was just landed; a second commit writes nothing.
##   5. THE PRUNE DROPS ONLY STALE ABILITIES. ATTACK / MOVE / WAIT are job-independent verbs and
##      survive any job change; an ability the new job cannot perform goes; one it can stays. The
##      implementation that prunes on `action_kind != ATTACK` deletes the player's MOVE rows.
##   6. THE PRUNE REPORTS. It returns the dropped rows, because design §4 rules that a silent
##      no-op slot is worse than either refusing the job change or arguing with the player — a
##      bool cannot be shown.
##   7. THE USABLE SET IS PRIMARY ∪ SECONDARY, read from the real job + ability tables. If
##      `jobs.json`/`abilities.json` drift, every id below is measuring an invented skillset.
##
## Arms 8-11 are [ImperativeGambits] (#1006, design §5) — the same shape of subject and the SAME
## setup, so they share this process rather than paying another 2.3 s boot for a second one (test
## charter clause 13). It is the third half of the pre-turn image the two classes split between
## them, and the arms are written against the seam:
##
##   8. CHARGES ARE FINITE AND PER UNIT. A unit spends its allowance and is then refused; its
##      neighbour still has a full one. The implementation that keeps one counter for the battle
##      passes every arm about a single unit and hands the squad one shared lock-on.
##   9. THE REFUND IS THE TURN'S, AND ONLY THE TURN'S. Cancel gives back every charge spent since
##      `open` — two, if the player re-aimed twice — and puts back the order that stood BEFORE the
##      turn rather than merely clearing the new one. `close` gives back nothing. The one-charge
##      refund passes the common case and silently eats the second.
##  10. THE WATCHDOG TAKES THE ORDER AND NEVER THE CHARGE. Design §5: "a wasted lock-on is a real
##      mistake". Both triggers are separated — a passed deadline with a live pool, and a dead pool
##      inside the deadline — so an implementation that only ever tests one still reds.
##  11. THE IMPERATIVE IS A LEAD ENTRY AND COSTS NO SLOT. `encode_for_unit` puts it at index 0,
##      where the shader looks first, and every authored slot survives behind it. Read off the
##      ENCODER, because "above the standing list" is a claim about the buffer.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/AdjustmentTurnTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const Gambit = ExMateriaAlmanac.Gambit
const GambitList = ExMateriaAlmanac.GambitList
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

const Character = ExMateriaCatalogue.Character
const ImperativeGambits = preload("res://src/gpu/ImperativeGambits.gd")
const TargetSelector = ExMateriaAlmanac.TargetSelector

## Squire and Wizard — two GENERIC jobs with disjoint action skillsets, which is what makes an
## ability of one provably unusable by the other. Read from the tables at run time; these ids are
## the KEY into the data, not a copy of it.
const SQUIRE_JOB := "4a"
const WIZARD_JOB := "4d"

var _passed: int = 0
var _failed: int = 0
## Stub units, freed at the end — real `Node`s so `name` behaves as it does for a [Unit].
var _made: Array[Node] = []


## A simulator that does nothing but count. `AdjustmentTurn.commit` takes its simulator untyped for
## exactly this reason: the thing under test is which calls it makes, not what they do.
class StubSim extends RefCounted:
	var reconfigured: Array = []
	var gambits_set: Array = []
	func reconfigure_unit_from(battle_id: int, unit_idx: int, _unit) -> bool:
		reconfigured.append([battle_id, unit_idx])
		return true
	## The encoded buffer of the LAST push, kept whole so an arm can ask what led it — the size is
	## fixed at `MAX_USER_GAMBITS + 1` and can never witness a lead entry (#1006).
	var last_gambits: Array = []
	func set_unit_gambits(battle_id: int, unit_idx: int, gambits: Array) -> void:
		gambits_set.append([battle_id, unit_idx, gambits.size()])
		last_gambits = gambits


func _ready() -> void:
	_test_steerability_is_a_conjunction()
	_test_cancel_restores_the_same_object()
	_test_untouched_costs_nothing_touched_writes_both()
	_test_the_window_closes_once()
	_test_the_prune_drops_only_stale_abilities()
	_test_the_usable_set_is_primary_union_secondary()
	_test_charges_are_finite_and_per_unit()
	_test_the_refund_is_the_turns_and_only_the_turns()
	_test_the_watchdog_takes_the_order_and_never_the_charge()
	_test_the_imperative_is_a_lead_entry_and_costs_no_slot()

	for node in _made:
		node.free()
	_made.clear()

	print("\n=== AdjustmentTurnTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] AdjustmentTurnTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] AdjustmentTurnTest")
		get_tree().quit(1)
	else:
		print("[PASS] AdjustmentTurnTest: steerability / in-place cancel / two-buffer commit / prune + report")
		get_tree().quit(0)


# === Arms =====================================================================

## Both terms of the conjunction bite, in all three phases.
func _test_steerability_is_a_conjunction() -> void:
	var a := AdjustmentTurn.new()

	# RUNNING — no turn open. Nobody is editable, owned or not.
	_true(not a.steerable(0, true, false), "between turns, your own unit is not editable")
	_true(not a.steerable(0, false, false), "between turns, an enemy is not editable")

	# DEPLOYMENT — the whole owned squad, and still nobody else's.
	_true(a.steerable(3, true, true), "deploying, an owned unit is editable")
	_true(not a.steerable(3, false, true), "deploying, an enemy is still not editable")

	# TURN_OPEN on unit 2.
	a.open(2, _fixture(SQUIRE_JOB))
	_true(a.steerable(2, true, false), "on your turn, the taker is editable")
	_true(not a.steerable(1, true, false), "on your turn, another owned unit is NOT editable")
	_true(not a.steerable(2, false, false), "ownership still bites for the taker")
	_eq(a.taker(), 2, "the window names its taker")
	_true(a.is_open(), "the window is open")


## Undo restores the state AND keeps the instance.
func _test_cancel_restores_the_same_object() -> void:
	var a := AdjustmentTurn.new()
	var c := _fixture(WIZARD_JOB)
	var id_before := c.get_instance_id()
	var job_before: String = c.progression.current_job_id
	var gambits_before: int = c.gambits.size()
	_true(job_before != "4a", "the fixture's job is NOT UnitProgression's default — a blank "
		+ "progression must not be able to read as a successful restore")

	a.open(0, c)
	# The edit, as the formation screen makes it: straight through to the durable Character.
	c.progression.current_job_id = SQUIRE_JOB
	c.progression.equipment[UnitProgression.EquipSlot.RIGHT_HAND] = 999
	c.progression.level = 99
	c.gambits.add(_ability_gambit(_first_action(SQUIRE_JOB)))
	_true(c.progression.current_job_id == SQUIRE_JOB, "the edit landed on the Character")

	_true(a.cancel(c), "cancel had an image to restore")
	_eq(c.progression.current_job_id, job_before, "the job came back")
	_eq(int(c.progression.equipment.get(UnitProgression.EquipSlot.RIGHT_HAND, -1)), -1,
		"the equipment came back")
	_eq(c.gambits.size(), gambits_before, "the gambit list came back")
	# Stats too, and at values no blank progression carries: a restore that installs a DEFAULT
	# UnitProgression rather than the image's would pass every assert above on a Squire fixture.
	_eq(c.progression.level, 5, "the level came back")
	_eq(c.progression.raw_hp, 200, "the raw stats came back")
	# The arm the `from_dict` implementation fails.
	_eq(c.get_instance_id(), id_before, "cancel restored the SAME Character instance")
	_true(not a.is_open(), "cancel closed the window")


## An untouched turn writes nothing; a touched one writes the unit block AND the gambit SSBO.
func _test_untouched_costs_nothing_touched_writes_both() -> void:
	var quiet := AdjustmentTurn.new()
	var sim := StubSim.new()
	quiet.open(4, _fixture(SQUIRE_JOB))
	_true(not quiet.commit(sim, 0, _unit_stub()), "an untouched turn reports no landing")
	_eq(sim.reconfigured.size(), 0, "an untouched turn wrote no unit block")
	_eq(sim.gambits_set.size(), 0, "an untouched turn wrote no gambits")

	var edited := AdjustmentTurn.new()
	var sim2 := StubSim.new()
	edited.open(4, _fixture(SQUIRE_JOB))
	edited.touch()
	_true(edited.was_touched(), "the surface was opened")
	_true(edited.commit(sim2, 0, _unit_stub()), "a touched turn lands")
	_eq(sim2.reconfigured.size(), 1, "the unit block was written once")
	_eq(sim2.gambits_set.size(), 1, "the gambit SSBO was written once")
	_eq(sim2.reconfigured[0], [0, 4], "written to the right battle and taker")


## Commit closes the window; cancel after it un-lands nothing.
func _test_the_window_closes_once() -> void:
	var a := AdjustmentTurn.new()
	var sim := StubSim.new()
	var c := _fixture(SQUIRE_JOB)
	a.open(1, c)
	a.touch()
	_true(a.commit(sim, 0, _unit_stub()), "the turn landed")
	_true(not a.is_open(), "commit closed the window")
	_eq(a.taker(), -1, "and cleared the taker")
	c.progression.current_job_id = WIZARD_JOB
	_true(not a.cancel(c), "cancel after commit has nothing to restore")
	_eq(c.progression.current_job_id, WIZARD_JOB, "and it did not resurrect the pre-turn image")
	_true(not a.commit(sim, 0, _unit_stub()), "a second commit lands nothing")
	_eq(sim.reconfigured.size(), 1, "and wrote nothing more")


## Only stale ABILITY rows go. The job-independent verbs stay.
func _test_the_prune_drops_only_stale_abilities() -> void:
	var wizard_ability := _first_action(WIZARD_JOB)
	var squire_ability := _first_action(SQUIRE_JOB)
	_true(wizard_ability >= 0 and squire_ability >= 0, "both jobs have an action ability")

	var c := _fixture(SQUIRE_JOB)
	c.gambits = GambitList.new()
	c.gambits.add(_kind_gambit(Gambit.ActionKind.ATTACK))
	c.gambits.add(_kind_gambit(Gambit.ActionKind.MOVE))
	c.gambits.add(_kind_gambit(Gambit.ActionKind.WAIT))
	c.gambits.add(_ability_gambit(squire_ability))
	c.gambits.add(_ability_gambit(wizard_ability))
	var before := c.gambits.size()

	var pruned := AdjustmentTurn.prune_unusable_gambits(c)
	_eq(pruned.size(), 1, "exactly the Wizard row was pruned from a Squire")
	_true(pruned[0].ability_id == wizard_ability, "and it is the one the job cannot do")
	_true(before - c.gambits.size() >= 1, "the list actually shrank")

	var kinds: Array = []
	for g in c.gambits.gambits:
		if g != null and not g.is_empty():
			kinds.append(g.action_kind)
	_true(Gambit.ActionKind.ATTACK in kinds, "ATTACK survived the prune")
	_true(Gambit.ActionKind.MOVE in kinds, "MOVE survived the prune")
	_true(Gambit.ActionKind.WAIT in kinds, "WAIT survived the prune")

	# Running it again reports nothing, so the report stays silent when nothing changed.
	_eq(AdjustmentTurn.prune_unusable_gambits(c).size(), 0, "a second prune reports nothing")
	# And a list with nothing stale in it is never touched.
	var clean := _fixture(SQUIRE_JOB)
	clean.gambits = GambitList.new()
	clean.gambits.add(_ability_gambit(squire_ability))
	_eq(AdjustmentTurn.prune_unusable_gambits(clean).size(), 0, "a clean list prunes to nothing")
	_true(clean.gambits.size() >= 1, "and keeps its row")


## The usable set is the two skillsets the ROM model names, read from the real tables.
func _test_the_usable_set_is_primary_union_secondary() -> void:
	var squire_actions := _actions_of(SQUIRE_JOB)
	var wizard_actions := _actions_of(WIZARD_JOB)
	_true(squire_actions.size() > 0, "Squire's skillset is not empty")
	_true(wizard_actions.size() > 0, "Wizard's skillset is not empty")

	var c := _fixture(SQUIRE_JOB)
	var primary_only := AdjustmentTurn.usable_ability_ids(c)
	_true(primary_only.has(int(squire_actions[0])), "the job's own skillset is usable")
	_true(not primary_only.has(int(wizard_actions[0])),
		"another job's skillset is not — the fixture's disjointness holds")

	c.progression.sub_job_id = WIZARD_JOB
	var with_secondary := AdjustmentTurn.usable_ability_ids(c)
	_true(with_secondary.has(int(squire_actions[0])), "the primary is still usable")
	_true(with_secondary.has(int(wizard_actions[0])), "the SECONDARY skillset is usable too")
	_true(with_secondary.size() > primary_only.size(), "the union is strictly larger")


# === Fixtures =================================================================

## A Character built through the save schema — no catalogue, no roster, no promotion. Everything
## the adjustment turn touches (`progression`, `gambits`) is real; identity is deliberately blank.
## === Arms 8-11: the imperative ledger (#1006) ===============================================

## Charges are per unit PER BATTLE, and running out is a refusal rather than a free order.
func _test_charges_are_finite_and_per_unit() -> void:
	var imp := ImperativeGambits.new()
	var allowance := imp.allowance()
	_true(allowance >= 1,
		"the allowance tunable is at least one — a zero would make every arm below vacuous")
	_eq(imp.charges_left(3), allowance, "a unit nobody has touched has the full allowance")
	_true(not imp.is_armed(3), "and nothing standing")
	_true(imp.idle(), "the ledger is idle before anybody issues")

	for i in range(allowance):
		_true(imp.issue(3, ImperativeGambits.default_order(), 0),
			"issue %d of %d is accepted" % [i + 1, allowance])
	_eq(imp.charges_left(3), 0, "which spends the whole allowance")
	_true(imp.is_armed(3), "and leaves exactly one order standing — a re-aim REPLACES")
	_true(not imp.can_issue(3), "so the unit may not issue again")
	var standing = imp.entry_for(3)
	_true(not imp.issue(3, ImperativeGambits.default_order(), 0),
		"and a further issue is refused")
	_eq(imp.entry_for(3), standing, "changing nothing that stands")

	# THE ARM THAT SEPARATES per-unit from per-battle. A single shared counter passes every
	# assertion above and hands the whole squad one lock-on between them.
	_eq(imp.charges_left(4), allowance, "the NEXT unit still has its own full allowance")
	_true(imp.can_issue(4), "and may issue")
	_eq(imp.armed_units(), [3], "only unit 3 has an order standing")

	imp.reset()
	_eq(imp.charges_left(3), allowance, "a new battle gives the charges back")
	_true(imp.idle(), "and drops every standing order — charges are PER BATTLE")


## Cancel refunds every charge the turn spent and restores what stood before it; close refunds none.
func _test_the_refund_is_the_turns_and_only_the_turns() -> void:
	var imp := ImperativeGambits.new()
	var allowance := imp.allowance()

	# A turn that spends nothing owes nothing.
	imp.open(2)
	_eq(imp.cancel(), 0, "a cancel on a turn that issued nothing refunds nothing")
	_eq(imp.charges_left(2), allowance, "and mints no charge from nowhere")

	# Spend one, cancel: the charge comes back AND the order goes.
	imp.open(2)
	_true(imp.issue(2, ImperativeGambits.default_order(), 0), "an order is issued on the turn")
	_eq(imp.charges_left(2), allowance - 1, "which costs a charge")
	_eq(imp.cancel(), 1, "cancel refunds exactly the one spent")
	_eq(imp.charges_left(2), allowance, "the charge is back")
	_true(not imp.is_armed(2), "and the order is gone — a cancel that kept it would be a trap")

	# Spend one and COMMIT: nothing comes back, and the order stands.
	imp.open(2)
	_true(imp.issue(2, ImperativeGambits.default_order(), 0), "issued again")
	_true(imp.close(), "close reports that the turn issued one")
	_eq(imp.charges_left(2), allowance - 1, "a committed turn refunds nothing")
	_true(imp.is_armed(2), "and its order stands")
	_true(not imp.close(), "a second close reports nothing — the window closed once")

	# THE ARM A ONE-CHARGE REFUND FAILS. Two issues on one turn is a re-aim, and both were paid
	# for; a cancel that gave back one would silently eat the other. A FRESH ledger, so this needs
	# only two charges and stays live at the smallest allowance the tunable can be scrubbed to
	# without going vacuous — the arm above already asserts that floor.
	_true(allowance >= 2, "the allowance is at least two — the re-aim arms below need both")
	var reaim := ImperativeGambits.new()
	reaim.open(9)
	_true(reaim.issue(9, ImperativeGambits.default_order(), 0), "re-aimed once")
	_true(reaim.issue(9, _order_at(TargetSelector.TeamFilter.FRIENDLY), 0), "and again")
	_eq(reaim.charges_left(9), allowance - 2, "which spent two charges")
	_eq(reaim.cancel(), 2, "cancel refunds BOTH charges the turn spent")
	_eq(reaim.charges_left(9), allowance, "so the unit is whole again")

	# And the restore is of the ORDER THAT STOOD, not merely a clear: an order issued on an
	# EARLIER turn survives a cancelled later one.
	var kept := ImperativeGambits.new()
	_true(kept.issue(8, _order_at(TargetSelector.TeamFilter.FRIENDLY), 0),
		"an order stands from an earlier turn")
	var prior = kept.entry_for(8)
	kept.open(8)
	_true(kept.issue(8, ImperativeGambits.default_order(), 0), "the player re-aims on this turn")
	_true(kept.entry_for(8) != prior, "which replaces what stood")
	_eq(kept.cancel(), 1, "cancel refunds this turn's charge only")
	_eq(kept.entry_for(8), prior,
		"and puts the EARLIER order back — a cancel that only cleared would disarm a unit the"
			+ " player never disarmed")
	_eq(kept.charges_left(8), allowance - 1, "the earlier turn's charge stays spent")


## The watchdog is two dumb tests and no third, and it never refunds.
func _test_the_watchdog_takes_the_order_and_never_the_charge() -> void:
	var span := ImperativeGambits.new().deadline_span()
	_true(span >= 1, "the watchdog span is at least a tick")

	# The deadline must outlast at least one ACTION CYCLE — the invariant the old 120-tick default
	# broke the moment ADR-0260 widened the meter. Only an action spends an imperative (ADR-0259
	# dec. 10: a move does not raise `action_committed`) and expiry refunds nothing (dec. 11), so a
	# deadline shorter than one ability cooldown sells the player a charge for an order their unit
	# cannot possibly get to use.
	#
	# Asserted as a FLOOR against the ability data rather than pinned at the default, for two
	# reasons. The value is an ADR-0068 tunable, so pinning it would only restate the assignment.
	# And it is deliberately read in COOLDOWNS, never in turns: pricing this deadline in turns is
	# exactly how the old default came to depend on `TURN_METER_FULL` and rot silently when it
	# moved — no test could see it, because both watchdog arms are span-relative.
	var cooldown := _longest_ability_cooldown()
	_true(cooldown > 0, "effects.json reports an ability cooldown to price the deadline against")
	_true(span >= cooldown,
		("the watchdog span (%d) is at least one ability cooldown (%d) — an unconsumed order"
			+ " survives long enough for its unit to act on it at least once") % [span, cooldown])
	var alive := func(_u: int, _e) -> bool: return true
	var dead := func(_u: int, _e) -> bool: return false

	# Inside the deadline with a live pool: nothing happens. The control that stops the two arms
	# below from passing on an implementation that expires everything unconditionally.
	var a := ImperativeGambits.new()
	var spent_to := a.allowance() - 1
	_true(a.issue(5, ImperativeGambits.default_order(), 100), "an order is issued at tick 100")
	_eq(a.expire(100 + span - 1, alive), [],
		"inside the deadline with a live pool, nothing expires")
	_true(a.is_armed(5), "and the order still stands")

	# The DEADLINE, with the pool still full.
	_eq(a.expire(100 + span, alive), [5], "the deadline takes it")
	_true(not a.is_armed(5), "the order is gone")
	_eq(a.charges_left(5), spent_to,
		"and the charge is NOT refunded — design §5: a wasted lock-on is a real mistake")
	_eq(a.expire(100 + span, alive), [], "and there is nothing left to take twice")

	# The POOL, well inside the deadline — the design's "target dead/removed" under the one
	# constraint the GPU imposes (SPECIFIC_UNITS is unencodable, so an order aims at a RULE).
	var b := ImperativeGambits.new()
	var spent_to_b := b.allowance() - 1
	_true(b.issue(6, ImperativeGambits.default_order(), 100), "another order at tick 100")
	_eq(b.expire(101, dead), [6], "an empty target pool takes it, deadline or no deadline")
	_true(not b.is_armed(6), "the order is gone")
	_eq(b.charges_left(6), spent_to_b, "and this charge is not refunded either")

	# `withdraw` is the OTHER removal edge (`action_committed`) and behaves the same.
	var c := ImperativeGambits.new()
	_true(not c.withdraw(7), "withdrawing from a unit with no order reports nothing")
	_true(c.issue(7, ImperativeGambits.default_order(), 0), "an order to spend")
	_true(c.withdraw(7), "the unit acted, so the order is spent")
	_eq(c.charges_left(7), c.allowance() - 1, "and spending it refunds nothing either")


## The lead entry is at index 0 and displaces nothing.
func _test_the_imperative_is_a_lead_entry_and_costs_no_slot() -> void:
	var unit := _unit_stub()
	unit.gambit_list = GambitList.new()
	unit.gambit_list.add(_kind_gambit(Gambit.ActionKind.MOVE))
	unit.gambit_list.ensure_fixed_size()
	# One authored row and three padded "Wait on Self" empties. The count is a claim about the
	# ENCODER'S FILTER and not about the list's fixed size, which is four either way.
	_eq(unit.gambit_list.size(), GambitList.VISIBLE_SLOTS, "the list is padded to four slots")
	var authored := GambitEncoder.authored_gambits(unit)
	_eq(authored.size(), 1, "of which one is authored — the padding is not a rule")

	var bare: Array = GambitEncoder.encode_for_unit(unit)
	var led: Array = GambitEncoder.encode_for_unit(unit, ImperativeGambits.default_order())
	_eq(bare.size(), GPUConstants.MAX_USER_GAMBITS + 1,
		"the buffer is the authored region plus ADR-0048's safety net")
	_eq(led.size(), bare.size(), "and a lead entry does not grow it — it costs no slot")
	_true(bare[0] != null, "the unauthored buffer leads with the unit's own first rule")
	_true(led[0] != bare[0],
		"the LED buffer leads with something else — index 0 is where the shader looks first")
	_eq(led[1], bare[0],
		"and the unit's own first rule moved down one, intact behind the order")
	_eq(led[GPUConstants.MAX_USER_GAMBITS], bare[GPUConstants.MAX_USER_GAMBITS],
		"the safety net is still last (ADR-0048)")

	# THE SEAM. `AdjustmentTurn.commit` is the one crossing, and the lead rides its SECOND write —
	# an imperative is a gambit-list edit, so it needs no write path of its own.
	var sim := StubSim.new()
	var turn := AdjustmentTurn.new()
	turn.open(2, _fixture(SQUIRE_JOB))
	turn.touch()
	_true(turn.commit(sim, 0, unit, ImperativeGambits.default_order()), "the turn landed")
	_eq(sim.gambits_set.size(), 1, "through ONE gambit write, not two")
	_eq(sim.last_gambits[0], led[0], "which carried the lead entry")


## An order aimed at a team, for the arms that need two orders that are not the same object.
func _order_at(team: int):
	var g = ImperativeGambits.default_order()
	g.condition_target.team_filter = team
	return g


func _fixture(job_id: String) -> Character:
	return Character.from_dict({
		"unit_name": "Fixture",
		"current_job_id": job_id,
		"level": 5,
		"raw_hp": 200, "raw_mp": 80, "raw_speed": 8, "raw_pa": 6, "raw_ma": 5,
		"gambits_data": [],
	})


## The only thing `commit` asks of a unit is its `gambit_list` — the gambit SSBO is not in the unit
## block, so the encoder reads the CPU list directly (`GambitEncoder.encode_for_units`). A real
## [Unit] always declares one; this stub is the minimum that is true of every unit.
class UnitStub extends Node:
	var gambit_list = null


func _unit_stub() -> Node:
	var u := UnitStub.new()
	u.gambit_list = GambitList.new()
	u.gambit_list.add(_kind_gambit(Gambit.ActionKind.ATTACK))
	_made.append(u)
	return u


## A verb row for the prune fixture — AIMED, and the aim is what makes it a ROW.
##
## `Gambit.new()` IS the empty gambit (`Wait / Self / — / —`, and its `conditions` array is
## literally empty since ADR-0283 dec. 2), so a bare one with
## `action_kind = WAIT` is byte-for-byte the padding an empty slot carries, and every reader that
## skips empties — including the one below — correctly skips it. It used to survive that filter
## only because `Gambit._init` disagreed with `Gambit.is_empty` about `action_target`: the WAIT
## row counted as a rule because the constructor could not build the empty gambit. Aiming it here
## states in the FIXTURE what the fixture needs, instead of inheriting it from a defect.
func _kind_gambit(kind) -> Gambit:
	var g := Gambit.new()
	g.action_kind = kind
	g.ability_id = -1
	g.action_target = TargetSelector.triggering()
	return g


func _ability_gambit(ability_id: int) -> Gambit:
	var g := Gambit.new()
	g.action_kind = Gambit.ActionKind.ABILITY
	g.ability_id = ability_id
	return g


## The job's action-ability list, straight from the tables the port ships.
func _actions_of(job_id: String) -> Array:
	var job = JobDatabase.get_job(job_id)
	if job == null or job.is_empty():
		return []
	var skill_set = AbilityDatabase.get_skill_set(int(job.get("skill_set_id", 0)))
	if skill_set == null or skill_set.is_empty():
		return []
	return skill_set.get("actions", [])


func _first_action(job_id: String) -> int:
	var actions := _actions_of(job_id)
	return int(actions[0]) if not actions.is_empty() else -1


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


## The longest `cooldown_ticks` in the ability catalogue — the ACTION CYCLE this game runs on.
##
## Read off `effects.json` itself rather than written down as 300, so that if abilities ever stop
## sharing one cooldown the floor above follows the data instead of quoting a number that has
## moved. ADR-0260 dec. 2 leans on the same constant to size the dwell.
func _longest_ability_cooldown() -> int:
	var text := FileAccess.get_file_as_string("res://assets/abilities/effects.json")
	if text.is_empty():
		return 0
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return 0
	var longest := 0
	for row: Variant in (parsed as Dictionary).values():
		if row is Dictionary and (row as Dictionary).has("cooldown_ticks"):
			longest = maxi(longest, int((row as Dictionary)["cooldown_ticks"]))
	return longest
