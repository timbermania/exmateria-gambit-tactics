extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: put ADR-0256 dec. 13's celebrate check back inside the IDLE fall-through of src/gpu/shaders/stage_compute.glsl (move it below the WALKING branch) — arm 5 reds because the busy survivor never leaves WALKING and the result never latches, and NOTHING ELSE in this file moves. Or: make the beat's seeds depend on something outside the position — in src/gpu/RolloutDriver.gd's `base_seed_for`, hash a wall-clock read (`get_ticks_usec`) in beside the header fields. Arm 1 reds on the candidate, the winner's score and the whole ranking at once, and NOTHING ELSE in the tree does: the fleet still runs, the apply still writes the right rows, and every score is still a probability. Alternatively, drop the `sized["ok"]` early return in `decide` — arm 4's per-slot clocks red because a refused beat ran the horizon.

## `RolloutDriver` end to end on a real fleet (#897, §7) — the beat, the choice,
## and the edit that lands.
##
## `GPURolloutHarnessTest` proves the MACHINE is invisible to the battle it forks
## from. This proves the DECISION taken on top of it: that the same position
## thought about twice produces the same move, that applying the winner writes
## exactly the winner's gambit rows and nothing else, and that a beat which does
## not fit its cap does not run at all.
##
## PASS: two beats on one position choose identically; `decide` alone leaves
##       battle 0 bit-identical; `apply` changes ONLY the acting unit's gambit
##       rows; a cap the plan cannot meet refuses without running; a beat
##       announced on the wrong team refuses instead of scoring from the wrong
##       side; and a WON battle latches even when its survivors are busy.
## FAIL: any of those.
##
## 🔴 ARM 1 IS #897'S HEADLINE AND IT NEEDS THE GPU. "The AI's choice must be
## reproducible" cannot be proved against `plan` alone — a plan is arithmetic and
## was always going to be deterministic. What could fail is everything after it:
## a seed derived from a clock, a candidate list ordered by a `Dictionary`'s
## insertion, a rank that broke ties by float noise. Only running the whole beat
## twice can see those, and only on the real kernel.
##
## ⚠️ ARM 4 SCRUBS A TUNABLE AND EXPECTS THE BEAT TO NOTICE. Testing that
## `plan` refuses a small cap proves a decision; it does not prove any tunable
## reaches the decision. `RolloutDriver` pull-reads its five slugs once per beat
## (ADR-0068 R5), and a pull that read the static var instead of the coalesced
## value would pass every other arm in this file.
##
## Small on purpose: 8 battles x 4 unit slots, `H = 200`. Fleet size is not what
## this proves — a suite that allocates a 256-battle fleet on a shared box loses
## its Vulkan device instead of failing an assertion.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/GPURolloutDriverTest.tscn

const FLEET_BATTLES := 8        # K=4 candidates x M=2 seeds
const FLEET_UNITS := 4          # 2v2 — teams split at the midpoint
const K := 4
const M := 2
const HORIZON := 200            # ticks per beat; long enough that the edits DIVERGE
const PREFORK := 40             # advance the live battle first — §7 forks MID-battle
const ACTOR := 2                # a team-1 unit: the enemy is the one that thinks
const ACTOR_TEAM := 1
const CAP_MS := 5000.0          # generous: this file is not measuring the box
## A spell the actor can afford, so the `action` and `insert` families have
## something to offer and the candidates DIVERGE. With an ATTACK-only roster and
## no usable ability every one-step edit plays out identically over a horizon,
## every score ties, and a comparison that always ties cannot show that ranking
## discriminates — it can only show that the tie-break is stable.
const ABILITY_FIRE := 16
## How far apart the two sides are seated, in entries of the sorted cell list.
##
## 🔴 THE ROSTER HAS TO ACTUALLY FIGHT, AND THE OBVIOUS SEATING DOES NOT. Placing
## the teams at opposite ENDS of the cell list — the shape `GPURolloutHarnessTest`
## uses, which is right for it because it asserts only identity — leaves them
## eight tiles apart at tick 240 with 400 HP a side untouched. Every fleet slot
## then carries the IDENTICAL result record, every candidate scores identically,
## and a ranking arm passes without ranking anything. Seated a few tiles apart
## they close, trade, and the records diverge.
const SEPARATION := 3

