class_name ScenarioDirector
extends RefCounted

## The FFT battle "director" — the runtime interpreter for BattleConditionals.
##
## Given a `battle_conditionals_id` (the ATTACK.OUT record field that a battle's
## setup scenario carries) and a [ScenarioDirectorState] to read combat/party
## state from, this decides which scenario the story advances to. It reproduces
## the PSX mechanism: evaluate the set's conditions top-to-bottom; the first
## condition whose requirements ALL hold fires its `Run Scenario N` result, and N
## is the next scenario.
##
## The PSX side is `bc_evaluate` at BATTLE.BIN 0x801425B0, read out of the ROM
## 2026-08-22: it walks records 0..9 of a condition-offset table and returns on the
## FIRST record that fires, so "first satisfied condition wins" is the engine's own
## rule and not an approximation of it. `Run Scenario N` writes **event-script
## variable 0x27** (RAM 0x800577B8) — NOT 0x8016A014, which is a fiber-stack word
## that merely mirrors it. See
## research/working_documents/WITHIN_GROUP_MEMBER_TRANSITION.md §7 and
## [BattleConditionalDatabase].
##
## Scope (deliberate): this is the pure data model + evaluator. State comes from a
## pluggable [ScenarioDirectorState] (stubbed by default). Wiring live combat state
## (GPU unit HP/turn/presence by ENTD id) and driving actual scenario transitions
## from it are separate, later steps — this class has no scene/VM/GPU dependency.
##
## Evaluation is stateless and side-effect free, and that is now ROM-confirmed rather
## than assumed: every one of the 376 conditions in the 146 shipped sets is a flat
## CONJUNCTION of predicates terminated by exactly one `Run Scenario`, and `Variable =`
## is a comparison, not an assignment. (The export's `commands` list is the WHOLE
## condition, predicates included — it overlaps `requirements` and must never be run as
## a second list of actions. Only `requirements` are read here.)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const BattleConditionalDatabase = ExMateriaAlmanac.BattleConditionalDatabase


# Requirement opcodes dispatch on the generated [BattleConditionalOpcode] enum
# (ADR-0059) — the member value IS the 2-byte opcode from
# assets/scenarios/battle_conditional_opcodes.json; never a literal hex here.

## No condition matched (the set does not advance under the current state).
const NONE := -1

var _state: ScenarioDirectorState


func _init(state: ScenarioDirectorState = null) -> void:
	_state = state if state != null else ScenarioDirectorState.new()


## Evaluate the set for `bc_id` against the current state. Returns the scenario id
## of the first condition whose requirements all hold, or [constant NONE] if none do.
func next_scenario(bc_id: int) -> int:
	var set_rec := BattleConditionalDatabase.get_set(bc_id)
	if set_rec.is_empty():
		return NONE
	for cond in set_rec.get("conditions", []):
		var target = cond.get("run_scenario")
		if target == null:
			continue
		if _condition_holds(cond):
			return int(target)
	return NONE


## Static graph view for a picker / UI: every outgoing edge of `bc_id` with a
## human-readable guard string, ignoring state. Shape:
##   [ { "target": int, "requirements": Array, "guard": String } ]
func edges(bc_id: int) -> Array:
	var out: Array = []
	var set_rec := BattleConditionalDatabase.get_set(bc_id)
	for cond in set_rec.get("conditions", []):
		var target = cond.get("run_scenario")
		if target == null:
			continue
		var reqs: Array = cond.get("requirements", [])
		out.append({
			"target": int(target),
			"requirements": reqs,
			"guard": describe_guard(reqs),
		})
	return out


## Human-readable guard, e.g. "Unit Present(7), HP <=(7, 0)" or "(unconditional)".
static func describe_guard(requirements: Array) -> String:
	if requirements.is_empty():
		return "(unconditional)"
	var parts: Array = []
	for req in requirements:
		var vals: Array = []
		for p in req.get("params", []):
			vals.append(str(int(p.get("value", 0))))
		parts.append("%s(%s)" % [req.get("name", "?"), ", ".join(vals)])
	return ", ".join(parts)


func _condition_holds(cond: Dictionary) -> bool:
	for req in cond.get("requirements", []):
		if not _requirement_holds(req):
			return false
	return true


