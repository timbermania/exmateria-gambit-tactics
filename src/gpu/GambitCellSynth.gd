class_name GambitCellSynth
extends RefCounted

## THE GAMBIT LAB'S SYNTHESIZER — a CELL, its MIRROR, and the refusals it will not fake.
## ADR-0275 decs. 1, 2, 8-12; issue #1129.
##
## A pure function: [method build] turns `(ability_id, gambit, axis)` into a CELL SPEC — one
## actor, one dummy in the axis's pool, one condition, one boot, placed so that exactly one
## quantity decides the slot. No scene, no `CombatLoop`, no `RenderingDevice`. It lives under
## `src/gpu/` rather than `tests/` (dec. 13) because production could never consult it there,
## and because both arms of the lab — the live scene and dec. 13's fleet sweeper — have to
## synthesize the SAME cell or the two instruments describe different experiments.
##
## === THE CELL SPEC IS A SCENARIO DICT, AND THAT IS THE WHOLE INTEGRATION ====================
##
## `spec["scenario"]` is shaped exactly like one of the 84 fixtures in
## `tests/gambit_scenarios/`, so [GambitScenarioBoot] boots it with no new code path:
## `spawn_unit`, `encode_units` and `build_battle_spec` take it as-is. A synthesized cell and
## a replayed fixture therefore reach the GPU through ONE boot, which is the same argument
## [GambitScenarioBoot] itself records — a trace is only an explanation if it is a trace of
## that battle.
##
## === "EXACTLY ONE DUMMY" IS ONE DUMMY IN THE AXIS'S POOL, NOT ONE UNIT ON THE FIELD ========
##
## dec. 1's primitive is "one actor, exactly one dummy, one condition, one boot", and an
## ALLY-POOL cell cannot be run that way: with no team-1 unit, `check_victory` returns
## `RESULT_TEAM_0_WINS` on tick 1 and the actor's first turn is 29 ticks later, so every slot
## reads `NONE(not walked)`. That was MEASURED on `cell/COND_IS_ALIVE/positive`, not reasoned
## about. So an allied cell carries one inert OPPONENT for liveness, and the reading stays what
## dec. 1 asks for: the axis's pool still holds exactly one candidate, which is the property
## dec. 1's argument actually turns on. [method _liveness_opponent] carries the full argument
## and the placement that keeps the third unit out of every action's reach.
##
## === WHAT A MIRROR IS, AND WHY A PAIR IS THE UNIT OF EVIDENCE ===============================
##
## dec. 2. Every positive cell auto-generates its MIRROR: the same cell with the one knob
## moved to the other side of that condition's boundary, and nothing else touched. A pair that
## fails to FLIP is a defect regardless of what anyone expected — which is what makes the
## instrument self-checking instead of a generator of claims. [method build_pair] returns the
## positive and every mirror the row can reach, and counts the ones it cannot.
##
## === THE STRADDLE TABLE IS HAND-AUTHORED, AND A GENERIC ±1 IS BANNED ========================
##
## dec. 8. [constant STRADDLE_TABLE] carries one row per `COND_*` opcode the kernel declares.
## Each row names the kernel's own predicate, which knob moves, WHOSE state the knob is, what
## int B will measure, and which side of the boundary is positive. Perturbing an operand by ±1
## without reading the predicate is rejected: it manufactures false negatives silently, and
## `COND_IN_RANGE` alone has four different boundaries depending on the actor's weapon — two of
## them with a NEAR edge as well as a far one. `tools/check_gambit_straddle_table.py` reds when
## the kernel declares an opcode this table has no row for.
##
## === IT REFUSES, AND THE REFUSAL IS THE PRODUCT =============================================
##
## decs. 9 and 10. An unplaceable or unseedable cell REFUSES and is counted; it is never
## nudged. A nudged dummy still produces a verdict, and that verdict now describes a different
## experiment from the one on its label — it fails PRODUCTIVELY, which is the most dangerous
## option on the table. Three classes of refusal come out of this file, and all three are
## findings rather than gaps in it:
##
##   * `COND_ALWAYS` has no operand to move (dec. 9 names it).
##   * `COND_IS_DEAD` / `COND_IS_ALIVE` cannot be seeded at all. `is_unit_dead` reads
##     `FLAG_DEAD` in `U_FLAGS`, and `FLAG_DEAD` is written ONLY by `stage_damage.glsl`
##     (plus `GPUBatchSimulator` marking unused slots); the battle spec
##     [GambitScenarioBoot.build_battle_spec] builds has no `flags` channel, and `hp: 0` does
##     not flag anybody. A cell cannot boot with a corpse on the field — and neither can a
##     battle, which is why the spec is REFUSED rather than widened.
##   * A boundary that falls off MAP116, or off the cardinal line an `ATTACK_LUNGING` weapon
##     needs, or below `check_arcing`'s `h_distance >= 3` floor.
##
## === MAP116, AND WHY NOT THE FIXTURES' OWN MAP ==============================================
##
## dec. 11. 11x11, 121/121 walkable, uniformly height 0 — measured with
## `tools/preview_map.py MAP116`. MAP042 (67 of the 84 fixtures) has a largest fully-flat
## Manhattan disk of radius **1**, so a controlled-distance cell is geometrically impossible
## there. Flat matters because 46 of 84 fixtures use plain `ATTACK`, whose reach test
## `can_attack_target` is height- AND line-of-sight-sensitive: on uneven ground the separation
## stops being the only quantity that moved.
##
## ⚠️ MAP116 IS STILL BOUNDED, and the bound is not the one dec. 11's prose suggests. From
## (5,5) the greatest MANHATTAN separation is 10 — but it is reached only on the diagonal
## (e.g. `(9,9)` is 8). The greatest CARDINAL separation is 5. Every `ATTACK_LUNGING` straddle
## and every near-edge straddle is bounded by the second number, not the first.
##
## === THROW IS STRADDLED BY SPEED ===========================================================
##
## dec. 12. Throw's reach is not in the attributes table: `get_effective_ability_range` returns
## `speed / 2 + 1` for any ability carrying `ABFLAG_THROW_RANGE`
## (`combat_common.glslinc:1516-1519`), unbounded above and unreachable by placement. The cell
## spec RECORDS the actor's Speed for every cell, not only the throw ones, because Speed also
## decides who acts first and a cell whose actor never gets a turn reads `VERDICT_NONE`.
##
## === THE COVERAGE LINE IS MEASURED, NEVER QUOTED ============================================
##
## dec. 22 bans a raw-opcode injection path and asks for a coverage line instead.
## [method encoder_coverage] MEASURES it: it pushes the supported cross product of
## `GambitCondition` and `TargetSelector` through the real [GambitEncoder] and reports which
## kernel opcodes never came out. The ADR's "two conditions and two selectors" is a number with
## a date on it — #1114 moved it from six-and-two in the hours before the ADR was written — so
## this function exists precisely so nobody quotes that sentence again.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias line per file
# keeps every use site's spelling, and makes a grep for the façade a complete census of
# host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase

# =============================================================================================
# THE BOARD
# =============================================================================================

## dec. 11. The only map of 119 with a flat Manhattan disk above radius 3.
const MAP := "MAP116"
const MAP_W := 11
const MAP_H := 11

## The actor never moves off this tile, so every separation in this file is measured from it.
const ORIGIN_X := 5
const ORIGIN_Z := 5

## The greatest Manhattan separation reachable from [constant ORIGIN_X]/[constant ORIGIN_Z] —
## the corner, on the diagonal. DERIVED, so an origin move cannot leave it stale.
const MAX_SEPARATION := (MAP_W - 1 - ORIGIN_X) + (MAP_H - 1 - ORIGIN_Z)

## The greatest separation reachable WITHOUT leaving the cardinal line, which is what
## `check_lunging`'s `ax != tx && az != tz` rejection requires. Half of MAX_SEPARATION, and the
## number that bounds every lunging straddle.
const MAX_CARDINAL := MAP_W - 1 - ORIGIN_X

## Two units cannot share a tile on MAP116: it is single-level, so a separation of 0 needs the
## under-a-bridge geometry ADR-0224 dec. 6 allows and this map does not have.
const MIN_SEPARATION := 1

# =============================================================================================
# THE ROSTER
# =============================================================================================

## The actor's Speed. High on purpose: the turn meter is `TURN_METER_FULL` (3600) and a cell
## whose actor has not reached a turn inside its tick budget reads `VERDICT_NONE`, which
## [GambitVerdictReader] renders `NONE(not walked)` — indistinguishable from an instrument that
## never ran. Overridden, and RECORDED, by the throw straddle (dec. 12).
const ACTOR_SPEED := 120

## The dummy is INERT BY CONSTRUCTION, and each of these three is load-bearing:
##   `move: 0`      — it cannot walk, so the separation the cell was built around is the
##                    separation the kernel measures. A dummy that closes the distance turns a
##                    controlled straddle into a race.
##   `speed: 1`     — it reaches a turn ~120x slower than the actor, so its own safety net
##                    (ADR-0048, and it has one: every unit routes through the encoder) does not
##                    act before the actor's verdict is written.
##   `max_hp: 100`  — `get_hp_percent` is `hp * 100 / max_hp`, so a max of 100 makes `hp` the
##                    percent EXACTLY. Any other max quantises the HP boundary and a straddle
##                    one step either side of it stops landing where the table says.
const DUMMY_SPEED := 1
const DUMMY_MOVE := 0
const SCALAR_MAX := 100

## `max_mp` on the ACTOR, for the same exactness reason — and it is the actor's, not the
## dummy's, because `COND_MP_ABOVE`/`_BELOW` read `unit_id` and not `target_id`
## (`stage_compute.glsl:200-206`). See [constant STRADDLE_TABLE]'s note on that row.
const ACTOR_MAX_MP := 100

## The status bit the `COND_HAS_STATUS` / `COND_NOT_STATUS` rows straddle, and the choice
## INVERTS the usual advice about hollow bits.
##
## A gambit on a declaration-only `STATUS_*` encodes cleanly and never fires, which is a trap
## everywhere else. Here it is the requirement: `evaluate_condition` reads the bit out of
## `U_STATUS_FLAGS_LO` directly, so the bit's truth does not depend on any OTHER kernel site
## reading it — and a bit nothing else reads cannot perturb the cell. `STATUS_FROG` (14) is
## marked `UNREAD -- should be built` in `combat_common.glslinc`, is a real FFT status name
## (unlike `STATUS_BLIND` / `STATUS_CURSE`, both RESERVED and slated for deletion), and is not
## `STATUS_DEAD` (bit 0, the trap: `is_unit_dead` reads `FLAG_DEAD`, a different word).
const INERT_STATUS := &"frog"

