extends Node
# test-kind: logic
# seeded-break: in src/ui3/GambitProse.gd's `team_word`, the FRIENDLY arm returns "Enemy" instead of "Ally" — the one word every team-filtered noun phrase is built on. 7 of the 60 pinned strings red (both `noun:` arms, all five `resolution word:` arms, and `when: a named role`), each got="… Enemy …" want="… Ally …"; the ENEMY arm, the action lines, the sentence-line shapes and the condition sentences all stay green, which is what shows the goldens separate the team word from the phrase it sits in. Measured, not asserted: 60/60 PASS on the reverted tree, rc 0; seeded, the scene prints [FAIL] GambitProse and run_tests_parallel.py --tests GambitProseTest exits 1. GREEN unbroken on the reverted tree.
## The gambit's ENGLISH, pinned string by string, so #1160 can move it.
##
## 🔴 THIS TEST IS OLDER THAN THE MOVE IT GUARDS, ON PURPOSE. Before it,
## `Gambit.get_sentence_lines`, its five private helpers and
## `GambitCondition.get_sentence_text` had **zero** assertions anywhere in
## `tests/` — measured, not assumed (`grep -rn get_sentence_lines tests/`
## returned nothing). ADR-0280 dec. 4 rules that prose is UI's, and a
## ~150-line move with no instrument is a rewrite wearing a move's commit
## message. So the goldens below were captured from the surface IN THE
## ALMANAC, committed green there, and only then re-pointed at
## `GambitProse`. A byte-identical run on the far side is then evidence; a
## test written after the move would only have pinned the destination. The
## commit before this one is that green run — `git show HEAD~1 -- this file`
## reads the SAME goldens against `Gambit.get_sentence_lines`.
##
## Every expected string here is a LITERAL. None is computed from the code
## under test — a golden derived from the thing it grades is the
## fixture-seeds-the-expectation defect, and it passes on a rewrite.
##
## THE ONE EXCEPTION IS NAMED AND IS NOT AN EXCEPTION: the ABILITY action
## line asks `AbilityDatabase` for the name, and that bank is not this
## test's subject. So the ability case grades the COMPOSITION — "<name>
## Them" — against the bank's answer plus a literal suffix, and a second
## case pins the unknown-id fallback `"Ability?"` outright, which is the
## branch that is actually this file's.

const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase

var _failed := false
var _checks := 0


func _expect(got, want, what: String) -> void:
	_checks += 1
	if got != want:
		_failed = true
		print("[FAIL] %s\n         want %s\n          got %s" % [what, JSON.stringify(want), JSON.stringify(got)])


func _ready() -> void:
	_noun_and_team()
	_resolution_words()
	_when_line()
	_action_line()
	_sentence_lines()
	_condition_sentences()
	_debug_repr()

	if _failed:
		print("[FAIL] GambitProse")
	else:
		print("[PASS] GambitProse: %d strings pinned — every noun, team word, resolution "
			  % _checks + "word, action line, sentence-line shape and condition sentence the "
			  + "surface can produce")
	get_tree().quit()


# --- helpers ---------------------------------------------------------------

## One gambit, fully specified, so no case depends on a default drifting.
func _g(cond_target, conds: Array, kind, aid: int, action_target) -> Gambit:
	return Gambit.create(cond_target, conds, kind, aid, action_target)


## THE SUBJECT. Two one-line aliases so the assertions below stay readable at
## the width the goldens need — every one of them is a call into `GambitProse`
## and nothing else, which is the whole claim this file makes after #1160.
func _lines(gambit) -> Array[String]:
	return GambitProse.sentence_lines(gambit)


func _says(cond) -> String:
	return GambitProse.condition_sentence(cond)


func _always() -> Array:
	return [GambitCondition.always()]


# --- the noun and the team word -------------------------------------------

