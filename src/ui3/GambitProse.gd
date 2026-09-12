class_name GambitProse
extends RefCounted
## The gambit's ENGLISH. Reads a gambit; writes the words a player sees.
##
## ADR-0280 dec. 4: *"A model class that renders itself to prose for one UI file
## is ADR-0115 dec. 4's shape with the arrow reversed."* This file is the
## reversal. Every method here lived on `ExMateriaAlmanac.Gambit` or
## `ExMateriaAlmanac.GambitCondition` until #1160; the gambit is now a rule the
## kernel encodes and the GPU runs, and the sentence is this layer's opinion
## about how to say it.
##
## THE ARROW ONLY POINTS ONE WAY, AND THAT IS THE WHOLE POINT: this file names
## `ExMateriaAlmanac.Gambit`, `.GambitCondition` and `.TargetSelector`; nothing
## in the almanac names `GambitProse`. Adding a reach back — a `_to_string` that
## delegates here, a model method that formats "for the editor" — puts the arrow
## back and is the thing dec. 4 exists to prevent.
##
## STATIC, and a `class_name` rather than a preload const, because it holds no
## state and every caller is a different UI file: `UICombatManager` (the combat
## roster's six-line rows), `GambitSurface` (the detail scene's slot list) and
## `GambitOptions` (the `If` row's readout).
##
## 🔴 WHAT DID **NOT** MOVE, AND WHY, BECAUSE THE TICKET ASKED:
##
## `Gambit._to_string()` stays in the almanac. It is not this surface wearing
## another name — it shares NO helper with anything below. It composes
## `TargetSelector._to_string`, `GambitCondition._to_string` and the action's
## display name, and all three stay where they are. Its register is the DEBUG
## REPR every `RefCounted` model in that package already has
## (`TargetSelector`, `GambitCondition`, `GambitList` — and
## `ExMateriaSchema.TerrainCell` in the kernel itself), so deleting the
## gambit's alone would make it the only model in its own package without one,
## and would silently degrade `GambitBattle._report_prune`'s player-facing
## print to `<RefCounted#...>`. Dec. 4 indicts prose composed FOR A UI FILE; a
## repr the kernel's own types carry cannot be what it means, or it indicts the
## kernel.
##
## `Gambit.action_display_name()` stays too, and it was the closer call. It
## resolves an `ability_id` against `AbilityDatabase` — the almanac's own bank —
## or names a control verb from `KIND_TO_VERB`. That is the model answering
## WHICH ability it is, not a sentence: the one thing here it feeds is
## `_action_line`'s first word, and `_to_string` needs it independently. Moving
## it would have left the almanac reaching back for it.
##
## 🔴 TWO DEFECTS ARE CARRIED ACROSS UNCHANGED, both marked below and both
## pinned by `tests/GambitProseTest.gd`. ADR-0167: a behavioural change does not
## ride inside a move. They are carried EXACTLY, not carried carelessly.

const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole


## The six lines of a gambit row.
##
## Line 0 is the action and its target, line 1 is "when" plus who is being
## checked, and lines 2-5 are up to four conditions prefixed "is " then "and ".
## ALWAYS SIX, whatever the gambit holds — the row is a fixed frame and a short
## gambit pads with empty strings rather than collapsing.
##
##     Cure Them
##     when Nearest Ally Unit
##     is HP < 50%
##     (blank)
##     (blank)
##     (blank)
##
## An `Always` condition renders as a BLANK rather than as the word: the row
## shows the rule, and "is Always" is noise the player has to read past. It also
## does not spend the "is " — the next real condition still opens the list — and
## neither does a null. FOUR is the ceiling and a fifth condition is dropped
## without a word.
##
## ⚠ THE NULL GUARDS HERE AND IN `condition_sentence` ARE NEW, AND THEY ARE THE
## MOVE ITSELF RATHER THAN A CHANGE TO IT. A method on a gambit could not be
## called with no gambit; a static can, so the state exists now that did not
## before. Both guards are unreachable from every current caller — `UICombatManager`
## tests `if gambit and not gambit.is_empty()` and `GambitSurface` tests
## `g == null` before calling — and `condition_sentence`'s reproduces exactly what
## the old loop's `if cond else ""` did one frame further out.
static func sentence_lines(gambit) -> Array[String]:
	var lines: Array[String] = []
	if gambit == null:
		return ["", "", "", "", "", ""] as Array[String]

	lines.append(action_line(gambit))
	lines.append(when_line(gambit))

	var cond_count := 0
	for i in range(4):
		if i < gambit.conditions.size():
			var cond = gambit.conditions[i]
			var cond_text := condition_sentence(cond) if cond else ""
			if cond_text == "Always" or cond_text.is_empty():
				lines.append("")
			else:
				var prefix := "is " if cond_count == 0 else "and "
				lines.append(prefix + cond_text)
				cond_count += 1
		else:
			lines.append("")

	return lines


