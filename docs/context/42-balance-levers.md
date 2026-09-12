# Balance levers

The vocabulary of the **lever layer** — the hand-authored multipliers composed
over the ROM tables, which stay immutable underneath. Coined by
[#1106](https://github.com/timbermania/fft-monorepo/issues/1106) and decided in
ADR-0277.

The easy mistake is calling the whole thing "the balance config", which
collapses four different objects: the file, one entry in it, the number that
entry carries, and the product of all the entries that touch one record. They
have different lifetimes and different guards, so they have different names.

The second easy mistake is folding the two **pacing** slugs in here. They are a
separate layer and always have been — see [Pacing layer] below for why the
distinction is load-bearing rather than pedantic.

**Lever set**:
The file — `assets/balance/levers.json` — and, at run time, the `LeverSet`
object over it (`src/balance/LeverSet.gd`). Hand-authored, committed, read by
the shipped build, and **sparse**: a category with no entry has factor 1.0.
Content, not machine config, which is why it lives under `assets/` and not
`config/` — a teammate's checkout must read the same levers, and `config/` is
where machine-scoped things live (`tune_overrides.json` is rewritten by the F3
panel). It ships **empty**: ADR-0277 decided the layer, and the first real
numbers belong to
[#1107](https://github.com/timbermania/fft-monorepo/issues/1107) and
[#1108](https://github.com/timbermania/fft-monorepo/issues/1108), where the
evidence for them will exist.
_Avoid_: "the balance file" (there could be several, and this is the only one
the kernel reads); "overrides" — that is `config/tune_overrides.json`, a
different artifact with different semantics.

**Lever**:
One entry in the lever set: a `{quantity, by, key, factor, why, evidence}`
object. It is a **claim that the ROM number is wrong for this kernel**, which is
why `why` is required and an empty one is a boot error rather than a warning.
_Avoid_: "rule", "override", "tweak". A lever multiplies; it never replaces.

**Factor**:
The number a lever carries. Strictly positive and bounded to `[0.05, 20.0]`,
because deletion is not a balance operation and must not be reachable by typing
a small number.
_Avoid_: "modifier", "scalar" — the latter is taken, see [Pacing layer].

**Tier**:
Which resolution a lever speaks at: **global** (`by: all`), **category**
(`by: formula` / `ability_type` / `item_type`) or **record** (`by: ability` /
`item`). The three **multiply** —
`effective = rom x global x category x record` — so 1.0 is the identity at
every tier and a sweep at one tier still moves the records another tier has
touched. Replace-semantics was rejected: under it, moving a whole category
silently fails to move any record carrying an override, so the more you author
the less the category tier does.

**Effective factor**:
The product of all three tiers for one quantity on one record. This is what
[Digest] hashes and what [Realised factor] is measured against.

**Levered**:
Said of a value that has been through the layer. ⚠️ **A unit's `wp` is levered;
the item's `wp` is not.** The two are different numbers whenever a `wp` lever
exists, and anything reading a unit's stats for display, or diffing against the
oracle, sees the levered one. The word exists so that difference can be stated
in one syllable instead of re-explained.

**Quantity**:
What a lever scales, drawn from a **closed enum of six**: `wp`,
`weapon_range`, `w_ev`, `cooldown_ticks`, `charge_time`, `mp_cost`. Closed
means adding a seventh is a decision, not an edit — an open key space is how the
file becomes 300 magic numbers, and it makes the guard's "this names a quantity
that does not exist" check impossible to write. A field naming an **identity**
rather than a magnitude (`formula_id`, `element`, `inflict_mask`,
`weapon_type`, …) is deliberately absent: scaling those is not balance, it is a
different record.

**Capability quantity** / **Cost quantity**:
The split that decides a levered value's floor. `wp` and `weapon_range` are
**capability** and floor at 1 whenever the ROM value was >= 1 — a lever may
weaken a weapon and may never silently disarm one (`Nagrarock` is `wp 1`).
`cooldown_ticks`, `charge_time`, `mp_cost` and `w_ev` are **cost**, where 0 is
a meaningful value (free, instant, no evasion), so they floor at 0.

**Attack period**:
The ticks between a unit committing to a basic attack and its next decision.
The **seventh** quantity, and the one whose base was already there: it is the
weapon's SEQ animation length, so it is per-weapon-type before any lever is
authored — 38 ticks for all nine melee types, 40 unarmed, 44 Gun, 52
Crossbow/Bow, plus a distance-proportional flight tail the firer waits out for
the three ranged types. A bow at its native range 5 is **2.0x** a sword.
🔴 **So reach was never free**, which is what
[#1107](https://github.com/timbermania/fft-monorepo/issues/1107) opened
believing. What the period lacked was an author, not a downside.
_Avoid_: "attack cooldown" — a [cooldown] is per-(unit, ability) and lives in
its own SSBO under `MAX_COOLDOWN_ABILITIES`; the attack period touches neither
and must never be smuggled in as ability id 0.

**Recovery**:
How a levered [attack period] is realised: the **difference** between the levered
period and the unlevered one, owed after the action completes as `U_TIMER` on the
IDLE edge. It is not a second authored number — nothing names a recovery, and
scaling one would be scaling a difference.
🔴 **The unlevered period is the floor.** Recovery is `max(0, levered - rom)`, so
a factor below 1.0 buys nothing: there is no shorter SEQ to play and no faster
arrow. Measured in a live battle — a sword at x1.0 and x0.5 both realise a
40-tick gap and x2.0 realises 78; a bow at distance 3 goes 59 → 115.
⚠️ **The base is the whole period, not the animation.** For a sword those are the
same number; for a bow they are not, because the firer waits out
`projectile_frame + max(dist * 10, 15)` in `AWAITING_IMPACT` before it may choose
again. Scaling only the SEQ would make `x2.0` mean `x1.68` on exactly the three
ranged types, varying with how far away the target stood.
_Avoid_: calling the whole period "recovery". The period includes the action;
recovery is only the tail, and ADR-0032 reserves `ACTING` for SEQ playback, so
the two cannot be the same span.

**Category** (of a record):
The **one** class a record belongs to, as a tagged `{by, key}`. For abilities:
`formula` where the record has one (368 of them, 82 classes) and
`ability_type` where it does not (144, 9 classes). For items: `item_type` (35).
🔴 **A strict partition, not a matching rule.** A record is in exactly one
category, so `{by: ability_type, key: Normal}` matches **nothing** — every
`Normal` ability carries a formula — and that is a guard error, not a silent
no-op. To move all `Normal` abilities, author `{by: all}` plus nine
`ability_type` counter-rows.
_Avoid_: **skill set as a category.** It is not a partition — 224 of the 355
abilities it covers sit in more than one set and 157 of the 512 sit in none.

**Reachability** (of a lever):
Whether the kernel can actually consume this quantity on this record.
**Derived, never listed** — `MAX_COOLDOWN_ABILITIES` is scanned out of
`combat_common.glslinc` and the unreachable ability types come from the ROM's
own `ability_type`, so the day
[#1108](https://github.com/timbermania/fft-monorepo/issues/1108) raises the
ceiling the numbers move with it. Reaction, Support and Movement abilities are
unreachable for all six quantities: Support and Movement have no extractor at
all, and a Reaction reaches the kernel through its own 7-entry `REACT_*` enum,
which consults none of them.

**Hollow lever**:
A lever whose category is reachable by spelling but whose quantity reaches
**none** of its members — coverage 0. It encodes cleanly, passes every other
check, and never fires. This is the [bit-0 trap] one layer up, and it is an
**error**.

**Static coverage** / **Dynamic coverage**:
Two different numbers that must never be summed. **Static** is a property of
the lever set and needs no run — *"this lever reaches 25 of the 41 abilities in
formula 8"* — and belongs to the boot guard. **Dynamic** is a property of a
**roster** and only exists once units are seated — *"this lever reached 3 of the
47 units in this run"* — and belongs to the rig's report. Reporting only the
static one would let the instrument certify a lever set the game never touches:
of 5,657 deployed ENTD slots, 5,103 name no weapon at all
([#1121](https://github.com/timbermania/fft-monorepo/issues/1121)).

**Realised factor**:
What a levered integer actually achieved, as against what the author wrote.
Every quantity lands in an int buffer, so an arbitrary factor is not
representable: `wp 3 x 0.9` rounds to 3, a realised **1.0**. Rounding half away
from zero beats truncation (which would give 2 — a 33% cut from a 10% lever)
but does not fix the resolution, it hides it, so the guard reports the worst
realised factor per lever beside the authored one.

**Digest**:
The provenance stamp: a hash of the **composed effective factors** plus the
pacing layer's live values, stamped on every corpus row. It answers *"are these
two rows comparable?"* as a check rather than an assumption.
🔴 **The output is hashed, not the input.** An input hash moves when a key is
reordered or a `why` is reworded — changes that alter nothing — and stays still
when a loader change alters behaviour without touching the file. Hashing the
composed result means the digest moves exactly when the numbers the kernel sees
move. It is read **per sample**, not per write, so a mid-run scrub puts two
digests in one file; that is the truth about the run, and freezing it at start
would claim a uniformity the file lacks.

**Pacing layer**:
`pacing.move_time_scale` and `pacing.damage_scale` — **not** part of the lever
set. They ride the config buffer as Q8 fixed point, they stay live-scrubbable
`Tune` slugs, and they scale quantities **no record has a field for**
(`scale_hp_transfer` / `scale_move_ticks`), so neither has a per-record form.
Folding them in would put two unlike things under one word. [Digest] covers
both layers, because a provenance stamp that certifies half a configuration is
worse than none.
_Avoid_: "the global levers" — the lever set has its own global tier
(`by: all`) and it is a different mechanism at a different address.
