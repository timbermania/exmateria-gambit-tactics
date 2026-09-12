# The baseline is taken, and the series opens at 190,408 lines and 1,143 reaches

Prologue pass 5. The reading is published against a **stated code commit and a
stated classifier revision**, into `docs/BASELINE.tsv`, and **frozen** — the
freeze is a checksum, not a sentence. Two counts per system, kept apart. Residue
is attributed rather than counted, and nothing is deleted.

Status: accepted (2026-08-21). Discharges
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 1/2/7 and its fifth amendment, and
[ADR-0114](0114-refactor-progress-is-two-per-cluster-numbers.md) dec. 7's
inventory slot. Builds `refactor-loop.md` → *What has to be built* item 2
(residue attribution). Unblocks prologue pass 6
([ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)) and,
after it, extraction #1
([ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md)).
Mechanized by `tools/check_baseline.py` and `tools/check_residue.py`.

## Context

`refactor-loop.md` gates every extraction on this pass: *"No extraction begins
before the blueprint baseline exists, or the first system's movement is
unmeasurable."* Everything the baseline needs was settled by prologue pass 4
([ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)),
so this pass measures nothing new. It publishes, and it makes the publication
hard to move.

**The thing to be careful about is the publication, not the measurement.**
ADR-0131's opening reading has been restated five times — 354 → 360 → 358 → 316
→ 1,143 — and **not one of those steps was a code change**. Every one was a
classifier rule moving under a number that lived in prose. Its fifth amendment
says why that is dangerous and its dec. 6 says what to do about it: *"a reading
is only meaningful against a stated commit AND a stated classifier revision —
quote both or quote neither."* A sixth silent move is the specific failure this
pass exists to make impossible, and prose cannot make it impossible.