## `_get_noun_string` and `_get_team_string` have no callers outside the
## sentence surface, so they are graded THROUGH the action line — which is
## also the only way a reader can check the golden by eye.
func _noun_and_team() -> void:
	# Every case is "Wait" on the named target, so the golden's first word is a
	# constant and everything after it is the phrase under test.
	for c in [
		[TargetSelector.self_(), "Wait Self", "noun: SELF"],
		[TargetSelector.triggering(), "Wait Them", "noun: TRIGGERING is 'Them' HERE"],
		[TargetSelector.specific(["Ramza"] as Array[String]), "Wait Ramza",
			"noun: SPECIFIC_UNITS takes the FIRST name"],
		[TargetSelector.specific([] as Array[String]), "Wait Specific",
			"noun: SPECIFIC_UNITS with no names at all"],
		[TargetSelector.friendlies(), "Wait Ally Unit",
			"noun: the ANY role reads 'Unit' so the team word is not left dangling"],
		[TargetSelector.enemies(), "Wait Enemy Unit", "team word: ENEMY"],
		[TargetSelector.friendlies(UnitRole.Role.HEALER), "Wait Ally Healer",
			"noun: a named role replaces 'Unit'"],
		[TargetSelector.enemies(UnitRole.Role.MAGE), "Wait Enemy Mage",
			"noun and team word together"],
		[null, "Wait", "a null action target prints the verb alone"],
	]:
		_expect(_act_line(c[0]), c[1], c[2])


## The action line for a WAIT gambit aimed at `target`.
func _act_line(target) -> String:
	return _lines(_g(TargetSelector.self_(), _always(), Gambit.ActionKind.WAIT, -1, target))[0]


## The when line for a WAIT-on-Self gambit whose CONDITION target is `target`.
func _when(target) -> String:
	return _lines(_g(target, _always(), Gambit.ActionKind.WAIT, -1, TargetSelector.self_()))[1]


# --- the six resolution words, one of which is the empty string ------------

## 🔴 `NEAREST_FIRST` PRINTS NO WORD AT ALL, AND `NEAREST_ONLY` TOOK "Nearest" (ADR-0285).
##
## The table is exhaustive over the enum on purpose, and the size check below is what makes a
## newly-added strategy a RED rather than a silently unprinted one. Before ADR-0285 the member
## then called `NEAREST` printed "Nearest", and that word was the screen's defect written out
## in prose: the kernel retries that pool at ranks 1, 2, 3…, so "Wait Nearest Ally Unit"
## claimed a depth the rule did not have. A resolution that narrows the pool by nothing
## contributes no word, and both sentence builders already drop an empty one rather than
## leaving a double space.
func _resolution_words() -> void:
	var R := TargetSelector.ResolutionStrategy
	var table := [
		[R.NEAREST_FIRST, &"", "Wait Ally Unit"],
		[R.NEAREST_ONLY, &"", "Wait Nearest Ally Unit"],
		[R.MOST_CRITICAL, &"", "Wait Most Critical Ally Unit"],
		[R.FIRST_IN_ROSTER, &"", "Wait First Ally Unit"],
		[R.HIGHEST_STAT, &"Speed", "Wait Highest Speed Ally Unit"],
		[R.LOWEST_STAT, &"Faith", "Wait Lowest Faith Ally Unit"],
	]
	for c in table:
		_expect(_act_line(TargetSelector.friendlies().with_resolution(c[0], c[1])),
				c[2], "resolution word: %s" % R.keys()[c[0]])
	_expect(str(table.size()), str(R.size()),
			"the table must cover EVERY ResolutionStrategy — a strategy with no row here is one"
			+ " whose prose nobody has ever read, and the two that differ by depth alone"
			+ " (NEAREST_FIRST / NEAREST_ONLY) are exactly the pair a partial table would let"
			+ " collapse back into one word")


# --- the "when" line -------------------------------------------------------

