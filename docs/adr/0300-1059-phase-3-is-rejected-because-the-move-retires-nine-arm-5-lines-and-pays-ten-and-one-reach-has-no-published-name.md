# #1059 phase 3 is rejected: the move retires nine arm-5 lines and pays ten, and one of the seven reaches has no published name

[#1059](https://github.com/timbermania/fft-monorepo/issues/1059) phase 2 gave every member
of `exmateria_almanac`'s façade a declared kind in `const MEMBER_KINDS` and named three of
them `state` — `UnitProgression`, `GambitList`, `AbilityLoadout` — with a sentence that
deliberately did not settle anything: *"Declaring the kind does not settle where they live
— it makes the debt a countable number instead of a paragraph."* Phase 3 is the pass that
would settle it by moving those three to `exmateria_catalogue`.

It is rejected, and it is rejected as an ADR rather than as a pass that runs and gets
reverted, because **four independent blocks stand in front of it and only one of them had
never been priced**. Three were already on the record. The fourth is `UnitProgression`'s
own seven `preload` lines, which are intra-package and free today and become cross-addon
reaches the moment the file moves. Priced here for the first time, that fourth block is on
its own sufficient: the move **retires nine arm-5 lines and pays ten**, which is
[ADR-0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md)
dec. 2's shape one member over.

## Status

accepted

## Context: the three blocks that already stood

**ADR-0241 dec. 1 ruled `UnitProgression` the catalogue's BY OWNERSHIP — and dec. 2 ruled
that applying the ruling doubles the debt.** Its membership table measured `A` (nine
`src/characters/` files + `AllTemplatesSeeder`) at 4 names / 45 lines and `B` (`A` +
`UnitProgression`) at 9 names / 85 lines: *"the ruling does not unblock the extraction —
applied, it doubles the debt."* The seven names `B` trades for are the same seven this ADR
re-prices, because they are the same seven `preload` consts.

**ADR-0241 dec. 3 ruled the class does not split.** The obvious escape — a durable record
in the catalogue, a derivation layer left behind — does not exist in the file. Re-measured
on today's tree (`addons/exmateria_almanac/progression/UnitProgression.gd`): **41 of 52
functions touch a database or `StatCalculator`**, 11 are database-free accessors over
dictionaries the other 41 populate, and all **72** database reaches are static class
access, so there is no injection point to cut at. Dec. 3 read 41 of 53 and 56 calls; the
file has moved and the ruling has not.

**ADR-0280 dec. 2 ruled `GambitList` does not move, because it costs 4 and pays 9.** Its
own arithmetic, not an argument by analogy: moving it alone retires the four
`identity/Character.gd` lines and creates nine `GambitList` → `Gambit` lines, and `Gambit`
is declared `rule`, so the nine stay printed. *"`GambitList` travels with `Gambit` or it
does not travel."*

**`exmateria_schema`'s twelfth-row block rules `UnitProgression` itself inadmissible to the
shared kernel.** The block above `const UnitRole` in `addons/exmateria_schema/exmateria_schema.gd`
(grep `UnitProgression ITSELF DID NOT MOVE`) says it *"names five databases by static class
access and would fail ADR-0139 dec. 4(a)'s sink veto on every one of them"*. What ADR-0294
admitted to the kernel was the value sets nested inside it — `EquipSlot`, `BaseStatType`,
`Zodiac` — not the class.

**And ADR-0280 dec. 6 already ruled the catalogue's arm-5 lines a price rather than a
countdown**, *"recorded here because #1060 was being treated as the catalogue's isolation
blocker, and it is not."* It read 36. The tree reads **13** today.

## Decisions

**1. #1059 phase 3 does not happen. The three `state` members stay in `exmateria_almanac`.**
The kind declarations are untouched and stay `state`: the kind is a claim about what a
member ANSWERS, and all three answer *a unit's own numbers*. What phase 3 proposed was a
consequence — that a `state` member should therefore live with the package that owns units
— and the consequence does not follow, because every route to it is measured and every
measurement is negative.

**2. Moving `UnitProgression` to the catalogue retires NINE arm-5 lines and pays TEN.**
Its seven `preload` consts are intra-package today and cost nothing. After the move they
are reaches into a sibling addon, and the conformant form is the ADR-0175 dec. 2 façade
alias (`ExMateriaAlmanac.X`), which is exactly what arm 5 measures. Priced against
`MEMBER_KINDS`, code lines only, the guard's own stripper:

| target | kind | code lines | after the move |
|---|---|---:|---|
| `ItemDatabase` | `table` | 21 | free |
| `JobDatabase` | `table` | 13 | free |
| `AbilityDatabase` | `table` | 9 | free |
| `JobLevelsDatabase` | `table` | 8 | free |
| `AbilityType` | `table` | 3 | free |
| `StatCalculator` | **`rule`** | **10** | **PRINTED** |
| `BaseStatsDatabase` | **absent from `MEMBER_KINDS`** | **5** | **cannot be written** — dec. 3 |

54 lines are free, 10 are new arm-5 debt, and 5 cannot be spelled at all. Against that,
the move retires the nine lines that name `ExMateriaAlmanac.UnitProgression` from inside
the catalogue (`identity/Character.gd:55,119,193,404,483,550` and
`seeding/AllTemplatesSeeder.gd:45,297,298`). **13 → 14 at best**, and only if
`BaseStatsDatabase` is published as a `table` first.

**3. `BaseStatsDatabase` is the block that is not arithmetic: it has no published name, and
a sibling addon is not the trigger the façade names.** The façade's *"NOT published, and
why"* paragraph rules on it directly — *"ZERO namers outside this addon: `StatCalculator`
and `UnitProgression` are its only readers, and the host reaches those … Publish it the day
a host file names it, in the pass that adds the call"* (ADR-0251 dec. 3). A move does not
satisfy that trigger. It manufactures a SIBLING namer, forces the publication as a side
effect of relocating one file, and moves the extraction's frozen thirty-one/thirty-two
register for a reason that is not the trigger that paragraph names. `table` is very likely the
right kind for it — it is a bank — but that call belongs to the pass that adds the host
call, with the host call in front of it as evidence.

**4. Keeping the seven raw `res://` preloads instead is the WRONG escape, because no arm
can see them.** This is the shape that makes the move look cheap, so it is ruled on
explicitly. Arm 6's subject is *"a quoted `res://` literal whose target leaves every
addon"* — `check_addon_portability.res_path_reaches` emits a row only when
`_ADDON_RES_RE` does NOT match the target. `res://addons/exmateria_almanac/…` lands inside
an addon root, so **arm 6 reports nothing**. Arm 5 reads `class_name` reaches, and a
`preload` const is not one. So the raw-path form would take nine lines the net currently
MEASURES and re-spell them into a form nothing counts: the census would read 13 → 4 while
the coupling was identical. A number that improves because the instrument stopped looking
is the defect this repo keeps finding, not a result.

**5. A move creates NO CYCLE — but only if the façade DROPS the three published names, and
that is the expensive half.** *Cycle* is the objection a reader reaches for first, so it is
answered rather than left implied. Measured with the guard's own stripper, each of the
three `state` members is named on exactly **two** almanac code lines outside its own file:
the façade's `preload` const and its `MEMBER_KINDS` row. **Zero members reach them.** So
the almanac → catalogue edge a cycle needs does not exist in the member set.

It exists in the façade. Re-exporting a moved member — keeping
`const UnitProgression = preload("res://addons/exmateria_catalogue/…")` so host call sites
do not change — creates a real one: the almanac would reach the catalogue, the catalogue
already reaches the almanac on 30 measured lines, and `deps=` would have to name both
directions, so each addon's stranger-rig closure would contain the other. ADR-0115 dec. 1
is *the granule of reuse is the granule of release*, and ADR-0280 dec. 1 applies it: *"a
package whose install closure strictly contains the package it was split from is not a
second granule"*. Dropping the consts instead is the conformant option and it costs **56
code lines across 55 files** re-pointed from `ExMateriaAlmanac.X` to `ExMateriaCatalogue.X`
— `UnitProgression` 41 in 40, `GambitList` 10 in 10, `AbilityLoadout` 5 in 5 — plus the
almanac's published census re-pinned.

**6. THIRTEEN IS THE FLOOR under the current architecture, and it is a price, not a
countdown.** The 13 lines are `identity/Character.gd` 10 (six naming `UnitProgression`,
four naming `GambitList`) and `seeding/AllTemplatesSeeder.gd` 3. Every route to a smaller
number is closed by a ruling: MOVE them (dec. 2 for `UnitProgression`, ADR-0280 dec. 2 for
`GambitList`), DECLARE them `table` (they answer a unit's own numbers, and `MEMBER_KINDS`
is an enforcing register where *"a wrong word is a verdict on an enforcing guard, not a
typo"*), or SPELL the reach as a path (dec. 4). ADR-0280 dec. 6 said the number is not a
countdown; this says where the countdown would stop if anyone ran it anyway, so the next
handoff does not have to re-derive it. `AbilityLoadout` contributes **zero** of the 13 —
no catalogue file reaches it — so its case is ownership and publication cost, not
arithmetic.

**7. Arm 8 (#1241) does not check acyclicity, and the cycle in dec. 5 would pass it.**
Recorded against the guard that landed the same week rather than left for its first
victim. Arm 8 checks a CORRESPONDENCE — every `deps=` name is reached, every measured reach
is declared — and a mutual dependency satisfies it in both directions. `rig.sh`'s BFS
dedups at pop time, so it terminates and stages both, quietly. The thing that refuses a
cycle in this repo is ADR-0115 dec. 1 read by a person, and dec. 5 above is the place that
reading is written down.

## Evidence

- **The census, from the guard.** `uv run python tools/check_addon_portability.py` →
  `cross-addon class_name DEBT — 13 line(s)`, three rows, all `exmateria_catalogue` →
  `exmateria_almanac`: `identity/Character.gd:53,120,203,584 ExMateriaAlmanac.GambitList`,
  `identity/Character.gd:55,119,193,404,483,550 ExMateriaAlmanac.UnitProgression`,
  `seeding/AllTemplatesSeeder.gd:45,297,298 ExMateriaAlmanac.UnitProgression`.
- **The seven targets, priced.** `MEMBER_KINDS` reads 32 rows, 18 `table` / 11 `rule` /
  3 `state`. Five of `UnitProgression`'s seven `preload` targets are `table`,
  `StatCalculator` is `rule`, and `BaseStatsDatabase` has **no row at all** and no
  `const` on the façade — it is one of the two members the *"NOT published, and why"*
  paragraph covers. Line counts in decision 2's table are code lines under
  `check_addon_portability.strip_gdscript_comments`, excluding the seven `preload` consts
  themselves.
- **The split, re-measured.** 52 functions, 41 touching a database or `StatCalculator`,
  11 database-free, 72 static reaches: `ItemDatabase` 21, `JobDatabase` 13,
  `StatCalculator` 10, `AbilityDatabase` 9, `JobLevelsDatabase` 8, `AbilityType` 6,
  `BaseStatsDatabase` 5.
- **Arm 6's blindness, from its own source.** `res_path_reaches` appends a row only
  `if not _ADDON_RES_RE.match(target[len("res://"):])`. A cross-addon `res://addons/…`
  literal matches, so it is not a row. Read the predicate, not the docstring: the
  docstring's subject is *"a target outside every addon root"* and that is what the code
  implements.
- **The cycle test.** For each of `UnitProgression`, `GambitList`, `AbilityLoadout`, a
  stripped scan of every `.gd` under `addons/exmateria_almanac/` except the member's own
  file returns exactly two lines — the façade `preload` and the `MEMBER_KINDS` row. Every
  other almanac mention of the three is a comment or a docstring, including
  `items/ItemDatabase.gd`'s *"See UnitProgression.get_accessory_evade"* and
  `items/EquipCandidates.gd`'s record that it *used to* reach it.
- **The publication surface.** Stripped, outside the almanac: `ExMateriaAlmanac.UnitProgression`
  41 lines in 40 files (9 `src/`, 2 `addons/`, 29 `tests/`), `ExMateriaAlmanac.GambitList`
  10 in 10, `ExMateriaAlmanac.AbilityLoadout` 5 in 5.
- **Not dynamically validated, and it does not need to be.** Nothing here was run against
  a moved tree; every number is a static read of the tree as it stands plus the guard's own
  arms. The claim being made is about what the guard WOULD print, and the guard's rules are
  in `tools/check_addon_portability.py` and `tools/_walk_roots.py`, not in a runtime.

## Rejected alternatives

- **Move `UnitProgression` alone** — ADR-0241 dec. 2's `B` membership, re-priced in the
  addon era. Retires 9, pays 10, and needs a publication ADR-0251 dec. 3 defers.
- **Move all three together.** Strictly worse: it adds `GambitList`'s nine `Gambit` lines
  (ADR-0280 dec. 2) to decision 2's ten, and `AbilityLoadout` brings no retirement at all
  because no catalogue file reaches it.
- **Split `UnitProgression` into a catalogue record and an almanac derivation layer.**
  ADR-0241 dec. 3, and the re-measurement above leaves it where it was: 41 of 52 functions
  touch a database, and all 72 reaches are static, so there is no seam to cut.
- **Publish `BaseStatsDatabase` first, then move.** This is the move buying its own
  precondition. The façade's rule is *the day a host file names it*, and the pass that adds
  that call is the pass that should choose its kind — with the call in hand as the evidence
  for the choice.
- **Keep the raw `res://` preloads after the move.** Decision 4: invisible to arm 6 by its
  predicate and to arm 5 by its shape, so it improves the census by 9 lines without
  changing a single edge.
- **Re-export the moved members from the almanac façade** so the 56 call sites do not
  change. Decision 5: that is the cycle, and it makes each addon's install closure contain
  the other.
- **Declare the three `table`** and let arm 5 free them. `MEMBER_KINDS` is read by
  `_walk_roots.member_free` and consumed by an enforcing arm; a kind is a falsifiable claim
  about what the member answers, and *"a unit's own numbers"* is not a bank.
- **Lift `UnitProgression` into the shared kernel instead**, the way ADR-0294 lifted its
  nested value sets. Blocked by ADR-0139 dec. 4(a)'s sink veto on all five database edges,
  and stated in `exmateria_schema.gd` at the row that did land.

## Soft spots

- **ADR-0280 dec. 6 read 36 and this reads 13; the 23-line difference is not audited line
  by line here.** #1180 / ADR-0294's kernel lift accounts for at least seven of them —
  `exmateria_catalogue` now names `ExMateriaSchema.{EquipSlot,BaseStatType,Zodiac}` on
  seven lines that used to reach the almanac — and ADR-0272's sprite-rig row accounts for
  two more. The decisions above do not turn on the remainder: 13 is measured from the
  guard's own output today, in both the floor claim and the arithmetic.
- **Decision 2's arithmetic is keyed on `MEMBER_KINDS` as it stands.** If a later pass
  re-kinds `StatCalculator`, the ten moves. That is the register working as designed —
  it is why the kind is declared in one place and read by the guard — but it does mean
  this ADR's number has a named dependency rather than being a fact about the file.
- **`AbilityLoadout` is the weakest of the three cases.** It has no measured catalogue
  reach, so nothing here prices its move; what blocks it is ADR-0241 dec. 1's ownership
  argument plus decision 5's publication cost. If a future pass gives the catalogue a real
  reach to it, this ADR does not answer the question that pass will be asking.
- **Decision 7 names a gap in arm 8 and does not close it.** An acyclicity arm over the
  `deps=` graph is buildable — `_walk_roots.dep_closure` already has the BFS — and it is
  not built here because there is no cycle in the tree to hold it, and #424's rule is that
  a named list is only cheap when it lands empty against a real corpus.