## Line 0 — "[Action] [Target]".
##
## The verb or ability name comes from the gambit itself
## (`Gambit.action_display_name`, which reads the almanac's ability bank); this
## function is only the target phrase after it. TRIGGERING reads "Them" here and
## "Trigger" on the when-line, and the asymmetry is deliberate: "Attack Them"
## and "when Trigger" are the two halves of one sentence in different cases.
##
## RETREAT IS THE ONE VERB THAT NEEDS A PREPOSITION, and the row lies without it.
## Every other verb here takes its target as the thing acted ON, so bare
## juxtaposition reads correctly; RETREAT takes its target as the thing moved AWAY
## FROM (ADR-0301), and "Retreat Nearest Foe" reads as retreating TOWARD them —
## the exact opposite of what the slot does.
static func action_line(gambit) -> String:
	var parts: Array[String] = []
	parts.append(gambit.action_display_name())
	if gambit.action_kind == Gambit.ActionKind.RETREAT:
		parts.append("from")

	var target = gambit.action_target
	if not target:
		return " ".join(parts)

	match target.pool_type:
		TargetSelector.PoolType.SELF:
			parts.append("Self")
		TargetSelector.PoolType.TRIGGERING:
			parts.append("Them")
		TargetSelector.PoolType.TEAM_FILTER:
			var res_str := resolution_word(gambit, target.resolution)
			if not res_str.is_empty():
				parts.append(res_str)
			var team_str := team_word(target)
			if not team_str.is_empty():
				parts.append(team_str)
			parts.append(noun(target))
		TargetSelector.PoolType.SPECIFIC_UNITS:
			parts.append(noun(target))

	return " ".join(parts)


## Line 1 — "when [Resolution] [Team] [Noun]".
##
## Always shown, because a gambit without a stated subject reads as if it
## applied to everyone. A NULL condition target prints the empty string and not
## a bare "when".
static func when_line(gambit) -> String:
	var target = gambit.condition_target
	if not target:
		return ""

	var parts: Array[String] = ["when"]

	match target.pool_type:
		TargetSelector.PoolType.SELF:
			parts.append("Self")
		TargetSelector.PoolType.TEAM_FILTER:
			var res_str := resolution_word(gambit, target.resolution)
			if not res_str.is_empty():
				parts.append(res_str)
			var team_str := team_word(target)
			if not team_str.is_empty():
				parts.append(team_str)
			parts.append(noun(target))
		_:
			parts.append(noun(target))

	return " ".join(parts)


## Who the pool is: "Self", "Trigger", a unit's name, a role, or "Unit".
##
## "Unit" for a TEAM_FILTER whose role is ANY, so the phrase is never left
## dangling after its team word — "Nearest Ally" alone reads as a fragment.
static func noun(target) -> String:
	if not target:
		return ""
	match target.pool_type:
		TargetSelector.PoolType.SELF:
			return "Self"
		TargetSelector.PoolType.TRIGGERING:
			return "Trigger"
		TargetSelector.PoolType.SPECIFIC_UNITS:
			return target.unit_names[0] if target.unit_names.size() > 0 else "Specific"
		TargetSelector.PoolType.TEAM_FILTER:
			if target.role_filter != UnitRole.Role.ANY:
				return UnitRole.get_role_name(target.role_filter)
			return "Unit"
	return ""


## "Ally", "Enemy", or nothing.
##
## Nothing for any pool that is not a TEAM_FILTER, and nothing for
## `TeamFilter.ANY` — a pool that spans both sides has no word that would narrow
## it, and "Any Unit" would claim a filter the selector does not carry.
static func team_word(target) -> String:
	if not target or target.pool_type != TargetSelector.PoolType.TEAM_FILTER:
		return ""
	match target.team_filter:
		TargetSelector.TeamFilter.FRIENDLY:
			return "Ally"
		TargetSelector.TeamFilter.ENEMY:
			return "Enemy"
	return ""


