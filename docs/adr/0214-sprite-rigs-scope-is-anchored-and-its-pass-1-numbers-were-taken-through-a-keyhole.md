# `Sprite Rig`'s scope is anchored, and its pass-1 numbers were taken through a keyhole

Loop **pass 2** of extraction #4 — *scope the system and establish its vault
anchors*. Status: **accepted (2026-08-31)**.

The loop's row 2 asks for three things — anchors, scope, and the closure from the
root set — and a fourth is owed here by
[ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
dec. 10. All four land: **40 vault anchors** across 14 files
(`docs/EXTRACTION-4-VAULT-ANCHORS.md`); a **path-reference register**
(`docs/EXTRACTION-4-PATH-REFERENCES.md` + `.tsv`), discharging ADR-0213 soft spot
S3; the **closure from the declared root set** (dec. 11, registered in the same
document); and the **ADR-0126 check 2 audit** of `BLUEPRINT.md`'s claims,
recorded in `BLUEPRINT.md` itself.

**The audit did not confirm pass 1. It corrected five of its published numbers,
including the one in its title.** Every correction has the same cause and it is
not carelessness: `touch_matrix.py`'s `record()` stores every bucket, and its
**printed matrix iterates SYSTEMS only**. ADR-0213 read the printout. Between
41% and 88% of the traffic it was measuring is booked to `assembler`,
`content`, `infrastructure`, `generated`, `platform` or `schema`, and none of it
appears in a SYSTEM × SYSTEM grid.

Code at trunk `571e4e3bd`, classifier at `571e4e3bd`, `touch_matrix.py` cache
regenerated in-session (the on-disk cache was six days stale and disagreed with
the tree — e.g. `CameraRelativeRenderer.gd` cached `DebugConfig` where the file
reaches `PSXDisplay`). ADR-0131's fourth amendment: *"a reading is only
meaningful against a stated commit AND a stated classifier revision."*

⚠️ **Line numbers in ADR-0213 no longer resolve, by exactly the anchor count.**
`UnitDisplay.gd`'s `Unit` reaches were `(30, 103, 362)` and are `(34, 107, 366)`;
`SpriteLayerManager.gd`'s `Tune` reaches were `(86, 759)` and are `(91, 764)`.
The offsets are 4 and 5 — the anchors written into those two files. Nothing
moved; the census grew from **5,343 to 5,383** for the same reason, and any
size comparison against pass 1 must subtract 40.

## Context

Pass 1 ([ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md),
#730, merged `571e4e3bd`) selected `Sprite Rig` **against** ADR-0141 dec. 2 as
literally written, and against two standing recommendations for
`Character Catalogue`. It said so, and it left four soft spots. Its dec. 10
states outright that ADR-0126 check 2 is **not** discharged.

Pass 2 owes both: the anchors, which ADR-0111 dec. 7 calls the one step that
cannot be deferred, and the audit ADR-0126 requires *before* pass 3 designs
anything. ADR-0126's own Consequences predicted where this would land:
*"`Sprite Rig` is the first live test … it carries the same untested 'knows
nothing about combatants' claim that turned out false for `Effects`."*

## Decision

**1. The anchor set is complete and tight, and it was proved from both ends
rather than asserted.** 20 notes, 40 anchors, 14 of 29 files, guard green. The
seed is the vault's `R:` line (ADR-0147's rule: *a note is anchored where its
`R:` points, not where its subject belongs*). Two control arms:

- a **wide** re-scan with the file filter removed returns the same 20 notes and
  the same 40 pairs — nothing was dropped by narrowing;
- **fourteen subject-scoped candidates** — notes plainly about sprites, SEQ, SHP,
  poses or weapon frames whose `R:` points elsewhere — were checked one at a
  time. None cites a `Sprite Rig` file. Their citations name
  `fft-iso-patcher/`, `research/` or a `tools/` extractor, which is the rule
  working, not a gap.

**2. `R: none` is a THIRD trap, and it is the inverse of a citation.** Four
notes write their `R:` as an absence claim that names the file the absence is
*about* — *"R: none — the frame table is read by `SpriteLayerManager.gd` but the
opcode itself is not implemented"*. A basename scan over the whole `R:` line
books that as a live edge. Exactly one pair was reachable only that way
(`[[EVTCHR Script VM]]` → `SpriteLayerManager.gd`); it is **excluded**. The two
traps ADR-0147 recorded (bare basenames; longest-first suffix alternation) both
still bite and are re-recorded with this one.

**3. There is a SECOND seed, and it is not a subset of the first.** The code
cites `research/` documents back. Six lines across four `Sprite Rig` files do so,
and one resolves to a note the `R:` scan never reached —
`[[EVTCHR Frame Resolution]]`, in `SpriteLayerManager.gd`. It is anchored, and it
is the 20th note. The check that this is not a coincidence is
`[[EVTCHR CLUT Resolution]]`: a sibling note, same format, same file, which the
`R:` seed found **independently**. Two seeds, one overlap, one gap covered.

Future passes should run both directions. The first seed answers *"which notes
describe code we have"*; the second answers *"which code says which note
describes it"*, and neither contains the other.

**And the question the handoff deferred here is ruled: a bare `research/` path
citation does NOT satisfy ADR-0126's anchor requirement.** It is a fine *seed* —
it found the 20th note — but it is not an anchor, on ADR-0111 dec. 7's own
grounds. The anchor exists because *a comment travels through any rename, move
or rewrite and a path citation does not*; a `research/` path in a comment is a
path citation, sitting on the wrong side of exactly that argument, and it is the
side the vault already lost 81 of 320 paths on. Nor does anything check it:
`tools/check_vault_anchors.py` resolves `[[Note]]` against `git ls-tree main
vault/` and cannot see a `research/` string at all. So all six such citations
were treated as leads, and every one of them that named a note got a real
`Vault: [[…]]` anchor beside it. **None of the 40 anchors is a `research/`
path.**

**4. ADR-0213's TITLE is falsified. The widest inbound name is not the generated
enum.**

| inbound name | SYSTEM buckets only (ADR-0213's reading) | all buckets |
|---|---:|---:|
| `SpriteLayerManager` | 14 | **56** |
| `DisplayActivity` | 41 | 44 |
| `AnimationStateController` | 26 | 38 |
| **total inbound lines** | **119** | **206** |
| `DisplayActivity`'s share | **34.5%** | **21.4%** |

`SpriteLayerManager` is a 700-line Node with methods that are called. It is an
interface by any definition, and it is now the widest name in the surface by 27%.
`DisplayActivity`'s share falls by a third.

**This weakens dec. 4, which is dec. 1's stated ground for overriding the
inbound gate.** Dec. 4's *argument* is untouched — an enum crossing a seam is a
shared vocabulary, not an interface, and ADR-0141 dec. 2 still has no term for
the difference. What has gone is its *coverage*: it explained the widest name in
the surface, and it no longer does.

The gate outcome does not move. Distinct inbound names are **17** system-only
(19 rows, two of them a `res://` path spelling a class already counted) and **18**
across all buckets (`ResourceHotReload`, named from `assembler`). Seventeen or
eighteen, ADR-0141 dec. 2 fails either way, exactly as dec. 1 said.

**5. 42% of the inbound surface is an ASSEMBLER, and one dev viewer is the widest
caller in the tree.**

| referrer bucket | lines | files | share |
|---|---:|---:|---:|
| `Battle` | 91 | 10 | 44% |
| **`assembler`** | **87** | **7** | **42%** |
| `Cutscene` | 20 | 3 | 10% |
| `UI` | 7 | 1 | 3% |
| `Character Catalogue` | 1 | 1 | <1% |
| **total** | **206** | **22** | |

| widest caller | lines | bucket |
|---|---:|---|
| `src/scenes/SequenceViewer.gd` | **66** | `assembler` |
| `src/units/Unit.gd` | 49 | `Battle` |
| `src/gpu/CombatLoop.gd` | 12 | `Battle` |
| `src/scenarios/ScenarioVM.gd` | 12 | `Cutscene` |

`SequenceViewer.gd` is *"a standalone scene for testing all unit sequences"* — a
developer viewer, 575 lines, 42 of its 66 reaches naming `SpriteLayerManager`.
Dec. 7 reads *"`Unit.gd` is 41% of it"*; against 206 that is **23.8%**, and the
top two files together are 55.8%.

**This replaces dec. 4 as the ground for dec. 1, and it is a better one.** An
assembler reaching across systems is what ADR-0110's model says an assembler is
*for*; a viewer scene that drives a rig directly is the least surprising inbound
traffic a renderer can have, and it is the traffic least likely to survive as a
seam obligation. **Forty-two percent of what looked like coupling is wiring
between a system and the scenes that exercise it.** Dec. 1 stands, on this.

**6. The outbound is 49 lines across 15 files, not six in one, and dec. 3's
"there is nothing else" names the very autoload it omits.**

| → bucket | lines | files | names |
|---|---:|---:|---|
| `Debug` | 21 | 5 | `DebugConfig` 17, `GameLogger` 4 |
| `platform` | 6 | 4 | `Tune` 2, **`PSXDisplay` 2**, `psx_par.gdshaderinc` 2 |
| `content` | 6 | 3 | `WeaponZeroFrames` 3, `JobDatabase` 2, `WeaponGraphicData` 1 |
| `Battle` | 6 | 1 | `Unit` 3, `ReactionType` 3 |
| `schema` | 5 | 3 | `ExMateriaSchema` 2, two `.gdshaderinc` includes 3 |
| `infrastructure` | 4 | 4 | `JsonAsset` 4 |
| `generated` | 1 | 1 | `AbilityDatabase` 1 |
| **total** | **49** | **15** | |

Dec. 3's **six** is ADR-0141 dec. 2's defined metric — cross-SYSTEM reaches after
excluding `platform`, `schema` and `Debug` — and as that metric it is correct.
What is false is the sentence beside it: *"That is the complete list. There is no
`PSXDisplay`-style exclusion to argue about, because there is nothing else."*
There is: 43 further lines, of which two are **literally `PSXDisplay`**
(`src/animation/CameraRelativeRenderer.gd:36,44`). The file is unchanged since
`127f4112e`, so this is an omission at pass 1, not drift.

Likewise *"one file holds the entire outbound severance problem"* and *"nothing
else in the system names a class in another system at all"*: fifteen files carry
outbound reaches, and `AnimationResolutionMap.gd`'s call into `AbilityDatabase`
is a class in another bucket that dec. 3 could not see.

**7. The shipping debt is 25 lines across 6 files, not 23 across 5.** Dec. 5's
table omits `PSXDisplay`. `tools/autoload_reach.py "Sprite Rig"` — the instrument
built for exactly this at extraction #3 pass 2 — reads *"REACHED: 25 lines in 6
files"* and lists `DebugConfig` 17/5, `GameLogger` 4/2, `PSXDisplay` 2/1,
`Tune` 2/1. Dec. 5's comparison against `Battlefield`'s 120 across 13 survives
the correction intact; the row is added so the guard and the ADR agree.

**8. S3 is discharged, and dec. 6's single ratio hid two answers that point in
opposite directions.** Measured with `tools/path_refs.py` — the real tool — on
both systems:

| | `Battlefield` (#3 pass 2) | `Sprite Rig` | ratio |
|---|---:|---:|---:|
| inbound | 259 | **23** | **11.3×** |
| outbound | 33 | **22** | **1.5×** |
| inbound per 100 lines | 3.14 | 0.43 | 7.3× |
| outbound per 100 lines | 0.40 | **0.41** | **0.98× — a wash** |
| inbound excluding `tests/` | 29 | 12 | **2.4×** |

**Two of those cells compare unlike denominators, and the correction is this
pass's own S3 one level down.** `path_refs.py` counts a reference INTO a system,
and a system's own `.tscn` scenes are outside `classify_blueprint.walk()` — they
enter only through `--scene`, which the tool hardcodes for `Battlefield`
(`DEFAULT_SCENES`, two names) and cannot supply for `Sprite Rig`, **which owns no
scene at all**. So 120 of `Battlefield`'s 259 inbound rows — and 12 of its 29
production rows — target one of those two scenes, and `Sprite Rig` has no such
row to have. Like for like, counting only script, shader and resource targets:

| | `Battlefield` | `Sprite Rig` | ratio |
|---|---:|---:|---:|
| inbound, non-scene targets | 139 | 23 | **6.0×** |
| inbound excl. `tests/`, non-scene targets | 17 | 12 | **1.4×** |

Both readings are true and they are answers to different questions. The raw row
is *"how many references does a move have to re-point"* — and a scene is a real
file with a real path, so 11.3× is the honest re-pointing cost. The non-scene row
is *"how coupled is the code"*, and there the production gap is **1.4×, not
2.4×** — nearly a wash, the same shape the outbound row already showed. Owning
no scene is a genuine property of `Sprite Rig`, not a tool artifact; but reading
2.4× as *coupling* credits it for a scene it never had.

The inbound advantage is real and **larger** than dec. 6's 7.7×. The outbound
advantage is **not there**: per line, `Sprite Rig` emits marginally *more*
outbound path references than `Battlefield` did. Dec. 6 averaged the two and
reported the flattering half.

The direction it hid is the one that matters for a move. **Inbound references are
other people's files to re-point; outbound references are this system's own
claims about where the world is** — they travel with the code and break silently
in the new location. **17 of the 22 point at `assets/`**, hard-coded across
nine files, `SpriteLayerManager.gd` holding seven including an absolute sprite
sheet (`assets/sprites/02.png:275`). `tools/path_refs.py` prints `(none)` for
dec. 2's residue and that zero is not the same as no coupling.

**9. ADR-0126 check 2 is discharged, and four `BLUEPRINT.md` claims are false.**
Recorded *in* `BLUEPRINT.md` per check 2's own rule — *"record it rather than
quietly rewriting, the `BLUEPRINT-AUDIT.md` precedent, so nobody cites it while
the fix is pending"*.

| claim | verdict | evidence |
|---|---|---|
| §4 *"It does not know what a combatant is"* | **FALSE** | `UnitDisplay.gd` declares `var _unit: Unit`; reaches `Unit` (34, 107, 366) and `ReactionType` (663, 690, 736) |
| §4 *"never asks about … abilities"* | **FALSE** | `AnimationResolutionMap.gd:377` → `AbilityDatabase.get_ability_view` |
| §4 *"never asks about health"* | **FALSE** | `DisplayActivity.Activity.IDLE_LOW_HEALTH`, resolved in `AnimationResolutionMap` (126, 144-145, 209), forced by `AnimationStateController.to_critical_idle` (203, 215) |
| §4 *"never asks about … turns"* | **HOLDS** | zero hits across 29 files |
| §2 *"`Battle` depends on the schema and never on the renderer"* | **FALSE** | `Battle` → `Sprite Rig`, 91 lines / 10 files, plus `assets/scenes/Unit.tscn` naming four of its files by `ext_resource` |
| §6 *"no tactics RPG in it anywhere"* | **FALSE** | the above, plus `JobDatabase`, `WeaponZeroFrames`, `WeaponGraphicData` |
| §6 *"almost no content shadow"* | **FALSE** | 17 of 22 outbound path references are `assets/` |
| ADR-0189 amendment, *"no file outside it names a unit shader path"* | **OVERSTATED** | its guard enforces *no `.gd`* and does so correctly; three `.tscn`/`.tres` bindings and five `tools/*.py` name the variants |

**The abilities reach is the one to learn from.** `AbilityDatabase` is booked
`generated`. `touch_matrix.py` stores that edge and has stored it all along; the
SYSTEM × SYSTEM printout cannot show it. **The claim that `Sprite Rig` never asks
about abilities survived a full pass-1 measurement because the instrument's
output shape, not its data, could not represent the counterexample.** That is
ADR-0148's failure mode with a different subject, and it is why check 2 is
mandatory rather than advisory.

The honest restatement of §4's thesis is narrower and still worth having: **it
does not know what a combatant is *doing*. It knows what one *is*.** That is a
pass-3 seam question, not a wording edit, so the blueprint sentence stands
annotated rather than rewritten.

**10. Dec. 1 stands. `Sprite Rig` remains extraction #4.** Its outbound after
dec. 2's exclusions is genuinely six lines in one file; its shipping debt is a
fifth of #3's; its inbound path-reference cost is an order of magnitude below
#3's; and 42% of its inbound class traffic is assembler wiring. Nothing found
here argues for stopping.

What has changed is **which sentence carries the override**. It is no longer
*"the widest inbound name is a generated enum"* — that is false. It is *"the
inbound surface is smaller than a SYSTEM-only reading makes it look in kind, and
larger in size: 206 lines of which 87 are assembler wiring and 44 a vocabulary
enum, leaving 78 lines of genuine cross-system call traffic across 12 files."*

**11. The closure is ELEVEN live roots reaching ALL of the system, and one file
no declared root reaches.** Pass 2's third deliverable (`refactor-loop.md` row 2)
is the closure from the declared root set, and it had not been taken. Run over
`docs/ROOT_SET.tsv`'s 13 `root` rows with `closure.py`:

* **11 of 13 reach `Sprite Rig`; two reach ZERO of it** —
  `assets/scenes/OpeningScene.tscn` and `assets/scenes/WorldMap.tscn`. Neither
  draws a unit, and that is a fact about the seam: the world map and the opening
  are already on the far side of it.
* **All eleven reach all 28.** Not a subset each — the *same* 28 files, every
  time. `Battlefield`'s closure at extraction #3 was partial and per-root;
  this one is **total**, which means no root can be used to scope a smaller
  move, and any test that boots any of the eleven loads the whole system.
* **`src/animation/ResourceHotReload.gd` (47 lines) is reached by no declared
  root.** Its only path in is `assets/scenes/UnitAnimationViewerScene.tscn` →
  `src/scenes/UnitAnimationViewerScene.gd` → `ResourceHotReload.gd`, and that
  scene is `declined` in `ROOT_SET.tsv` (ADR-0135 dec. 6). This is the 29th
  file — scope 29, closure 28 — and it is **pass 5's deletion question**,
  exactly the shape `Battlefield` had. UNREACHED is a ceiling on deadness, not
  a floor (ADR-0112 dec. 1); it is not being called dead here.
* **`src/units/Unit.gd` is the articulation point, with
  `assets/scenes/Unit.tscn` beside it.** Delete both edges from the walk and the
  totality collapses into a spread — the eleven roots stop agreeing:

  | reach without `Unit` | roots |
  |---:|---|
  | 21 | `GPUArena`, `NavigatorMain`, `SequenceViewer` |
  | 16 | `Formation`, `AllTemplatesFormation`, `DetailScreen`, `FormationDetailTransition`, `FormationDev` |
  | 15 | `ScenarioPlayer` |
  | 2 | `EffectViewer` (`DisplayActivity.gd`, `SpritePaletteResolver.gd`) |
  | 1 | `TrapViewer` (`SpritePaletteResolver.gd`) |

  `Unit` is not a gate — 21 of 28 files survive its removal on three roots — but
  it is what makes the closure *total*. Seven files reach the tree only through
  it, and two roots reach essentially nothing without it. A worked path:
  `DetailScreen.tscn` → `DetailSceneBoot.gd` → `Character.gd` →
  `UnitProgression.gd` → `StatCalculator.gd` → `Unit.gd` → `UnitDisplay.gd` —
  five `Battle` and `Character Catalogue` hops before the first `Sprite Rig`
  file, which is what a seam at `Unit` would have to cut.

This is the third independent instrument to land on `Unit` — dec. 4 has it as a
typed reach, dec. 12's second bullet below has `Unit.tscn` as the densest inbound
object, and the closure has it as the articulation point. Registered in
`docs/EXTRACTION-4-PATH-REFERENCES.md`.

**12. Pass 3 owes three things this pass could measure but not settle.**

- **The content shadow.** 17 hard-coded `assets/` addresses in nine files. Do the
  sprite tables and textures move with the addon, stay in the host, or become a
  declared dependency? This is goal #6 and it is the largest single thing a move
  relocates.
- **`assets/scenes/Unit.tscn`.** One scene, booked `Battle`, naming four
  `Sprite Rig` files by `ext_resource`. It is the densest inbound object in the
  tree and it is invisible to `touch_matrix.py`, to `closure.py`'s typed edges,
  and to the census — a `.tscn` is not walked at all.
- **The §4 restatement.** `Unit`, `ReactionType`, `AbilityDatabase`,
  `JobDatabase`, `WeaponZeroFrames`, `WeaponGraphicData`: six names that make the
  blueprint's strongest claim about this system false. The seam either severs
  them or the claim is retired.

## Considered alternatives

**Re-run pass 1's whole selection against all-bucket numbers.** Rejected. The
gate ADR-0141 dec. 2 defines is a SYSTEM-to-SYSTEM reading, and changing the
denominator for one candidate while eight rows of ADR-0213's comparison table
keep the old one produces a table that cannot be read. The corrections above are
scoped to `Sprite Rig`'s own claims; a re-ranking is a change to the method and
belongs in an ADR about the method.

**Rewrite the false `BLUEPRINT.md` sentences.** Rejected by ADR-0126 check 2,
which exists because a quietly-corrected blueprint cannot be audited. Annotated
in place.

**Fill the 15 unanchored files.** Rejected. Coverage is reported, never asserted
(#310), and an anchor authored because a file looked bare — rather than because a
note points at it — is a link that resolves and does not support, which
`check_vault_anchors.py`'s own docstring names as the failure it records rather
than repeats.

**Include the `[[EVTCHR Script VM]]` → `SpriteLayerManager.gd` pair.** Rejected.
Its citation is inside an `R: none`; the note is asserting the reimplementation
does **not** exist. Anchoring it would put a live-edge marker on an absence.

## Consequences

- `docs/EXTRACTION-4-VAULT-ANCHORS.md`, `docs/EXTRACTION-4-PATH-REFERENCES.md`
  and `.tsv` join the extraction-#3 set as the pass-2 register. The `.tsv` is the
  live register and regenerates; the `.md` is the reading and does not.
- `tools/check_vault_anchors.py` reports `Sprite Rig 40` under `WALK_ROOTS`,
  ahead of `Battlefield 31`. Nothing asserts that number and nothing should.
- Five ADR-0213 numbers are corrected in place here and not edited there. A
  reader arriving at 0213 through `INDEX.md` will still read 119, six, 23 and the
  title. **That is the standing risk of correcting an ADR from a successor**, and
  the mitigation is the pointer in 0213's own Soft spots, added in this commit.
- **The closure names `src/animation/ResourceHotReload.gd` as pass 5's deletion
  question** and rules two declared roots (`OpeningScene`, `WorldMap`) outside
  the system entirely. It also puts a floor under `scoped_tests.py`: because the
  closure is total, a change anywhere in `Sprite Rig` is in scope for all eleven
  reaching roots, and a scoped run that selects fewer has selected wrong.
- `BLUEPRINT.md` carries four new audit blocks. §4's is the one ADR-0126's
  Consequences predicted, and it landed the way it predicted.
- ✅ **The suite's preflight runs green.** An earlier draft of this ADR said it
  could not be run and blamed a guard; see Amendment 1, which withdraws that.

## Amendment 1 — #731's mechanism was right, its inheritance claim was not (2026-08-31)

*This amendment was itself corrected before merge. Its first form withdrew the
guard diagnosis wholesale; measurement then showed the guard diagnosis was
correct and only the reasoning around it was wrong. What follows is the measured
version.*

**HOLDS — the mechanism.** `bash tests/run_all_tests.sh --preflight-only` aborted
because `tools/test_check_addon_globals.py`'s ownership predicate read
`not d.is_symlink()`. That predicate does not encode ADR-0212 dec. 11's package
boundary; it encodes the **install method**, and this repo supports two.
`tools/link_worktree_godot_assets.sh` symlinks; `tools/sync_exmateria_sound.sh`
does `rsync -aL`, which lands a real directory. Seeded both forms in one checkout
on one ref:

| install form | `owned` | equals `FACADES` |
|---|---|---|
| symlink | 4 names | ✅ |
| rsync | 6 — `exmateria_sound`, `exmateria_spu` leak in | ❌ |

Three of twenty live worktrees install by rsync, and one of them is the canonical
`~/Repos/fft-monorepo`. The guard therefore failed there, and because it runs in
the **preflight** its failure aborted the run and masked the ~38 guards behind
it — the ADR-0148 shape, and the same early-abort masking pattern as #695/#696.

**WITHDRAWN — "verified inherited."** This ADR justified calling the failure
inherited by reproducing it on clean `origin/main`. That experiment could not
have returned anything else: it re-ran in the **same worktree**, whose addon tree
is gitignored and therefore byte-identical on every ref. A gitignored dependency
cannot vary with the ref. The conclusion happened to be true; the evidence for it
was vacuous. **A red result describes the TREE it ran in**, and reproducing on
another ref in the same checkout is not the same fact as reproducing in another
checkout.

**WITHDRAWN — "the preflight could not be run on this branch or on trunk."**
It can. Fixed here by making ownership a question about the REF rather than the
install: `git ls-files addons/`, which returns the same four names in both forms
and stays independent of `cag.FACADES` (the anti-vacuity property that control
exists for). Proved in both directions — the old predicate fails under a seeded
rsync install, the new test file passes 29/29 under both. The preflight now runs
to completion: **554 lines, every static guard green.**

**And the abort was hiding a second, unrelated defect.** With it cleared the
preflight reached `check_adr_classification: STALE INDEX.md / STALE AUDIT.md`.
`gen_adr_index.py` and `gen_adr_audit.py` walked with `os.walk`'s default
`followlinks=False` and `check_adr_classification.py` scanned with
`pathlib.rglob` — none of which descends a symlinked directory. So all three read
a different corpus per install form and their committed output oscillated on
nothing: ADR-0085 `code` 37↔35, 0136 1↔0, 0003 5↔2, 0008 6↔5, 0140 8↔6,
0152 9↔8. Whichever checkout regenerated last won; the next one to run the
preflight aborted on staleness it did not cause. Routed all three through
`_walk_roots.walk_files()`, which exists for exactly this. The register grew, so
**trunk's committed counts were the undercount.** What that does not fix: a
checkout that never installed the addons still counts less, because following a
link cannot conjure a directory — but that tree is a parse-error cascade for the
game anyway.

Consequence for this ADR's own Consequences: the register above is
**green-by-preflight**, not green-by-inspection.

## Soft spots

**S1. The second seed was found, not designed, and it is not a tool.** Six
`research/` citation lines in four files yielded one note. There is no reason to
think four files is the whole of it — the scan was a `grep` over the system's own
sources for `research/`, and a citation written any other way (a bare note title,
a wiki link, a URL) is invisible to it. The 20-note set is a **floor**, and
`check_vault_anchors.py` is green through a note that has no edge at all
(ADR-0168 dec. 7 is the precedent, and the fix there was a frozen
`VAULT-EDGES.tsv` that this pass has not written).

**S2. "Complete and tight" rests on two control arms that share a matcher.** The
wide arm removes the *file filter*, not the *regex*. A citation spelled in a form
the regex cannot parse is missed by both arms identically, and the agreement
between them would still read as confirmation. The subject-scoped arm is the only
genuinely independent check and it was fourteen notes chosen by me, by eye.

**S3. The `assembler` finding cuts two ways and I have taken the favourable
one.** 87 lines of assembler traffic is wiring an extraction expects — *or* it is
87 lines that will need re-pointing at an addon API that does not exist yet, in
files nobody has budgeted. Dec. 5 reads it the first way because ADR-0110's model
says an assembler reaches across. The measurement does not distinguish them, and
`SequenceViewer.gd`'s 42 reaches into `SpriteLayerManager` are a lot of surface
for a system whose interface is supposed to be a pose request.

**S4. Five corrections to a two-day-old ADR is either good instrumentation or a
sign the pass-1 method is under-specified.** Every one has the same cause — a
SYSTEM-only printout over an all-bucket cache — and that cause is not specific to
`Sprite Rig`. **Every extraction-order number in ADR-0213's comparison table, and
in ADR-0157's and ADR-0141's before it, was read off the same printout.** This
ADR does not re-take them, and it should not be read as evidence that they are
sound. It is evidence that nobody has checked.

**S5. The closure is seven STATIC edges and the `Unit`-free spread is a
simulation.** `closure.py` cannot see a runtime-built path or a duck-typed
reach, so *"eleven roots, all 28"* is a floor on reach and *"one file unreached"*
is a ceiling on deadness — neither is a count. The `Unit`-free table is stronger
still as a claim: it was produced by monkey-patching `out_edges` to drop two
paths, which answers *"what does the static graph do without them"* and not
*"what would boot"*. Pass 5 must not read the 1 and the 2 as deletable sets.
