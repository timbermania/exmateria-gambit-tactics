class_name RolloutPlaybook
extends RefCounted

## Authored gambit POSTURES the rollout's candidate set draws on (#895, §7).
##
## §7's candidate set is "one-step mutation operators + a per-job authored
## playbook + imperative-issue". Mutation alone gets stuck refining a posture it
## can never abandon — every operator is a one-step edit, so a list that opens
## ATTACK/ALWAYS can reach "attack the weakest first" but never "hang back and
## heal", which is three coordinated edits away. The playbook is the set of whole
## postures the search can jump to in one step.
##
## 🔴 KEYED BY `UnitRole`, NOT BY JOB ID. §7 says "per-job", and a per-job table
## would be ~130 rows of invention with no data behind any of them. `JobDatabase`
## already owns a tested job -> archetype map (`get_job_role`, 5 roles, HYBRID for
## every unknown including monsters and specials), so the role is the widest key
## that is ALREADY authored. Splitting a role into its jobs later is additive: a
## job-keyed override table in front of this one changes no caller.
##
## Postures are authored as domain `Gambit` objects and encoded by the one
## encoder (`GambitEncoder` -> `GPUCombatPacker._pack_gambits`), never as raw
## ints. An authored posture that the GPU cannot express therefore fails the same
## ADR-0023 faithful-or-explicit way an editor-authored one does — loudly, at the
## encoder — instead of becoming a silently different battle plan inside a
## rollout nobody watches.
##
## Which abilities a posture may name is NOT a judgement this file makes: it is
## handed the unit's statically-usable ability ids by `RolloutCandidates`, which
## reads them out of the same ability table the shader reads (see that file's
## note on the static-only prefilter).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole

## At most this many of the unit's abilities get a posture of their own. A unit
## with twelve spells would otherwise flood the candidate set with twelve
## near-identical openers and crowd out every mutation family — and the families
## are interleaved (`RolloutCandidates.generate`), so a flood costs the OTHER
## families their slots, not its own.
const MAX_ABILITY_POSTURES := 3

## How many revive abilities the ONE revive posture lists, in id order — which is
## also cheapest-first over the shipped five (Raise 10 MP before Raise2 20 MP).
## Two, not `MAX_ABILITY_POSTURES` postures of one: every revive gambit carries
## the same condition, so slot 0 wins whenever it CAN, and the later slots are
## reached exactly when it cannot (MP, the 120-tick cooldown, range). That is one
## plan with a fallback, where three postures differing only in which raise they
## spell would be the near-identical flood `MAX_ABILITY_POSTURES` exists to stop.
const MAX_REVIVE_GAMBITS := 2

## How near an enemy has to be for the withdraw posture's opening slot to fire —
## MANHATTAN tiles, and `COND_DISTANCE_LESS` is strict, so 3 means "adjacent or one
## step from it".
##
## 🔴 THIS NUMBER IS PINNED TO `RolloutCandidates.CONDITION_MENU`'S OWN DISTANCE
## FIGURE, NOT CHOSEN. The `condition` family re-conditions any enabled slot from
## that menu, and the menu's two distance entries both read 3. Authoring the same
## number puts this posture's slot ON the mutation lattice rather than one step off
## it: the search can walk the threshold, and the walk starts from a value it
## already offers. Pinning is asserted, not hoped for —
## `RolloutCandidatesTest._test_withdraw_posture` holds the two equal, because a
## silent drift would leave the posture a neighbour of nothing.
const WITHDRAW_TILES := 3


## The HP thresholds the authored postures switch on. Named because two postures
## share them and a silent disagreement between "hurt enough to finish" and
## "hurt enough to heal" reads as a playbook bug that is really a typo.
const FINISH_HP_PERCENT := 40.0
const MEND_HP_PERCENT := 60.0


