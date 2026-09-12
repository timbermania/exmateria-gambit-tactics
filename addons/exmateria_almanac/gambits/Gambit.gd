extends RefCounted
## A single gambit rule with explicit target selection.
##
## New structure separates "who triggers" from "who to act on":
## - condition_target: Which units to check conditions against
## - conditions: What must be true (AND logic - all must pass)
## - action: The ability or action to perform
## - action_target: Who to perform the action on
##
## Also supports legacy single-condition format for backward compatibility.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/gambits/Gambit.gd")
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const GambitCondition = preload("res://addons/exmateria_almanac/gambits/GambitCondition.gd")
const TargetSelector = preload("res://addons/exmateria_almanac/gambits/TargetSelector.gd")
# ADR-0202 dec. 2 / ADR-0280 dec. 3 — `UnitRole` is the SHARED KERNEL's, not this
# addon's: ADR-0118 dec. 1's eleventh schema row, reached through the kernel's
# facade rather than by path because a `res://` literal leaving this addon root
# is arm 6 and this addon's arm-6 burn-down is EMPTY. Every reach INTO the
# kernel is free. `plugin.cfg`'s `deps=` declares it so the stranger rig stages
# it (#1159).
const UnitRole = ExMateriaSchema.UnitRole

## Whether this gambit is active
var enabled: bool = true

## WHO triggers this gambit - which units to check conditions against
var condition_target: TargetSelector = null

## WHAT must be true - all conditions must pass (AND logic)
var conditions: Array[GambitCondition] = []

## The predicate the `Always` subject SET ASIDE — kept so flipping back off `Always` restores it
## instead of making the player re-pick it.
##
## 🔴 IT IS NOT A CONDITION AND NEVER REACHES THE KERNEL. `check_gambit_conditions` ANDs every
## entry in `conditions`, so parking the predicate THERE (as `[ALWAYS, HP<50%]`) would leave the
## row reading `Always` while firing only below half HP — the readout-that-lies shape the whole
## gambit surface is built against. `GambitEncoder` never reads this field; it is screen state
## that happens to be worth saving.
##
## Serialized, because the flip the player wants undone survives a save. A park that evaporated
## on reload would restore a predicate on Tuesday and a blank on Wednesday, from one visible
## row state.
##
## AT MOST ONE, matching the one condition the surface edits (ADR-0268 dec. 3 — index 0). A
## parked ARRAY would be a second, invisible copy of the `+N` problem.
var parked_condition: GambitCondition = null

## The action to perform when triggered, as a tagged sum type (ADR-0023): a
## control verb (ATTACK/WAIT/MOVE) or an ABILITY carrying a stable ability_id.
## Abilities are referenced by id, never by display name — names are fragile
## across renames / duplicates / localization.
##
## MOVE is unit-anchored (its action_target is a unit TargetSelector);
## absolute-tile moves are a separate program-built command path that bypasses
## this domain.
##
## RETREAT is BACK, and ADR-0301 is why it is a verb again after ADR-0062 deleted
## it. ADR-0062 removed it because "retreat" named no single behaviour -- a
## corner, a near ally, away from the nearest enemy were all candidates and none
## was the meaning. It has one now, decided in #1103 and stated by the person
## whose game it is: ONE TILE directly away from the unit it is aimed at, then a
## fresh gambit walk. That is not composable from MOVE plus a target, because
## every target MOVE can take is somewhere to move TOWARD; the sign is the verb.
##
## APPROACH stays deleted, and for exactly ADR-0062's original reason: it IS
## MOVE aimed at the thing approached. Only the away-facing half of that pair
## needed a word of its own.
enum ActionKind { ATTACK, WAIT, MOVE, ABILITY, RETREAT }

var action_kind: ActionKind = ActionKind.WAIT
## Ability id when action_kind == ABILITY; -1 otherwise.
var ability_id: int = -1

## Control-verb <-> ActionKind maps (abilities are not verbs — they carry an id).
const VERB_TO_KIND := {
	"Attack": ActionKind.ATTACK,
	"Wait": ActionKind.WAIT,
	"Move": ActionKind.MOVE,
	"Retreat": ActionKind.RETREAT,
}
const KIND_TO_VERB := {
	ActionKind.ATTACK: "Attack",
	ActionKind.WAIT: "Wait",
	ActionKind.MOVE: "Move",
	ActionKind.RETREAT: "Retreat",
}

