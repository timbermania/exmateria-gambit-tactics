class_name GambitOptions
extends RefCounted

## The choice catalogues the gambit surface offers — every one a WHOLE domain value built by
## the domain's own constructor, never a raw enum field (ADR-0255 dec. 3, preserved verbatim
## by ADR-0268 dec. 1).
##
## === WHY THIS IS NOT ON THE SCREEN ==========================================================
##
## ADR-0268 dec. 8: *every choice this surface offers must round-trip through [GambitEncoder]
## without a skip.* Rule **E1** (ADR-0023) makes a gambit carrying an UNSUPPORTED feature a
## null slot at encode time — `push_error`, evaluation falls through — so a screen that OFFERS
## such a choice silently bricks the row the player just authored, **and the row reads back
## correctly while doing nothing**. That is the worst shape a defect can take on an authoring
## surface: the readout agrees with the player and the unit does not.
##
## The gate is a test, and the test has to be able to ask for the lists **without booting a
## screen** — a guard that needed the surface would need a battle, a turn and a cast, and would
## be the slowest process in the suite for an assertion about two arrays. So the catalogues
## live here, static and scene-free, and [GambitSurface] reads them. `GambitEncoderTest`
## round-trips the whole cross-product in a pure, GPU-free process.
##
## === WHAT IS NOT HERE =======================================================================
##
## The ABILITY choices. They are [method AdjustmentTurn.usable_ability_ids] filtered by the
## character's job and sub-job, so they are a question about a UNIT and not about the screen's
## vocabulary; the surface still assembles those. They cannot fail the E1 gate as a SET — an
## ABILITY encodes on its `ability_id` alone (`GambitEncoder._encode_from_gambit_object`) — so
## what the guard checks for them is the one way they can: an id of -1.

const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityFamily = ExMateriaAlmanac.AbilityFamily


## The target presets, shared by "To" and "When" — one named whole selector each, never a
## cross-product of pool x team x resolution.
##
## All eight are E1-supported: SELF and TRIGGERING map directly, and the six TEAM_FILTER
## selectors use NEAREST_FIRST / NEAREST_ONLY / MOST_CRITICAL, which are the only three
## resolutions `_target_selector_to_gpu` maps (HIGHEST_STAT, LOWEST_STAT and FIRST_IN_ROSTER
## are in `GambitEncoder.UNSUPPORTED_RESOLUTIONS`, and SPECIFIC_UNITS in
## UNSUPPORTED_POOL_TYPES — which is why there is no "Named Unit" row here and cannot be one
## until #32/#33 drain).
##
## === THREE ROWS PER TEAM, AND THE MIDDLE ONE IS NEW CAPABILITY (ADR-0285) ===================
##
## *"I want all 3 options. Ally, Nearest, Weakest"*. The column now splits POOL from DEPTH:
##
## [codeblock]
## Ally           the whole team; the condition FILTERS it, act on the first match
## Nearest Ally   ONE unit by proximity;  the condition GATES it
## Weakest Ally   ONE unit by lowest HP;  the condition GATES it
## [/codeblock]
##
## 🔴 `Ally` IS TODAY'S `Nearest Ally`, BYTE FOR BYTE — and that is the bug being named, not a
## relabel for its own sake. `TARGET_NEAREST_ALLY` is retried at ranks 1, 2, 3… by
## `evaluate_gambits_up_to`'s second pass, so the row has always meant *"an ally"* while its
## label said *"the nearest ally"*. The player's own objection — *"it can't be nearest and
## any"* — is correct and this is the answer to it. Every existing save keeps the selector it
## already had, so nothing a player authored before today changes behaviour; only the WORD on
## the row changes, from a wrong one to a right one.
##
## `Nearest Ally` / `Nearest Foe` are the genuinely new rows. Strict depth did not exist in the
## kernel before ADR-0285: Pass 2's retry decision reads `cond_target_type` and nothing else,
## with no per-slot flag to consult, which is why this needed two GPU target types rather than
## a bit on the row.
##
## ⚠️ **A lone unit's `Nearest Ally` resolves to NOBODY.** `find_unit_by_criteria` skips the
## caster on the nearest metric unconditionally (`if (mode == 0 && u == unit_id) continue;`),
## so with no other friendly standing the strict row has no rank 0 and Pass 1 writes
## `VERDICT_NO_CANDIDATE`. That is exactly what today's `Nearest Ally` does in the same spot —
## strict depth changes what happens AFTER rank 0 fails, never whether rank 0 exists — so it is
## recorded rather than fixed here. `Ally` behaves identically for the same reason.
##
## ORDER IS LOAD-BEARING: the cursor rests on the head of this list, `Self` stays at it, and
## each team's POOL row leads its own group with the two narrowings under it. Eight rows now
## scroll past `GambitSurfaceMenu.VISIBLE_ROWS`.
static func targets() -> Array:
	return [
		{"name": "Self", "make": func(): return TargetSelector.self_()},
		{"name": "Them", "make": func(): return TargetSelector.triggering()},
		{"name": "Foe", "make": func(): return foe_pool()},
		{"name": "Nearest Foe", "make": func():
			return TargetSelector.enemies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_ONLY)},
		{"name": "Weakest Foe", "make": func():
			return TargetSelector.enemies().with_resolution(TargetSelector.ResolutionStrategy.MOST_CRITICAL)},
		{"name": "Ally", "make": func():
			return TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_FIRST)},
		{"name": "Nearest Ally", "make": func():
			return TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_ONLY)},
		{"name": "Weakest Ally", "make": func():
			return TargetSelector.friendlies().with_resolution(TargetSelector.ResolutionStrategy.MOST_CRITICAL)},
	]


