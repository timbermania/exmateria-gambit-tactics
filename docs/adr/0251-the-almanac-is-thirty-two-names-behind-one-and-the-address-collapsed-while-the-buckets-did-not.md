# The almanac is thirty-two names behind one, and the address collapsed while the buckets did not

[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
ruled the scope and deliberately left the design at the address to this pass
(its dec. 12, and [#945](https://github.com/timbermania/fft-monorepo/issues/945)'s
six items). The move is built.

**It opens with an EMPTY arm-6 burn-down and an EMPTY arm-7 burn-down, which no
extracted addon in this repo has done before** — and both were earned by a
DELETION rather than declared away, one per arm. ADR-0243 dec. 4 predicted one
arm-6 row and one arm-7 row and said *"No extracted addon has ever opened this
clean"*; the real answer is one better than the prediction on both arms, because
in each case the thing crossing the boundary turned out to be dead or already
re-implemented on the host side.

Two of #945's six items did not survive contact. The `~36 src/data/` rows in
`classify_blueprint.py` do **not** collapse to one directory rule (dec. 7), and
ADR-0243's three-way `BattleConditionalOpcode` severance had a fourth answer it
did not consider (dec. 5).

Status: accepted (2026-09-06). Builds
[#945](https://github.com/timbermania/fft-monorepo/issues/945) and
[ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 12. Reads
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md)
dec. 1/2/4 and
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 for the façade,
[ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md) dec. 1/2 for
asset travel and the `ls` test,
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)
dec. 2/3 for naming the directory after the fact and for the collapse precedent,
[ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md)
dec. 8 for the port,
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 3/7
for the rig and the engine declaration,
[ADR-0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md) dec. 8 and
[ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md) for the
`RIGS` join, and
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 7 for
the codec rule this addon's `StatusRegistry` still sits outside. Corrects three
counts in ADR-0243 (dec. 6) and refuses one of #945's six items (dec. 7); leaves
every ADR-0243 decision otherwise standing.

## Context

### What the pass inherited, and what it had to decide

ADR-0243 closed membership, destination and `UnitProgression`'s home. What it
explicitly did not close, in its own words, was *"the addon's name and
subdirectory layout, the folder-named facade over 31 bare globals, the ~36
`src/data/` rows in `classify_blueprint.py` that collapse to one directory rule,
`tools/generate_ability_database.py`'s hardcoded output paths, which severance
`BattleConditionalOpcode` gets"*.

The façade is the piece that dominated: `class_name` is engine-global in Godot 4,
so an addon's every `class_name` lands in its consumer's global scope whether the
consumer asked for it or not (ADR-0211 dec. 1). Thirty-one was described as
*"the largest such surface in the package by a wide margin"*. It is thirty-two,
and the count is the first thing this pass corrected.

### The two deletions

Both burn-down registers opened empty because two lines that ADR-0243 booked as
unavoidable boundary crossings turned out not to be load-bearing at all. Neither
was found by argument; both were found by counting occurrences.

`encounters/BattleConditionalDatabase.gd` carried, before this pass:

```gdscript
const OP_RUN_SCENARIO := BattleConditionalOpcode.RUN_SCENARIO
```

`BattleConditionalOpcode` is a Campaign type, named 34 times by Campaign and once
by the tier, which is why ADR-0243 dec. 7 refused to move it and offered three
severances instead. The fourth answer is that the constant is **dead**: two
occurrences repo-wide, its own declaration and ADR-0243's quotation of it. The
records this class serves carry `run_scenario` as a resolved integer field —
`tools/export_battle_conditionals.py` consumes the opcode while decoding
`BTLEVT.BIN`, so nothing downstream of the JSON ever compares against the opcode
value.

`status/StatusRegistry.gd` carried a `SHADER_PATH` into
`res://src/gpu/shaders/combat_common.glslinc` and parsed it, at static-init time,
to assert its `STATUS_*` bits had not drifted from the GPU's. ADR-0243 dec. 8
recorded that removing the registry from the membership was *measurably worse*,
and it is — but that was a question about the CLASS, not about the PATH. The
parity assertion was already re-implemented in full by
`tests/StatusRegistryTest.gd::_test_shader_parity`, on the host side, where the
shader is.

## Decision

**1. The addon is `addons/exmateria_almanac/`, `class_name ExMateriaAlmanac`, and
the name is a compromise that the README states outright.** Eight subdirectories
named for the fact each holds — `abilities/`, `encounters/`, `gambits/`,
`items/`, `jobs/`, `progression/`, `sprites/`, `status/` — so ADR-0146 dec. 2's
`ls` test is answerable at the root.

The name was chosen against two better-fitting alternatives and one worse one.
**Twenty-two of the thirty-two members are ROM tables or projections of them**,
for which `exmateria_rom_tables` or `exmateria_records` would be exact. **The four
`gambits/` members are not**: `Gambit`, `GambitList`, `GambitCondition` and
`TargetSelector` are an original FFXII-style AI design this project invented, and
nothing in Final Fantasy Tactics has them. A ROM-named package would make a false
claim about a fifth of its own contents, which is the opposite of ADR-0184 dec.
2's *"name the directory after the fact"*. An almanac is a book of tables you look
things up in: true of the ROM tables, true of the gambits, and claims nothing
about provenance. `exmateria_schema` and `exmateria_platform` were ruled out as
destinations by ADR-0243 decs. 1–2 and are not alternatives here.

🔴 **This is the one decision in the pass settled by taste rather than by
measurement, and it is the cheapest one to reverse** — a `git mv` plus one
identifier substitution, with the façade making the second half a single name.

**2. Thirteen JSON payloads travel with their readers, one beside each database
that reads it — not twelve.** ADR-0243 dec. 4 and dec. 8 both say twelve;
`ItemDatabase` carries two, `items.json` and `item_attributes.json`. They are
2.9 MB of the addon's 3.7 MB and they sit in the subdirectory of the database
that loads them rather than in a shared `data/`, so a member and its payload are
one `ls` apart.

🔴 **The stranger rig is the only instrument that can prove they travelled.** A
payload left behind in `assets/` is not a parse error, produces no arm-6 row (the
path moved with the reader), and no static guard in `tools/` would see it — the
addon would install and load and then come up empty-handed at runtime, in a
project that is not this one. See dec. 9.

**3. One published name, thirty-one published constants, and members reach each
other by PATH.** `addons/exmateria_almanac/exmateria_almanac.gd` declares the
addon's only `class_name` and publishes 31 of the 32 members as
`const X = preload(...)`. This is ADR-0211 dec. 1/2 and ADR-0212 dec. 1's rule,
carrying more weight here than it has anywhere: **31 published is the largest
façade surface in the repo**, against `exmateria_sprite_rig` 20,
`exmateria_sound` 18, `exmateria_battlefield` 17 and `exmateria_render` 1.

- **Outward**, a host writes `const JobDatabase = ExMateriaAlmanac.JobDatabase`
  once per file (the ADR-0211 dec. 4 alias) and every use site below keeps its
  spelling. That is **270 alias lines across 134 host and test files**, and it is
  what makes `grep -rn ExMateriaAlmanac` a complete census of host→addon symbol
  coupling — the measurement a bare `class_name` makes impossible.
- **Inward**, members never reach through the façade; a member reaching its own
  package through its own published surface would make the addon depend on what
  it exports. A `preload` const is a full type: it annotates, `is`-checks and
  `.new()`s exactly as the deleted `class_name` did. Self-typed statics use
  `const _Self = preload("<own path>")`.
- **One pair forms a `preload` cycle**, which is a parse error and not a warning:
  `JobDatabase` ↔ `JobCandidates`. The back edge is the only runtime `load()` in
  the package, at `jobs/JobDatabase.gd:148`, with the reason at the line.

**`progression/BaseStatsDatabase.gd` is the one member that is shed but NOT
published**, because zero files outside the addon name it: it is read only by
`StatCalculator` and `UnitProgression`, its own siblings. Thirty-two moved;
thirty-one are reachable. `check_addon_globals.py`'s CREEP/ROT/CITE arms are
seeded with `FACADES["exmateria_almanac"] = "ExMateriaAlmanac"` and an **EMPTY**
`BURN_DOWN` — the first addon whose burn-down was seeded empty in the same commit
that created the directory.

**4. The shader parity check leaves the addon, and arm 6 opens EMPTY.**
`status/StatusRegistry.gd` loses `SHADER_PATH`, `static var _shader_verified` and
`_verify_against_shader()` entirely. The assertion now lives only in
`tests/StatusRegistryTest.gd::_test_shader_parity`, which already re-implemented
it in full.

The test's copy is **the stronger instrument**, not a fallback: it `_expect`s and
FAILs, where the registry's copy could only `push_error` from a static
initializer that fires at most once per boot and that nothing asserts on. And the
fact is a HOST fact about a host shader — `combat_common.glslinc` is 1,511 lines
of Battle's GPU kernel — so the host's test is where it belongs. ADR-0243 dec. 8
is upheld on its own question (the CLASS stays; removing it is measurably worse)
and superseded on the PATH.

**5. `OP_RUN_SCENARIO` is DELETED, which is the fourth answer to a three-way
question.** ADR-0243 dec. 7 offered an ADR-0211 dec. 4 alias, an inline with a
generated-enum citation, or one `ARM7_BURN_DOWN` row with an owner — *"that
register's third row ever"*. The constant had two occurrences repo-wide and no
caller had ever read it. Deleting it costs nothing, needs no owner, and is what
lets arm 7 open at **zero**. The fact it encoded (that `run_scenario` arrives
already resolved) moved into the class docstring, where a future reader looking
for the opcode will find why there is none.

🔴 **A three-way question with a live premise is still a false trichotomy if
nobody counted the occurrences.** The three severances were all correct answers
to *"how does this class name a Campaign type"*; none of them is an answer to
*"does it"*.

**6. Three of ADR-0243's counts are corrected.**

| | ADR-0243 | measured |
|---|---:|---:|
| `class_name`s in the membership | 31 | **32** |
| JSON payloads that travel | 12 | **13** |
| hand-written lines moved | (24,111 quoted flat) | **4,490** |

The 31 is the arithmetic that matters: it coincidentally equals the *published*
count, so the two numbers agree in the ADR by accident. `BaseStatsDatabase` is the
thirty-second, and it is shed without being published (dec. 3). The 24,111 is not
wrong, it is misleading — ADR-0243's own soft spots already flag it — and the
package's real shape is 24,484 lines under the root of which **19,689 are two
generated files** and 305 are the façade and `plugin.gd`.

**7. The address collapsed; the buckets did not. #945's item 5 is REFUSED, on
measurement.** The ticket asked for the ~36 `src/data/` rows in
`classify_blueprint.py` to become one directory rule on ADR-0184 dec. 3's
precedent. Measured, that cannot be had, for three independent reasons:

1. **`check_blueprint_walk.py` check 4 runs a two-way `content` ↔ store rule over
   exactly this population.** Booking the whole addon `content` would need a
   ~20-name exemption set — the blanket exemption that check's own comment
   refuses.
2. **Booking it anything else re-books nineteen files whose consumers did not
   change**, which is #744's rule one directory over: a bucket is who consumes a
   file, and no consumer stopped consuming.
3. **A new bucket would invalidate the frozen baseline.** `check_baseline.py`
   check 2 requires `BASELINE.tsv`'s `other` rows to equal
   `classify_blueprint.OTHER` exactly, so a seventh `OTHER` bucket forces a
   re-freeze of `data_sha256` for an addressing convenience.

So the thirty-two exact rules were **re-addressed** to
`addons/exmateria_almanac/<dir>/`, buckets unchanged — 2 `generated`, 11
`content`, 5 `UI`, 12 `Battle` — plus two new `Battle` rows for
`progression/UnitProgression.gd` and `abilities/AbilityLoadout.gd`, which held
`Battle` through the `src/units/` prefix rule they no longer match, and two
`infrastructure` rows for the addon's own plumbing.

**What the collapse was FOR is still had.** Its purpose was that a file added to
the addon cannot arrive unclassified and unnoticed. There is deliberately no
catch-all rule under this root either, so a new file books `UNCLASSIFIED` and
`classify_blueprint.py` exits non-zero (check 1) until someone decides what it is.

**8. The generator moves with its output.**
`tools/generate_ability_database.py` writes `abilities/AbilityDatabase.gd`
(19,418 lines) and `abilities/AbilityView.gd` (271) and its `ADDON_DIR` now points
inside the addon. Both templates lost their `class_name` line and gained the
intra-addon `preload` consts dec. 3 requires, kept in one `PRELOAD_BANNER`
constant beside `ADDON_RES` rather than spelled inline per template, so the two
files' paths move together. `--check` is the witness that the checked-in files
match what the generator writes today, and it is clean.

**9. `tests/stranger/exmateria_almanac/` is the sixth rig, `engine="stock"`, and
this is the first addon to arrive AFTER the join that would have caught its
absence.** `plugin.cfg` declares `engine="stock"` (the addon ships 32 `.gd` and
zero shaders, `.gdshaderinc`, `.tres` or scenes; every member `extends
RefCounted` except `UnitProgression`, which extends `Resource`) and
`deps="exmateria_platform"` (the 11 `ExMateriaPlatform.JsonAsset` lines, which are
the PORT ADR-0223 dec. 8 books as a conformant residual, not debt).

`_walk_roots.RIGS` gained its row **in the same commit as the addon root**.
`exmateria_sprite_rig` was the fifth in-walk addon for three days with no rig and
no ticket, found by noticing a missing `[PASS] stranger:` line; `rigs()` arm 2 now
RAISES when an addon root has no row and arm 3 raises when a `run.sh` exists that
no row names, and arm 3's own docstring had already named this case in the
abstract as *"the sixth rig landing without a row"*.
`tests/stranger/README.md`'s 🔴 paragraph saying nothing detects a missing rig is
rewritten rather than re-dated: something detects it now.

**10. The payoff is 49.5%, measured on one tree before and after with one
instrument, and the prediction was a floor that the real number cleared from
below by 1.5 points.** ADR-0243 dec. 9 predicted 758 → 372 (−51%) for arm-7 debt
across the six unextracted systems and its own soft spot called that *"a
PREDICTION that `check_baseline.py --delta` settles"*.

Re-taken with `tools/arm7_membership.py`, same script, same six memberships, trunk
`448a08502` against this branch:

| system | before | after | predicted after |
|---|---:|---:|---:|
| `Battle` | 172 | **46** | 45 |
| `UI` | 322 | **127** | 127 |
| `Cutscene` | 107 | **103** | 90 |
| `Character Catalogue` | 79 | **32** | 32 |
| `Campaign` | 59 | **57** | 57 |
| `Effects` | 25 | **21** | 21 |
| **total** | **764** | **386** | 372 |

By declaring directory: `src/data/` **330 → 0**, `src/units/` **74 → 26**,
`src/debug/` 202 unchanged, `src/scenarios/` 87 unchanged, everything else 71
unchanged.

⚠️ **The `before` column here is NOT ADR-0243's middle column and the difference
is not drift.** ADR-0243 held the membership constant by removing the tier's files
from both sides, so `Battle` and `UI` read *higher* before; this takes each
system's files as `classify()` books them on each tree, which on trunk puts the
tier's files INSIDE `Battle` and `UI` and makes their references internal. The two
methods answer different questions and only the `after` column is comparable. Four
of the six `after` rows reproduce the prediction exactly; `Cutscene` +13 and
`Battle` +1 are the gap, and `Cutscene` was already drifting from ADR-0241 dec. 7
(15 names / 92 lines) to 20 / 107 on trunk before this branch existed.

`check_baseline.py --delta` against the same pair: **cross-system reaches
819 → 694, −125.** `Battle`'s inbound falls 191 → 66 and `UI`'s outbound
257 → 167.

**11. `tools/test_arm7_membership.py`'s ADR-0241 calibration is RE-PINNED, not
deleted, and two of its four deltas are now ZERO.** The instrument ADR-0243 dec.
11 built is pinned by two calibrations; the second is ADR-0241 dec. 2's four
hand-applied memberships, and **it was a claim about a tree that this extraction
changed** — the same shape as a guard's hardcoded directory surviving a move.
Measured on this tree:

| membership | ADR-0241 dec. 2 | now |
|---|---:|---:|
| A — `src/characters/` + `AllTemplatesSeeder` | 4 / 45 | **0 / 0** |
| B — A + `UnitProgression` | 9 / 85 | **0 / 0** |
| C — `classify()`'s fourteen | 8 / 79 | **4 / 32** |
| D — C + `UnitProgression` | 13 / 119 | **4 / 32** |

`UnitProgression.gd` is inside an addon now, so arm 7's own predicate filters it
and **adding it to a membership costs nothing**. `B == A` and `D == C` are not a
defect in the test; they are ADR-0243 dec. 6's *"dissolves rather than being
answered"* stated as an equality, and the test asserts the equality directly
rather than only the two numbers. The historical values stay in the docstring
because the ADRs quoting them are the record of why #5 was the tier.

🔴 **Row A is a live input to the next selection.** ADR-0241 dec. 5 rejected
Character Catalogue as extraction #5 on *"45 lines over 4 names at best-case
membership"*. That membership now reaches nothing outside an addon root.
Whoever selects #7 should re-read dec. 5 against this row and not against the
number it quotes. Row C independently reproduces dec. 10's `Character Catalogue`
79 → 32 by a different route — `sysof` bucketing there, `arm7` directly here.

## Considered alternatives

**`exmateria_rom_tables` / `exmateria_records`** — exact for 22 of 32 members and
false for the four `gambits/` ones, which are an original design. Rejected on dec.
1's argument, and recorded in the README so the compromise is visible from inside
the addon.

**A `data/` subdirectory holding all 13 payloads** — rejected; it separates a
database from the file it loads and answers the `ls` test worse than putting each
payload beside its reader.

**Publishing all 32, including `BaseStatsDatabase`** — rejected. Publishing a name
nothing outside the addon uses is a surface with no consumer, and the
CITE arm would have nothing to cite for it. It is reachable by path from inside,
which is where it is read.

**Aliasing or inlining `OP_RUN_SCENARIO`, or booking it in `ARM7_BURN_DOWN`** —
all three ADR-0243 dec. 7 offered, all three rejected once the occurrence count
came back at two (dec. 5). A burn-down row in particular buys an owner and a
ticket for a line no code executes.

**Keeping `_verify_against_shader()` and booking one `ARM6_BURN_DOWN` row** —
ADR-0243 dec. 4's own expectation. Rejected: the assertion is duplicated on the
host side already and the host's copy is stronger, so the row would have bought
a weaker instrument at the cost of the arm.

**One directory rule in `classify_blueprint.py`** — #945 item 5, rejected on three
independent measurements (dec. 7). The strongest of the three is
`check_blueprint_walk.py` check 4, which would have gone **silently blind**: it
was scoped to `src/data/*.gd`, would have found one file left, reported OK and
stopped asserting the store rule over 11 stores; and its `is_store` predicate's
`res://assets/**.json` regex would have returned False for every moved database.
Both were widened in this pass, which is the same class of defect as a guard's
hardcoded directory surviving a move.

## Consequences

- One new global name in every consumer's scope where there were thirty-two.
  270 alias lines is the price, and `grep -rn ExMateriaAlmanac` is what it buys.
- `addons/exmateria_almanac/` is the largest addon root by bytes (3.7 MB, 2.9 MB
  of it JSON) and reports under `(NO FORMAT RULE)` in `tools/asset_census.py`
  alongside all six other addon roots. No `FORMAT_OWNER` entry was added, because
  adding one for this root and not the other six states a rule the package does
  not hold.
- `check_baseline.py --delta` reads `TOTAL (systems)` **+331 lines** across this
  branch. A pure relocation would read 0. The 331 are the alias lines and the
  docstrings this pass authored; the moved files kept their buckets (dec. 7) so
  their lines never left the systems' totals in the first place.
- `docs/RESIDUE.tsv` regenerated: its derived-roots header gains
  `addons/exmateria_almanac`, and two files' line counts move because they gained
  alias blocks. Two of its four drifting rows were already stale on trunk.
- ADR-0243's soft spot that *"`AbilityCandidates` reaches `AbilityLoadout._SLOT_TYPE`,
  a PRIVATE member"* is no longer a boundary concern: both are members, so the
  reach is intra-addon. The coupling itself is unchanged and still unfixed.
- `tools/check_addon_portability.py`'s shader-global heading said *"five stranger
  rigs"*; corrected to six.

## Soft spots

- 🔴 **The name is a taste call and nothing measures it — so it was PUT to the
  owner, and confirmed.** dec. 1 states the compromise honestly rather than
  resolving it, and the compromise stands: `gambits/` is an original design, not
  a ROM table, so a strictly accurate name would be false about a quarter of the
  subdirectories. The name was raised with the repo owner on 2026-09-07 before
  the merge, with the reversal cost stated (a `git mv` and one substitution then;
  136 files and a published API after), and `exmateria_almanac` was confirmed.
  The underscore spelling matches all eight sibling addon directories. This is
  recorded because *confirmed by the person with standing* is the only evidence
  this decision can have — no instrument will ever score it.
- **`StatusRegistry` is still a codec whose counterpart cannot travel**, which
  ADR-0139 dec. 7 and ADR-0146 dec. 7 do not cover. dec. 4 moved the ASSERTION
  out; the underlying case that a codec's two halves are in two packages is
  recorded and unresolved, exactly as ADR-0243 dec. 8 left it.
- **dec. 10's `before` column is a second reading of a table ADR-0243 took a
  different way**, and the ADR-0147/0148 warning about second readings of the
  same set applies to it. The `after` column and the `check_baseline --delta`
  pair are the load-bearing numbers; the `before` column is context.
- **`Cutscene` reads 103 where the prediction said 90** and this pass did not
  chase the 13. It is the one row where the floor was cleared by more than one
  line, and the trunk drift from ADR-0241 dec. 7's 92 accounts for at least part
  of it.
- **The 270 alias lines are a census only while they are the ONLY route.** A host
  file that ever writes `preload("res://addons/exmateria_almanac/...")` directly
  would be invisible to the grep dec. 3 claims as a complete census.
  `check_addon_globals.py`'s CITE arm reads the façade's citations, not the
  hosts', so nothing enforces it today.
