# `gambits/` stays in the almanac, and the tests that said otherwise were measuring a kernel vocabulary in the wrong package

[ADR-0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)
dec. 1 named its own soft spot in the ADR that created the package: *"This is the one
decision in the pass settled by taste rather than by measurement, and it is the cheapest
one to reverse."* The four `gambits/` members are an original FFXII-style AI design and
nothing in Final Fantasy Tactics has them, so a ROM-provenance name would make a false
claim about them. #1060 asked whether the answer is instead to move them out.

Taken as five questions, four of them measurable, the answer is **no, and not for the
reason the ticket expected**. `gambits/` passes ADR-0115 dec. 3's asymmetry test and dec.
6's one-import test. It fails **dec. 1** — REP, *the granule of reuse is the granule of
release* — because the package it would become cannot be installed without the package it
left. And the single edge that makes both of the passing tests interesting is
`jobs/UnitRole.gd`, which is a **unit vocabulary in a rules package** and belongs in the
kernel on the precedent `unit_vocabulary/Facing.gd` set for itself.

Nothing here moves the arm-5 number. That is the finding, not an omission: the 252 lines
`gambits/` is reached on are HOST reaches, bucketed identically whether the directory
moves or not, and extraction's measurement benefit is **zero** — measured, not assumed.

Status: accepted (2026-09-10), on trunk `f60bb3290`. Closes **#1060**. Reads
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 1 for REP, dec. 3 for one-way
uselessness, dec. 4 for the content shadow and dec. 6 for a feature threading systems,
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 3 for the
kernel's admission gate and dec. 4 for its two vetoes,
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1 for the schema table this
ADR amends,
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 1 for `UnitProgression`'s ownership and dec. 2 for the doubling this ADR does not
answer,
[ADR-0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)
dec. 1 for the taste call,
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 5 for the accepted debt and its four grounds, and
[ADR-0273](0273-free-ness-inside-the-rules-tier-is-declared-per-member-because-a-package-of-tables-is-not-all-tables.md)
decs. 4, 5, 6 and 7 for the member-kind register, its tie-break, its numbers and its
mutation standard.
**Supersedes nothing.** ADR-0251 dec. 1 stays accepted and is RATIFIED rather than
reversed: its 🔴 marker recorded a decision settled by taste, and this ADR settles the
same decision by measurement without changing it.

## Context

#1060 is `wayfinder:grilling` and posed five questions. Three of its premises did not
survive being checked, which is decision 8, and the two that did are the whole argument.

The package under question is `addons/exmateria_almanac/gambits/` — `Gambit` (414),
`GambitList` (128), `GambitCondition` (326), `TargetSelector` (194), 1,062 lines. Its
entire outbound surface, measured by reading every `preload` and every capitalised
identifier in the four files:

| file | reaches outside `gambits/` |
|---|---|
| `GambitCondition.gd` | **nothing** |
| `TargetSelector.gd` | `UnitRole` — 9 code lines |
| `Gambit.gd` | `UnitRole` — 3 code lines; `AbilityDatabase` — 3 code lines |
| `GambitList.gd` | `Gambit` — 9 code lines |

`JobDatabase` is not reached at all. And **nothing in the almanac's other 28 files names a
`gambits/` member**, so the dependency is strictly one-way.

🔴 **The instrument for the consumer census below is a re-implementation, not the guard.**
`sibling_class_reaches` answers addon→addon only, and the question here is host→addon. The
script reuses `score_goals.strip_noncode`, `classify_blueprint.classify` and the façade-alias
binding modelled on `sibling_class_reaches`' pass A, but it is not that function and its
numbers are not arm 5's. It agrees with arm 5 on the one row both can see —
`exmateria_catalogue` naming `GambitList` on 4 lines — which is a control and not a proof.

## Decision

**1. `gambits/` stays in `exmateria_almanac`, and REP is what decides it.** Three options
were on the table and only one of them is wrong on its face.

*Extract as it stands* is refused. `Gambit.gd` names `AbilityDatabase` on three lines, so
the resulting addon would declare `deps="exmateria_almanac"` and its stranger rig would
stage the entire package it had just left. ADR-0115 dec. 1 is *the granule of reuse is the
granule of release*; a package whose install closure strictly contains the package it was
split from is not a second granule, it is a subdirectory with a `plugin.cfg`.

*Sever the rendering first, then extract* is coherent, is not refused, and is declined on
today's evidence — see decision 4 and the alternatives. Its benefit is naming accuracy plus
a standalone install **no consumer has asked for**, and its cost is a tenth addon with its
own `plugin.cfg`, README and stranger rig, ~252 call-site substitutions, and the façade
census re-pinned in three places.

