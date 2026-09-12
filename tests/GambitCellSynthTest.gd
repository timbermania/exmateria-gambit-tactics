extends Node

# test-kind: logic
# seeded-break: in `src/gpu/GambitCellSynth.gd`'s `_straddle`, change `COND_HP_BELOW`'s
#   positive from `(value - 1)` to `value` — arm 3 then reads a knob of 50 where 49 is
#   required and arm 4's one-knob diff collapses to zero, so the aggregate goes red twice.
#   Every arm below was proved red the same way, by breaking the thing it names.

## GambitCellSynth — the synthesizer's PURE half, guarded without a GPU (#1129).
##
## [GambitCellSynth] turns `(ability_id, gambit, axis)` into a cell spec, and the expensive half
## of that — does the kernel agree — is scored by the live arm (`--cell=`, which boots the cell
## and compares field by field) and by dec. 13's fleet sweeper. Neither of those is in the suite:
## ADR-0275 dec. 15 keeps the sweep out on purpose, because it would be red on day one for
## reasons that are FINDINGS and a test red for known reasons is one everybody trains themselves
## to ignore.
##
## So this test guards the half that CAN be guarded cheaply and has no excuse to be red: the
## arithmetic, the placement, the refusals, and the structural invariant that makes a mirror
## worth generating at all. `logic`, not `gpu` — no `CombatLoop`, no `RenderingDevice`, no tick
## (TEST-CHARTER clause 2: take the cheapest kind that can still fail).
##
## 🔴 ARM 4 IS THE ONE THAT MATTERS, and it is the one no other instrument covers.
## ADR-0275 dec. 2 says a positive and its mirror differ by ONE knob and a pair that fails to
## flip is a defect. That argument is only sound if the pair really differs by one thing: a
## mirror that also moved the dummy's team, or the actor's Speed, or the roster, would flip for a
## reason nobody named and the verdict would be unattributable. The live arm cannot see this —
## it boots one cell at a time and never holds both boards. So arm 4 diffs the two scenarios
## field by field and requires every difference to sit inside the knob's declared FOOTPRINT.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/GambitCellSynthTest.tscn

const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector

## What each knob is ALLOWED to move between a positive and its mirror. Anything else differing
## is arm 4's failure — including a field that moved for a defensible reason, because "defensible"
## is exactly what an unattributable pair looks like from the inside.
##
## `actor_speed` carries `max_ticks` with it and that is not a leak: the budget is DERIVED from
## Speed (`ticks_for_speed`), because a Speed-8 throw actor needs 450 ticks to reach the turn a
## Speed-120 actor reaches in 30. A mirror that kept the positive's budget would read blind.
const KNOB_FOOTPRINT := {
	"dummy_hp_percent": ["units.1.hp"],
	# `units.0`, the ACTOR, and that is not a typo. `evaluate_condition` reads
	# `get_mp_percent(battle_id, unit_id)` for both MP opcodes (`stage_compute.glsl:200-206`)
	# while every HP opcode reads `target_id` — so an MP straddle has to move the ACTOR'S MP, and
	# `GambitCondition.Type.TARGET_MP` encodes cleanly onto a condition that never looks at the
	# target. This arm is how that got written down: the footprint table omitted the row, and the
	# run said `knob actor_mp_percent has no declared footprint` twice.
	"actor_mp_percent": ["units.0.mp"],
	"dummy_status_bit": ["units.1.status_flags_lo"],
	"separation": ["units.1.tile"],
	"actor_speed": ["units.0.speed", "max_ticks"],
}

## `find_nth_nearest` has a hard `int unit_ids[8]` (`stage_compute.glsl:224`), so a cell that
## seated a ninth unit would silently truncate the rank walk — ADR-0275's own Consequences say
## so, and nothing else in the tree checks it for a synthesized roster.
const MAX_CELL_UNITS := 8

var _fail := false