## The SUBJECT vocabulary — who the condition is a question ABOUT (ADR-0283 dec. 1).
##
## Two rows and it is deliberately not six. A full subject selector is what ADR-0268 dec. 2
## priced and rejected: its widest string is `Most Critical Ally` at 68 px, and no arrangement
## of four columns survives that. Two words survive at 20 px (`Their`), and the ally/foe and
## nearest/weakest axes are ALREADY on the screen one column to the left — so nothing is lost
## by keeping the subject to a switch. "Test the weakest ally" is `To = Weakest Ally` with
## `Subject = Their`.
##
## === `Their` MIRRORS THE `To` COLUMN, AND THAT IS THE POINT OF THE WHOLE CHANGE ============
##
## `Their` does not name a pool of its own. It builds a COPY of the gambit's own
## `action_target`, so `cond_target_type == action_target_type` — and that equality is what
## reaches the kernel's second pass. `evaluate_gambits_up_to` retries a slot at rank 1, 2, 3…
## (`find_nth_nearest`) for exactly three condition targets — `TARGET_NEAREST_ENEMY`,
## `TARGET_NEAREST_ALLY`, `TARGET_NEAREST_ALLY_OR_KO` — and writes `VERDICT_NOT_RETRYABLE` for
## every other one (`stage_compute.glsl`, the `target_type !=` guard in Pass 2).
##
## The FOLDED catalogue could not reach it. Every `Ally HP<X%` row bound its subject to
## MOST_CRITICAL friendlies, which `GambitEncoder._target_selector_to_gpu` maps to
## `TARGET_LOWEST_HP_ALLY` — one of the non-retryable types. So the screen offered the one ally
## subject that switches the rank walk OFF, and *"the nearest ally whose HP is below half"* was
## inexpressible from it. `To = Nearest Ally` + `Subject = Their` is that sentence, and the
## kernel has always been able to run it.
##
## A copy and not a reference (`from_dict(to_dict())`): a shared selector would make a later
## edit of the `To` column silently rewrite the subject of a condition the player is not
## looking at. [method GambitSurface._resync_subject] re-derives it on purpose instead, which
## is a write the row can show.
static func subjects() -> Array:
	return [
		{"name": SUBJECT_MINE, "make": func(_aim): return TargetSelector.self_()},
		{"name": SUBJECT_THEIRS, "make": func(aim): return mirror_of(aim)},
	]


## A COPY of `aim`, which is what [constant SUBJECT_THEIRS] means — with the one aim it cannot
## copy answered explicitly.
##
## 🔴 **A `TRIGGERING` aim is NOT copied.** `Them` means "whoever the subject picked", so
## copying it onto the subject is a cycle, and the encoding it produces —
## `cond_target_type = TARGET_THEM` — is one `select_target` answers `-1` for (see
## [constant AIM_NEVER_RESOLVES]). The subject falls back to the actor, which is the one
## concrete unit a `Them` aim can be made to resolve to, and the row then says `My` — a
## sentence that is merely redundant instead of one that never fires. [method aim_verdict]
## withholds the `Them` row from the `To` list for the same reason, so the screen does not
## normally reach here; a save or a mutation operator can.
##
## PUBLIC because the surface mirrors on four paths (a `To` press, a `Subject` press, a blank
## condition and the aim seed) and a fifth copy of this rule would be the one that forgets the
## `TRIGGERING` case.
static func mirror_of(aim):
	if aim == null or aim.pool_type == TargetSelector.PoolType.TRIGGERING:
		return TargetSelector.self_()
	return TargetSelector.from_dict(aim.to_dict())


## The actor. `My HP<50%` is "when I am below half".
const SUBJECT_MINE := "My"
## Whoever the `To` column picked out. `Their HP<50%` is "when THAT one is below half".
const SUBJECT_THEIRS := "Their"
## What a column with nothing in it reads as — `—`, the em dash, which FONT.BIN carries as one
## 10-px glyph.
##
## NOT the empty string, and that is a rendering decision with a reason: an empty column is a
## column the focus chevron points at nothing beside, and on a row where both the subject and
## the test are unset that is two thirds of the sentence rendered as a gap the player cannot
## tell from a draw failure. `—` says "deliberately nothing", which is what it is.
const BLANK := "—"