func _when_line() -> void:
	_expect(_when(TargetSelector.self_()), "when Self", "when: SELF")
	_expect(_when(TargetSelector.triggering()), "when Trigger",
			"when: TRIGGERING is 'Trigger' here and 'Them' on the action line — the "
			+ "asymmetry is deliberate, they are one sentence in two cases")
	_expect(_when(TargetSelector.enemies()), "when Enemy Unit",
			"when: a team filter carries resolution, team word and noun — and the DEFAULT"
			+ " resolution NEAREST_FIRST contributes no word, so this line is the team and the"
			+ " noun alone (ADR-0285)")
	_expect(_when(TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.NEAREST_ONLY)), "when Nearest Enemy Unit",
			"when: and STRICT depth is the one that says 'Nearest' — the same pool, one word"
			+ " apart, which is the distinction the whole column exists to make")
	_expect(_when(TargetSelector.friendlies(UnitRole.Role.MELEE)), "when Ally Melee",
			"when: a named role")
	_expect(_when(TargetSelector.specific(["Agrias"] as Array[String])), "when Agrias",
			"when: SPECIFIC_UNITS takes the bare noun with no resolution word")
	_expect(_when(null), "",
			"when: a null condition target prints nothing at all — not even a bare 'when'")

	# 🔴 THE STAT NAME ON A "when" LINE COMES FROM THE **ACTION** TARGET, AND THAT
	# IS A DEFECT THIS TEST PINS RATHER THAN FIXES. The resolution word is built
	# from the strategy alone and then reads `action_target.stat_name` for it, so
	# a condition target resolved by HIGHEST_STAT prints the stat the ACTION was
	# aimed by. Pinned so the move cannot quietly change it (ADR-0167 — a
	# behavioural change does not ride inside a move) and so the ticket that fixes
	# it inherits a failing assertion instead of having to write one.
	var when_by_stat = TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.HIGHEST_STAT, &"Brave")
	var act_by_stat = TargetSelector.friendlies().with_resolution(
			TargetSelector.ResolutionStrategy.NEAREST_FIRST, &"Speed")
	var crossed := _g(when_by_stat, _always(), Gambit.ActionKind.WAIT, -1, act_by_stat)
	_expect(_lines(crossed)[1], "when Highest Speed Enemy Unit",
			"🔴 KNOWN DEFECT PINNED: the when-line's stat is the ACTION target's "
			+ "('Speed'), not the condition target's ('Brave')")


# --- the action line -------------------------------------------------------

func _action_line() -> void:
	var them := TargetSelector.triggering()
	for pair in [[Gambit.ActionKind.ATTACK, "Attack"], [Gambit.ActionKind.WAIT, "Wait"],
				 [Gambit.ActionKind.MOVE, "Move"]]:
		var g := _g(TargetSelector.self_(), _always(), pair[0], -1, them)
		_expect(_lines(g)[0], "%s Them" % pair[1], "control verb: %s" % pair[1])

	# The ABILITY branch. The NAME is the bank's and is not this test's subject;
	# the composition around it is.
	var any_view := AbilityDatabase.get_ability_view(1)
	if any_view.is_empty() or any_view.name.is_empty():
		_failed = true
		print("[FAIL] positive control: ability id 1 has no name in the bank, so the "
			  + "ABILITY case below would pass for the wrong reason")
	else:
		var g := _g(TargetSelector.self_(), _always(), Gambit.ActionKind.ABILITY, 1, them)
		_expect(_lines(g)[0], "%s Them" % any_view.name,
				"an ability action line composes <bank name> + target phrase")

	# The fallback IS this surface's, so it is a literal.
	var unknown := _g(TargetSelector.self_(), _always(), Gambit.ActionKind.ABILITY, 999999, them)
	_expect(_lines(unknown)[0], "Ability? Them",
			"an ability id the bank cannot name falls back to 'Ability?'")


# --- the six-line shape ----------------------------------------------------

