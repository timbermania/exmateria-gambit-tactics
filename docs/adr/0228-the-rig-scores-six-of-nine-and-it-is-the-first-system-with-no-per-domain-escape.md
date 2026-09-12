# The rig scores six of nine, and it is the first system with no per-domain escape

- **Status:** Accepted
- **Date:** 2026-09-04
- **Constrains:** ADR-0117 dec. 12, ADR-0135 dec. 5, ADR-0145 dec. 1, ADR-0148,
  ADR-0149, ADR-0150, ADR-0190, ADR-0213 dec. 10, ADR-0215 dec. 7, ADR-0217
  dec. 9 / dec. 14, ADR-0222 dec. 3, ADR-0227

## Context

Pass 9 closes extraction #4. `refactor-loop.md` gives it two jobs — the global
better/worse reading against the frozen baseline, and the ten goals scored for
the system just extracted — and every reading is in
`docs/EXTRACTION-4-PASS-9-MEASURE.md`. This records only what the readings
decided.

### The global reading is better, and one bucket is worse

Cross-system reaches fall **1,143 → 792, −31%**, and **three of eleven systems
now read 0 outbound** — `Render`, `Battlefield`, `Sprite Rig`, one per
extraction. The rig's own half is 29 → 0 out and 118 → 33 in.

Four buckets moved the wrong way, and `Campaign` is the one that matters:
**+10 outbound, +22 inbound, +598 lines on a 1,123-line base.** This extraction
touched five `Campaign`-booked files inside its own commit range, one of them
**new** — `src/debug/StoryTimelineDebugPanel.gd`, 175 lines from ADR-0216's
derived timeline, naming `RosterTimeline` (`Cutscene`) and `BaseDebugPanel`
(`Debug`). So some part of the regression is ours. **How much is not knowable
from this instrument**: `docs/BASELINE.tsv` is frozen at `de055dc49` and stores
per-bucket totals, not per-PAIR ones, so a delta can be detected and cannot be
sourced without re-deriving the matrix at the baseline commit — which
[ADR-0145](0145-the-baseline-is-taken-and-the-series-opens.md) dec. 1
freezes precisely to stop.

### Four goals are open and they are not four debts

- **#6** — the ROM-format goal. Owed, not written.
- **#7** — 34 jargon lines. Dispositioned row by row in the measure doc: **20**
  USE a `psx_*` name published by `exmateria_schema` or `exmateria_platform`, so
  the rename is the provider's and this addon cannot take it unilaterally; **2**
  are `PSX_FOLD_GAIN`, which is goal #8's subject; the rig's own debt is the
  remaining **12**, all naming one thing — the camera yaw the port already
  publishes as `PSXDisplay.live_camera_angle` — and **#583 is open and is
  exactly that work.**
- **#8** — one `const float PSX_FOLD_GAIN = 2.2` in `crystal/crystal_fold.gdshader`,
  guarded by `tools/check_no_psx_brightness_in_fold.py`. Its register half is
  epilogue **E1** and blocks `Render`, `Audio` and `Battlefield` identically.
- **#10** — owed. And, uniquely, ACHIEVABLE (below).

Four open rows read as four debts on a scorecard and are one owed document, one
other package's rename, one epilogue and one owed root-set entry.

### The achievable score was never stated, and it is ten

The loop doc is explicit: *"a system's achievable score is usually less than ten,
and pass 1 states the number rather than pass 9 discovering it."* `Render`'s is
8 — the two per-domain goals score `n/a`. Extraction #4's pass 1
([ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)) does not name a number.
Its dec. 10 enumerates what pass 1 deliberately leaves open and the achievable
score is on neither that list nor the settled one; the omission is a gap, not a
deferral.

The number is **10**, and both halves were knowable at pass 1:

- **#6 cannot be `n/a`.** The system owns ROM-derived formats — the SPR/SHP/SEQ
  template triple, `BATTLE.BIN`'s layer-priority table at `0x80094548`,
  EVTCHR.BIN's 137 segments. ADR-0213 dec. 4 already knew it owned a generated
  ROM vocabulary.
- **#10 cannot be `n/a`.** `docs/ROOT_SET.tsv` books
  `addons/exmateria_sprite_rig/viewer/SequenceViewer.tscn` as `set=authoring,
  status=root` — a root scene that ADR-0215 dec. 4 moved INSIDE the addon.
  **No previous extraction has had this half closed**: `Render`, `Audio` and
  `Battlefield` all score #10 `n/a` in the words *the addon has no authoring
  surface*.

### P5's count was right and its shape was wrong

ADR-0217 dec. 14 restated ten predictions; dec. 6 owed **P5** and **P8** to this
pass. P5 predicted **6 met / 1 n/a / 3 open** and the measurement is **6 met /
0 n/a / 4 open**. It got the met count exactly right and spent an `n/a` this
system does not have — a claim about the CHARTER, not about the work. That
matters because `6/10` and `6 of 9 buyable, of 10 achievable` are different
verdicts, and only the second is true.

