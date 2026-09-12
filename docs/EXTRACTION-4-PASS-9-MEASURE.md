# Extraction #4 — loop pass 9 (measure + score the ten goals)

`Sprite Rig`, `addons/exmateria_sprite_rig/`. 2026-09-04. Every reading below is
taken over the tree this pass lands in — extraction #4's work with trunk
`d7c8f8b9b` merged in, which is what makes the delta a claim about the tree that
ships rather than about a checkout that has since moved. Trunk gained 28 commits
during the 51-minute suite run and four rows of the table moved with them; the
`Sprite Rig` row did not. The decisions this measurement produced are
[ADR-0228](adr/0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md);
this file is the readings, kept apart so a later pass can re-run them without
re-reading an argument.

`refactor-loop.md`: **pass 9 is the better/worse reading, and it is GLOBAL.**
The failure it exists to catch is local improvements that sum to a worse whole,
which a per-system reading is blind to by construction. Always against the frozen
**baseline**, never the previous commit.

## 1. The global reading — `check_baseline.py --delta`

`docs/BASELINE.tsv` frozen at `de055dc49` (2026-08-21), classifier `1b9ba2ba3`.

| bucket | lines | Δ | out | Δ | in | Δ |
|---|---:|---:|---:|---:|---:|---:|
| Battlefield | 12183 | +3936 | **0** | −105 | 31 | −100 |
| Battle | 24050 | +984 | 192 | −151 | 182 | −19 |
| Character Catalogue | 2141 | +3 | 67 | −6 | 26 | **+5** |
| **Sprite Rig** | **6435** | **+1478** | **0** | **−29** | **33** | **−85** |
| Effects | 58103 | +623 | 87 | −23 | 25 | −12 |
| UI | 41521 | +3089 | 248 | −29 | 4 | +0 |
| Audio | 1926 | −891 | 11 | **+3** | 21 | −25 |
| Cutscene | 17303 | +1137 | 121 | −7 | 22 | **+6** |
| Campaign | 1721 | +598 | 61 | **+10** | 32 | **+22** |
| Render | 506 | −657 | **0** | −17 | 1 | −26 |
| Debug | 3477 | +479 | 5 | **+3** | 415 | −117 |
| **TOTAL** | **169366** | **+10779** | **792** | **−351** | **792** | **−351** |

**Better.** Cross-system reaches are down **1,143 → 792, −31%** against the
baseline, and
**three of the eleven systems now read 0 outbound** — `Render`, `Battlefield`,
`Sprite Rig`, one per extraction. `Sprite Rig`'s own half of it is 29 → 0 out and
118 → 33 in, a 72% fall on the inbound side that no single ticket bought:
ADR-0217's vocabulary move, #744's address, #746's façade and #809's last two
files each took a slice.

**Worse, and named.** Four buckets grew a reach: `Campaign` **+10 out / +22 in**,
`Cutscene` +6 in, `Character Catalogue` +5 in, `Audio` and `Debug` +3 out each. (`Cutscene`'s outbound is +1 rather than the
+0 this pass first measured — trunk's own `#822` landed between the reading and
the merge, which is the reason the table is retaken here rather than quoted.)
`Campaign` is the one worth a sentence — it is also the fastest-growing system
proportionally (1,123 → 1,721 lines, **+53%**), and this extraction owns at least
part of it: `src/debug/StoryTimelineDebugPanel.gd` is a **new 175-line file
booked `Campaign`**, added inside the extraction's own commit range by ADR-0216's
derived story timeline, and it names `RosterTimeline` (`Cutscene`) and
`BaseDebugPanel` (`Debug`) — two cross-system names in a bucket that gained ten
outbound lines.

🔴 **Exact attribution is not available from this instrument.** `BASELINE.tsv`
stores per-bucket totals, not per-PAIR ones, so a delta can be DETECTED but not
SOURCED without re-deriving the whole matrix at `de055dc49`. Pass 9's charter is
to scan for regressions it did not intend, and the honest form of that finding is
*"`Campaign` grew, this extraction touched five `Campaign`-booked files, one of
them new"* — not a number attributed to a cause the register cannot carry.

**Conservation.** systems Δ +10779 + extracted Δ +2222 = +13001; `Audio` Δ −891 +
its package Δ +2222 = +1331. Printed, never asserted — it holds across the MOVE
commit, not across an arbitrary interval (ADR-0145 dec. 1 vs dec. 9).

## 2. The scorecard — `tools/score_goals.py`, `GOALS.tsv OK`, rc 0

| system | met | n/a | open | unscorable | achievable |
|---|---:|---:|---:|---:|---:|
| Render | 7 | 2 | 1 | 0 | 8 |
| Audio (two packages) | 8 | 2 | 8 | 2 | 8 |
| Battlefield | 5 | 1 | 4 | 0 | 9 |
| **Sprite Rig** | **6** | **0** | **4** | **0** | **10** |

