# A reach has a bucket and an address, and goal #5 only ever read the bucket

- **Status:** Accepted
- **Date:** 2026-09-03
- **Constrains:** ADR-0139 dec. 9 / dec. 12, ADR-0148, ADR-0151, ADR-0175 dec. 2,
  ADR-0184 dec. 4, ADR-0202 dec. 2, ADR-0205 dec. 7

## Context

### Goal #5 read `met` for a system with five unreported host reaches

`score_goals.py` scores goal #5 — *portable systems* — from
`outbound_reaches(addon_rel, system)`, and `check_addon_portability.py`'s arm 1 reads the
same function so that *"a reach"* has one definition in the package (ADR-0151).

`outbound_reaches` returned `(rel, kind, target, dst, [lines])`, where **`dst` is
`classify()`'s BUCKET**. `record()` computed the resolved target path, looked up
`d = sysof[dst_path]`, keyed the row on `d` — and threw the path away. It then dropped
every row where `d` was not one of the eleven systems.

Those are two different questions and only one of them was askable:

| question | what answers it | who needs it |
|---|---|---|
| **budget** — is the target's system one of the eleven? | the bucket | goal #5, arm 1 |
| **boundary** — does the target resolve outside every addon root? | the **path** | arms 3, 6, and the arm that did not exist |

`classify()` is a budget oracle, and it was the only oracle in the function. So
`exmateria_sprite_rig` printed `0 cross-system reach lines leave the addon`, `met`, while
five lines named a type declared in `src/`:

| site | symbol | declared in | bucket |
|---|---|---|---|
| `content/SpritePaletteResolver.gd:52` | `JsonAsset` | `src/data/JsonAsset.gd` | `infrastructure` |
| `layers/AnimationResolutionMap.gd:89` | `JsonAsset` | " | " |
| `layers/WeaponAnimationSelector.gd:55` | `JsonAsset` | " | " |
| `sequence/AnimationDatabase.gd:104` | `JsonAsset` | " | " |
| `viewer/SequenceViewer.gd:271,316` | `AnimationNames` | `src/data/AnimationNames.gd` | `content` |

A `class_name` is a global the **project's** script-class cache mints by scanning the
project. A file naming one declared in `src/` parses only where the host is — arm 5's
sentence exactly, and arm 5 cannot say it, because `class_name_homes()` is built from the
addon roots alone and a type declared in `src/` is in no map it reads.

### Widening the bucket filter is the obvious fix and it is wrong