## Legacy save migration. ADR-0062 retired two action names and sent both here;
## ADR-0301 takes "Retreat" back out, because the name now resolves to a real
## verb through `VERB_TO_KIND` above -- which `action_from_name` consults FIRST,
## so a pre-0062 save that stored the word finally round-trips to the thing it
## said instead of degrading to WAIT.
##
## "Approach" stays. It was never a verb of its own even before 0062: it is MOVE
## aimed at the unit approached, and the alias keeps the action_target that says
## which one.
const LEGACY_VERB_ALIAS := {
	"Approach": ActionKind.MOVE,
}

## WHO to perform the action on
var action_target: TargetSelector = null

# ============================================================================
# CONSTRUCTORS
# ============================================================================

func _init() -> void:
	"""Default constructor — THE EMPTY GAMBIT. Use `create()` for full configuration.

	`Gambit.new().is_empty()` is TRUE, and that invariant is the point: `is_empty` describes
	"Always: Wait on Self", so the default-constructed gambit has to BE that or the predicate is
	describing an object the constructor cannot make. It used to be false — `_init` set
	`action_target` to `triggering()` while `is_empty` requires SELF — and `GambitList` carried a
	second, disagreeing definition of the same object to paper over it.

	`self_()` and not `triggering()`, and the two are not merely different spellings here: with
	`condition_target` also SELF, "act on whoever the condition picked out" resolves to the actor
	anyway, so the pair name one behaviour and only one of them SAYS so. `triggering()` is the
	right action target for a gambit whose condition has a real subject; that is a property of a
	CONFIGURED gambit, and the surface writes it when the player gives the slot a subject.

	`conditions` IS EMPTY, not `[always()]` (ADR-0283 dec. 2). The two are the same rule TO THE
	KERNEL -- `check_gambit_conditions` loops `for c in 0..cond_count` and returns true at zero,
	and an `ALWAYS` condition returns true at one -- so a fresh gambit gets the spelling that
	claims the least: a row nobody has authored has not DECLARED that it will never test
	anything, it simply has no test yet.

	🔴 THE SCREEN TELLS THEM APART, and that is why the constructor's choice matters. The gambit
	surface reads an explicit `ALWAYS` as the `Always` SUBJECT -- a row that has declared it has
	no test, and greys its `If` column out -- while a zero-length array reads `My`/`Their` with
	an `If` column reading `--`. Seeding `[always()]` here would make every untouched slot claim
	a declaration the player never made, and make their first `Subject` press look like it did
	nothing. `ALWAYS` stays on the enum for #895's mutation operators and for saves written
	before ADR-0283, which meant the declaration and now read back as it; [method is_empty] and
	`GambitOptions.condition_label` read either spelling, and
	`GambitOptions.is_unconditional` is the one that splits them.
	"""
	var default_cond: Array[GambitCondition] = []
	conditions = default_cond
	condition_target = TargetSelector.self_()
	action_target = TargetSelector.self_()


## Create a new-style gambit with explicit targets.
static func create(
	p_condition_target: TargetSelector,
	p_conditions: Array,  # Array[GambitCondition] - untyped to accept literals
	p_action_kind: ActionKind,
	p_ability_id: int,
	p_action_target: TargetSelector
) -> _Self:
	var g = _Self.new()
	g.condition_target = p_condition_target
	# Cast to typed array
	var typed_conditions: Array[GambitCondition] = []
	for cond in p_conditions:
		typed_conditions.append(cond)
	g.conditions = typed_conditions
	g.action_kind = p_action_kind
	g.ability_id = p_ability_id
	g.action_target = p_action_target
	return g


# ============================================================================
# DISPLAY
# ============================================================================

# 🔴 THE ENGLISH LEFT HERE AT #1160 AND IT IS NOT COMING BACK. ADR-0280 dec. 4:
# *"A model class that renders itself to prose for one UI file is ADR-0115
# dec. 4's shape with the arrow reversed."* `get_sentence_lines`,
# `_build_action_line`, `_build_when_line`, `_get_noun_string`,
# `_get_team_string` and `_resolution_to_friendly_string` are now
# `GambitProse` in `src/ui3/`, along with `GambitCondition.get_sentence_text`.
# The words a player reads are the host's opinion; what this object IS, is the
# almanac's.
#
# `get_ui_display_data()` left too, and it was DELETED rather than moved: it
# had zero callers repo-wide — `.gd`, `.tscn` and `.py` all searched, and its
# only occurrence outside its own body was its own declaration. Same shape as
# ADR-0251 dec. 5's `OP_RUN_SCENARIO`, which was severed by deletion for the
# same reason. `TargetSelector.get_ui_display_data` and
# `GambitCondition.get_ui_display_data` are live and STAY — they return
# structured fields the editor's dropdowns read as fields, not prose.
#
# TWO THINGS STAYED, and neither is a residue:

