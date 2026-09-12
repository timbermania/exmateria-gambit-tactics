# `UnitProgression` is the catalogue's by ownership and `src/data/`'s by address, so extraction #5 is a tier and not a system

Three ADRs in a row named `Character Catalogue` the strongest next candidate and
deferred the same objection — ADR-0141's *"a store reaching the simulator is
backwards, and settling that is a boundary question the pass would have to answer
before it could start."* ADR-0213 dec. 8 asked for it to be grilled **before** the
#5 pass rather than inside one, on ADR-0157 dec. 8's ground that *"it does not
belong inside a pass"*.

Grilled. **The objection has an answer, the answer is not the one either side
expected, and settling it does not unblock the extraction.** `Battle` already
declares `UnitProgression` foreign in its own type annotations — `Unit.gd` types
the field `Resource`, preloads the class by path, and its comments say the object
*"outlives this node"* and is *"shared with the roster entry"*. So the store is
not reaching into the simulator; the simulator is holding an injected record it
does not own. Ownership is the catalogue's and it is not close.

**And ruling it that way makes the extraction worse, measurably.** Applying
`check_addon_portability` arm 7's predicate to the proposed addon membership: with
`UnitProgression` left behind, a `Character Catalogue` addon names **4** classes
declared outside every addon root on **45** lines; with `UnitProgression` moved in,
it names **9** on **85**. The class is a rules object over five `src/data/`
databases on 56 lines of static access with no injection point, and moving it
drags `StatCalculator` and `AbilityType` to the boundary as well — two names no
cross-bucket instrument could see, because they are `Battle`-booked and so were
internal to `Battle` on both sides of the edge.

That is the finding, and it generalises. **`src/data/` and `src/debug/` are 70.8%
of all arm-7 debt across the six unextracted systems — 528 of 746 lines — and
neither is a system.** `TuneField` alone is 170 lines, 22.8% of the total, one
class. The method's OUT column cannot see any of it: OUT counts reach into other
members of `SYSTEMS`, and `content`, `generated` and `Debug` are buckets. Three
selection surveys ranked `Character Catalogue` first on a column that was blind to
the thing blocking it.