Relaxing `if d and d in SYSTEMS` to accept every bucket yields **30 rows tree-wide, and 25
of them target `addons/exmateria_platform/`** — because `classify()` books the port's own
files `platform`. Reaching the port is what a portable addon is *allowed* to do (ADR-0139
dec. 12, ADR-0202 dec. 2), so a bucket-keyed widening reds the two addons that already
paid. `platform` names a TIER and a BUCKET (#575). The budget filter is correct where it
is used; it is simply not a boundary test and cannot be made into one.

### The boundary question has six shapes and five already have an owner

Measured tree-wide 2026-09-02, over all seven addon roots, with the addon-root prefix rule
arm 6 already uses: **eight rows leave every addon root.** Three are somebody's, one is not
a row, and five are unreported.

| shape | rows | owner |
|---|---|---|
| `autoload` | 1 (`SpriteLayerManager.gd:121,811` → `Tune`) | arm 2, standalone-parse DEBT |
| `const path` | 1 (`audio_engine.gd:28` → `res://assets/music/WAVESET.WD`) | arm 6, `ARM6_BURN_DOWN` |
| `preload` | 1 (`trace_writer.gd:82`) | **nobody, and correctly** — it is `load("res://...")` inside a `#` comment. `outbound_reaches` matches `preload`/`load` against the RAW line; arm 6 strips comments and does not see it |
| `class_name` → sibling addon | 0 outside the roots | arm 5 |
| `class_name` → host | **5** | **nobody** |
| `#include` | 0 | arm 3 |

## Decision

**1. `outbound_reaches` returns `Reach(rel, kind, target, dst, dst_path, lines)` — a
NamedTuple, and the arity is the point.**
Every consumer unpacks positionally. A bare 6-tuple lets an un-updated one read `dst_path`
where it expected `lines`, and `score_goals`' own `n = sum(len(h[4]) for h in hits)` is the
case that would **not** have raised: `len()` of a path string counts characters and returns
a plausible number. Exactly three consumers exist —
`check_addon_portability.py`, `score_goals.py`, and the probe `seed_platform_outbound.py`.

**2. `record()` keeps every reach that LEAVES THE ADDON; each consumer applies its own
filter.**
Adding the field is not enough. Keyed on the bucket, a row whose target classified outside
the eleven was not kept unscored — it was **dropped**, so returning the path would have
surfaced nothing. The exclusion inside `record()` is now `dst_path.startswith(inside)` and
nothing else. `score_goals.cross_system()` is the eleven-systems filter, named once and
applied by all three consumers, so the two production readings do not move.

**3. A scanner change that moves a burn-down is indistinguishable from debt being paid
(ADR-0205 dec. 7), so decision 2 ships under a NOTHING-MOVES gate.**
Goal #5's rendered line for every addon and `check_addon_portability`'s complete output are
captured before the change and diffed after. **Byte-identical, or decision 2 is wrong.**

**4. Arm 7 is arm 5's rule one level out: a `class_name` under an addon root declared
OUTSIDE every addon root. ENFORCING, for every subject.**
It sits before arm 1's `continue` for arm 6's reason — the question is the address, so it
needs no classifier verdict and no standalone project, and the kernel and the port are
scanned too. The predicate is arm 6's `^addons/[^/]+/` against `dst_path`, not a bucket.

**5. Arm 7's universe is the `class_name` shape alone.**
Not a filter over rows (#424) — a scope over shapes, which is what `_ARM6_REFERRERS`
already does when it subtracts the four shader suffixes because arm 3 owns them. This
file's own words: *"scanning shaders here prints one defect twice under two headers."*
The other five shapes are reported by arms 2, 2b, 3 and 6, each with the right stripper.

**6. Rows ship NAMED in `ARM7_BURN_DOWN`, with an owner and a reason each.**
A named list and never a pattern (#424, ADR-0184 dec. 4): an exclusion expressed as a
filter manufactures its own debt and cannot tell a triaged site from one that merely
matches. Both directions fail — an unlisted reach, and a listed reach that no longer
happens. The stale arm is scoped to the walk: `--root` NARROWS the subject, so a row naming
a file outside the narrowed root is **out of scope, not stale**. The register is
**empty** as of #809 and deliberately still declared — emptied by a fix rather than
by a deletion, which is the only reading of 0 worth having (dec. 12, ADR-0220's
arm-3 note).

**7. The two rows are not one row wearing two names, and the burn-down says so.**
`JsonAsset` is a 64-line free-function JSON loader with no host state, named by twenty-four
other `src/` files; it is a host-wide move, and its destination is the port (dec. 8).
`AnimationNames` reads `res://assets/sprites/animation_names.json`, so moving the class
carries a host **asset** address under an addon root and lands the row on arm 6 instead;
its answer is ADR-0202's host-injected content root, which the rig already ships as
`SpriteRigContentRoot`. Collapsing them into one owner would schedule the wrong work.

**8. `JsonAsset`'s destination is `addons/exmateria_platform/` — the port, not the kernel —
and pass 9 owns the move.**
The kernel's admission gate refuses the file and names it doing so. ADR-0139 dec. 3 makes
membership the realising of *"a named published schema"* and says *"a file move cannot do
it"*; its Alternatives section uses this very file as the worked counterexample to the sink
veto — *"`JsonAsset` (15 edges from 6 buckets), `PsxNum` (8 from 3) … all have zero outbound
edges and none of them is a payload crossing a boundary"* — so the one property that makes
`JsonAsset` look like a kernel member is the property that sentence was written to
disqualify. Layout refuses it a second time: ADR-0146 dec. 2 fixes the kernel's directory
shape so *"a reviewer checks membership with `ls`"*, and ADR-0169 dec. 1 already turned down
`addons/exmateria_schema/` as the `platform` bucket's address because *"a `platform/`
subdirectory inside the kernel addon makes that check lie about the addon it is checking."*
A `json/` directory there lies the same way, and would be the kernel's first member-shaped
directory realising no schema. **ADR-0217 dec. 16 had already ruled this file by name** —
*"`JsonAsset` is `platform`'s, and the deferral names its owner"* — pricing all three of
ADR-0215's options, refusing vendoring as *"self-refuting"* (the file exists so a
parse-handling fix lands once instead of ×18), and deferring the work to pass 9 under
ADR-0196 dec. 5. `PsxNum` is the shipped precedent and it is in the port, not the kernel:
same profile, moved by ADR-0169 dec. 2 to `addons/exmateria_platform/fixed_point/PsxNum.gd`
and published by ADR-0212 as `ExMateriaPlatform.PsxNum`. Arm 5 does not pick between the two
destinations — its free set is **the kernel and the platform port**, keyed on
`system_of[home] is None`, and this ADR's own Context says the same from the other side: 25
of the 30 rows a widened bucket filter yields *"target `addons/exmateria_platform/`"*, and
*"reaching the port is what a portable addon is allowed to do."* It is ADR-0139's gate that
picks, not arm 5.

**9. The move is a façade publish plus one alias line per namer, in either destination, so
cost was never what separated them.**
`class_name JsonAsset` cannot land under *any* addon root as written:
`tools/check_addon_globals.py` holds `BURN_DOWN` empty for both `exmateria_platform` and
`exmateria_schema`, so a second global in either reds it (ADR-0212 dec. 1 / dec. 6). The
shape is `PsxNum`'s — drop the `class_name`, publish `const JsonAsset = preload(…)` on the
façade, give each namer one `const JsonAsset = ExMateriaPlatform.JsonAsset` line. Identical
work either way, which is what makes ADR-0139 dec. 3 load-bearing here rather than
decorative.

**10. The burn-down note carries the ruling, not just this file.**
`ARM7_BURN_DOWN`'s note is where the next reader meets the destination — it is printed in
the guard's own output — so it names the destination, the owning pass, and the ADRs that
decided each. Same rule ADR-0222 dec. 5 applies to a mount's reason: an annotation a
reader quotes has to survive being quoted.

**11. A seeded control rots through its SUBJECT as well as through its REGISTER, and the two
rot in opposite directions.**
`tools/test_check_addon_install.py` already records the register direction and calls it
*"the sixth guard in this repo to fail that way"*: a control that hardcodes the debt heading
reds the day the last row is paid, i.e. on the addon getting better. Arm 7's shipped-register
control was the seventh. The subject direction is its mirror image and is new — two arm-7
seeds *borrowed* `JsonAsset` as their symbol because it was a live host `class_name`, and
the move put it under an addon root, which is precisely what this arm's CONTROL asserts
stays green. The seed silently became its own control and the test reddened while the arm
was working. **A seed constructs its register row and DERIVES its subject at run time, under
the predicate the arm turns on.** Here that is two predicates: declared under `src/`
(outside every addon root — arm 7's question) *and* `_sg.classify(rel) not in _sg.SYSTEMS`,
because a `class_name` whose file classifies into one of the eleven is arm 1's row as well,
and a seed that fires two arms cannot say which one it tested. `JsonAsset` satisfied the
second predicate by being `infrastructure`, which is the only reason the hardcoded seed ever
printed one arm's line; the first host `class_name` under `src/` alphabetically is
`CatalogueReplay`, which is `Character Catalogue`'s and fires both — measured, not supposed.

**12. Every shipped-register control in this family discriminates on the register instead of
asserting a heading.**
rc 0 means nothing unlisted and nothing stale, so on a green tree the burned set *is* the
list: a non-empty register must print its heading and its trailer, an empty one must print
neither, and both directions are asserted. This holds for arm 6's twin as well, whose
register still carries rows and has therefore not expired yet — which is when the shape is
worth fixing, rather than after the eighth failure.

**13. A façade constant's doc block cannot narrate provenance by path.**
`tools/check_addon_globals.py` reads any `src/….gd` path inside a published constant's doc
block as a CITATION of a host use (ADR-0210 dec. 1) and fails when it does not resolve, so a
sentence naming the file's former host address is unsayable in the place a reader would most
expect it. This is not a defect in that guard — its predicate is a path shape, and a
provenance note and a citation are the same shape. The doc blocks name the former directory
without the filename; the exact former path lives in this ADR.

## Prediction

1. Decision 3's diff is byte-identical on both instruments, over all seven addon roots.
2. Arm 7 reads exactly 5 rows / 6 lines, all `exmateria_sprite_rig`, all on the burn-down,
   and `check_addon_portability` stays rc 0.
3. Goal #5 continues to print `met` for `Sprite Rig` — because goal #5 asks the **budget**
   question, and decision 4 deliberately does not change what goal #5 asks. The `met` is
   now qualified by a printed burn-down instead of by silence.
4. The control seed — the same scratch addon naming `ExMateriaSchema` instead of
   `JsonAsset` — is green. If it is not, the arm measures the seeding.

## Consequences

* **Goal #5's `met` and arm 7's burn-down are now two readings that can disagree, and they
  should.** Goal #5 is scored against `docs/GOALS.tsv` and a threshold on it would make the
  register worth gaming (`score_goals.py`'s own contract). Arm 7 is the boundary reading
  beside it. Say them separately, never one as the other (ADR-0202 dec. 1).
* **`check_addon_portability`'s green sentence grows a seventh clause**, and it has to name
  what it does not claim: while any burn-down carries a row, an unqualified *"names no
  `class_name` declared outside every addon root"* would be false, so the sentence ends
  *"beyond the burn-downs above"* and the per-arm trailer prints only when that arm has
  rows (dec. 12).
* **The eighth measured row stays unreported and that is deliberate.**
  `outbound_reaches` scores `preload`/`load`/`get_node("/root/…")` against the RAW line, so
  it reads prose. Arm 6 owns the path axis with `strip_gdscript_comments`, which is the
  right stripper. Fixing `outbound_reaches`' stripper is not available inside decision 3's
  gate — `strip_noncode` blanks string literals, so the naive fix reports **zero**
  `preload` reaches — and it is not needed while arm 6 owns the axis.

* **Whether the four sprite-rig sites should reach a shared loader at all is not decided
  here.** Decision 8 rules where the host-wide symbol lives; it does not price a rig-local
  reader, and neither did ADR-0217 dec. 16, which refused *vendoring* for the host-wide
  symbol. The extracted precedent points the other way and no ADR has scored it:
  `exmateria_battlefield` names `JsonAsset` **zero** times and hand-inlines the open/parse
  dance at three production sites (`doodad/DoodadLibrary.gd:168`,
  `overlay/TileOverlayConfig.gd:191`, `assembly/MapComposer.gd:796`) plus two in its own
  tests, and `exmateria_sprite_rig` already inlines it once itself at
  `layers/SpriteLayerManager.gd:623`. That is evidence about the drift ADR-0217 dec. 16
  cites, in both directions, and it belongs to whoever prices the rig-local option.

## Alternatives considered

* **Move `JsonAsset` into `addons/exmateria_schema/`** — *(named by decision 7 as first
  written, reversed 2026-09-03: the kernel's admission gate refuses the file and uses it
  as its own counterexample, and the shipped precedent `PsxNum` is in the port — dec. 8).*
* **Vendor `JsonAsset` into each addon that names it** — refused by ADR-0217 dec. 16 as
  *"self-refuting"*: the file exists so a parse-handling fix lands once instead of ×18.
* **Widen `SYSTEMS` to every bucket.** Measured: 30 rows, 25 into the port. Rejected above.
* **Replace `dst` with `dst_path` rather than adding a field.** Silently breaks the two
  budget readings, which is decision 3's exact failure mode.
* **Fold arm 7 into arm 5 by adding `src/` to `class_name_homes`.** Arm 5's free/bad
  split is keyed on `system_of[home]`, a dict with one entry per ADDON ROOT; `src/` has no
  entry, and the only verdict available for it is `None` — which is arm 5's FREE branch,
  *"the kernel and the platform port"*. The fold reports nothing. That split is the arm.
* **Report arm 7 rather than enforce it.** A channel that scores nothing is where debt goes
  to hide (ADR-0222). Five rows is a burn-down, not a channel.
* **Name all eight measured rows in `ARM7_BURN_DOWN`.** Bills one defect to two registers:
  severing `Tune` would leave a live row in arm 2's DEBT and a stale row here, and naming a
  `#` comment as debt is the guard reading its own prose (ADR-0208 dec. 7's shape).

## Built (2026-09-03)

`tools/score_goals.py`, `tools/check_addon_portability.py`,
`tools/seed_platform_outbound.py`, `tools/test_check_addon_portability.py`,
`tests/run_all_tests.sh`. The five rows are owned by **#809**.

All four Predictions held.

* **Decision 3's gate passed.** `score_goals.py` (79 lines) and
  `check_addon_portability.py` (97 lines) are **byte-identical** before and after
  decision 2, over all seven addon roots. The probe `seed_platform_outbound.py` is
  unmoved too — including its one pre-existing `FAIL`, verified against the unpatched
  tree so the reading is the probe's and not this change's.
* **Arm 7 reads 5 rows / 6 lines**, all `exmateria_sprite_rig`, all on the burn-down,
  `check_addon_portability` rc **0**.
* Guard suite **160 → 168**: eight arm-7 tests, each with its control, and the
  `--root` scope test that the stale arm is not measuring a narrowed subject. The
  NAMED-row test **constructs both the site and the register row**, so it cannot
  expire the day the shipped rows are paid.

Two things the build found that the design did not say:

1. **The green sentence is machine-recounted and the banner is its second copy.**
   `test_the_spelled_arm_count_equals_the_enumerated_arms` reads the tool's own
   enumeration *and* `tests/run_all_tests.sh`, and it caught the banner's `echo` —
   thirty lines below the section header it had already been fixed in — still spelling
   `EIGHT`. That is the exact drift the test's own docstring predicts.
2. **Two shipped assertions were written against the old sentence, and only one of
   them was a wording change.** `Arm6ResPathTests` asserted `beyond the burn-down
   above`, now plural because there are three; that is wording. But
   `test_the_green_sentence_carries_arm_1_unqualified` forbade the bare substring
   `NOT part of that sentence`, which arm 7 legitimately prints about its own
   burn-down — unscoped, that test asserts **no other arm may ever carry a
   burn-down**, a claim it was never written to make. It is now scoped to arm 1's own
   caveat.

### #809 — decisions 8–13 built (2026-09-04)

`src/data/JsonAsset.gd` → `addons/exmateria_platform/json/JsonAsset.gd`, `class_name`
dropped, published as `ExMateriaPlatform.JsonAsset` (platform façade 3 → 4 constants). 32
files take one alias line: **23 in `src/`, 4 in `tests/`, 5 inside `exmateria_sprite_rig`**,
four of them the rows this ADR named. Two host files also carried
`const _JSON_ASSET := preload("res://src/data/JsonAsset.gd")`
(`src/audio/AttackSfxResolver.gd`, `src/audio/SfxCatalog.gd`); a host may alias a published
constant and may **not** `preload` an addon path (ADR-0211 dec. 4), so both are deleted
rather than repointed.

`src/data/AnimationNames.gd` → `addons/exmateria_sprite_rig/sequence/AnimationNames.gd`,
internal to the addon and published as `ExMateriaSpriteRig.AnimationNames` (rig façade
20 → 21). The asset address decision 7 warned about goes through the mechanism that already
shipped: `SpriteRigContentRoot.ANIMATION_NAMES_SUBPATH`, its eleventh subpath, resolved
against the host-declared content root. `assets/sprites/animation_names.json` does not move,
so arm 6 is never reached. One host alias survives, in `src/debug/UnitAnimationViewerPanel.gd`.
`tools/classify_blueprint.py`'s two override rows for these files are retired — an addon
root classifies them now.

`ARM7_BURN_DOWN` goes **5 rows / 6 lines → 0**, empty and deliberately still declared.
`check_addon_portability` rc 0 with the trailer gone; the rig's remaining burn-down rows are
arm 6's three, which are Audio's #726 and not this addon's. **Goal #5 for `Sprite Rig` is
now at 0 on both instruments that can see it** — arm 7 and arm 1 — which pass 9 scores, not
this receipt. Green beside it: `check_addon_globals` rc 0 (the global surface is still 5
names), `check_addon_install` rc 0 (axis B 0), `check_lattice_scene` rc 0 (criterion 4 0),
`check_residue` rc 0 at 33 unclaimed; `check_adr_shape`, `check_adr_anchors`,
`check_adr_quotes`, `check_adr_classification` and `check_context_index` green over the
fold itself. `tools/test_check_addon_portability.py` **69 OK** —
decisions 11 and 12 changed three tests and added none, because the defect was never a
missing arm.

🔴 **Decision 13 was found by the guard and decision 11 by the suite; neither was found by
reading.** Decision 9 rehearsed this move on paper as identical work either way, and both of
these sat inside that identical work. What it priced was the alias lines. What it could not
price was every instrument that had quietly taken `src/data/JsonAsset.gd` as a fixed point.

Verified 2026-09-04 — dec. 1–13 built; two dated amendments folded into decs. 7–13, 34
citations retargeted in the same commit; 416 lines → 332 including this receipt.
