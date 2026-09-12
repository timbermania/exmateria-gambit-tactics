# A sensible default is the aim the ROM cannot fault, and the preference is still open

A player opened the gambit surface, pressed `Move`, and got `Move / Self / Foe HP<25%`. Then
they picked `ThrowStone` and got `ThrowStone / Self`. Neither is a typo, a mis-encode, or a
readout bug: both rows say exactly what the slot holds, both encode with no E1 skip, and both
reach the kernel. One of them spends the turn standing still. The other throws a stone at the
unit that threw it.

They asked for two things, and the second is the one this ADR is about:

> *"What does `Move / Self / Foe HP<25%` do? When I choose ThrowStone it defaults to Self — we
> need a rule/audit for this to make sure sensible defaults apply. Is it a damage spell? a
> healing spell? a buff? a debuff? something else?"*

The rule is here. The last question — the effect FAMILY — is not answered, and §"What is not
decided" says why, with the number that sizes it.

## Status

accepted

Supersedes [ADR-0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md)
dec. 12's account of seeding, and **corrects two claims dec. 12 makes** — see
§"The correction". Extends dec. 8's derived-option-list gate. Reads
[ADR-0049](0049-ability-hit-policy-is-rom-flag-derived.md)'s hit policy as an authoring-time
classifier for the first time, and records a conformance gap in it. Builds the (b) half of
**#1125**; the (c) half — `If` two levels deep — is untouched.

## Decision

### The state space, and what each cell can be

1. **The space is `(verb x aim)`, and every cell in it is graded.** The verbs are `Attack`,
   `Move`, `Wait` and each ABILITY; the aims are the six rows of `GambitOptions.targets()`.
   `Them` is not a seventh class — it forwards to whatever the `If` column picked out, so the
   same aim is a different cell under a different subject, and the space is really
   `(verb x aim x If-subject)`. **5,058 cells** as of this ADR: 3 verbs plus the 278 abilities
   any skillset row can open onto, times 3 distinct subject classes, times 6 aims.

   Enumerating rather than patching the two reported cells is the whole point. They are
   instances. `GambitOptions.aim_verdict` is the grader and `GambitEncoderTest`
   (`_audit_every_aim_cell`) is the audit that walks the space.

2. **Five verdicts, and the four broken ones are broken in different ways.**

   | verdict | what it means | census |
   |---|---|---|
   | `sensible` | legal, and nothing in the ROM record or the kernel can fault it | 4,059 |
   | `no_op` | encodes, FIRES, blocks every lower slot — and does nothing | 4 |
   | `forbidden` | the ability's own ROM record says this pool is off limits | 797 |
   | `ignored` | the kernel never reads the aim for this verb | 14 |
   | `unnamed` | `Them` under a `Self` subject — the `Self` row under a second name | 184 |

   A cell can be more than one of these, and the GRAVER reading wins: `Move / Them` under a
   `Self` subject is unnamed *and* a no-op, and it is counted as the no-op, because that is the
   one that costs a turn rather than a word. The 184 is what is left after the 96 abilities
   whose record forbids the caster take their `Them` cells into `forbidden`.

   `unreachable` — rule E1's class, the choice the encoder skips — is deliberately absent.
   ADR-0268 dec. 8 already owns it and `GambitEncoderTest`'s round-trip already asserts it.
   What this ADR grades is what happens *after* a clean encode, which is the half E1 cannot
   see.