## The condition presets for the "If" part — a BARE predicate each, with no subject baked in
## (ADR-0283 dec. 2 supersedes ADR-0268 dec. 2's fold).
##
## `HP<50%` and not `Ally HP<50%`: the subject is its own column now ([method subjects]), so an
## entry here answers ONE field — `conditions[0]` — and the 13 folded `(subject, test)` pairs
## collapse to these 5 plus [constant BLANK]. Nothing became unsayable: the ally/foe axis moved
## to the `To` column, which already offers all four pools.
##
## [b]`Always` IS NOT HERE ANY MORE, and blank is not a sixth condition — it is the ABSENCE of
## one.[/b] `check_gambit_conditions` loops `for c in 0..cond_count` and returns `true` at zero,
## so a zero-length `conditions` array already fires every time; a named `Always` row was a
## second spelling of that, and it was the spelling the row had to print in a column whose whole
## job is to say what the rule TESTS. `GambitCondition.Type.ALWAYS` stays in the DOMAIN — #895's
## mutation operators write it and old saves carry it — and [method condition_label] reads it
## back as blank rather than pretending it is not there.
##
## [b]No comparator spaces, and that is 8 px of the row.[/b] `HP < 25%` measures 48 px against
## `HP<25%`'s 40 — the ROM space advance is 4 px each side of a 10-px `<`. Those 8 px are the
## difference between a `Do` column that elides 21 of 228 ability names and one that elides 102:
## the count is not linear in the cap, it has a cliff between 48 px and 46.
##
## [b]"In Range" is ONE row now, not two, and it is not two RANGES either.[/b] The screen used
## to offer `In Melee Range` and `In Spell Range` — both
## [constant GambitCondition.Type.TARGET_IN_RANGE], both in
## `GambitEncoder.UNSUPPORTED_CONDITION_TYPES`, so both authored a slot that read back correctly
## and never once fired. ADR-0268 dec. 8 removed them; dec. 11 brought the idea back drained as
## `Ally In Range` / `Foe In Range`, and unfolding the subject collapses that pair too.
##
## THE RANGE IS THE ACTION'S. A row asking "melee or spell?" asks the player to restate what
## the `Do` column already says, and gets it wrong the moment they change `Do`: the kernel
## answers against the gambit's own action — the equipped weapon for `Attack` / `Move` / `Wait`,
## the ability's own reach for an ability, including the ROM's vertical tolerance and its
## line-of-sight. So `range_type` is set and IGNORED by the encoder (see
## `GambitEncoder._encode_gambit_condition`).
static func conditions() -> Array:
	return [
		{"name": "HP<25%", "make": func(): return GambitCondition.target_hp_below(25.0)},
		{"name": "HP<50%", "make": func(): return GambitCondition.target_hp_below(50.0)},
		{"name": "HP>50%", "make": func(): return GambitCondition.target_hp_above(50.0)},
		{"name": "MP<50%", "make": func(): return GambitCondition.target_mp_below(50.0)},
		{"name": "In Range", "make": func(): return GambitCondition.target_in_range()},
	]


## PUBLIC, because it is two things at once and they have to be the SAME value: the `Foe In
## Range` condition's subject, and the aim a bare `Attack` seeds onto an unaimed slot
## (`GambitSurface._seed_aim`). It is also the `Foe` row of [method targets], which is what
## lets the `To` column NAME the seeded aim — `_target_text` probes that catalogue, so an aim
## built from a second literal would render as the fallback rather than as itself.
##
## 🔴 CALLED `foe_pool()` UNTIL ADR-0285, AND THE OLD NAME WAS THE SCREEN'S DEFECT IN A
## FUNCTION SIGNATURE. It builds `NEAREST_FIRST`, the pool the kernel walks past rank 0 — the
## single nearest foe and nobody else is the SEPARATE `Nearest Foe` row, built from
## `NEAREST_ONLY`. A seed named after a depth it does not have is how a reviewer confirms the
## wrong thing in one glance, so the name follows the row it builds.
static func foe_pool():
	return TargetSelector.enemies().with_resolution(TargetSelector.ResolutionStrategy.NEAREST_FIRST)


## Which `If` entry a gambit is currently showing, by NAME — the row's readout.
##
## Probed against the catalogue rather than re-derived from the field, so the row can only ever
## print a string the list also offers. A gambit the catalogue cannot name (one #895's mutation
## operators authored, or a save from before ADR-0283) falls through to
## `GambitProse.condition_sentence` — this layer's own general renderer since #1160, where it
## used to be the condition's own `get_sentence_text` — because a row that printed `HP<50%` for
## a condition that is not that would be a readout that lies about the rule the unit is under.
##
## [constant BLANK] for no condition AND for [constant GambitCondition.Type.ALWAYS], which are
## the same rule under two spellings (see [method conditions]): `check_gambit_conditions`
## returns true at zero conditions, and an `ALWAYS` condition returns true at one. The screen
## writes the first spelling and reads back either — so the ALWAYS case never reaches the
## fallback, which is why #1160's rename and ADR-0283's blank rule compose rather than collide.
static func condition_label(gambit) -> String:
	if gambit == null or gambit.conditions.is_empty() or gambit.conditions[0] == null:
		return BLANK
	var cond = gambit.conditions[0]
	if cond.type == GambitCondition.Type.ALWAYS:
		return BLANK
	for entry in conditions():
		var probe = entry["make"].call()
		if probe.type == cond.type and probe.comparator == cond.comparator \
				and is_equal_approx(probe.threshold, cond.threshold):
			return String(entry["name"])
	return GambitProse.condition_sentence(cond)