**The gate this pass was waiting on had already lifted.**
`refactor-loop.md` gates pass 5 on [#299](https://github.com/timbermania/fft-monorepo/issues/299)
— both Effect Studio branches landing on trunk, ~34k lines. It is **closed**,
with its own re-measurement recorded on it, and the three branches
(`feature/effect-studio-authoring`, `feature/effect-sound-trigger-honesty`,
`character-catalogue-navigator`) are all ancestors of trunk `de055dc49`.
Checked both ways rather than read off the ticket state, which is not evidence.

## Decision

**1. The opening reading, and it is quoted with both revisions or not at all.**

- **code** — `de055dc49`, trunk `import-godot-game`, 2026-08-21.
- **classifier** — `1b9ba2ba3` (`tools/classify_blueprint.py` + `tools/touch_matrix.py`).

The reading is taken on `refactor/pass-5-blueprint-baseline`, which is two
commits ahead of trunk and changes **no file the walk reads** — `git diff
origin/import-godot-game...HEAD -- src assets project.godot` is empty — so the
code side is trunk's exactly.

| system | files | lines | shader lines | reaches out | reaches in |
|---|---:|---:|---:|---:|---:|
| Battlefield | 49 | 8,247 | 925 | 105 | 131 |
| Battle | 79 | 23,066 | 6,239 | 343 | 201 |
| Character Catalogue | 14 | 2,138 | 0 | 73 | 21 |
| Sprite Rig | 26 | 4,957 | 1,029 | 29 | 118 |
| Effects | 183 | 57,480 | 335 | 110 | 37 |
| UI | 126 | 38,432 | 3,122 | 277 | 4 |
| Audio | 13 | 2,817 | 0 | 8 | 46 |
| Cutscene | 57 | 16,166 | 427 | 128 | 16 |
| Campaign | 7 | 1,123 | 0 | 51 | 10 |
| Render | 15 | 1,163 | 258 | 17 | 27 |
| Debug | 15 | 2,998 | 0 | 2 | 532 |
| **in a system** | **584** | **158,587** | **12,335** | **1,143** | **1,143** |

Not systems, and reported because ADR-0131 dec. 4 excludes at report time and
never at walk time: `assembler` 8,419 · `generated` 19,677 · `content` 1,424 ·
`schema` 1,086 · `platform` 863 · `infrastructure` 313 · `DELETE` 39. Whole
package **635 files / 190,408 lines**; the dec. 3 baseline unit — less
`generated` and `content` — is **169,307 lines in 619 files**.

**Extracted, and reported rather than vanished** (dec. 7), read from the
canonical package and not the host's drifted copy (dec. 8): `exmateria_sound`,
**152 files / 15,961 lines**. The host's copy reads 15,929 — a **32-line** drift,
up from the 24 ADR-0131 measured, which is [#326](https://github.com/timbermania/fft-monorepo/issues/326)
getting worse, not better.

**The reach count is a FLOOR** (dec. 6). It is five static shapes over stripped
source; a duck-typed reach carries no type name and is invisible. Every quotation
of it says so.

**2. The baseline is a file with a checksum, not a paragraph.**
[`docs/BASELINE.tsv`](../BASELINE.tsv) is the published reading; `# data_sha256`
covers every non-comment line and `tools/check_baseline.py` verifies it. Editing
a number without editing the checksum is red; editing both is a deliberate act
that has to survive review. The guard also pins the row set to
`classify_blueprint.SYSTEMS` and `OTHER`, so a bucket cannot be added, dropped or
renamed without someone answering what that does to a frozen baseline — which is
precisely the move that happened five times unremarked.

`--delta` prints baseline → HEAD per system. That is loop pass 9's reading, and
it is **reported, never asserted**: a guard that re-measured and compared would
be red permanently and deleted within a week.

**3. Reaches are attributed to the reaching system, and both directions are
published.** `reaches_out` sums to `reaches_in` because every crossing is one
edge read from both ends; the guard checks it. Out is the count a system's own
extraction can lower; in is the count its callers must be made to stop doing. A
system with one number and not the other is unreadable — `UI` (277 out, **4**
in) and `Debug` (2 out, **532** in) are the same package's two extremes and
neither is legible from a single figure.

**4. `Debug` absorbs 46.5% of every uninterfaced reach in the package, and two
symbols carry 476 of its 532.** `DebugConfig` (241, autoload) and `TuneField`
(204 `class_name` + 31 `preload` = 235). The rest is `BaseDebugPanel` 38,
`GameLogger` 13, `DebugOverlay` 5.

This is **reported and not adjusted for**. It is not instrument error: `TuneField`
is ADR-0068's materialisation home and every tunable in the package reaches it,
which is a real coupling that
[ADR-0113](0113-tunables-invert-at-the-addon-boundary.md) already names and
already says how to fix — tunables invert at the addon boundary. Netting it out
would produce a flattering second instrument measuring a different thing, and
ADR-0131 dec. 1 refuses derived figures for exactly that reason.

**5. The reach count cannot see a reach into an extracted addon, so every
extraction will hand the series a fall it did not earn.** The walk is scoped to
`src/` and `assets/`; `addons/exmateria_sound/` is outside it, so the **22 lines**
that reach into the one already-extracted system (`Effects` 14, `Audio` 8) are
counted nowhere. ADR-0131 dec. 7 anticipated this for **lines** and fixed it —
extracted systems are reported, not vanished — and did not notice that **reaches
have the same hole and no such rule**.

Left as it is, deliberately. ADR-0131 schedules instrument changes into prologue
pass 4, which ADR-0144 closed, and this is the pass whose whole purpose is that
the baseline stops moving. So: the 22 lines are **published beside the count and
never folded into it**, and the instrument extension is owed at **extraction #1's
loop pass 9** — the first reading where it could change a conclusion — as its own
ADR, measured both ways, per dec. 6.

**6. Residue is attributed, and the attribution is a program.**
`tools/residue.py` takes `closure.py`'s unclaimed set and gives each file a
reason; [`docs/RESIDUE.tsv`](../RESIDUE.tsv) is the register, generated and never
hand-edited; `tools/check_residue.py` re-derives it and fails when it is stale.
This is `refactor-loop.md` → *What has to be built* item 2, and it is prologue
work because an extraction unclaims files as a **side effect** — a boot script
left behind when its scene moved into an addon reaches nothing and is reached by
nothing — and there is no other moment in the loop where anyone would look.

Five classes, in order of decreasing claim: `declined` (reachable from a declined
scene — ADR-0135 dec. 11, not deadness), `test`, `tool`, `cluster` (named only
from another unclaimed file), `orphan`.

| class | files | lines |
|---|---:|---:|
| declined | 21 | 4,027 |
| test | 6 | 640 |
| tool | 2 | 56 |
| orphan | **5** | **596** |

**ADR-0144's *"13 files / 1,292 lines that no declared scene reaches"* is eight
files with a claim and five without.** The five: `src/debug/EffectTimelineView.gd`
(237), `src/effects/PSXDitherCurves.gd` (159),
`assets/shaders/bitmap_char_3d.gdshader` (108),
`src/ui3/testing/UICompileTest.gd` (82), `assets/shaders/ui_nearest.gdshader` (10).
The first is named three times and every one of them is a docstring — including
its own sibling `EffectTimelineModel.gd`, which calls it *"thin glue"* and is
itself claimed by a test.

The guard is a **staleness** check, not a threshold. A rising residue count is
not a defect; an unattributed one is.

**Prose is evidence and never a class, and this is the decision that cost the
most to get right.** A first version scored a `.md` mention as a claim, which
looks harmless and inverts the answer, because the documents that name an
unreached file are overwhelmingly the ones naming it *in order to say nothing
reaches it*:

| file | named by | saying |
|---|---|---|
| `UICompileTest.gd` | ADR-0112 | *"dead code is what the root set cannot reach"* — as its example |
| `ui_nearest.gdshader` | ADR-0144 | *"a closure candidate"* |
| `EffectTimelineView.gd`, `PSXDitherCurves.gd` | **this ADR** | the sentence above naming them orphans |

So publishing the register emptied it: writing dec. 6 reclassified its own two
orphans out of `orphan`. Prose is now printed in the report, kept out of
`RESIDUE.tsv` entirely, and decides nothing — which also means a docstring edit
cannot make the guard red, and a register that churns on prose is a register
somebody switches off. Verified both ways: a document naming all five orphans
leaves the guard green; a test `preload`ing one turns it red.

Two adjacent false-claim mechanisms were found the same way and are recorded in
`residue.py`'s docstring. **An instrument is not a consumer** —
`classify_blueprint.py` names two of these shaders in its rules table and
`delete_dead_code.py` names six in a `KEEP_FILES` set, which is a register of
what *not* to delete, so a hit there is the recorded **absence** of a claim.
**A comment is not a reference** — identifier matching runs over
`touch_matrix.strip_noncode`'s output, the same stripper sliced out of that
module rather than copied, because a word-match over raw text scored 672 edges
against a real 358 the last time this repo tried it.

**7. Nothing is deleted, and the baseline is not the moment to reconsider that.**
ADR-0142 dec. 8 stands. The closure's 34 files and its **56.7 MB / 7.4%** of
unreached assets are a **ceiling on deadness** — everything dead plus everything
reached only through a path the walk cannot see, with 117 non-literal `load()`
sites naming where it could be wrong. The register makes each one answerable
later; deleting on it now would be spending the series' opening act on 596 lines.

## Consequences

- **Prologue pass 6 is unblocked**, and `check_baseline.py --delta` is how its
  calibration shot is read. ADR-0139's predicted delta is **zero** for all eleven
  systems, and it is now a claim a command can check rather than a claim about a
  paragraph. Anything non-zero there is instrument error caught before a real
  extraction can be blamed for it.
- **`psx_par.gdshaderinc` (70) and `psx_dither.gdshaderinc` (45) are in this
  baseline as `platform`.** That is ADR-0144's holding position, not an answer;
  the kernel-membership question is still pass 6's and the baseline does not
  prejudge it. If pass 6 books them `schema` the delta reports a pure rebooking
  of 115 lines, which is what a rebooking should look like.
- **Extraction #1 owes an instrument ADR** — dec. 5's blind spot, measured both
  ways at that extraction's loop pass 9, before its number is published.
- **Guards are 26** (24 + `check_baseline.py` + `check_residue.py`).
  `check_compositor_routing.py` is red and was red at trunk: it names
  `effect_native_add.gdshader` and `effect_native_sub.gdshader`, and this branch
  touches no `.gd`, `.tscn` or shader file at all.
- **`Render` is confirmed as extraction #1 by the new unit.** 1,163 lines, 17
  outbound reaches of which only **8** land on a system that is not `Debug`, and
  27 inbound. ADR-0141 chose it on the file-edge unit; the line unit does not
  disturb the choice.
- **`godot-learning/CLAUDE.md` → *Test scenes* is wrong three ways now** — it
  names `CombatUITest` and `ProgressionTester`, which are `declined` in
  `ROOT_SET.tsv`, `declined-only` in the closure, and `declined` in
  `RESIDUE.tsv`. Still left: fixing it collides with PR #233.
- **[#326](https://github.com/timbermania/fft-monorepo/issues/326) is quantified
  by this reading** — the host's copy of the extracted system is 32 lines behind
  the canonical package, and dec. 8 exists because reading the wrong one feeds
  copy drift into a longitudinal series.

## Considered alternatives

- **Publish the reading into `BLUEPRINT.md` as prose.** Rejected, and this is the
  central decision of the pass. Prose is where the previous five readings lived
  and it is why they moved without anyone noticing. A checksum makes *frozen* a
  fact about the file rather than an intention about the reader. `BLUEPRINT.md`
  gets a pointer.

- **Report reaches as one number per system instead of two.** Rejected: `UI` at
  277/4 and `Debug` at 2/532 collapse to figures that say nothing about what
  either system would have to do, and the direction is the actionable half.

- **Net `DebugConfig` and `TuneField` out of the reach count.** Rejected. It
  would remove 41.6% of the total and make the opening number flattering, which
  ADR-0131's Consequences explicitly refuse: *"a series that opens on a
  flattering number has nowhere honest to go."* It is also a real coupling with a
  real fix already decided (ADR-0113).

- **Extend the walk to the extracted addon now, so dec. 5's hole never opens.**
  Rejected on ADR-0131's own rule. The hole costs nothing until extraction #1 and
  the freeze is worth more than the 22 lines; a sixth instrument change landing
  in the baseline pass would be the exact failure the freeze exists to prevent.

- **Delete the five orphans while the evidence is in hand.** Rejected: `UNREACHED`
  is a ceiling and 596 lines is not worth the precedent of deleting on it.
  Attribution is the deliverable; deletion is a separate decision with its own
  evidence.

- **Keep `doc` as a weak class rather than demoting it to evidence.** Rejected on
  the table in dec. 6: it does not measure a weak claim, it measures the deadness
  literature, and it made the register unstable under its own publication.

- **Make `RESIDUE.tsv` hand-maintained, with a human verdict column.** Rejected:
  a hand-maintained register that nobody reads back is exactly the shape ADR-0140
  dec. 1 failed in — *"keep every entry matching an actual file, or the shadow
  returns"* was a comment, so the shadow returned, and 14 of 41 fragments could
  never fire. Generated plus a staleness guard is the shape that survives.
