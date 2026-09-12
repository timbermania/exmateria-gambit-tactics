# The `src/data/` tier is a third addon, and the split the selection assumed does not exist

[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 9 selected the tier and left three questions, and it stated a premise while doing
it: *"Its four buckets (`Battle` 12 files, `content` 12, `UI` 5, `generated` 2) do not
move as one and the split has to be ruled before anything moves."*
[#930](https://github.com/timbermania/fft-monorepo/issues/930) restates it verbatim.

**Measured across ten candidate memberships, the premise is false in the strongest
possible way: the whole directory is the cleanest membership available, and every
proposed split is worse than it.** Taken as one it opens at **one arm-7 line**; taken as
`content` alone it opens at 25, as `UI` alone at 27. The four buckets are `classify()`'s
reading of *who consumes each file*, and a consumer census is not a seam.

That inverts the pass. There was no split to rule, so the two remaining questions could
be answered instead of sequenced: `UnitProgression`'s home **dissolves** once the
databases travel with it, and `TuneField` is a clean second move rather than a competing
first one.

Status: accepted (2026-09-06). Answers [#930](https://github.com/timbermania/fft-monorepo/issues/930),
which is ADR-0126's pass 2 for extraction #5, and closes
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
soft spots **S1** (dec. 11) and **S2** (dec. 10). Reads
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md) for the pass split,
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1 and
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 3/4 for the
kernel's gate, [ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)
dec. 2/3 for the port's, [ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
for arm 7, [ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md) dec. 2 for
the content port, and [ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
dec. 1/7 for asset travel and the codec test. Leaves every decision any of them made
standing. Tickets: files [#945](https://github.com/timbermania/fft-monorepo/issues/945) (the
pass-3 build) and [#946](https://github.com/timbermania/fft-monorepo/issues/946) (the
`src/debug/` widget pass, extraction #6); closes nothing.

## Context

### The instrument, which is new, and the three ways it was calibrated

ADR-0241 S1 is the reason this section exists: *"`outbound_reaches` walks an addon
directory, so there is no way to run `check_addon_portability` against a hypothetical."*
Every arm-7 number in the three ADRs that led here was the predicate applied by hand.

`tools/arm7_membership.py` applies it mechanically to an arbitrary set of paths, reusing
`score_goals._tables()` and `strip_noncode` rather than re-implementing them. A fresh
instrument agreeing with nothing is a fresh instrument's opinion, so before it was used
for anything:

1. **Against the real guard, row for row including line numbers, on every addon in the
   package.** ⚠️ The obvious form of this test is **vacuous**: goal #5 is enforcing and
   `ARM7_BURN_DOWN` is empty, so every addon reads arm-7 **zero** and `0 == 0` passes
   whether the instrument works or returns nothing. Re-taken with the addon-root filter
   lifted, where the sets are non-empty — `exmateria_battlefield` **2 names / 35 lines**,
   `exmateria_sprite_rig` **2 / 19**, `exmateria_render` **1 / 1** — all equal, by name
   and by line number.
2. **Against ADR-0241 dec. 2's four hand-applied memberships**: A 4/45, B 9/85, C 8/79,
   D 13/119. All four reproduce exactly.
3. **Against ADR-0241 dec. 7's six-system table and dec. 8's by-directory table.** Every
   row reproduces exactly, both totals **746**.

`tools/test_arm7_membership.py` pins calibrations 1 and 2. Seeded by removing
`strip_noncode` from the predicate, **all eight tests fail** — the arms fire.

### No extracted addon names a single one of these classes, and the one that did was cut with a port

Two instruments, deliberately different, agree. The walk reports zero `class_name`
reaches from any of the seven addons into any of the 31 classes. A raw `grep -E` for all
31 names across `addons/` — comments included, which the walk blanks — returns 14 hits in
8 files, and **every one is prose**.

The most useful of those hits is `addons/exmateria_sprite_rig/content/ContentPort.gd`,
because it is the history:

```
## Seven call sites used to name four host content stores — `WeaponGraphicData`,
## `WeaponZeroFrames`, `JobDatabase`, `AbilityDatabase` — and every one of them was
## a pure query, so they collapse to one port the host adapts rather than four
## dependencies the addon carries.
```

One addon did reach this tier, and ADR-0203 severed it with a **port**, not by promoting
the databases into a shared bucket. That is the precedent, and it points away from the
kernel rather than towards it.

## Decision

**1. The tier does not extend `exmateria_schema`, and the kernel's own gate closes
against it twice over.**

ADR-0139 dec. 3 makes admission *"membership in a named published schema"*: *"A file
enters the kernel when it realises a row of ADR-0118 dec. 1's table, and by no other
route."* The gate is an ADR, not a directory — *"A file move cannot do it."* That table
has ten rows today and **not one of them is game content**. The nearest is **character records**, and ADR-0139 dec. 4(a) already records
that row's only code candidate failing: *"It bites immediately: `Character.gd`, the only
code candidate for the character records schema, fails with three (`GambitList`,
`UnitProgression`, `JobDatabase`)."* Two of those three are
`src/data/` files. The gate was measured against this exact tier a hundred ADRs ago and
it said no.

And the two mechanical vetoes fail independently, measured on the real files:

| ADR-0139 dec. 4 veto | `src/data/` as a whole |
|---|---|
| **(a) sink** — zero outbound edges into any system, `content` or `platform` bucket | **FAIL** — 5 edges / 20 lines (`ExMateriaPlatform` 11, `UnitProgression` 4, `AbilityLoadout` 3, `BattleConditionalOpcode` 1, one `.glslinc` const path) |
| **(b) autoload** — a member is never an autoload | **FAIL** — `SpriteRigContent` is `[autoload]` |

**2. It does not join `exmateria_platform` either, and the reason is what `platform`
already is.** ADR-0184 dec. 2 landed the port with four files, *"and the subdirectory
names are the fact each file encodes"* — pixel aspect, dither, fixed point, display.
ADR-0146 dec. 4 gives the shape: *"a display fact six buckets include."* An FFT job
table is not a display fact; it is the game.

The decisive evidence is the direction of the existing edge. **The tier already consumes
the port on 11 lines** — `const JsonAsset = ExMateriaPlatform.JsonAsset`, ADR-0211
dec. 4's alias, in ten of the twelve `content` databases. Folding a consumer into its
provider does not draw a boundary; it deletes the one that is already working, and it
would put game content behind the name every portable addon in the package is allowed to
reach.

**3. The premise is falsified: the tier moves as ONE, and every split is worse.** Ten
memberships, `tools/arm7_membership.py`, on trunk `f805ece1e`. `arm7` is names/lines
declared outside every addon root; `codeOUT` is all five shapes minus asset paths.

| membership | files | arm 7 | codeOUT |
|---|---:|---:|---:|
| `content` only | 12 | 4 / **25** | 37 |
| `content` + `generated` | 14 | 4 / **28** | 40 |
| `content` + `generated` + `UnitProgression` | 15 | 6 / **41** | 53 |
| `Battle`-booked `src/data/` only | 12 | 2 / **6** | 7 |
| `UI`-booked `src/data/` only | 5 | 7 / **27** | 27 |
| `generated` only | 2 | 2 / **5** | 5 |
| `content`+`generated`+`UI` | 19 | 5 / **33** | 45 |
| **all 31** | 31 | 3 / **8** | 21 |
| **all 31 + `UnitProgression`** | 32 | 2 / **4** | 17 |
| **the ruling, dec. 4** | 32 | **1 / 1** | **1** |

`content` alone is six times the boundary of the whole directory. The reason is
`JobDatabase` naming `UnitRole` on 22 lines: both live in `src/data/`, `classify()` books
one `content` and the other `Battle`, and a split along the buckets cuts straight through
them. **A bucket is who consumes a file. It was never a claim about where the seam is**,
and reading it as one is the same error one level down that ADR-0241 dec. 2 found when
`StatCalculator` and `AbilityType` turned out to be invisible for exactly this reason.

**4. The membership is 32 files / 24,111 lines, and it opens at one arm-7 line.**
Every `.gd` in `src/data/` except `SpriteRigContent.gd` (dec. 5), plus
`src/units/UnitProgression.gd` (dec. 6) and `src/units/AbilityLoadout.gd` (dec. 7).

| `classify()` bucket | files | lines |
|---|---:|---:|
| `Battle` | 14 | 2,670 |
| `content` | 11 | 1,299 |
| `UI` | 5 | 465 |
| `generated` | 2 | 19,677 |
| **total** | **32** | **24,111** |

What crosses, in full:

| arm | what | count |
|---|---|---:|
| **7** `class_name` outside every addon root | `BattleConditionalOpcode`, at `BattleConditionalDatabase.gd:28` | **1 line** |
| **6** `res://` code path | `StatusRegistry.gd:54` → `src/gpu/shaders/combat_common.glslinc` | **1 line** |
| **6** `res://` asset payloads | twelve `assets/**.json` the databases load — they travel (dec. 8) | 12 |
| **2** host autoloads | none | **0** |

**No extracted addon has ever opened this clean.** `Battlefield` was selected with nine
measured outbound lines and an arm-1 burn-down to carry them (ADR-0184 dec. 4); `Sprite
Rig` with six. This is one, and it is severable three ways (dec. 7).

**5. `SpriteRigContent.gd` is excluded, and it is the only file in the directory that
is.** It is not a database. It is the **host adapter** that answers
`exmateria_sprite_rig`'s `ContentPort` — the addon's own file says so
(*"`src/data/SpriteRigContent.gd` is the host adapter that ANSWERS the port"*), it is
registered by the host's `project.godot [autoload]` under the name `ContentPort.ADAPTER_NODE`
soft-binds to, and nothing names it as a symbol at all (inbound: zero).

Moving it into the tier would put the answer inside the question: the host's adapter for
one addon would ship inside another addon, and a consuming project that installs the tier
would silently acquire the rig's adapter. It stays in the host, where ADR-0203 dec. 2 put
it. Its own three sibling reaches (`WeaponZeroFrames`, `JobDatabase`, `WeaponGraphicData`)
become host→addon inbound, which is free.

**6. `UnitProgression` moves in with the tier, and ADR-0241 dec. 9's second question
dissolves rather than being answered.** The question is *"whether the five static
database calls stay static or become injection"* (#930 restates it as *"its 56 static
database calls"*; dec. 3's own measurement is **56 calls over five databases**, so the two
spellings are the same fact and dec. 9 dropped a word). It presupposed the databases
staying behind. They do not.

All five databases `UnitProgression` reads — `ItemDatabase`, `JobDatabase`,
`JobLevelsDatabase`, `BaseStatsDatabase`, `AbilityDatabase` — plus `StatCalculator` and
`AbilityType`, are in the membership. **All 56 calls become internal**, and an internal
static call is not a portability fact at all. Measured, adding the class *reduces* the
boundary: 3 names / 8 lines → **2 / 4**, because its four `UnitProgression` mentions
from inside `src/data/` stop escaping.

This is dec. 4 of ADR-0241 executing, and it is why ownership and address had to be
separated: `Character` still constructs the record and still owns its lifetime (ADR-0241
dec. 1, untouched), and the rules object sits beside the five ROM tables it is a function
of. No injection point has to be invented, and ADR-0241 dec. 3's *"there is no injection
point to cut at either"* stops being an obstacle and becomes irrelevant.

**7. `AbilityLoadout` moves in; `BattleConditionalOpcode` is the one line that does not,
and it is severable three ways.** `AbilityLoadout` (167 lines, `src/units/`) is named by
`AbilityCandidates.gd` on 3 lines — `AbilityLoadout.Slot.SECONDARY` and
`AbilityLoadout._SLOT_TYPE`, a slot vocabulary and a private member. It carries no
outbound of its own (adding it moves `codeOUT` 5 → 2) and `Battle` does not name it. In
it goes; the boundary drops to 1 / 1.

The survivor is `BattleConditionalDatabase.gd:28`,
`const OP_RUN_SCENARIO := BattleConditionalOpcode.RUN_SCENARIO` — one constant off a
**generated** enum (ADR-0059). It is **not** absorbed, and the count is the reason:
`BattleConditionalOpcode` is named 34 times by `Campaign` and once by the tier. Pulling
it in to win one line would re-address a `Campaign` type on the strength of its smallest
caller. Pass 3 picks one of: the ADR-0211 dec. 4 alias; inlining the value with its
generated-enum citation; or one `ARM7_BURN_DOWN` row with an owner — which is the
register's documented shape and would be its **third** row ever.

**8. The twelve asset payloads travel with the databases, and `StatusRegistry` stays
even though it is a codec.**

The twelve `assets/**.json` files are the databases' own content —
`assets/jobs/jobs.json` is what `JobDatabase` *is*. ADR-0146 dec. 1 already ruled this
shape when `assets/fold_layer.tres` moved with `Fold.gd`: *"Left in the host it would be
an outbound edge into the game."* They move.

`StatusRegistry` is the harder one and it is a genuine codec by the test ADR-0146
sharpened dec. 7 into, recorded in ADR-0139's amendment block — *"whether an encoding is
implemented **twice**, once per language, such that the two must agree"* — with
the parity check in the file (*"A runtime drift assertion parses the shader once and
pushes an error if any entry disagrees"*). Under ADR-0139 dec. 7 a codec's two halves
move together into the kernel. **Here they cannot**: the other half is
`src/gpu/shaders/combat_common.glslinc`, 1,511 lines of the GPU combat kernel of which
the `STATUS_*` block is one section. The shader is not a codec half that can travel; it
is `Battle`.

So `StatusRegistry` stays in the tier and its `SHADER_PATH` is the one arm-6 code row.
**Removing it is worse and that is measured** — without it the membership reads 1 name /
3 lines on arm 7, because `StatusEncoder` then names it across the boundary. A codec
whose counterpart cannot move is a case the kernel's rules do not cover, and this is the
first one; it is recorded rather than resolved.

**9. The payoff is 51% of every remaining extraction's portability debt, and it is the
number dec. 8 predicted.** Arm-7 debt for the six unextracted systems, membership held
constant on both sides, the tier treated as an addon root on the right:

| system | ADR-0241 dec. 7 | before | after |
|---|---:|---:|---:|
| `Battle` | 17 / 169 | 200 | **45** |
| `UI` | 29 / 322 | 303 | **127** |
| `Cutscene` | 15 / 92 | 92 | **90** |
| `Character Catalogue` | 8 / 79 | 79 | **32** |
| `Campaign` | 8 / 59 | 59 | **57** |
| `Effects` | 4 / 25 | 25 | **21** |
| **total** | **746** | **758** | **372** |

⚠️ **The middle column is not ADR-0241's and the difference is not drift.** dec. 7 counts
each system's own files; this holds the membership constant by removing the tier's files
from both sides, so `Battle` and `UI` — which lose 14 and 5 files to the tier — read
higher before. The left column reproduces dec. 7 exactly, all six rows, as the control.

By declaring directory, which is dec. 8's own table:

| declared under | before | after |
|---|---:|---:|
| `src/data/` | 326 | **0** |
| `src/debug/` | 202 | 202 |
| `src/scenarios/` | 82 | 82 |
| `src/units/` | 67 | 19 |
| everything else | 69 | 69 |
| **total** | **746** | **372** |

**10. `TuneField` and `BaseDebugPanel` are extraction #6, not a cheaper #5 — S2 is right
about the measurement and wrong about the ordering.** ADR-0241 S2 asked whether *"the
cheapest first move might be that one file rather than the larger directory."*

Measured, they are cleaner than anything in this pass: **zero arm-7 names between them.**
`BaseDebugPanel` (217 lines, `extends PanelContainer`) has **zero outbound edges of any
kind**. `TuneField` (491 lines, `extends RefCounted`) has exactly one dependency — the
`Tune` autoload on 35 lines — and `Tune` lives at `src/core/Tune.gd`, a **host** file, so
those 35 are arm 2's subject rather than arm 7's, which is precisely why dec. 8's arm-7
table could not see the cost. **The port for it already exists**: ADR-0234 built
`TunePort` in `exmateria_platform` for the autoload half, and the move is 35 rewrites
against a signature that is already shipped and tested.

It stays #6 for two reasons that are not cost. First, share: `src/data/` is 43.7% against
`src/debug/`'s 27.1%, and after this pass `src/debug/` is **202 of the remaining 372
lines — 54.3%**, so it becomes the unambiguous next move rather than a contested one.
Second, destination: this pass had to *rule* where the tier goes and dec. 1–2 did that,
whereas `TuneField`'s home is genuinely unsettled — an editor widget is not a PSX
platform fact, `Debug` is a system rather than a bucket (ADR-0140 dec. 1), and nothing in
the corpus says where a shared debug widget lives. **That is a selection question, and
selecting inside a pass is what ADR-0126 splits passes to prevent.**

**11. S1 is closed by `tools/arm7_membership.py`, and it is an instrument, not a guard.**
It has no pass/fail and no burn-down, so it is deliberately not a `tools/check_*.py` and
`check_guard_registry.py` correctly wants no row for it. The witness is still the real
guard on the real folder after the move, and **the number can only go up** — S1's own
sentence survives this decision unchanged. What is closed is that the next selection ADR
need not apply the predicate by hand, and that ADR-0241's four published memberships now
have a regression test.

**12. What this does NOT decide.** Pass 2 audits; pass 3 designs (ADR-0126).

- **The addon's name and its subdirectory layout.** ADR-0146 dec. 2's *`ls` test* and
  ADR-0184 dec. 2's *name the directory after the fact* both apply and neither is
  applied here.
- **The façade.** ADR-0211 dec. 1/4 and ADR-0212 dec. 1 make a folder-named brand-prefixed
  façade the rule, and 31 bare globals is the largest such surface in the package by a
  wide margin.
- **The ~36 `src/data/` rows in `classify_blueprint.py`**, which collapse to one directory
  rule on ADR-0184 dec. 3's precedent — and that decision's own warning applies: after the
  collapse the census restates where files were *put*.
- **`tools/generate_ability_database.py`**, which writes both `generated` files to
  hardcoded `src/data/` paths from two more `assets/abilities/` sources.
- **Which of the three severances dec. 7 lists is taken** for `BattleConditionalOpcode`.
- **The five `src/debug/` files `classify()` books to `Character Catalogue`**, and
  whether `Character Catalogue` becomes #7 — both inherited unchanged from ADR-0241 dec. 9.

**13. This pass found a defect in `check_adr_anchors.py`, and it is fixed here because
this ADR is the file that could not cite around it.**

`anchors_of()` reads a line beginning `##` as a Markdown heading and, if it is not
`## Decision`, turns the Decision section off. This corpus quotes GDScript, and a
GDScript docstring line begins `## ` — so **ADR-0241's own fenced quote of a
`Character` docstring ended its Decision section at decision 1.** That ADR offered
decision `1` and nothing else. Decisions 2 through 9 — the ruling, the rejections and
the deferred-questions list this pass is built on — were uncitable from any `.py` or
`.gd` in the package.

The reason nobody saw it is the same reason it matters. The guard scans `src`,
`addons`, `assets`, `tests`, `tools` and `docs`, but **excludes `docs/adr/` itself**, so
an ADR quoted only by other ADRs can lose its whole Decision section and the guard stays
green: an offer that is not made is not a failure until somebody outside the corpus
writes the citation. This ADR is that somebody.

Fixed by skipping fenced blocks in `anchors_of()`, with `tools/test_check_adr_anchors.py`
pinning it from both sides — a fence must not end a section, and a real `##` heading must
still end one, so the fix is not "stop tracking sections". Blast radius measured tree-wide
before it landed: **exactly two files move.** ADR-0241 gains decisions 2-9. ADR-0137 loses
`12` from its any-numbered set, which was `12.6  12.6  9.6` — a row of a fenced table of
camera sizes, never a section — and nothing outside `docs/adr/` addresses it.

**The second half of that blind spot is NOT closed, and is left named rather than fixed.**
ADR-0137's Decision section is prose bullets, so it offers no numbered decisions at all;
every citation against them, including five against its twelfth, is written in another
ADR and therefore unchecked. Widening the scan to `docs/adr/` is a separate change with
its own burn-down, and taking it inside a scope pass would bury it.

## Considered alternatives

- **Rule the split first, as #930 asks.** Rejected because dec. 3 measured it and there
  is no split: every partition of the directory is worse than the whole, and the worst
  one is the `content`/`Battle` line the four buckets suggest. Ruling a seam that the
  instrument says is not there would have cost the pass its best result.
- **Extend `exmateria_schema`.** Rejected in dec. 1 on the kernel's own gate — no
  ADR-0118 dec. 1 row, and both ADR-0139 dec. 4 vetoes failing on measurement. The
  temptation is real: 21 of the 31 classes are named by two or more buckets and that
  *looks* like a shared surface. But ADR-0139 dec. 2 refuted the reach threshold when it
  was proposed, and the reductio it used is that *"any admission test that ranks by reach admits
  `Debug` first and `Tune` second"*.
- **Join `exmateria_platform`.** Rejected in dec. 2. It is also the alternative that
  would have looked cheapest — the tier already names `ExMateriaPlatform` 11 times, so
  the `codeOUT` column would fall to near zero by fiat.
- **Give each consumer a port, as `ContentPort` did for the rig.** Rejected on the
  direction of travel. `ContentPort` exists because an *addon* needed host content; here
  the consumers are `Battle`, `UI`, `Campaign`, `Cutscene`, `Effects` and
  `Character Catalogue` — all still in the host, all still to be extracted. Porting each
  would build six adapters for a dependency that a single address change deletes, and
  every one of those systems would still have to name something.
- **Absorb `BattleConditionalOpcode` and open at arm-7 zero.** Rejected in dec. 7: a
  zero bought by re-addressing a 34-caller `Campaign` type on the strength of its
  one-line caller is the burn-down's own anti-pattern, priced as a headline.
- **Take `TuneField` as #5 instead.** Rejected in dec. 10, on share and on destination
  rather than on cost — it is genuinely the cheaper move and this ADR does not dispute
  that.
- **Leave `UnitProgression` in `src/units/` and let the tier name it.** Rejected on
  measurement: that is the 32-file membership's predecessor at 3 names / 8 lines against
  2 / 4, and it re-opens ADR-0241 dec. 4, which is a ruling.

## Consequences

- **ADR-0241 dec. 9's three questions are answered rather than sequenced**, and #930's
  reproduction section is superseded by `tools/arm7_membership.py`. The tier's shape is
  a third addon (dec. 1–2), `UnitProgression` lands inside it with its question dissolved
  (dec. 6), and `TuneField` is #6 with its cost measured (dec. 10).
- **A `classify()` bucket is now known not to be a seam**, and dec. 3 is the case where
  reading it as one costs 6x. ADR-0241 dec. 2 found the same error one level down for
  `StatCalculator`; this is the general form, and the next pass that reaches for the
  bucket table to plan a move should read dec. 3 first.
- **The arm-7 predicate is mechanical and regression-tested.** Any future selection ADR
  quoting a hypothetical membership can be reproduced with one command, and ADR-0241's
  own four numbers now fail loudly if the classifier moves under them.
- **A codec whose counterpart cannot move is an unruled case** (dec. 8). ADR-0139 dec. 7
  and ADR-0146 dec. 7 both assume both halves can travel. `StatusRegistry` is the first
  member of a category that has no rule, and it is left in the tier with one arm-6 row
  rather than having a rule invented for it inside a pass.
- **After this lands, `src/debug/` is 54.3% of all remaining portability debt** and the
  next selection has one obvious subject for the first time in the loop's history.

## Soft spots

- **S1. Nothing has moved, so nothing has been run.** Every number here is static — the
  classifier, arm 7's predicate and the five-shape scan. ADR-0241 S1's sentence carries
  forward unchanged and is not weakened by dec. 11: **the first run of
  `check_addon_portability.py` against the real folder is the witness, and it can only go
  up.** The instrument closes the reproducibility gap, not the reality gap.
- **S2. The 24,111-line figure is dominated by one generated file** —
  `AbilityDatabase.gd` is 19,411 of it, 81%. Every ratio in this ADR that uses lines of
  *source* rather than lines of *reach* is distorted by it, and the honest size of the
  hand-written tier is **4,434 lines**. The arm-7 and arm-6 counts are unaffected; the
  "largest single relocation" framing would be.
- **S3. `AbilityCandidates.gd` reaches `AbilityLoadout._SLOT_TYPE`, a private member.**
  dec. 7 moves the class in and the reach becomes internal, which makes a real coupling
  invisible to every instrument rather than fixing it. It is named here so pass 3 can
  decide whether it wants a public accessor; the boundary number does not care either
  way, which is exactly the problem.
- **S4. The line count is a FLOOR in both directions** (ADR-0131 dec. 6, ADR-0241 S3).
  Duck-typed reaches carry no type name, and `Unit.gd`'s `progression: Resource`
  parameters are that shape. If pass 3 turns them into typed parameters the count goes
  up, and that is the design working.
- **S5. The payoff table in dec. 9 treats the tier as an addon root without one
  existing**, which is the same hypothetical S1 covers, applied six more times. The
  `-386` is a prediction. `check_baseline.py --delta` after the move is what settles it,
  and ADR-0146's calibration shot is the precedent for expecting the prediction to be
  exact and for treating any residue as instrument error.