3. **`no_op` is `Move / Self`, and it is rooted in the kernel, not inferred from the row.**
   `GambitEncoder.gd:275-282` maps `ActionKind.MOVE` to `ACTION_MOVE_TO_UNIT`, and MOVE
   inherits `action_target` as its DESTINATION — so the destination is the unit that is me.
   `execute_move_to_unit_gambit` (`stage_pathfind.glsl:677`) reads `U_TARGET`, and its
   adjacency check is the first thing it does:

       if (manhattan_distance(my_x, my_z, tx, tz) <= 1) { ...REASON_ARRIVED; idle }

   `0 <= 1`. The slot commits — `execute_gambit_action` returns true with `VERDICT_FIRED`, so
   the slot walk stops and every lower-priority slot is unreachable — and the unit has not
   moved. It re-arrives every `TICKS_GAMBIT_REEVAL`, forever. A unit whose slot 0 is
   `Move / Self / Foe HP<25%` freezes for as long as any foe is critical.

   This is ADR-0268 dec. 11's own name for dec. 8's failure mode — *"a
   row that reads back correctly and does nothing"* — reached through the DEFAULT rather than
   through an unsupported feature.

4. **`forbidden` is the ROM's `dont_hit_*` triple, and it is a HARD GATE.** ADR-0049 extracted
   `dont_hit_enemies` / `dont_hit_allies` / `dont_hit_caster` per ability;
   `GPUAbilityLoader.gd:96-101` encodes them to `ABFLAG_HIT_NO_*`; `hit_policy_allows`
   (`combat_common.glslinc:1593`) is the predicate. Over the 368 records that carry a formula:

   | flag | true | false |
   |---|---|---|
   | `dont_hit_caster` | **186** | 182 |
   | `dont_hit_allies` | 49 | 319 |
   | `dont_hit_enemies` | 13 | 355 |

   **`Self` is an illegal aim for more than half the catalogue** — and `Self` is exactly what
   the screen left an ability-verb slot aimed at. ThrowStone (id 148) is one of the 186.

5. 🔴 **`forbidden` does not currently no-op. It LANDS — and that is a live ADR-0049
   conformance gap.** `hit_policy_allows` has exactly two call sites,
   `stage_damage.glsl:128` and `stage_spell.glsl:637`, and **both are inside AoE distribution
   walks entered only when `effect_area > 0`**. ThrowStone's `effect_area` is 0, so it takes
   the single-target path — `apply_damage_to_target` writes `U_DAMAGE_TARGET` /
   `U_DAMAGE_AMOUNT`, stage_damage Phase 2 applies it — and **nothing on that path consults
   the hit policy at all.**

   So `ThrowStone / Self` is not a wasted turn. The Squire hits itself for real damage. The
   same hole is under every one of the 797 `forbidden` cells whose ability has
   `effect_area == 0`. Fixing it is a kernel change with its own faithfulness question — does
   an illegal aim fall through to the next slot, or commit and hit nobody? — so it is filed as
   **#1144**. `tests/gambit_scenarios/scenarios_K_defaults.gd::K2` is the xfailed witness that
   holds the place.

6. **`Weakest Ally` is a CONTINGENTLY forbidden aim for the 186, and it is not graded.**
   `TargetSelector.friendlies()` includes the caster, and `find_unit_by_criteria` skips the
   caster on NEAREST **and only on NEAREST** (`if (mode == 0 && u == unit_id) continue;`). So
   `Nearest Ally` can never resolve onto the caster and `Weakest Ally` — MOST_CRITICAL, mode 1 —
   resolves onto it whenever the caster is the most-hurt friendly, which is exactly the tick a
   heal gambit fires. The gate leaves the row standing: it is legal to author, legal on most
   ticks, and the screen cannot know the tick. A gate that removed rows on a contingency would
   be over-reaching, and this one only removes what it can prove. It does bear on #1144 — a
   forbidden aim that falls through to the next slot handles this case gracefully, and one that
   commits and hits the caster does not.

7. **`unnamed` is `Them` under a `Self` subject, and it is #1125's opening line.** `Them`
   forwards to whatever the `If` column picked out; when the condition is `Always` that subject
   is the actor (`Gambit._init`), so `Them` resolves to the caster and IS the `Self` row already
   on the list — under the one name that does not say so. ADR-0268 dec. 12 wrote the same
   sentence about the empty gambit's two fields: *"the two spell one behaviour and only one of
   them says so."* The row is dropped, and it comes back the moment the `If` column gives it a
   subject to forward to — `Them` under `Foe HP<50%` names a foe and earns its place. The
   surface already treated `Them` this way in one place and only one: `safety_net_row` and
   `imperative_row` both read the CONDITION target for their `to` column precisely because
   `triggering()` *"says nothing about the pool it aimed at"*.