P8 predicted the largest surprise would be content rather than code — the
templates crossing the seam. `du -sbL assets/characters/templates` reads
**96,278,494 bytes** (`du -sb` without `-L` reads the symlink, at 78). It holds,
and the answer to it is not a move: ADR-0215 dec. 7 keeps the content in the host
and ADR-0217 dec. 9 has the host INJECT it through `SpriteRigContentRoot`'s
eleven subpaths.

### An instrument disagreed with its own charter

Goal #7's shader path stripped `//` and nothing else. Every `.gdshader` in this
tree opens with a `/* … */` header paragraph by house style, so those paragraphs
read as CODE. Five of the rig's 39 lines were prose — including two sentences
saying the file *"renders PSX-era sprite animations"*, i.e. the instrument was
scoring its own subject's DESCRIPTION as its subject's vocabulary.
[ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)'s rule
is that a comment is prose, and the GDScript path had always honoured it. This is
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)'s
shape: an instrument whose reading drifts from its own definition and stays
green.

### A published kernel name with no reader

`ExMateriaSchema.UnitActivity.Display` has **4** readers, all four in
`src/gpu/ActivityTranslator.gd` and all four generator-written;
**`.Logical` has zero readers anywhere**, because `Battle` reads
`GPUConstants.LOGICAL_ACTIVITY_*` integers. The tree still spells the rig's own
`DisplayActivity.Activity.` 67 times and the GPU constants 218 times. ADR-0217
dec. 8 publishes both halves ON PURPOSE and this ADR does not reopen it.

## Decision