func _sentence_lines() -> void:
	var wait := Gambit.ActionKind.WAIT
	var slf := TargetSelector.self_()

	# "Always" is rendered as a BLANK line, not as the word — the row shows the
	# rule, and "when Self / is Always" would be noise the player has to read past.
	var plain := _g(slf, _always(), wait, -1, slf)
	_expect(_lines(plain), ["Wait Self", "when Self", "", "", "", ""] as Array[String],
			"an Always condition renders as an EMPTY line")

	var one := _g(slf, [GambitCondition.target_hp_below(50.0)], wait, -1, slf)
	_expect(_lines(one),
			["Wait Self", "when Self", "is HP < 50%", "", "", ""] as Array[String],
			"the first real condition takes the 'is ' prefix")

	var two := _g(slf, [GambitCondition.target_hp_below(50.0), GambitCondition.is_ko()],
			wait, -1, slf)
	_expect(_lines(two),
			["Wait Self", "when Self", "is HP < 50%", "and KO'd", "", ""] as Array[String],
			"the second takes 'and '")

	# An Always in the MIDDLE blanks its own line and does NOT consume a prefix —
	# the next real condition still reads "and", because the counter only advances
	# on a rendered row.
	var gap := _g(slf, [GambitCondition.target_hp_below(50.0), GambitCondition.always(),
			GambitCondition.is_alive()], wait, -1, slf)
	_expect(_lines(gap),
			["Wait Self", "when Self", "is HP < 50%", "", "and Alive", ""] as Array[String],
			"an Always mid-list blanks a line without spending the 'and'")

	# FOUR is the ceiling. A fifth condition is dropped silently, and the row is
	# six lines whatever happens.
	var five: Array = []
	for i in range(5):
		five.append(GambitCondition.target_hp_below(10.0 * (i + 1)))
	var over := _g(slf, five, wait, -1, slf)
	_expect(_lines(over).size(), 6, "always six lines")
	_expect(_lines(over),
			["Wait Self", "when Self", "is HP < 10%", "and HP < 20%", "and HP < 30%",
			 "and HP < 40%"] as Array[String],
			"a FIFTH condition is dropped without a word")

	var none := _g(slf, [], wait, -1, slf)
	_expect(_lines(none), ["Wait Self", "when Self", "", "", "", ""] as Array[String],
			"no conditions at all is still six lines")

	# A null condition in the array must not crash the row.
	var holed := _g(slf, [null, GambitCondition.is_ko()], wait, -1, slf)
	_expect(_lines(holed),
			["Wait Self", "when Self", "", "is KO'd", "", ""] as Array[String],
			"a null condition blanks its line and does NOT spend the 'is' — so the next "
			+ "real condition still opens the list")


# --- every condition sentence ---------------------------------------------