func _ready() -> void:
	print("\n=== GambitCellSynth Test ===")

	_arm1_table_is_complete_and_named()
	_arm2_placement_refuses_rather_than_approximates()
	_arm3_straddle_arithmetic()
	_arm4_a_mirror_moves_exactly_one_knob()
	_arm5_refusals_all_say_why()
	_arm6_the_ladder_refuses_what_it_cannot_hold()
	_arm7_the_tick_budget_follows_speed()
	_arm8_every_cell_is_a_legal_board()
	_arm9_the_coverage_measurement_has_no_surprises()

	if _fail:
		print("[FAIL] GambitCellSynth test")
	else:
		print("[PASS] GambitCellSynth: table complete, placement refuses off-board, straddle "
			+ "arithmetic exact, every mirror moves ONE knob, refusals all reasoned, ladder "
			+ "refuses a collision and an over-long climb, tick budget tracks Speed, every "
			+ "roster legal on MAP116, coverage measured with no undeclared gap")
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("[FAIL] %s" % what)
		_fail = true


# =============================================================================================

## Every row the kernel needs exists and every cell the catalogue names is named. The table's
## COMPLETENESS is `tools/check_gambit_straddle_table.py`'s job (a static guard, no Godot); what
## this arm adds is that the rows are reachable from GDScript with the spellings the synthesizer
## uses — a row whose key the kernel declares but whose `_straddle` arm typo'd the name would
## pass the text guard and refuse at run time.
func _arm1_table_is_complete_and_named() -> void:
	var reader := GambitVerdictReader.new()
	reader.load_layout()
	var declared := 0
	for k in reader.consts.keys():
		if String(k).begins_with("COND_"):
			declared += 1
			_check(GambitCellSynth.STRADDLE_TABLE.has(k), "the kernel declares %s and "
				% k + "STRADDLE_TABLE has no row (see tools/check_gambit_straddle_table.py)")
	_check(declared > 0, "parsed zero COND_* out of the kernel header — the instrument, not the tree")
	_check(GambitCellSynth.STRADDLE_TABLE.size() == declared,
		"STRADDLE_TABLE has %d rows against %d declared opcodes" % [
			GambitCellSynth.STRADDLE_TABLE.size(), declared])
	for c in GambitCellSynth.catalogue():
		_check(String(c["name"]) != "", "a catalogue entry has no name (refused: %s) — dec. 9's "
			% str(c["refused"]) + "refusal list is a to-do list, and an unnamed to-do is not one")


## dec. 10: an unplaceable cell REFUSES and is counted, never nudged. `place()` returning an
## approximation is the single most dangerous thing this file could do, because the cell would
## still produce a verdict and the verdict would describe a different experiment.
func _arm2_placement_refuses_rather_than_approximates() -> void:
	var ox := GambitCellSynth.ORIGIN_X
	var oz := GambitCellSynth.ORIGIN_Z
	for d in range(GambitCellSynth.MIN_SEPARATION, GambitCellSynth.MAX_SEPARATION + 1):
		var t = GambitCellSynth.place(d, false)
		_check(t != null, "separation %d is inside MAP116's Manhattan maximum and place() refused" % d)
		if t == null:
			continue
		var got: int = absi(int(t[0]) - ox) + absi(int(t[1]) - oz)
		_check(got == d, "place(%d) returned %s, Manhattan %d — a placement that is not the "
			% [d, str(t), got] + "separation asked for IS the nudge dec. 10 bans")
		_check(int(t[0]) >= 0 and int(t[0]) < GambitCellSynth.MAP_W
			and int(t[1]) >= 0 and int(t[1]) < GambitCellSynth.MAP_H,
			"place(%d) returned %s, off an %dx%d board" % [
				d, str(t), GambitCellSynth.MAP_W, GambitCellSynth.MAP_H])
	_check(GambitCellSynth.place(GambitCellSynth.MAX_SEPARATION + 1, false) == null,
		"place() approximated a separation past MAP116's Manhattan maximum instead of refusing")
	_check(GambitCellSynth.place(0, false) == null,
		"place(0) returned a tile — two units in one cell needs the under-a-bridge geometry "
		+ "ADR-0224 dec. 6 allows and MAP116, single-level, does not have")
	# The CARDINAL cap is half the Manhattan one, and it is what bounds every `check_lunging`
	# straddle: the diagonal that reaches 10 is rejected by `ax != tx && az != tz`.
	for d in range(GambitCellSynth.MIN_SEPARATION, GambitCellSynth.MAX_CARDINAL + 1):
		var tc = GambitCellSynth.place(d, true)
		_check(tc != null and int(tc[1]) == oz,
			"cardinal place(%d) must stay on the actor's row, got %s" % [d, str(tc)])
	_check(GambitCellSynth.place(GambitCellSynth.MAX_CARDINAL + 1, true) == null,
		"place(%d, cardinal) must refuse — MAP116's cardinal maximum from (%d,%d) is %d, and a "
		% [GambitCellSynth.MAX_CARDINAL + 1, ox, oz, GambitCellSynth.MAX_CARDINAL]
		+ "diagonal substitute would straddle the lunging CROSS instead of the reach")