*Stays* is the ruling. ADR-0262 dec. 5's first ground was *"folding severs no edge; it
stops the guard printing one."* The mirror is what settles this: **splitting creates no
edge either.** Decision 7's 252 lines are host reaches that `classify()` books to `Battle`
and `UI` whether or not the directory moves, and arm 5 has never seen one of them. #1060's
question 4 — *would extracting convert 232 printed lines into invisible ones?* — is
unfounded in both directions, and so is the benefit it was guarding.

**2. `GambitList` does not move to the Character Catalogue, because it costs 4 and pays 9.**
#1060 question 2 reads `GambitList` as per-unit state in the category ADR-0241 dec. 1 ruled
the catalogue's, and proposes it may move regardless of the other three. Measured, it may
not:

| edge | code lines |
|---|---:|
| `exmateria_catalogue` → `GambitList` (`identity/Character.gd:53,108,191,461`) | **4** |
| `GambitList` → `Gambit` (`:12,15,18,22,45,51,89,97,126`) | **9** |

Moving it alone retires 4 lines of arm-5 debt and creates 9, and `Gambit` is declared
`rule`, so the new nine stay printed under ADR-0273 dec. 1. The debt gets **worse by five**
under every destination. `GambitList` travels with `Gambit` or it does not travel; ADR-0241
dec. 1's ownership argument is about `UnitProgression` and does not reach it.

**3. `UnitRole` is a unit vocabulary, and it is admitted to the shared kernel as ADR-0118
dec. 1's ELEVENTH row.** It is the single reason `gambits/` looked expensive to extract —
12 code lines into a member declared `rule`, which ADR-0273 dec. 1 prints rather than frees.

`jobs/UnitRole.gd` is 47 lines and contains **no derivation**: an `enum Role`, an
enum→string table (`get_role_name`), a list of the enum's members (`get_all_roles`) and a
two-line predicate (`matches`). Its docstring says *"derived from job type"*, and that
describes `JobDatabase.get_job_role`, a different file. FFT has no roles at all — they are
this project's AI archetypes, the same provenance ADR-0251 dec. 1 records for the gambits
themselves. So it is neither a `table` of ROM facts nor a `rule` that computes what the ROM
computes: it is a **value set**.

🔴 **A file move cannot do this, and the gate is why this decision is in an ADR at all.**
ADR-0139 dec. 3 sets the admission test as membership in a named published schema: a file
enters the kernel when it realises a row of ADR-0118 dec. 1's table and by no other route,
and adding a member means first naming a payload and the two systems it crosses between, in
an ADR. ADR-0139 dec. 3's last sentence is the whole of it: *"A file move cannot do it."*
The ADR-0164 amendment block inside ADR-0118 dec. 1 says the same of its own row — the row
exists because ADR-0139 dec. 3 makes an ADR the gate, and the type cannot be written until
the schema is named there. So the row comes first:

| Schema | From, to |
|---|---|
| the **unit role vocabulary** | the `rules` tier (`JobDatabase.get_job_role` decides it), to `Battle` (`src/gpu/GambitEncoder.gd` packs it) and `UI` (`src/ui3/UIGambitEditor.gd` populates its dropdown) — the **eleventh** |

ADR-0118 dec. 1 carries the amendment block, in the shape ADR-0164, ADR-0196 and ADR-0215
each added one. The row is a **vocabulary and not a payload**, which the tenth row already
established as admissible.

ADR-0139 dec. 4's two mechanical vetoes both pass, by inspection rather than by assertion:

- **(a) the sink veto — zero outbound edges into any system, `content` or `platform`
  bucket.** `UnitRole.gd` contains no `preload`, no `load`, and names no identifier it does
  not declare. Its outbound edge count is **0**. Worth contrasting with dec. 4(a)'s own
  worked failure: `Character.gd` was rejected from the kernel for three outbound edges, and
  one of them is `GambitList`.
- **(b) the autoload veto — never an autoload.** `extends RefCounted`, one enum and three
  static functions. The almanac ships no `[autoload]` and this member installs nothing.