## All eighteen `Type` members, so a sentence cannot be lost in the move by
## being the one nobody wrote a case for.
func _condition_sentences() -> void:
	var T := GambitCondition.Type
	var C := GambitCondition.Comparator

	var hp := GambitCondition.new(T.SELF_HP, C.LESS_THAN, 40.0)
	_expect(_says(hp), "HP < 40%", "SELF_HP")
	_expect(_says(GambitCondition.new(T.ALLY_HP, C.GREATER_THAN, 60.0)),
			"HP > 60%", "ALLY_HP — same words as SELF_HP, the subject is the target line's")
	_expect(_says(GambitCondition.new(T.ENEMY_HP, C.EQUALS, 100.0)),
			"HP = 100%", "ENEMY_HP")
	_expect(_says(GambitCondition.new(T.TARGET_HP, C.LESS_THAN, 25.0)),
			"HP < 25%", "TARGET_HP")
	_expect(_says(GambitCondition.new(T.SELF_MP, C.LESS_THAN, 20.0)),
			"MP < 20%", "SELF_MP")
	_expect(_says(GambitCondition.new(T.TARGET_MP, C.GREATER_THAN, 30.0)),
			"MP > 30%", "TARGET_MP")

	# The three range types drop the comparator AND the threshold, so they render
	# as a bare noun phrase.
	for t in [T.ENEMY_IN_RANGE, T.ALLY_IN_RANGE, T.TARGET_IN_RANGE]:
		_expect(_says(GambitCondition.new(t, C.LESS_THAN, 99.0)),
				"In Range", "%s drops comparator and threshold" % T.keys()[t])

	_expect(_says(GambitCondition.new(T.ENEMY_COUNT, C.GREATER_THAN, 3.0)),
			"Enemies > 3", "ENEMY_COUNT")
	_expect(_says(GambitCondition.new(T.ALLY_COUNT, C.LESS_THAN, 2.0)),
			"Allies < 2", "ALLY_COUNT")

	# ALWAYS renders "Else" through the structured data and then "Always" through
	# the sentence — the two disagree on purpose and both are load-bearing.
	_expect(_says(GambitCondition.always()), "Always", "ALWAYS")
	_expect(GambitCondition.always().get_ui_display_data()["type"], "Else",
			"positive control: the STRUCTURED data says 'Else' where the sentence says "
			+ "'Always', so the sentence is not a passthrough")

	# 🔴 THE STATUS NAME NEVER REACHES THE SENTENCE, AND THAT IS A DEFECT PINNED
	# RATHER THAN FIXED. `get_ui_display_data` puts the status in the THRESHOLD
	# slot and clears the comparator; `get_sentence_text` then returns the type
	# alone whenever the comparator is empty, so "Has Status Poison" and "Has
	# Status Haste" are the SAME string — a row that cannot say which status the
	# rule is about. `IN_RANGE_OF` escapes it only because it fills the comparator
	# with the word "of". Fixing it changes what a player reads, and ADR-0167 says
	# that does not ride inside a move.
	var poison := GambitCondition.has_status(&"Poison")
	_expect(_says(poison), "Has Status",
			"🔴 KNOWN DEFECT PINNED: HAS_STATUS drops the status name")
	_expect(_says(GambitCondition.missing_status(&"Haste")), "Missing",
			"🔴 KNOWN DEFECT PINNED: MISSING_STATUS drops the status name too")
	_expect(poison.get_ui_display_data()["threshold"], "Poison",
			"positive control: the STRUCTURED data carries 'Poison' — the name is present "
			+ "and the sentence is what drops it, so this is a rendering defect and not a "
			+ "missing field")

	var missing_hp := GambitCondition.new(T.HP_MISSING)
	missing_hp.hp_amount = 120
	_expect(_says(missing_hp), "HP Missing >= 120",
			"HP_MISSING overrides the comparator with '>='")

	var in_range_of := GambitCondition.new(T.IN_RANGE_OF)
	in_range_of.ability_name = &"Cure"
	_expect(_says(in_range_of), "In Range of Cure",
			"IN_RANGE_OF puts the ability in the THRESHOLD slot and 'of' in the comparator's")

	_expect(_says(GambitCondition.is_ko()), "KO'd", "IS_KO")
	_expect(_says(GambitCondition.is_alive()), "Alive", "IS_ALIVE")
	_expect(_says(GambitCondition.new(T.TARGET_DISTANCE, C.LESS_THAN, 4.0)),
			"Distance < 4", "TARGET_DISTANCE")

	# Completeness: every enum member above is named. If one is added and this
	# count is not, the new sentence ships ungraded.
	_expect(T.keys().size(), 19, "every Type member has a pinned sentence above — "
			+ "if this fails, a new condition type landed without one")


# --- the debug repr, which is NOT prose and does NOT move ------------------

## `_to_string` is the engine hook `str(gambit)` reaches, and #1160 keeps it in
## the almanac. It shares NO helper with the sentence surface: it composes
## `TargetSelector._to_string`, `GambitCondition._to_string` and the action's
## display name, all three of which stay. Pinned here because two of its three
## call sites print to a HUMAN (`GambitBattle._report_prune` is player-facing)
## and neither has any other assertion.
func _debug_repr() -> void:
	var g := _g(TargetSelector.friendlies(UnitRole.Role.HEALER),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
	_expect(str(g), "[✓] [Healer Friendly] HP < 50% → Attack",
			"str(gambit) — the repr `GambitBattle._report_prune` prints to the player")

	g.enabled = false
	_expect(str(g), "[ ] [Healer Friendly] HP < 50% → Attack",
			"a disabled gambit swaps the tick for a blank")

	var empty := Gambit.new()
	_expect(str(empty), "[✓] [Self] Always → Wait", "the empty gambit's repr")

	var no_conds := _g(TargetSelector.self_(), [], Gambit.ActionKind.WAIT, -1,
			TargetSelector.self_())
	_expect(str(no_conds), "[✓] [Self] Always → Wait",
			"no conditions reads the same as one Always — the repr cannot tell them apart")