Status: accepted (2026-09-06). Answers
[ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
dec. 8's request and closes the deferral opened by
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) and
carried by [ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
dec. 8. Reads [ADR-0126](0126-every-system-pass-audits-before-it-designs.md) for the
pass split, [ADR-0117](0117-the-blueprints-ten-systems.md) for `SYSTEMS`,
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 5 for the unit, [ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
for arm 7 and [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
for the free set. Leaves every decision any of them made standing.
Tickets: files [#930](https://github.com/timbermania/fft-monorepo/issues/930) for the
`src/data/` tier's scope pass; closes nothing.

## Context

### The table, re-measured on trunk `153e360bf`

Reproduced rather than quoted, with `uv run python tools/touch_matrix.py` and
`uv run python tools/classify_blueprint.py` from `godot-learning/`.

⚠️ **Taken twice, nineteen commits apart, and the boundary did not move.** First at
`d84fbdb0e`, where every OUT and inbound cell matched the handoff's reading of
`a2e7a95df` exactly; then again at `153e360bf` after nineteen commits landed
(ADR-0235–0237 and ADR-0239, all `engine`/`Battle`). **The matrix is
byte-identical across all three readings — 807 cross-system lines, every cell —
and so is every arm-7 figure in this ADR.** Only three size cells moved: `Battle`
78 → 80 files and 24,609 → 25,516 lines, `UI` 141 → 142 and 41,863 → 42,198,
`Effects` 58,103 → 58,112. The table below is the later reading. A system can gain
907 lines without gaining a single crossing, which is what the OUT ÷ size column is
for.

| system | files | lines | OUT | OUT ÷ size | inbound |
|---|---:|---:|---:|---:|---:|
| `Effects` | 191 | 58,112 | 6 | 0.010% | 25 |
| `Debug` | 21 | 3,702 | 5 | 0.135% | 415 |
| `Battle` | 80 | 25,516 | 57 | 0.223% | 184 |
| `Cutscene` | 58 | 17,599 | 66 | 0.375% | 29 |
| `UI` | 142 | 42,198 | 160 | 0.379% | 4 |
| `Character Catalogue` | 14 | 2,141 | 41 | **1.915%** | 26 |
| `Campaign` | 10 | 1,721 | 54 | 3.138% | 38 |

⚠️ **`Audio` reads OUT 3, not 0.** ADR-0213's own table says so and the handoff
that opened this session flattened it to *"all reading OUT 0"*. The control arm at
OUT 0 is `Render`, `Battlefield` and `Sprite Rig`; `Audio`'s three residual lines
are `src/audio/SfxRouter.gd` naming `UnitProgression`, host-side residue left
behind by ADR-0153's package rather than an addon. It matters here only because
those three lines are the same name this ADR is about.

### The handoff's pivot number is wrong in both halves

The session handoff stated **37 of 41 outbound lines are one name**, by file:
28 `Character.gd`, 6 `AllTemplatesSeeder.gd`, 3 `UnitBirthdays.gd` — and flagged
its own number as a grep rather than the instrument. Re-derived with the
instrument, from `tools/.touch_cache.json` which `touch_matrix.py` writes on every
run:

```
24  class_name  UnitProgression   src/characters/Character.gd
 6  class_name  Unit              src/debug/ProgressionDebugPanel.gd
 4  class_name  UnitProgression   src/scenarios/AllTemplatesSeeder.gd
 3  class_name  GambitList        src/characters/Character.gd
 1  class_name  UnitProgression   src/characters/UnitBirthdays.gd
```

**29 of 41, not 37 — and no per-file figure matched.** The gap is comments and
string literals: `strip_noncode` blanks both, and `Character.gd`'s three
`UnitProgression` mentions in its own docstring are exactly the kind of line this
repo's documentation density manufactures.

### The system is not the fourteen files the handoff describes

The handoff says *"14 files, all in `src/characters/` plus
`src/scenarios/AllTemplatesSeeder.gd`"*. `classify()` books **five of the fourteen
under `src/debug/`** — `BattleBindingDebugPanel`, `ProgressionDebugPanel`,
`RosterDebugView`, `RosterUniverseDebugPanel`, `RosterViewDebugPanel`, together
744 lines, **35% of the system's 2,141**. They are why the OUT cell reads `UI` 2
and why 6 of the 38 `Battle` lines are `Unit` rather than `UnitProgression`. Any
addon membership has to rule on them, and no prior survey noticed they were there.

### The instrument that decides this is not the matrix

`touch_matrix.py`'s OUT is *reach into another member of `SYSTEMS`*. ADR-0213
states the exclusion — *"with `platform`, `schema` and `Debug` excluded from the
outbound count"* — and the omission of `content` and `generated` is not stated
because they are not columns at all.

`tools/check_addon_portability.py` **arm 7** asks the question the matrix cannot:
*a `class_name` declared OUTSIDE every addon root*, ENFORCING for every subject,
`ARM7_BURN_DOWN` deliberately **empty**. It carried five rows for two days in
September and both were discharged by moving the class — `JsonAsset` to the
platform port, `AnimationNames` into the rig with a host-injected content root —
never by excusing it.

Against arm 7's predicate the three extracted addons are clean and their only
outbound reaches are `platform` and `schema`: `Battlefield` 23 + 26, `Sprite Rig`
12 + 13, `Render` 2. **No extracted addon reaches `content` or `generated` on a
single line.** That is not a rule anyone wrote down; it is what three extractions
produced, and arm 7 is the guard that keeps it.

## Decision

**1. `UnitProgression` is the catalogue's, and `Battle`'s own source says so.**
The deferred objection is answered in the direction ADR-0141 suspected, on
evidence that was in the tree the whole time.

`src/units/Unit.gd` — the simulator's own unit node, and the file with the most
`UnitProgression` mentions in the codebase at 33 raw lines — holds it like this:

```
var unit_progression: Resource = null  # UnitProgression (a Resource shared with the roster entry; bound or minted)
func bind_progression(progression: Resource, unit_team: UnitStats.Team, mov_speed: float = 3.0) -> void:
```

The field is typed `Resource`. The parameter is typed `Resource`. The class is
reached by `preload("res://src/units/UnitProgression.gd")` rather than by symbol.
The docstrings say *"a Resource shared with the roster entry"*, *"The progression
Resource is shared/persistent and outlives this node"* and *"SAME progression
object, so menu/combat edits persist with no copy-back"*. Every one of those is a
statement that the object is owned elsewhere and injected.

`src/characters/Character.gd` is where it is owned, and its own class docstring
(which cites ADR-0066 for the model, not for these words) says so three times:

```
## A Character = identity, the catalog record above the battle roster (ADR-0066).
...
## It also holds refs to the durable *functional* objects the codebase already
## has (`UnitProgression`, `GambitList`); those are optional in this prefactor
## slice (issue #158) and get populated as Forms/Profiles land.
##
## This is the thing a live `Unit` is spawned from and that dialogue + scenario
## actors point at — never itself the in-scene node.
```

It is also the constructor: every `UnitProgression.new()` outside the simulator's
own standalone path is in this file.

Measured, code-only, with `strip_noncode` applied so the comparison is the
instrument's unit: `Character Catalogue` **29** lines, `Battle` **13**, `UI` 9,
`assembler` 9, `Audio` 3. And **12 of `Battle`'s 13 are enum access** —
`UnitProgression.EquipSlot.*` and `UnitProgression.BaseStatType.*`. Exactly one
line in the simulator types against it:
`src/gpu/GPUCombatPacker.gd:786  static func _get_evade_breakdown(prog: UnitProgression, is_magic: bool) -> Dictionary`.
`Unit.gd`'s 33 raw lines collapse to 3.

The residual simulator dependency is a vocabulary, not a coupling, and `Unit.gd`
already carries the idiom that dissolves it: two blocks of `const X =
ExMateriaSpriteRig.X` / `ExMateriaBattlefield.Lattice` aliases at the top of the
file, ADR-0211 dec. 4's façade pattern, for two addons it already consumes.

**2. And the ruling does not unblock the extraction — applied, it doubles the
debt.** This is the decision that matters, and it is why three deferrals bought
nothing.

Arm 7's predicate over each proposed addon membership, on trunk `153e360bf`
(names declared outside every addon root, counted in code lines, names internal to
the moving set excluded):

| membership | arm-7 names | lines |
|---|---:|---:|
| **A.** nine `src/characters/` + `AllTemplatesSeeder` files | **4** | **45** |
| **B.** A + `UnitProgression` | **9** | **85** |
| **C.** all fourteen classified files | 8 | 79 |
| **D.** C + `UnitProgression` | 13 | 119 |

A is `UnitProgression` 29, `JobDatabase` 12, `GambitList` 3, `SpriteDatabase` 1.
B trades the 29 for `JobDatabase` 25, `ItemDatabase` 21, `StatCalculator` 10,
`AbilityDatabase` 9, `JobLevelsDatabase` 8, `BaseStatsDatabase` 5, `AbilityType` 3.

**`StatCalculator` and `AbilityType` are the reason a cross-bucket instrument
could not have found this.** Both are declared in `src/data/` and both are booked
`Battle`, so `UnitProgression` naming them is an intra-bucket reach that
`touch_matrix.py` does not record in either direction. They surface only when you
ask arm 7's question — *what address does this name resolve to* — of a membership
that does not exist yet. `StatCalculator.grow_stat` is the FFT growth formula on
`level_up`'s critical path; `AbilityType.from_string` gates all three ability
slots.

**3. The class is one tier, not two, and it does not split.** The obvious escape
from dec. 2 is to keep a durable record in the catalogue and leave a derivation
layer in the simulator. Measured against the file, that split does not exist. Of
53 functions, **41 touch a database**, and they are not the derived-stat getters —
`_initialize_from_base_stats` reads `BaseStatsDatabase`, `level_up` and
`change_job` read `JobDatabase`, `add_jp` reads `JobLevelsDatabase`,
`learn_ability` reads `AbilityDatabase`. Only 12 functions are database-free, and
they are accessors over dictionaries the other 41 populate. All 56 database calls
are **static class access** — `JobDatabase.get_job(...)` — so there is no
injection point to cut at either.

**4. `UnitProgression`'s address is `src/data/`, and that is not in conflict with
dec. 1.** Ownership and address are different questions, and fusing them is what
made this look unanswerable for three passes. The catalogue *owns* the record: it
constructs it, it holds the reference, it decides its lifetime. But a rules object
over five ROM databases belongs beside the databases, not inside a consumer — and
`Character Catalogue`, `Battle`, `UI`, `assembler` and `Audio` all consume it, five
buckets, not two. Moving it *down* leaves every one of them naming it inbound;
moving it *sideways* into the catalogue leaves four of them reaching across.

This is the shape ADR-0213 dec. 10 already named for `DisplayActivity`: *"`schema`
is the obvious home for a vocabulary two systems share"*. One tier further out,
because a rules object is not a vocabulary.

**5. `Character Catalogue` is not extraction #5, and the ground is measured rather
than deferred.** At best-case membership A it opens with 45 lines of arm-7 debt
over 4 names, against `Battlefield`'s 9 and `Sprite Rig`'s 6 — and unlike those
two, none of it is severable by the pass. `UnitProgression` needs a tier that does
not exist; `JobDatabase` and `SpriteDatabase` are `content`; `GambitList` is
`src/data/`. Three of its four names are in one directory the catalogue does not
own. **The rejection this time carries no deferred question**: dec. 1 rules the
one that was outstanding, and it is the tier build that is owed, not another
grilling.

**6. `Effects`' deferral is re-ratified, and on evidence rather than on its
citation.** ADR-0157 dec. 9 and ADR-0213 both defer `Effects` as *"scheduled last
by `docs/agents/refactor-loop.md` → *Extraction order*"* because wayfinder map
**#262** is live on that tree. ⚠️ **That citation no longer resolves** — there is
no *Extraction order* section in `docs/agents/refactor-loop.md` today, and no
occurrence of `Effects` in it that schedules anything.

The reason survives its citation. Measured: **#262 is OPEN, its declared scope is
`godot-learning/src/effects/studio/`, and that subtree is 116 of `Effects`' 191
files and 40,623 of its 58,112 lines — 70% of the system — with 355 commits since
2026-08-01.** `Effects` has by far the cleanest boundary in the package (4 arm-7
names on 25 lines, and 18 of those 25 are `TuneField`/`BaseDebugPanel`, leaving
**7**), and it stays deferred anyway. The deferral is now recorded against the map
rather than against a heading.

**7. `Campaign`, `Cutscene`, `Battle` and `UI` are rejected, and their arm-7 debt
is why.** Arm 7's predicate over each system's own files:

| system | arm-7 names | lines | largest |
|---|---:|---:|---|
| `Effects` | 4 | 25 | `TuneField` 15 |
| `Campaign` | 8 | 59 | `BattleConditionalOpcode` 34 |
| `Character Catalogue` | 8 | 79 | `UnitProgression` 29 |
| `Cutscene` | 15 | 92 | `TuneField` 37 |
| `Battle` | 17 | 169 | `ItemDatabase` 40 |
| `UI` | 29 | 322 | `TuneField` 70 |

`Campaign` also still carries ADR-0157 dec. 11's live `src/world_map/` collision,
unchanged. `Battle` is the hub at 184 inbound lines. `UI` is the largest debt in
the package by a factor of two.

**8. Extraction #5 is the `src/data/` tier — a third shared bucket, not a
system.** Across all six unextracted systems, arm-7 debt sorts by the directory
the name is declared in:

| declared under | lines | share |
|---|---:|---:|
| `src/data/` | 326 | **43.7%** |
| `src/debug/` | 202 | **27.1%** |
| `src/scenarios/` | 82 | 11.0% |
| `src/units/` | 67 | 9.0% |
| everything else | 69 | 9.2% |
| **total** | **746** | |

Two directories are **70.8%** of every remaining extraction's portability debt and
neither is a member of `SYSTEMS`. `TuneField` is 170 lines by itself — more than
any system's total outbound — and it is one 491-line editor widget in `src/debug/`.
`ItemDatabase` 78, `JobDatabase` 67 and `AbilityDatabase` 61 are the next three.

Selecting a bucket rather than a system is **precedented and not novel**: both
addons an extracted system is permitted to name were built exactly this way.
`exmateria_schema` is ADR-0139's kernel and `exmateria_platform` landed at
extraction #3's pass 6 (ADR-0184). Neither was ever a member of `SYSTEMS`; each was
created because the systems above it could not be moved otherwise. That is the
situation now, one tier out, and `src/data/` is 31 files / 23,069 lines of which
19,677 are two generated files.

**9. What this ADR does NOT decide.** Pass 1 selects; pass 3 designs (ADR-0126).

- **The tier's shape.** Whether `src/data/`'s databases extend `exmateria_schema`,
  join `exmateria_platform`, or take a third addon of their own. Its four
  buckets (`Battle` 12 files, `content` 12, `UI` 5, `generated` 2) do not move as
  one and the split has to be ruled before anything moves.
- **Where `UnitProgression` lands inside that tier**, and whether the five static
  database calls stay static or become injection. Dec. 4 rules the address; it does
  not rule the shape at the address.
- **`TuneField` and `BaseDebugPanel`.** 202 lines, 27.1% of the debt, and `Debug`
  is method-excluded from OUT everywhere — so this is a second tier question,
  possibly the same one. ADR-0234 already built `TunePort` in `exmateria_platform`
  for the autoload half; `TuneField` is the editor-widget half and it never moved.
- **The five `src/debug/` files `classify()` books to `Character Catalogue`.**
  Whether they ship, stay, or re-book.
- **Whether `Character Catalogue` becomes #6.** After the tier lands its membership-A
  debt falls to `GambitList` 3 and whatever the tier does not absorb. That is a
  measurement to take then, not a promise now.

## Considered alternatives

- **Rule `UnitProgression` into `Character Catalogue` and open the #5 pass on it.**
  Rejected on dec. 2's measurement: 4 names / 45 lines becomes 9 / 85, and two of
  the new names were invisible to every cross-bucket instrument. The ruling is
  right about ownership and wrong about address, and a pass that acted on the first
  half alone would have found the second half on day one.
- **Rule it into `Battle` and take the 29 lines as the catalogue's shipping debt**,
  on ADR-0184's precedent that `Battlefield` was chosen with nine measured outbound
  lines and an arm-1 burn-down to carry them. Rejected: `Battlefield`'s nine were
  severable by its own pass and these are not — the burn-down would carry a row
  that no work inside `Character Catalogue` can ever discharge, which is the shape
  ADR-0184's own comment says a named list exists to prevent.
- **Split `UnitProgression`.** Rejected in dec. 3 by measurement, not preference:
  41 of 53 functions touch a database and the database calls are on `level_up` and
  `add_jp`, not only on the derived-stat getters.
- **`Effects`, on its boundary.** It is the cleanest in the package by a factor of
  eight and this ADR does not dispute that. Rejected in dec. 6 on the live map, now
  sized at 70% of the system.
- **Defer the selection and ship only the ruling.** Rejected. ADR-0213 dec. 8 is
  the third ADR to defer, and a fourth would land on the same table the fifth would
  read. The measurement that rejects `Character Catalogue` also names its
  replacement, so there is nothing left to defer to.
- **Widen the OUT column to count `content` and `generated`.** Rejected as the
  wrong instrument: arm 7 already asks the question, it is already enforcing, and
  its burn-down is already empty by design. A second register describing the same
  set is what ADR-0146 dec. 5 warns about. What the OUT column needs is a caveat,
  which dec. 8's table supplies.

## Consequences

- **`Character Catalogue`'s blocking objection is closed.** ADR-0141's sentence,
  carried by ADR-0157 dec. 8 and ADR-0213 dec. 8, is answered in dec. 1 and is no
  longer an open question against any future selection. Any ADR that re-opens it
  is re-opening a ruling, not inheriting a deferral.
- **A selection survey that reads only OUT is now known to be blind**, and dec. 8's
  by-directory table is the reading that is not. The next pass-1 ADR should state
  arm-7 debt beside OUT rather than instead of it — they answer different
  questions and `Character Catalogue` is the case where they disagree by 5x.
- **`Effects`' deferral is recorded against map #262 and its measured overlap**,
  so the next survey can re-test it by looking at one issue and one subtree instead
  of chasing a heading that no longer exists.
- The `docs/agents/refactor-loop.md` *Extraction order* citation in ADR-0157 dec. 9
  and ADR-0213's alternatives is **dangling and is left standing** — historical
  records keep their spelling (ADR-0240 dec. 7); dec. 6 supplies the live reading.

## Soft spots

- **S1. The arm-7 numbers are the predicate applied by hand to a membership that
  does not exist, not the guard run on a real addon.** `outbound_reaches` walks an
  addon directory, so there is no way to run `check_addon_portability` against a
  hypothetical. The predicate is reproduced faithfully — `class_name` kind, target
  declared outside every addon root, `strip_noncode` applied, names internal to the
  moving set excluded — but the first real run after the folder exists is the
  witness, and it can only go up: arm 6 (`res://` paths) and arm 2 (host autoloads)
  are not counted here at all.
- **S2. `TuneField` at 170 lines may make dec. 8's ordering wrong.** `src/data/` is
  43.7% and `src/debug/` is 27.1%, but a single 491-line class is 22.8% of the
  whole debt, and the cheapest first move might be that one file rather than the
  larger directory. Dec. 9 leaves it open deliberately; it is a measurement worth
  taking before the tier's pass 2.
- **S3. The line count is a FLOOR in both directions** (ADR-0131 dec. 6).
  Duck-typed reaches carry no type name and are invisible, and `Unit.gd`'s
  `progression: Resource` parameters are exactly that shape — the coupling dec. 1
  reads as *evidence of foreignness* is also coupling no instrument can count. If
  the tier's design turns those back into typed parameters the number goes up, and
  that would be the design working rather than a regression.
- **S4. Nothing here was run in Godot.** Every number is static — the classifier,
  the touch cache, arm 7's predicate and `git log`. That is the right instrument
  for a selection, and it is the wrong one for the first claim pass 3 makes about
  behaviour.
