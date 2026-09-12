class_name ForcedDirectorState
extends ScenarioDirectorState

## The debug/manual [ScenarioDirectorState] the [Path] navigation synthesizes to
## make a chosen guard true.
##
## The base class anticipates three subclasses: a live-combat source, a hand-set
## test stub, and this forced source. It is a plain read store — hand-set or
## synthesized combat/party reads (variables, unit HP/MP/presence/turn, victory,
## gil, casualties, date, locations) — that the [ScenarioDirector] queries exactly
## like any other state. It NEVER writes game state; the director's faithfulness
## rests on read-only state, and this class preserves that (it only records what a
## human/planner asked the director to *see*).
##
## Use [method synthesize] to turn one BattleConditional condition's `requirements`
## list into the minimal ForcedDirectorState that makes every requirement hold.
## Unit ids are ENTD slot ids and variable ids are raw BattleConditional indices,
## matching the operands the director reads (see [ScenarioDirector]).

# All JSON numbers arrive as float; every stored/read value is int()-cast so the
# director's `==` comparisons against int operands never miss on 1 vs 1.0.
var _vars: Dictionary = {}          # var_id -> int
var _present: Dictionary = {}       # unit_id -> bool
var _hp: Dictionary = {}            # unit_id -> int
var _hp_pct: Dictionary = {}        # unit_id -> int (0..100)
var _mp: Dictionary = {}            # unit_id -> int
var _active: Dictionary = {}        # unit_id -> bool
var _equipped: Dictionary = {}      # item_id -> bool
var _unit_loc: Dictionary = {}      # unit_id -> [x, y, z]
var _team_loc: Dictionary = {}      # team_id -> [x, y, z]
var _victory: bool = false
var _gil: int = 0
var _casualties: int = 0
var _date: Array = [0, 0]


# --- Setters (fluent-ish; return self so a synthesizer can chain) ---

func set_variable(id: int, value: int) -> ForcedDirectorState:
	_vars[int(id)] = int(value)
	return self

func set_present(unit_id: int, value: bool = true) -> ForcedDirectorState:
	_present[int(unit_id)] = value
	return self

func set_hp(unit_id: int, value: int) -> ForcedDirectorState:
	_hp[int(unit_id)] = int(value)
	return self

func set_hp_percent(unit_id: int, value: int) -> ForcedDirectorState:
	_hp_pct[int(unit_id)] = int(value)
	return self

func set_mp(unit_id: int, value: int) -> ForcedDirectorState:
	_mp[int(unit_id)] = int(value)
	return self

func set_active_turn(unit_id: int, value: bool = true) -> ForcedDirectorState:
	_active[int(unit_id)] = value
	return self

func set_equipped(item_id: int, value: bool = true) -> ForcedDirectorState:
	_equipped[int(item_id)] = value
	return self

func set_victory(value: bool = true) -> ForcedDirectorState:
	_victory = value
	return self

func set_gil(value: int) -> ForcedDirectorState:
	_gil = int(value)
	return self

func set_casualties(value: int) -> ForcedDirectorState:
	_casualties = int(value)
	return self

func set_date(month: int, day: int) -> ForcedDirectorState:
	_date = [int(month), int(day)]
	return self

func set_unit_location(unit_id: int, x: int, y: int, z: int) -> ForcedDirectorState:
	_unit_loc[int(unit_id)] = [int(x), int(y), int(z)]
	return self

func set_team_location(team_id: int, x: int, y: int, z: int) -> ForcedDirectorState:
	_team_loc[int(team_id)] = [int(x), int(y), int(z)]
	return self


# --- Read overrides (the ScenarioDirectorState query interface) ---

func get_variable(id: int) -> int:
	return int(_vars.get(int(id), 0))

func unit_present(unit_id: int) -> bool:
	return bool(_present.get(int(unit_id), false))

func unit_hp(unit_id: int) -> int:
	return int(_hp.get(int(unit_id), 0))

func unit_hp_percent(unit_id: int) -> int:
	return int(_hp_pct.get(int(unit_id), 0))

func unit_mp(unit_id: int) -> int:
	return int(_mp.get(int(unit_id), 0))

func is_active_turn(unit_id: int) -> bool:
	return bool(_active.get(int(unit_id), false))

func is_victory() -> bool:
	return _victory

func gil() -> int:
	return _gil

func casualties() -> int:
	return _casualties

func main_character_equipped(item_id: int) -> bool:
	return bool(_equipped.get(int(item_id), false))

