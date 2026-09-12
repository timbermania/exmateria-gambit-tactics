class_name GambitVerdictProbe
extends RefCounted

## THE KERNEL'S PER-SLOT VERDICT, READ OFF ANY HOST THAT OWNS A BATTLE (ADR-0275 dec. 4, #1211).
##
## `evaluate_gambits_up_to` has twelve distinct outcomes per slot and, before dec. 4, exactly one
## of them stamped a reason anywhere a host could read. The kernel now writes
## `{verdict, condition index, opcode, evaluated mask}` per pass into each slot's two reserved
## ints. This turns those ints into rows.
##
## === WHY IT IS NOT PART OF THE LAB ANY MORE ================================================
##
## It was, and that was the whole reason the verdict could only be read in a scene with no
## deployment: [GambitLabScene] owned the reader, the `REASON_*` table, the row builder and the
## four naming helpers as private members, so `GambitVerdictReader` had exactly two consumers in
## the tree and both were the lab. A host that wanted the readout had to become the lab.
##
## Nothing here is lab-shaped. Given a [GPUBatchSimulator], a battle index and a name table it
## answers rows — so the lab reads its synthesized cell and [GambitBattle] reads the battle you
## are actually playing, through ONE implementation. Two readers of the same ints that could
## disagree about what they mean is the defect this class exists to make impossible.
##
## === WHAT IT REFUSES TO ANSWER BLANK =======================================================
##
## `VERDICT_NONE == 0` is a real answer — *this call did not reach this slot* — so every slot is
## returned, including the ones that never moved. A row set that omitted them would say "no
## reason", which is the one failure mode dec. 18 says a debugging instrument must not have.
## A zero from a blind instrument is not absence.

const UnitField = GPUCombatPacker.UnitField

## Every `REASON_*` the kernel declares, parsed out of the same header the verdict comes from, so
## the name a host prints and the number the GPU wrote cannot drift.
const KERNEL_HEADER := "res://src/gpu/shaders/combat_common.glslinc"

## Unit state ids, for the state column.
const STATE_NAMES := ["IDLE", "MOVING", "ATTACKING", "DEAD", "SPELL_CHARGING",
	"AWAITING_IMPACT", "CELEBRATING", "REACTING"]

var reader := GambitVerdictReader.new()
var reason_of: Dictionary = {}          # 2 -> "CAN_ATTACK"

var _simulator = null
var _battle: int = 0
var _names: Array = []


## Load the verdict layout out of the kernel header. False when the layout could not be read —
## the caller must report `reader.checks` and NOT fall back to a blank readout, which would be
## indistinguishable from "nothing declined".
func load_layout() -> bool:
	if not reader.load_layout():
		return false
	_load_reason_names()
	return true


## Point at a battle. `names` is GPU unit index → display name, in the GPU's own order — which is
## TEAM order, not the host's authoring order: `set_battle_units` writes team 0 into indices
## `0..n0-1` and team 1 after it. A name table built in any other order makes every `target=` and
## every row heading name the wrong unit, in a readout whose whole job is to say WHO.
func bind(simulator, battle_index: int, names: Array) -> void:
	_simulator = simulator
	_battle = battle_index
	_names = names


func bound() -> bool:
	return _simulator != null and is_instance_valid(_simulator)


func snapshot() -> Dictionary:
	if not bound():
		return {}
	return _simulator.snapshot_battle(_battle)


## One row per unit, or `[]` when nothing is bound. [param count] is how many units to read; pass
## the host's own unit count rather than deriving one, because a host knows which slots of the
## battle buffer it actually filled.
func rows(count: int) -> Array:
	var snap := snapshot()
	if snap.is_empty():
		return []
	var out: Array = []
	for u in range(count):
		out.append(row_for(u, snap))
	return out


## One unit's whole picture: the kernel's per-slot verdicts PLUS the three unit fields a verdict
## cannot answer. The verdict says which slot committed and why the others declined; it says
## nothing about what happened to `U_TARGET` afterwards, and a target rewritten downstream of the
## decision is invisible to it. The two are read together or not at all.
func row_for(unit: int, snap: Dictionary) -> Dictionary:
	var battle: PackedInt32Array = snap["battle"]
	var gambits: PackedInt32Array = snap["gambits"]
	var slots: Array = []
	for s in range(GPUConstants.MAX_GAMBITS):
		slots.append(reader.read_slot(gambits, unit, s))
	return {
		"unit": unit,
		"name": unit_name(unit),
		"state": _unit_field(battle, unit, UnitField.STATE),
		"target": _unit_field(battle, unit, UnitField.TARGET),
		"reason": _unit_field(battle, unit, UnitField.DBG_STATE_REASON),
		"gambit": _unit_field(battle, unit, UnitField.CURRENT_GAMBIT),
		"hp": _unit_field(battle, unit, UnitField.HP),
		"x": _unit_field(battle, unit, UnitField.POS_X),
		"z": _unit_field(battle, unit, UnitField.POS_Z),
		"slots": slots,
	}


func _unit_field(battle: PackedInt32Array, unit: int, field: int) -> int:
	var offset: int = GPUCombatPacker.BATTLE_HEADER_SIZE + unit * GPUCombatPacker.UNIT_SIZE
	if offset + field >= battle.size():
		return 0
	return battle[offset + field]


func state_name(s: int) -> String:
	return STATE_NAMES[s] if s >= 0 and s < STATE_NAMES.size() else str(s)


func reason_name(r: int) -> String:
	return reason_of.get(r, str(r))


func unit_name(u: int) -> String:
	if u < 0:
		return "none"
	return String(_names[u]) if u < _names.size() else "u%d" % u


## Is this slot the ADR-0048 safety net? Its index is `MAX_USER_GAMBITS` — DERIVED (dec. 19),
## because a literal 5 is a number that stops being true the day the cap moves.
func is_safety_net_slot(slot: int) -> bool:
	return slot == GPUConstants.MAX_USER_GAMBITS


func _load_reason_names() -> void:
	var src := FileAccess.get_file_as_string(KERNEL_HEADER)
	var rx := RegEx.new()
	rx.compile("(?m)^const int REASON_([A-Za-z_0-9]+)\\s*=\\s*(-?[0-9]+)\\s*;")
	for m in rx.search_all(src):
		reason_of[int(m.get_string(2))] = m.get_string(1)