## Which `Subject` entry a gambit is showing, by NAME — [constant SUBJECT_MINE], [constant
## SUBJECT_THEIRS], or [constant BLANK] for no gambit at all.
##
## 🔴 IT DOES NOT BLANK ON A BLANK CONDITION, AND IT USED TO — ADR-0283 dec. 3, amended. The old
## rule read "a subject is who a QUESTION is about, so with no question there is no subject to
## name", and the same sentence then conceded that printing `Their` there "would name a field the
## player cannot act on". Both halves of that are false on a conditionless row, and the column
## being mute is the reported bug — the SECOND report of it, because `a8e001303` fixed the write
## half (the `If` press no longer overwrites the subject) and left the display half standing.
##
## THE PLAYER CAN ACT ON IT. `GambitSurface`'s `Part.SUBJ` offers the list on a row with no
## condition, deliberately and in writing: the subject is what MAKES the condition mean
## something, so refusing it until a test is set would be a part the player has to author out of
## order. The press landed in `condition_target` and this function erased it on the way to the
## screen — the column was never unselectable, it was MUTE, and from the player's seat those are
## one symptom.
##
## AND THE FIELD HAS BEHAVIOUR WITH NO CONDITION ATTACHED, so the blank hid a live switch rather
## than declining to name nothing. `evaluate_gambits_up_to` (`src/gpu/shaders/stage_compute.glsl`)
## calls `select_target` on the CONDITION target and writes `VERDICT_NO_CANDIDATE` at
## `candidate < 0` BEFORE `check_gambit_conditions` is consulted — and at zero conditions that
## check returns true, so on a conditionless row the subject is the row's ONLY gate.
## `GambitSurface._clear_condition` states it from the other side: a blank condition MIRRORS the
## aim rather than clearing to SELF, or "an `Attack / Nearest Foe` row with no test would gate on
## the ACTOR existing, which is always true, and the row would fire at a pool it never checked
## was there". `My` versus `Their` toggles exactly that gate.
##
## A row holding NOTHING never reaches here — `GambitSurface.row_entries` short-circuits an
## `is_empty()` slot to `---` in all four columns — so what newly prints a subject is a row that
## already says something. That includes the safety net, which reads `Attack / Nearest Foe /
## Their / —`: `Their` is the pool the net is gated on, and the column now says so.
##
## Read off the POOL and not off a catalogue probe, because [constant SUBJECT_THEIRS] has no
## fixed selector to probe against — it is a copy of whatever the `To` column holds. SELF is
## `My`; anything else is `Their`, including the pools the old folded catalogue wrote
## (MOST_CRITICAL allies and foes), which is what makes a pre-ADR-0283 save read as a sentence
## instead of as a gap.
static func subject_label(gambit) -> String:
	if gambit == null:
		return BLANK
	var subject = gambit.condition_target
	if subject == null or subject.pool_type == TargetSelector.PoolType.SELF:
		return SUBJECT_MINE
	return SUBJECT_THEIRS


## The job-independent control verbs the "Do" part offers above the unit's abilities. Each
## `make` answers the `{kind, ability_id}` pair the surface writes onto the gambit, which is
## the stored form (ADR-0023) — never a display name.
##
## ATTACK, MOVE, RETREAT and WAIT are the whole set: `GambitEncoder.UNSUPPORTED_ACTION_KINDS`
## is empty, and ABILITY is not a verb because it carries an id. RETREAT joined them at
## ADR-0301 — it sits next to MOVE because it is the same aim read with the opposite sign
## (move away from, rather than toward).
static func action_verbs() -> Array:
	var out: Array = []
	for verb in [Gambit.ActionKind.ATTACK, Gambit.ActionKind.MOVE, Gambit.ActionKind.RETREAT,
			Gambit.ActionKind.WAIT]:
		var kind: int = verb
		out.append({
			"name": String(Gambit.KIND_TO_VERB[verb]),
			"make": func(): return {"kind": kind, "ability_id": -1},
		})
	return out


# =============================================================================
# THE AIM GATE — which `To` rows a verb is willing to carry (#1125 (b))
# =============================================================================

## A cell's verdict. `(verb x aim)` is the state space the screen offers, and every cell in it
## lands on exactly one of these.
##
## `UNREACHABLE` is deliberately NOT here. That is rule E1's class — a choice the encoder skips
## — and it is asserted where it is already asserted, by `GambitEncoderTest`'s round-trip over
## the offered catalogues (ADR-0268 dec. 8). All eight [method targets] rows encode; what this
## enum grades is what happens AFTER a clean encode, which is the half E1 cannot see.
const AIM_SENSIBLE := &"sensible"
## Legal, encodes, FIRES — and does nothing. `Move / Self` is the whole class: the destination
## is the tile the unit is standing on.
const AIM_NO_OP := &"no_op"
## The ability's own ROM record forbids this pool (ADR-0049's `dont_hit_*` triple).
##
## This is the SPLASH axis: the cursor may land here, and the effect then skips this unit.
## [constant AIM_UNTARGETABLE] is the other axis, and the two are separate ROM rules — see
## ADR-0291 for the state table they form together.
const AIM_FORBIDDEN := &"forbidden"
## The ROM's target-selection routine will not let the CURSOR land here — a different axis
## from [constant AIM_FORBIDDEN]'s splash filter, and the one `dont_target_self` (flags1 bit
## 0x01) names.
##
## Rooted in the ROM, not in the FFHacktics flag name. `FUN_8017A290` @ `0x8017A290` builds the
## selectable-tile table at `0x80192DD8` (0x200 entries x 5 bytes), marks the caster's OWN tile
## selectable at `0x8017A410`-`0x8017A418`, and then at `0x8017A444` tests flags1 & 0x01 and
## `sb zero` ZEROES that entry at `0x8017A450`. The flag removes a tile from the cursor's
## reachable set; it says nothing about who the effect lands on once a tile is chosen.
##
## 🔴 **REACHED ONLY WHERE [constant AIM_FORBIDDEN] DID NOT ALREADY ANSWER, AND THAT IS
## DELIBERATE.** 156 records carry `dont_target_self`; 152 of them also carry
## `dont_hit_caster`, which is graded first and wins. So this grade counts exactly the
## **4-ability gap** the rule was added to close — `Revive` (107), `Invitation` (116), `Wish`
## (152), `BloodSuck` (200) — every one of them skillset-reachable, and every one of them a
## cell the screen offered and the ROM refuses. The census row is therefore the ticket's own
## subject rather than a number that has to be subtracted from another one.
##
## ⚠️ **THE KERNEL DOES NOT ENFORCE THIS AND THIS GRADE DOES NOT CLAIM IT DOES.** ADR-0049's
## triple has a kernel counterpart (`hit_policy_allows` in `combat_combat.glslinc`);
## `dont_target_self` has none, and all four abilities are `effect_area 0`, which is the same
## single-target hole #1144 already opens on. This stops the SURFACE authoring the cell. It
## does not make a gambit arriving from anywhere else safe.
const AIM_UNTARGETABLE := &"untargetable"
## The kernel never reads the aim for this verb, so the column is describing a field nobody
## consults. `Wait / Nearest Foe` is the whole class.
const AIM_IGNORED := &"ignored"
## `Them` under a `Self` subject. It resolves to the actor, so it is the `Self` row already on
## the list under a second name — and it is the name that does NOT say so. #1125 opens on
## exactly this: *"`Attack / Them / Always` names its pool nowhere at all."*
const AIM_UNNAMED := &"unnamed"
## `Them` under a `Their` subject — the CIRCULAR pair, and the one cell the fourth column
## created (ADR-0283). `Their` is a copy of the aim, so a `Them` aim makes the subject
## `TRIGGERING` too, which encodes `cond_target_type = TARGET_THEM` — and the kernel's
## `select_target` answers **`case TARGET_THEM: return -1;  // Set by caller`**. Pass 1 then
## writes `VERDICT_NO_CANDIDATE` and skips the slot, on every tick, forever.
##
## Graded separately from [constant AIM_UNNAMED] because the two fail differently: `unnamed`
## resolves to the actor and merely says so badly, while this ENCODES CLEANLY AND NEVER
## RESOLVES. Rule E1 cannot see it — `_target_selector_to_gpu` maps `TRIGGERING` to a real
## constant — which makes it the same shape as the fold's own defect, one column over.
const AIM_NEVER_RESOLVES := &"never_resolves"