func date() -> Array:
	return _date

func unit_location(unit_id: int) -> Array:
	return _unit_loc.get(int(unit_id), [])

func team_location(team_id: int) -> Array:
	return _team_loc.get(int(team_id), [])


## Human-readable dump of everything this state forces (for F3 / debug logs).
func describe() -> String:
	var parts: Array = []
	for id in _vars:
		parts.append("Var%d=%d" % [id, _vars[id]])
	for id in _present:
		if _present[id]:
			parts.append("present(%d)" % id)
	for id in _hp:
		parts.append("hp(%d)=%d" % [id, _hp[id]])
	for id in _mp:
		parts.append("mp(%d)=%d" % [id, _mp[id]])
	for id in _active:
		if _active[id]:
			parts.append("turn(%d)" % id)
	if _victory:
		parts.append("victory")
	return ", ".join(parts) if not parts.is_empty() else "(empty)"


## Turn one condition's `requirements` list (raw BattleConditional records, as
## served by [BattleConditionalDatabase]) into the minimal ForcedDirectorState that
## makes EVERY requirement hold. This is the guard inverter: each opcode maps to the
## smallest read that satisfies it — `Variable ==(id,k)` → var id=k; `HP >=(u,1)` →
## hp(u)=1; `Present(u)` → present(u); `Victory()` → true; etc. Unhandled opcodes are
## skipped with a warning (the director fails-closed on them, so the plan would then
## report the step unverifiable — never a silent lie).
static func synthesize(requirements: Array) -> ForcedDirectorState:
	var s := ForcedDirectorState.new()
	s.apply_requirements(requirements)
	return s


## Accumulate `requirements` onto this state (used by [method synthesize] and to
## layer a manual override — e.g. the preemption test polluting a synthesized state).
func apply_requirements(requirements: Array) -> void:
	for req in requirements:
		_apply_requirement(req)


func _apply_requirement(req: Dictionary) -> void:
	var op := int(req.get("opcode", -1))
	# Operands read by NAME through the shared reader, mirroring ScenarioDirector
	# (ADR-0059) — the same catalog the director evaluates against, inverted here.
	var a := BattleConditionalSet.args(req)
	match op:
		BattleConditionalOpcode.VARIABLE_EQ, BattleConditionalOpcode.VARIABLE_GE, BattleConditionalOpcode.VARIABLE_LE:
			# ==/>=/<= are all satisfied by setting the var equal to the operand.
			set_variable(a.raw("Variable"), a.raw("Value"))
		BattleConditionalOpcode.UNIT_PRESENT:
			set_present(a.raw("Unit"))
		BattleConditionalOpcode.HP_GE, BattleConditionalOpcode.HP_LE:
			set_hp(a.raw("Unit"), a.raw("Value"))
		BattleConditionalOpcode.HP_0X0007, BattleConditionalOpcode.HP_0X0008:  # HP % >=/<=
			set_hp_percent(a.raw("Unit"), a.raw("Value"))
		BattleConditionalOpcode.MP_GE, BattleConditionalOpcode.MP_LE:
			set_mp(a.raw("Unit"), a.raw("Value"))
		BattleConditionalOpcode.ACTIVE_TURN:
			set_active_turn(a.raw("Unit"))
		BattleConditionalOpcode.MAIN_CHARACTER_EQUIP:
			set_equipped(a.raw("Item"))
		BattleConditionalOpcode.GIL_GE, BattleConditionalOpcode.GIL_LE:
			set_gil(a.raw("Value"))
		BattleConditionalOpcode.CASUALTIES_GE, BattleConditionalOpcode.CASUALTIES_LE:
			set_casualties(a.raw("Value"))
		BattleConditionalOpcode.DATE_GE, BattleConditionalOpcode.DATE_LE:
			set_date(a.raw("Month"), a.raw("Day"))
		BattleConditionalOpcode.VICTORY:
			set_victory(true)
		BattleConditionalOpcode.UNIT_LOCATION:
			set_unit_location(a.raw("Unit"), a.raw("X"), a.raw("Y"), a.raw("Z"))
		BattleConditionalOpcode.TEAM_UNIT_LOCATION:
			set_team_location(a.raw("Team ID"), a.raw("X"), a.raw("Y"), a.raw("Z"))
		_:
			push_warning("[ForcedDirectorState] cannot synthesize unhandled opcode 0x%04x" % op)