## The boundary is where the kernel's comparison turns over, and for every numeric row that means
## the NEGATIVE side sits exactly ON the threshold: `measured < value` fails at `value`. A guard
## that only checked "the two sides differ" would pass a table that straddled the wrong side.
func _arm3_straddle_arithmetic() -> void:
	var hp_below := _pair_for(GambitCondition.target_hp_below(50.0))
	_check(int(hp_below["positive"]["axis"]["knob_value"]) == 49,
		"HP_BELOW(50) positive must put the dummy at 49%% — the kernel tests `<`, got %s"
			% str(hp_below["positive"]["axis"]["knob_value"]))
	_check(int(hp_below["mirrors"][0]["axis"]["knob_value"]) == 50,
		"HP_BELOW(50) mirror must sit ON the threshold at 50%%, got %s"
			% str(hp_below["mirrors"][0]["axis"]["knob_value"]))
	_check(_expect_for(hp_below["mirrors"][0], 0).get("payload", -1) == 50,
		"the mirror must predict int B == 50 — the payload IS the number that lost, and it is "
		+ "the assertion that ends an investigation rather than restating the verdict")

	var hp_above := _pair_for(GambitCondition.target_hp_above(50.0))
	_check(int(hp_above["positive"]["axis"]["knob_value"]) == 51,
		"HP_ABOVE(50) positive must be 51%%, got %s" % str(hp_above["positive"]["axis"]["knob_value"]))
	_check(int(hp_above["mirrors"][0]["axis"]["knob_value"]) == 50,
		"HP_ABOVE(50) mirror must sit ON 50%%")

	var near := _pair_for(GambitCondition.target_within(3.0))
	_check(int(near["positive"]["separation"]) == 2 and int(near["mirrors"][0]["separation"]) == 3,
		"DISTANCE_LESS(3) must straddle 2 / 3, got %d / %d" % [
			int(near["positive"]["separation"]), int(near["mirrors"][0]["separation"])])
	var far := _pair_for(GambitCondition.target_beyond(3.0))
	_check(int(far["positive"]["separation"]) == 4 and int(far["mirrors"][0]["separation"]) == 3,
		"DISTANCE_GREATER(3) must straddle 4 / 3, got %d / %d" % [
			int(far["positive"]["separation"]), int(far["mirrors"][0]["separation"])])

	# Status is CATEGORICAL: the straddle sets or clears the bit. Stepping the bit INDEX would
	# ask about a different status entirely, which is the shape of the error dec. 8 bans.
	var has := _pair_for(GambitCondition.has_status(GambitCellSynth.INERT_STATUS))
	var bit: int = int(ExMateriaAlmanac.StatusRegistry.bit(GambitCellSynth.INERT_STATUS))
	_check(int(has["positive"]["axis"]["knob_value"]) == bit
		and int(has["mirrors"][0]["axis"]["knob_value"]) == -1,
		"HAS_STATUS must straddle bit-set / bit-clear on the SAME bit (%d), got %s / %s" % [
			bit, str(has["positive"]["axis"]["knob_value"]),
			str(has["mirrors"][0]["axis"]["knob_value"])])

	# dec. 2: the pair has to FLIP in its PREDICTION, or the mirror is decoration.
	for pair in [hp_below, hp_above, near, far, has]:
		_check(String(_expect_for(pair["positive"], 0).get("p1", "")) == "FIRED",
			"a positive cell must predict FIRED at slot 0")
		_check(String(_expect_for(pair["mirrors"][0], 0).get("p1", "")) == "CONDITION_FALSE",
			"a mirror must predict CONDITION_FALSE at slot 0 — a pair that does not flip in its "
			+ "own prediction cannot detect a pair that does not flip in the kernel")