8. **`ignored` is `Wait` with any aim but the one meaning "nobody".** `execute_gambit_action`
   exempts WAIT from the no-final-target bail (`final_target < 0 && action_type != ACTION_WAIT`)
   and its `apply_pending_action` branch idles without touching a carrier. `Wait / Nearest Foe`
   is a column describing a field the kernel never opens — a readout lie rather than a wasted
   turn, but the same class of thing: the row says something the unit does not mean.

### The rule

9. **The `To` list offers only `sensible` cells.** ADR-0268 dec. 8 established that the option
   lists are DERIVED — *"every choice this surface offers must round-trip through
   `GambitEncoder` without a skip"* — and this extends the same idea one step past the encoder.
   Dec. 8 removed choices the encoder skips; this removes choices the encoder accepts and the
   kernel then wastes. **Both failures look identical to the player**, which is why they belong
   behind one gate: `GambitOptions.targets_for(action_kind, ability_id, condition_subject)`.

   The gate never empties a list. No ROM record carries all three `dont_hit_*` flags, so at
   least one pool always survives every ability — a fact about the data, asserted over the
   whole catalogue by the audit rather than assumed by the code.

10. **The seed onto an empty slot is the HEAD of the gated list, and that is not a preference.**
   Picking "damage wants a foe" needs a family taxonomy this screen does not have (dec. 13).
   Picking the first row the screen is willing to show involves no new opinion at all: it is
   where the cursor already sits when the player opens `To`, and every row it could land on is
   one the grader could not fault.

   `Attack` keeps dec. 12's explicit `Nearest Foe` and does not take its list head. Two
   reasons, both dec. 12's and both still good: `Attack` is the one unconditionally offensive
   verb, and the seeded value has to be the same object ADR-0048's safety net carries so the
   `To` column can NAME it. (Its list head would be `Self` — legal, unfaultable by the ROM
   because a basic attack carries no ability record, and obviously not what anyone means.)

11. **A configured slot is re-aimed only when the press made its aim BROKEN.** dec. 12's
   restraint — *"a slot the player has already aimed is one they have made a decision about"* —
   is right and survives. It just never covered the case where the press invalidates the
   decision rather than disagreeing with it. Change `Cure / Self` to `ThrowStone` and `Self`
   stops being a choice the screen should defer to: the ability may not take it, the `To` list
   no longer offers it, and leaving it strands the row on a value the player can see and can no
   longer re-pick. So a verdict of `sensible` is left alone and anything else is re-seeded.

   The `If` column re-seeds too, for the same reason: the subject is half of what `Them` MEANS,
   so landing `Always` re-points `Them` at the actor and an aim that was legal under the old
   subject can be forbidden under the new one.

12. **The readout probes the UNGATED catalogue.** `GambitSurface._target_text` names the aim
    out of `GambitOptions.targets()` and not out of the offer list. Since dec. 7 the offer list
    is a SUBSET, and a slot can legitimately hold an aim the current verb would no longer
    offer — one aimed before the verb changed, one authored by ADR-0048's net, one loaded from
    a save. Naming it out of the subset would miss, fall through to `"Self"`, and print an aim
    the slot does not hold: the readout lie this column exists to prevent, arriving through the
    gate meant to prevent it.

### The correction

