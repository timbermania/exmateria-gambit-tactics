# The seed is the family's pool, and the family is OURS because the ROM records a hit policy and not a purpose

[ADR-0276](0276-a-sensible-default-is-the-aim-the-rom-cannot-fault-and-the-preference-is-still-open.md)
ended on a question it refused to answer:

> *"is it a damage spell? a healing spell? a buff? a debuff? something else?"*

It shipped the half the ROM could settle — a hard gate that removes every aim an ability's own
record or the kernel can be shown to reject — and left the other half open on purpose, because
*"The vocabulary is a player-facing concept and the wrong one is expensive to unpick"*. The
player has now answered it:

> *"a second level optimization beyond hit policy. damage defaults to nearest foe. healing
> defaults to nearest friendly. buffs default to nearest friendly. debuffs default to nearest
> enemy."*

This ADR is that answer built. The mapping above is not re-litigated here. What IS decided here
is how an ability is classified into one of the four, where that classifier lives, what happens
to the abilities it cannot classify, and — dec. 8 — what the decision costs, which is a real
cost and is not zero.

## Status

accepted

**Supersedes [ADR-0276](0276-a-sensible-default-is-the-aim-the-rom-cannot-fault-and-the-preference-is-still-open.md)
dec. 10 by NARROWING it**, and dec. 10's argument is the thing that changes, not just its
outcome — see dec. 3. Discharges that ADR's "What is not decided" first entry; its SECOND entry
(`range == 0`) is still not decided and dec. 8 says why it now matters more than it did.
Consumes [ADR-0049](0049-ability-hit-policy-is-rom-flag-derived.md)'s triple as the gate this
preference runs inside, keeps
[ADR-0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md)
dec. 8's derived-option-list rule and dec. 12's explicit `Attack` seed untouched, and declares
its new member under
[ADR-0273](0273-free-ness-inside-the-rules-tier-is-declared-per-member-because-a-package-of-tables-is-not-all-tables.md)
dec. 1. Builds the rest of **#1125 (b)**; the (c) half — `If` two levels deep — is still
untouched. **#1144** (the single-target hit-policy hole) is not a blocker and is not fixed here.

## Decision

### The rule

**1. The seed onto an empty ability slot is the ability's FAMILY's pool.** Four families, two
pools, and the collapse is the player's own sentence rather than a shortcut in the code:

| family | what it is | pool |
|---|---|---|
| `damage` | takes HP, MP or Gil off the target | `Nearest Foe` |
| `debuff` | takes something other than HP off it — a status, a stat, a piece of equipment | `Nearest Foe` |
| `healing` | gives HP back, or takes harm away | `Nearest Ally` |
| `buff` | grants a good status, or raises a stat | `Nearest Ally` |

Four names for two answers is deliberate. The seed needs two; the AUDIT needs four, because a
classifier that booked every ability as `damage` satisfies "every seed matches its family"
perfectly and only a per-family count can see it (dec. 12). Measured on this tree, over the 278
abilities any skillset row can open onto: **88 damage / 126 debuff / 29 healing / 34 buff**.

**2. 🔴 THE GATE RUNS FIRST AND THE PREFERENCE RUNS INSIDE IT, AND THAT ORDER IS THE
INVARIANT.** A hit policy says *may this aim*; a family says *should it*. ADR-0276 dec. 4's
`dont_hit_*` triple is the ROM's and it is hard; this is ours and it is soft. So
`GambitOptions.targets_for` removes every row it can prove broken, and the family then picks a
row **from what is left**. A family that names a pool the record forbids falls back to the head
of the gated list and never overrides it.

It never has to, and the zero is the classifier's positive control rather than a convenience:
across all 278, the family's pool survives the gate **every single time** — and 59 of those
records carry `dont_hit_allies` or `dont_hit_enemies`, so the gate had 59 chances to contradict
a ruling and took none. A fallback here would not be a crash; it would be a ruling the ROM
disagrees with, which is a reason to re-read the ruling. `GambitEncoderTest` asserts the zero
and prints the names if it ever moves.