## ⚠️ THE ARM NOTHING ELSE COVERS. See the class docstring.
func _arm4_a_mirror_moves_exactly_one_knob() -> void:
	for c in GambitCellSynth.catalogue():
		if bool(c["refused"]) or String(c["kind"]) != "mirror":
			continue
		var knob: String = String(c["axis"]["knob"])
		if not KNOB_FOOTPRINT.has(knob):
			_check(false, "mirror %s moves knob `%s`, which has no declared footprint here. A "
				% [c["name"], knob] + "knob nobody bounded is a pair nobody can attribute.")
			continue
		var twin := GambitCellSynth.find(String(c["name"]).replace("/mirror", "/positive"))
		if twin.is_empty() or bool(twin["refused"]):
			continue
		var diffs := _diff_scenarios(twin["scenario"], c["scenario"])
		var allowed: Array = KNOB_FOOTPRINT[knob]
		for d in diffs:
			_check(allowed.has(d), "mirror %s differs from its positive at `%s`, which is not in "
				% [c["name"], d] + "knob `%s`'s footprint %s. dec. 2's argument — a pair that "
				% [knob, str(allowed)] + "fails to flip is a defect — only holds if the pair "
				+ "differs by ONE thing.")
		_check(not diffs.is_empty(), "mirror %s is byte-identical to its positive: the straddle "
			% c["name"] + "moved nothing, so the pair would flip for no reason and a green would "
			+ "mean the instrument stopped looking")


## decs. 9 and 10. A refusal with no reason is indistinguishable from an unfinished row, and the
## refusal count is meant to be a to-do list rather than a tally.
func _arm5_refusals_all_say_why() -> void:
	var refused := 0
	for c in GambitCellSynth.catalogue():
		if not bool(c["refused"]):
			continue
		refused += 1
		_check(String(c["refusal"]).length() > 20, "%s refuses with too little reason: '%s'" % [
			c["name"], c["refusal"]])
	_check(refused > 0, "the catalogue refuses NOTHING. Three rows cannot be straddled "
		+ "(COND_ALWAYS has no operand; COND_IS_DEAD/COND_IS_ALIVE cannot seed FLAG_DEAD) and two "
		+ "opcodes are unreachable from any authored gambit, so a zero here means the refusal "
		+ "path stopped firing — and a synthesizer that never refuses is one that nudges")
	# The three named refusals, asserted by NAME so a row quietly becoming buildable is news.
	var always := GambitCellSynth.build_pair(-1, _gambit_for(GambitCondition.always()), 0)
	_check(int(always["refused"]) > 0 and (always["positive"]["negative_sides"] as int) == 0,
		"COND_ALWAYS must report no negative case — dec. 9 names it structurally unstraddleable")
	var dead := GambitCellSynth.find("COND_IS_DEAD/positive")
	_check(not dead.is_empty() and bool(dead["refused"])
		and String(dead["refusal"]).contains("FLAG_DEAD"),
		"COND_IS_DEAD's cell must refuse and name FLAG_DEAD: `is_unit_dead` reads U_FLAGS, which "
		+ "only stage_damage writes, and the battle spec has no `flags` channel")
	for team_row in ["COND_TEAM_ALLY", "COND_TEAM_ENEMY"]:
		var t := GambitCellSynth.find("%s/positive" % team_row)
		_check(not t.is_empty() and bool(t["refused"]),
			"%s must refuse — `GambitCondition.Type` has no TEAM member, so no authored gambit "
			% team_row + "reaches it, and dec. 22 ships a coverage line rather than an injection path")


