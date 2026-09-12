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
## `revive_ids` carries NO DEFAULT on purpose: a defaulted bucket is a posture
## family a caller can omit by accident, and the omission would read as "this unit
## cannot revive" rather than as a missing argument.
static func postures_for(role: int, offensive_ids: Array, healing_ids: Array,
		revive_ids: Array) -> Array:
	var out: Array = []
	out.append_array(_raise_the_fallen(revive_ids, healing_ids))
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
