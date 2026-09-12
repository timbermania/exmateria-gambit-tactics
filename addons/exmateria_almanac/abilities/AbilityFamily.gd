extends RefCounted

## What an ability is FOR — `damage`, `healing`, `buff` or `debuff` (ADR-0278).
##
## === THIS IS NOT THE HIT POLICY, AND THE TWO ANSWER DIFFERENT QUESTIONS =====================
##
## ADR-0049's `dont_hit_*` triple says *may this ability land on that pool*. It is the ROM's, it
## is a HARD GATE, and [method GambitOptions.aim_verdict] is where it is read. This member says
## *which pool should it be pointed at in the first place*, which the ROM does not record
## anywhere — `Cure` legally hits an enemy (an undead one takes the heal as damage), so
## `dont_hit_enemies` is false on it and the flags say nothing about `Cure` wanting an ally.
##
## So the gate runs FIRST and this preference runs INSIDE it. A family that named a pool the
## record forbids must fall back, never the other way round. It never does today — see
## [method GambitOptions.seed_aim_for] and the audit's zero-fallback assertion — but the
## ordering is the invariant and the zero is the measurement.
##
## === THE THREE ROUTES, IN ORDER ============================================================
##
## An ability is classified by the first route that answers. Over the **278** abilities any
## skillset row can open onto, the routes cover all but ONE and nothing falls through silently:
##
##   0. six abilities ruled BY NAME — see [constant ABILITY_FAMILY], and formula 42 is why.
##   1. `target_reaction_type == "receive_heal"` -> `healing`. 20 abilities, 12 of them Items.
##      This is the same field the kernel reads: `GPUAbilityLoader` encodes it to
##      `ABFLAG_HEALING` and `is_ability_healing` (`combat_common.glslinc`) is the predicate.
##      Taken ahead of the rest so the host and the kernel cannot disagree about what a heal is.
##   2. a non-empty `inflict_statuses` -> the XOR below.       114 abilities.
##   3. the `formula`, ruled in [constant FORMULA_FAMILY].     121 abilities.
##   4. the `ability_type`, for the 16 Throw and Jump records that carry no formula at all —
##      [constant TYPE_FAMILY].
##
## The one left is `Move-GetJp`, and [constant TYPE_FAMILY] says why it SHOULD be left.
##
## === ROUTE 2 IS AN XOR, AND `inflict_mode` ALONE IS A TRAP ==================================
##
## `cancel` does NOT mean "helpful". `Esuna` cancels an ally's ailments; `DispelMagic` cancels a
## FOE's buffs. Both are `cancel`. The direction needs the mode AND the polarity of the statuses:
##
##     inflicts & good -> buff      cancel & good -> debuff   (strip a foe's buffs)
##     inflicts & bad  -> debuff    cancel & bad  -> healing  (cleanse an ally)
##
## [b]`inflicts` is `mode != "cancel"`, NOT `mode == "all"`.[/b] The field has FOUR values and
## `random` and `separate` are inflict modes too — 17 reachable abilities carry one. Spelling the
## test as `mode == "all"` inverts every one of them, and it inverts in BOTH directions:
## `StasisSword` (separate, bad) would read `healing` and `NamelessSong` (random, good) would
## read `debuff`. `StasisSword` is the one that reaches the player, because its record does not
## carry `dont_hit_allies` and so the gate leaves `Nearest Ally` standing for the seed to land
## on — a Holy Knight's Stop-sword aimed at a friend. Both are asserted by name in
## `GambitEncoderTest`.
##
## === THE POLARITY TABLE IS MOSTLY THE ROM'S OWN, AND THAT IS THE POINT ======================
##
## 23 of the 30 statuses named anywhere in the catalogue are ruled by the ROM rather than by us,
## because the ROM ships two `cancel` sets that partition them and the two do not overlap:
##
##   `Despair` / `Despair2` / `DispelMagic` cancel {Transparent, Reraise, Float, Haste, Shell,
##     Protect, Regen, Reflect, Faith} — a dispel, so every member is GOOD.
##   `Esuna` / `StigmaMagic` / `Deathspell2` / `DragonCare` / `Raise` / `Revive` / `Heal` cancel
##     {Berserk, BloodSuck, Confusion, Darkness, Dead, DontAct, DontMove, Frog, Oil, Petrify,
##     Poison, Silence, Sleep, Stop} — a cleanse, so every member is BAD.
##
## That settles five of the calls a reader would otherwise argue about: `Faith` and `Transparent`
## are good because the ROM's own dispel list holds them, and `Berserk`, `Oil` and `BloodSuck`
## are bad because its cleanse list does. [b]Seven are OURS[/b] — `Charm`, `Crystal`,
## `DeathSentence`, `Innocent`, `Invite`, `Slow`, `Undead` — and all seven are ruled BAD. Five of
## the seven are corroborated by the gate: every reachable record inflicting `Charm` or `Invite`
## carries `dont_hit_allies`, which is the ROM saying "not at a friend" in the one vocabulary it
## has. They are marked in the table so a reader can falsify ours without re-deriving the ROM's.
##
## Keyed on the EXTRACTION's status spelling (`Darkness`, `DontAct`), which is not
## `StatusRegistry`'s (`blind`, `disable`) and not a subset of it — `DeathSentence`, `Charm`,
## `Reflect`, `Innocent` and `Crystal` have no `STATUS_` bit at all. A polarity row is a claim
## about what the RECORD says the ability does, so a status whose bit is hollow (13 of the 32 are
## declaration-only) makes the ability inert, not the classification wrong.
##
## === WHAT THIS DOES NOT CLASSIFY ===========================================================
##
## 42 records carry a formula this member does not rule, and [b]every one of them is unreachable
## — no skillset row opens onto any of them.[/b] They are the monster attack formulas (f1's
## sixteen `Bite` / `Scratch` / `Tentacle` rows), a handful of monster specials, and six records
## literally named `(Nothing)`. Ruling them would be inventing rulings for records the surface
## cannot offer, so they return [constant UNKNOWN] and `seed_aim_for` falls back to ADR-0276
## dec. 10's head-of-the-gated-list — which is why that decision is NARROWED here rather than
## deleted. The audit asserts the REACHABLE unknown count is zero and ratchets the other.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH.
const _Self = preload("res://addons/exmateria_almanac/abilities/AbilityFamily.gd")
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")