`Sprite Rig`, row by row: **#1 met** (the seam was argued over ten ADRs, not
inherited) · **#2 met** (`CONTEXT.md` carries `translation table (\`Sprite Rig\`)`,
17 rows, `docs/context/18-sprite-layers.md`) · **#3 met** (one `declined` row,
`ResourceHotReload.gd`, on a register that could finally LOOK — ADR-0227) ·
**#4 met** (in `WALK_ROOTS`, so all 56 `tools/check_*.py` still enter it) ·
**#5 met** (0 on all four instruments) · **#6 open** · **#7 open** · **#8 open** ·
**#9 met** · **#10 open**.

## 3. The achievable score is TEN, and pass 1 never said so

The loop doc: *"a system's achievable score is usually less than ten, and pass 1
states the number rather than pass 9 discovering it."* `Render`'s is 8 — two
per-domain goals score `n/a`. **`Sprite Rig`'s is 10**, because it has neither
escape:

- **#6** — it OWNS ROM-derived formats: the SPR/SHP/SEQ template triple, the
  `BATTLE.BIN` layer-priority table at `0x80094548`, EVTCHR.BIN's 137 segments.
  Same closure `Audio` and `Battlefield` already had.
- **#10** — it SHIPS a root scene. `docs/ROOT_SET.tsv` books
  `addons/exmateria_sprite_rig/viewer/SequenceViewer.tscn` `set=authoring,
  status=root`, moved inside the addon by ADR-0215 dec. 4. **No previous
  extraction has had this half closed**; `Render`, `Audio` and `Battlefield` all
  read *"the addon has no authoring surface"*.

Nine of the ten are buyable inside an extraction; **#8's register half is
epilogue E1** and blocks `Render`, `Audio` and `Battlefield` identically. So the
buyable score is **9**, and six are bought.

Both facts were available at pass 1 — `ROOT_SET.tsv` carried the `authoring`
booking before extraction #4 opened, and ADR-0213 dec. 4 already knew the system
owns a generated ROM vocabulary. ADR-0213 dec. 10 enumerates what pass 1 does not
decide and the achievable score is on neither list.

## 4. The P-table at pass 9

ADR-0217 dec. 14 restated ten predictions and named an instrument for each. Eight
were scored at #744/#745/#746; **P5 and P8 were explicitly owed to this pass.**