## Which class of unit an aim can name: `&"caster"`, `&"ally"`, `&"foe"`, or `&"unknown"`.
##
## `Them` has no class of its own — it forwards to whatever the `Subject` column picked out
## (`execute_gambit_action`: `final_target = condition_target` when the aim is TARGET_THEM), so
## it is classified by the SUBJECT and one level of forwarding is all there is to follow. On an
## empty slot that subject is `self_()` (`Gambit._init`), which is why `Them` and `Self` are the
## same aim there under two names — the thing #1125 opens with.
##
## ⚠️ **A SUBJECT CAN NOW BE `TRIGGERING` ITSELF, which it could not before ADR-0283.** This
## docstring used to assert the opposite — *"a subject is never itself TRIGGERING (no
## `conditions()` entry builds one), so there is no chain to walk and no cycle to guard
## against"* — and that was true of the folded catalogue and false the moment `Their` became a
## copy of the aim. The recursion is still one hop and still terminates, because the second call
## passes `null`; what changed is that the answer is `&"unknown"`, and
## [constant AIM_NEVER_RESOLVES] is what makes that answer a withheld row instead of a
## fall-through to SENSIBLE.
##
## FRIENDLY is `&"ally"` even though `TargetSelector.friendlies()` includes the caster, and the
## two ally rows are NOT alike about it. `find_unit_by_criteria` skips the caster on NEAREST and
## only on NEAREST (`if (mode == 0 && u == unit_id) continue;`), so `Nearest Ally` can never
## resolve onto the caster and **`Weakest Ally` resolves onto the caster whenever the caster is
## the most-hurt friendly** — which is precisely the tick a heal gambit fires. So for a
## `dont_hit_caster` ability, `Weakest Ally` is a CONTINGENTLY forbidden aim, and the contingency
## is the common case rather than a corner.
##
## Not graded, and that is deliberate: the row is legal to author, legal on most ticks, and the
## screen cannot know the tick. Dropping it would be the gate over-reaching — it removes only
## what it can prove. What the contingency does affect is #1144, whose fix has to decide what a
## forbidden aim DOES; falling through to the next slot handles this case gracefully and hitting
## the caster does not.
static func aim_class(aim, condition_subject = null) -> StringName:
	if aim == null:
		return &"unknown"
	match aim.pool_type:
		TargetSelector.PoolType.SELF:
			return &"caster"
		TargetSelector.PoolType.TRIGGERING:
			# One hop, never two: a subject is never itself TRIGGERING (no `conditions()` entry
			# builds one), so there is no chain to walk and no cycle to guard against.
			if condition_subject == null:
				return &"unknown"
			return aim_class(condition_subject, null)
		TargetSelector.PoolType.TEAM_FILTER:
			if aim.team_filter == TargetSelector.TeamFilter.FRIENDLY:
				return &"ally"
			if aim.team_filter == TargetSelector.TeamFilter.ENEMY:
				return &"foe"
	return &"unknown"


