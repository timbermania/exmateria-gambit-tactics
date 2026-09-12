# The `To` list is ordered by the ability's family, and the ROM stores the polarity we hand-wrote

## Status

Accepted (2026-09-11)

Extends ADR-0278 (which owns `AbilityFamily`) and ADR-0276 dec. 12 (membership is
`aim_verdict`'s decision). Composes with ADR-0291. Supersedes nothing — but see
dec. 5, which **falsifies a premise ADR-0278 states**.

## The ask

> *"can we also have it do some common sense sorting based on the spell? for example healing
> spells have ally above foe in the list. damage spells the opposite. buffs have ally on top.
> debuffs have foe on top… self should be on top if it's self targetable and positive"*

## Context

`GambitOptions.targets()` returned ONE hardcoded order for every verb and every ability:
`Self, Them, Foe, Nearest Foe, Weakest Foe, Ally, Nearest Ally, Weakest Ally`. So `Cure` opened
on `Self` then `Nearest Foe`, and `Fire` opened on `Self` too.

The taxonomy the ask calls for **already existed** — it did not need building. `AbilityFamily`
(ADR-0278) classifies every ability `damage` / `healing` / `buff` / `debuff`, and
`is_ally_side()` is exactly the ally-vs-foe polarity. It was wired to pick the DEFAULT aim
(`seed_aim_for`) and to nothing else.

## Decisions

### 1. The order is the family's, and it is the SAME decision as the seed

`targets_for` now returns its gated rows ordered by `family_aim_name` — the very function
`seed_aim_for` consults. Deliberately not a second classifier: if the list were sorted by one
rule and seeded by another they could disagree, and the player would watch the screen default to
a row that is not the one on top.

| family | order |
|---|---|
| `healing`, `buff` | `Self`, ally block, foe block |
| `damage`, `debuff` | foe block, ally block, `Self` |

`Self` **sinks below the ally block** for a negative ability rather than merely leaving the top:
`Fire / Ally` is a bad row and `Fire / Self` is a worse one, so the list says so.

⚠️ **ONE licensed disagreement, and it is dec. 3's.** For a positive, self-targetable ability the
head is `Self` while the DEFAULT stays the family's row — `Cure` opens the list on `Self` and
still seeds `Ally`, because ADR-0278 dec. 2 (*"healing defaults to nearest friendly"*, the
player's own words) owns the default and this ADR owns the order. 57 of 281 cells. It is licensed
**only** for `Ally` polarity; a foe-side ability heading on `Self` is the dec. 6 defect, and
`GambitEncoderTest` asserts the carve-out is neither empty nor the whole walk.

### 2. It REORDERS — it can never add or remove

It runs strictly after the gate, on what the gate left. No row can be resurrected by sorting and
none hidden by it, so ADR-0276 dec. 12 is untouched and `GambitEncoderTest`'s one-decision guard
(a SET comparison) is unaffected by order.

Ties keep `targets()` order via an index-decorated sort, so the `nearest`/`weakest` sequence
inside a block cannot shuffle on a sort-stability accident.

### 3. `Self` rises only when positive AND self-targetable — and neither half is re-asked

The player's rule has two conditions and **both were already answered**:

- *positive* — `is_ally_side(family)`.
- *self-targetable* — **whether the `Self` row is still in the list at all**. ADR-0291's gate
  already withheld it for the four abilities whose ROM record forbids the cursor landing on the
  caster.

So this asks about the **row**, not about the flag. `Wish` is `healing`, therefore positive, and
never floats `Self` to the top — because `Self` is not there to float. `Revive` likewise. That is
the two features composing rather than a special case, and `GambitEncoderTest` carries it as an
explicit arm: if `Wish` ever reports `Self` first, either the gate stopped withholding or the
sorter started resurrecting.

### 4. An unclassified ability keeps `targets()` order, and that is the test's control

`family_aim_name` answers `&""` for the 42 UNKNOWN-family records and for every verb with no
family (`Move` aims at a DESTINATION, `Wait` reads no aim). Those are returned untouched —
ordering them would invent a claim the classifier declined to make.

🔴 **That row is also what makes the test a test.** *"`Cure` puts an ally row first"* is satisfied
by a sorter that puts an ally row first for everything. Every arm is therefore paired with its
opposite (`Cure` vs `Fire`), and the unclassified control pins that a sorter which rearranged the
whole catalogue would be caught.

### 5. 🔴 THE ROM STORES THIS POLARITY, AND ADR-0278 SAYS IT DOES NOT

ADR-0278 built `AbilityFamily` as *"a `rule` and not a table **because nothing in the ROM stores
it**"* (quoted in `docs/context/07-ability-hit-policy.md`). **That premise is false for the
polarity axis.**

`research/effect-meta-data/data/ability_data.json` carries a 4-byte AI block per ability, 512
records, including `ai_target_allies` / `ai_target_enemies` (AI Flags 1) and `ai_only_allies` /
`ai_only_enemies` (AI Flags 4). True counts: 72 ally-targeting, 315 enemy-targeting, 17
ally-only, 41 enemy-only. Spot-checked against our hand-written families, **12 of 12 agree**:

| | `Cure` `Cure2` `Raise` | `Protect` `Shell` `Haste` | `Fire` `Bolt` `Ice` | `Slow` `Poison` `Blind` |
|---|---|---|---|---|
| our family | healing | buff | damage | debuff |
| `ai_target_allies` | 1 | 1 | 0 | 0 |
| `ai_target_enemies` | 0 | 0 | 1 | 1 |

The player's instinct — *"I'm sure the enemy AI implements something"* — is correct, and the data
is extracted but **not shipped**: `assets/abilities/ability_attributes.json` carries no `ai_*`
field.

**Not used here, deliberately.** Two reasons, and the second is the one that matters:

1. The seed already uses `AbilityFamily`, so ordering on it keeps dec. 1's one-decision
   property. Ordering on a second source would re-open exactly the disagreement dec. 1 avoids.
2. 🔴 **These are FFHacktics wiki names, and ADR-0291 dec. 5 is what a wiki name is worth here** —
   `targeting_ai_only` reads like a rule and is read by nothing. 12/12 data agreement is
   corroboration, **not** a decompile. Rooting them is a data-provenance change that deserves its
   own evidence, not a ride inside a sorting change.

Filed as [#1209](https://github.com/timbermania/fft-monorepo/issues/1227). If it holds, the
polarity axis stops being a hand-written rule and `AbilityFamily` narrows to the
`damage`-vs-`debuff` / `healing`-vs-`buff` distinction the ROM genuinely does not store.

### 6. 🔴 `Attack` is foe-side WITHOUT having a family, and the seed already knew

This ADR shipped believing `Attack` was out of scope for lacking a family. **It was not out of
scope — it was the one cell already violating dec. 1**, and the invariant that proves it did not
exist until it was written.

`seed_aim_for` hardcoded `if action_kind == ATTACK: return foe_pool()`, while `_ordered_by_family`
asked `family_aim_name`, which answers `&""` for every non-ABILITY verb. So **`Attack` seeded
`Foe` and opened its list on `Self`** — head and default disagreeing on the most-used verb on the
screen. Two gates answering one question, which is the defect shape and not the fix shape.

There is now ONE answer, `aim_polarity`, and both the seed and the order read it. `Attack`
returns `&"Foe"` there; `family_aim_name` is untouched and keeps saying *no family* for `Move` and
`Wait`, because a weapon swing genuinely has no ability record for `AbilityFamily` to classify.

`Attack` now reads `Foe, Nearest Foe, Weakest Foe, Ally, Nearest Ally, Weakest Ally, Self`.

⚠️ **A per-case assertion is what missed this, so the replacement is an INVARIANT.** A
pre-existing arm pinned `Attack`'s seed and wrote *"its gated list head is `Self`"* in its own
failure message — it documented the defect and passed. `GambitEncoderTest` now walks every cell
and asserts the head IS the seeded row, minus dec. 3's carve-out.

## What was NOT done

- **`Move` keeps `targets()` order.** Its aim is a DESTINATION, not a target, and `Move / Self`
  is already graded `AIM_NO_OP` and withheld — so its list begins with `Foe` anyway and there is
  no disagreement to fix. Confirmed by probe rather than assumed.

## Consequences

- `GambitOptions.targets_for` -> `_ordered_by_family`; no data, no schema, no new classifier.
- `GambitEncoderTest` gains a four-arm matrix: `Cure` (positive + self-targetable -> `Self`
  first), `Fire` (negative -> foe block first, `Self` not first), `Wish` (positive + gated ->
  no `Self` at all), and an UNKNOWN-family control asserting `targets()` order byte for byte.
- Census unchanged — ordering does not change grades.