## The ladder is dec. 2's third shape, and both refusals below are findings the build ATTEMPT
## produced rather than rules somebody remembered.
func _arm6_the_ladder_refuses_what_it_cannot_hold() -> void:
	var g = _gambit_for(GambitCondition.target_hp_below(50.0))
	var too_long: Array = []
	for _i in range(GPUConstants.MAX_USER_GAMBITS + 1):
		too_long.append(g)
	var over := GambitCellSynth.build_ladder(-1, too_long, [])
	_check(bool(over["refused"]) and String(over["refusal"]).contains("MAX_USER_GAMBITS"),
		"a ladder of %d rungs must refuse: pass 1 walks slot %d as ADR-0048's safety net, whose "
		% [too_long.size(), GPUConstants.MAX_USER_GAMBITS] + "Always cannot fail, so the last "
		+ "rung could never be reached (#1128)")

	# Two HP rungs cannot climb one board: rung 0 declines `< T0` only at T0 and rung 1 fires
	# `> T1` only at T1 + 1, so the board would need two different HP values at once.
	var collide := GambitCellSynth.build_ladder(-1, [
		_gambit_for(GambitCondition.target_hp_below(71.0)),
		_gambit_for(GambitCondition.target_hp_above(69.0))], [0, 0])
	_check(bool(collide["refused"]) and String(collide["refusal"]).contains("disagree"),
		"two rungs straddling the same knob to different values must refuse, not silently take "
		+ "the last — that is dec. 10's productive failure with a different name")

	var ladder := GambitCellSynth.find("ladder/")
	_check(not ladder.is_empty() and not bool(ladder["refused"]),
		"the catalogue's probe ladder must BUILD: %s" % String(ladder.get("refusal", "absent")))
	if ladder.is_empty() or bool(ladder["refused"]):
		return
	_check((ladder["expect"] as Array).size() == GPUConstants.MAX_GAMBITS,
		"a ladder must predict every slot of the buffer (%d), so a slot nobody named cannot pass "
		% GPUConstants.MAX_GAMBITS + "by being unexamined. Got %d" % (ladder["expect"] as Array).size())
	# "Slot N fired" alone is not a pass (dec. 2): the rungs below it must each be predicted to
	# decline, with the opcode they declined on.
	var declines := 0
	for e in ladder["expect"]:
		if String(e.get("p1", "")) == "CONDITION_FALSE":
			declines += 1
			_check(e.has("op"), "a ladder rung predicted CONDITION_FALSE without naming the "
				+ "OPCODE it declined on — which is the half that makes it a reason")
	_check(declines >= 2, "the probe ladder must predict at least two declines before the fire, "
		+ "with distinct reasons; got %d" % declines)


## A fixed tick budget read every throw cell as blind. The budget is derived, and the derivation
## has to be monotone in the thing it derives from.
func _arm7_the_tick_budget_follows_speed() -> void:
	var slow := GambitCellSynth.ticks_for_speed(8)
	var fast := GambitCellSynth.ticks_for_speed(GambitCellSynth.ACTOR_SPEED)
	_check(slow > fast, "a slower actor needs MORE ticks, not fewer (%d vs %d)" % [slow, fast])
	# `compute_unit_state` adds max(1, U_SPEED) per tick and a unit is ready at TURN_METER_FULL,
	# so the budget has to clear one turn with room to spare or the cell is blind by construction.
	var reader := GambitVerdictReader.new()
	reader.load_layout()
	var full: int = int(reader.consts.get("TURN_METER_FULL", 3600))
	for speed in [1, 8, 18, 120, 999]:
		var budget := GambitCellSynth.ticks_for_speed(speed)
		_check(budget > full / maxi(1, speed), "Speed %d reaches its first turn at tick %d and "
			% [speed, full / maxi(1, speed)] + "the derived budget is only %d — every cell at "
			% budget + "that Speed would read NONE(not walked), which is a BLIND run and not a "
			+ "failed prediction")
	var throw_cell := GambitCellSynth.find("throw_speed")
	if not throw_cell.is_empty() and not bool(throw_cell["refused"]):
		_check(int(throw_cell["ticks"]) > full / maxi(1, int(throw_cell["actor_speed"])),
			"the throw cell's Speed %d needs %d ticks and its spec budgets %d" % [
				int(throw_cell["actor_speed"]), full / maxi(1, int(throw_cell["actor_speed"])),
				int(throw_cell["ticks"])])