var _failed := false
var _sim: GPUBatchSimulator = null
var _cells: Array = []


func get_test_name() -> String:
	return "GPU Rollout Driver"


func _ready() -> void:
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here, then stored (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_fail("map has no lattice")
		_finish()
		return

	_collect_cells()
	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if not df:
		_fail("no distance field")
		_finish()
		return
	if _cells.size() < FLEET_UNITS:
		_fail("map has %d walkable cells, needs %d" % [_cells.size(), FLEET_UNITS])
		_finish()
		return

	_sim = GPUBatchSimulator.new()
	if not _sim.initialize(lattice, df, FLEET_BATTLES, FLEET_UNITS):
		_sim.cleanup()
		_fail("could not initialize a %d-battle simulator (VRAM?)" % FLEET_BATTLES)
		_finish()
		return

	_run_arms()

	_sim.cleanup()
	if _failed:
		print("[FAIL] GPURolloutDriver")
	else:
		print("[PASS] GPURolloutDriver: one position decides identically twice, apply writes only the actor's rows, a cap that cannot fit refuses, a won battle latches from a busy state")
	_finish()


func _process(_delta):
	pass


func _fail(msg: String) -> void:
	_failed = true
	print("[FAIL] %s" % msg)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _collect_cells() -> void:
	var cells: Array = []
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0:
			continue
		if c.impassable or c.pass_through_only:
			continue
		cells.append(c.grid)
	cells.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	_cells = cells


func _unit_cfg(seat: int, team: int) -> Dictionary:
	return {
		"name": "%s%d" % ["P" if team == 0 else "E", seat],
		"hp": 200, "max_hp": 200, "pa": 12, "ma": 10, "wp": 6,
		"brave": 60, "faith": 60, "mp": 200, "max_mp": 200,
		"speed": 8, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"c_ev": 10, "s_ev": 15, "w_ev": 10,
		"body_sprite_id": 0x02 if team == 0 else 0x05,
	}


## Seat a real 2v2 and walk it PREFORK ticks, so the beat forks a battle whose
## units are already engaged — §7's actual case, and the expensive regime
## (ADR-0237 dec. 6).
func _seat_live_battle() -> void:
	var per_team := FLEET_UNITS / 2
	var team0: Array = []
	var team1: Array = []
	for i in range(per_team):
		team0.append(_build_gpu_config(_cells[i], _unit_cfg(i, 0)))
		team1.append(_build_gpu_config(_cells[i + per_team + SEPARATION], _unit_cfg(i, 1)))
	_sim.set_battle_units(0, team0, team1, 4242)
	for i in range(FLEET_UNITS):
		# The actor gets TWO enabled slots so the `swap` family has a priority to
		# move, and a spell so `action` has an alternative to offer. Everybody else
		# stays on plain ATTACK: this rig is about the actor's search.
		_sim.set_unit_gambits(0, i, [make_spell_gambit(ABILITY_FIRE), make_attack_gambit()]
			if i == ACTOR else [make_attack_gambit()])
	_sim.step_tick(PREFORK)


func _slices_equal(a: Dictionary, b: Dictionary, label: String, skip: String = "") -> void:
	for slice_name in ["battle", "cooldowns", "gambits", "results"]:
		if slice_name == skip:
			continue
		var lhs: PackedInt32Array = a.get(slice_name, PackedInt32Array())
		var rhs: PackedInt32Array = b.get(slice_name, PackedInt32Array())
		if lhs == rhs:
			continue
		var first := -1
		for i in range(mini(lhs.size(), rhs.size())):
			if lhs[i] != rhs[i]:
				first = i
				break
		_fail("%s: the '%s' slice changed (sizes %d/%d, first differing int at %d)" % [
			label, slice_name, lhs.size(), rhs.size(), first])


## Point the driver's five tunables at this rig's shape. Written through `Tune`
## rather than onto the static vars, so every arm below is also exercising the
## pull-read that carries a scrub into a beat.
func _scrub_to_rig_shape(cap: float) -> void:
	Tune.set_value(RolloutDriver.CAP_MS_SLUG, cap)
	Tune.set_value(RolloutDriver.HORIZON_SLUG, HORIZON)
	Tune.set_value(RolloutDriver.CANDIDATES_SLUG, K)
	Tune.set_value(RolloutDriver.SEEDS_SLUG, M)
	Tune.set_value(RolloutDriver.FLEET_SIZE_SLUG, FLEET_BATTLES)


func _ctx() -> Dictionary:
	return RolloutCandidates.make_context("4a", [ABILITY_FIRE], 200,
		GPUAbilityLoader.build()["buffer"])


func _run_arms() -> void:
	_seat_live_battle()
	_scrub_to_rig_shape(CAP_MS)

	var driver := RolloutDriver.new(_sim, 0)
	_expect(driver.is_ready(),
		"the driver is not ready — the fitted artifact at assets/gambit/rollout_value_function.json did not load")
	if not driver.is_ready():
		return

	_arm_1_one_position_decides_the_same_way_twice(driver)
	_arm_2_apply_writes_only_the_actors_rows(driver)
	_arm_3_the_wrong_team_refuses(driver)
	_arm_4_a_cap_that_cannot_fit_runs_no_beat(driver)
	_arm_5_a_won_battle_latches_from_any_state()


## #897's headline: the same position, thought about twice, chooses the same move.
##
## Everything downstream of the plan gets its chance to be non-deterministic here
## — the seed derivation, the candidate order, the fleet's arithmetic, the rank's
## tie-break. And the arm is only as good as its positive control: a driver that
## returned "no decision" both times would agree with itself perfectly, so the
## beat has to have actually happened and actually ranked every slot.
func _arm_1_one_position_decides_the_same_way_twice(driver: RolloutDriver) -> void:
	var before: Dictionary = _sim.snapshot_battle(0)
	var first: Dictionary = driver.decide(ACTOR, ACTOR_TEAM, _ctx())
	_expect(bool(first["ok"]), "the first beat produced no decision: %s" % first["reason"])
	if not bool(first["ok"]):
		return

	# The positive control. Without it every assertion below is satisfied by a
	# beat that ran zero candidates.
	var plan: Dictionary = first["plan"]
	_expect(int(plan["k"]) == K and int(plan["m"]) == M and int(plan["horizon"]) == HORIZON,
		"the scrubbed shape did not reach the beat — planned K=%d M=%d H=%d, scrubbed K=%d M=%d H=%d" % [
			plan["k"], plan["m"], plan["horizon"], K, M, HORIZON])
	_expect(plan["degraded"].is_empty(),
		"this rig's fleet holds K x M exactly, so nothing should degrade: %s" % [plan["degraded"]])
	_expect(first["ranked"].size() >= RolloutDriver.MIN_CANDIDATES,
		"only %d candidate(s) were ranked — there was no comparison to reproduce" % first["ranked"].size())
	_expect(float(first["value"]) >= 0.0 and float(first["value"]) <= 1.0,
		"the winner's score %.6f is outside [0, 1] — every objective bounds its value there" % first["value"])

	# 🔴 THE COMPARISON MUST NOT BE VACUOUS, AND WHICH INVARIANT HOLDS DEPENDS ON
	# THE RIG. Without this, "reproducible" could be satisfied by a scorer that
	# returned a constant.
	#
	# MEASURED HERE, and worth writing down because it is the rig's limit rather
	# than the driver's: the four candidates this seating generates are genuinely
	# different IMAGES — swap puts ATTACK above the spell, condition gates the
	# spell on HP_BELOW 50, action replaces the spell with ATTACK — and they play
	# out IDENTICALLY, because the spell never fires and every one of them reduces
	# to "attack the nearest enemy". So the scores tie, and the live assertion
	# becomes ADR-0246 dec. 2's tie-break to the unmutated incumbent, which is a
	# real rule tested on a real fleet. A rig that discriminated would be a better
	# rig; it would not test anything about `decide` that this does not.
	var lo := 2.0
	var hi := -1.0
	for row in first["ranked"]:
		lo = minf(lo, float(row["value"]))
		hi = maxf(hi, float(row["value"]))
	if is_equal_approx(lo, hi):
		print("[driver] every candidate tied at P(win) %.6f — the tie-break is the assertion" % hi)
		_expect(int(first["candidate"]) == 0,
			"every candidate tied and the winner was %d, not the incumbent (ADR-0246 dec. 2)" % first["candidate"])
	else:
		print("[driver] scores span %.6f .. %.6f across %d candidates" % [lo, hi, first["ranked"].size()])
		_expect(is_equal_approx(float(first["value"]), hi),
			"the winner scored %.6f but the best score was %.6f" % [first["value"], hi])

	# `decide` reads and restores; it does not decide anything about the world.
	_slices_equal(before, _sim.snapshot_battle(0), "after decide()")

	var second: Dictionary = driver.decide(ACTOR, ACTOR_TEAM, _ctx())
	_expect(bool(second["ok"]), "the second beat produced no decision: %s" % second["reason"])
	if not bool(second["ok"]):
		return
	_expect(int(first["candidate"]) == int(second["candidate"]),
		"two beats on one position chose candidates %d and %d" % [
			first["candidate"], second["candidate"]])
	_expect(is_equal_approx(float(first["value"]), float(second["value"])),
		"two beats on one position scored the winner %.9f and %.9f" % [
			first["value"], second["value"]])
	_expect((first["rows"] as PackedInt32Array) == (second["rows"] as PackedInt32Array),
		"two beats on one position produced different gambit images for the same candidate index")

	# The whole ranking, not only its head: a tie-break that fell to float noise
	# would move the tail long before it moved the winner.
	var a: Array = first["ranked"]
	var b: Array = second["ranked"]
	_expect(a.size() == b.size(), "the two beats ranked %d and %d candidates" % [a.size(), b.size()])
	for i in range(mini(a.size(), b.size())):
		_expect(int(a[i]["candidate"]) == int(b[i]["candidate"])
				and is_equal_approx(float(a[i]["value"]), float(b[i]["value"])),
			"the two rankings part at position %d: candidate %d (%.9f) vs %d (%.9f)" % [
				i, a[i]["candidate"], a[i]["value"], b[i]["candidate"], b[i]["value"]])

	print("[driver] beat: %.2f ms measured, %.2f ms predicted; winner candidate %d at P(win) %.4f (incumbent %.4f)" % [
		first["beat_ms"], first["predicted_ms"], first["candidate"],
		first["value"], first["value_incumbent"]])


## The edit that lands is EXACTLY the winning image, over EXACTLY the acting unit.
##
## The failure this arm exists for is not "the AI picked wrong" — it is an apply
## that also carried the beat's last fleet slot back into battle 0, or that wrote
## the rows at the wrong unit offset. Either one leaves a battle that still runs,
## still looks right, and is playing somebody else's plan.
func _arm_2_apply_writes_only_the_actors_rows(driver: RolloutDriver) -> void:
	var before: Dictionary = _sim.snapshot_battle(0)
	var decision: Dictionary = driver.decide(ACTOR, ACTOR_TEAM, _ctx())
	if not bool(decision["ok"]):
		_fail("no decision to apply: %s" % decision["reason"])
		return

	# Applying the INCUMBENT must be a no-op down to the bit. That is what makes
	# "held" a real state rather than a label, and it is the control for the
	# assertion below: without it, an apply that wrote nothing at all would pass.
	var incumbent := RolloutCandidates.unit_rows(before["gambits"], ACTOR)
	_expect(driver.apply(ACTOR, incumbent), "applying the incumbent image failed")
	_slices_equal(before, _sim.snapshot_battle(0), "after applying the incumbent")

	var rows: PackedInt32Array = decision["rows"]
	_expect(driver.apply(ACTOR, rows), "applying the winning image failed")
	var after: Dictionary = _sim.snapshot_battle(0)
	_slices_equal(before, after, "after applying the winner", "gambits")
	_expect(RolloutCandidates.unit_rows(after["gambits"], ACTOR) == rows,
		"the actor's gambit rows are not the winning image")
	# The `held` flag has to agree with what the buffer did.
	var changed: bool = (before["gambits"] as PackedInt32Array) != (after["gambits"] as PackedInt32Array)
	_expect(changed != bool(decision["held"]),
		"the decision reports held=%s and the gambit slice %s" % [
			decision["held"], "changed" if changed else "did not change"])

	# 🔴 AND NOW A WRITE THAT REALLY IS ONE. The two applies above may BOTH be
	# no-ops — the AI is free to hold, and in this rig it usually does — so on
	# their own they cannot tell an apply that writes the right rows from one that
	# writes nothing at all. This one edits the image by hand so the write is
	# guaranteed, and it is where "only the actor's rows" is actually proved.
	var edited := (RolloutCandidates.unit_rows(before["gambits"], ACTOR) as PackedInt32Array).duplicate()
	RolloutCandidates.set_field(edited, 0, GPUCombatPacker.GambitField.ENABLED,
		1 - RolloutCandidates.get_field(edited, 0, GPUCombatPacker.GambitField.ENABLED))
	_expect(edited != RolloutCandidates.unit_rows(before["gambits"], ACTOR),
		"the hand-edited image is identical to the incumbent — this arm would prove nothing")
	_expect(driver.apply(ACTOR, edited), "applying a hand-edited image failed")
	var edited_snap: Dictionary = _sim.snapshot_battle(0)
	_slices_equal(before, edited_snap, "after applying a hand-edited image", "gambits")
	_expect(RolloutCandidates.unit_rows(edited_snap["gambits"], ACTOR) == edited,
		"the actor's gambit rows are not the image that was applied")
	for u in range(FLEET_UNITS):
		if u == ACTOR:
			continue
		_expect(RolloutCandidates.unit_rows(edited_snap["gambits"], u)
				== RolloutCandidates.unit_rows(before["gambits"], u),
			"applying the actor's image moved unit %d's gambit rows" % u)

	# Put the position back, so the arms after this one fork what the arms before
	# them forked.
	_expect(_sim.restore_battle(0, before), "could not restore the pre-apply position")


## A turn announced on the wrong side is refused, not scored.
##
## This is the silent-inversion guard. Scoring an enemy's beat from team 0's
## perspective produces a perfectly well-formed probability for every candidate
## and ranks them exactly backwards, so the AI plays to lose and no assertion
## anywhere else in the tree can see it.
func _arm_3_the_wrong_team_refuses(driver: RolloutDriver) -> void:
	var before: Dictionary = _sim.snapshot_battle(0)
	var decision: Dictionary = driver.decide(ACTOR, 1 - ACTOR_TEAM, _ctx())
	_expect(not bool(decision["ok"]),
		"unit %d was announced on team %d and the driver scored it anyway" % [ACTOR, 1 - ACTOR_TEAM])
	_expect(int(decision["candidate"]) == -1, "a refusal must not name a candidate")
	_slices_equal(before, _sim.snapshot_battle(0), "after a wrong-team refusal")

	# The perspective the driver reads is the packer's own byte, not the midpoint
	# — `set_battle_units` seats the two rosters contiguously, so the midpoint is
	# only right when team 0 fills exactly half.
	_expect(RolloutDriver.team_in_snapshot(before, ACTOR) == ACTOR_TEAM,
		"unit %d's GPU unit block says team %d" % [
			ACTOR, RolloutDriver.team_in_snapshot(before, ACTOR)])
	_expect(RolloutDriver.team_in_snapshot(before, 0) == 0,
		"unit 0's GPU unit block says team %d" % RolloutDriver.team_in_snapshot(before, 0))


## A cap the plan cannot meet runs NO beat — it does not run a shortened one.
##
## Two things at once, and the second is the one worth the GPU. That `plan`
## refuses is arithmetic. That the refusal reaches the beat — through a scrub, a
## pull-read, and a `decide` that returns before it snapshots anything — is
## behaviour, and it is what makes the cap hard rather than advisory.
func _arm_4_a_cap_that_cannot_fit_runs_no_beat(driver: RolloutDriver) -> void:
	var before: Dictionary = _sim.snapshot_battle(0)
	# Every slot's clock, taken NOW. Not `before_tick + HORIZON`: the arms above
	# already ran beats, so the fleet is carrying their ticks and a bound written
	# against one beat's arithmetic would fail against two.
	var ticks_before: Array[int] = []
	for b in range(FLEET_BATTLES):
		ticks_before.append(_sim.get_battle_tick(b))
	var ctx := _ctx()
	_scrub_to_rig_shape(0.001)
	var decision: Dictionary = driver.decide(ACTOR, ACTOR_TEAM, ctx)
	_scrub_to_rig_shape(CAP_MS)

	_expect(not bool(decision["ok"]), "a 0.001 ms cap admitted a beat")
	_expect(not bool(decision["plan"].is_empty()) and not bool(decision["plan"]["ok"]),
		"the refusal should carry the plan that refused")
	_expect(int(decision["plan"]["horizon"]) == HORIZON,
		"a refusal must refuse at the FULL horizon — reads %d" % decision["plan"]["horizon"])
	_slices_equal(before, _sim.snapshot_battle(0), "after a capped-out refusal")
	# The fleet never ran either, and THIS is the arm that separates "refused" from
	# "ran and then complained". A wall clock would say the same thing less
	# reliably: on a box under load a millisecond bar measures the box.
	for b in range(FLEET_BATTLES):
		_expect(_sim.get_battle_tick(b) == ticks_before[b],
			"slot %d advanced from tick %d to %d under a cap that refused the beat" % [
				b, ticks_before[b], _sim.get_battle_tick(b)])


func _finish() -> void:
	# Charter clause 14a: a FRAME budget, not a duration — a 0.2 s timer is a bet
	# that 0.2 s is enough on this box at this load.
	await AwaitUntil.settle(self)
	get_tree().quit(0)


## A WON battle latches even when the survivors are BUSY (ADR-0256 dec. 13).
##
## `stage_compute.glsl` used to notice a won battle only from `LOGICAL_ACTIVITY_IDLE`,
## and a unit with a live "attack the nearest enemy" gambit and no living enemy never
## reaches idle: the gambit re-evaluates, the unit re-enters WALKING toward a target
## that no longer resolves, and its timer restarts every tick. `stage_victory` reports
## a win only when every survivor is CELEBRATING, so the fight was decided and the
## battle ran forever.
##
## 🔴 THE ARM'S WHOLE VALUE IS THAT THE SURVIVOR IS NOT IDLE WHEN THE LAST ENEMY DIES.
## It is asserted, not assumed — a rig that happened to catch its survivors idling
## would pass against the very defect this exists for, which is exactly how the old
## check survived: Gariland's ENTD cast boots with EMPTY gambit lists (ADR-0242), so
## its survivors sat in IDLE and fell through.
func _arm_5_a_won_battle_latches_from_any_state() -> void:
	var before: Dictionary = _sim.snapshot_battle(0)

	# Walk the live battle until a team-0 unit is doing something. The units were
	# seated SEPARATION tiles apart, so they close, and closing is WALKING.
	var busy := -1
	for _step in range(HORIZON):
		_sim.step_tick(1)
		for u in range(FLEET_UNITS / 2):
			var st: int = _sim.get_battle_unit_states(0)[u].get("state", 0)
			if st != GPUConstants.LOGICAL_ACTIVITY_IDLE \
					and st != GPUConstants.LOGICAL_ACTIVITY_CELEBRATING \
					and st != GPUConstants.LOGICAL_ACTIVITY_DYING:
				busy = u
				break
		if busy >= 0:
			break
	_expect(busy >= 0,
		"no team-0 unit was ever busy in %d ticks — this arm cannot see the defect it exists for" % HORIZON)

	# Kill team 1 outright, in the buffer, leaving the busy unit mid-whatever.
	var snap: Dictionary = _sim.snapshot_battle(0)
	var battle: PackedInt32Array = (snap["battle"] as PackedInt32Array).duplicate()
	for u in range(FLEET_UNITS / 2, FLEET_UNITS):
		var base := GPUCombatPacker.BATTLE_HEADER_SIZE + u * GPUCombatPacker.UNIT_SIZE
		battle[base + GPUCombatPacker.UnitField.HP] = 0
		battle[base + GPUCombatPacker.UnitField.FLAGS] = \
			battle[base + GPUCombatPacker.UnitField.FLAGS] | GPUConstants.FLAG_DEAD_BIT
	snap["battle"] = battle
	_expect(_sim.restore_battle(0, snap), "could not install the wiped-team-1 position")

	var busy_state: int = _sim.get_battle_unit_states(0)[busy].get("state", -1)
	_expect(busy_state != GPUConstants.LOGICAL_ACTIVITY_IDLE,
		"unit %d is IDLE at the moment team 1 dies (state %d) — the arm is testing the easy path" % [
			busy, busy_state])

	# A handful of ticks is all it should need: the check runs before the state machine
	# dispatches, so it does not wait for anything to finish.
	_sim.step_tick(8)

	# 🔴 THE ASSERTION IS THE LATCH, NOT THE PER-UNIT STATE, AND THAT IS NOT A
	# WEAKENING. Once `stage_victory` declares a winner every stage opens with
	# `if (result != RESULT_ONGOING) return;` (ADR-0237 dec. 10) — including the
	# per-tick `copy_unit_to_next` — so the two ping-pong halves stop being
	# synchronised and `get_battle_unit_states` alternates between a frozen
	# pre-victory half and the post-victory one. A first cut of this arm asserted
	# `state == CELEBRATING` and read WALKING / CELEBRATING / WALKING on successive
	# ticks while the result was already TEAM_0_WINS. The latch is the property the
	# fix exists for and it is a single word that stops changing.
	var result: Dictionary = _sim.get_battle_result(0)
	_expect(int(result.get("winner", -1)) == 0,
		"the battle did not latch a team-0 win with team 1 wiped and a survivor mid-%s — result reads %s" % [
			GPUConstants.LOGICAL_ACTIVITY_NAMES[busy_state], result])
	# `is_battle_finished` is deliberately NOT the reader here: it tests the battle
	# HEADER's result word, which lives in the ping-pong slice and therefore
	# alternates once the copy stops. `get_battle_result` reads the single-buffered
	# results SSBO, which is the same word `stage_victory` writes and the only one
	# that stops changing. `CombatLoop._check_victory` polls every frame and so sees
	# it either way; a test that steps ticks by hand does not.

	_expect(_sim.restore_battle(0, before), "could not restore the pre-arm position")
