# Ability hit policy

**Hit policy**:
The "who-in-the-radius-actually-gets-affected" axis of an ability —
distinct from **target** (the gambit-selected unit the ability
*centers on*), distinct from the [AOE grid](39-ability-targeting.md) (the tiles
the area covers, and how they are chosen),
and distinct from **HP-write direction** (`ABFLAG_HEALING` —
whether the formula's number is added to HP or subtracted; the absorb /
undead-invert re-flip happens at apply time on top of it). FFT's canon
is **friendly fire by default**: an AOE hits every living unit in radius
regardless of team. Per-ability carve-outs come from three ROM flags on
the `ability_attributes` record:
`dont_hit_enemies` / `dont_hit_allies` / `dont_hit_caster`. Esuna has all
three false (cleanses any unit in radius — the use case that surfaced
the rule); Bio has `dont_hit_caster=true` (caster excluded from its own
poison cloud); Cure has all three false (will heal enemies caught in the
radius — the FFT-canonical friendly-fire shape).
The runtime never *infers* hit policy from animation/intent shorthand —
the old `is_ability_healing`-as-team-gate read (derived from
`target_reaction_type == "receive_heal"`, a post-hit reaction-animation
tag) was a two-step indirection that broke for Esuna (`target_reaction_type
= none`) and was retired. `ABFLAG_HEALING` survives, narrowed to its
HP-write direction job only. Forward-compatibility note: the word
"target" deliberately stays scoped to the gambit-selected unit / center
tile — tile-targeted spells (no unit target) will read the same hit
policy without needing a vocabulary change. A fourth word joined this
neighbourhood with ADR-0283 and is kept out of it on purpose:
[**condition subject**](32-formation-screen-hosting.md) is who a gambit's
CONDITION asks about (`condition_target`), never who the ability centers
on. A rule may test one unit and act on another, so the two are two terms
because they are two fields. Two WORDS as well, because a bare "subject"
is already the unit-and-equipment a capture diff masks out
([port vs oracle](35-port-vs-oracle-diffing.md)).
**Two things it also is, and one thing it is not yet** (ADR-0276):
the triple was read as a **classifier for what an ability may be aimed at**
— see **Aim policy** below, which is that classifier and is a DIFFERENT
ROM rule — and the gambit surface now reads it at
*authoring* time — `GambitOptions.aim_verdict` grades every
`(verb × aim)` cell and `targets_for` drops the rows an ability's record
forbids, which is what stopped `ThrowStone` defaulting to `Self`. It
answers *may this aim* and **never** *should it*: it is not an effect
family, so it cannot say `Fire` wants a foe and `Cure` an ally (`Cure`
legally hits an undead enemy, hence all three flags false above).
**And since ADR-0278 the third thing it is not IS answered, elsewhere.**
**Effect family** — `damage` / `healing` / `buff` / `debuff`, the
*should it* the hit policy refuses — is `AbilityFamily` in the almanac,
a `rule` and not a table because the ROM stores no family: it is
four-valued, and five routes derive it. The ROM *does* store the
ally/foe PROJECTION of it (`ai_target_allies`/`ai_target_enemies`, read
as a two-bit field at `0x8018b604`), and since ADR-0278's 2026-09-11
update those flags ship on `AbilityView` as CORROBORATION — 265/265
agreement over the 278 reachable abilities, guarded in
`GambitEncoderTest`. They are not the source: the ROM is silent on 12 of
them, so the rule is still what answers for every ability. It is a
third axis, not a refinement of either of the two above: hit policy is
*may it land there*, `ABFLAG_HEALING` is *which way the HP write goes*,
and family is *which pool should it be pointed at*. The gambit surface
consults it INSIDE the gate — `seed_aim_for` picks the family's pool
from the rows `targets_for` left standing, and a family naming a
forbidden pool falls back rather than overriding. Note the route order
deliberately re-uses `target_reaction_type == "receive_heal"` as the
FIRST route, which is the same tag this entry retires as a team gate;
that is not a contradiction, because there it answers HP-write direction
(what it is for) and it is backed by four more routes, so Esuna —
`target_reaction_type = none` — classifies `healing` off the status XOR
instead, not off the tag that broke for it before.
🔴 **And `CombatLoop.gd:2175` STILL READS A TEAM GATE OFF THIS AXIS, which
is the retired bug shape surviving in the one place nobody looked.** Its
AoE effect spray does `if is_healing and unit_team != caster_team:
continue`, which is a FAMILY question answered with an HP-write flag. On
**32** records that `effect_area > 0` branch can actually reach —
`Protect`, `Shell`, `Haste`, `Esuna`, `Carbunkle`, every Song,
`Chakra`, `StigmaMagic`, `Murasame` — the gate is inverted: it sprays
the effect on FOES and skips the caster's own party. `AbilityFamily.is_ally_side`
is the predicate that belongs there. Filed as **#1148**; not fixed inside ADR-0278,
because a behavioural change does not ride inside a classification change
(ADR-0167).
🔴 And the "who-in-the-radius" scoping in the first paragraph is
currently **literal**: `hit_policy_allows` has exactly two call sites and
both are inside AoE distribution walks gated on `effect_area > 0`, so an
ability with `effect_area == 0` takes the single-target damage path and
the policy is never consulted at all. That is **#1144**, not a design
choice — a `dont_hit_caster` ability aimed at its own caster lands.