## How many TURNS a cell is given before it is called blind. Turns, not ticks — and that
## distinction is the whole reason this is not a constant budget.
##
## 🔴 A FIXED TICK BUDGET WOULD HAVE READ EVERY THROW CELL AS BLIND, and the conclusion a
## session would have drawn is "dec. 12's Speed straddle does not work". `compute_unit_state`
## adds `max(1, U_SPEED)` to the turn meter every tick and a unit is ready at
## `TURN_METER_FULL` (3600), so time-to-first-turn is `3600 / Speed` ticks: 30 at
## [constant ACTOR_SPEED], and **450 at the Speed 8 the throw straddle demands**. Throw's reach
## is `speed / 2 + 1`, so reaching a boundary at separation 5 means Speed 8 and reaching the
## map's diagonal maximum of 10 means Speed 18 — on an 11x11 board there is no throw boundary a
## normally-fast unit can straddle at all. The budget is therefore DERIVED from the actor's own
## Speed by [method ticks_for_speed], and the cell spec carries it.
const TURNS_WANTED := 3

## Slack on top of the derived budget, for the ticks a turn's own reconfiguration costs.
const TICK_MARGIN := 30

# =============================================================================================
# THE STRADDLE TABLE (dec. 8) — ONE ROW PER `COND_*` THE KERNEL DECLARES
# =============================================================================================