## Reduces the target's HP or a resource it holds.
const DAMAGE := &"damage"
## Restores an ally's HP, or removes what is wrong with them.
const HEALING := &"healing"
## Grants a good status, or raises a stat.
const BUFF := &"buff"
## Inflicts a bad status, strips a good one, or lowers a stat.
const DEBUFF := &"debuff"
## No ruling. NOT a family — the caller must have its own answer for this.
const UNKNOWN := &""


## The nine statuses the ROM's own dispel (`Despair` / `DispelMagic`) removes.
const GOOD_STATUSES: Array[String] = [
	"Faith", "Float", "Haste", "Protect", "Reflect", "Regen", "Reraise", "Shell", "Transparent",
]

## The fourteen the ROM's own cleanse (`Esuna` / `StigmaMagic` / …) removes, then the seven this
## file rules. The split is kept visible because the first fourteen are falsifiable against the
## catalogue and the last seven are only falsifiable against a reader's judgement.
const BAD_STATUSES: Array[String] = [
	# --- ruled by the ROM's cleanse sets ---
	"Berserk", "BloodSuck", "Confusion", "Darkness", "Dead", "DontAct", "DontMove", "Frog",
	"Oil", "Petrify", "Poison", "Silence", "Sleep", "Stop",
	# --- OURS. `Charm` and `Invite` take control of the unit away from its owner and every
	#     record inflicting either carries `dont_hit_allies`; `Crystal` and `DeathSentence` end
	#     it; `Innocent` severs it from friendly magic; `Slow` and `Undead` are FFT canon and
	#     `Slow` is cancelled by nothing in the catalogue, which is why the ROM did not rule it.
	"Charm", "Crystal", "DeathSentence", "Innocent", "Invite", "Slow", "Undead",
]