## Grade one `(verb, ability, aim)` cell against the ROM record and the kernel.
##
## === WHY THERE IS A CLASSIFIER, AND WHAT IT IS NOT ==========================================
##
## ADR-0268 dec. 12 said this screen "has no classifier" for what an ability wants to be aimed
## at. That was WRONG, and ADR-0276 corrects it: the ROM ships one, it is already extracted
## (`AbilityView.dont_hit_caster` / `_allies` / `_enemies`), already encoded to the GPU
## (`GPUAbilityLoader` -> `ABFLAG_HIT_NO_*`), and already consulted by the kernel
## (`hit_policy_allows`). It is ADR-0049's, and it is a HARD GATE: it says which aims the
## ability is FORBIDDEN to take.
##
## What it is not is an effect FAMILY. It cannot tell you that `Fire` wants a foe and `Cure` an
## ally — `Cure` legally hits an enemy (undead take it as damage), so `dont_hit_enemies` is
## false on it. Picking a PREFERENCE inside the legal set is a different question with a
## different source, and since ADR-0278 it has an answer: [AbilityFamily], consulted by
## [method seed_aim_for] INSIDE this gate and never instead of it.
##
## So this function only ever removes a row it can prove the ROM or the kernel rejects. It never
## promotes one — and `&"unknown"` (an aim whose class it cannot read, or a `Them` with no
## subject to forward to) falls through to SENSIBLE for the same reason. A grader that removed
## rows it could not reason about would shrink the screen every time the domain grew a selector,
## silently, in the direction that is hardest to notice.
static func aim_verdict(action_kind: int, ability_id: int, aim, condition_subject = null) -> StringName:
	var verdict := _aim_verdict_for_verb(action_kind, ability_id, aim, condition_subject)
	if verdict != AIM_SENSIBLE:
		# A cell that is a no-op or forbidden is BOTH of those and unnamed; the graver reading
		# wins, because it is the one that costs the player a turn rather than a word.
		return verdict
	if aim != null and aim.pool_type == TargetSelector.PoolType.TRIGGERING:
		# THE CIRCULAR PAIR FIRST, because it is the graver reading: `Them` aimed at a subject
		# that is ITSELF `Them` encodes `cond_target_type = TARGET_THEM`, which `select_target`
		# answers -1 for. See [constant AIM_NEVER_RESOLVES].
		if condition_subject != null \
				and condition_subject.pool_type == TargetSelector.PoolType.TRIGGERING:
			return AIM_NEVER_RESOLVES
		# 🔴 EVERY OTHER `Them` IS UNNAMED, AND IT DOES NOT DEPEND ON THE SUBJECT.
		#
		# This used to ask `aim_class(condition_subject) == &"caster"` — grading the cell
		# against the subject AS IT STANDS. That is the wrong moment to ask, because LANDING
		# this aim MOVES the subject: `GambitSurface`'s `To` apply re-mirrors when the subject
		# was a copy of the aim, and `mirror_of` refuses to copy a `TRIGGERING` aim and falls
		# back to the actor. The other branch is no different — with a two-row subject
		# catalogue, "not a copy of the aim" can only mean `My`, which is the actor already. So
		# BOTH paths end with the subject on the caster, and a `Them` aim is the `Self` row
		# wearing a name that hides it no matter what the column said before the press.
		#
		# The old reading therefore answered SENSIBLE for a cell whose own justification
		# expires on being accepted — the screen offered `Them` beside `Self`, and choosing it
		# produced `Self` under a word that says otherwise. #1125 opens on exactly that
		# sentence: *"`Attack / Them / Always` names its pool nowhere at all."*
		#
		# Graded after the verb, and only where the verb had no complaint, so the census still
		# counts `Move / Them` as the no-op it also is.
		return AIM_UNNAMED
	return AIM_SENSIBLE


static func _aim_verdict_for_verb(action_kind: int, ability_id: int, aim, condition_subject) -> StringName:
	var cls := aim_class(aim, condition_subject)

	# WAIT reads no target at all. `execute_gambit_action` exempts it from the
	# "no final target" bail (`final_target < 0 && action_type != ACTION_WAIT`) and its
	# `apply_pending_action` branch idles without touching a carrier, so any aim but the one
	# that means "nobody" is a column describing a field the kernel never opens.
	if action_kind == Gambit.ActionKind.WAIT:
		return AIM_SENSIBLE if cls == &"caster" else AIM_IGNORED

	# MOVE inherits the aim as its DESTINATION (`GambitEncoder` -> ACTION_MOVE_TO_UNIT). Aimed
	# at the caster, `execute_move_to_unit_gambit` reads its own tile, the adjacency check
	# `manhattan_distance(my, my) <= 1` is true on the first evaluation, and it writes
	# REASON_ARRIVED + idle. The slot COMMITS — it blocks every lower-priority slot for
	# TICKS_GAMBIT_REEVAL — and the unit has not moved.
	if action_kind == Gambit.ActionKind.MOVE:
		return AIM_NO_OP if cls == &"caster" else AIM_SENSIBLE

	# RETREAT reads the aim as the thing to move AWAY from (`GambitEncoder` ->
	# ACTION_RETREAT_STEP). Aimed at the caster it is worse than MOVE's no-op: without a
	# guard the threat tile IS the caster's own tile, `get_distance` from a cell to itself
	# is 0, and the kernel's "strictly opens distance" test then waves through any
	# neighbour at all — a step in an arbitrary direction, every evaluation, forever.
	# `retreat_step_cell` refuses `flee_from == unit_id` outright so the buffer cannot
	# reach that state, which makes the slot a guaranteed VERDICT_NO_RETREAT fall-through
	# rather than a rule. FORBIDDEN and not NO_OP: the row can never do anything.
	if action_kind == Gambit.ActionKind.RETREAT:
		return AIM_FORBIDDEN if cls == &"caster" else AIM_SENSIBLE

	if action_kind == Gambit.ActionKind.ABILITY and ability_id >= 0:
		# `get_ability_view` answers a view for an unknown id too — an EMPTY one, whose bool
		# accessors all read false. Asking `is_empty()` is what keeps a missing record from
		# reading as "the ROM permits every aim".
		var view = AbilityDatabase.get_ability_view(ability_id)
		if view != null and not view.is_empty():
			if cls == &"caster" and view.dont_hit_caster:
				return AIM_FORBIDDEN
			# AFTER the hit-policy line, never before it: see [constant AIM_UNTARGETABLE] for
			# why the 152-record overlap stays graded as ADR-0049 graded it, and why what is
			# left is exactly the four-ability gap.
			if cls == &"caster" and view.dont_target_self:
				return AIM_UNTARGETABLE
			if cls == &"ally" and view.dont_hit_allies:
				return AIM_FORBIDDEN
			if cls == &"foe" and view.dont_hit_enemies:
				return AIM_FORBIDDEN

	return AIM_SENSIBLE