## Every board the synthesizer emits has to be one the kernel can actually hold.
func _arm8_every_cell_is_a_legal_board() -> void:
	for c in GambitCellSynth.catalogue():
		if bool(c["refused"]):
			continue
		var sc: Dictionary = c["scenario"]
		_check(String(sc["map"]) == GambitCellSynth.MAP, "%s is on %s, not %s (dec. 11: MAP042's "
			% [c["name"], sc["map"], GambitCellSynth.MAP] + "largest flat Manhattan disk is "
			+ "radius 1, so a controlled-distance cell is geometrically impossible there)")
		var us: Array = sc["units"]
		_check(us.size() <= MAX_CELL_UNITS, "%s seats %d units; `find_nth_nearest` has a hard "
			% [c["name"], us.size()] + "int unit_ids[8], so a ninth would truncate the rank walk")
		_check(us.size() >= 2, "%s seats %d unit(s) — a cell needs an actor and a dummy"
			% [c["name"], us.size()])
		var teams: Dictionary = {}
		for u in us:
			teams[int(u.get("team", 0))] = true
			var tile: Array = u["tile"]
			_check(int(tile[0]) >= 0 and int(tile[0]) < GambitCellSynth.MAP_W
				and int(tile[1]) >= 0 and int(tile[1]) < GambitCellSynth.MAP_H,
				"%s places %s at %s, off the board" % [c["name"], u["name"], str(tile)])
		# 🔴 A BATTLE WITH NO TEAM-1 UNIT IS WON ON TICK 1. `check_victory` returns
		# RESULT_TEAM_0_WINS the moment team1_alive hits zero, and the actor's first turn is 29
		# ticks later — so every slot reads NONE(not walked) and the cell is BLIND, not failing.
		# Measured on cell/COND_IS_ALIVE/positive before `_liveness_opponent` existed.
		_check(teams.has(0) and teams.has(1), "%s has no unit on team %s. A battle missing "
			% [c["name"], "1" if teams.has(0) else "0"] + "either team is decided on tick 1, "
			+ "before any unit reaches a turn, and every verdict reads NONE(not walked)")
		# Two units on one tile is the geometry MAP116 does not have (ADR-0224 dec. 6 makes
		# occupancy a CELL, but this map is single-level).
		var seen: Dictionary = {}
		for u in us:
			var key := "%d,%d" % [int(u["tile"][0]), int(u["tile"][1])]
			_check(not seen.has(key), "%s puts two units on %s" % [c["name"], key])
			seen[key] = true


## dec. 22's coverage line is a MEASUREMENT, and the thing to guard is not the number — the ADR
## says outright that the number has a date on it. What must stay zero is `surprises`: a
## condition or selector that is in no declared `UNSUPPORTED_*` set and still fails to encode.
## That is an UNDECLARED gap, and ADR-0023's whole contract is that a gap is declared.
func _arm9_the_coverage_measurement_has_no_surprises() -> void:
	var cov := GambitCellSynth.encoder_coverage()
	_check(int(cov["conditions_declared"]) > 0 and int(cov["selectors_declared"]) > 0,
		"encoder_coverage() measured nothing — a blind instrument, not an empty gap")
	_check(int(cov["conditions_reached"]) > 0 and int(cov["selectors_reached"]) > 0,
		"encoder_coverage() says the encoder reaches NO opcode at all, which would mean the "
		+ "enumeration broke rather than that the encoder did")
	for s in cov["surprises"]:
		_check(false, "undeclared encoder gap: %s. ADR-0023 is faithful-or-EXPLICIT — a "
			% s + "combination that refuses without being in an UNSUPPORTED_* set refuses "
			+ "silently, which is the substitution the ADR exists to ban")


# =============================================================================================
# helpers
# =============================================================================================

func _gambit_for(cond):
	return Gambit.create(TargetSelector.enemies(), [cond], Gambit.ActionKind.ATTACK, -1,
		TargetSelector.triggering())


func _pair_for(cond) -> Dictionary:
	return GambitCellSynth.build_pair(-1, _gambit_for(cond), 0)


func _expect_for(spec: Dictionary, slot: int) -> Dictionary:
	for e in spec.get("expect", []):
		if int(e["slot"]) == slot:
			return e
	return {}


## Dotted paths at which two scenario dicts differ, `name` excluded (it encodes the side by
## design). Units are compared POSITIONALLY, which is sound because both boards come out of the
## same builder in the same order — and a roster whose ORDER moved is itself a difference worth
## reporting, under `units.N`.
func _diff_scenarios(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a.keys():
		if k == "name":
			continue
		if k == "units":
			var ua: Array = a["units"]
			var ub: Array = b["units"]
			if ua.size() != ub.size():
				out.append("units.size")
				continue
			for i in range(ua.size()):
				for f in (ua[i] as Dictionary).keys():
					if f == "gambits":
						continue        # Gambit objects, compared by identity — not a board field
					if str((ua[i] as Dictionary)[f]) != str((ub[i] as Dictionary).get(f)):
						out.append("units.%d.%s" % [i, f])
			continue
		if str(a[k]) != str(b.get(k)):
			out.append(String(k))
	return out