13. **ADR-0268 dec. 12 says this screen "has no classifier" for what an ability wants to be
    aimed at. That is false, and it is merged.** The ROM ships one. It is already extracted
    (`AbilityView.dont_hit_caster` / `_allies` / `_enemies`), already encoded to the GPU, and
    already consulted by the kernel. It is ADR-0049's, and dec. 4 above is it.

    The correction is narrower than *"so just use the flags"*, and the narrowness is the
    interesting part. The `dont_hit_*` triple is a **hit policy** — who the effect may land on
    — and not an **effect family**. It answers *may it*, never *should it*. `Cure` legally hits
    an enemy, because an undead one takes the heal as damage, so `dont_hit_enemies` is false on
    it and the flags say nothing about `Cure` wanting an ally. The restraint dec. 12 built on
    the false premise was therefore under-justified but not wrong: seeding `Attack` alone was
    too little, and seeding a *family preference* would still be a guess.

14. **dec. 12 also says `Move` and `Wait` "mean Self". `Wait` does; `Move` does not.**
    "Move to the unit that is me" is not what `Move` means — it is dec. 3's no-op, and dec. 12
    kept the slot pointed at it on purpose. `Wait`'s aim is unread (dec. 6), so `Self` there is
    the honest spelling of "nobody" rather than a claim about a destination.

## What is not decided

**The effect FAMILY, which is the half of the player's question this ADR does not answer.**
They asked *"is it a damage spell? a healing spell? a buff? a debuff? something else?"* — and
after the gate above, **153 of the 249 reachable abilities still seed `Self`**, because the ROM
permits the caster and nothing else in the tree says they are offensive. **130 of those 153
carry `target_reaction_type: "taking_damage"`** — `Fire`, `Bolt`, every summon. FFT canon is
that summons hit allies, so the hit policy is *right* to permit it and *useless* as a default.
Only a family taxonomy improves those cells.

Three things were checked and are recorded here so the next session does not re-derive them:

- **The family lives in `formula`, and the space is 82 values, not ~180.** The 368 abilities
  that carry a formula use 82 distinct ids. `combat_combat.glslinc` already partitions them
  implicitly across its branches (damage at `:451+`, break effects at `:282+`, inflict at
  `:346`). Nothing names the partitions.
- **`formula` alone does not separate buff from debuff.** `Protect` / `Shell` / `Haste` /
  `Esuna` are formula 11 and `Poison` / `Slow` / `Stop` are formula 10, which looks like a
  clean split until formula 56 (22 abilities) holds `Heal` and `Seal` together. The direction
  there is in `inflict_mode` (CANCEL vs ALL) and in whether the statuses are good ones. A
  family table needs both fields, not one.
- **Three partial family predicates already exist in the tree and they CONTRADICT each other.**
  `AbilityDatabase.is_damage` lists formula 10 as damage while `NON_DAMAGE_FORMULAS` lists 10 as
  not-damage; `AbilityDatabase.is_healing` is `formula == 12` while the shader's
  `is_ability_healing` reads `ABFLAG_HEALING`, which comes from
  `target_reaction_type == "receive_heal"` and covers formulas 12 AND 13. `is_damage` has no
  callers. Building the taxonomy means reconciling these, not adding a fourth.

The vocabulary is a player-facing concept and the wrong one is expensive to unpick, so it is
being put to the player before it is built rather than inferred from the phrasing of the
question.

**And a SECOND candidate verdict class, found while enumerating and deliberately NOT graded:
`range == 0`.** 41 of the 249 reachable abilities carry it — every Draw Out, every Song and
Dance, `SpinFist`, `Chakra`, `StigmaMagic`. Range 0 does not mean "self only"; it means the
effect is CENTRED ON THE CASTER and radiates, so the `To` column is picking a target for
something that does not take one. Statically, `spell_pre_validate` checks MP and **not** range
(`stage_compute.glsl:533-539`), and the range gate lives on the cast-position path, which by
design defers a tick rather than falling through — so the candidate reading is *"the unit walks
toward a target it can never be in range of, forever"* rather than a clean decline. **That is
not validated and is not graded here.** `SpinFist` is the sharp case: `range 0` AND
`dont_hit_caster`, so this ADR's gate removes `Self` and every row it leaves standing may be a
row that never fires — which would make it the one ability in the catalogue with no working
aim. Validating it needs a rule-group-K scenario per branch, not a static reading; a grader
that took the static reading on its own would be exactly the "a mechanism that could explain it
is not evidence it did" mistake.