**Aim policy**:
The *may the CURSOR land here* axis — what the ROM's target-selection
routine will let an ability be pointed AT, as opposed to hit policy's
*who in the radius gets affected once it is pointed somewhere*. One ROM
flag: `dont_target_self` (flags1 bit 0x01 on the same `ability_attributes`
record). The two are separate rules with separate enforcement points, and
ADR-0291 roots the distinction at an instruction rather than at the
FFHacktics flag names both axes are otherwise taken on: `FUN_8017A290`
@ `0x8017A290` builds the selectable-tile table at `0x80192DD8`, marks the
caster's OWN entry selectable, then tests the bit at `0x8017A444` and
zeroes that entry at `0x8017A450`. Hit policy is enforced somewhere else
entirely — the AoE distribution walk.
156 records carry it; 152 of those also carry `dont_hit_caster`, so the
cells the gambit surface could actually author are **four** — `Revive`,
`Invitation`, `Wish`, `BloodSuck` — graded `AIM_UNTARGETABLE` by
`GambitOptions.aim_verdict`. 🔴 **Surface-only**: unlike hit policy there
is no kernel counterpart to `hit_policy_allows`, and all four are
`effect_area 0`, which is the same #1144 hole named above.
A third flag the wiki names in this neighbourhood, `targeting_ai_only`,
is **inert** — BATTLE.BIN never reads the bit, proven against the other
bits of the same byte as positive controls — so there is no third axis
here and no vocabulary for one.

_Avoid_: answering a *should it* with either of the first two axes —
that is what `AbilityFamily` is for, and both of the bug shapes this
entry names are instances of it; re-conflating hit policy with HP-write
direction (the bug shape this entry retires — a spell that doesn't play a heal animation
is not therefore an enemy-targeted spell); using a per-battle
"friendly-fire toggle" in lieu of the ROM flags (a future game-design
knob can sit on top of this axis, but the per-ability data is the
authoritative ROM-derived floor); calling Esuna's carve-out "ally
targeting" (Esuna doesn't pick allies — it hits everyone, and the
cancel-mask happens to no-op on units without the named statuses);
treating hit policy and aim policy as one rule (they are enforced at two
different addresses, and a `dont_hit_caster` ability that does NOT carry
`dont_target_self` can legally be aimed at the caster's own tile — the
splash simply skips it); building a rule on `targeting_ai_only`, which
the engine never reads.