**3. ADR-0276 dec. 10 IS NARROWED, NOT DELETED — AND ITS ARGUMENT IS WHAT CHANGES.** Dec. 10's
whole case for the head-of-the-gated-list was that it *"involves no new opinion at all."* That
was right, and it is exactly what is being given up: a family preference IS a new opinion. The
justification moves from "no guess" to "a guess the player authorised, derived from the ROM's
own fields", and [ADR-0023](0023-gambit-gpu-projection-stays-in-encoder-faithful-or-explicit.md)'s
faithful-or-explicit rule is why that is written here rather than absorbed quietly.

Dec. 10 survives as the answer everywhere the family has nothing to say, which is three places
and all three are principled:

- **`Move`** — its aim is a DESTINATION. Asking what a destination is FOR is the wrong axis, and
  a family that answered would re-seed dec. 3's no-op through the preference instead of through
  the head.
- **`Wait`** — the kernel never reads its aim at all (dec. 8 of ADR-0276).
- **an ability with no family** — one reachable ability, named in dec. 11.

`Attack` keeps ADR-0268 dec. 12's explicit `Nearest Foe` and still does not take its list head,
for dec. 12's two reasons, both still good.

### The classifier

**4. THE FAMILY IS READ OFF FIVE ROUTES AND THE ORDER OF THE ROUTES IS THE DECISION.** The first
route to answer wins. `AbilityFamily.of_view` is the whole implementation:

| # | route | n | why it is where it is |
|---|---|---:|---|
| 0 | six abilities ruled BY NAME | 6 | formula 42 holds both directions at once; dec. 6 |
| 1 | `target_reaction_type == "receive_heal"` | 20 | the field the KERNEL reads, so host and GPU cannot disagree about what a heal is |
| 2 | a non-empty `inflict_statuses` → the XOR | 114 | decs. 5 and 6, below |
| 3 | the `formula` | 121 | 43 formulas, a bank of rulings |
| 4 | the `ability_type` | 16 | the Throw and Jump records carry no `formula` at all |

Route 1 sits ahead of route 2 rather than beside it because `Raise` answers BOTH — it is
`receive_heal` and it carries a `cancel` of `Dead` — and taking the kernel's own field first is
what keeps `AbilityDatabase.is_healing`, `ABFLAG_HEALING` and this member one answer instead of
three (dec. 10).

⚠ **`receive_heal` is the tag `docs/context/07-ability-hit-policy.md` retires as a team gate, and
using it here is not that mistake.** That entry's argument is that the tag is a post-hit
reaction-animation flag narrowed to HP-WRITE DIRECTION, so reading "hits allies" off it is a
two-step indirection — and its worked counterexample is `Esuna`, whose `target_reaction_type` is
`none`. Here the tag answers the question it is actually about (this ability adds to HP, so it is
a heal), it is never the only route, and `Esuna` classifies `healing` off route 2's XOR. A
one-route classifier resting on it would be the retired shape; a five-route one whose first route
is provably sufficient-but-not-necessary is not.

**5. ROUTE 2 IS AN XOR OVER (mode, polarity), AND `inflict_mode` ALONE IS A TRAP.** `cancel`
does not mean "helpful": `Esuna` cancels an ally's ailments and `DispelMagic` cancels a **foe's
buffs**, and both are `cancel`. So:

```
inflicts & good -> buff       cancel & good -> debuff    (strip a foe's buffs)
inflicts & bad  -> debuff     cancel & bad  -> healing   (cleanse an ally)
```

🔴 **`inflicts` is `mode != "cancel"`, and spelling it `mode == "all"` inverts seventeen
records.** The field has FOUR values — `all` (88), `cancel` (11), `separate` (11), `random` (6)
— and `random` and `separate` inflict exactly as `all` does. The mis-spelling is wrong in BOTH
directions, and one direction reaches the player: `StasisSword` is `separate` + `Stop`, its
record carries **no** `dont_hit_allies`, so a family of `buff` survives the gate and seeds
`Nearest Ally` — a Holy Knight's Stop-sword aimed at a friend. The other direction
(`NamelessSong`, `random` + good) is masked by `dont_hit_enemies`, which is why a single witness
would not have been enough. Both are asserted by name.

**6. 23 OF THE 30 STATUS POLARITIES ARE THE ROM'S OWN, AND THE SEVEN THAT ARE OURS SAY SO.**
The catalogue ships two `cancel` sets that partition most of the vocabulary and do not overlap:

- `Despair` / `Despair2` / `DispelMagic` cancel `{Transparent, Reraise, Float, Haste, Shell,
  Protect, Regen, Reflect, Faith}` — a **dispel**, so every member is GOOD.
- `Esuna` / `StigmaMagic` / `Deathspell2` / `DragonCare` / `Raise` / `Revive` / `Heal` cancel
  `{Berserk, BloodSuck, Confusion, Darkness, Dead, DontAct, DontMove, Frog, Oil, Petrify,
  Poison, Silence, Sleep, Stop}` — a **cleanse**, so every member is BAD.

That settles five of the calls a reader would otherwise argue about — `Faith` and `Transparent`
are good because the ROM's own dispel list holds them, `Berserk`, `Oil` and `BloodSuck` are bad
because its cleanse list does. **Seven are ours**: `Charm`, `Crystal`, `DeathSentence`,
`Innocent`, `Invite`, `Slow`, `Undead`, all ruled BAD, and five of the seven corroborated by the
gate (every record inflicting `Charm` or `Invite` carries `dont_hit_allies`, which is the ROM
saying "not at a friend" in the one vocabulary it has). They are marked in the table so a reader
can falsify ours without re-deriving the ROM's.

The table reads `statuses[0]` as a set's polarity. That is only sound because **no record in the
catalogue mixes good and bad**, which is a fact about the data and is asserted over every record
rather than assumed — a mixed set would make the family depend on array order and nothing would
say so.

**7. FORMULA 42 IS WHY THERE IS A PER-ABILITY ROUTE AT ALL.** ADR-0276 already found that
`formula` alone cannot separate buff from debuff, and named formula 56 (`Heal` and `Seal`) as
the case. Route 2 answers that one. Formula 42 is the case route 2 CANNOT answer: Talk Skill's
`Praise` and `Threaten` are both f42, both `taking_damage`, both carry no statuses at all, and
they move the target's Brave in opposite directions. **The ROM records the magnitude and not the
sign** — `Praise` and `Preach` are both `(x=50, y=4)` and `Threaten` and `Solution` are both
`(x=90, y=20)`, which is the catalogue corroborating the pairing and still not naming the
direction. So six abilities are ruled individually, and the granularity is the granularity the
evidence has. (Our kernel's f42 branch is the status-inflict path, so these six do nothing today
— the ruling is about where the `To` column POINTS, which the screen asks whether or not the
effect lands.)

### The price, the home, and the residual

**8. 🔴 `Nearest Ally` EXCLUDES THE CASTER, AND THIS DECISION MAKES 47 ABILITIES WORSE FOR IT.**
`find_unit_by_criteria` skips self on NEAREST and **only** on NEAREST
(`if (mode == 0 && u == unit_id) continue;`, `stage_compute.glsl:247`) — ADR-0276 dec. 6 records
the asymmetry and this is it collected on. Today `Cure` seeds `Self`, which is the head of its
gated list and is the right thing for a lone wounded healer. After this ADR it seeds
`Nearest Ally`, which **can never resolve onto the caster**, so that healer heals nobody.

Forty-seven reachable abilities move `Self → Nearest Ally`, and every one of them loses the
caster as a reachable target. **Fifteen carry `range == 0`** — centred on the caster, so the
caster is the unit they are ABOUT — and two of those fifteen, `Accumulate` and `Scream`, are
`range 0 / effect_area 0`: they affect the caster and nobody else. `Accumulate / Nearest Ally`
raises somebody else's PA. That is visible on a capture and it is worse than what shipped.

**The player said "nearest" four times, so `Nearest Ally` is what is built.** The alternative is
one line and it is recorded in "Considered options" rather than taken unasked, because the
vocabulary is theirs and ADR-0276's own reason for asking rather than inferring has not expired.
What is NOT deferred is the measurement: the 47 and the 15 are here so the question can be
answered from numbers instead of from a hunch.

This is also where ADR-0276's second open item stops being independent. `range == 0` was left
ungraded there because grading it needs a rule-group-K scenario and not a static reading; it is
still ungraded, and this decision now points fifteen range-0 abilities at a unit they may never
be in range of. **The overlap is real and it is not closed here.**