The kernel already holds the drawer and the precedent.
`addons/exmateria_schema/unit_vocabulary/` is the tenth row's realisation and holds `Facing`
(58), `UnitActivity` (64), `ClockOwner` (31), `SpriteLayer` (31) and `UnitMaterialVariant`
(29) — the same size, the same shape, the same `extends RefCounted` enum-plus-helpers.
`Facing.gd`'s own docstring records why it was lifted out of a 369-line Node: *"a caller
compiled against the sprite rig's animation state machine in order to say 'south' — 52
uses, and a caller of them learns a **value set**, not a contract."* Substitute *the
almanac's job tables* and *melee* and the sentence is unchanged. `UnitRole` does not join
that row — its producer is the `rules` tier and not `Sprite Rig` — but it shares the row's
shape and its directory. `JobDatabase`'s own 24 `UnitRole.Role` lines get the same benefit.

**4. `Gambit`'s English rendering is UI's, and it moves whatever happens to the package.**
`_get_noun_string`, `_get_team_string`, `_build_when_line`, `_action_display_name`,
`_build_action_line`, `_resolution_to_friendly_string` and `_to_string` are ~150 of
`Gambit.gd`'s 414 lines, plus `GambitCondition.get_sentence_text`. The entire surface has
**one** external consumer, `src/ui3/detail/GambitOptions.gd`, on two lines. Both
`AbilityDatabase` call sites live inside it, and both are name resolution:
`Gambit.gd:219` renders an ability's display name, and `:233` is documented *"for
construction / legacy-save migration only — the stored form is kind + id, never the name
(the fragility ADR-0023 removes)."*

A model class that renders itself to prose for one UI file is ADR-0115 dec. 4's shape with
the arrow reversed, and this is booked as its own change for its own reason. That it also
happens to be the whole cost of decision 1's declined third option is stated here so nobody
later reads the move as a fix booked into the bucket it drains
([ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)).

**5. The name `exmateria_almanac` is ratified, and ADR-0251 dec. 1 stops being a taste
call.** Dec. 1's argument was that a ROM-provenance name would misdescribe a fifth of the
package while *"an almanac is a book of tables you look things up in"* claims nothing about
provenance. Decision 3 moves the composition **toward** that description, not away: the one
member that was a vocabulary rather than a lookup leaves, and what remains is 32 members —
18 `table`, 11 `rule`, 3 `state`.