## The `To` rows a slot with this verb is willing to carry — [method targets] minus every row
## [method aim_verdict] can prove broken.
##
## This is ADR-0268 dec. 8's gate ("the option lists are DERIVED from encoder support") extended
## one step: dec. 8 removed choices the ENCODER skips, and this removes choices the encoder
## accepts and the KERNEL then wastes. Both failures look identical to the player — a row that
## reads back correctly and changes nothing — which is why they belong behind one idea.
##
## Never empty for any ability in the ROM's catalogue: no record carries all three `dont_hit_*`
## flags, so at least one pool always survives. That is a fact about the data and not a
## guarantee of this code, so `GambitEncoderTest` asserts it over the whole catalogue rather
## than trusting it here.
static func targets_for(action_kind: int, ability_id: int = -1, condition_subject = null) -> Array:
	var out: Array = []
	for entry in targets():
		if aim_verdict(action_kind, ability_id, entry["make"].call(), condition_subject) == AIM_SENSIBLE:
			out.append(entry)
	return _ordered_by_family(out, action_kind, ability_id, condition_subject)


## The gated rows, put in the order the ability's own FAMILY implies (ADR-0296).
##
## A healing spell should not open with `Nearest Foe`, and a fire spell should not open with
## `Self`. The polarity that answers it is already computed — [method family_aim_name] is what
## [method seed_aim_for] consults — so this is the SAME decision expressed as an order rather
## than a second classifier. That matters: if the list were sorted by one rule and seeded by
## another, the head of the list and the default could disagree, and the player would watch the
## screen pick a row that is not the one on top.
##
## === IT REORDERS, IT NEVER ADDS OR REMOVES ==================================================
##
## Membership is [method aim_verdict]'s decision and stays [method aim_verdict]'s decision
## (ADR-0276 dec. 12). This runs strictly after the gate, on what the gate left, so no row can
## be resurrected by sorting and none can be hidden by it. `GambitEncoderTest`'s one-decision
## guard compares the offer list to the grader as a SET and is untouched by order.
##
## === `Self` RISES ONLY WHEN IT IS BOTH POSITIVE AND ACTUALLY SELF-TARGETABLE =================
##
## The player's rule: *"self should be on top if it's self targetable and positive"*. Both
## halves are already answered and neither is re-asked here.
##
## *Positive* is `is_ally_side` — `healing` and `buff`. *Self-targetable* is *whether the `Self`
## row is still in `rows` at all*: ADR-0291's gate already withheld it for the four abilities
## whose ROM record forbids the cursor landing on the caster. So `Wish` — `healing`, and
## therefore positive — never floats `Self` to the top, because `Self` is not in the list to
## float. That is the two features composing rather than a special case, and it is why this
## asks about the ROW and not about the flag.
##
## === AN UNCLASSIFIED ABILITY KEEPS [method targets]' ORDER ===================================
##
## `family_aim_name` answers `&""` for the 42 records that classify UNKNOWN and for every verb
## that has no family at all (`Move` aims at a DESTINATION, `Wait` reads no aim). Ordering them
## would be inventing a claim the classifier declined to make, so they are returned untouched —
## and that is also the control arm the test carries, because a sorter that rearranged
## everything would look identical to a correct one on the classified rows alone.
static func _ordered_by_family(rows: Array, action_kind: int, ability_id: int,
		condition_subject) -> Array:
	var polarity := aim_polarity(action_kind, ability_id)
	if polarity == &"":
		return rows
	# `caster` outranks `ally` for a positive ability; for a negative one it sinks BELOW `ally`,
	# because `Fire / Self` is a worse row than `Fire / Ally` and the list should say so.
	var rank := {&"caster": 0, &"ally": 1, &"foe": 2, &"unknown": 3} if polarity == &"Ally" \
		else {&"foe": 0, &"ally": 1, &"caster": 2, &"unknown": 3}
	# Decorated with the ORIGINAL index, so ties keep `targets()` order no matter whether
	# `sort_custom` is stable — the nearest/weakest sequence inside a block is deliberate and
	# must not shuffle.
	var decorated: Array = []
	for i in rows.size():
		var cls := aim_class(rows[i]["make"].call(), condition_subject)
		decorated.append({"i": i, "rank": int(rank.get(cls, 3)), "entry": rows[i]})
	decorated.sort_custom(func(a, b):
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["i"] < b["i"])
	var out: Array = []
	for d in decorated:
		out.append(d["entry"])
	return out