**9. THE CLASSIFIER IS AN ALMANAC MEMBER AND IT IS A `rule`.** `AbilityFamily` lives at
`addons/exmateria_almanac/abilities/AbilityFamily.gd`, published by the façade, declared `rule`
in `MEMBER_KINDS`. Three arguments and they agree:

- It is a fact about an ABILITY, not about a screen. `Fire` is damage whether or not the gambit
  surface exists, and the two predicates it reconciles (dec. 10) live in the addon and in the
  shader — a host-side home could not have reconciled either.
- It COMPUTES. Nothing in the ROM stores a family; five routes derive one. ADR-0273 dec. 1's
  vocabulary calls that a driver. ⚠️ The ROM **does** store the family's ally/foe PROJECTION, and
  the Update below roots that in a decompile rather than leaving it a premise — but a family is
  four-valued where the projection is two-valued, and the ROM is silent on 12 reachable
  abilities, so the routes remain the only thing that answers for *every* ability. The `rule`
  declaration stands; what changes is that one axis of its output is now corroborated.
- ADR-0273 dec. 5's tie-break points the same way and costs nothing here: the member has no
  sibling-addon namer, so arm 5 reads **36 debt lines either way**, measured under the
  declaration rather than assumed. The live register moves 32 → 33 published and 11 → 12 rules.

It cannot live in `AbilityDatabase.gd`, which is AUTO-GENERATED and would eat the table on the
next `generate_ability_database.py` run.

**10. THE THREE CONTRADICTORY PREDICATES ARE RECONCILED BY DELETION AND REALIGNMENT, NOT BY A
FOURTH.** ADR-0276 named them and said reconciling them was the price of building this:

- **`AbilityDatabase.is_damage` is DELETED.** It listed formula 10 as damage while
  `NON_DAMAGE_FORMULAS`, two lines below it in the same file, listed 10 as not-damage — one file
  contradicting itself — and it had **zero callers**, so nothing was reading either answer.
- **`AbilityDatabase.is_healing` now reads `target_reaction_type == "receive_heal"`**, the same
  field `GPUAbilityLoader` encodes to `ABFLAG_HEALING` and `is_ability_healing` reads. It was
  `formula == 12`, which disagreed with the kernel on **sixteen** records — `Raise` / `Raise2`
  are formula 13, and the fourteen `Item` records carry no `formula` key at all, so the old
  predicate read 0 and called every potion not-a-heal. **The realignment changes no behaviour
  today, and that was measured rather than asserted**: its one caller (`CombatLoop.gd`'s AoE
  effect spray) is inside an `effect_area > 0` branch and not one of the sixteen has a non-zero
  `effect_area`. The disagreement was real in the predicate and unreachable at the call site.

Both edits land in `tools/generate_ability_database.py` as well as in the generated file, or the
next regeneration undoes them.

🔴 **FOUND WHILE RECONCILING THEM: `is_healing`'s ONE CALLER IS THE BUG SHAPE
`docs/context/07-ability-hit-policy.md` ALREADY RETIRED, SURVIVING WHERE NOBODY LOOKED.** That
entry records the `is_ability_healing`-as-team-gate read being taken out of the kernel, and
`CombatLoop.gd:2175` still does exactly it — `if is_healing and unit_team != caster_team:
continue` is a FAMILY question answered with an HP-write flag. Measured over the 193 records
whose shape that `effect_area > 0` branch can actually reach, the gate disagrees with
`is_ally_side` on **32**: `Protect`, `Shell`, `Haste`, `Esuna`, `Carbunkle`, `Murasame`,
`Kiyomori`, `Masamune`, every Song, `Chakra`, `StigmaMagic` and eleven more all spray their AoE
effect on FOES and skip the caster's own party. It is reachable and it is visible.

**It is NOT fixed here**, and the realignment above deliberately does not fix it either: swapping
the predicate for `AbilityFamily.is_ally_side` changes what the screen draws, and a behavioural
change does not ride inside a classification change
([ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)).
Filed as **#1148**, with the 32 as its subject.