func _requirement_holds(req: Dictionary) -> bool:
	var op := int(req.get("opcode", -1))
	# Operands read by NAME through the shared reader (catalog-driven widths),
	# not hand-counted `params[i].value` (ADR-0059).
	var a := BattleConditionalSet.args(req)
	match op:
		BattleConditionalOpcode.VARIABLE_EQ:
			return _state.get_variable(a.raw("Variable")) == a.raw("Value")
		BattleConditionalOpcode.VARIABLE_GE:
			return _state.get_variable(a.raw("Variable")) >= a.raw("Value")
		BattleConditionalOpcode.VARIABLE_LE:
			return _state.get_variable(a.raw("Variable")) <= a.raw("Value")
		BattleConditionalOpcode.UNIT_PRESENT:
			return _state.unit_present(a.raw("Unit"))
		BattleConditionalOpcode.HP_GE:
			return _state.unit_hp(a.raw("Unit")) >= a.raw("Value")
		BattleConditionalOpcode.HP_LE:
			return _state.unit_hp(a.raw("Unit")) <= a.raw("Value")
		BattleConditionalOpcode.HP_0X0007:  # HP % >=
			return _state.unit_hp_percent(a.raw("Unit")) >= a.raw("Value")
		BattleConditionalOpcode.HP_0X0008:  # HP % <=
			return _state.unit_hp_percent(a.raw("Unit")) <= a.raw("Value")
		BattleConditionalOpcode.MP_GE:
			return _state.unit_mp(a.raw("Unit")) >= a.raw("Value")
		BattleConditionalOpcode.MP_LE:
			return _state.unit_mp(a.raw("Unit")) <= a.raw("Value")
		BattleConditionalOpcode.ACTIVE_TURN:
			return _state.is_active_turn(a.raw("Unit"))
		BattleConditionalOpcode.MAIN_CHARACTER_EQUIP:
			return _state.main_character_equipped(a.raw("Item"))
		BattleConditionalOpcode.GIL_GE:
			return _state.gil() >= a.raw("Value")
		BattleConditionalOpcode.GIL_LE:
			return _state.gil() <= a.raw("Value")
		BattleConditionalOpcode.CASUALTIES_GE:
			return _state.casualties() >= a.raw("Value")
		BattleConditionalOpcode.CASUALTIES_LE:
			return _state.casualties() <= a.raw("Value")
		# The two comparisons are SWAPPED relative to the catalog's names. bc_predicate's
		# 0x0010 case (BATTLE.BIN 0x8014295C) returns true the moment var 0x2E < Month —
		# i.e. current date <= (Month, Day) — and 0x0011 (0x8014299C) is its mirror. Every
		# other paired opcode (0x02/0x03, 0x0E/0x0F, 0x12/0x13) matches its name under the
		# same reading, so this is the catalog's naming, not a polarity slip here. Inert in
		# practice: neither opcode appears anywhere in the 146 shipped sets. Guarded by
		# ScenarioDirectorTest._test_date_polarity_follows_the_rom.
		# WITHIN_GROUP_MEMBER_TRANSITION.md §7.5.
		BattleConditionalOpcode.DATE_GE:      # 0x0010 — ROM: current <= (Month, Day)
			return _date_cmp(a.raw("Month"), a.raw("Day")) <= 0
		BattleConditionalOpcode.DATE_LE:      # 0x0011 — ROM: current >= (Month, Day)
			return _date_cmp(a.raw("Month"), a.raw("Day")) >= 0
		BattleConditionalOpcode.VICTORY:
			return _state.is_victory()
		# "Z" is NOT an elevation. bc_predicate compares it to bit 15 of the halfword at
		# unit+0x48 — a one-bit upper/lower-layer flag — while X and Y are the bytes at
		# unit+0x47 and +0x48. It is 0 in all 50 uses across the shipped sets, so
		# [ScenarioDirectorState] must return 0/1 there, not a height.
		BattleConditionalOpcode.UNIT_LOCATION:
			return _state.unit_location(a.raw("Unit")) == [a.raw("X"), a.raw("Y"), a.raw("Z")]
		BattleConditionalOpcode.TEAM_UNIT_LOCATION:
			return _state.team_location(a.raw("Team ID")) == [a.raw("X"), a.raw("Y"), a.raw("Z")]
		_:
			# Unknown requirement: fail closed so a mis-decoded op never advances the story.
			push_warning("[ScenarioDirector] unhandled requirement opcode 0x%04x" % op)
			return false


# Compare current date to (month, day). Returns <0 / 0 / >0.
func _date_cmp(month: int, day: int) -> int:
	var d := _state.date()
	var cur_m := int(d[0]) if d.size() > 0 else 0
	var cur_d := int(d[1]) if d.size() > 1 else 0
	if cur_m != month:
		return cur_m - month
	return cur_d - day