## Every posture this role can be handed, as arrays of `Gambit` objects in
## priority order (slot 0 first). The safety net is NOT included — the encoder
## injects it at slot `MAX_USER_GAMBITS` (ADR-0048), so a posture that runs out
## of applicable slots still has a terminal candidate.
##
## `offensive_ids` / `healing_ids` / `revive_ids` are the unit's statically-usable
## ability ids, already split by `RolloutCandidates.usable_abilities` — by the
## ability table's `ABFLAG_HEALING` bit and by its own inflict list. Any of them
## may be empty: a role whose postures all want an ability it does not have
## contributes nothing rather than a posture that cannot fire.
##
## 🔴 THE REVIVE POSTURE IS OFFERED TO EVERY ROLE, AND IT IS FIRST (#1104). Two
## reasons, and the first is data:
##
##   - **The raisers are not on a HEALER job.** `JOB_ROLES` makes Priest — the job
##     that learns Raise and Raise2 — a MAGE, and HEALER is Chemist alone, whose
##     revive is the PhoenixDown ITEM. Offering the posture to HEALER and HYBRID,
##     as #1104's scope reads, would have withheld it from the only generic job
##     whose own skill set can raise the dead. `revive_ids` already answers "can
##     this unit do it", so keying the verb to the role would be asking a second,
##     worse question — the same argument ADR-0293 makes for the kernel: the
##     ABILITY DATA is the permission. A secondary Item skill set puts a
##     PhoenixDown in a Knight's hands and the posture follows it there.
##   - **No mutation can reach it.** `RolloutCandidates`' menus hold neither
##     `COND_IS_DEAD` nor `TARGET_NEAREST_ALLY_OR_KO`, so a revive gambit is two
##     coordinated edits away from anything in the incumbent and the playbook is
##     the ONLY route to it. Its siblings are not in that position: `_press` is
##     one `action` edit away, `_finish` one `condition` edit. So when K is too
##     small to hold the family the tail that drops should be theirs, which is
##     what putting this first means. It costs nothing to the units that cannot
##     revive — for them it returns no posture at all.
##
## 🔴 THE WITHDRAW POSTURE IS SECOND, AND THE ORDER OF THE HEAD IS THE WHOLE
## CROWDING ANSWER (#1104). `_withdraw` is the file's OTHER unreachable-verb
## posture — `_action_menu` holds no `ACTION_RETREAT_STEP`, so like the revive it
## is playbook-only — and it is offered to every role too, for a different reason
## it states itself. It sits BEHIND the revive rather than in front because the
## revive is the scarcer plant: it needs an unreachable condition AND an
## unreachable pool AND an ability the action menu omits, while a withdraw slot,
## once planted, is one `_family_condition` edit from every distance and self-HP
## threshold the menu offers. So the head of this list is the two verbs no edit
## can introduce, revive first, and the TAIL — `_press`, `_finish`, the third
## ability opener — is what `K` truncates, which is right because each of those is
## one edit from the incumbent. For a role with three offensive abilities, what
## this posture displaces is that third opener; nothing else moves.
##
## `revive_ids` carries NO DEFAULT on purpose: a defaulted bucket is a posture
## family a caller can omit by accident, and the omission would read as "this unit
## cannot revive" rather than as a missing argument.
static func postures_for(role: int, offensive_ids: Array, healing_ids: Array,
		revive_ids: Array) -> Array:
	var out: Array = []
	out.append_array(_raise_the_fallen(revive_ids, healing_ids))
	out.append(_withdraw())
	match role:
		UnitRole.Role.MELEE, UnitRole.Role.RANGED:
			out.append(_press())
			out.append(_finish())
			out.append_array(_ability_postures(offensive_ids))
		UnitRole.Role.MAGE:
			out.append_array(_ability_postures(offensive_ids))
			out.append(_focus_weak(offensive_ids))
			out.append(_press())
		UnitRole.Role.HEALER:
			out.append_array(_mend_postures(healing_ids))
			out.append(_press())
			out.append_array(_ability_postures(offensive_ids))
		_:
			# HYBRID and ANY — Squire, Geomancer, Oracle, every monster, every
			# special. The widest set, deliberately: an archetype we cannot name
			# gets the union of the two we can, not a narrower guess.
			out.append(_press())
			out.append(_finish())
			out.append_array(_ability_postures(offensive_ids))
			out.append_array(_mend_postures(healing_ids))
	var kept: Array = []
	for p in out:
		if not p.is_empty():
			kept.append(p)
	return kept