## Route 3 — the ruling for every formula a reachable ability carries that routes 1 and 2 miss.
## 43 formulas, 121 abilities. Absent = [constant UNKNOWN], never a silent default: #424's rule
## that a list which may only shrink needs both arms, and the audit holds both.
const FORMULA_FAMILY: Dictionary = {
	# --- damage: it takes HP, MP or Gil off the target -------------------------------------
	8: DAMAGE,    # elemental + Ultima + every summon (33)
	9: DAMAGE,    # Demi / Demi2 / Lich — fraction of current HP
	15: DAMAGE,   # SpellAbsorb / Aspel — drains MP
	16: DAMAGE,   # LifeDrain / Drain
	21: DAMAGE,   # Return2
	23: DAMAGE,   # Gravi2
	30: DAMAGE,   # Holy Sword / Bracelet (6)
	31: DAMAGE,   # the "…Back" variants (5)
	32: DAMAGE,   # Draw Out, damage-all-enemies (4)
	33: DAMAGE,   # BizenBoat — drains MP
	47: DAMAGE,   # DarkSword
	48: DAMAGE,   # NightSword
	49: DAMAGE,   # SpinFist / WaveFist / EarthSlash
	50: DAMAGE,   # RepeatingFist
	55: DAMAGE,   # Dash / ThrowStone
	67: DAMAGE,   # Shock / Shock!
	68: DAMAGE,   # Difference
	78: DAMAGE,   # the elemental Bracelets
	# --- debuff: it takes something OTHER than HP off the target ---------------------------
	22: DEBUFF,   # Mute
	26: DEBUFF,   # SpeedRuin / PowerRuin / MindRuin
	27: DEBUFF,   # MagicRuin
	29: DEBUFF,   # the Dances (6) — every one carries `dont_hit_allies`
	37: DEBUFF,   # HeadBreak / ArmorBreak / ShieldBreak / WeaponBreak
	38: DEBUFF,   # Steal* (5)
	39: DEBUFF,   # GilTaking
	40: DEBUFF,   # StealExp
	43: DEBUFF,   # SpeedBreak / PowerBreak / MindBreak
	44: DEBUFF,   # MagicBreak
	46: DEBUFF,   # ShellbustStab / BlastarPunch / HellcryPunch / IcewolfBite
	97: DEBUFF,   # Foxbird / Chicken — Brave down
	# --- healing: it gives HP back, or takes harm away -------------------------------------
	35: HEALING,  # Murasame — the ally-side Draw Out. `dont_hit_enemies` corroborates.
	52: HEALING,  # Chakra — HP + MP to the caster and its neighbours
	60: HEALING,  # Wish — spends the caster's own HP to heal the target
	# --- buff: it raises something ---------------------------------------------------------
	18: BUFF,     # Quick — hands the target its turn back
	20: BUFF,     # Golem — the party's physical shield
	28: BUFF,     # the Songs (6) — every one carries `dont_hit_enemies`
	54: BUFF,     # Accumulate
	57: BUFF,     # Yell
	58: BUFF,     # CheerUp
	59: BUFF,     # Scream
	92: BUFF,     # DragonPowerUp
	93: BUFF,     # DragonLevelUp
}


## The per-ABILITY overrides, and formula 42 is the whole reason they exist.
##
## Talk Skill holds both directions under one formula with no field that separates them: `Praise`
## and `Threaten` are both f42, both `taking_damage`, both carry no statuses, and they move the
## target's Brave in opposite directions. The ROM records the MAGNITUDE and not the sign —
## `Praise` and `Preach` are both `(x=50, y=4)` and `Threaten` and `Solution` are both
## `(x=90, y=20)`, which is the catalogue corroborating the pairing and still not naming the
## direction. So these six are rulings, and they are spelled per ability because that is the
## granularity the evidence has. The other four f42 abilities carry statuses and route 2 answers
## them.
##
## ⚠ Our kernel's f42 branch (`combat_combat.glslinc:346`) is the status-inflict path, so these
## six do nothing today. The ruling is about where the `To` column POINTS, which is a question
## the screen asks whether or not the effect lands.
const ABILITY_FAMILY: Dictionary = {
	117: DEBUFF,  # Persuade  — ruled with the rest of Talk Skill's y=0 enemy-facing half
	118: BUFF,    # Praise    — Brave +4
	119: DEBUFF,  # Threaten  — Brave -20
	120: BUFF,    # Preach    — Faith +4
	121: DEBUFF,  # Solution  — Faith -20
	123: DEBUFF,  # Negotiate — takes Gil. `dont_hit_allies` corroborates.
}