| # | predicted | pass-9 reading | verdict |
|---|---|---|---|
| P1 | 1 global name / 9 constants / 18 members; falsified >24 non-enum | 1 global name, **21** façade constants, 30 non-enum + 1 enum | FALSIFIED (at #746) |
| P2 | inbound **84** lines ±20 | 44 all-buckets; `check_baseline` reads inbound **33** | FALSIFIED low |
| P3a | outbound SYSTEM reaches 27 → 0 | **0** | HOLDS |
| P3b | residual 19 lines, band 17–21 | 23 | FALSIFIED high |
| P3c | 7 `content`+`generated` → 0 | 2 at #745; **0** now — #809 moved `AnimationNames` in and `JsonAsset` to the port | **CLOSED at pass 9** |
| P4 | **0** `res://assets/` addresses in the addon | 0 code | HOLDS |
| **P5** | **goals 6 met / 1 n/a / 3 open** | **6 met / 0 n/a / 4 open** | **FALSIFIED — and the met COUNT was exactly right** |
| P6 | goal #7 scores content 0 and is wrong; true 437, band 350–520 | content **0** ✓; shipped instrument **34** after the repair in §6 (39 before); dec. 11's widened eight-term set read 651/579 at pass 3 | FALSIFIED high (at #745) |
| P7 | ~6,000 lines / ~31 files | **7,054 lines / 36 source files** (`git ls-files`); 6,913 / 35 at #745, +1 file for `AnimationNames.gd` | holds within its tilde |
| **P8** | the largest surprise is content, not code — the 91.7 MB templates crossing | **96,278,494 bytes** (`du -sbL assets/characters/templates`; `du -sb` without `-L` reads the symlink at **78**) | **HOLDS — and the disposition is INJECT, not MOVE** |
| P9 | criterion 4 seeds at exactly 1, the mount | 1 mount + 11 burn-down rows at #744; **0 production, +6 oracle, 2 declared mounts, 0 burn-down** now | FALSIFIED (at #744), CLOSED at pass 9 |

**P5's shape is the finding, not its arithmetic.** It predicted six met and six
are met. It also spent an `n/a` this system does not have — so the prediction was
right about the work and wrong about the CHARTER, and a scorecard read as
`6/10` instead of `6/9-buyable-of-10` manufactures a shortfall out of a scoping
question, which is the exact error the loop doc warns about for `Render`.

**P8's verdict.** The 96 MB is real, it grew 5.0% since pass 3, and the content
did **not** move: ADR-0215 dec. 7 keeps it in the host and ADR-0217 dec. 9 has
the host INJECT it through `SpriteRigContentRoot`'s eleven subpaths under one
root. So the largest thing in this extraction is content the addon never owned,
and the seam that disposes of it is a port, not a move. P8 predicted the surprise
correctly and pass 9 records that the surprise was answered by a different verb
than "extract".

## 5. Goal #7, dispositioned per row — 34 lines, and 12 of them are the rig's

All 34 are `platform`; **content jargon is 0**. `Sprite Rig` is not in
`PLATFORM_EXEMPT` and should not be: `Render`'s exemption is that the PSX look IS
its subject, and this system's subject is an FFT unit sprite, which is content,
and content is never exempt (ADR-0117 dec. 12).

| lines | what they are | whose debt |
|---:|---|---|
| **20** | uses of a `psx_*` name PUBLISHED BY ANOTHER PACKAGE — 6 `#include`s plus `psx_ot_depth`, `psx_par_anchor`, `psx_unit_stretch`, `psx_color_apply` and the `psx_ot_computed_depth` varying, every one declared in `addons/exmateria_schema` or `addons/exmateria_platform` | the PROVIDER's — this addon cannot rename them unilaterally |
| **12** | the rig's OWN identifiers carrying `psx`, all naming ONE thing: the camera yaw the platform port publishes as `PSXDisplay.live_camera_angle`. `CameraRelativeRenderer.gd` ×7, `UnitDisplay.gd` ×3, `AnimationStateController.gd` ×2 | **the rig's**, kind `rename`, and it is **#583**'s work — *"Rename PSXDisplay to DisplayCalibration, and execute ADR-0129 dec. 10's psx_ prefix retirement"*, open. Renaming the consumer ahead of the port would have the addon spell a concept the port still spells `psx` |
| **2** | `const float PSX_FOLD_GAIN = 2.2` and its use in `crystal/crystal_fold.gdshader` | goal **#8**'s subject, not #7's |

## 6. One instrument repaired inside the pass

`score_goals.jargon_hits` stripped `//` from a shader and nothing else, so the
`/* … */` header paragraph every `.gdshader` in this tree opens with read as
CODE. Five of `Sprite Rig`'s 39 lines were prose, two of them sentences saying
the file *"renders PSX-era sprite animations"*. ADR-0149 settled this for a shader when
goal #7 was first mechanised — `RGB555` scores zero for `Render` because it
appears in `foldsurface_resolve.glsl` only in a comment, and stays a goal #8
defect — and the GDScript path had always honoured it through
`touch_matrix.strip_noncode`. The shader path honoured it for `//` only.

`_blank_block_comments` is the repair (ADR-0228 dec. 5), with
`tools/test_score_goals.py` — 11 seeds, every subject fabricated. Measured across
every scored package, **only `Sprite Rig`'s count moved: 39 → 34.** `Battlefield`
111, `Audio` 155, `exmateria_spu` 5 and `Render`'s three exempt lines are
unchanged, because those shaders comment with `//`. No register state flipped and
`GOALS.tsv OK` both before and after.

The blindness is `score_goals`-local: goal #7's line filter is its own
`_cut_comment`, not `touch_matrix.strip_noncode`. That distinction is what made
the repair safe to take here — `strip_noncode` is the reach matrix's, pinned by
`BASELINE.tsv`'s `classifier_rev`, and editing it would have moved every number
in §1 of this very document.

## 7. Filed, not settled

- **`ExMateriaSchema.UnitActivity` is published and almost entirely unread.**
  `.Display` has **4** readers, all four in `src/gpu/ActivityTranslator.gd` and
  all four written by the generator; **`.Logical` has zero readers anywhere**,
  because `Battle` reads `GPUConstants.LOGICAL_ACTIVITY_*` integers rather than
  the enum. The tree still spells the rig's own copy 67 times
  (`DisplayActivity.Activity.`) and the GPU constants 218 times. This is not
  reopened here: dec. 7 made the generated pair alias-free ON PURPOSE. But a
  kernel name with no reader is ADR-0190's rule mirrored — that ADR removed a
  `global uniform` for having no WRITER — and the question is `Battle`'s
  extraction's, not this one's.
- **Pass-7's findings have no owner.** Finding S5 (48 dead vault `R:` citations)
  is recorded in `EXTRACTION-4-PASS-7-REVIEW.md` and belongs to no ticket.
- **`BASELINE.tsv` cannot attribute a delta to a pair** (§1). Recording it here
  because the loop asks pass 9 for regressions it did not intend, and the
  register can only answer half of that question.
