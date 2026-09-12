# The catalogue's progression debt is a vocabulary, and the kernel is where a value set lives

[ADR-0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md)
dec. 6 ruled the Character Catalogue's 36 arm-5 lines *"the accepted price, not a
countdown"*, and dec. 9 (ii) left the other half of that open in the same breath: it
*"does not rule that a future pass may not pay them."* This is that pass, and it pays 23
of the 36 without moving a single class into the catalogue.

The 36 were never 36 reaches into `UnitProgression`. Read line by line they are **23 lines
that name an enum declared inside it and 13 that hold or construct the object itself** —
and ADR-0241 dec. 1 had already said so, in the sentence nobody built on: *"The residual
simulator dependency is a vocabulary, not a coupling."* A vocabulary has a home, dec. 4 of
the same ADR names it, and it is not the catalogue — quoting
[ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
dec. 10: *"`schema` is the obvious home for a vocabulary two systems share."*

So `EquipSlot`, `BaseStatType` and `Zodiac` go **down** into the shared kernel as ADR-0118
dec. 1's **twelfth** row, on exactly the route #1159 took for `UnitRole` one ticket
earlier. `UnitProgression` does not move, is not admissible, and re-exports all three, so
no call site in `src/` is respelled and the diff never touches the game.

Status: accepted (2026-09-11), on trunk `863849637`. Closes **#1180**. Reads
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 3 for the
kernel's admission gate and dec. 4 for its two vetoes,
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1 for the schema table
this ADR amends,
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 1 for the vocabulary-not-coupling finding, dec. 2 for the doubling this ADR still does
not answer, and decs. 3/4 for the two homes,
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 2 for the
install target that makes a kernel reach free,
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) dec. 4 for the alias idiom,
[ADR-0273](0273-free-ness-inside-the-rules-tier-is-declared-per-member-because-a-package-of-tables-is-not-all-tables.md)
decs. 1 and 4 for the member kinds and dec. 7 for the mutation standard,
[ADR-0280](0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md)
dec. 3 for the eleventh row this one follows, dec. 6 for the accepted price and dec. 9 (i)
and (ii) for what it left open, and
[ADR-0215](0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
dec. 2 for the one-row-many-members precedent.
**Supersedes nothing.** ADR-0280 dec. 6 stays accepted and is **narrowed by its own dec. 9
(ii)** rather than reversed — see decision 7.

## Context

`addons/exmateria_catalogue/` is the one addon in the tree that cannot be installed
standalone. `check_addon_portability.py` arm 5 prints its cross-addon `class_name` reaches
in two blocks: a FREE block, for reaches into a tier `_walk_roots.PORTABLE_TIERS` declares
portable, and a DEBT block for everything else. At `863849637` the DEBT block was 36 lines
over three files, and it has been the catalogue's isolation blocker for four ADRs.

The block, reconstructed from `863849637` rather than quoted from a handoff:

| file | member | code lines |
|---|---|---:|
| `identity/Character.gd` | `GambitList` | 4 |
| `identity/Character.gd` | `UnitProgression` | 25 |
| `identity/UnitBirthdays.gd` | `UnitProgression` | 2 |
| `seeding/AllTemplatesSeeder.gd` | `UnitProgression` | 5 |
| | | **36** |

Arm 5 counts **lines inside `addons/` only** — `src/` is not walked — so every number in
this ADR is an addon-to-addon count and none of them is a count of how much of the game
uses these names. The game's use is measured separately in decision 2, because the ADR-0118
row has to name the systems the payload crosses between, and arm 5 cannot see them.

⚠ **The instrument is `strip_noncode`, and a docstring mention is not a line.**
`Character.gd:150` reads *"Map a job + authored gender to a `UnitProgression.BaseStatType`"*
and is invisible to the census. Counting by `grep` gives 25/3/2 where the guard gives
25/2/5; the three-line difference is two prose mentions and one `[UnitProgression]` doc
link. Every table below is the guard's reading, re-taken for this ADR.

## Decision

**1. The 36 lines are 23 of vocabulary and 13 of object, and only the 13 are coupling.**
Split by what the line actually names:

| what the line names | code lines |
|---|---:|
| `UnitProgression.EquipSlot.*` | 16 |
| `UnitProgression.BaseStatType.*` | 4 |
| `UnitProgression.zodiac_from_birthday` / `.Zodiac` | 2 |
| `const UnitProgression = …` in `UnitBirthdays.gd`, whose only use is the line above | 1 |
| **vocabulary** | **23** |
| `const UnitProgression`, `var progression: UnitProgression`, `UnitProgression.new()`, one parameter type | 9 |
| `GambitList` — held and constructed, ADR-0280 dec. 2 measured its move at +5 | 4 |
| **the object itself** | **13** |

A line that reads `UnitProgression.EquipSlot.HEAD` does not use `UnitProgression`. It uses
a five-member enum that happens to be declared inside it, and it would read identically if
the enum were declared anywhere else. Sixteen of the 36 are that one enum. This is
ADR-0241 dec. 1's finding — *"12 of `Battle`'s 13 are enum access — `UnitProgression.EquipSlot.*`
and `UnitProgression.BaseStatType.*` … The residual simulator dependency is a vocabulary,
not a coupling"* — measured again on the catalogue side, where it turns out to be 23 of 36
rather than 12 of 13.

🔴 **THE REMAINING 13 ARE REAL AND THIS ADR DOES NOT PAY THEM.** `Character` holds a
`UnitProgression` field and constructs one on three lines; `AllTemplatesSeeder` returns
one. That is a genuine object dependency and no vocabulary lift touches it. It is left
standing deliberately, and decision 7 says under whose authority.

**2. `EquipSlot`, `BaseStatType` and `Zodiac` are admitted to the shared kernel as ADR-0118
dec. 1's TWELFTH row.** The payload is *the value vocabulary a unit's progression is
described with* — **which slot a piece of equipment occupies**, **which base-stat curve a
unit grows on**, **which zodiac sign it was born under**. A caller of one of these learns a
**value set**, not a contract: no ordering, no invariant, no error mode. That is the tenth
row's own test (ADR-0215 dec. 2), and these three pass it for the same reason `Facing` did.

| Schema | From, to |
|---|---|
| the **unit progression vocabulary** | the `rules` tier (`UnitProgression` declares them), to `Character Catalogue` (seeds and serialises them), `Battle` (`src/units/Unit.gd`, `src/gpu/`), `UI` (`src/ui3/detail/`, `src/ui3/formation/`), `Audio` (`src/audio/SfxRouter.gd` picks a voice bank off the body type) and `Cutscene` (`src/scenarios/PromotedRosterSeeder.gd`) — the **twelfth** |

ADR-0118 dec. 1 carries the amendment block, in the shape ADR-0164, ADR-0196, ADR-0215 and
ADR-0280 each added one. It is the **second** row whose producer is the `rules` tier rather
than a system, ADR-0280 dec. 3's being the first.

🔴 **A FILE MOVE CANNOT DO THIS, WHICH IS WHY THIS IS AN ADR AND NOT A COMMIT.** ADR-0139
dec. 3 sets the admission test as membership in a named published schema: a file enters the
kernel when it realises a row of ADR-0118 dec. 1's table and by no other route. Its last
sentence is the whole of it — *"A file move cannot do it."* Two of these three members did
not even exist as files before this pass; they were enums nested in a 1,000-line `Resource`.
The row comes first, then the files.

ADR-0139 dec. 4's two mechanical vetoes, per member, by inspection rather than by assertion:

| member | lines | outbound edges | autoload |
|---|---:|---:|---|
| `unit_vocabulary/EquipSlot.gd` | 41 | **0** — no `preload`, no `load`, names no identifier it does not declare | no; `extends RefCounted` |
| `unit_vocabulary/BaseStatType.gd` | 37 | **0** — same | no; `extends RefCounted` |
| `unit_vocabulary/Zodiac.gd` | 93 | **0** — the month table is a literal `Array`, and `zodiac_from_birthday` reads only it | no; `extends RefCounted` |

`BaseStatType` is the one worth stating rather than waving through, because its **table is
not here and must not come.** `progression/BaseStatsDatabase.gd` holds the growth curves and
`progression/StatCalculator.gd` applies them; both name a `JsonAsset` and both would fail dec.
4(a)'s sink veto the moment they tried to follow. What crosses is the three-member *label*,
not the numbers it indexes — and that is the whole distinction dec. 4(a) exists to draw.

🔴 **THREE MEMBERS, ONE ROW, AND THAT IS A RECORDED CHOICE RATHER THAN A COUNT.** ADR-0196
gave the cell marking its own row beside the terrain cell, so the precedent for splitting
exists. It is not followed here for ADR-0215 dec. 2's reason: these are one vocabulary —
one decision, one directory, one README section, one `plugin.cfg` sentence — and three of
the eleven existing rows would have to be re-cut before a per-enum rule was consistent.

**3. `UnitProgression` re-exports all three, so not one call site is respelled.** ADR-0211
dec. 4's alias idiom, doubled because each kernel member is a *file* holding an *enum*:

```gdscript
const EquipSlotVocab = ExMateriaSchema.EquipSlot
const EquipSlot = EquipSlotVocab.Slot
```

Every `UnitProgression.EquipSlot.HEAD`, `.BaseStatType.MALE` and `.Zodiac.ARIES` in the
tree resolves exactly as before. **`src/` is not touched by this change at all** — 8 files
and 33 lines across `Battle`, `UI`, `Audio`, `Cutscene`, `assembler` and `Debug` were in
scope for a respelling and none of them needed one. ADR-0217 dec. 7 paid 61 alias
declarations to move four enums because the kernel published no names; this pass pays
**six**, because the producer that owned them is still there to forward them.

This is not a courtesy. A vocabulary lift that respells hundreds of call sites is a
different change with a different risk profile, and it would make the arm-5 delta
unreadable — the census would move for two reasons at once.

🔴 **THE IDIOM CARRIES A CONST AND AN ENUM, AND IT DOES NOT CARRY A STATIC FUNCTION.**
`zodiac_from_birthday` is `static`, and GDScript resolves a static call against the
declaring script rather than through a `const` alias, so `UnitProgression.zodiac_from_birthday(…)`
stops parsing the moment the function leaves the file. **One** call site in the tree was
still spelled that way — `tests/ZodiacFromBirthdayTest.gd` — and it moved to the kernel
spelling. Zero `src/` sites were affected, because the catalogue was this function's only
production caller and it moved with the lift.

The limit is recorded because it is invisible to every Python guard in the repo: arm 5
reads 426 / 13 either way, and `check_addon_portability.py` does not parse GDScript. What
found it was `godot --path . -e --quit`, the project-wide parse sweep, run before the
suite. A vocabulary lift that moves a `static func` must sweep; one that moves only enums
need not, and this pass could not tell which it was until it swept.

**4. `zodiac_from_birthday` travels with the enum, because it is a `table` and not a
`rule`.** ADR-0273 dec. 4's kinds turn on whether an answer is stored or computed. The
function is a 12-row lookup over `const _ZODIAC_MONTH`, FFT's own sign boundaries written
out: delete the function and the whole answer is still sitting there in the array. It
computes nothing the ROM computes, so it is not a `rule`, and a `table` that ships with its
own vocabulary is what every other kernel member already looks like — `UnitRole` carries
`get_role_name`, `get_all_roles` and `matches` for the same reason.

The boundaries were validated against four known units before the move rather than after:
Ramza 12/30 → Capricorn, Agrias 6/22 → Cancer, Delita 3/18 → Pisces, Algus 5/11 → Taurus.

⚠ **`Zodiac.zodiac_from_birthday` stutters, and it is left stuttering.** The kernel's naming
convention is `<Subject>.gd` holding `enum <Kind>`, so the call site reads the subject twice.
`UnitRole.get_role_name` set that precedent one ticket earlier and ADR-0196's title is the
standing rule — *a respelling is never the reason*. Renaming it would put a second variable
in a change whose whole value is that its measurement is readable.

**5. `AbilitySlot` does not travel, and that is measured rather than deferred.** #1123 lifted
`EquipSlot` and `AbilitySlot` together as a pair and ADR-0280 dec. 9 (i) calls that lift
*"preparation and not approval"*. Only one of the pair is admissible here.
`addons/exmateria_almanac/abilities/AbilitySlot.gd` has **zero namers outside the almanac
and `tests/`**. It crosses no boundary, so it realises no row, so ADR-0139 dec. 3's gate
refuses it — not on taste, on the gate's own terms. It stays in the almanac until something
outside the almanac names it.

**6. The move is DOWN into the kernel, and that is what makes it not #1059 phase 3.** This
needs saying explicitly or a reader arrives at the right conclusion by accident, or the
wrong one on purpose.

ADR-0280 dec. 9 (i) leaves open *"whether `UnitProgression` and `AbilityLoadout` move to the
Character Catalogue"* — a move **up**, from the `rules` tier into a system, which is the
question ADR-0241 dec. 2's unanswered 4-names/45-lines against 9/85 measurement governs.
Nothing here moves toward it:

| | #1059 phase 3 | this ADR |
|---|---|---|
| what moves | `UnitProgression`, the class | three enums declared inside it |
| where to | `exmateria_catalogue`, a system | `exmateria_schema`, the shared kernel |
| direction | a `rules` member becomes a system's | a `rules` member's vocabulary becomes everyone's |
| who may depend on the result | the catalogue's consumers | anyone; ADR-0202 dec. 2 puts the kernel in the install target, so the reach is free |
| what gates it | ADR-0241 dec. 2, unanswered | ADR-0139 dec. 3, answered in decision 2 |
| the catalogue's 13 residual lines | would go to 0 | unchanged |

`EquipSlot.gd`'s own docstring at `863849637` carried the objection, and it prices a
*different* move: *"🔴 LEFT INLINE, THE MOVE WOULD HAVE INVERTED A DECLARED DEPENDENCY."*
That is true of a move **up** into the catalogue, which would make the almanac depend on a
system that depends on it. The kernel inverts nothing — no tier depends on the kernel's
consumers, which is the property ADR-0139 exists to protect. The objection is recorded as
answered-for-this-destination rather than deleted, in the file's rewritten docstring.

`tools/test_check_addon_portability.py`'s `TierDeclarationTests` docstring separately rejects
three other routes to the same number — widening `PORTABLE_TIERS`, adding a `rules`
exemption, and moving `UnitProgression` itself. None is taken here. The 23 lines are paid by
the payload crossing a boundary legitimately, which is the only route that leaves the census
meaning what it meant before.

**7. The authority to pay these lines is ADR-0280 dec. 9 (ii), and dec. 6 survives intact.**
Dec. 6 ruled the 36 *"the accepted price, not a countdown"* against two consecutive handoffs
that had read it as a target of zero. That ruling is not weakened by this pass — it is
**confirmed by it**, because 13 lines are left standing with no plan to remove them and no
ticket that treats them as owed. Dec. 9 (ii)'s exact words are the licence: *"Whether the
catalogue's 36 lines should ever reach zero. Decision 6 rules them the accepted price; it
does not rule that a future pass may not pay them."* A line paid because its payload turned
out to belong somewhere else is not a countdown being run down; it is a misfiling being
corrected, and the 13 that remain are the evidence of the difference.

**8. The census reads 426 free / 13 debt, and the two sides do not match on
purpose.** The free side rose by 18 where the debt side fell by 23, and a reader who expects
those to be the same number will read a 5-line leak that is not there. Three distinct
mechanisms, each measured:

| effect | free lines |
|---|---:|
| the 23 debt lines re-home to **7** — an alias declaration is ONE line however many use sites it serves (`Character.gd` 19 → 4, `UnitBirthdays.gd` 2 → 2, `AllTemplatesSeeder.gd` 2 → 1) | +7 |
| `UnitProgression.gd`'s re-export block, decision 3 — six lines that did not exist at `863849637` | +6 |
| `items/EquipCandidates.gd` becomes VISIBLE — it named `EquipSlot` through a same-addon `preload`, so it was in NEITHER block; the same five use sites now name a sibling addon | +5 |
| | **+18** |

The third is arm 5 acquiring sight of a dependency it previously could not see, and it is the
one worth flagging: a census that grows because the instrument improved is not a regression,
and the reverse case was recorded at #1160, where the free side FELL for the same class of
reason.

🔴 **`UnitBirthdays.gd` LEAVES THE DEBT BLOCK ENTIRELY, AND THAT IS WHY THE RESIDUE IS 13
AND NOT 14.** Its `const UnitProgression` alias existed to serve one call,
`zodiac_from_birthday`. The call now names `Zodiac`, so the alias has no remaining use and
is deleted rather than kept. This is the only file in the three to go to zero.

Per ADR-0273 dec. 7 the register is proved by mutation and not by a green guard. The control
that was **32** is now **9**: declaring `UnitProgression` a `table` moves arm 5 by **+9 free /
−9 debt** (426 / 13 → 435 / 4) where before the lift the same word moved 32. The residue of
**4** is the positive control — `GambitList` is untouched `state` and stays printed under every
mutation, so the 9 is a real 9 and not an instrument that stopped looking. Declaring
`UnitProgression` a `rule` still moves **nothing**, 426 / 13.

The mutation arms state the **delta** and not the pair, because #1168 made the free side a
single named constant read back out of the report: a literal per arm redded on any legitimate
`ExMateriaSchema.` line anywhere in the walk, which is a treadmill and not a guard. The 9 and
the 13 are this decision's claims; 426 is a live count of the tree and is named once.

**9. What this ADR does NOT decide.**

- **(i)** Whether `UnitProgression` or `AbilityLoadout` move to the Character Catalogue.
  That is #1059 phase 3 and ADR-0241 dec. 2's measurement is still unanswered. Decision 6 is
  the whole of what this ADR says about it: this is a different move in the opposite
  direction, and it is neither preparation for phase 3 nor an argument against it.
- **(ii)** Whether the catalogue's remaining 13 lines should ever reach zero. Decision 7
  leaves ADR-0280 dec. 6 standing over them, unamended.
- **(iii)** Whether `AbilitySlot` may later join the twelfth row. Decision 5 refuses it on a
  measurement that a single outside namer would overturn, and the row is written to hold it
  without another amendment if one appears.

## Considered alternatives

- **Widen `_walk_roots.PORTABLE_TIERS` to include `rules`.** Rejected, and already rejected
  in `TierDeclarationTests`' docstring. It takes the debt block to zero by declaring the
  question closed rather than answering it, and it is the mutation the guard runs as a
  CONTROL — the arm would be scoring its own control as a pass.
- **Add a `rules`-tier exemption for `UnitProgression` specifically.** Rejected on the same
  ground, one file narrower. ADR-0273 already built the principled version of this — per-member
  kinds — and `UnitProgression` is declared `state` there for reasons this pass does not touch.
- **Move `UnitProgression` into the catalogue.** That is #1059 phase 3, gated by ADR-0241
  dec. 2, and decision 6 is a whole table on why it is a different change. It would take the
  residue to 0 and the `src/data/` address question to the top of the queue.
- **Lift only `EquipSlot`, the 16-line member.** Coherent and declined. The three enums are
  one vocabulary by decision 2's own argument, the marginal cost of the other two is 4 files
  and 4 alias lines, and splitting the pass would leave `Character.gd` reaching
  `UnitProgression` for `BaseStatType` — the debt block would read 20 and the next reader
  would have to re-derive the whole finding to see why.
- **Respell the call sites instead of re-exporting.** Rejected by decision 3. ~33 `src/`
  lines and every `tests/` site, for no measurement change, in a pass whose value is that its
  delta is attributable.
- **Give each enum its own ADR-0118 row.** Rejected by decision 2's recorded choice. It has a
  precedent (ADR-0196) and it would make three of the existing eleven rows inconsistent.

## Consequences

- The shared kernel gains three code members. `addons/exmateria_schema/unit_vocabulary/` now
  holds nine files; the façade publishes 15 members where it published 12.
- `addons/exmateria_catalogue/plugin.cfg` declares `exmateria_schema` in its `deps` for the
  first time, and the sentence *"Nothing here reaches `exmateria_schema`"* is deleted as
  false.
- The almanac's published register is **unchanged** — `EquipSlot` was never published on the
  façade, so `MEMBER_KINDS` does not move and ADR-0273's 18/12/3 split is untouched. The
  member COUNT falls 36 → 35 and the published count 33 → 32, which is `EquipSlot.gd` leaving
  the directory and nothing else.
- `tools/classify_blueprint.py` loses its exact rule for `items/EquipSlot.gd`; the
  `addons/exmateria_schema/` prefix rule derives the bucket now. `Battle` −1 file, `schema`
  +1. `abilities/AbilitySlot.gd` keeps its exact rule, per decision 5.
- `tools/test_check_addon_portability.py` is re-pinned on the sides that are claims: the
  debt literal 36 → 13, the widening arm's delta 36 → 13, the mutation control's delta 32 → 9,
  and the `..._by_exactly_32` arm renamed `..._by_exactly_9`. The free side is NOT re-pinned
  per arm — #1168 collapsed it to the single `PERMITTED` constant, bumped here 408 → 426 and
  RE-READ from the guard's own report on the rebased tree rather than carried over from this
  branch's pre-rebase 424. Two legitimate lines landed in between; keeping 424 would have been
  a fabricated number. The dated history lines (`371 -> 373 AT #1120`, `373 -> 408 AT #1159`,
  `408 -> 406 AT #1160`) keep their OLD numbers — they are records of what a tree read, not
  readings of this one.

## Soft spots

- 🔴 **`BaseStatType`'s ordinals are stored data.** `UnitProgression.base_stat_type` is an
  `@export`, so `MALE`/`FEMALE`/`MONSTER` are written as 0/1/2 into every saved Resource on
  disk. The enum is moved with explicit `= 0` / `= 1` / `= 2` so a future reorder is a
  deliberate act rather than a diff artefact, and the file's docstring says so. The same is
  true of `Zodiac.Sign`, which is `@export`ed as an `int` and pinned 0..12.
- The row names **five** consumers and arm 5 can see one of them. Everything outside
  `addons/` in decision 2's row is a `grep` of `src/`, not a census reading, because the
  census does not walk `src/`. If that count is wrong it is wrong in the direction of
  undercounting — a `preload` route would be invisible to it.
- 🔴 **AND THE ROW OMITS TWO BUCKETS THAT REACH THESE NAMES.** `src/scenes/ProgressionTester.gd`
  and `src/scenes/GambitScenarioBoot.gd` are `assembler`, and `src/debug/UnitAnimationViewerPanel.gd`
  is the debug surface — 17 more code lines. They are left out because an ADR-0118 dec. 1 row
  names the **systems** a payload crosses between, and the assembler is what wires systems
  together rather than one of them. That is a reading of the table's shape, not a measurement,
  and a reader who thinks the assembler belongs in a row should add it rather than re-derive
  the decision: nothing in decisions 1 through 8 turns on the count.
- Decision 5's zero for `AbilitySlot` is a `grep` over `src/` and the sibling addon roots. It
  is a real zero rather than a blind one only because the same instrument finds 33 lines for
  `EquipSlot` and `BaseStatType` in the same sweep, which is the positive control.
- Decision 1's 23/13 split is the guard's reading of `863849637` and is reconstructed in this
  ADR rather than quoted from the guard, because the guard no longer prints those lines. The
  reconstruction is checkable: 4 + 25 + 2 + 5 = 36, and the residue the change actually
  produces is 4 + 6 + 3 = 13, which is the prediction the pass was built against.