## The aim a verb brings with it when it lands on an EMPTY slot — its FAMILY's pool, gated.
##
## === THE GATE RUNS FIRST AND THE PREFERENCE RUNS INSIDE IT =================================
##
## A hit policy says *may this aim* and a family says *should it* (see [method aim_verdict] and
## [AbilityFamily]). So the order is fixed and it is the invariant: [method targets_for] removes
## every row the ROM record or the kernel can fault, and the family then picks a row from what is
## LEFT. A family that named a pool the record forbids falls back to the head of the gated list
## and never overrides it.
##
## It never has to. Across the 249 abilities any skillset row can open onto, the family's pool
## survives the gate every single time — and 59 of those records carry `dont_hit_allies` or
## `dont_hit_enemies`, so the zero is not a zero from an instrument that was not looking. That is
## the classifier's positive control and `GambitEncoderTest` asserts it rather than this file
## assuming it.
##
## === THE MAPPING IS THE PLAYER'S, AND IT IS FOUR FAMILIES ONTO TWO POOLS ====================
##
## *"damage defaults to nearest foe. healing defaults to nearest friendly. buffs default to
## nearest friendly. debuffs default to nearest enemy."* — the answer to ADR-0276's open
## question, recorded as ADR-0278 dec. 2. `damage` and `debuff` take [method foe_pool];
## `healing` and `buff` take the `Ally` row.
##
## 🔴 **THOSE WORDS NAMED A ROW THAT HAS SINCE SPLIT IN THREE, AND THE SEED KEEPS THE
## BEHAVIOUR THEY DESCRIBED (ADR-0285 dec. 4, amending ADR-0278 dec. 2).** When the player said
## "nearest friendly" the only ally row on the screen was `Nearest Ally`, and that row WAS the
## pool search — the kernel retried it at ranks 1, 2, 3…, so what they have been playing is
## *"an ally, nearest first"*. ADR-0285 gives that behaviour its honest name, `Ally`, and gives
## the name `Nearest Ally` to strict depth, which is new. Seeding the NAME would therefore have
## silently narrowed every healing and buff ability to a single candidate on the tick the
## rename landed — a behaviour change riding inside a relabel. Seeding the BEHAVIOUR keeps
## every seeded slot doing exactly what it did yesterday, and a player who wants the strict row
## picks it, which is the whole point of it being a row.
##
## 🔴 **`Ally` EXCLUDES THE CASTER, and the ally rows are not alike about it.**
## `find_unit_by_criteria` skips self on the nearest metric and only there
## (`if (mode == 0 && u == unit_id) continue;`), which is `NEAREST_FIRST` and `NEAREST_ONLY`
## alike. So the 47 abilities that move `Self` -> `Ally` here lose the caster as a target they could previously
## reach, and 15 of them are `range == 0` — centred on the caster, so the caster is the one unit
## they are ABOUT. ADR-0278 dec. 5 records this as the decision's price, names `Weakest Ally`
## (MOST_CRITICAL, which does include the caster) as the one-line alternative, and says why it
## was not taken unasked.
##
## === WHAT IS NOT SUPERSEDED ================================================================
##
## ADR-0276 dec. 10 — the seed is the head of the gated list — is NARROWED, not deleted. It is
## still the answer for `Move`, for `Wait`, and for any ability [AbilityFamily] does not rule
## (42 records, every one unreachable). A fallback that is a STATED rule rather than a silent
## `Nearest Foe` is the difference between a residual somebody can count and the defect class
## this whole ticket exists to remove.
##
## `Attack` keeps dec. 12's explicit `Nearest Foe` and still does not take its list head. Two
## reasons, both dec. 12's and both still good: `Attack` is the one unconditionally offensive
## verb, and the seeded value has to be the same object ADR-0048's safety net carries so the `To`
## column can NAME it. (Its list head would be `Self` — legal, unfaultable by the ROM because a
## basic attack carries no ability record, and obviously not what anyone means.)
##
## Returns null when the gate leaves nothing, which the catalogue never does.
static func seed_aim_for(action_kind: int, ability_id: int = -1, condition_subject = null):
	var allowed := targets_for(action_kind, ability_id, condition_subject)
	if allowed.is_empty():
		return null
	var preferred := aim_polarity(action_kind, ability_id)
	if preferred != &"":
		for entry in allowed:
			if String(entry["name"]) == String(preferred):
				return entry["make"].call()
	return allowed[0]["make"].call()


## Which side a `(verb, ability)` points at — `&"Ally"`, `&"Foe"`, or `&""` for *nothing rules
## it*. **The ONE answer both the seed and the list order read**, and it exists because they were
## briefly two (ADR-0296 dec. 6).
##
## 🔴 **`Attack` is the case that proved the duplicate.** [method seed_aim_for] hardcoded it to
## [method foe_pool] while [method _ordered_by_family] asked [method family_aim_name], which
## answers `&""` for every non-ABILITY verb — so `Attack` seeded `Foe` and OPENED ON `Self`. The
## list head and the default disagreed on the most-used verb on the screen, which is exactly what
## ADR-0296 dec. 1 says must not happen. Two gates answering one question IS the defect, so the
## fix is one gate, not a second special case.
##
## A weapon swing is foe-side without having a family: `Attack` has no ability record, so
## [AbilityFamily] has nothing to classify. That is why this is a separate question from
## [method family_aim_name] rather than a widening of it — `Move` and `Wait` must keep answering
## "no family", and they do.
static func aim_polarity(action_kind: int, ability_id: int) -> StringName:
	if action_kind == Gambit.ActionKind.ATTACK:
		return &"Foe"
	return family_aim_name(action_kind, ability_id)


## The `To` row this verb's FAMILY prefers, by name — or `&""` when nothing rules it.
##
## By NAME rather than by a built selector, for the reason [method foe_pool] is public: the
## `To` column probes [method targets] to render itself, so an aim built from a second literal
## would render as the fallback rather than as itself. Returning the name makes the seed
## literally one of the rows the list offers, which is what [method seed_aim_for] then looks up.
##
## Only ABILITY has a family. `Move` aims at a DESTINATION and `Wait` reads no aim at all
## ([method aim_verdict]), so asking what they are FOR is asking a question about the wrong axis.
static func family_aim_name(action_kind: int, ability_id: int) -> StringName:
	if action_kind != Gambit.ActionKind.ABILITY or ability_id < 0:
		return &""
	var family := AbilityFamily.of_id(ability_id)
	if family == AbilityFamily.UNKNOWN:
		return &""
	return &"Ally" if AbilityFamily.is_ally_side(family) else &"Foe"