## Hand-authored, one row per opcode. `tools/check_gambit_straddle_table.py` reds when
## `combat_common.glslinc` declares a `COND_*` with no row here, when a row names an opcode the
## kernel does not declare, and when a row is missing a required field.
##
## Fields:
##   `predicate`   the kernel's own arm, quoted, so the table can be checked against the source
##                 rather than believed. Every `positive`/`negative` below is derived from it.
##   `knob`        the ONE quantity the mirror moves. Anything else differing between a cell and
##                 its mirror makes the pair unattributable.
##   `subject`     whose state the knob is — `dummy`, `actor`, `placement`, or `action`. The
##                 `actor` rows are the surprise, and they are a finding: see `COND_MP_*`.
##   `measures`    what int B carries on the failing side (`combat_common.glslinc`'s own list).
##   `positive`    which side of the boundary makes the condition TRUE, as prose in the knob's
##                 own units. Resolved to numbers by [method _straddle].
##   `negative`    the other side. `""` when the row is not straddleable.
##   `refusal`     why there is no negative, for the rows that have none (dec. 9).
const STRADDLE_TABLE := {
	"COND_ALWAYS": {
		"predicate": "return true;",
		"knob": "", "subject": "", "measures": "0 — cannot fail",
		"positive": "any placement", "negative": "",
		"refusal": "structurally unstraddleable — the kernel's arm is a bare `return true` "
			+ "with no operand to move. dec. 9 names this row explicitly.",
	},
	"COND_HP_BELOW": {
		"predicate": "measured = get_hp_percent(battle_id, target_id); return measured < condition_value;",
		"knob": "dummy_hp_percent", "subject": "dummy", "measures": "target HP percent",
		"positive": "threshold - 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_HP_ABOVE": {
		"predicate": "measured = get_hp_percent(battle_id, target_id); return measured > condition_value;",
		"knob": "dummy_hp_percent", "subject": "dummy", "measures": "target HP percent",
		"positive": "threshold + 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_DISTANCE_LESS": {
		"predicate": "measured = manhattan_distance(u, t); return measured < condition_value;",
		"knob": "separation", "subject": "placement", "measures": "manhattan distance",
		"positive": "threshold - 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_DISTANCE_GREATER": {
		"predicate": "measured = manhattan_distance(u, t); return measured > condition_value;",
		"knob": "separation", "subject": "placement", "measures": "manhattan distance",
		"positive": "threshold + 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_HAS_STATUS": {
		"predicate": "bool held = has_status(battle_id, target_id, condition_value); return held;",
		"knob": "dummy_status_bit", "subject": "dummy",
		"measures": "target U_STATUS_FLAGS_LO (the whole low word, not the asked-for bit)",
		"positive": "bit SET on the dummy", "negative": "bit CLEAR on the dummy",
		"refusal": "",
	},
	"COND_NOT_STATUS": {
		"predicate": "bool held = has_status(battle_id, target_id, condition_value); return !held;",
		"knob": "dummy_status_bit", "subject": "dummy",
		"measures": "target U_STATUS_FLAGS_LO",
		"positive": "bit CLEAR on the dummy", "negative": "bit SET on the dummy",
		"refusal": "",
	},
	"COND_IS_DEAD": {
		"predicate": "bool dead = is_unit_dead(battle_id, target_id); return dead;",
		"knob": "dummy_flag_dead", "subject": "dummy", "measures": "target HP",
		"positive": "FLAG_DEAD set on the dummy", "negative": "",
		"refusal": "UNSEEDABLE, and this is a finding rather than a gap here. `is_unit_dead` "
			+ "reads FLAG_DEAD in U_FLAGS; FLAG_DEAD is written only by stage_damage.glsl and "
			+ "by GPUBatchSimulator marking UNUSED slots. `build_battle_spec` has no `flags` "
			+ "channel and `hp: 0` flags nobody, so a cell cannot boot with a corpse on the "
			+ "field. Neither can a battle — which is why the cell is refused rather than the "
			+ "spec widened (dec. 10, and dec. 22's argument against exercising battles that "
			+ "cannot exist).",
	},
	"COND_IS_ALIVE": {
		"predicate": "bool dead = is_unit_dead(battle_id, target_id); return !dead;",
		"knob": "dummy_flag_dead", "subject": "dummy", "measures": "target HP",
		"positive": "the dummy's default — nothing sets FLAG_DEAD at boot", "negative": "",
		"refusal": "the POSITIVE side is free and the MIRROR is unseedable, for the reason "
			+ "`COND_IS_DEAD` records. The positive cell is therefore vacuous on its own: it "
			+ "passes for every unit in every battle, and dec. 9's label is the whole value.",
	},
	"COND_MP_ABOVE": {
		"predicate": "measured = get_mp_percent(battle_id, unit_id); return measured > condition_value;",
		"knob": "actor_mp_percent", "subject": "actor", "measures": "ACTOR MP percent",
		"positive": "threshold + 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_MP_BELOW": {
		"predicate": "measured = get_mp_percent(battle_id, unit_id); return measured < condition_value;",
		"knob": "actor_mp_percent", "subject": "actor", "measures": "ACTOR MP percent",
		"positive": "threshold - 1", "negative": "threshold",
		"refusal": "",
	},
	"COND_TEAM_ALLY": {
		"predicate": "measured = get_team(battle_id, target_id); return get_team(battle_id, unit_id) == measured;",
		"knob": "dummy_team", "subject": "dummy", "measures": "target team",
		"positive": "dummy on the actor's team", "negative": "dummy on the other team",
		"refusal": "",
	},
	"COND_TEAM_ENEMY": {
		"predicate": "measured = get_team(battle_id, target_id); return get_team(battle_id, unit_id) != measured;",
		"knob": "dummy_team", "subject": "dummy", "measures": "target team",
		"positive": "dummy on the other team", "negative": "dummy on the actor's team",
		"refusal": "",
	},
	"COND_IN_RANGE": {
		"predicate": "return target_in_action_range(battle_id, unit_id, target_id, action_type, action_id);",
		"knob": "separation OR actor_speed — the ACTION decides which", "subject": "action",
		"measures": "manhattan distance (the separation, against a reach the row cannot print)",
		"positive": "at the action's own reach", "negative": "one tile beyond it — and, for "
			+ "ATTACK_STRIKING and ATTACK_ARCING, a NEAR edge as well",
		"refusal": "",
	},
}

## Every knob [method _straddle] can return, so a row naming one that does not exist is a
## parse-time error in the guard rather than a silently skipped cell.
const KNOBS := ["", "dummy_hp_percent", "dummy_status_bit", "dummy_flag_dead", "dummy_team",
	"actor_mp_percent", "separation", "actor_speed",
	"separation OR actor_speed — the ACTION decides which"]

# =============================================================================================
# BUILD
# =============================================================================================

## The POSITIVE cell for `gambit`'s condition at index [param axis], acting with
## [param ability_id] (`-1` for the control verbs, which take the equipped weapon's reach).
##
## Returns a cell spec. A spec is ALWAYS returned: when the cell cannot be built it comes back
## with `refused == true` and a `refusal` naming the boundary that could not be reached, because
## dec. 10's refusal is the product and a null would make it uncountable.
static func build(ability_id: int, gambit, axis: int = 0) -> Dictionary:
	return _build_side(ability_id, gambit, axis, "positive", 0)


## The positive cell and every MIRROR the row can reach (dec. 2).
##
## Returns `{positive, mirrors, refused, refusals}`. `mirrors` is an Array of specs, one per
## boundary side the row declares — `COND_IN_RANGE` on an `ATTACK_ARCING` weapon has TWO, a far
## edge and `check_arcing`'s `h_distance >= 3` near floor, and a pair that flips on one and not
## the other is a different finding from a pair that does not flip at all. `refusals` carries
## the reason for each side that could not be built; `refused` is its count, which is dec. 9's
## to-do list.
static func build_pair(ability_id: int, gambit, axis: int = 0) -> Dictionary:
	var positive := _build_side(ability_id, gambit, axis, "positive", 0)
	var mirrors: Array = []
	var refusals: Array = []
	if positive["refused"]:
		refusals.append("positive: %s" % positive["refusal"])
	var sides: int = int(positive["negative_sides"])
	for i in range(sides):
		var m := _build_side(ability_id, gambit, axis, "mirror", i)
		mirrors.append(m)
		if m["refused"]:
			refusals.append("mirror %d: %s" % [i, m["refusal"]])
	if sides == 0 and not positive["refused"]:
		refusals.append("mirror: %s" % String(positive["axis"].get("refusal", "no negative case available")))
	return {
		"positive": positive,
		"mirrors": mirrors,
		"refused": refusals.size(),
		"refusals": refusals,
	}


## A LADDER cell (dec. 2's third shape): `rungs` are authored into slots 0..N-1 in order, and
## the expectation is that each DECLINES FOR THE PREDICTED REASON before the last one fires.
## "Slot N fired" alone is not a pass, so the spec's `expect` carries a row per rung.
##
## 🔴 THE LADDER IS BUILT THROUGH [GambitEncoder], AND THAT CAPS IT AT `MAX_USER_GAMBITS`.
## #1128 measured what pass 1 does: it walks slots `0..MAX_GAMBITS-1`, slot `MAX_USER_GAMBITS`
## IS ADR-0048's injected safety net, the net's condition is `Always` and cannot fail, and
## firing does `return true`. So a rung authored at or past the net's index can never be
## reached, and a ladder longer than `MAX_USER_GAMBITS` is a cell that silently tests the net.
## Seating the rungs through `sim.set_unit_gambits` directly would lift the cap —
## `GambitVerdictCellsTest` does exactly that — but dec. 22 bans a raw-opcode injection path as
## a lab FEATURE, and dec. 20 keeps the encoder in the loop precisely so editor->encoder drift
## stays visible. So the cap is accepted and the net is LABELLED (dec. 19): the expectation
## carries its row at `GPUConstants.MAX_USER_GAMBITS`, predicted FIRED when every authored rung
## declines and `NONE(not walked)` when one of them fires first.
static func build_ladder(ability_id: int, rungs: Array, axes: Array = []) -> Dictionary:
	var spec := _empty_spec("ladder")
	spec["axis"] = {"opcode": "", "opcode_name": "ladder", "knob": "", "subject": "slot order",
		"side": "ladder", "rungs": rungs.size(),
		"predicate": "slots 0..N-1 each decline FOR THE PREDICTED REASON, then slot N fires "
			+ "(dec. 2 — \"slot N fired\" alone is not a pass)",
		"measures": "each rung's own payload; see the per-rung rows below"}
	if rungs.is_empty():
		spec["refused"] = true
		spec["refusal"] = "a ladder needs at least one rung"
		return spec
	if rungs.size() > GPUConstants.MAX_USER_GAMBITS:
		spec["refused"] = true
		spec["refusal"] = ("a ladder of %d rungs exceeds MAX_USER_GAMBITS (%d): pass 1 walks "
			+ "slot %d as ADR-0048's safety net, whose Always cannot fail, so rung %d could "
			+ "never be reached. REFUSED rather than truncated (dec. 10).") % [
				rungs.size(), GPUConstants.MAX_USER_GAMBITS, GPUConstants.MAX_USER_GAMBITS,
				GPUConstants.MAX_USER_GAMBITS]
		return spec

	# Every rung is straddled to its NEGATIVE side except the last, which is straddled
	# positive — that is what makes the ladder a ladder and not N independent cells. A rung
	# whose axis cannot be straddled refuses the whole ladder: a rung that cannot be made to
	# decline is a rung that might fire, and the cell would then be describing a different
	# climb from the one on its label.
	var rung_specs: Array = []
	for i in range(rungs.size()):
		var ax: int = int(axes[i]) if i < axes.size() else 0
		var side := "positive" if i == rungs.size() - 1 else "mirror"
		var s := _build_side(ability_id, rungs[i], ax, side, 0)
		rung_specs.append(s)
		if s["refused"]:
			spec["refused"] = true
			spec["refusal"] = "rung %d (%s): %s" % [i, s["axis"].get("opcode_name", "?"), s["refusal"]]
			return spec

	# One board for the whole ladder. Each rung's straddle is a knob setting, and a ladder is
	# only coherent when the rungs' knobs do not collide: two rungs straddling `separation` to
	# different values cannot both hold on one board, and a ladder that quietly took the last
	# one would be the productive failure dec. 10 bans.
	var knobs: Dictionary = {}
	for i in range(rung_specs.size()):
		var k: String = String(rung_specs[i]["axis"].get("knob", ""))
		var v = rung_specs[i]["axis"].get("knob_value", null)
		if k == "" or v == null or not KNOBS.has(k):
			continue
		if knobs.has(k) and knobs[k] != v:
			spec["refused"] = true
			spec["refusal"] = ("rungs disagree about `%s` (%s vs %s): one board cannot hold "
				+ "both, and taking the last would relabel the cell (dec. 10).") % [
					k, str(knobs[k]), str(v)]
			return spec
		knobs[k] = v

	# One dummy, so every rung's CONDITION POOL has to be looking at the same team. A ladder
	# mixing an ally-pool rung with an enemy-pool rung would read NO_CANDIDATE on one of them —
	# a real verdict, about the roster rather than about the rung's condition, and the spec's
	# label would be describing a decline that never happened.
	var team_of_rung0: bool = _pool_is_enemy(rungs[0])
	for i in range(1, rungs.size()):
		if _pool_is_enemy(rungs[i]) != team_of_rung0:
			spec["refused"] = true
			spec["refusal"] = ("rung %d's condition pool looks at the other team from rung 0's. "
				+ "With one dummy, one of them would read NO_CANDIDATE — a verdict about the "
				+ "ROSTER, not about the rung. REFUSED rather than relabelled (dec. 10).") % i
			return spec

	var cardinal := false
	for s2 in rung_specs:
		if bool((s2["axis"] as Dictionary).get("cardinal", false)):
			cardinal = true
	var separation: int = int(knobs.get("separation", _default_separation(ability_id, {})))
	var tile = place(separation, cardinal)
	if tile == null:
		spec["refused"] = true
		spec["refusal"] = "the ladder's separation %d%s is unplaceable on %s" % [
			separation, " on the cardinal line" if cardinal else "", MAP]
		return spec
	var dummy_team: int = 1 if team_of_rung0 else 0
	if knobs.has("dummy_team"):
		dummy_team = int(knobs["dummy_team"])

	var actor := _actor_cfg(rungs[0], knobs)
	actor["gambits"] = rungs.duplicate()
	var roster: Array = [actor, _dummy_cfg(dummy_team, tile, knobs)]
	if dummy_team == 0:
		roster.append(_liveness_opponent())
		spec["notes"].append("allied axis pool, so one inert OPPONENT rides along for battle "
			+ "liveness — see _liveness_opponent")
	spec["scenario"] = {
		"rule": "CELL",
		"name": "ladder_%d_rungs" % rungs.size(),
		"map": MAP,
		"seed": 42,
		"max_ticks": ticks_for_speed(int(actor["speed"])),
		"units": roster,
	}
	spec["ticks"] = ticks_for_speed(int(actor["speed"]))
	spec["separation"] = separation
	spec["actor_speed"] = int(actor["speed"])
	spec["notes"].append("the safety net sits at slot %d and is LABELLED, never suppressed "
		% GPUConstants.MAX_USER_GAMBITS + "(dec. 19)")

	var expect: Array = []
	for i in range(rung_specs.size()):
		var row: Dictionary = (rung_specs[i]["expect"][0] as Dictionary).duplicate(true)
		row["slot"] = i
		expect.append(row)
	# 🔴 EVERY SLOT PAST THE FIRING RUNG IS `NONE(not walked)`, NOT `DISABLED` — and this
	# prediction was WRONG on the first run, which is exactly what the scorer is for. The
	# reasoning that got it wrong: `encode_gambits` pads the authored region with null and
	# `_pack_gambits` reads null as disabled, so a padding slot the kernel WALKS stamps
	# `VERDICT_DISABLED`. But the last rung FIRES, and firing does `return true` out of pass 1
	# (#1128's finding) — so the walk never reaches the padding at all. Predicting DISABLED for
	# slots 3-4 while predicting NONE for the net at slot 5 was self-contradictory, and the run
	# said so: `p1 is NONE(not walked), predicted DISABLED`, twice.
	#
	# The general rule, and it is worth carrying: a padding slot's verdict is DISABLED only in a
	# cell where nothing before it fires. In a ladder the whole point is that something does.
	for i in range(rung_specs.size(), GPUConstants.MAX_USER_GAMBITS + 1):
		var what := "ADR-0048's safety net" if i == GPUConstants.MAX_USER_GAMBITS \
			else "encoder padding — no authored gambit in this slot"
		expect.append({"unit": 0, "slot": i, "p1": "NONE",
			"why": "%s — not walked, because rung %d fired and pass 1 returns on a fire"
				% [what, rungs.size() - 1]})
	spec["expect"] = expect
	spec["name"] = "ladder/%d_rungs" % rungs.size()
	return spec


# =============================================================================================
# THE ONE BUILDER BOTH SIDES GO THROUGH
# =============================================================================================

## `side` is `"positive"` or `"mirror"`; `which` picks among a row's several negative edges.
static func _build_side(ability_id: int, gambit, axis: int, side: String, which: int) -> Dictionary:
	var spec := _empty_spec(side)

	# === the opcode comes from the ENCODER, never from a second mapping table ===============
	# dec. 20 keeps `GambitEncoder` in the path so editor->encoder drift stays visible, and a
	# synthesizer that re-derived the opcode from `GambitCondition.Type` would be that second
	# mapping — and would go stale in exactly the direction nobody checks.
	var enc = _encode_one(gambit)
	if enc == null:
		spec["refused"] = true
		spec["refusal"] = ("GambitEncoder refused this gambit (ADR-0023 faithful-or-explicit). "
			+ "That is a COVERAGE line, not a synthesizer bug — see encoder_coverage().")
		return spec
	var conds: Array = enc["conditions"]
	if axis < 0 or axis >= conds.size():
		spec["refused"] = true
		spec["refusal"] = "axis %d is out of range: the gambit encoded %d condition(s)" % [
			axis, conds.size()]
		return spec
	var opcode: int = int(conds[axis]["type"])
	var value: int = int(conds[axis]["value"])
	var opcode_name := opcode_name_of(opcode)
	if not STRADDLE_TABLE.has(opcode_name):
		spec["refused"] = true
		spec["refusal"] = ("no straddle row for %s. tools/check_gambit_straddle_table.py is "
			+ "the guard that should have caught this before you ran it.") % opcode_name
		return spec
	var row: Dictionary = STRADDLE_TABLE[opcode_name]

	# === the straddle ======================================================================
	var st := _straddle(opcode_name, value, ability_id, side, which)
	spec["negative_sides"] = int(st["negative_sides"])
	spec["axis"] = {
		"opcode": opcode, "opcode_name": opcode_name, "condition_index": axis,
		"threshold": value, "knob": String(st.get("knob", row["knob"])),
		"subject": row["subject"], "side": side, "edge": String(st.get("edge", "")),
		"predicate": row["predicate"], "measures": row["measures"],
		"refusal": row["refusal"], "knob_value": st.get("knob_value", null),
		# `cardinal` rides on the axis because a LADDER has to know whether ANY of its rungs
		# needs the cross `check_lunging` demands — the diagonal that reaches separation 10 is
		# not available to a lunging weapon, and a ladder placed off-axis would straddle the
		# cross instead of the rung.
		"cardinal": bool(st.get("cardinal", false)),
	}
	spec["notes"].append_array(st.get("notes", []))
	# NAMED BEFORE THE REFUSAL CAN RETURN. A refused spec used to come back with an empty `name`,
	# so the census printed `REFUSED  <blank>  <reason>` — five rows that said what went wrong
	# and not which cell it was. dec. 9 makes the refusal list a to-do list, and an unnamed
	# to-do is not one.
	spec["name"] = _cell_name(opcode_name, side, String(st.get("edge", "")))
	if st["refused"]:
		spec["refused"] = true
		spec["refusal"] = String(st["refusal"])
		return spec

	# === the board =========================================================================
	# The dummy's team follows the gambit's own CONDITION POOL, because the condition has to be
	# able to SEE it: an enemy-pool slot with only an ally on the field reads NO_CANDIDATE, and
	# a NO_CANDIDATE reading says nothing about the axis the cell was built to move.
	var knobs := _knob_set(st)
	var dummy_team: int = 1 if _pool_is_enemy(gambit) else 0
	if knobs.has("dummy_team"):
		dummy_team = int(knobs["dummy_team"])
	var separation: int = int(st.get("separation", _default_separation(ability_id, st)))
	var cardinal: bool = bool(st.get("cardinal", false))
	var tile = place(separation, cardinal)
	if tile == null:
		spec["refused"] = true
		spec["refusal"] = ("separation %d%s is unplaceable on %s from (%d,%d): the Manhattan "
			+ "maximum is %d and the CARDINAL maximum is %d. NOT NUDGED (dec. 10).") % [
				separation, " on the cardinal line" if cardinal else "", MAP,
				ORIGIN_X, ORIGIN_Z, MAX_SEPARATION, MAX_CARDINAL]
		return spec

	var actor := _actor_cfg(gambit, knobs)
	var dummy := _dummy_cfg(dummy_team, tile, knobs)
	var roster: Array = [actor, dummy]
	if dummy_team == 0:
		roster.append(_liveness_opponent())
		spec["notes"].append("this cell's axis pool is ALLIED, so the roster carries one inert "
			+ "OPPONENT at the far corner — without a team-1 unit `check_victory` ends the "
			+ "battle on tick 1 and every slot reads NONE(not walked) 29 ticks before the "
			+ "actor's first turn. Measured, not assumed; see _liveness_opponent.")
	spec["scenario"] = {
		"rule": "CELL",
		"name": "%s_%s%s" % [opcode_name.to_lower(), side,
			("_" + String(st["edge"])) if String(st.get("edge", "")) != "" else ""],
		"map": MAP,
		"seed": 42,
		"max_ticks": ticks_for_speed(int(actor["speed"])),
		"units": roster,
	}
	spec["ticks"] = ticks_for_speed(int(actor["speed"]))
	spec["separation"] = separation
	spec["actor_speed"] = int(actor["speed"])   # dec. 12 — recorded for EVERY cell, not only throw

	# === the expectation ===================================================================
	# The positive side predicts FIRED. The mirror predicts CONDITION_FALSE *at this condition
	# index, on this opcode* — and the PAYLOAD where the knob makes it exactly predictable,
	# which is the assertion that ends an investigation rather than restating the verdict.
	var expect: Array = []
	if side == "positive":
		expect.append({"unit": 0, "slot": 0, "p1": "FIRED",
			"why": "%s holds: %s" % [opcode_name, String(row["positive"])]})
	else:
		var e := {"unit": 0, "slot": 0, "p1": "CONDITION_FALSE", "ci": axis, "op": opcode,
			"why": "%s fails: %s" % [opcode_name, String(row["negative"])]}
		if st.has("payload"):
			e["payload"] = int(st["payload"])
		expect.append(e)
		# dec. 19 — the net fires in the lab exactly as it fires in a battle, and the cell says
		# so rather than hiding it. It can only reach an ENEMY, so an ally-pool cell sees
		# NO_CANDIDATE there instead, and that is the labelled reading, not a defect.
		# The net's pool is NEAREST_ENEMY and the roster always carries an enemy now — the
		# axis dummy when the pool is hostile, the liveness opponent when it is allied — so the
		# prediction is FIRED either way. It fires out of reach too: `execute_gambit_action`
		# commits the ATTACK and the unit walks, which is a commitment and not a decline.
		expect.append({"unit": 0, "slot": GPUConstants.MAX_USER_GAMBITS, "p1": "FIRED",
			"why": "ADR-0048's safety net (ATTACK + NEAREST_ENEMY + Always), LABELLED per "
				+ "dec. 19 — it reaches %s" % ("the axis dummy" if dummy_team == 1
					else "the liveness opponent at the far corner")})
	spec["expect"] = expect
	return spec


# =============================================================================================
# THE STRADDLE ARITHMETIC — per opcode, never generic (dec. 8)
# =============================================================================================

## Resolve one side of one opcode's boundary into knob settings.
##
## Returns `{refused, refusal, knob, knob_value, separation, cardinal, payload, edge,
## negative_sides, notes}`. `negative_sides` is how many mirrors the row has — 0 for the
## unstraddleable rows, 1 for most, 2 where the kernel's arm has a near edge as well as a far
## one. Every arm below quotes the comparison it inverts; there is no shared `±1` path, which
## is dec. 8's whole point.
static func _straddle(opcode_name: String, value: int, ability_id: int,
		side: String, which: int) -> Dictionary:
	var out := {"refused": false, "refusal": "", "negative_sides": 1, "notes": [], "edge": ""}
	var positive := side == "positive"

	match opcode_name:
		"COND_ALWAYS":
			out["negative_sides"] = 0
			out["knob"] = ""
			if not positive:
				out["refused"] = true
				out["refusal"] = String(STRADDLE_TABLE["COND_ALWAYS"]["refusal"])
			out["notes"].append("no negative case available — " + String(STRADDLE_TABLE["COND_ALWAYS"]["refusal"]))

		# `measured < value`, so `value - 1` passes and `value` itself FAILS. The boundary is
		# equality, and it is on the negative side — which is the thing a generic ±1 gets
		# wrong half the time without ever saying so.
		"COND_HP_BELOW":
			out["knob"] = "dummy_hp_percent"
			out["knob_value"] = (value - 1) if positive else value
			if int(out["knob_value"]) < 1:
				out["refused"] = true
				out["refusal"] = ("HP percent %d is unreachable: the dummy would have to be at "
					+ "or below 0 HP, and a KO cannot be seeded (see COND_IS_DEAD's row). "
					+ "Authoring HP_BELOW(%d) leaves no passing side.") % [int(out["knob_value"]), value]
			if not positive:
				out["payload"] = value

		# `measured > value`: `value + 1` passes, `value` FAILS.
		"COND_HP_ABOVE":
			out["knob"] = "dummy_hp_percent"
			out["knob_value"] = (value + 1) if positive else value
			if int(out["knob_value"]) > SCALAR_MAX:
				out["refused"] = true
				out["refusal"] = ("HP percent %d is above full: HP_ABOVE(%d) has no passing "
					+ "side with max_hp %d.") % [int(out["knob_value"]), value, SCALAR_MAX]
			if not positive:
				out["payload"] = value

		"COND_MP_ABOVE":
			out["knob"] = "actor_mp_percent"
			out["knob_value"] = (value + 1) if positive else value
			out["notes"].append("⚠️ THE KNOB IS THE ACTOR'S MP, NOT THE TARGET'S. "
				+ "`evaluate_condition` reads `get_mp_percent(battle_id, unit_id)` for both MP "
				+ "opcodes (stage_compute.glsl:200-206) while every HP opcode reads "
				+ "`target_id` — so GambitCondition.Type.TARGET_MP encodes cleanly onto a "
				+ "condition that never looks at the target. Reported, not worked around.")
			if int(out["knob_value"]) > SCALAR_MAX:
				out["refused"] = true
				out["refusal"] = "actor MP percent %d is above full" % int(out["knob_value"])
			if not positive:
				out["payload"] = value

		"COND_MP_BELOW":
			out["knob"] = "actor_mp_percent"
			out["knob_value"] = (value - 1) if positive else value
			out["notes"].append("⚠️ THE KNOB IS THE ACTOR'S MP, NOT THE TARGET'S — see "
				+ "COND_MP_ABOVE's note; the same kernel line serves both.")
			if int(out["knob_value"]) < 0:
				out["refused"] = true
				out["refusal"] = "actor MP percent %d is below empty" % int(out["knob_value"])
			if not positive:
				out["payload"] = value

		# `measured < value` on a MANHATTAN separation — planar, level-blind, wall-blind, and a
		# different question from the path cost that ranks a NEAREST pool.
		"COND_DISTANCE_LESS":
			out["knob"] = "separation"
			out["knob_value"] = (value - 1) if positive else value
			out["separation"] = int(out["knob_value"])
			if int(out["separation"]) < MIN_SEPARATION:
				out["refused"] = true
				out["refusal"] = ("separation %d needs two units in one cell. MAP116 is "
					+ "single-level, so the under-a-bridge geometry ADR-0224 dec. 6 allows is "
					+ "not available here.") % int(out["separation"])
			if not positive:
				out["payload"] = value

		"COND_DISTANCE_GREATER":
			out["knob"] = "separation"
			out["knob_value"] = (value + 1) if positive else value
			out["separation"] = int(out["knob_value"])
			if int(out["separation"]) < MIN_SEPARATION:
				out["refused"] = true
				out["refusal"] = "separation %d needs two units in one cell" % int(out["separation"])
			if not positive:
				out["payload"] = value

		# Categorical, not numeric: there is no operand to step, and a ±1 on a BIT INDEX would
		# silently ask about a different status.
		"COND_HAS_STATUS":
			out["knob"] = "dummy_status_bit"
			out["knob_value"] = value if positive else -1
			out["notes"].append("bit %d (%s). The straddle SETS or CLEARS the bit; stepping the "
				% [value, _status_name_of(value)] + "bit INDEX would ask about a different status.")

		"COND_NOT_STATUS":
			out["knob"] = "dummy_status_bit"
			out["knob_value"] = -1 if positive else value
			out["notes"].append("bit %d (%s), inverted." % [value, _status_name_of(value)])

		"COND_IS_DEAD":
			out["negative_sides"] = 0
			out["knob"] = "dummy_flag_dead"
			out["refused"] = true
			out["refusal"] = String(STRADDLE_TABLE["COND_IS_DEAD"]["refusal"])

		"COND_IS_ALIVE":
			out["negative_sides"] = 0
			out["knob"] = "dummy_flag_dead"
			out["knob_value"] = 0
			if not positive:
				out["refused"] = true
				out["refusal"] = String(STRADDLE_TABLE["COND_IS_ALIVE"]["refusal"])
			out["notes"].append("no negative case available — " + String(STRADDLE_TABLE["COND_IS_ALIVE"]["refusal"]))

		"COND_TEAM_ALLY", "COND_TEAM_ENEMY":
			out["knob"] = "dummy_team"
			var want_same: bool = (opcode_name == "COND_TEAM_ALLY") == positive
			out["knob_value"] = 0 if want_same else 1
			out["payload"] = int(out["knob_value"])
			out["notes"].append("⚠️ NOT ENCODABLE TODAY. `GambitCondition.Type` has no TEAM "
				+ "member at all, so no authored gambit can reach this opcode and this row "
				+ "cannot be built from a Gambit object. The row exists so the straddle is "
				+ "already written when the domain enum grows one — see encoder_coverage().")

		"COND_IN_RANGE":
			var r := _in_range_straddle(ability_id, side, which)
			for k in r.keys():
				out[k] = r[k]

		_:
			out["refused"] = true
			out["refusal"] = "no straddle arm for %s" % opcode_name

	return out


## `COND_IN_RANGE` has FOUR boundaries, not one, and two of them have a near edge. The reach is
## the ACTION'S (ADR-0268 dec. 11): `target_in_action_range` routes an ability through
## `ability_in_reach` and every control verb through `can_attack_target`, which then branches on
## `get_attack_type`. This is the sub-table, and it is why dec. 8 bans a generic perturbation —
## a single ±1 on a separation gets `ATTACK_ARCING` wrong on both sides at once.
static func _in_range_straddle(ability_id: int, side: String, which: int) -> Dictionary:
	var out := {"refused": false, "refusal": "", "negative_sides": 1, "notes": [], "edge": ""}
	var positive := side == "positive"
	var ab := ability_row(ability_id)

	# --- an ability with a real range: `manhattan_distance > range` is the whole far edge ----
	if not ab.is_empty() and int(ab["range"]) > 0:
		if bool(ab.get("_throw", false)):
			# dec. 12 — throw's reach is `speed / 2 + 1`, integer division, unbounded above and
			# NOT in the attributes table. Varying Speed is the only way to reach that boundary
			# at all; unlike dec. 10's nudge it DEFINES the quantity under test.
			var sep := MAX_CARDINAL
			out["knob"] = "actor_speed"
			out["separation"] = sep
			# reach >= sep  <=>  speed / 2 + 1 >= sep  <=>  speed >= 2 * (sep - 1)
			out["knob_value"] = (2 * (sep - 1)) if positive else (2 * sep - 3)
			out["edge"] = "throw_speed"
			if int(out["knob_value"]) < 1:
				out["refused"] = true
				out["refusal"] = "Speed %d is not a speed" % int(out["knob_value"])
			if not positive:
				out["payload"] = sep
			out["notes"].append(("throw reach is `speed / 2 + 1` "
				+ "(combat_common.glslinc:1516-1519), so at separation %d the boundary is "
				+ "Speed %d / %d. The ability buffer's nominal range (%d) is NOT the reach "
				+ "and is never consulted for a throw.") % [sep, 2 * (sep - 1), 2 * sep - 3,
					int(ab["range"])])
			out["notes"].append(("⚠️ AND THE ACTOR IS NOW 15x SLOWER THAN A UNIT. Speed %d means "
				+ "%d ticks to its first turn against %d at the default Speed %d — on an 11x11 "
				+ "board there is no throw boundary a normally-fast unit can straddle, because "
				+ "reach %d needs Speed %d and the map's Manhattan maximum is %d. The cell's own "
				+ "tick budget is derived from this (ticks_for_speed), which is why the throw "
				+ "cells are not blind runs.") % [int(out["knob_value"]),
					ticks_for_speed(int(out["knob_value"])), ticks_for_speed(ACTOR_SPEED),
					ACTOR_SPEED, ACTOR_SPEED / 2 + 1, ACTOR_SPEED, MAX_SEPARATION])
			return out
		var reach: int = int(ab["range"])
		out["knob"] = "separation"
		out["knob_value"] = reach if positive else reach + 1
		out["separation"] = int(out["knob_value"])
		out["edge"] = "far"
		if int(out["separation"]) > MAX_SEPARATION:
			out["refused"] = true
			out["refusal"] = ("separation %d exceeds MAP116's Manhattan maximum of %d from "
				+ "(%d,%d). %s has range %d, so its far edge is off the board — REFUSED, not "
				+ "nudged (dec. 10).") % [int(out["separation"]), MAX_SEPARATION,
					ORIGIN_X, ORIGIN_Z, String(ab["name"]), reach]
		if not positive:
			out["payload"] = reach + 1
		if bool(ab.get("_vertical_tolerance", false)):
			out["notes"].append(("%s carries ABFLAG_VERTICAL_TOLERANCE, so `ability_in_reach` "
				+ "adds a height gate (|dh| <= %d). MAP116 is uniformly height 0, so the gate "
				+ "is satisfied and the separation is the only quantity moving — which is "
				+ "dec. 11's argument for this map, in one cell.")
				% [String(ab["name"]), int(ab["vertical"])])
		return out

	# --- a control verb, or an ability whose `range` is 0: the WEAPON's reach ---------------
	# `get_effective_ability_range` falls back to U_WEAPON_RANGE for range 0, and
	# `target_in_action_range` routes ATTACK / MOVE / WAIT to `can_attack_target` outright.
	var wr := ACTOR_WEAPON_RANGE
	var wf := ACTOR_WEAPON_FLAGS
	var atk := attack_type_of(wr, wf)
	out["knob"] = "separation"
	match atk:
		"ATTACK_STRIKING":
			# `if (h_distance != 1) return false;` — the reach is EXACTLY 1, so BOTH sides are
			# negative. dec. 9 says so; what it does not say is that only one of them is
			# placeable here, and that is the honest difference.
			out["negative_sides"] = 2
			out["edge"] = "far" if which == 0 else "near"
			if positive:
				out["knob_value"] = 1
			elif which == 0:
				out["knob_value"] = 2
				out["payload"] = 2
			else:
				out["knob_value"] = 0
				out["refused"] = true
				out["refusal"] = ("the NEAR edge of ATTACK_STRIKING is separation 0 — two units "
					+ "in one cell. ADR-0224 dec. 6 makes occupancy a CELL and not a column, so "
					+ "that geometry exists under a bridge; MAP116 is single-level and has "
					+ "none. REFUSED and counted (dec. 10): dec. 9's 'nearer and farther are "
					+ "both negative' is true of the PREDICATE and only half buildable on the "
					+ "map dec. 11 chose.")
			out["separation"] = int(out["knob_value"])
			out["notes"].append("`check_striking`: h_distance must be exactly 1, so the reach "
				+ "has a near edge as well as a far one.")
		"ATTACK_DIRECT":
			out["edge"] = "far"
			out["knob_value"] = wr if positive else wr + 1
			out["separation"] = int(out["knob_value"])
			if not positive:
				out["payload"] = wr + 1
			out["notes"].append("`check_direct`: 1 <= h_distance <= weapon_range (%d), plus "
				% wr + "`has_line_of_sight_direct` — which MAP116's flatness satisfies.")
		"ATTACK_ARCING":
			# `if (h_distance < 3) return false;` AND `h_distance <= effective_range`, where
			# effective_range is clamped into [3, weapon_range]. A weapon_range below 3 makes
			# the window EMPTY — no separation can satisfy both — which is a finding about the
			# kernel and not about this cell.
			out["negative_sides"] = 2
			out["edge"] = "far" if which == 0 else "near"
			if wr < 3:
				out["refused"] = true
				out["refusal"] = ("ATTACK_ARCING with weapon_range %d can never hit ANYTHING: "
					+ "`check_arcing` needs h_distance >= 3, then clamps effective_range into "
					+ "[3, weapon_range] — which on a flat map resolves to %d. The window "
					+ "[3, %d] is empty, so there is no positive cell to build and no mirror "
					+ "to flip. A finding, not a gap in the synthesizer.") % [wr, wr, wr]
				out["separation"] = 3
				return out
			if positive:
				out["knob_value"] = wr
			elif which == 0:
				out["knob_value"] = wr + 1
				out["payload"] = wr + 1
			else:
				out["knob_value"] = 2
				out["payload"] = 2
			out["separation"] = int(out["knob_value"])
			out["notes"].append("`check_arcing` has a MINIMUM as well as a maximum "
				+ "(h_distance >= 3), so this row has two mirrors: separation %d is beyond "
				% (wr + 1) + "reach and separation 2 is beneath it. A pair that flips on one "
				+ "and not the other is a different finding from a pair that does not flip.")
		"ATTACK_LUNGING":
			# `if (ax != tx && az != tz) return false;` — the reach is a CROSS, not a disk. So
			# this row has a far edge and an OFF-AXIS edge, and the off-axis one is the reason
			# the cardinal cap matters.
			out["negative_sides"] = 2
			out["edge"] = "far" if which == 0 else "off_axis"
			out["cardinal"] = true
			if positive:
				out["knob_value"] = wr
			elif which == 0:
				out["knob_value"] = wr + 1
				out["payload"] = wr + 1
			else:
				# Off-axis INSIDE the reach: the separation passes and the cross rejects. Needs
				# both dx and dz non-zero, so a separation of at least 2.
				out["cardinal"] = false
				out["knob_value"] = maxi(2, wr)
				out["payload"] = int(out["knob_value"])
				if wr < 2:
					out["refused"] = true
					out["refusal"] = ("the OFF-AXIS edge needs |dx| >= 1 and |dz| >= 1, so a "
						+ "separation of at least 2 — but weapon_range is %d, so every "
						+ "off-axis tile is also out of reach and the mirror would be "
						+ "straddling two boundaries at once. REFUSED rather than "
						+ "attributed to the wrong one.") % wr
			out["separation"] = int(out["knob_value"])
			if int(out["separation"]) > MAX_CARDINAL and bool(out["cardinal"]):
				out["refused"] = true
				out["refusal"] = ("separation %d on the CARDINAL line exceeds MAP116's cardinal "
					+ "maximum of %d from (%d,%d). The Manhattan maximum is %d, but "
					+ "`check_lunging` rejects `ax != tx && az != tz`, so the diagonal that "
					+ "reaches 10 is not available to a lunging weapon.") % [
						int(out["separation"]), MAX_CARDINAL, ORIGIN_X, ORIGIN_Z, MAX_SEPARATION]
			out["notes"].append("`check_lunging` needs a CARDINAL line (`ax != tx && az != tz` "
				+ "rejects), so this row's second mirror is OFF-AXIS rather than far.")
		_:
			out["refused"] = true
			out["refusal"] = "no attack-type arm for %s" % atk
	return out


# =============================================================================================
# PLACEMENT (decs. 10, 11)
# =============================================================================================

## The dummy's tile at Manhattan separation [param separation] from the actor, or `null` when
## no such tile exists on MAP116. NEVER a nudged approximation — dec. 10.
##
## Cardinal placement is exact up to [constant MAX_CARDINAL]; beyond that the separation is
## split across both axes, which is legal for every predicate except `check_lunging`'s cross.
static func place(separation: int, cardinal: bool = false) -> Variant:
	if separation < MIN_SEPARATION:
		return null
	if cardinal:
		if separation > MAX_CARDINAL:
			return null
		return [ORIGIN_X + separation, ORIGIN_Z]
	if separation > MAX_SEPARATION:
		return null
	var dx: int = mini(separation, MAP_W - 1 - ORIGIN_X)
	var dz: int = separation - dx
	if dz > MAP_H - 1 - ORIGIN_Z:
		return null
	return [ORIGIN_X + dx, ORIGIN_Z + dz]


## Where the dummy goes when the axis is NOT placement — far enough apart to be two units and
## near enough that the slot's own ACTION can land, so a passing condition produces FIRED
## rather than a reading about the action's reach instead of the axis.
static func _default_separation(ability_id: int, st: Dictionary) -> int:
	if st.has("separation"):
		return int(st["separation"])
	var ab := ability_row(ability_id)
	if not ab.is_empty() and int(ab["range"]) > 0 and not bool(ab.get("_throw", false)):
		return mini(int(ab["range"]), MAX_SEPARATION)
	var atk := attack_type_of(ACTOR_WEAPON_RANGE, ACTOR_WEAPON_FLAGS)
	if atk == "ATTACK_ARCING":
		return maxi(3, ACTOR_WEAPON_RANGE)
	return mini(maxi(MIN_SEPARATION, ACTOR_WEAPON_RANGE), MAX_CARDINAL)


# =============================================================================================
# THE TWO UNIT DICTS
# =============================================================================================

## The actor's weapon. A plain STRIKING melee weapon of range 1 — the reach `can_attack_target`
## gives an unarmed-ish Squire, and the one every fixture in the corpus uses. Named constants
## rather than literals because `_in_range_straddle` reads them to pick an attack type, and a
## cell whose weapon and whose straddle disagree would be labelled for the wrong boundary.
const ACTOR_WEAPON_RANGE := 1
const ACTOR_WEAPON_FLAGS := 1       # WFLAG_STRIKING


## [param knobs] is a `{knob_name: value}` set rather than one knob, because a LADDER applies
## every rung's knob to ONE board. A single-knob signature forced the ladder to pick the last
## rung's board and silently drop the earlier rungs' settings — which made every rung but the
## last straddle nothing, while the spec still claimed a climb.
static func _actor_cfg(gambit, knobs: Dictionary) -> Dictionary:
	var mp_pct: int = int(knobs.get("actor_mp_percent", ACTOR_MAX_MP))
	var speed: int = int(knobs.get("actor_speed", ACTOR_SPEED))
	return {
		"name": "Actor", "team": 0, "tile": [ORIGIN_X, ORIGIN_Z],
		"job": "4c", "max_hp": SCALAR_MAX, "hp": SCALAR_MAX,
		"max_mp": ACTOR_MAX_MP, "mp": mp_pct,
		"pa": 10, "ma": 10, "wp": 5, "brave": 50, "faith": 50,
		"speed": speed, "move": 4, "jump": 3,
		"weapon_range": ACTOR_WEAPON_RANGE, "weapon_flags": ACTOR_WEAPON_FLAGS, "weapon_type": 0,
		"body_sprite_id": 0,
		"gambits": [gambit],
	}


## 🔴 AN ALLY-POOL CELL NEEDS A THIRD UNIT TO EXIST AT ALL, AND THIS IS THE MEASUREMENT THAT
## SAYS SO — not an argument, a run.
##
## `cell/COND_IS_ALIVE/positive` was built with one actor and one ALLY dummy, both team 0, and
## the trace ended at **tick 1** with every slot of both units reading `NONE(not walked)`.
## `check_victory` returns `RESULT_TEAM_0_WINS` the moment `team1_alive == 0`
## (`stage_victory.glsl:48`), `CombatLoop` stops, and the actor needs 30 ticks at
## [constant ACTOR_SPEED] to reach its first turn. So the cell was not a failed prediction — it
## was a BLIND RUN, and the instrument said so rather than scoring a pass.
##
## The fix is ONE inert opponent, and it does not breach dec. 1. dec. 1 bans a TABLEAU — "one
## dummy of every kind" — because a crowded scene's answer is joint over a population and the
## pick cannot be attributed to the axis. This unit is not in the axis's pool: an ally-pool
## condition has exactly one candidate either way, so the reading stays attributable. What the
## opponent IS in is ADR-0048's safety-net pool, and dec. 19 is explicit that the net is
## LABELLED rather than suppressed — so the cell's expectation names its row.
##
## It is placed at the FAR CORNER (Manhattan 10 from the actor, the board's maximum) and given
## `move: 0` / `speed: 1`, so it is out of reach of every action in the catalogue: the STRIKING
## weapon's 1, Fire's 4, and the throw straddle's 5 at Speed 8.
static func _liveness_opponent() -> Dictionary:
	var cfg := _dummy_cfg(1, [0, 0], {})
	cfg["name"] = "Opponent"
	return cfg


static func _dummy_cfg(team: int, tile: Array, knobs: Dictionary) -> Dictionary:
	var hp_pct: int = int(knobs.get("dummy_hp_percent", SCALAR_MAX))
	var status_lo: int = 0
	var bit: int = int(knobs.get("dummy_status_bit", -1))
	if bit >= 0:
		status_lo = 1 << bit
	# The dummy's own gambit is `Wait on Self`, which is what `Gambit.new()` IS — and
	# `is_empty()` is true of it, so `GambitEncoder.authored_gambits` would strip it. The
	# fixture path does not call that (it reads `cfg["gambits"]` directly through
	# `GambitScenarioBoot.encode_units`), so the WAIT survives here. #1128's finding, the other
	# way round: `is_empty()` cannot tell a pad from an authored WAIT, so which boundary does
	# the filtering decides what a dummy's slot 0 reads.
	return {
		"name": "Dummy", "team": team, "tile": tile,
		"job": "4c", "max_hp": SCALAR_MAX, "hp": hp_pct,
		"max_mp": SCALAR_MAX, "mp": SCALAR_MAX,
		"pa": 1, "ma": 1, "wp": 1, "brave": 50, "faith": 50,
		"speed": DUMMY_SPEED, "move": DUMMY_MOVE, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
		"body_sprite_id": 0,
		"status_flags_lo": status_lo,
		"gambits": [Gambit.create(TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())],
	}


# =============================================================================================
# THE CATALOGUE — every cell the table can produce TODAY
# =============================================================================================

## Abilities the `COND_IN_RANGE` row is probed with, because that one opcode's boundary is the
## ACTION'S and there is no single boundary to probe. Each entry reaches a different arm of
## `target_in_action_range`, and the third is dec. 12's whole reason for existing.
##
##   `-1`    no ability — `can_attack_target`, which branches on the WEAPON. With the actor's
##           STRIKING range-1 weapon that is `check_striking`: reach EXACTLY 1, two edges.
##   `16`    Fire, range 4, no throw flag — `ability_in_reach`, a plain Manhattan far edge.
##   `382`   Shuriken, the first of the twelve `ability_type == "Throwing"` records — reach is
##           `speed / 2 + 1`, so the knob is Speed and not placement (dec. 12).
const IN_RANGE_PROBES := [-1, 16, 382]


## A representative gambit per opcode: HAND-AUTHORED, one per row, for the same reason the
## straddle table is.
##
## A generated condition would not know which POOL can see the thing it asks about, and two rows
## turn on exactly that: `COND_IS_DEAD` and `COND_IS_ALIVE` are only REACHABLE through
## `TargetSelector.friendlies_or_ko()` — every other pool routes through `find_unit_by_criteria`,
## which drops `is_unit_dead` candidates before any condition sees them (#1102). A probe built
## with `enemies()` would encode cleanly, never reach the corpse, and read `CONDITION_FALSE`
## forever while the label said the deadness test was being exercised.
##
## Returns null for an opcode no authored gambit can reach — which is dec. 22's coverage gap, and
## [method catalogue] records it as a refusal rather than skipping it.
static func probe_gambit(opcode_name: String) -> Variant:
	var cond = null
	var pool = TargetSelector.enemies()
	match opcode_name:
		"COND_ALWAYS":
			cond = GambitCondition.always()
		"COND_HP_BELOW":
			cond = GambitCondition.target_hp_below(50.0)
		"COND_HP_ABOVE":
			cond = GambitCondition.target_hp_above(50.0)
		"COND_DISTANCE_LESS":
			cond = GambitCondition.target_within(3.0)
		"COND_DISTANCE_GREATER":
			cond = GambitCondition.target_beyond(3.0)
		"COND_HAS_STATUS":
			cond = GambitCondition.has_status(INERT_STATUS)
		"COND_NOT_STATUS":
			cond = GambitCondition.missing_status(INERT_STATUS)
		"COND_IS_DEAD":
			cond = GambitCondition.is_ko()
			pool = TargetSelector.friendlies_or_ko()
		"COND_IS_ALIVE":
			cond = GambitCondition.is_alive()
			pool = TargetSelector.friendlies_or_ko()
		"COND_MP_ABOVE":
			cond = GambitCondition.new(GambitCondition.Type.SELF_MP,
				GambitCondition.Comparator.GREATER_THAN, 50.0)
		"COND_MP_BELOW":
			cond = GambitCondition.new(GambitCondition.Type.SELF_MP,
				GambitCondition.Comparator.LESS_THAN, 50.0)
		"COND_IN_RANGE":
			cond = GambitCondition.target_in_range()
		_:
			# `COND_TEAM_ALLY` / `COND_TEAM_ENEMY`: `GambitCondition.Type` has no TEAM member at
			# all, so there is no condition object to author. Not a missing probe — a missing
			# domain enum, and encoder_coverage() is where that is measured.
			return null
	return Gambit.create(pool, [cond], Gambit.ActionKind.ATTACK, -1,
		TargetSelector.triggering())


## Every cell the straddle table can produce today: each opcode's positive and every mirror, plus
## one ladder. Flat, and each entry carries its own `refused` flag — dec. 9's refusal count is a
## TO-DO LIST, so the refusals stay in the list rather than being filtered out of it.
static func catalogue() -> Array:
	var out: Array = []
	for opcode_name in STRADDLE_TABLE.keys():
		var g = probe_gambit(opcode_name)
		if g == null:
			var r := _empty_spec("positive")
			r["name"] = "cell/%s/positive" % opcode_name
			r["axis"] = {"opcode_name": opcode_name, "knob": String(STRADDLE_TABLE[opcode_name]["knob"]),
				"side": "positive", "refusal": ""}
			r["refused"] = true
			r["refusal"] = ("no authored gambit can reach %s — `GambitCondition.Type` has no "
				+ "member that encodes to it. A COVERAGE gap (dec. 22), reported here and "
				+ "measured by encoder_coverage(); NOT a raw-opcode injection path.") % opcode_name
			out.append(r)
			continue
		var abilities: Array = IN_RANGE_PROBES if opcode_name == "COND_IN_RANGE" else [-1]
		for ab in abilities:
			# 🔴 THE ACTION IS RE-POINTED BEFORE THE STRADDLE, NEVER AFTER. `COND_IN_RANGE` asks
			# the SLOT'S OWN ACTION for its reach (`target_in_action_range` branches on
			# `action_type`/`action_id`), so a cell whose straddle was computed against an
			# ability while the encoded action stayed ATTACK would have the kernel measuring
			# `can_attack_target` — the weapon's reach 1 — against a board laid out for range 4.
			# The verdict would be real and the label would be wrong, which is dec. 10's
			# productive failure arriving through the back door.
			var probe = g if ab < 0 else _with_ability(g, ab)
			var pair := build_pair(ab, probe, 0)
			out.append(_tag(pair["positive"], ab))
			for m in pair["mirrors"]:
				out.append(_tag(m, ab))
	var ladder := _probe_ladder()
	if not ladder.is_empty():
		out.append(ladder)
	return out


## The one ladder the catalogue ships: two rungs that must each decline for the PREDICTED reason
## before the third fires. Capped at `MAX_USER_GAMBITS` by [method build_ladder] — see the note
## there on why the cap is accepted rather than routed around.
##
## 🔴 THE RUNGS HAVE TO AGREE ABOUT THE BOARD, AND THE FIRST ATTEMPT DID NOT. Three HP rungs
## cannot climb: rung 0 declines `< T0` only when the dummy sits AT `T0`, and rung 2 fires
## `> T2` only when it sits at `T2 + 1`, so two HP boundaries on one board are two different HP
## values and [method build_ladder] refuses the pair — correctly, and the refusal is what caught
## it. The fix is rungs with DISJOINT knobs:
##
##   rung 0  `HP < 50`       declines — the dummy is at exactly 50, and the kernel tests `<`
##   rung 1  `missing frog`  declines — the dummy carries bit 14, so "missing" is false
##   rung 2  `HP > 49`       FIRES    — 50 > 49
##
## Two distinct decline REASONS before the climb ends, which is dec. 2's requirement: slots
## 0..N-1 must each decline for the reason the lab predicted, and "slot N fired" alone is not a
## pass. One board holds all three (`dummy_hp_percent = 50`, `dummy_status_bit = 14`), and the
## two HP rungs straddle the SAME boundary from opposite sides — so if rung 0 fires, the pair did
## not flip and nothing about the climb can be believed.
static func _probe_ladder() -> Dictionary:
	var rungs: Array = [
		Gambit.create(TargetSelector.enemies(), [GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
		Gambit.create(TargetSelector.enemies(), [GambitCondition.missing_status(INERT_STATUS)],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
		Gambit.create(TargetSelector.enemies(), [GambitCondition.target_hp_above(49.0)],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
	]
	return build_ladder(-1, rungs, [0, 0, 0])


## Find one catalogue entry by a case-insensitive substring of its name. Returns `{}` when
## nothing matches, so a caller can say "no such cell" instead of booting entry 0.
static func find(needle: String) -> Dictionary:
	var n := needle.to_lower()
	for c in catalogue():
		if String(c["name"]).to_lower().contains(n):
			return c
	return {}


static func _tag(spec: Dictionary, ability_id: int) -> Dictionary:
	spec["ability_id"] = ability_id
	var ab := ability_row(ability_id)
	spec["ability_name"] = String(ab["name"]) if not ab.is_empty() else "(weapon)"
	if ability_id >= 0:
		spec["name"] = "%s/%s" % [spec["name"], String(ab["name"]).to_lower()]
	return spec


## Re-point a probe gambit's ACTION at an ability, keeping its condition. The condition is what
## the cell is about; the action is what decides the reach `COND_IN_RANGE` asks about, so the two
## have to be settable independently or the `COND_IN_RANGE` row could only ever probe ATTACK.
static func _with_ability(gambit, ability_id: int):
	return Gambit.create(gambit.condition_target, gambit.conditions,
		Gambit.ActionKind.ABILITY, ability_id, gambit.action_target)


# =============================================================================================
# THE COVERAGE LINE (dec. 22) — MEASURED, never quoted
# =============================================================================================

## What the kernel declares that no authored gambit can reach, measured NOW.
##
## dec. 22 rejects a raw-opcode injection path — it would exercise battles that cannot exist in
## the game, and it routes around the encoder dec. 20 keeps in the path — and asks for a
## coverage line instead. This is that line, and it is a MEASUREMENT: the supported cross
## product of [GambitCondition] and [TargetSelector] is pushed through the real [GambitEncoder]
## and the opcodes that never come out are the gap.
##
## Declared-UNSUPPORTED inputs are SKIPPED rather than attempted, for two reasons: the encoder
## `push_error`s on each one (ADR-0023's loud refusal), and its own `UNSUPPORTED_*` constants
## are the public declaration of that set. So a combination that IS in the supported set and
## still encodes to null is a genuine undeclared gap — and it shows up here as a `surprise`.
##
## Returns `{conditions_missing, selectors_missing, surprises, conditions_reached,
## selectors_reached, summary}`.
static func encoder_coverage() -> Dictionary:
	var reader := GambitVerdictReader.new()
	reader.load_layout()
	var declared_conds: Dictionary = {}     # name -> value
	var declared_targets: Dictionary = {}
	for k in reader.consts.keys():
		var n: String = k
		if n.begins_with("COND_"):
			declared_conds[n] = int(reader.consts[n])
		elif n.begins_with("TARGET_") and not n.begins_with("TARGET_IN_"):
			declared_targets[n] = int(reader.consts[n])

	var reached_conds: Dictionary = {}
	var reached_targets: Dictionary = {}
	var surprises: Array = []

	# --- conditions: every supported Type x Comparator -------------------------------------
	for t in GambitCondition.Type.values():
		if t in GambitEncoder.UNSUPPORTED_CONDITION_TYPES:
			continue
		for c in GambitCondition.Comparator.values():
			var cond = GambitCondition.new(t, c, 50.0)
			cond.status_id = INERT_STATUS
			var g = Gambit.create(TargetSelector.enemies(), [cond],
				Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
			var enc = _encode_one(g)
			if enc == null:
				# TARGET_DISTANCE + EQUALS is a DECLARED skip in the encoder's own comment (the
				# kernel has no equality arm and widening `== 3` to `> 3` is ADR-0023's banned
				# silent substitution), so it is expected rather than a surprise.
				if not (t == GambitCondition.Type.TARGET_DISTANCE
						and c == GambitCondition.Comparator.EQUALS):
					surprises.append("condition %s/%s is in no UNSUPPORTED_* set and still "
						% [GambitCondition.Type.keys()[t], GambitCondition.Comparator.keys()[c]]
						+ "encodes to null")
				continue
			for ec in enc["conditions"]:
				reached_conds[opcode_name_of(int(ec["type"]))] = true

	# --- selectors: every supported pool x team x resolution x include_ko -------------------
	for pool in TargetSelector.PoolType.values():
		if pool in GambitEncoder.UNSUPPORTED_POOL_TYPES:
			continue
		for res in TargetSelector.ResolutionStrategy.values():
			if res in GambitEncoder.UNSUPPORTED_RESOLUTIONS:
				continue
			for team in TargetSelector.TeamFilter.values():
				if team in GambitEncoder.UNSUPPORTED_TEAM_FILTERS:
					continue
				for ko in [false, true]:
					# 🔴 THE KO RULE IS DECLARED IN PROSE, NOT IN AN `UNSUPPORTED_*` SET, and
					# skipping it here is what keeps the `surprises` channel meaningful.
					# `_target_selector_to_gpu` admits `include_ko` for exactly ONE shape —
					# TEAM_FILTER + FRIENDLY + NEAREST, the only pool with a GPU spelling
					# (`TARGET_NEAREST_ALLY_OR_KO`, #1102) — and refuses the rest with its own
					# reasons: on SELF the flag "names a pool that cannot exist", on TRIGGERING
					# it "would be inert", and MOST_CRITICAL over the fallen would let the corpse
					# (HP% 0) win every time and starve the living. Those refusals are DESIGN, so
					# attempting them would print eleven `push_error`s per run and make a genuine
					# undeclared gap indistinguishable from eleven expected ones.
					if ko and not (pool == TargetSelector.PoolType.TEAM_FILTER
							and team == TargetSelector.TeamFilter.FRIENDLY
							and res == TargetSelector.ResolutionStrategy.NEAREST_FIRST):
						continue
					var sel = TargetSelector.new()
					sel.pool_type = pool
					sel.team_filter = team
					sel.resolution = res
					sel.include_ko = ko
					sel.role_filter = UnitRole.Role.ANY
					var g2 = Gambit.create(sel, [GambitCondition.always()],
						Gambit.ActionKind.ATTACK, -1, sel)
					var enc2 = _encode_one(g2)
					if enc2 == null:
						continue
					reached_targets[target_name_of(int(enc2["cond_target_type"]))] = true
					reached_targets[target_name_of(int(enc2["action_target_type"]))] = true

	var conds_missing: Array = []
	for n in declared_conds.keys():
		if not reached_conds.has(n):
			conds_missing.append(n)
	conds_missing.sort()
	var targets_missing: Array = []
	for n in declared_targets.keys():
		if not reached_targets.has(n):
			targets_missing.append(n)
	targets_missing.sort()

	return {
		"conditions_missing": conds_missing,
		"selectors_missing": targets_missing,
		"surprises": surprises,
		"conditions_reached": reached_conds.keys().size(),
		"conditions_declared": declared_conds.size(),
		"selectors_reached": reached_targets.keys().size(),
		"selectors_declared": declared_targets.size(),
	}


## The one line dec. 22 asks the lab to SHIP. Measured on every call; the ADR's "two conditions
## and two selectors" is a number with a date on it, and this is how you get today's.
static func coverage_line() -> String:
	var c := encoder_coverage()
	var parts: Array = []
	parts.append("[coverage] the encoder reaches %d/%d conditions and %d/%d selectors" % [
		int(c["conditions_reached"]), int(c["conditions_declared"]),
		int(c["selectors_reached"]), int(c["selectors_declared"])])
	if not (c["conditions_missing"] as Array).is_empty():
		parts.append("  unreachable conditions: %s" % ", ".join(c["conditions_missing"]))
	if not (c["selectors_missing"] as Array).is_empty():
		parts.append("  unreachable selectors:  %s" % ", ".join(c["selectors_missing"]))
	for s in c["surprises"]:
		parts.append("  🔴 SURPRISE: %s" % s)
	parts.append("  no raw-opcode injection path exists and none is wanted (dec. 22) — these "
		+ "are REPORTED, not bypassed.")
	return "\n".join(parts)


# =============================================================================================
# ABILITY + OPCODE LOOKUPS
# =============================================================================================

## 🔴 THE ABILITY AUTHORITY IS `AbilityDatabase`, NOT `ability_attributes.json`, AND THAT IS A
## MEASUREMENT RATHER THAN A PREFERENCE.
##
## #1129's ticket says range data lives in `assets/abilities/ability_attributes.json` (368
## records) and not in `abilities.json` — true of the raw sources, and the wrong conclusion for
## this file, because the GPU never reads either one. `GPUAbilityLoader` fills the ability buffer
## from `AbilityDatabase`, which `tools/generate_ability_database.py` builds by MERGING the
## attributes in. Two things follow, and both of them would have silently mislabelled a cell:
##
##   * THE TWELVE THROW ABILITIES ARE IDS 382-393, past the attributes table's last record
##     (367). `ability_attributes.json` has no row for a single one of them, so a synthesizer
##     reading it would resolve every throw to "no ability" and straddle the WEAPON's reach —
##     building a cell about `check_striking` while labelling it dec. 12's Speed boundary.
##   * THE THROW FLAG IS NOT A COLUMN ANYWHERE. `GPUAbilityLoader:90-91` derives
##     `ABFLAG_THROW_RANGE` from `ability_type == "Throwing"`, then writes a NOMINAL range of 4
##     (`:112-113`) which `get_effective_ability_range` overrides with `speed / 2 + 1`.
##
## So this function mirrors `GPUAbilityLoader`'s own derivation, field for field, and reads the
## same records it reads. `_range` is the nominal the BUFFER carries; `_throw` says whether the
## kernel will ignore it.
static func ability_row(ability_id: int) -> Dictionary:
	if ability_id < 0:
		return {}
	var view = AbilityDatabase.get_ability_view(ability_id)
	if view == null or view.is_empty():
		return {}
	var throwing: bool = view.ability_type == "Throwing"
	# `GPUAbilityLoader:108-110` — range carries a non-zero POLICY DEFAULT for records that omit
	# it, and 0 is a genuine value (it means "fall back to the weapon"), so absent and zero have
	# to be distinguished via `has()`. Reading `view.range` alone would turn every omitting
	# record into a weapon-reach cell.
	var base_range: int = view.range if view.has("range") else 1
	if throwing:
		base_range = 4      # the nominal the loader writes; the shader never consults it
	return {
		"name": view.name,
		"range": base_range,
		"vertical": view.vertical,
		"_throw": throwing,
		# `GPUAbilityLoader:92-93` sets ABFLAG_VERTICAL_TOLERANCE from EITHER column, so reading
		# only `vertical_tolerance` would miss every `vertical_fixed` ability.
		"_vertical_tolerance": view.vertical_tolerance or view.vertical_fixed,
	}


## `COND_*` name for an opcode value, read out of the kernel header rather than mirrored.
static func opcode_name_of(opcode: int) -> String:
	_load_kernel_names()
	return String(_cond_names.get(opcode, "COND_%d" % opcode))


## `TARGET_*` name for a target-type value.
static func target_name_of(t: int) -> String:
	_load_kernel_names()
	return String(_target_names.get(t, "TARGET_%d" % t))


## The attack type `get_attack_type` picks for a weapon, transcribed from
## `combat_combat.glslinc:20-36`. Returned as a NAME rather than an int because the straddle
## table reads it and a number there would be unreadable.
static func attack_type_of(weapon_range: int, flags: int) -> String:
	const WFLAG_STRIKING := 1
	const WFLAG_LUNGING := 2
	const WFLAG_DIRECT := 4
	const WFLAG_ARC := 8
	if weapon_range >= 2:
		if flags & WFLAG_DIRECT:
			return "ATTACK_DIRECT"
		if flags & WFLAG_ARC:
			return "ATTACK_ARCING"
		if flags & WFLAG_LUNGING:
			return "ATTACK_LUNGING"
		return "ATTACK_DIRECT"
	if flags & WFLAG_STRIKING:
		return "ATTACK_STRIKING"
	if flags & WFLAG_LUNGING:
		return "ATTACK_LUNGING"
	if flags & WFLAG_DIRECT:
		return "ATTACK_DIRECT"
	if flags & WFLAG_ARC:
		return "ATTACK_ARCING"
	return "ATTACK_STRIKING"


static var _cond_names: Dictionary = {}
static var _target_names: Dictionary = {}


static func _load_kernel_names() -> void:
	if not _cond_names.is_empty():
		return
	var reader := GambitVerdictReader.new()
	reader.load_layout()
	for k in reader.consts.keys():
		var n: String = k
		if n.begins_with("COND_"):
			_cond_names[int(reader.consts[n])] = n
		elif n.begins_with("TARGET_") and not n.begins_with("TARGET_IN_"):
			_target_names[int(reader.consts[n])] = n


static func _status_name_of(bit: int) -> String:
	for n in StatusRegistry.NAMES_TO_BITS.keys():
		if int(StatusRegistry.NAMES_TO_BITS[n]) == bit:
			return String(n)
	return "bit %d" % bit


# =============================================================================================
# PLUMBING
# =============================================================================================

## One gambit through the REAL encoder, or null. This is the editor->encoder path dec. 20 keeps
## in the loop — `encode_gambits` pads and appends the safety net, and slot 0 is the authored
## one, so this reads the authored config and nothing else.
static func _encode_one(gambit) -> Variant:
	var encoded := GambitEncoder.encode_gambits([gambit])
	if encoded.is_empty() or encoded[0] == null:
		return null
	return encoded[0]


## Whether the gambit's CONDITION pool looks at the other team — which decides the dummy's team,
## because a condition that cannot see the dummy reads NO_CANDIDATE and says nothing about the
## axis. Read off the selector rather than off the encoded opcode so a SELF/TRIGGERING pool
## (which has no team of its own) defaults to an enemy dummy, the shape the safety net wants.
static func _pool_is_enemy(gambit) -> bool:
	var sel = gambit.condition_target if ("condition_target" in gambit) else null
	if sel == null:
		return true
	if sel.pool_type == TargetSelector.PoolType.TEAM_FILTER:
		return sel.team_filter == TargetSelector.TeamFilter.ENEMY
	return true


## The one knob a single-sided straddle moves, as a set — so [method _actor_cfg] and
## [method _dummy_cfg] take the same shape from a cell and from a ladder. A row whose knob is
## `""` (`COND_ALWAYS`) or whose knob is the prose one (`COND_IN_RANGE`'s table row, before
## [method _in_range_straddle] narrows it) contributes nothing.
static func _knob_set(st: Dictionary) -> Dictionary:
	var k: String = String(st.get("knob", ""))
	var v = st.get("knob_value", null)
	if k == "" or v == null or not KNOBS.has(k):
		return {}
	return {k: v}


## The catalogue name for one cell. The EDGE rides on the name only where it distinguishes two
## cells: a mirror can sit on a far edge or a near one (`check_striking`, `check_arcing`) or off
## the lunging cross, and those are different experiments. A POSITIVE has one side by definition,
## so `positive/far` named an edge the cell does not have — except for a throw, where the edge
## names the KNOB (Speed, not placement) and is the one thing a reader needs to see.
## Ticks to give a cell whose actor has this Speed. `TURN_METER_FULL` is PARSED out of the
## kernel header, never mirrored: a constant here would be a second copy of a number ADR-0236
## owns, and it would go stale in the direction that makes every cell read blind.
static func ticks_for_speed(speed: int) -> int:
	var full := _turn_meter_full()
	var per_turn: int = int(ceil(float(full) / float(maxi(1, speed))))
	return per_turn * TURNS_WANTED + TICK_MARGIN


static var _tmf: int = 0


static func _turn_meter_full() -> int:
	if _tmf > 0:
		return _tmf
	var reader := GambitVerdictReader.new()
	reader.load_layout()
	_tmf = int(reader.consts.get("TURN_METER_FULL", 3600))
	return _tmf


static func _cell_name(opcode_name: String, side: String, edge: String) -> String:
	var show_edge := edge != "" and (side != "positive" or edge == "throw_speed")
	return "cell/%s/%s%s" % [opcode_name, side, ("/" + edge) if show_edge else ""]


static func _empty_spec(kind: String) -> Dictionary:
	return {
		"name": "", "kind": kind, "map": MAP,
		"axis": {}, "scenario": {}, "expect": [],
		"refused": false, "refusal": "", "notes": [],
		"negative_sides": 0, "separation": 0, "actor_speed": ACTOR_SPEED,
	}