## Considered options

**Fix the two reported cells.** Rejected: they are instances. `Move / Self` and
`ThrowStone / Self` are 2 of the 801 cells the audit grades broken, and the two the player
happened to press. A patch that named them would leave 799 and no way to find the next report.

**Derive the aim from `formula` now, and skip the hit policy.** Rejected: it inverts the
evidence. The hit policy is extracted, encoded and consumed today; the family table is ~82
formulas of RE with two unreconciled predecessors, and it answers a *preference* question whose
answer is a player-facing vocabulary nobody has chosen. Doing the cheap, ROM-grounded, hard
half first is what makes the remaining question small enough to ask crisply — 130 cells, named.

**Gate the `To` list AND pick a family preference inside it.** Deferred, not rejected: this is
the shape the design should end at, and dec. 7 + dec. 8 are its first half. The second half
needs the vocabulary decision above.

**Revive the five-dropdown editor** (`UIGambitEditor3`'s `Do / Prefer / Team / To / When`).
Still rejected, on ADR-0255's Considered-options ground: *"a cross-product, most of it
meaningless"*. Note that this ADR is the opposite move — it makes the offered set SMALLER by
proving cells meaningless, where the five-dropdown editor made it larger by exposing raw fields.

## Consequences

- **`GambitOptions` grew the grader and the gate**, and it is still static and scene-free, so
  the audit needs no surface, no character and no battle — the same property ADR-0268 dec. 8
  bought and this ADR spends again.
- **The audit rides in `GambitEncoderTest`**, an existing GPU-free process, rather than
  arriving as a new one. `docs/TEST-CHARTER.md` clause 13: the suite is 736 processes and a
  new test costs a ~2.3 s boot forever, so an assertion that shares a setup carries in the test
  that already has it.
- **The audit prints its subject and asserts a NON-ZERO count of both broken classes.** An
  audit reporting "0 nonsense cells" because it examined nothing looks exactly like a clean
  bill of health; a classifier gone blind — a renamed `AbilityView` accessor, a `dont_hit_*`
  key dropped from the extractor — would grade every cell `sensible`, pass every
  "nothing is broken" assertion, and be caught only by the positive control.
- **Rule group K joins `tests/gambit_scenarios/`** with the two reported cells as kernel
  witnesses, because the effect is the only layer that can see this defect class — every layer
  above it says yes. K1 ships with a control arm (the same fixture minus the no-op slot) since
  it asserts two absences.
- **797 cells stop being offered.** A player who wants one back cannot have it: the row is
  gone from `To`, not greyed. That is dec. 7's deliberate shape and it matches dec. 8's
  precedent — an unofferable choice is removed, never shown-and-refused.
- 🔴 **The single-target hit-policy hole is now written down and unfixed.** It was invisible
  before this ADR looked for it. Anyone reading ADR-0049 would reasonably assume the policy is
  enforced; it is enforced on AoE only.

## Amendment 1 (2026-09-11) — `range == 0` is GRADED, and it grades `sensible`

*Closes the one open class this ADR left. Grades it; it does not change a rule. Every
verdict, count and decision above stands — the 5,058 cells and the five verdicts are
untouched, because the class was never counted into them.*

§"What is not decided" recorded `range == 0` as a **second candidate verdict class** and
deliberately refused to grade it, on the correct ground that its reading —

> *"the unit walks toward a target it can never be in range of, forever"*

— was a mechanism and not evidence. [ADR-0278](0278-the-seed-is-the-familys-pool-and-the-family-is-ours-because-the-rom-records-a-hit-policy-and-not-a-purpose.md)
dec. 8 / S2 then pointed fifteen of them at `Nearest Ally` and said so.

**The reading is false, and one accessor is why.** `start_spell` never reads the ability's
range. It reads `get_effective_ability_range` (`combat_common.glslinc:1512`), whose first
branch is:

```glsl
int base_range = get_ability_range(ability_id);
if (base_range == 0) {
    return read_unit(battle_id, unit_id, U_WEAPON_RANGE);
}
```

`range == 0` is the ROM's *"this ability inherits the wielder's reach"*, not a literal zero.
So `spell_range` at `find_cast_position` is the **weapon's** range, the search box is the
ordinary one, and a range-0 ability walks into weapon reach and fires like any other. This
ADR read the FIELD; the accessor is the answer, and it was already there.

**Validated, not inferred — which is what §"What is not decided" asked for.** Rule group
`K3` starts a Monk at Manhattan 2 from its ally, outside a weapon reach of 1, and asserts
that it closes the gap *and* that the ally takes the hit; a unit that arrived and then
stalled would satisfy the first alone. Every assertion K3 leans on is a PRESENCE, which is
why it ships without a control arm — a blind fixture produces absences, and the one absence
it does carry (the Knight, Manhattan 6) is geometric rather than evidential.

**The `spell_range == 0` branch is graded too, and the SEED is what graded it.** On a true
zero `find_cast_position` searches the box `[tx, tx] × [tz, tz]` — the target's own tile and
nothing else — and `continue`s on `is_tile_occupied(..., unit_id)`, which the target itself
satisfies, so it returns `(-1,-1,-1)` and `start_spell` writes IDLE + `TICKS_GAMBIT_REEVAL` +
`REASON_SPELL_FAILED`. Running `K3` with the accessor's `base_range == 0` branch disabled
reproduces every line of that: **closest dist 2 at tick 2**, no damage to anyone. So the
other half of this ADR's candidate reading is refuted as well — **it does not walk.** It
idles. `spell_pre_validate` has already let the slot COMMIT by then (it checks the target and
the MP, as this ADR said), so the turn is spent: the `Move / Self` no-op shape of dec. 3,
arrived at from the other direction.

⚠️ **That branch is not reachable in production, and the arm that tried to reach it honestly
was DELETED as vacuous.** A `K3c` control forcing `weapon_range: 0` was written first;
`GPUCombatPacker`'s `weapon_range` row is `BEHAVE_RECOMPUTE`, so the value is re-derived from
the unit's weapon and a scenario cannot set it. That arm ran identically to `K3` and would
have shipped as a control measuring nothing. Seeding the accessor is what reached the branch,
and a seed is a statement about code rather than about a reachable game state — which is the
right strength of claim for a branch no unit can enter.

**What this does and does not buy ADR-0278.** Its dec. 8 named `Nearest Ally` as making 47
abilities worse, and 15 of those carried `range == 0`. Those fifteen are no longer part of
the complaint: they fire, they reach, and the AoE centres on the target with host and kernel
agreeing (`K3` asserts the caster is inside its own radius; the untouched Knight at Manhattan
6 is the geometric control). The host/kernel agreement was measured directly on a four-unit
probe — a neighbour of the CASTER at Manhattan 2 from the target was touched by neither the
effect spawn nor the damage, which is the one arrangement that separates the two centres. ADR-0278's second rejected option — *"seed `Self` for the
fifteen"* — was rejected **only** because this class was ungraded, and grading it removes the
reason without supplying a new one: `Nearest Ally` works for them.

🔴 **`Accumulate` and `Scream` are NOT covered by that and are now the sharp case.** They are
`range 0 / effect_area 0`, so the effective reach is the weapon's and the single-target path
applies the result to **one** unit — the neighbour, not the caster. In the ROM `Accumulate`
raises the caster's own PA. That is a faithfulness gap in `get_effective_ability_range`'s
blanket rule rather than a gambit-surface defect, and it is a different question from either
this ADR's or ADR-0278's. `SpinFist`, this ADR's named sharp case, is fine: it is `range 0`
with `effect_area 1`, so its reach is the weapon's and its radius covers the ally it was
aimed at.