1. **`Sprite Rig` scores 6 met / 4 open / 0 n/a, and the four open rows are
   recorded as four DIFFERENT kinds of owing, not four debts.** `GOALS.tsv`
   carries the disposition in each row's evidence: #6 owed; #7 20 lines the
   provider's, 2 goal #8's, and 12 this addon's own; #8's register half epilogue
   **E1**; #10 owed. A scorecard that renders four `open` cells identically is the
   reason the evidence column exists.

   **THE COUNT TRAVELLED 6/4 → 5/5 → 6/4 AND THE MEASUREMENT NEVER MOVED, WHICH IS
   THE POINT OF NAMING THE INSTRUMENT.** At pass 9 goal #5 WAS the cross-system
   reach count, all four deliberately-disagreeing readings of it were 0, and the
   row was `met` by the definition in force.
   [ADR-0232](0232-goal-5-is-a-conjunction-and-neither-instrument-may-claim-the-word-alone.md)
   then made goal #5 a conjunction of that BUDGET half and an INSTALL half — could
   the addon come up in a project that did nothing for it — which the rig
   [ADR-0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md)
   built two days later could see and no static instrument in this pass could. The
   row read `open` for one day on the new definition and returned to `met` when
   [#848](https://github.com/timbermania/fft-monorepo/issues/848) was paid
   ([ADR-0234](0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md)).
   The reach half read 0 throughout and still does. What changed was the
   definition, not the reading — the same observation as dec. 3's finding that P5
   was falsified in its SHAPE rather than in its count, one turn earlier. The
   achievable score (10) and the buyable score (9) were unaffected in both
   directions.

   🔴 **#7's twelve were NOT #583's, and this decision said they were.** The
   disposition above read *"12 ours and already ticketed as #583"*, on the argument
   that renaming them ahead of the port would spell a concept the port still spells
   `psx`. ADR-0234 measured the port and it does not: `live_camera_angle` and
   `set_camera_angle` are prefix-free on both the autoload and `DisplayPort`, so
   the `psx` was this addon's own local spelling. The twelve were renamed at #848
   and #7's residue is 22, of which 20 are a PROVIDER's to rename and 2 are goal
   #8's — filed as [#899](https://github.com/timbermania/fft-monorepo/issues/899).
   #583 as scoped clears 2 of the 22, so it does not close this row either.

2. **The achievable score is 10 and the buyable score is 9, and stating it is
   PASS 1's job.** `Sprite Rig` is the first system with no per-domain escape on
   either goal: it owns ROM-derived formats (#6) and ships an authoring root
   (#10, `ROOT_SET.tsv`, ADR-0215 dec. 4). Only #8 is unbuyable inside an
   extraction. **Pass 1 owed this number and did not state it**; ADR-0213 dec. 10
   is amended by reference — a future pass 1 states the achievable score and
   names the per-domain goals it is claiming `n/a` on, with the evidence, before
   any work begins. A pass-9 `n/a` that pass 1 did not predict is a finding
   either way.

3. **P5 is FALSIFIED, and the falsification is in its SHAPE.** 6 met / 1 n/a /
   3 open predicted; 6 met / 0 n/a / 4 open measured. The met count was exactly
   right. Recorded as falsified rather than as a rounding, because the error was
   spending an `n/a` the system cannot have, which is the same error dec. 2
   forbids pass 1 from making silently.

4. **P8 HOLDS, and its disposition is INJECT.** 96,278,494 bytes measured with
   `du -sbL`; the `-L` is load-bearing, since the path is a symlink and `du -sb`
   reads 78. The content does not move (ADR-0215 dec. 7) and the host supplies it
   through one root (ADR-0217 dec. 9), so the biggest thing in the extraction was
   answered by a port rather than by a move. P8's own instrument stands: a
   content number is not a code number and the two are never summed.

5. **Goal #7's shader path blanks `/* … */` regions before scoring.**
   `score_goals._blank_block_comments`, line-count preserving, with the `//` arm
   keeping the existing `(?<!:)` guard so `res://` is not read as a comment.
   `tools/test_score_goals.py`, 11 seeds, all fabricated in a temp tree, plus one
   live control asserting at least one shipped `addons/**/*.gdshader*` still
   contains a block comment — so the branch cannot go inert. **Measured across
   every scored package, only `Sprite Rig` moved: 39 → 34**; `Battlefield` 111,
   `Audio` 155, `exmateria_spu` 5 and `Render`'s exempt lines are unchanged, and
   no register state flipped. The repair is deliberately **local to
   `score_goals`** — goal #7 filters lines with its own `_cut_comment`, not with
   `touch_matrix.strip_noncode`, which is the reach matrix's and is pinned by
   `BASELINE.tsv`'s `classifier_rev`. Editing that instead would have moved every
   number in the same document that reports this.

6. **`UnitActivity.Logical` is published and unread, and the question is
   `Battle`'s, not this extraction's.** Filed here with its counts (4 readers on
   `.Display`, 0 on `.Logical`, 67 `DisplayActivity.Activity.`, 218
   `LOGICAL_ACTIVITY_*`) so `Battle`'s pass 1 inherits a measurement rather than
   an impression. It is
   [ADR-0190](0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md)
   mirrored — that ADR retired a `global uniform` for having no WRITER, and this
   is a kernel name with no READER — but the mirror is a reason to ask the
   question, not to answer it inside the wrong system's extraction.

7. **`Campaign` is named as the one bucket that got worse, and the attribution
   limit is named with it.** +10 out / +22 in / +598 lines; this extraction added
   `src/debug/StoryTimelineDebugPanel.gd` to it, which carries two cross-system
   names. `BASELINE.tsv` stores bucket totals, so pass 9 can DETECT the
   regression and cannot SOURCE it. The honest record is the direction, the
   touched files and the limit — not a number attributed to a cause the register
   cannot carry. Widening the baseline to pairs is not taken here: it would
   unfreeze the one artifact ADR-0145 dec. 1 freezes.

## Consequences

- `docs/GOALS.tsv` gains ten `Sprite Rig` rows; the ratchet reads **`GOALS.tsv OK`
  / `Sprite Rig 6 met, 4 open`**, rc 0, and it fails in both directions, so a
  later row that drifts from the code reds whichever half moved.
- `docs/context/18-sprite-layers.md` gains
  `#### Extraction #4 translation table (\`Sprite Rig\`)`, 17 rows;
  `CONTEXT.md` regenerated (38 clusters, this cluster 20 terms / 581 lines), which
  is what buys goal **#2**.
- `tools/score_goals.py` gains `_blank_block_comments`;
  `tools/test_score_goals.py` is new, 11 tests.
- **Nothing in `addons/exmateria_sprite_rig/` changes in this pass.** Pass 9
  measures; the last line it was entitled to move landed at #809.
- The two axis guards, re-read at pass 9: `check_lattice_scene.py` rc 0 —
  criterion 4 per addon `exmateria_battlefield 0 (+0 oracle, 3 mount),
  exmateria_sprite_rig 0 (+6 oracle, 2 mount)`, the production channel at its
  target with the oracle channel reported beside it and never summed (ADR-0222
  dec. 3); `check_addon_portability.py` rc 0, with the only outstanding
  `ARM6_BURN_DOWN` rows belonging to `exmateria_sound`.
- **P9 closes as FALSIFIED-then-drained**: it predicted criterion 4 would seed at
  exactly 1. It seeded at 1 mount plus 11 burn-down rows at #744 and now reads
  0 production / 6 oracle / 2 declared mounts / 0 burn-down. Every prediction
  ADR-0217 dec. 14 restated is now scored.
- Extraction #4 is closed. Goal #6 and goal #10 are owed by the epilogue
  alongside E1. Goal #7's rig-owned half was paid at #848 (ADR-0234) and its
  residue is the provider-side retirement #899 asks about; goal #5's install half
  was paid the same day.