## Hit the nearest enemy, always. The floor posture, and the one that lets the
## search ABANDON a bad plan in a single step — a candidate set that cannot
## propose "just attack" leaves a caster that has run dry refining which spell it
## cannot afford.
static func _press() -> Array:
	return [Gambit.create(
		TargetSelector.enemies(), [GambitCondition.always()],
		Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())]


## Finish the weakest enemy first, then fall through to the nearest.
static func _finish() -> Array:
	return [
		Gambit.create(
			_weakest_enemy(), [GambitCondition.target_hp_below(FINISH_HP_PERCENT)],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
		Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
	]


## One posture per offensive ability: open with it, fall through to attacking.
static func _ability_postures(offensive_ids: Array) -> Array:
	var out: Array = []
	for i in range(mini(offensive_ids.size(), MAX_ABILITY_POSTURES)):
		out.append([
			Gambit.create(
				TargetSelector.enemies(), [GambitCondition.always()],
				Gambit.ActionKind.ABILITY, int(offensive_ids[i]), TargetSelector.triggering()),
			Gambit.create(
				TargetSelector.enemies(), [GambitCondition.always()],
				Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
		])
	return out


## Spend the strongest opener on the enemy already closest to dying.
static func _focus_weak(offensive_ids: Array) -> Array:
	if offensive_ids.is_empty():
		return []
	return [
		Gambit.create(
			_weakest_enemy(), [GambitCondition.target_hp_below(FINISH_HP_PERCENT)],
			Gambit.ActionKind.ABILITY, int(offensive_ids[0]), TargetSelector.triggering()),
		Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
	]


## Raise the fallen ally, else mend the worst-off living one, else attack — ONE
## posture (#1104), the whole "hang back and bring them back" plan the file's header
## says mutation cannot assemble.
##
## 🔴 THE KO-INCLUSIVE POOL AND `IS_KO` ARE BOTH REQUIRED, AND NEITHER IS OPTIONAL.
## Every pool is KO-blind by default, so `friendlies()` + `is_ko()` is a slot that
## decides a condition it can never reach (#1102); `friendlies_or_ko()` without the
## condition ranks the corpse against the living and spends the raise on whoever is
## nearest. The pair is the image `tests/gambit_scenarios/scenarios_F_actions.gd`'s
## F7 and F8 scenarios watch revive a real corpse in a real battle — the same three
## fields, authored here by the same factories.
##
## ⚠️ AND IT MUST BE `IS_KO`, NOT A STATUS CHECK. `STATUS_DEAD` (bit 0) is hollow —
## nothing in the kernel sets it (#1105) — so `has_status(&"dead")` encodes cleanly
## and never fires. #1104 names this as the place that trap would resurface, and
## inside a rollout nobody watches it is the worst place to land it.
##
## The mend fall-through reads `healing_ids[0]` rather than every healing ability
## because this posture's subject is the corpse; the per-ability mend postures are
## `_mend_postures`' job and this is their one-step neighbour, not their rival.
static func _raise_the_fallen(revive_ids: Array, healing_ids: Array) -> Array:
	if revive_ids.is_empty():
		return []
	var posture: Array = []
	for i in range(mini(revive_ids.size(), MAX_REVIVE_GAMBITS)):
		posture.append(Gambit.create(
			TargetSelector.friendlies_or_ko(), [GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, int(revive_ids[i]), TargetSelector.triggering()))
	if not healing_ids.is_empty():
		posture.append(Gambit.create(
			_weakest_ally(), [GambitCondition.target_hp_below(MEND_HP_PERCENT)],
			Gambit.ActionKind.ABILITY, int(healing_ids[0]), TargetSelector.triggering()))
	posture.append(Gambit.create(
		TargetSelector.enemies(), [GambitCondition.always()],
		Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()))
	return [posture]


## Back off when a foe has closed, else press — ONE posture (#1104), the retreat
## half of the two verbs this ticket exists to make reachable. ADR-0301 is the rule
## it authors against: a retreat is ONE tile directly away from the unit it is aimed
## at, and then a fresh decision.
##
## 🔴 OFFERED TO EVERY ROLE, AND THE REASON IS NOT THE ONE THAT MADE THE REVIVE
## POSTURE UNIVERSAL. `_raise_the_fallen` skips the role gate because the ABILITY
## DATA answers the same question better (`revive_ids`, ADR-0293's argument applied
## to authoring). Retreat has no such data: a step needs no ability, so nothing in
## `RolloutCandidates.make_context` can say which units want to disengage, and the
## role genuinely IS the widest key available here. It is still not used as a gate,
## for a different reason:
##
##   - **Planting the verb once puts the whole retreat family on the mutation
##     lattice.** `RolloutCandidates._action_menu` holds ATTACK, WAIT and the unit's
##     spells and NOTHING else — `ACTION_RETREAT_STEP` is in no menu, so no one-step
##     edit can introduce a retreat into a list that has none. But once a slot
##     CARRIES the verb, `_family_condition` can re-condition it from
##     `CONDITION_MENU` x `CONDITION_TARGET_MENU`, which between them hold
##     `SELF / HP_BELOW(50)` and `(25)`. So the low-HP break-off — the retreat a
##     MELEE unit actually wants — is ONE condition edit from this posture, and
##     withholding the posture from MELEE would have withheld the VERB from the
##     role entirely, for every beat of every rollout. ADR-0301's own closing note
##     is that every balance number so far was tuned against an AI that could not
##     disengage; a role gate here would have left the largest role exactly there.
##   - **So the HP-keyed variant is deliberately NOT authored.** Two postures one
##     condition edit apart is the near-identical flood `MAX_ABILITY_POSTURES`
##     exists to stop, and the search picks the threshold better than a balance
##     number invented in this file would.
##
## ⚠️ THE AIM IS `triggering()` AND IT MUST NOT BE `self_()`. A retreat's
## `action_target` is the unit to move AWAY from (`GambitEncoder` ->
## ACTION_RETREAT_STEP). Aimed at the caster, `retreat_step_cell` refuses
## `flee_from == unit_id` outright and the slot is a guaranteed VERDICT_NO_RETREAT —
## a row that can never fire, which `GambitOptions.aim_verdict` grades
## AIM_FORBIDDEN for the same reason. `triggering()` forwards to the condition
## subject, the nearest enemy, which is step 1 of the user's own definition of
## retreat ("find the nearest enemy").
##
## The ATTACK fall-through is not decoration. A retreat that cannot open distance
## FALLS THROUGH (ADR-0301: the cell is picked in the DECIDE stage precisely so it
## can), and without a slot beneath it a cornered unit would reach the safety net
## instead — which walks it back toward the thing it was fleeing. `_press`'s shape,
## for `_press`'s reason.
static func _withdraw() -> Array:
	return [
		Gambit.create(
			TargetSelector.enemies(), [GambitCondition.target_within(WITHDRAW_TILES)],
			Gambit.ActionKind.RETREAT, -1, TargetSelector.triggering()),
		Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
	]


## One posture per healing ability: mend the worst-off ally, else attack.
static func _mend_postures(healing_ids: Array) -> Array:
	var out: Array = []
	for i in range(mini(healing_ids.size(), MAX_ABILITY_POSTURES)):
		out.append([
			Gambit.create(
				_weakest_ally(), [GambitCondition.target_hp_below(MEND_HP_PERCENT)],
				Gambit.ActionKind.ABILITY, int(healing_ids[i]), TargetSelector.triggering()),
			Gambit.create(
				TargetSelector.enemies(), [GambitCondition.always()],
				Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering()),
		])
	return out


## MOST_CRITICAL is the one non-NEAREST resolution the GPU can express
## (`GambitEncoder._target_selector_to_gpu` -> TARGET_LOWEST_HP_*); HIGHEST_STAT
## and LOWEST_STAT are in the encoder's UNSUPPORTED set, so no posture may reach
## for them.
static func _weakest_enemy() -> TargetSelector:
	var s := TargetSelector.enemies()
	s.resolution = TargetSelector.ResolutionStrategy.MOST_CRITICAL
	return s


static func _weakest_ally() -> TargetSelector:
	var s := TargetSelector.friendlies()
	s.resolution = TargetSelector.ResolutionStrategy.MOST_CRITICAL
	return s