## Display name of the action: the ability's name (resolved from id) or the verb.
##
## STAYS IN THE ALMANAC, and it is the closer of #1160's two calls. This resolves
## an `ability_id` against `AbilityDatabase` — this addon's own bank — or names a
## control verb out of `KIND_TO_VERB`. That is the model answering WHICH ability
## it is, not a sentence about it: `GambitProse.action_line` uses it for one
## word, and `_to_string` below needs it with no UI in reach at all. Moving it
## would have left this file reaching back into `src/ui3/` for its own repr,
## which is the arrow dec. 4 removes.
##
## PUBLIC since #1160 — it was `_action_display_name`, private by convention with
## two in-file callers. One of those callers is now in another package, so the
## underscore would be a lie.
func action_display_name() -> String:
	if action_kind == ActionKind.ABILITY:
		var n := AbilityDatabase.get_ability_view(ability_id).name
		return n if not n.is_empty() else "Ability?"
	return KIND_TO_VERB.get(action_kind, "Wait")


## Does this gambit SAY NOTHING -- "wait on myself, whatever happens"?
##
## `GambitEncoder.authored_gambits` filters on this BEFORE encoding, so the predicate decides
## whether a slot reaches the GPU at all, and it is wrong in two directions rather than one:
##
## - too PERMISSIVE and a rule the player authored is silently dropped from the buffer -- the row
##   reads back correctly and the unit is not under it;
## - too STRICT and a blank slot encodes as a real rule, occupying a priority the slots below it
##   then never get (rule A1 -- slot order IS priority).
##
## Both arms are direction-tested in `GambitSurfaceTest`; a predicate that answered `true` for
## everything passes any test that only checks the first.
##
## FOUR THINGS HAVE TO BE TRUE AT ONCE, and each one is the ABSENCE of an authored decision:
## the verb is WAIT (the one verb that spends no turn), the aim is the actor, the subject is the
## actor, and nothing is TESTED.
##
## "Nothing is tested" is not "`conditions` is empty" (ADR-0283 dec. 2). Zero conditions and a
## list of nothing-but-`ALWAYS` are the same rule: `check_gambit_conditions` returns true at
## zero, and `ALWAYS` returns true at one. The constructor writes the first spelling and the
## screen writes the first spelling; #895's mutation operators and pre-ADR-0283 saves carry the
## second, and a predicate that rejected them would make every old save's blank slots encode.
##
## [b]A CONDITION IS WHAT SAVES A NON-WAIT ROW, NOT WHAT MAKES A ROW REAL.[/b] `Attack / Nearest
## Foe` with no condition at all is the player's own sentence -- ADR-0283's third worked example,
## and the one a "blank means empty" predicate deletes. It survives here on `action_kind`, which
## is checked first and alone.
func is_empty() -> bool:
	if action_kind != ActionKind.WAIT:
		return false
	if not action_target or action_target.pool_type != TargetSelector.PoolType.SELF:
		return false
	if not condition_target or condition_target.pool_type != TargetSelector.PoolType.SELF:
		return false
	for cond in conditions:
		if cond != null and cond.type != GambitCondition.Type.ALWAYS:
			return false
	return true


func _to_string() -> String:
	"""Human-readable representation for debugging — NOT the gambit's prose.

	STAYS IN THE ALMANAC, and #1160's ticket asked for this to be decided out
	loud rather than by coin-flip. It shares no helper with the surface that
	left: it composes `TargetSelector._to_string`, `GambitCondition._to_string`
	and `action_display_name`, all three of which are here. Its register is the
	DEBUG REPR every `RefCounted` model in this package already carries
	(`TargetSelector`, `GambitCondition`, `GambitList`) and that the kernel
	carries too (`ExMateriaSchema.TerrainCell`) — so it cannot be the thing
	dec. 4 indicts, or dec. 4 indicts the kernel.

	It is NOT a delegate. A delegate would be a one-line reach into `src/ui3/`
	and would put the arrow back; this composes neighbours in its own package
	and names no UI type.

	And the third option — deleting it — was priced and refused. `str(gambit)`
	is an engine hook, so a caller that never spells `_to_string` still reaches
	it, and `GambitBattle._report_prune:1534` prints the result to a PLAYER.
	Deleting this degrades that message to `<RefCounted#-9223...>` with no
	compile error and no test to catch it. The three reachers are that print,
	`GambitLabScene`'s slot dump and `GambitList._to_string`; all three are
	pinned by `tests/GambitProseTest._debug_repr`.
	"""
	var enabled_str = "[✓]" if enabled else "[ ]"

	# Build condition string
	var cond_strs: Array[String] = []
	for cond in conditions:
		cond_strs.append(cond._to_string() if cond else "null")
	var cond_str = " AND ".join(cond_strs) if not cond_strs.is_empty() else "Always"

	# Build target string
	var target_str = ""
	if condition_target:
		target_str = " [%s]" % condition_target._to_string()

	return "%s%s %s → %s" % [enabled_str, target_str, cond_str, action_display_name()]


# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Convert to dictionary for JSON serialization."""
	var conditions_data: Array = []
	for cond in conditions:
		conditions_data.append(cond.to_dict())
	# Serialize targets as their dict, or null when absent (avoids Dictionary/null ternary).
	var condition_target_data = null
	if condition_target:
		condition_target_data = condition_target.to_dict()
	var action_target_data = null
	if action_target:
		action_target_data = action_target.to_dict()
	var out := {
		"enabled": enabled,
		"condition_target": condition_target_data,
		"conditions": conditions_data,
		"action_kind": action_kind,
		"ability_id": ability_id,
		"action_target": action_target_data,
	}
	# OMITTED when there is nothing parked, rather than written as `null`. Every save in the wild
	# predates this field, so absent must already mean "nothing parked" — and writing the key
	# anyway would make a round-tripped old save differ from the original on a field neither the
	# kernel nor the row can see.
	if parked_condition != null:
		out["parked_condition"] = parked_condition.to_dict()
	return out


static func from_dict(data: Dictionary) -> _Self:
	"""Create from dictionary (JSON deserialization)."""
	var g = _Self.new()
	g.enabled = data.get("enabled", true)
	var ct_data = data.get("condition_target")
	if ct_data:
		g.condition_target = TargetSelector.from_dict(ct_data)
	var conds_data = data.get("conditions", [])
	g.conditions.clear()
	for cond_dict in conds_data:
		g.conditions.append(GambitCondition.from_dict(cond_dict))
	var parked_data = data.get("parked_condition")
	if parked_data:
		g.parked_condition = GambitCondition.from_dict(parked_data)
	if data.has("action_kind"):
		# Guard against a stored int from the pre-ADR-0062 enum numbering (which
		# had MOVE=2, RETREAT=3, APPROACH=4, ABILITY=5). An out-of-range value
		# degrades to WAIT rather than mis-mapping or crashing; in-range values
		# below ABILITY are stable across the renumber.
		var ak := int(data["action_kind"])
		g.action_kind = ak if ak in ActionKind.values() else ActionKind.WAIT
		g.ability_id = int(data.get("ability_id", -1))
	elif data.has("action"):
		# Legacy save: action was a control-verb OR an ability display name.
		# Resolve once to the stable {kind, ability_id} form (ADR-0023).
		var resolved := _Self.action_from_name(StringName(data["action"]))
		g.action_kind = resolved["kind"]
		g.ability_id = resolved["ability_id"]
	else:
		g.action_kind = ActionKind.WAIT
		g.ability_id = -1
	var at_data = data.get("action_target")
	if at_data:
		g.action_target = TargetSelector.from_dict(at_data)
	return g


## Resolve a control-verb or ability display-name to {kind, ability_id}. For
## construction / legacy-save migration only — the stored form is kind + id,
## never the name (the fragility ADR-0023 removes).
##
## ⚠ THIS SAT INSIDE THE `DISPLAY` BLOCK UNTIL #1160 AND IT NEVER BELONGED
## THERE. #1160's ticket predicted `AbilityDatabase` would lose TWO call sites
## because both were "inside the moving surface" — but this one is
## DESERIALIZATION reading a display block's heading. `from_dict` above is its
## only caller, and no legacy save can be read without it. It is moved down
## here, beside the function it serves, and the call site stays.
static func action_from_name(name: StringName) -> Dictionary:
	var s := String(name)
	if VERB_TO_KIND.has(s):
		return {"kind": VERB_TO_KIND[s], "ability_id": -1}
	if LEGACY_VERB_ALIAS.has(s):
		return {"kind": LEGACY_VERB_ALIAS[s], "ability_id": -1}
	var view := AbilityDatabase.get_view_by_name(s)
	var aid := view.ability_id if not view.is_empty() else -1
	return {"kind": ActionKind.ABILITY, "ability_id": aid}