## Route 4 — the ruling for the ability TYPES whose records carry no `formula` at all.
##
## 29 of the 278 reachable abilities have no `formula` key, so routes 2 and 3 cannot see them and
## nothing below `ability_type` distinguishes one from another. They fall in four groups and only
## two need a row here:
##
##   `Item` (12)     — every reachable one is `receive_heal`, so ROUTE 1 answers them. A row here
##                     would be a ruling with no subject, and the `Item` skillset holds no
##                     offensive item to give it one.
##   `Throwing` (8)  — Ninja Throw. The record IS the thrown weapon (`Shuriken`, `KnightSword`),
##                     and its `shield_block` reaction is the ROM saying the target defends.
##   `Jumping` (8)   — Lancer Jump. `evade` reaction, same reading.
##   `Movement` (1)  — `Move-GetJp`, and it is NOT an action. A movement support ability earns JP
##                     by walking; it lands on nobody, and it is in a skillset's `actions` list
##                     rather than its `rsm` list, which is where a gambit surface can reach it.
##                     There is no pool to prefer, so it is [constant UNKNOWN] by the same rule
##                     that makes `Move` and `Wait` have no family, and the audit names it.
const TYPE_FAMILY: Dictionary = {
	"Throwing": DAMAGE,
	"Jumping": DAMAGE,
}


## The family of one ability id. [constant UNKNOWN] when nothing rules it.
static func of_id(ability_id: int) -> StringName:
	return of_view(AbilityDatabase.get_ability_view(ability_id))


## The family of one [AbilityView]. The routes are tried in the order the class docstring gives
## and the FIRST one to answer wins; an empty view is [constant UNKNOWN] rather than a guess.
static func of_view(view) -> StringName:
	if view == null or view.is_empty():
		return UNKNOWN

	# Route 0 — the named overrides, ahead of everything, because formula 42 holds both
	# directions and route 3 would have to pick one for all of them.
	if ABILITY_FAMILY.has(view.ability_id):
		return ABILITY_FAMILY[view.ability_id]

	# Route 1 — the field the KERNEL reads. `Raise` is `receive_heal` AND carries a `cancel` of
	# `Dead`, so it would answer route 2 as well; both say `healing` and this one says it in the
	# same vocabulary `ABFLAG_HEALING` uses.
	if view.target_reaction_type == "receive_heal":
		return HEALING

	# Route 2 — the XOR over (mode, polarity).
	var statuses: Array = view.inflict_statuses
	if not statuses.is_empty():
		var polarity := status_polarity(String(statuses[0]))
		if polarity != 0:
			var good := polarity > 0
			# `random` and `separate` INFLICT. Only `cancel` removes.
			var inflicts: bool = String(view.inflict_mode if view.inflict_mode != null else "") != "cancel"
			if inflicts:
				return BUFF if good else DEBUFF
			return DEBUFF if good else HEALING

	# Route 3 — the formula. `has("formula")` rather than the accessor's typed 0, because
	# formula 0 is a real (and unruled) value and 29 reachable records carry no formula at all.
	if view.has("formula") and FORMULA_FAMILY.has(view.formula):
		return FORMULA_FAMILY[view.formula]

	# Route 4 — the ability TYPE, for the records with no formula to read.
	if TYPE_FAMILY.has(view.ability_type):
		return TYPE_FAMILY[view.ability_type]
	return UNKNOWN


## `+1` good, `-1` bad, `0` for a status no row rules.
##
## Reads the FIRST status of a set as the set's polarity, which is only sound because no record
## in the catalogue mixes the two — asserted over every record by `GambitEncoderTest`, because a
## mixed set would make the XOR pick a side by array order and nothing would say so.
static func status_polarity(status_name: String) -> int:
	if GOOD_STATUSES.has(status_name):
		return 1
	if BAD_STATUSES.has(status_name):
		return -1
	return 0


## True when this family wants to be pointed at the caster's own side.
##
## The four families collapse onto two pools, and that is the shape of the player's decision
## rather than a shortcut in the code: *"damage defaults to nearest foe. healing defaults to
## nearest friendly. buffs default to nearest friendly. debuffs default to nearest enemy."*
## [constant UNKNOWN] is neither, which is why this returns a bool and the caller must ask
## [method of_view] first.
static func is_ally_side(family: StringName) -> bool:
	return family == HEALING or family == BUFF