⚠️ **Those literals moved between drafting and merge, and the argument did not.** At
`f60bb3290` the live register was 32 published / 18 `table` / 11 `rule` / 3 `state`, so this
sentence read 31 and 10. [ADR-0278](0278-the-seed-is-the-familys-pool-and-the-family-is-ours-because-the-rom-records-a-hit-policy-and-not-a-purpose.md)
dec. 9 then landed `AbilityFamily` as the thirty-third member and the twelfth `rule`. The
DIRECTION is what decision 5 rests on — one `rule` leaves and no `table` does — and that is
unchanged by a member arriving beside it. The literals are re-taken here rather than left,
because the census is the live register and not a frozen count
([ADR-0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)'s
thirty-two is the extraction's and does not move).

`exmateria_rules` was weighed, because the package now declares `tier="rules"` and is that
tier's only member. Rejected: ~700 call sites spell `ExMateriaAlmanac.`, the substitution
changes no measurement, and a package named after the tier it inhabits becomes a land-grab
the day a second `rules` addon lands — which decision 9 (iii) deliberately keeps possible.

**6. The Character Catalogue's 36 arm-5 lines are the accepted price, not a countdown.**
ADR-0262 dec. 5 named 55 lines and accepted them, *"stated so nobody re-sells the fold
without answering it."* The number has moved 55 → 53 (ADR-0272, the sprite-rig row) → 36
(ADR-0273's member kinds) by three separate rulings and **none of them set a target of
zero**. Two consecutive handoffs into this area have read it as one. It is recorded here
because #1060 was being treated as the catalogue's isolation blocker, and it is not:
`GambitList` is 4 of the 36 and decision 2 leaves them where they are.

**7. The census is re-taken, and #1060's table is stale.** Non-test, `src/` plus every
sibling addon root, façade-resolved, on trunk `f60bb3290`, with the instrument caveat in
the Context above:

| member | Battle | UI | other |
|---|---:|---:|---|
| `Gambit` | 35 | 26 | — |
| `GambitCondition` | 35 | 46 | — |
| `TargetSelector` | 44 | 41 | assembler 4 |
| `GambitList` | 5 | 12 | Character Catalogue 4 |
| **total** | **119** | **125** | **8** |

**252 lines, and UI is ahead of Battle.** #1060's body reports 240 with Battle 118 / UI 114
and `plugin.cfg` reports a third set from `c6549fd4c`; both predate this tree and neither is
wrong for the tree it was taken on. The ordering matters only because the ticket's framing
leaned on Battle being the larger consumer.

**8. Three of #1060's premises are refuted, and the register is proved by mutation.**

- The title's `a feature threading two systems` — the ticket's own words, and a quotation of
  nothing. ADR-0115 dec. 6 reads *"Gambits thread through three systems"*. This is the defect
  ADR-0273 dec. 6 found and corrected in two live-source sites, appearing again in a ticket. `check_adr_quotes.py` is structurally
  blind to it — a bare paraphrase carries no `*"…"*` span to match.
- *"if the useful core drags `JobDatabase`, `UnitRole` and the ability tables"* (question 1).
  `JobDatabase` is not reached from `gambits/` at all, and the ability tables are reached on
  two display lines into a member declared `table`, which ADR-0273 dec. 1 frees.
- *"`GambitList` may belong to the roster regardless of what happens to the other three"*
  (question 2). Decision 2 measures it at +5.

🔴 **Another paraphrase was found while writing decision 3, and it is not #1060's.**
#1059's phase-1 tier table gives the kernel's free-ness as `ADR-0139 — a shared vocabulary
is not coupling`. **ADR-0139 contains no such sentence**, and neither does anything else in
the tree — this ADR would have been the first file to carry it. What ADR-0139 actually
grounds the kernel on is narrower and more useful: dec. 4(a)'s sink veto, *"a member that
reached into a system would drag that system behind every consumer"*, plus dec. 3's
admission gate. Drafting decision 3 from the paraphrase would have moved `UnitRole` on a
one-line rationale and skipped the gate entirely. This is the same class as ADR-0273 dec. 6
and ADR-0271 dec. 10, and `check_adr_quotes.py` is blind to it for the same reason: a bare
paraphrase carries no `*"…"*` span to match. The ticket is not source and is left as
written; the correction lives here.

Per ADR-0273 dec. 7 the register is proved by mutation and not by a green guard. On
`f60bb3290`, arm 5 baseline is **373 free / 36 debt / 12 shader-global, rc 0**. Declaring
`UnitRole` a `table` moves **nothing** — 373 / 36 / 12 — and reds exactly one test, the
almanac's census pin in `tools/test_check_addon_portability.py`. That test was named
`test_the_split_is_eighteen_tables_eleven_rules_three_state` when the mutation was run and
is `..._twelve_rules_...` since ADR-0278; the mutation's result is unchanged, only the
method name is. The positive control that
makes that zero readable is ADR-0273 dec. 7's own: declaring `UnitProgression` a `table`
takes arm 5 to **405 / 4**, the predicted numbers to the line. The register is consulted, so
`UnitRole`'s zero is a real zero and not a blind instrument: a zero
from an instrument with no positive control is indistinguishable from a zero from an
instrument that never looked.

🔴 **The 12 lines decision 3 removes are DERIVED, not measured.** Arm 5's rule gives them —
a sibling reach into a member declared `rule` is debt — and the rule is proved live by the
control above. But no addon was staged to observe them, because the addon this ADR declines
to create is the only tree they would appear in.

**9. What this ADR does NOT decide.** Three things, named so the next reader does not
mistake silence for a ruling.

- **(i)** Whether `UnitProgression` and `AbilityLoadout` move to the Character Catalogue.
  That is #1059 phase 3, and ADR-0241 dec. 2's measurement — membership A at 4 names / 45
  lines against A + `UnitProgression` at 9 / 85 — is still unanswered. Nothing here touches
  it, and #1123's lift of `EquipSlot` / `AbilitySlot` is preparation and **not** approval.
- **(ii)** Whether the catalogue's 36 lines should ever reach zero. Decision 6 rules them the
  accepted price; it does not rule that a future pass may not pay them.
- **(iii)** Whether a second `rules`-tier addon may exist. Decision 1's third option stays
  available and is declined on today's evidence rather than forbidden. A real consumer for
  standalone gambits is the evidence that would reopen it, and decision 4 is what would make
  it cheap.

## Considered alternatives

- **Extract `gambits/` as its own addon, as it stands.** Decision 1. It would declare
  `deps="exmateria_almanac"` on the strength of three lines, so it could never be installed
  without the package it left — which is ADR-0115 dec. 1's definition of not being a separate
  granule of release. Worth recording that arm 5 would have permitted it: post-decision 3 the
  extraction creates **zero** new debt lines, because the only surviving edge targets a
  member declared `table`. **The numbers never blocked this; REP did.**
- **Sever the rendering, then extract.** Decision 1's declined third option, kept alive by
  decision 9 (iii). Not rejected on principle — rejected on the ledger: zero measurement
  gain, a hypothetical consumer, and a tenth addon's fixed cost.
- **Re-kind `UnitRole` to `table` instead of moving it.** Rejected, and this ADR's author
  recommended it before running the mutation. ADR-0273 dec. 5's asymmetry is the reason: *"A
  member wrongly called `rule` costs a printed line somebody can falsify. One wrongly called
  `table` costs silence."* Dec. 5 called `UnitRole` a genuine near-tie and gave it `rule`
  precisely because *"none of the three has an arm-5 row, so 371/36 is identical under either
  reading."* The moment `gambits/` moves is the moment that stops being true — so the
  discovery that the tie now costs something is a reason to be **more** careful about
  flipping to the silent side, not less. Decision 3 gets the same 12 lines freed by TIER,
  which is falsifiable in a way a kind flip is not, and it is correct whether or not
  `gambits/` ever moves.
- **Move `GambitList` to the Character Catalogue on its own.** Decision 2. +5 lines.
- **Rename the package `exmateria_rules`.** Decision 5. Zero measurement change against ~700
  call sites, and it collides with the tier the package declares.
- **Rename the package `exmateria_rom_tables` / `exmateria_records`.** ADR-0251 dec. 1's own
  rejected pair, re-rejected on the same ground and now with the composition measured: 4 of
  31 members and 252 lines of consumed surface are an invented AI design with no ROM
  provenance at all.
- **Treat #1060 as the Character Catalogue's isolation blocker and rule accordingly.**
  Rejected by decision 6. It governs 4 of 36 lines and decision 2 leaves them standing. The
  catalogue is at its ruled destination.

## Consequences

- **Two code changes follow, in either order, each with its own ticket and its own
  falsifiable claim.** `UnitRole` → `exmateria_schema/unit_vocabulary/`, and the English
  rendering → UI. Neither is bundled with this ADR, so a mistake in either is visible as
  itself.
- **The almanac's `plugin.cfg` gains `exmateria_schema` to its `deps=`, and one sentence
  becomes false.** The `engine=` block currently states *"Nothing here reaches
  `exmateria_schema`."* `JobDatabase` will. It is a live source comment and is corrected with
  the move, not here.
- **ADR-0118 dec. 1's table is eleven rows**, and its amendment block carries the veto
  evidence. This is the first row whose producer is a TIER rather than a system, which is
  the shape ADR-0271 created and no schema row had needed yet.
- **Arm 5 does not move.** 373 / 36 / 12 before and after decision 3, because `UnitRole` has
  no arm-5 row on this tree. A pass that expects this ADR's work to change the debt number
  has misread it.
- **`gambits/` remains the one part of a `rules`-tier package with no ROM provenance**, and
  decision 5 accepts that as the cost of a name that claims nothing about provenance. The
  almanac README's purity predicate is unaffected — it tests for nodes, scenes, shaders and
  frames, none of which gambits hold.
- **#1060 closes; #1059 stays open.** Phase 3 is untouched and ADR-0241 dec. 2's doubling
  still has no answer.

## Soft spots

- **S1. The census instrument is a re-implementation.** Stated in Context and repeated here
  because it is the number most likely to be quoted. If the host→addon question is worth
  asking twice, it is worth a function in `check_addon_portability.py` beside
  `sibling_class_reaches`, and then three ADRs stop each carrying their own script.
- **S2. The 12 freed lines are derived from arm 5's rule, not observed.** Decision 8's 🔴.
  Staging a throwaway gambits addon would observe them and would also price decision 1's
  third option properly. It was not done, because the option is declined.
- **S3. `Gambit`, `GambitCondition` and `TargetSelector` are declared `rule` while being the
  one thing in the package that is not a rule the ROM computes.** ADR-0273's vocabulary
  defines `rule` as *"a driver, COMPUTES what the ROM computes"*. Gambits compute what
  **this project** invented. The kind is right for arm 5's purpose — they are not banks, so
  they must stay printed — and the definition is one word too narrow. Not corrected here;
  ADR-0273 is accepted and the fix is a word in its vocabulary, not a re-kind.
- **S4. Decision 4 leaves `_to_string()` behind, or moves a Godot override.** `_to_string`
  is an engine hook, so a caller writing `str(gambit)` gets the rendering wherever the code
  lives. Whoever builds decision 4 has to decide whether the override stays as a thin
  delegate or goes, and `GambitOptions.gd`'s two lines are the only external evidence of what
  breaks.