**11. THE RESIDUAL IS ONE REACHABLE ABILITY AND IT IS NAMED, NOT COUNTED.** `Move-GetJp` is a
MOVEMENT support ability sitting in a skillset's `actions` list. It lands on nobody, so there is
no pool to prefer, and dec. 3's fallback is the right answer for exactly the reason it is right
for `Wait`. It is in a one-entry allowlist in the audit with **both arms** (#424): an unexpected
name reds, and a name that has since learned to classify also reds.

The other residual is 42 records that carry a formula nothing rules, and **every one is
unreachable** — the monster attack formulas (f1's sixteen `Bite` / `Scratch` / `Tentacle` rows),
a handful of monster specials, and six records literally named `(Nothing)`. They return
`UNKNOWN`. Ruling them would mean inventing rulings for records no skillset row can open onto,
which is guessing dressed as coverage. The audit RATCHETS the number rather than tolerating it.

### The audit

**12. THE AUDIT IS FIVE ASSERTIONS THAT A COUNT CANNOT MAKE, AND IT IS PROVED BY MUTATION.**
It rides in `GambitEncoderTest` beside ADR-0276's cell audit — an existing GPU-free process,
per `docs/TEST-CHARTER.md` clause 13 — and it prints its subject before it asserts anything.

- **Coverage with no silent default.** Every reachable ability classifies; the exemption is one
  NAME, both arms.
- **Per-family counts, each asserted non-zero.** Without this, a classifier collapsing onto one
  family passes every other assertion in the file.
- **The traps by name.** `Chakra`, `Accumulate`, `Yell`, `CheerUp`, `Wish` and `Scream` are all
  `taking_damage` with an empty status list, and a rule reading the reaction type books every
  one of them as damage. `ThrowStone` is the control — it reads the same way and IS damage, so
  an `is_ally_side` that returned true unconditionally cannot pass.
- **Both directions of the XOR, twice.** `Esuna` / `DispelMagic` for the polarity, `StasisSword`
  / `NamelessSong` for the mode spelling — plus a check that the catalogue actually HOLDS a
  `random`/`separate` record, or the second pair would be drawing a distinction the data does
  not and would read as a clean pass.
- **Zero fallbacks**, which is dec. 2's positive control.

🔴 **Six mutations were run and each reds where predicted**, because a green audit reads the
same whether it consults the register or ignores it:

| mutation | reds |
|---|---|
| XOR spelled `mode == "all"` | `StasisSword` FOE→healing, `NamelessSong` ALLY→debuff, 6 fallbacks |
| `is_ally_side` returns false | all six named traps |
| drop the `Faith` polarity row | the coverage arm, on six records naming it |
| `seed_aim_for` reverted to the gated head | 462 seeds off their family's pool |
| every formula rules `DAMAGE` | the six named traps — **and NOT the per-family counts**, which stay 137/26/20/94 |
| `TYPE_FAMILY` emptied | 16 reachable abilities unclassified, by name |

The fifth row is the finding. A per-family census is a real control and it is **not sufficient**:
the named witnesses are the only thing that caught a classifier that had stopped reading its own
table. `GambitEncoderTest` already carried the sentence that says why, in the comment above its
named cells:

> *"a census counts and does not identify"*

⚠ That is the TEST's line and **not** an ADR's — it was written when ADR-0276 landed, and that
ADR argues the same thing in its consequences without those words. Cited to the file rather than
to the decision, because a paraphrase and a quotation are indistinguishable once the quotation
marks are on.

## Update — 2026-09-11: the ROM stores the ally/foe axis, and the classifier STAYS

Status: accepted. Supersedes no decision. dec. 9's `rule` declaration and every route in dec. 1-8
are unchanged; what changes is the PROVENANCE of one axis, and a premise this ADR asserted without
a decompile behind it. Issue #1227, opened by ADR-0296 dec. 5.

**The premise, corrected precisely.** dec. 9 reads *"nothing in the ROM stores a family"*, and
`docs/context/07-ability-hit-policy.md` quoted it as *"a `rule` and not a table because nothing in
the ROM stores it"*. The first sentence is still true. The second was too strong: the ROM stores
the **ally/foe projection** of the family, in the AI block of the 8-byte ability record at SCUS
`0x8005EBF0`, and BATTLE.BIN reads it as a **two-bit field**:

    0x8018b5e8  lui   v0,0x8006
    0x8018b5ec  addiu v0,v0,-0x1410   ; -> 0x8005EBF0
    0x8018b5f0  sll   v1,v1,0x3       ; the 8-byte stride
    0x8018b5f8  lbu   v0,0x4(v1)      ; AI Flags 1
    0x8018b604  andi  v0,v0,0x3       ; ai_target_allies | ai_target_enemies, TOGETHER
    0x8018b608  sb    v0,0x18(a0)     ; into the AI's working struct at [DAT_80192d90]

Rooted by ADR-0291 dec. 1's closed enumeration rather than by the FFHacktics name, because
ADR-0291 dec. 5 is what a name is worth here. Three seeds form a pointer into that table across
both binaries and every read is accounted for: this one, byte +7 `andi 0x1` at the same site, byte
+3 `andi 0x20` (`learn_on_hit`) and +2 at `0x8018e708`, and bytes +0/+1 (`jp_cost`, against the
unit's JP) and +2 at SCUS `0x8005cfc0` — the JP-spend path. Alternate encodings of the base are
absent (`ori`/`addiu` of `0xebf0`: zero sites).

**The positive control is the DISCARD.** Byte +4 carries eight bits and six of them — `ai_hp`
0x80 through `ai_unequip` 0x04 — do not survive `andi 0x3`. Byte +7 is read at the same site with
a *different* mask, so the code extracts other bits when it wants them. A whole-byte copy would
have looked identical to a field read without that.

⚠️ **A direct-address search for this table returns ZERO, and so does one for the table ADR-0291
PROVED is read.** `grep 8005ebf0` and `grep 8005fbf0` over `battle_disassembly.txt` are both
empty, because the base is a split `lui`/`addiu` constant. The positive control is the only reason
that zero was not reported as absence.

### The measurements

1. **Live RAM, 512/512.** Main RAM mined offline from three `.sstate`s (no emulator launched):
   the table at `0x8005EBF0` agrees with the disc-derived extraction on **all 32 AI bits for all
   512 records**, in every state. The ADR-0291 368/368 analogue, and it confirms the address, the
   stride and the byte offsets the static walk used.
2. **The fit is address-specific.** Shifting the base scores 74/512 at −4, 78 at −1, 99 at +1, 72
   at +4 — only the exact base reaches 512. And 390 of 512 records set at least one of the four
   bits, so a uniform all-false guess scores 122/512, not ~500.
3. **265/265 against this classifier, ZERO disagreements**, over all 278 skillset-reachable
   abilities rather than a spot check: `healing` 29 ally, `buff` 30 ally, `damage` 88 foe,
   `debuff` 118 foe. Both directions populated (59 ally / 206 foe), so it is not a degenerate fit.

### The decisions

**11. THE FLAGS SHIP AS CORROBORATION, AND `AbilityFamily` STAYS THE ANSWER.**
`ai_target_allies`/`ai_target_enemies` reach `AbilityView` through
`tools/parse_abilities.py` -> `effects.json` -> `generate_ability_database.py`, regenerated and
never hand-edited. They are **not** promoted to the source of the polarity axis, and the reason is
a measurement rather than a preference: the ROM is **silent on 12 reachable abilities** — `Frog`,
`Preach`, `Solution`, `Negotiate`, `PrayFaith`, `DoubtFaith`, `BlindRage`, `Faith`, `Innocent`,
`Golem`, `GilTaking`, `Invitation` — nine of them `ai_usable` Faith/Brave/talk skills. A family
narrowed onto these flags would leave all nine with no pool, regressing
`GambitOptions.seed_aim_for` for exactly the abilities whose direction is least obvious.

Rejected: **narrowing `AbilityFamily` to the `damage`/`debuff` vs `healing`/`buff` distinction and
taking polarity from the ROM**, which is what #1227 proposed. It trades a rule that answers for all
278 for one that answers for 266, and the two questions are not the same question anyway: this
classifier answers *should it* and the AI flag answers *what the AI does*
(`07-ability-hit-policy.md`). Where they disagree the ROM is not automatically right — which is
why the guard below reports a disagreement as a ruling owed, not as a defect.

**12. THE AGREEMENT IS GUARDED, NOT JUST OBSERVED.** `GambitEncoderTest._audit_ability_family`
carries the cross-tab: zero family/ROM conflicts over the reachable set, the silent 12 NAMED
rather than counted, and both arms of that list per #424. It rides the audit that already walks
the reachable set, so it costs no extra Godot process (the charter's real currency). Two bounds
stop it passing vacuously — the comparable set must be neither empty nor the whole walk, and the
ROM column must carry BOTH directions, because agreement with a constant is not agreement.
Direction-tested three ways: a seeded `Fire -> healing` override reds the conflict arm, a bogus
name on the silent list reds the dead-exemption arm, and dropping `Frog` from it reds the
unnamed-silent arm.

**13. `ai_only_allies`/`ai_only_enemies` ARE INERT AND ARE NOT SHIPPED.** They read like a
targeting rule and are read by **nothing**: byte +7 is loaded exactly once in the whole
enumeration and masked `0x01`, and the masks `0x40`/`0x20` appear nowhere against this table. They
also **contradict** the proven pair on `Silf`, `Fairy` and `StealExp`, and `GilTaking` sets both
at once, which no coherent polarity field would. This is ADR-0291 dec. 5's `targeting_ai_only`
arriving on a second name, and it is the reason #1227's four-flag framing is answered with two.

### Soft spot

**S6 — the CONSUMER of the polarity byte is not traced.** `+0x18` of the AI's working struct has
exactly three accesses tree-wide (write, read-modify, write), all at the seed above, so no
disassembled code reads what that site builds. Most likely the known blind spot — a static walk
cannot see a register-indexed array, and `0x80190a58` sits in an indexed per-unit AI block — so
absence of a reader is **not** evidence of absence, and it is not claimed either way. It does not
change any decision here: dec. 11 ships the flags as corroboration for an axis whose values are
independently confirmed 512/512 and 265/265, not as a claim about what the AI then does with them.

## Considered options

**`Weakest Ally` for the ally side instead of `Nearest Ally`.** This is dec. 8's alternative and
it is one line. `Weakest Ally` is MOST_CRITICAL over `friendlies()`, and MOST_CRITICAL is the one
ally resolution that **does** include the caster — so all 47 keep the caster reachable, a lone
wounded healer heals itself, and `Accumulate` lands on the caster whenever the caster is the
most-hurt friendly. For `healing` it is independently better: `GambitOptions`' own doc already
says an ally question is *"about the one who most needs it"*, and that sentence is why
`_weakest_ally` exists for the `If` column. Not taken, because the player said "nearest" four
times and a screen's vocabulary is theirs. Recorded with its numbers so the round-trip is cheap.

**Seed `Self` for the fifteen `range == 0` ally-side abilities and the family's pool for the
rest.** Narrower than the above and it fixes the two worst cases (`Accumulate`, `Scream`)
outright. Rejected for now on ADR-0276's own ground: `range == 0` is **not validated**, the
static reading of what it does to the cast-position path is exactly the
*"a mechanism that could explain it is not evidence it did"* mistake, and building a seeding rule
on top of an ungraded verdict class would bake the unvalidated reading into the screen. It
becomes the right answer the moment a rule-group-K scenario grades `range == 0`.

**Key the family on `formula` alone.** Rejected twice over. ADR-0276 found the first counterexample
(formula 56 holds `Heal` and `Seal`); formula 42 is the second and it is worse, because 56 is
separable by a field the record carries and 42 is not separable at all. A formula-only table
would have to pick one direction for Talk Skill and be wrong for half of it, silently.

**Infer the family from `target_reaction_type`.** The cheapest possible reader, and it is the
defect the audit's named witnesses exist to catch. Six reachable abilities — `Chakra`,
`Accumulate`, `Yell`, `CheerUp`, `Wish`, `Scream` — are `taking_damage` with an empty status
list and every one is a self- or ally-side restore. `Wish` spends the caster's own HP to heal an
ally and reads, by this proxy, as a strike.

**Put the table in `GambitOptions` with the rest of the screen's catalogues.** Rejected: it is
not the screen's fact. Two of the three predicates it reconciles (dec. 10) are in the addon and
in the shader, and a host-side home reconciles neither. It would also make the almanac's
`is_healing` and the surface's family two registers of the same idea, which is the shape
ADR-0273 dec. 2 rejects by name.

**Rule the 42 unreachable formulas too, so the unknown bucket is zero.** Rejected. A zero bought
by guessing at monster formulas no skillset row can reach is a worse number than a 42 that is
printed, ratcheted, and explained. The assertion that matters is that the REACHABLE count is
zero, and that one is hard.

**Declare the member a `table`.** It is a bank of rulings, which is a real argument. Rejected by
ADR-0273 dec. 5's tie-break and, independently, by dec. 1's own test: delete `AbilityFamily`'s
computation and nothing is left, where deleting `ShopAvailabilityDatabase`'s leaves a ROM table
still answering the question. The tie-break costs nothing on this tree (36 debt lines under
either word, run both ways) and it is recorded anyway.

## Consequences

- **The two cells the player reported both read correctly on a capture now.**
  `ThrowStone / Nearest Foe` with `Self` absent from the `To` list; before ADR-0276 it was
  `ThrowStone / Self` and the Squire hit itself.
- **153 abilities stop seeding `Self`.** 106 move to `Nearest Foe` and 47 to `Nearest Ally`.
  `Self` is still on most of those `To` lists — the seed moved, the offer did not.
- 🔴 **Forty-seven abilities can no longer be aimed at the caster by their default**, fifteen of
  them centred on the caster. Dec. 8. This is the one place this ADR makes a currently-correct
  case worse, it is on the record, and the fix is a one-word change to two table rows.
- **`AbilityDatabase.is_damage` is gone.** Any future caller wanting it writes
  `AbilityFamily.of_id(id) == AbilityFamily.DAMAGE`, which rules formula 10 through the status
  XOR rather than through a list that disagreed with the list beneath it.
- **`CombatLoop.gd:2175`'s AoE effect spray now agrees with the kernel about what a heal is**,
  and the agreement is currently unobservable (dec. 10). Migrating that call site to
  `AbilityFamily.is_ally_side` would spray ally-side effects at allies for buffs too, which is a
  behavioural change and does not ride inside a classification change
  ([ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)).
  Worth a ticket.
- **A status name that enters the extraction without a polarity row reds the audit**, naming the
  status and a record that inflicts it. So does a polarity row for a status nothing inflicts.
- **The almanac's live register moves to 33 published / 18 `table` / 12 `rule` / 3 `state`.**
  ADR-0251's frozen thirty-two is a different register and is deliberately untouched.
- **Rule group K gains nothing.** A default is provable statically and `scenarios_K_defaults`
  costs a battle; ADR-0276's consequence about clause 13 applies unchanged.

## Soft spots

- **S1. The seven polarity rulings are ours and nothing but a reader can falsify them.** The ROM
  partitions 23 of 30 and the gate corroborates five of the seven; `Crystal`, `DeathSentence`
  and `Undead` rest on FFT canon alone. `Crystal` is not even reachable, so its row exists only
  to keep the both-arms assertion honest.
- **S2. `range == 0` is still ungraded and this ADR raised its stakes.** ADR-0276 left it because
  validating it needs a scenario; fifteen of the abilities dec. 8 re-points are range 0, so the
  ungraded class and the new default now overlap on a named set instead of in principle.
- **S3. The six formula-42 rulings guard a branch our kernel does not run.** `Praise` and
  `Threaten` reach `combat_combat.glslinc:346`, the status-inflict path, carrying no statuses.
  The rulings are correct about FFT and untested against anything that moves.
- **S4. Route ORDER is a decision no test can falsify where two routes agree.** `Raise` answers
  route 1 and route 2 with the same family, so swapping them changes nothing today and would
  change something the day an extraction moves a field. The order is argued in dec. 4 and held
  by nothing else.
- **S5. The zero-fallback control is a property of this tree.** It is strong — 59 records had the
  chance to contradict a ruling — but it is a measurement, and a re-extraction that flips a
  `dont_hit_*` bit would turn a correct family into a printed fallback rather than into a red.
  The assertion treats a fallback as a defect, which is the right default and will one day be
  wrong about a legitimately contingent record.