## How one unit is picked out of the pool: "Nearest", "Most Critical", "First",
## a stat phrase — or NOTHING, which is a word in its own right.
##
## 🔴 **`NEAREST_FIRST` PRINTS THE EMPTY STRING, AND "Nearest" MOVED TO `NEAREST_ONLY`
## (ADR-0285).** This function used to answer "Nearest" for the member then called `NEAREST`,
## and that string was the screen's defect in prose form: the kernel retries that pool at ranks
## 1, 2, 3…, so the sentence *"Cure Nearest Ally Unit when Nearest Ally Unit HP < 50%"* claimed
## a depth the rule did not have. `NEAREST_FIRST` narrows the pool by nothing — the proximity
## order is a search order, not a filter — so the honest phrase is the team word alone,
## "Ally Unit", and both call sites already drop an empty resolution rather than leaving a gap.
## "Nearest" now appears exactly when one unit really is the whole pool.
##
## 🔴 `gambit` IS A PARAMETER BECAUSE OF A DEFECT, AND THE DEFECT IS CARRIED
## ACROSS UNCHANGED. The stat phrases read the **action** target's `stat_name`
## no matter which target's resolution was passed in, so a condition target
## resolved by HIGHEST_STAT prints the stat the ACTION was aimed by. The old
## private helper reached `action_target` off `self`; making the gambit explicit
## is the only way to keep that behaviour byte-identical here instead of
## quietly correcting it — ADR-0167 says a behavioural change does not ride
## inside a move. Pinned by `GambitProseTest._when_line`'s last case, which is
## the failing assertion the fixing ticket inherits. When it IS fixed, this
## parameter becomes the target itself and the signature says so.
static func resolution_word(gambit, res) -> String:
	var action_target = gambit.action_target if gambit else null
	match res:
		TargetSelector.ResolutionStrategy.NEAREST_FIRST:
			return ""
		TargetSelector.ResolutionStrategy.NEAREST_ONLY:
			return "Nearest"
		TargetSelector.ResolutionStrategy.MOST_CRITICAL:
			return "Most Critical"
		TargetSelector.ResolutionStrategy.HIGHEST_STAT:
			return "Highest %s" % action_target.stat_name if action_target else "Highest"
		TargetSelector.ResolutionStrategy.LOWEST_STAT:
			return "Lowest %s" % action_target.stat_name if action_target else "Lowest"
		TargetSelector.ResolutionStrategy.FIRST_IN_ROSTER:
			return "First"
	return ""


## One condition as a readable clause: "HP < 50%", "Allies < 2", "KO'd",
## "Always".
##
## Composed from `GambitCondition.get_ui_display_data()`, which STAYS in the
## almanac: that returns the three structured parts (`type` / `comparator` /
## `threshold`) and is read by the editor's dropdowns as fields, not as prose.
## This function is the only place those three are joined into a sentence.
##
## `ALWAYS` arrives as the structured word "Else" and leaves as "Always". The
## two disagree on purpose — "Else" is what the editor's dropdown offers, since
## the row is the fallback at the bottom of a list; "Always" is what the rule
## reads as on its own.
##
## 🔴 A CONDITION WITH NO COMPARATOR LOSES ITS THRESHOLD, AND THAT IS A DEFECT
## CARRIED ACROSS UNCHANGED. `HAS_STATUS` and `MISSING_STATUS` put the status
## name in the threshold slot and clear the comparator, so they return the type
## alone: "Has Status Poison" and "Has Status Haste" are the SAME string, and
## the row cannot say which status the rule is about. `IN_RANGE_OF` escapes it
## only because it fills the comparator with the word "of". The name IS present
## in the structured data — `GambitProseTest` asserts that as a positive
## control — so this is a rendering defect, not a missing field, and fixing it
## changes what a player reads.
static func condition_sentence(cond) -> String:
	if cond == null:
		return ""
	var ui_data: Dictionary = cond.get_ui_display_data()
	var type_str: String = ui_data.get("type", "")
	var comp_str: String = ui_data.get("comparator", "")
	var thresh_str: String = ui_data.get("threshold", "")

	if type_str == "Else" or type_str.is_empty():
		return "Always"
	if comp_str.is_empty():
		return type_str
	return "%s %s %s" % [type_str, comp_str, thresh_str]
